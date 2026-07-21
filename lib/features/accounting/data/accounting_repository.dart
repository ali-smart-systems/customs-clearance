import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../domain/account.dart';
import '../domain/journal_entry.dart';
import '../domain/journal_line.dart';

class AccountingRepository {
  AccountingRepository({
    AppDatabase? appDatabase,
    Uuid? uuid,
  })  : _appDatabase = appDatabase ?? AppDatabase.instance,
        _uuid = uuid ?? const Uuid();

  final AppDatabase _appDatabase;
  final Uuid _uuid;

  Future<List<Account>> getAccounts({bool activeOnly = false}) async {
    final db = await _appDatabase.database;

    final rows = await db.query(
      'accounts',
      where: activeOnly ? 'is_active = ?' : null,
      whereArgs: activeOnly ? [1] : null,
      orderBy: 'code ASC',
    );

    return rows.map(Account.fromMap).toList();
  }

  Future<Map<String, Object?>> getDefaultAccountingSettings() async {
    final db = await _appDatabase.database;

    final rows = await db.query(
      'accounting_settings',
      where: 'id = ?',
      whereArgs: ['default'],
      limit: 1,
    );

    if (rows.isEmpty) {
      return const {};
    }

    return rows.first;
  }

  Future<Account?> getAccountByCode(String code) async {
    final db = await _appDatabase.database;

    final rows = await db.query(
      'accounts',
      where: 'code = ?',
      whereArgs: [code.trim()],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return Account.fromMap(rows.first);
  }

  Future<Account?> getAccountById(String id) async {
    final db = await _appDatabase.database;

    final rows = await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return Account.fromMap(rows.first);
  }

  Future<Account> getCashAccount() async {
    final settings = await getDefaultAccountingSettings();
    final cashAccountId = settings['cash_account_id'] as String?;

    if (cashAccountId != null && cashAccountId.trim().isNotEmpty) {
      final account = await getAccountById(cashAccountId);
      if (account != null && account.isActive) return account;
    }

    final exactNameAccount =
        await _findActiveAccountByNormalizedName('الصندوق');
    if (exactNameAccount != null) {
      await _saveDefaultCashAccount(exactNameAccount.id);
      return exactNameAccount;
    }

    final containsNameAccount =
        await _findActiveAssetAccountContainingName('صندوق');
    if (containsNameAccount != null) {
      await _saveDefaultCashAccount(containsNameAccount.id);
      return containsNameAccount;
    }

    final codeAccount = await getAccountByCode('1000');
    if (codeAccount != null && codeAccount.isActive) {
      await _saveDefaultCashAccount(codeAccount.id);
      return codeAccount;
    }

    return _createDefaultCashAccount();
  }

  Future<Account> getCustomsPayableAccount() async {
    final settings = await getDefaultAccountingSettings();
    final accountId = settings['customs_payable_account_id'] as String?;

    if (accountId != null && accountId.trim().isNotEmpty) {
      final account = await getAccountById(accountId);
      if (account != null && account.isActive) return account;
    }

    final codeAccount = await getAccountByCode('2000');
    if (codeAccount != null && codeAccount.isActive) return codeAccount;

    final nameAccount =
        await _findActiveAccountByNormalizedName('جمارك مستحقة');
    if (nameAccount != null) return nameAccount;

    throw StateError('لم يتم العثور على حساب الجمارك المستحقة');
  }

  Future<Account> getDebtorsParentAccount() async {
    final account = await getAccountByCode('1100');

    if (account == null) {
      throw StateError(
        'لم يتم العثور على الحساب المحاسبي الافتراضي: 1100',
      );
    }

    const preferredName = 'المدينون / ذمم التجار';
    if (_normalizeName(account.name) != _normalizeName(preferredName)) {
      final db = await _appDatabase.database;
      await db.update(
        'accounts',
        {
          'name': preferredName,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [account.id],
      );

      final updated = await getAccountByCode('1100');
      if (updated != null) return updated;
    }

    return account;
  }

  Future<Account> getOrCreateMerchantAccount(String merchantName) async {
    final cleanName = _cleanName(merchantName);
    if (cleanName.isEmpty) {
      throw ArgumentError('اسم التاجر مطلوب لإنشاء حساب محاسبي');
    }

    final parent = await getDebtorsParentAccount();
    final db = await _appDatabase.database;
    final children = await db.query(
      'accounts',
      where: 'parent_id = ?',
      whereArgs: [parent.id],
      orderBy: 'code ASC',
    );
    final wantedName = _normalizeName(cleanName);

    for (final child in children) {
      if (_normalizeName(child['name'] as String) == wantedName) {
        return Account.fromMap(child);
      }
    }

    final now = DateTime.now().toIso8601String();
    final id = _uuid.v4();
    final code = await generateNextMerchantAccountCode();

    await db.insert('accounts', {
      'id': id,
      'code': code,
      'name': cleanName,
      'type': 'asset',
      'parent_id': parent.id,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });

    final account = await getAccountByCode(code);
    if (account == null) {
      throw StateError('تعذر إنشاء حساب التاجر');
    }

    return account;
  }

  Future<String> generateNextMerchantAccountCode() async {
    final parent = await getDebtorsParentAccount();
    final db = await _appDatabase.database;
    final rows = await db.query(
      'accounts',
      columns: ['code'],
      where: 'parent_id = ? OR code LIKE ?',
      whereArgs: [parent.id, '1100-%'],
    );

    var maxNumber = 0;
    for (final row in rows) {
      final code = row['code'] as String;
      final parts = code.split('-');
      if (parts.length != 2 || parts.first != '1100') continue;

      final number = int.tryParse(parts.last);
      if (number != null && number > maxNumber) {
        maxNumber = number;
      }
    }

    for (var next = maxNumber + 1; next < 10000; next++) {
      final code = '1100-${next.toString().padLeft(4, '0')}';
      final existing = await getAccountByCode(code);
      if (existing == null) return code;
    }

    throw StateError('تعذر توليد كود حساب تاجر جديد');
  }

  Future<JournalEntry?> getJournalEntryBySource(
    String sourceType,
    String sourceId,
  ) async {
    final db = await _appDatabase.database;

    final rows = await db.query(
      'journal_entries',
      where: 'source_type = ? AND source_id = ?',
      whereArgs: [sourceType, sourceId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final id = rows.first['id'] as String;
    return JournalEntry.fromMap(
      rows.first,
      lines: await _getLinesForEntry(db, id),
    );
  }

  Future<void> deleteJournalEntryBySource(
    String sourceType,
    String sourceId,
  ) async {
    final db = await _appDatabase.database;

    await db.transaction((txn) async {
      await _deleteJournalEntryBySourceInTransaction(
        txn,
        sourceType,
        sourceId,
      );
    });
  }

  Future<void> createOrReplaceAutoJournalEntry({
    required String sourceType,
    required String sourceId,
    required DateTime entryDate,
    required String description,
    required List<JournalLineInput> lines,
  }) async {
    final cleanDescription = description.trim();

    if (cleanDescription.isEmpty) {
      throw ArgumentError('وصف القيد مطلوب');
    }

    if (sourceType.trim().isEmpty || sourceId.trim().isEmpty) {
      throw ArgumentError('مصدر القيد التلقائي مطلوب');
    }

    _validateLines(lines);

    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    final entryId = _uuid.v4();

    await db.transaction((txn) async {
      await _validateAccountsForPosting(txn, lines);

      await _deleteJournalEntryBySourceInTransaction(
        txn,
        sourceType,
        sourceId,
      );

      await txn.insert('journal_entries', {
        'id': entryId,
        'entry_date': entryDate.toIso8601String(),
        'description': cleanDescription,
        'source_type': sourceType,
        'source_id': sourceId,
        'created_at': now,
        'updated_at': now,
      });

      for (final line in lines) {
        await txn.insert('journal_lines', {
          'id': _uuid.v4(),
          'journal_entry_id': entryId,
          'account_id': line.accountId,
          'debit': line.debit,
          'credit': line.credit,
          'note': line.note?.trim().isEmpty ?? true ? null : line.note!.trim(),
          'created_at': now,
        });
      }
    });
  }

  Future<void> createAccount({
    required String code,
    required String name,
    required String type,
    String? parentId,
  }) async {
    final cleanCode = code.trim();
    final cleanName = name.trim();

    if (cleanCode.isEmpty || cleanName.isEmpty) {
      throw ArgumentError('رمز الحساب واسمه مطلوبان');
    }

    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();

    await db.insert('accounts', {
      'id': _uuid.v4(),
      'code': cleanCode,
      'name': cleanName,
      'type': type,
      'parent_id': parentId,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateAccount({
    required Account account,
    required String code,
    required String name,
    required String type,
    String? parentId,
    required bool isActive,
  }) async {
    final cleanCode = code.trim();
    final cleanName = name.trim();

    if (cleanCode.isEmpty || cleanName.isEmpty) {
      throw ArgumentError('رمز الحساب واسمه مطلوبان');
    }

    final db = await _appDatabase.database;

    await db.update(
      'accounts',
      {
        'code': cleanCode,
        'name': cleanName,
        'type': type,
        'parent_id': parentId,
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [account.id],
    );
  }

  Future<void> deleteAccount(Account account) async {
    final db = await _appDatabase.database;
    final usage = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM journal_lines WHERE account_id = ?',
            [account.id],
          ),
        ) ??
        0;

    if (usage > 0) {
      throw StateError('لا يمكن حذف حساب عليه قيود');
    }

    await db.delete(
      'accounts',
      where: 'id = ?',
      whereArgs: [account.id],
    );
  }

  Future<List<JournalEntry>> getJournalEntries() async {
    final db = await _appDatabase.database;
    final entryRows = await db.query(
      'journal_entries',
      orderBy: 'entry_date DESC, created_at DESC, id DESC',
    );

    final entries = <JournalEntry>[];
    for (final row in entryRows) {
      final id = row['id'] as String;
      entries.add(
        JournalEntry.fromMap(
          row,
          lines: await _getLinesForEntry(db, id),
        ),
      );
    }

    return entries;
  }

  Future<void> resetAllJournalEntries() async {
    final db = await _appDatabase.database;

    await db.transaction((txn) async {
      await txn.delete('journal_lines');
      await txn.delete('journal_entries');
    });
  }

  Future<void> createJournalEntry({
    required DateTime entryDate,
    required String description,
    required List<JournalLineInput> lines,
  }) async {
    final cleanDescription = description.trim();

    if (cleanDescription.isEmpty) {
      throw ArgumentError('وصف القيد مطلوب');
    }

    _validateLines(lines);

    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    final entryId = _uuid.v4();

    await db.transaction((txn) async {
      await _validateAccountsForPosting(txn, lines);

      await txn.insert('journal_entries', {
        'id': entryId,
        'entry_date': entryDate.toIso8601String(),
        'description': cleanDescription,
        'source_type': null,
        'source_id': null,
        'created_at': now,
        'updated_at': now,
      });

      for (final line in lines) {
        await txn.insert('journal_lines', {
          'id': _uuid.v4(),
          'journal_entry_id': entryId,
          'account_id': line.accountId,
          'debit': line.debit,
          'credit': line.credit,
          'note': line.note?.trim().isEmpty ?? true ? null : line.note!.trim(),
          'created_at': now,
        });
      }
    });
  }

  Future<void> deleteJournalEntry(String id) async {
    final db = await _appDatabase.database;

    await db.transaction((txn) async {
      await txn.delete(
        'journal_lines',
        where: 'journal_entry_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'journal_entries',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> _deleteJournalEntryBySourceInTransaction(
    DatabaseExecutor txn,
    String sourceType,
    String sourceId,
  ) async {
    final rows = await txn.query(
      'journal_entries',
      columns: ['id'],
      where: 'source_type = ? AND source_id = ?',
      whereArgs: [sourceType, sourceId],
    );

    for (final row in rows) {
      final id = row['id'] as String;
      await txn.delete(
        'journal_lines',
        where: 'journal_entry_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'journal_entries',
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<List<LedgerRow>> getLedgerRows(String accountId) async {
    final db = await _appDatabase.database;
    final accountIds = await _ledgerAccountIds(db, accountId);
    final placeholders = List.filled(accountIds.length, '?').join(', ');
    final rows = await db.rawQuery(
      '''
      SELECT
        je.entry_date,
        je.id AS journal_entry_id,
        je.description,
        jl.id AS journal_line_id,
        a.code AS account_code,
        a.name AS account_name,
        jl.debit,
        jl.credit,
        jl.note
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_entry_id
      JOIN accounts a ON a.id = jl.account_id
      WHERE jl.account_id IN ($placeholders)
      ORDER BY
        je.entry_date ASC,
        je.created_at ASC,
        je.id ASC,
        jl.created_at ASC,
        jl.id ASC
      ''',
      accountIds,
    );

    var balance = 0.0;

    return rows.map((row) {
      final debit = (row['debit'] as num).toDouble();
      final credit = (row['credit'] as num).toDouble();
      balance += debit - credit;

      return LedgerRow(
        entryDate: DateTime.parse(row['entry_date'] as String),
        description: row['description'] as String,
        debit: debit,
        credit: credit,
        balance: balance,
        note: row['note'] as String?,
        accountCode: row['account_code'] as String?,
        accountName: row['account_name'] as String?,
      );
    }).toList();
  }

  Future<List<TrialBalanceRow>> getTrialBalanceRows() async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery('''
      SELECT
        a.id,
        a.code,
        a.name,
        a.type,
        a.parent_id,
        COALESCE(SUM(jl.debit), 0) AS debit,
        COALESCE(SUM(jl.credit), 0) AS credit
      FROM accounts a
      LEFT JOIN journal_lines jl ON jl.account_id = a.id
      GROUP BY a.id, a.code, a.name, a.type, a.parent_id
      ORDER BY a.code ASC
    ''');

    final baseRows = rows.map((row) {
      final debit = (row['debit'] as num).toDouble();
      final credit = (row['credit'] as num).toDouble();

      return TrialBalanceRow(
        accountId: row['id'] as String,
        code: row['code'] as String,
        name: row['name'] as String,
        type: row['type'] as String,
        parentId: row['parent_id'] as String?,
        debit: debit,
        credit: credit,
        balance: debit - credit,
        closingDebit: debit >= credit ? debit - credit : 0,
        closingCredit: credit > debit ? credit - debit : 0,
      );
    }).toList();

    return _withParentTotals(baseRows);
  }

  Future<List<JournalLine>> _getLinesForEntry(
    DatabaseExecutor db,
    String entryId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        jl.*,
        a.code AS account_code,
        a.name AS account_name
      FROM journal_lines jl
      JOIN accounts a ON a.id = jl.account_id
      WHERE jl.journal_entry_id = ?
      ORDER BY jl.created_at ASC
      ''',
      [entryId],
    );

    return rows.map(JournalLine.fromMap).toList();
  }

  void _validateLines(List<JournalLineInput> lines) {
    if (lines.length < 2) {
      throw ArgumentError('القيد يجب أن يحتوي سطرين على الأقل');
    }

    var totalDebit = 0;
    var totalCredit = 0;

    for (final line in lines) {
      if (line.accountId.trim().isEmpty) {
        throw ArgumentError('يجب اختيار حساب لكل سطر');
      }

      if (!line.debit.isFinite || !line.credit.isFinite) {
        throw ArgumentError(
            'قيم المدين والدائن يجب أن تكون أرقامًا مالية صالحة');
      }

      if (line.debit < 0 || line.credit < 0) {
        throw ArgumentError('لا يسمح بقيمة سالبة في سطر القيد');
      }

      final debitUnits = _financialUnits(line.debit);
      final creditUnits = _financialUnits(line.credit);
      final hasDebit = debitUnits > 0;
      final hasCredit = creditUnits > 0;

      if (hasDebit && hasCredit) {
        throw ArgumentError('لا يسمح بسطر فيه مدين ودائن معاً');
      }

      if (!hasDebit && !hasCredit) {
        throw ArgumentError('لا يسمح بسطر مدين ودائن كلاهما صفر');
      }

      totalDebit += debitUnits;
      totalCredit += creditUnits;
    }

    if (totalDebit != totalCredit) {
      throw ArgumentError('مجموع المدين يجب أن يساوي مجموع الدائن');
    }
  }

  int _financialUnits(double value) => (value * 1000000).round();

  Future<Account?> _findActiveAccountByNormalizedName(String name) async {
    final accounts = await getAccounts(activeOnly: true);
    final wantedName = _normalizeName(name);

    for (final account in accounts) {
      if (_normalizeName(account.name) == wantedName) return account;
    }

    return null;
  }

  Future<Account?> _findActiveAssetAccountContainingName(String text) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'accounts',
      where: 'is_active = ? AND type = ?',
      whereArgs: [1, 'asset'],
      orderBy: 'code ASC',
    );
    final wantedText = _normalizeName(text);

    for (final row in rows) {
      final account = Account.fromMap(row);
      if (_normalizeName(account.name).contains(wantedText)) return account;
    }

    return null;
  }

  Future<Account> _createDefaultCashAccount() async {
    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    final id = _uuid.v4();
    final code = await _nextAvailableCashCode();

    await db.insert('accounts', {
      'id': id,
      'code': code,
      'name': 'الصندوق',
      'type': 'asset',
      'parent_id': null,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });

    await _saveDefaultCashAccount(id);

    final account = await getAccountById(id);
    if (account == null) {
      throw StateError('تعذر إنشاء حساب الصندوق الافتراضي');
    }

    return account;
  }

  Future<String> _nextAvailableCashCode() async {
    if (await getAccountByCode('1000') == null) return '1000';

    for (var index = 1; index < 1000; index++) {
      final code = '1000-${index.toString().padLeft(3, '0')}';
      if (await getAccountByCode(code) == null) return code;
    }

    throw StateError('تعذر توليد كود حساب صندوق افتراضي');
  }

  Future<void> _saveDefaultCashAccount(String accountId) async {
    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();

    final updated = await db.update(
      'accounting_settings',
      {
        'cash_account_id': accountId,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: ['default'],
    );

    if (updated > 0) return;

    await db.insert('accounting_settings', {
      'id': 'default',
      'cash_account_id': accountId,
      'merchant_receivable_account_id': null,
      'customs_payable_account_id': null,
      'service_revenue_account_id': null,
      'updated_at': now,
    });
  }

  Future<void> _validateAccountsForPosting(
    DatabaseExecutor db,
    List<JournalLineInput> lines,
  ) async {
    final accountIds = lines.map((line) => line.accountId.trim()).toSet();
    final placeholders = List.filled(accountIds.length, '?').join(', ');
    final rows = await db.query(
      'accounts',
      columns: ['id', 'is_active'],
      where: 'id IN ($placeholders)',
      whereArgs: accountIds.toList(),
    );

    if (rows.length != accountIds.length) {
      throw ArgumentError('أحد حسابات القيد غير موجود');
    }

    if (rows.any((row) => (row['is_active'] as num).toInt() != 1)) {
      throw ArgumentError('لا يمكن استخدام حساب موقوف في قيد جديد');
    }
  }

  Future<List<Object?>> _ledgerAccountIds(
    DatabaseExecutor db,
    String accountId,
  ) async {
    final rows = await db.query(
      'accounts',
      columns: ['id'],
      where: 'parent_id = ?',
      whereArgs: [accountId],
    );

    return [
      accountId,
      ...rows.map((row) => row['id'] as String),
    ];
  }

  List<TrialBalanceRow> _withParentTotals(List<TrialBalanceRow> rows) {
    final childrenByParent = <String, List<TrialBalanceRow>>{};
    for (final row in rows) {
      final parentId = row.parentId;
      if (parentId == null) continue;
      childrenByParent.putIfAbsent(parentId, () => []).add(row);
    }

    final result = <TrialBalanceRow>[];
    for (final row in rows) {
      if (row.parentId != null) continue;

      final children = childrenByParent[row.accountId] ?? const [];
      final childDebit = children.fold(0.0, (sum, child) => sum + child.debit);
      final childCredit =
          children.fold(0.0, (sum, child) => sum + child.credit);
      final totalDebit = row.debit + childDebit;
      final totalCredit = row.credit + childCredit;
      final balance = totalDebit - totalCredit;

      result.add(
        row.copyWith(
          debit: totalDebit,
          credit: totalCredit,
          balance: balance,
          closingDebit: balance >= 0 ? balance : 0,
          closingCredit: balance < 0 ? -balance : 0,
          isParentTotal: children.isNotEmpty,
        ),
      );

      result.addAll(children.map((child) => child.copyWith(isChild: true)));
    }

    return result;
  }

  String _cleanName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeName(String value) {
    return _cleanName(value).toLowerCase();
  }
}

class JournalLineInput {
  const JournalLineInput({
    required this.accountId,
    required this.debit,
    required this.credit,
    this.note,
  });

  final String accountId;
  final double debit;
  final double credit;
  final String? note;
}

class LedgerRow {
  const LedgerRow({
    required this.entryDate,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
    this.note,
    this.accountCode,
    this.accountName,
  });

  final DateTime entryDate;
  final String description;
  final double debit;
  final double credit;
  final double balance;
  final String? note;
  final String? accountCode;
  final String? accountName;
}

class TrialBalanceRow {
  const TrialBalanceRow({
    required this.accountId,
    required this.code,
    required this.name,
    required this.type,
    this.parentId,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.closingDebit,
    required this.closingCredit,
    this.isChild = false,
    this.isParentTotal = false,
  });

  final String accountId;
  final String code;
  final String name;
  final String type;
  final String? parentId;
  final double debit;
  final double credit;
  final double balance;
  final double closingDebit;
  final double closingCredit;
  final bool isChild;
  final bool isParentTotal;

  TrialBalanceRow copyWith({
    double? debit,
    double? credit,
    double? balance,
    double? closingDebit,
    double? closingCredit,
    bool? isChild,
    bool? isParentTotal,
  }) {
    return TrialBalanceRow(
      accountId: accountId,
      code: code,
      name: name,
      type: type,
      parentId: parentId,
      debit: debit ?? this.debit,
      credit: credit ?? this.credit,
      balance: balance ?? this.balance,
      closingDebit: closingDebit ?? this.closingDebit,
      closingCredit: closingCredit ?? this.closingCredit,
      isChild: isChild ?? this.isChild,
      isParentTotal: isParentTotal ?? this.isParentTotal,
    );
  }
}
