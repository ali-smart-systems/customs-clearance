import 'dart:io';

import 'package:customs_clearance_app/core/db/app_database.dart';
import 'package:customs_clearance_app/features/accounting/data/accounting_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late AppDatabase appDatabase;
  late AccountingRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'customs_accounting_test_',
    );
    appDatabase = AppDatabase.forTesting(
      p.join(temporaryDirectory.path, 'accounting.db'),
    );
    await appDatabase.database;
    repository = AccountingRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test('database v5 schema enforces keys and stores no balance', () async {
    final db = await appDatabase.database;
    expect(await db.getVersion(), 5);
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
      "('accounts','journal_entries','journal_lines','accounting_settings')",
    );
    expect(tables.map((row) => row['name']).toSet(), {
      'accounts',
      'journal_entries',
      'journal_lines',
      'accounting_settings',
    });
    final accountColumns = await db.rawQuery('PRAGMA table_info(accounts)');
    expect(
        accountColumns.map((row) => row['name']), isNot(contains('balance')));
    final foreignKeys = await db.rawQuery(
      'PRAGMA foreign_key_list(journal_lines)',
    );
    expect(foreignKeys.map((row) => row['table']).toSet(), {
      'accounts',
      'journal_entries',
    });
    final indexes = await db.rawQuery('PRAGMA index_list(accounts)');
    expect(indexes.any((row) => row['unique'] == 1), isTrue);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('real v4 to v5 upgrade preserves old data and seeds once', () async {
    final upgradeDirectory = Directory.systemTemp.createTempSync(
      'customs_accounting_upgrade_',
    );
    final path = p.join(upgradeDirectory.path, 'upgrade.db');
    final oldDb = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE legacy_marker (value TEXT NOT NULL)');
          await db.insert('legacy_marker', {'value': 'preserved'});
          await db.execute('''
            CREATE TABLE accounts (
              id TEXT PRIMARY KEY,
              code TEXT NOT NULL UNIQUE,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              parent_id TEXT,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.insert('accounts', {
            'id': 'existing_cash',
            'code': '1000',
            'name': 'صندوق موجود',
            'type': 'asset',
            'parent_id': null,
            'is_active': 1,
            'created_at': '2025-01-01T00:00:00.000',
            'updated_at': '2025-01-01T00:00:00.000',
          });
        },
      ),
    );
    await oldDb.close();

    final upgrading = AppDatabase.forTesting(path);
    final upgraded = await upgrading.database;
    expect(await upgraded.getVersion(), 5);
    expect(await upgraded.query('legacy_marker'), [
      {'value': 'preserved'},
    ]);
    expect(
      Sqflite.firstIntValue(
        await upgraded.rawQuery(
          "SELECT COUNT(*) FROM accounts WHERE code = '1000'",
        ),
      ),
      1,
    );
    expect(
      Sqflite.firstIntValue(
        await upgraded.rawQuery(
          "SELECT COUNT(*) FROM accounts "
          "WHERE code IN ('1000','1100','2000','4000','5000')",
        ),
      ),
      5,
    );
    await upgrading.close();

    final reopenedDatabase = AppDatabase.forTesting(path);
    final reopened = await reopenedDatabase.database;
    expect(
      Sqflite.firstIntValue(
        await reopened.rawQuery('SELECT COUNT(*) FROM accounts'),
      ),
      5,
    );
    await reopenedDatabase.close();
    upgradeDirectory.deleteSync(recursive: true);
  });

  test('default accounts and account validation are correct', () async {
    final accounts = await repository.getAccounts();
    expect(
      accounts
          .map((account) => '${account.code}|${account.name}|${account.type}'),
      containsAll(<String>[
        '1000|الصندوق|asset',
        '1100|ذمم التجار|asset',
        '2000|جمارك مستحقة|liability',
        '4000|إيرادات خدمات التخليص|revenue',
        '5000|مصروفات تشغيلية|expense',
      ]),
    );
    await expectLater(
      repository.createAccount(code: '1000', name: 'مكرر', type: 'asset'),
      throwsA(anything),
    );
    await expectLater(
      repository.createAccount(code: ' ', name: 'اسم', type: 'asset'),
      throwsArgumentError,
    );
    await expectLater(
      repository.createAccount(code: '9000', name: ' ', type: 'asset'),
      throwsArgumentError,
    );
  });

  test('account update, inactive posting guard and deletion work', () async {
    await repository.createAccount(code: '9000', name: 'تجريبي', type: 'asset');
    var account = (await repository.getAccounts()).singleWhere(
      (value) => value.code == '9000',
    );
    await repository.updateAccount(
      account: account,
      code: '9000',
      name: 'تجريبي معدل',
      type: 'asset',
      isActive: false,
    );
    account = (await repository.getAccounts()).singleWhere(
      (value) => value.code == '9000',
    );
    expect(account.name, 'تجريبي معدل');
    expect(account.isActive, isFalse);
    await expectLater(
      repository.createJournalEntry(
        entryDate: DateTime(2026, 7, 14),
        description: 'حساب موقوف',
        lines: [
          JournalLineInput(accountId: account.id, debit: 10, credit: 0),
          const JournalLineInput(
            accountId: 'account_service_revenue',
            debit: 0,
            credit: 10,
          ),
        ],
      ),
      throwsArgumentError,
    );
    await repository.deleteAccount(account);
    expect(
      (await repository.getAccounts()).where((value) => value.code == '9000'),
      isEmpty,
    );
  });

  test('journal validation rejects all invalid line contracts', () async {
    Future<void> create(List<JournalLineInput> lines) =>
        repository.createJournalEntry(
          entryDate: DateTime(2026, 7, 14),
          description: 'قيد غير صالح',
          lines: lines,
        );

    final invalid = <List<JournalLineInput>>[
      const [JournalLineInput(accountId: 'account_cash', debit: 1, credit: 0)],
      const [
        JournalLineInput(accountId: 'account_cash', debit: 2, credit: 0),
        JournalLineInput(
          accountId: 'account_service_revenue',
          debit: 0,
          credit: 1,
        ),
      ],
      const [
        JournalLineInput(accountId: 'account_cash', debit: 1, credit: 1),
        JournalLineInput(
          accountId: 'account_service_revenue',
          debit: 0,
          credit: 1,
        ),
      ],
      const [
        JournalLineInput(accountId: 'account_cash', debit: 0, credit: 0),
        JournalLineInput(
          accountId: 'account_service_revenue',
          debit: 0,
          credit: 0,
        ),
      ],
      const [
        JournalLineInput(accountId: 'account_cash', debit: -1, credit: 0),
        JournalLineInput(
          accountId: 'account_service_revenue',
          debit: 0,
          credit: -1,
        ),
      ],
      const [
        JournalLineInput(
          accountId: 'account_cash',
          debit: double.infinity,
          credit: 0,
        ),
        JournalLineInput(
          accountId: 'account_service_revenue',
          debit: 0,
          credit: double.infinity,
        ),
      ],
      const [
        JournalLineInput(
          accountId: 'account_cash',
          debit: double.nan,
          credit: 0,
        ),
        JournalLineInput(
          accountId: 'account_service_revenue',
          debit: 0,
          credit: double.nan,
        ),
      ],
    ];
    for (final lines in invalid) {
      await expectLater(create(lines), throwsArgumentError);
    }
    expect(await repository.getJournalEntries(), isEmpty);
  });

  test('minor floating differences use financial integer units', () async {
    await repository.createJournalEntry(
      entryDate: DateTime(2026, 7, 14),
      description: 'جمع عشري آمن',
      lines: const [
        JournalLineInput(accountId: 'account_cash', debit: 0.1, credit: 0),
        JournalLineInput(accountId: 'account_cash', debit: 0.2, credit: 0),
        JournalLineInput(
          accountId: 'account_service_revenue',
          debit: 0,
          credit: 0.3,
        ),
      ],
    );
    expect(
      (await repository.getJournalEntries()).single.totalDebit,
      closeTo(0.3, 1e-9),
    );
  });

  test('nonexistent account fails before storing a header', () async {
    await expectLater(
      repository.createJournalEntry(
        entryDate: DateTime(2026, 7, 14),
        description: 'حساب غير موجود',
        lines: const [
          JournalLineInput(accountId: 'account_cash', debit: 10, credit: 0),
          JournalLineInput(accountId: 'missing', debit: 0, credit: 10),
        ],
      ),
      throwsArgumentError,
    );
    final db = await appDatabase.database;
    expect(
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM journal_entries'),
      ),
      0,
    );
    expect(
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM journal_lines'),
      ),
      0,
    );
  });

  test('later line failure rolls back header and earlier line', () async {
    final db = await appDatabase.database;
    await db.execute('''
      CREATE TRIGGER fail_credit_line
      BEFORE INSERT ON journal_lines
      WHEN NEW.credit > 0
      BEGIN
        SELECT RAISE(ABORT, 'test failure');
      END
    ''');
    await expectLater(
      repository.createJournalEntry(
        entryDate: DateTime(2026, 7, 14),
        description: 'اختبار rollback',
        lines: const [
          JournalLineInput(accountId: 'account_cash', debit: 10, credit: 0),
          JournalLineInput(
            accountId: 'account_service_revenue',
            debit: 0,
            credit: 10,
          ),
        ],
      ),
      throwsA(anything),
    );
    expect(
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM journal_entries'),
      ),
      0,
    );
    expect(
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM journal_lines'),
      ),
      0,
    );
  });

  test('full accounting cycle, reload, ledger, trial and deletion', () async {
    final firstDate = DateTime(2026, 7, 14, 9);
    await repository.createJournalEntry(
      entryDate: firstDate,
      description: 'اختبار إيراد يدوي',
      lines: const [
        JournalLineInput(
          accountId: 'account_cash',
          debit: 1250,
          credit: 0,
          note: 'قبض تجريبي',
        ),
        JournalLineInput(
          accountId: 'account_service_revenue',
          debit: 0,
          credit: 1250,
        ),
      ],
    );
    await repository.createJournalEntry(
      entryDate: DateTime(2026, 7, 14, 10),
      description: 'اختبار مصروف يدوي',
      lines: const [
        JournalLineInput(
          accountId: 'account_operating_expenses',
          debit: 300,
          credit: 0,
        ),
        JournalLineInput(accountId: 'account_cash', debit: 0, credit: 300),
      ],
    );

    var entries = await repository.getJournalEntries();
    expect(entries, hasLength(2));
    final first = entries.singleWhere(
      (entry) => entry.description == 'اختبار إيراد يدوي',
    );
    final second = entries.singleWhere(
      (entry) => entry.description == 'اختبار مصروف يدوي',
    );
    expect(first.entryDate, firstDate);
    expect(first.lines, hasLength(2));
    expect(first.lines.first.note, 'قبض تجريبي');
    expect(first.totalDebit, 1250);
    expect(first.totalCredit, 1250);

    var cashLedger = await repository.getLedgerRows('account_cash');
    expect(cashLedger.map((row) => row.debit), [1250, 0]);
    expect(cashLedger.map((row) => row.credit), [0, 300]);
    expect(cashLedger.last.balance, 950);
    expect(
      (await repository.getLedgerRows('account_service_revenue')).last.balance,
      -1250,
    );
    expect(
      (await repository.getLedgerRows('account_operating_expenses'))
          .last
          .balance,
      300,
    );

    var trial = await repository.getTrialBalanceRows();
    expect(trial.fold<double>(0, (sum, row) => sum + row.debit), 1550);
    expect(trial.fold<double>(0, (sum, row) => sum + row.credit), 1550);
    expect(
      trial.fold<double>(0, (sum, row) => sum + row.closingDebit),
      1250,
    );
    expect(
      trial.fold<double>(0, (sum, row) => sum + row.closingCredit),
      1250,
    );

    await repository.deleteJournalEntry(second.id);
    entries = await repository.getJournalEntries();
    expect(entries, hasLength(1));
    cashLedger = await repository.getLedgerRows('account_cash');
    expect(cashLedger.single.balance, 1250);
    expect(
      await repository.getLedgerRows('account_operating_expenses'),
      isEmpty,
    );
    trial = await repository.getTrialBalanceRows();
    expect(
      trial.fold<double>(0, (sum, row) => sum + row.closingDebit),
      1250,
    );
    expect(
      trial.fold<double>(0, (sum, row) => sum + row.closingCredit),
      1250,
    );

    final db = await appDatabase.database;
    expect(
      Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM journal_lines WHERE journal_entry_id = ?',
          [second.id],
        ),
      ),
      0,
    );
    expect(
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM accounts'),
      ),
      5,
    );
    await expectLater(
      repository.deleteAccount(
        (await repository.getAccounts()).singleWhere(
          (account) => account.code == '1000',
        ),
      ),
      throwsStateError,
    );

    await repository.deleteJournalEntry(first.id);
    expect(await repository.getJournalEntries(), isEmpty);
    expect(await repository.getLedgerRows('account_cash'), isEmpty);
    expect(await repository.getLedgerRows('account_service_revenue'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect(
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM journal_lines'),
      ),
      0,
    );
  });
}
