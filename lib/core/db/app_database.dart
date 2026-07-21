import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../constants/app_roles.dart';
import '../constants/demo_users.dart';

class AppDatabase {
  AppDatabase._({String? databasePathOverride})
      : _databasePathOverride = databasePathOverride;

  AppDatabase.forTesting(String databasePath)
      : _databasePathOverride = databasePath;

  static final AppDatabase instance = AppDatabase._();

  static const int _databaseVersion = 9;
  static const String _databaseName = 'customs_clearance.db';

  final String? _databasePathOverride;

  Database? _database;
  bool _ffiInitialized = false;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;

    _database = await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    _initDesktopDatabaseFactoryIfNeeded();

    final override = _databasePathOverride;
    final path = override ?? join(await getDatabasesPath(), _databaseName);

    return openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> close() async {
    final existing = _database;
    _database = null;
    await existing?.close();
  }

  void _initDesktopDatabaseFactoryIfNeeded() {
    if (_ffiInitialized) return;

    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiInitialized = true;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.transaction((txn) async {
      await _createUsersTable(txn);
      await _createShipmentRequestsTable(txn);
      await _createCustomsRecordsTable(txn);
      await _createPricingHistoryTable(txn);
      await _createPaymentTransactionsTable(txn);
      await _createAccountingTables(txn);
      await _createAccountContactsTable(txn);
      await _createIndexes(txn);
      await _createAccountingIndexes(txn);
      await _createAccountContactsIndexes(txn);
      await _seedDemoUsers(txn);
      await _seedDefaultAccounts(txn);
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _upgradeToV2(db);
    }

    if (oldVersion < 3) {
      await _upgradeToV3(db);
    }

    if (oldVersion < 4) {
      await _upgradeToV4(db);
    }

    if (oldVersion < 5) {
      await _upgradeToV5(db);
    }

    if (oldVersion < 6) {
      await _upgradeToV6(db);
    }

    if (oldVersion < 7) {
      await _upgradeToV7(db);
    }

    if (oldVersion < 8) {
      await _upgradeToV8(db);
    }
    if (oldVersion < 9) {
      await _upgradeToV9(db);
    }
  }

  Future<void> _createUsersTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        role TEXT NOT NULL CHECK(role IN ('worker', 'manager')),
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createShipmentRequestsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE shipment_requests (
        id TEXT PRIMARY KEY,
        worker_id TEXT NOT NULL,
        agent_name TEXT NOT NULL,
        driver_name TEXT NOT NULL,
        plate_number TEXT NOT NULL,
        quantity REAL NOT NULL CHECK(quantity > 0),
        status TEXT NOT NULL CHECK(status IN ('pending', 'accepted', 'rejected')),
        created_at TEXT NOT NULL,
        reviewed_by TEXT,
        reviewed_at TEXT,
        reject_reason TEXT,
        sync_status TEXT NOT NULL DEFAULT 'local',
        server_id TEXT,
        FOREIGN KEY(worker_id) REFERENCES users(id),
        FOREIGN KEY(reviewed_by) REFERENCES users(id)
      )
    ''');
  }

  Future<void> _createCustomsRecordsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE customs_records (
        id TEXT PRIMARY KEY,
        request_id TEXT NOT NULL,
        parent_record_id TEXT,
        agent_name TEXT NOT NULL,
        driver_name TEXT NOT NULL,
        plate_number TEXT NOT NULL,
        quantity REAL NOT NULL CHECK(quantity > 0),
        customs_amount REAL NOT NULL DEFAULT 0,
        clearance_fee REAL NOT NULL DEFAULT 0,
        driver_advance REAL NOT NULL DEFAULT 0,
        radiology_fee_applied INTEGER NOT NULL DEFAULT 0,
        customs_amount_manual_override INTEGER NOT NULL DEFAULT 0,
        paid_amount REAL NOT NULL DEFAULT 0,
        beneficiary_merchant TEXT,
        pricing_unit TEXT,
        unit_price REAL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        display_order INTEGER NOT NULL DEFAULT 0,
        sync_status TEXT NOT NULL DEFAULT 'local',
        server_id TEXT,
        FOREIGN KEY(request_id) REFERENCES shipment_requests(id),
        FOREIGN KEY(parent_record_id) REFERENCES customs_records(id)
      )
    ''');
  }

  Future<void> _createPricingHistoryTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE pricing_history (
        id TEXT PRIMARY KEY,
        customs_record_id TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        unit_price REAL NOT NULL,
        customs_amount REAL NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(customs_record_id) REFERENCES customs_records(id)
      )
    ''');
  }

  Future<void> _createPaymentTransactionsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_transactions (
        id TEXT PRIMARY KEY,
        customs_record_id TEXT NOT NULL,
        amount REAL NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(customs_record_id) REFERENCES customs_records(id)
      )
    ''');
  }

  Future<void> _createAccountingTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
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

    await db.execute('''
      CREATE TABLE IF NOT EXISTS journal_entries (
        id TEXT PRIMARY KEY,
        entry_date TEXT NOT NULL,
        description TEXT NOT NULL,
        source_type TEXT,
        source_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS journal_lines (
        id TEXT PRIMARY KEY,
        journal_entry_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        debit REAL NOT NULL DEFAULT 0,
        credit REAL NOT NULL DEFAULT 0,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(journal_entry_id) REFERENCES journal_entries(id),
        FOREIGN KEY(account_id) REFERENCES accounts(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounting_settings (
        id TEXT PRIMARY KEY,
        cash_account_id TEXT,
        merchant_receivable_account_id TEXT,
        customs_payable_account_id TEXT,
        service_revenue_account_id TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createAccountContactsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS account_contacts (
        id TEXT PRIMARY KEY,
        account_type TEXT NOT NULL CHECK(account_type IN ('merchant', 'agent')),
        account_name TEXT NOT NULL,
        phone TEXT,
        whatsapp TEXT,
        whatsapp_same_as_phone INTEGER NOT NULL DEFAULT 1,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_shipment_requests_status ON shipment_requests(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_shipment_requests_created_at ON shipment_requests(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customs_records_agent_name ON customs_records(agent_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customs_records_created_at ON customs_records(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customs_records_parent_record_id ON customs_records(parent_record_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customs_records_beneficiary_merchant ON customs_records(beneficiary_merchant)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customs_records_driver_name ON customs_records(driver_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payment_transactions_record_id ON payment_transactions(customs_record_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payment_transactions_created_at ON payment_transactions(created_at)',
    );
  }

  Future<void> _createAccountingIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_accounts_code ON accounts(code)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_journal_entries_entry_date ON journal_entries(entry_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_journal_lines_entry_id ON journal_lines(journal_entry_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_journal_lines_account_id ON journal_lines(account_id)',
    );
  }

  Future<void> _createAccountContactsIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_account_contacts_type_name ON account_contacts(account_type, account_name)',
    );
  }

  Future<void> _seedDemoUsers(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();

    await db.insert('users', {
      'id': DemoUsers.workerId,
      'name': DemoUsers.workerName,
      'role': AppRoles.worker,
      'created_at': now,
    });

    await db.insert('users', {
      'id': DemoUsers.managerId,
      'name': DemoUsers.managerName,
      'role': AppRoles.manager,
      'created_at': now,
    });
  }

  Future<void> _seedDefaultAccounts(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();

    Future<void> insertAccount({
      required String id,
      required String code,
      required String name,
      required String type,
    }) async {
      await db.insert(
        'accounts',
        {
          'id': id,
          'code': code,
          'name': name,
          'type': type,
          'parent_id': null,
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await insertAccount(
      id: 'account_cash',
      code: '1000',
      name: 'الصندوق',
      type: 'asset',
    );
    await insertAccount(
      id: 'account_merchant_receivable',
      code: '1100',
      name: 'ذمم التجار',
      type: 'asset',
    );
    await insertAccount(
      id: 'account_customs_payable',
      code: '2000',
      name: 'جمارك مستحقة',
      type: 'liability',
    );
    await insertAccount(
      id: 'account_service_revenue',
      code: '4000',
      name: 'إيرادات خدمات التخليص',
      type: 'revenue',
    );
    await insertAccount(
      id: 'account_operating_expenses',
      code: '5000',
      name: 'مصروفات تشغيلية',
      type: 'expense',
    );

    await db.insert(
      'accounting_settings',
      {
        'id': 'default',
        'cash_account_id': 'account_cash',
        'merchant_receivable_account_id': 'account_merchant_receivable',
        'customs_payable_account_id': 'account_customs_payable',
        'service_revenue_account_id': 'account_service_revenue',
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _upgradeToV2(Database db) async {
    await db.execute('PRAGMA foreign_keys = OFF');

    await db.transaction((txn) async {
      await txn.execute('DROP INDEX IF EXISTS idx_customs_records_agent_name');
      await txn.execute('DROP INDEX IF EXISTS idx_customs_records_created_at');
      await txn
          .execute('DROP INDEX IF EXISTS idx_customs_records_parent_record_id');

      await txn
          .execute('ALTER TABLE customs_records RENAME TO customs_records_old');

      await _createCustomsRecordsTable(txn);

      await txn.execute('''
        INSERT INTO customs_records (
          id,
          request_id,
          parent_record_id,
          agent_name,
          driver_name,
          plate_number,
          quantity,
          customs_amount,
          paid_amount,
          beneficiary_merchant,
          pricing_unit,
          unit_price,
          created_at,
          updated_at,
          sync_status,
          server_id
        )
        SELECT
          id,
          request_id,
          NULL,
          agent_name,
          driver_name,
          plate_number,
          quantity,
          customs_amount,
          0,
          beneficiary_merchant,
          pricing_unit,
          unit_price,
          created_at,
          updated_at,
          sync_status,
          server_id
        FROM customs_records_old
      ''');

      await txn.execute('DROP TABLE customs_records_old');

      await _createIndexes(txn);
    });

    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _upgradeToV3(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(customs_records)');
    final hasPaidAmount =
        columns.any((column) => column['name'] == 'paid_amount');

    if (!hasPaidAmount) {
      await db.execute(
        'ALTER TABLE customs_records ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0',
      );
    }

    await _createIndexes(db);
  }

  Future<void> _upgradeToV4(Database db) async {
    await db.transaction((txn) async {
      await _createPaymentTransactionsTable(txn);

      final records = await txn.query(
        'customs_records',
        where: 'paid_amount > ?',
        whereArgs: [0],
      );

      for (final record in records) {
        final id = record['id'] as String;
        final paidAmount = (record['paid_amount'] as num).toDouble();
        final createdAt = record['updated_at'] as String? ??
            record['created_at'] as String? ??
            DateTime.now().toIso8601String();

        await txn.insert(
          'payment_transactions',
          {
            'id': 'opening_$id',
            'customs_record_id': id,
            'amount': paidAmount,
            'note': 'دفعة افتتاحية من الرصيد السابق',
            'created_at': createdAt,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await _createIndexes(txn);
    });
  }

  Future<void> _upgradeToV5(Database db) async {
    await db.transaction((txn) async {
      await _createAccountingTables(txn);
      await _seedDefaultAccounts(txn);
      await _createAccountingIndexes(txn);
    });
  }

  Future<void> _upgradeToV6(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(customs_records)');
    final hasDisplayOrder =
        columns.any((column) => column['name'] == 'display_order');

    if (!hasDisplayOrder) {
      await db.execute(
        'ALTER TABLE customs_records ADD COLUMN display_order INTEGER NOT NULL DEFAULT 0',
      );
    }

    await _initializeCustomsRecordsDisplayOrder(db);
  }

  Future<void> _upgradeToV7(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(customs_records)');
    final names = columns.map((column) => column['name']).toSet();

    if (!names.contains('radiology_fee_applied')) {
      await db.execute(
        'ALTER TABLE customs_records ADD COLUMN radiology_fee_applied INTEGER NOT NULL DEFAULT 0',
      );
    }

    if (!names.contains('customs_amount_manual_override')) {
      await db.execute(
        'ALTER TABLE customs_records ADD COLUMN customs_amount_manual_override INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> _upgradeToV8(Database db) async {
    await _createAccountContactsTable(db);
    await _createAccountContactsIndexes(db);
  }

  Future<void> _upgradeToV9(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(customs_records)');
    final names = columns.map((column) => column['name']).toSet();

    if (!names.contains('clearance_fee')) {
      await db.execute(
        'ALTER TABLE customs_records ADD COLUMN clearance_fee REAL NOT NULL DEFAULT 0',
      );
    }

    if (!names.contains('driver_advance')) {
      await db.execute(
        'ALTER TABLE customs_records ADD COLUMN driver_advance REAL NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> _initializeCustomsRecordsDisplayOrder(Database db) async {
    final rows = await db.query(
      'customs_records',
      columns: ['id'],
      orderBy: 'created_at DESC, id ASC',
    );

    await db.transaction((txn) async {
      for (var index = 0; index < rows.length; index++) {
        await txn.update(
          'customs_records',
          {'display_order': index},
          where: 'id = ?',
          whereArgs: [rows[index]['id']],
        );
      }
    });
  }
}
