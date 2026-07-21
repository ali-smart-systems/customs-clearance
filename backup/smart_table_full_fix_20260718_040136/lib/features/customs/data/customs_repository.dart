import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../accounting/data/accounting_repository.dart';
import '../../accounting/domain/account.dart';
import '../domain/customs_record.dart';
import '../domain/payment_transaction.dart';

class CustomsRepository {
  CustomsRepository({
    AppDatabase? appDatabase,
    Uuid? uuid,
    AccountingRepository? accountingRepository,
  })  : _appDatabase = appDatabase ?? AppDatabase.instance,
        _uuid = uuid ?? const Uuid(),
        _accountingRepository = accountingRepository ?? AccountingRepository();

  final AppDatabase _appDatabase;
  final Uuid _uuid;
  final AccountingRepository _accountingRepository;

  Future<List<CustomsRecord>> getRecords() async {
    final db = await _appDatabase.database;
    await ensureDisplayOrderInitialized();

    final rows = await db.query(
      'customs_records',
      orderBy: 'display_order ASC, created_at DESC, id ASC',
    );

    return rows.map(CustomsRecord.fromMap).toList();
  }

  Future<void> resyncPaymentsAndPaidAmounts() async {
    final db = await _appDatabase.database;

    final records = await db.query(
      'customs_records',
      columns: ['id'],
    );

    await db.transaction((txn) async {
      for (final record in records) {
        final recordId = record['id'] as String;
        await _recalculatePaidAmountInTransaction(txn, recordId);
      }
    });

    await resyncPaymentTransactionJournals();
  }

  Future<void> ensureDisplayOrderInitialized() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'customs_records',
      columns: ['id', 'display_order'],
      orderBy: 'display_order ASC, created_at DESC, id ASC',
    );

    var needsInitialization = false;
    for (var index = 0; index < rows.length; index++) {
      final order = (rows[index]['display_order'] as num?)?.toInt();
      if (order != index) {
        needsInitialization = true;
        break;
      }
    }

    if (!needsInitialization) return;

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

  Future<void> updateRecordsDisplayOrder(
    List<CustomsRecord> orderedRecords,
  ) async {
    if (orderedRecords.isEmpty) return;

    final db = await _appDatabase.database;
    final slotOrders =
        orderedRecords.map((record) => record.displayOrder).toList()..sort();

    await db.transaction((txn) async {
      for (var index = 0; index < orderedRecords.length; index++) {
        await txn.update(
          'customs_records',
          {
            'display_order': slotOrders[index],
            'sync_status': 'local',
          },
          where: 'id = ?',
          whereArgs: [orderedRecords[index].id],
        );
      }
    });
  }

  Future<void> resetAllOperationsData() async {
    final db = await _appDatabase.database;
    const automaticSourceTypes = [
      'customs_record_charge',
      'payment_transaction',
    ];

    await db.transaction((txn) async {
      await txn.delete(
        'journal_lines',
        where: '''
          journal_entry_id IN (
            SELECT id
            FROM journal_entries
            WHERE source_type IN (?, ?)
          )
        ''',
        whereArgs: automaticSourceTypes,
      );

      await txn.delete(
        'journal_entries',
        where: 'source_type IN (?, ?)',
        whereArgs: automaticSourceTypes,
      );

      await txn.delete('payment_transactions');
      await txn.delete('pricing_history');
      await txn.delete(
        'customs_records',
        where: 'parent_record_id IS NOT NULL',
      );
      await txn.delete('customs_records');
      await txn.delete('shipment_requests');
    });
  }

  Future<void> moveRecordToVisiblePosition({
    required List<CustomsRecord> visibleRecords,
    required int fromIndex,
    required int toIndex,
  }) async {
    if (visibleRecords.isEmpty) return;

    if (fromIndex < 0 ||
        fromIndex >= visibleRecords.length ||
        toIndex < 0 ||
        toIndex >= visibleRecords.length) {
      throw RangeError('رقم الصف خارج النطاق');
    }

    if (fromIndex == toIndex) return;

    final orderedRecords = [...visibleRecords];
    final movedRecord = orderedRecords.removeAt(fromIndex);
    orderedRecords.insert(toIndex, movedRecord);

    await updateRecordsDisplayOrder(orderedRecords);
  }

  Future<CustomsRecord?> getRecordById(String id) async {
    final db = await _appDatabase.database;

    final rows = await db.query(
      'customs_records',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return CustomsRecord.fromMap(rows.first);
  }

  Future<List<CustomsRecord>> getRecordsByAgentName(String agentName) async {
    final allRecords = await getRecords();
    final wantedName = _normalizeName(agentName);

    return allRecords.where((record) {
      return _normalizeName(record.agentName) == wantedName;
    }).toList();
  }

  Future<List<CustomsRecord>> getRecordsByMerchantName(
    String merchantName,
  ) async {
    final allRecords = await getRecords();
    final wantedName = _normalizeName(merchantName);

    return allRecords.where((record) {
      final current = record.beneficiaryMerchant;
      if (current == null || current.trim().isEmpty) return false;

      return _normalizeName(current) == wantedName;
    }).toList();
  }

  Future<AccountContact?> getAccountContact(
    String accountType,
    String accountName,
  ) async {
    final db = await _appDatabase.database;
    final cleanType = _cleanName(accountType);
    final cleanName = _cleanName(accountName);

    final rows = await db.query(
      'account_contacts',
      where: 'account_type = ? AND account_name = ?',
      whereArgs: [cleanType, cleanName],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return AccountContact.fromMap(rows.first);
  }

  Future<void> saveAccountContact({
    required String accountType,
    required String accountName,
    String? phone,
    String? whatsapp,
    bool whatsappSameAsPhone = true,
    String? notes,
  }) async {
    final db = await _appDatabase.database;
    final cleanType = _cleanName(accountType);
    final cleanName = _cleanName(accountName);
    final cleanPhone = phone == null ? null : _cleanName(phone);
    final cleanWhatsapp = whatsapp == null ? null : _cleanName(whatsapp);
    final cleanNotes = notes == null ? null : _cleanName(notes);
    final existing = await getAccountContact(cleanType, cleanName);
    final now = DateTime.now().toIso8601String();

    final values = {
      'account_type': cleanType,
      'account_name': cleanName,
      'phone': cleanPhone == null || cleanPhone.isEmpty ? null : cleanPhone,
      'whatsapp':
          cleanWhatsapp == null || cleanWhatsapp.isEmpty ? null : cleanWhatsapp,
      'whatsapp_same_as_phone': whatsappSameAsPhone ? 1 : 0,
      'notes': cleanNotes == null || cleanNotes.isEmpty ? null : cleanNotes,
      'updated_at': now,
    };

    if (existing == null) {
      await db.insert('account_contacts', {
        'id': _uuid.v4(),
        ...values,
        'created_at': now,
      });
      return;
    }

    await db.update(
      'account_contacts',
      values,
      where: 'id = ?',
      whereArgs: [existing.id],
    );
  }

  Future<String?> getAccountPhone(
    String accountType,
    String accountName,
  ) async {
    final contact = await getAccountContact(accountType, accountName);
    final phone = contact?.phone?.trim();
    return phone == null || phone.isEmpty ? null : phone;
  }

  Future<String?> getAccountWhatsApp(
    String accountType,
    String accountName,
  ) async {
    final contact = await getAccountContact(accountType, accountName);
    if (contact == null) return null;

    final value =
        contact.whatsappSameAsPhone ? contact.phone : contact.whatsapp;
    final whatsapp = value?.trim();
    return whatsapp == null || whatsapp.isEmpty ? null : whatsapp;
  }

  Future<List<CustomsRecord>> getRecordsByDriverName(String driverName) async {
    final allRecords = await getRecords();
    final wantedName = _normalizeName(driverName);

    return allRecords.where((record) {
      return _normalizeName(record.driverName) == wantedName;
    }).toList();
  }

  Future<List<PaymentTransaction>> getPaymentsForRecord(
    String customsRecordId,
  ) async {
    final db = await _appDatabase.database;

    final rows = await db.query(
      'payment_transactions',
      where: 'customs_record_id = ?',
      whereArgs: [customsRecordId],
      orderBy: 'created_at DESC',
    );

    return rows.map(PaymentTransaction.fromMap).toList();
  }

  Future<PaymentTransaction?> getPaymentById(String paymentId) async {
    final db = await _appDatabase.database;

    final rows = await db.query(
      'payment_transactions',
      where: 'id = ?',
      whereArgs: [paymentId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return PaymentTransaction.fromMap(rows.first);
  }

  Future<PaymentTransaction> addPaymentForRecordId({
    required String customsRecordId,
    required double amount,
    String? note,
  }) async {
    final record = await getRecordById(customsRecordId);
    if (record == null) {
      throw StateError('عملية التخليص غير موجودة');
    }

    return addPayment(
      record: record,
      amount: amount,
      note: note,
    );
  }

  Future<PaymentTransaction> addPayment({
    required CustomsRecord record,
    required double amount,
    String? note,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('مبلغ السداد يجب أن يكون أكبر من صفر');
    }

    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    final paymentId = _uuid.v4();

    await db.transaction((txn) async {
      await txn.insert('payment_transactions', {
        'id': paymentId,
        'customs_record_id': record.id,
        'amount': amount,
        'note': note?.trim().isEmpty ?? true ? null : note!.trim(),
        'created_at': now,
      });

      await _recalculatePaidAmountInTransaction(txn, record.id);
    });

    final refreshedRecord = await getRecordById(record.id);
    final recalculatedPaidAmount =
        refreshedRecord?.paidAmount ?? record.paidAmount + amount;
    developer.log(
      'payment added: recordId=${record.id}, '
      'customsAmount=${record.customsAmount}, '
      'oldPaidAmount=${record.paidAmount}, '
      'newPaymentAmount=$amount, '
      'recalculatedPaidAmount=$recalculatedPaidAmount, '
      'computedStatus=${_paymentStatusLabel(record.customsAmount, recalculatedPaidAmount)}',
      name: 'CustomsRepository',
    );

    final payment = PaymentTransaction(
      id: paymentId,
      customsRecordId: record.id,
      amount: amount,
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
      createdAt: DateTime.parse(now),
    );
    await syncPaymentTransactionJournal(payment);
    return payment;
  }

  Future<void> deletePayment({
    required String paymentId,
    required String customsRecordId,
  }) async {
    final db = await _appDatabase.database;

    await deletePaymentTransactionJournal(paymentId);

    await db.transaction((txn) async {
      await txn.delete(
        'payment_transactions',
        where: 'id = ? AND customs_record_id = ?',
        whereArgs: [paymentId, customsRecordId],
      );

      await _recalculatePaidAmountInTransaction(txn, customsRecordId);
    });

    final refreshedRecord = await getRecordById(customsRecordId);
    if (refreshedRecord != null) {
      developer.log(
        'payment deleted: recordId=$customsRecordId, '
        'customsAmount=${refreshedRecord.customsAmount}, '
        'recalculatedPaidAmount=${refreshedRecord.paidAmount}, '
        'computedStatus=${_paymentStatusLabel(refreshedRecord.customsAmount, refreshedRecord.paidAmount)}',
        name: 'CustomsRepository',
      );
    }
  }

  Future<void> deletePaymentById(String paymentId) async {
    final payment = await getPaymentById(paymentId);
    if (payment == null) {
      await deletePaymentTransactionJournal(paymentId);
      return;
    }

    await deletePayment(
      paymentId: payment.id,
      customsRecordId: payment.customsRecordId,
    );
  }

  Future<void> updatePayment({
    required String paymentId,
    required double amount,
    String? note,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('مبلغ السداد يجب أن يكون أكبر من صفر');
    }

    final payment = await getPaymentById(paymentId);
    if (payment == null) {
      throw StateError('دفعة السداد غير موجودة');
    }

    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      await txn.update(
        'payment_transactions',
        {
          'amount': amount,
          'note': note?.trim().isEmpty ?? true ? null : note!.trim(),
        },
        where: 'id = ?',
        whereArgs: [paymentId],
      );

      await _recalculatePaidAmountInTransaction(txn, payment.customsRecordId);
    });

    final updatedPayment = PaymentTransaction(
      id: payment.id,
      customsRecordId: payment.customsRecordId,
      amount: amount,
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
      createdAt: payment.createdAt,
    );
    await syncPaymentTransactionJournal(updatedPayment);

    final refreshedRecord = await getRecordById(payment.customsRecordId);
    if (refreshedRecord != null) {
      developer.log(
        'payment updated: recordId=${payment.customsRecordId}, '
        'customsAmount=${refreshedRecord.customsAmount}, '
        'newPaymentAmount=$amount, '
        'recalculatedPaidAmount=${refreshedRecord.paidAmount}, '
        'computedStatus=${_paymentStatusLabel(refreshedRecord.customsAmount, refreshedRecord.paidAmount)}',
        name: 'CustomsRepository',
      );
    }
  }

  Future<void> recalculatePaidAmount(String customsRecordId) async {
    final db = await _appDatabase.database;

    await db.transaction((txn) async {
      await _recalculatePaidAmountInTransaction(txn, customsRecordId);
    });
  }

  Future<bool> canDeleteAgent(String agentName) async {
    return await getAgentDeleteBlockReason(agentName) == null;
  }

  Future<String?> getAgentDeleteBlockReason(String agentName) async {
    final agentKey = _normalizeName(agentName);
    if (agentKey.isEmpty) return 'اسم الوكيل مطلوب';

    final records = await getRecords();
    final hasRecords = records.any((record) {
      return _normalizeName(record.agentName) == agentKey;
    });

    if (hasRecords) {
      return 'لا يمكن حذف الوكيل لأنه مرتبط بحركات تخليص.';
    }

    return null;
  }

  Future<bool> canDeleteMerchant(String merchantName) async {
    return await getMerchantDeleteBlockReason(merchantName) == null;
  }

  Future<String?> getMerchantDeleteBlockReason(String merchantName) async {
    final merchantKey = _normalizeName(merchantName);
    if (merchantKey.isEmpty) return 'اسم التاجر مطلوب';

    final records = await getRecords();
    final hasRecords = records.any((record) {
      final current = record.beneficiaryMerchant;
      if (current == null || current.trim().isEmpty) return false;

      return _normalizeName(current) == merchantKey;
    });

    if (hasRecords) {
      return 'لا يمكن حذف التاجر لأنه مرتبط بحركات تخليص أو قيود مالية.';
    }

    final merchantAccount = await _findMerchantAccountByName(merchantName);
    if (merchantAccount == null) return null;

    final db = await _appDatabase.database;
    final journalLineCount = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM journal_lines WHERE account_id = ?',
            [merchantAccount.id],
          ),
        ) ??
        0;

    if (journalLineCount > 0) {
      return 'لا يمكن حذف التاجر لأنه مرتبط بحركات تخليص أو قيود مالية.';
    }

    return null;
  }

  Future<bool> canDeleteCustomsRecord(String recordId) async {
    return await getCustomsRecordDeleteBlockReason(recordId) == null;
  }

  Future<String?> getCustomsRecordDeleteBlockReason(String recordId) async {
    final record = await getRecordById(recordId);
    if (record == null) return null;

    final db = await _appDatabase.database;
    final childCount = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM customs_records WHERE parent_record_id = ?',
            [recordId],
          ),
        ) ??
        0;

    if (childCount > 0) {
      return 'لا يمكن حذف السطر الأصلي قبل حذف السطور التابعة له.';
    }

    if (record.paidAmount > 0.01) {
      return 'لا يمكن حذف هذه الحركة لأنها مرتبطة بسداد أو قيود يومية أو الصندوق.';
    }

    final payments = await getPaymentsForRecord(recordId);
    if (payments.isNotEmpty) {
      return 'لا يمكن حذف هذه الحركة لأنها مرتبطة بسداد أو قيود يومية أو الصندوق.';
    }

    final chargeJournalCount = Sqflite.firstIntValue(
          await db.rawQuery(
            '''
            SELECT COUNT(*)
            FROM journal_entries
            WHERE source_type = ? AND source_id = ?
            ''',
            ['customs_record_charge', recordId],
          ),
        ) ??
        0;

    if (chargeJournalCount > 0) {
      return 'لا يمكن حذف هذه الحركة لأنها مرتبطة بسداد أو قيود يومية أو الصندوق.';
    }

    final paymentJournalCount = Sqflite.firstIntValue(
          await db.rawQuery(
            '''
            SELECT COUNT(*)
            FROM journal_entries
            WHERE source_type = ?
              AND source_id IN (
                SELECT id
                FROM payment_transactions
                WHERE customs_record_id = ?
              )
            ''',
            ['payment_transaction', recordId],
          ),
        ) ??
        0;

    if (paymentJournalCount > 0) {
      return 'لا يمكن حذف هذه الحركة لأنها مرتبطة بسداد أو قيود يومية أو الصندوق.';
    }

    return null;
  }

  Future<void> renameAgent(String oldName, String newName) async {
    final cleanNewName = _cleanName(newName);

    if (cleanNewName.isEmpty) {
      throw ArgumentError('اسم الوكيل مطلوب');
    }

    final oldKey = _normalizeName(oldName);
    final newKey = _normalizeName(cleanNewName);

    if (oldKey == newKey) return;

    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      final records = await _getRecordsInTransaction(txn);
      final matchingRecords = records.where((record) {
        return _normalizeName(record.agentName) == oldKey;
      });

      for (final record in matchingRecords) {
        await txn.update(
          'customs_records',
          {
            'agent_name': cleanNewName,
            'updated_at': now,
            'sync_status': 'local',
          },
          where: 'id = ?',
          whereArgs: [record.id],
        );
      }
    });

    final records = await getRecordsByAgentName(cleanNewName);
    for (final record in records) {
      await syncCustomsRecordChargeJournal(record);
      final payments = await getPaymentsForRecord(record.id);
      for (final payment in payments) {
        await syncPaymentTransactionJournal(payment);
      }
    }
  }

  Future<void> deleteAgent(String agentName) async {
    final agentKey = _normalizeName(agentName);

    if (agentKey.isEmpty) {
      throw ArgumentError('اسم الوكيل مطلوب');
    }

    final blockReason = await getAgentDeleteBlockReason(agentName);
    if (blockReason != null) {
      throw StateError(blockReason);
    }

    final db = await _appDatabase.database;
    final records = await getRecords();
    final matchingRecordIds = records
        .where((record) {
          return _normalizeName(record.agentName) == agentKey;
        })
        .map((record) => record.id)
        .toList();

    for (final recordId in matchingRecordIds) {
      await _deleteAccountingLinksForRecord(recordId);
    }

    await db.transaction((txn) async {
      final recordsInTransaction = await _getRecordsInTransaction(txn);
      final matchingRecords = recordsInTransaction.where((record) {
        return _normalizeName(record.agentName) == agentKey;
      }).toList()
        ..sort((a, b) {
          final aIsChild = a.parentRecordId != null;
          final bIsChild = b.parentRecordId != null;

          if (aIsChild == bIsChild) return 0;
          return aIsChild ? -1 : 1;
        });

      for (final record in matchingRecords) {
        await txn.delete(
          'payment_transactions',
          where: 'customs_record_id = ?',
          whereArgs: [record.id],
        );
        await txn.delete(
          'pricing_history',
          where: 'customs_record_id = ?',
          whereArgs: [record.id],
        );
      }

      for (final record in matchingRecords) {
        await txn.delete(
          'customs_records',
          where: 'id = ?',
          whereArgs: [record.id],
        );
      }
    });
  }

  Future<void> renameMerchant(String oldName, String newName) async {
    final cleanNewName = _cleanName(newName);

    if (cleanNewName.isEmpty) {
      throw ArgumentError('اسم التاجر مطلوب');
    }

    final oldKey = _normalizeName(oldName);
    final newKey = _normalizeName(cleanNewName);

    if (oldKey == newKey) return;

    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      final records = await _getRecordsInTransaction(txn);
      final matchingRecords = records.where((record) {
        final merchantName = record.beneficiaryMerchant;
        if (merchantName == null || merchantName.trim().isEmpty) return false;

        return _normalizeName(merchantName) == oldKey;
      });

      for (final record in matchingRecords) {
        await txn.update(
          'customs_records',
          {
            'beneficiary_merchant': cleanNewName,
            'updated_at': now,
            'sync_status': 'local',
          },
          where: 'id = ?',
          whereArgs: [record.id],
        );
      }
    });

    final records = await getRecordsByMerchantName(cleanNewName);
    for (final record in records) {
      await syncCustomsRecordChargeJournal(record);
      final payments = await getPaymentsForRecord(record.id);
      for (final payment in payments) {
        await syncPaymentTransactionJournal(payment);
      }
    }
  }

  Future<void> deleteMerchant(String merchantName) async {
    final merchantKey = _normalizeName(merchantName);

    if (merchantKey.isEmpty) {
      throw ArgumentError('اسم التاجر مطلوب');
    }

    final blockReason = await getMerchantDeleteBlockReason(merchantName);
    if (blockReason != null) {
      throw StateError(blockReason);
    }

    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    final records = await getRecords();
    final matchingRecordIds = records
        .where((record) {
          final current = record.beneficiaryMerchant;
          if (current == null || current.trim().isEmpty) return false;

          return _normalizeName(current) == merchantKey;
        })
        .map((record) => record.id)
        .toList();

    for (final recordId in matchingRecordIds) {
      await _deleteAccountingLinksForRecord(recordId);
    }

    await db.transaction((txn) async {
      final records = await _getRecordsInTransaction(txn);
      final matchingRecords = records.where((record) {
        final current = record.beneficiaryMerchant;
        if (current == null || current.trim().isEmpty) return false;

        return _normalizeName(current) == merchantKey;
      }).toList()
        ..sort((a, b) {
          final aIsChild = a.parentRecordId != null;
          final bIsChild = b.parentRecordId != null;

          if (aIsChild == bIsChild) return 0;
          return aIsChild ? -1 : 1;
        });

      for (final record in matchingRecords) {
        final parentRecordId = record.parentRecordId;

        if (parentRecordId != null) {
          final parentRows = await txn.query(
            'customs_records',
            where: 'id = ?',
            whereArgs: [parentRecordId],
            limit: 1,
          );

          if (parentRows.isNotEmpty) {
            final parent = CustomsRecord.fromMap(parentRows.first);

            await txn.update(
              'customs_records',
              {
                'quantity': parent.quantity + record.quantity,
                'customs_amount': parent.customsAmount + record.customsAmount,
                'clearance_fee': parent.clearanceFee + record.clearanceFee,
                'driver_advance': parent.driverAdvance + record.driverAdvance,
                'updated_at': now,
                'sync_status': 'local',
              },
              where: 'id = ?',
              whereArgs: [parent.id],
            );
          }

          await txn.delete(
            'payment_transactions',
            where: 'customs_record_id = ?',
            whereArgs: [record.id],
          );
          await txn.delete(
            'pricing_history',
            where: 'customs_record_id = ?',
            whereArgs: [record.id],
          );
          await txn.delete(
            'customs_records',
            where: 'id = ?',
            whereArgs: [record.id],
          );

          continue;
        }

        await txn.update(
          'customs_records',
          {
            'beneficiary_merchant': null,
            'paid_amount': 0,
            'updated_at': now,
            'sync_status': 'local',
          },
          where: 'id = ?',
          whereArgs: [record.id],
        );
        await txn.delete(
          'payment_transactions',
          where: 'customs_record_id = ?',
          whereArgs: [record.id],
        );
      }
    });
  }

  Future<void> updateBeneficiaryMerchant({
    required String recordId,
    required String merchantName,
  }) async {
    final record = await getRecordById(recordId);

    if (record == null) {
      throw StateError('السطر غير موجود');
    }

    _ensurePricingExists(record);

    final db = await _appDatabase.database;

    await db.update(
      'customs_records',
      {
        'beneficiary_merchant': merchantName.trim(),
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': 'local',
      },
      where: 'id = ?',
      whereArgs: [recordId],
    );

    final updatedRecord = await getRecordById(recordId);
    if (updatedRecord != null) {
      await syncCustomsRecordChargeJournal(updatedRecord);
    }
  }

  Future<void> updateRecord({
    required CustomsRecord record,
    required String agentName,
    required String driverName,
    required String plateNumber,
    required double quantity,
    String? unit,
    double? unitPrice,
    double? clearanceFee,
    double? driverAdvance,
    String? merchantName,
  }) async {
    final cleanAgentName = _cleanName(agentName);
    final cleanDriverName = _cleanName(driverName);
    final cleanPlateNumber = _cleanName(plateNumber);
    final cleanUnit = unit == null ? null : _cleanName(unit);
    final cleanMerchantName =
        merchantName == null ? null : _cleanName(merchantName);

    if (cleanAgentName.isEmpty) {
      throw ArgumentError('اسم الوكيل مطلوب');
    }

    if (cleanDriverName.isEmpty) {
      throw ArgumentError('اسم السائق مطلوب');
    }

    if (cleanPlateNumber.isEmpty) {
      throw ArgumentError('رقم اللوحة مطلوب');
    }

    if (quantity <= 0) {
      throw ArgumentError('الكمية يجب أن تكون أكبر من صفر');
    }

    if (unitPrice != null && unitPrice < 0) {
      throw ArgumentError('سعر الوحدة لا يمكن أن يكون أقل من صفر');
    }

    if (clearanceFee != null && clearanceFee < 0) {
      throw ArgumentError('رسوم التخليص لا يمكن أن تكون أقل من صفر');
    }

    if (driverAdvance != null && driverAdvance < 0) {
      throw ArgumentError('سلفة السائق لا يمكن أن تكون أقل من صفر');
    }

    final effectiveUnit =
        cleanUnit == null || cleanUnit.isEmpty ? null : cleanUnit;
    final effectiveUnitPrice =
        unitPrice == null || unitPrice <= 0 ? null : unitPrice;
    final quantityChanged = quantity != record.quantity;
    final unitPriceChanged = effectiveUnitPrice != record.unitPrice;
    final shouldKeepManualCustomsAmount = record.customsAmountManualOverride &&
        !quantityChanged &&
        !unitPriceChanged;
    final calculatedCustomsAmount =
        (effectiveUnitPrice == null ? 0.0 : quantity * effectiveUnitPrice) +
            (record.radiologyFeeApplied ? 10000.0 : 0.0);
    final customsAmount = shouldKeepManualCustomsAmount
        ? record.customsAmount
        : calculatedCustomsAmount;
    final manualOverride = shouldKeepManualCustomsAmount ? 1 : 0;
    final effectiveMerchantName =
        cleanMerchantName == null || cleanMerchantName.isEmpty
            ? null
            : cleanMerchantName;
    final effectiveClearanceFee = clearanceFee ?? record.clearanceFee;
    final effectiveDriverAdvance = driverAdvance ?? record.driverAdvance;

    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.update(
        'customs_records',
        {
          'agent_name': cleanAgentName,
          'driver_name': cleanDriverName,
          'plate_number': cleanPlateNumber,
          'quantity': quantity,
          'pricing_unit': effectiveUnit,
          'unit_price': effectiveUnitPrice,
          'customs_amount': customsAmount,
          'clearance_fee': effectiveClearanceFee,
          'driver_advance': effectiveDriverAdvance,
          'customs_amount_manual_override': manualOverride,
          'beneficiary_merchant': effectiveMerchantName,
          'updated_at': now,
          'sync_status': 'local',
        },
        where: 'id = ?',
        whereArgs: [record.id],
      );

      if (effectiveUnit != null && effectiveUnitPrice != null) {
        await txn.insert('pricing_history', {
          'id': _uuid.v4(),
          'customs_record_id': record.id,
          'quantity': quantity,
          'unit': effectiveUnit,
          'unit_price': effectiveUnitPrice,
          'customs_amount': customsAmount,
          'created_at': now,
        });
      }
    });

    final updatedRecord = await getRecordById(record.id);
    if (updatedRecord != null) {
      await syncCustomsRecordChargeJournal(updatedRecord);
      final payments = await getPaymentsForRecord(record.id);
      for (final payment in payments) {
        await syncPaymentTransactionJournal(payment);
      }
    }
  }

  Future<void> updateCustomsRecordInline({
    required CustomsRecord record,
    String? agentName,
    String? driverName,
    String? plateNumber,
    double? quantity,
    String? pricingUnit,
    double? unitPrice,
    double? customsAmount,
    double? clearanceFee,
    double? driverAdvance,
    String? beneficiaryMerchant,
  }) async {
    final cleanAgentName = _cleanName(agentName ?? record.agentName);
    final cleanDriverName = _cleanName(driverName ?? record.driverName);
    final cleanPlateNumber = _cleanName(plateNumber ?? record.plateNumber);
    final cleanUnit =
        pricingUnit == null ? record.pricingUnit : _cleanName(pricingUnit);
    final cleanMerchantName = beneficiaryMerchant == null
        ? record.beneficiaryMerchant
        : _cleanName(beneficiaryMerchant);
    final effectiveQuantity = quantity ?? record.quantity;
    final effectiveUnitPrice = unitPrice ?? record.unitPrice;

    if (cleanAgentName.isEmpty) {
      throw ArgumentError('اسم الوكيل مطلوب');
    }

    if (cleanDriverName.isEmpty) {
      throw ArgumentError('اسم السائق مطلوب');
    }

    if (cleanPlateNumber.isEmpty) {
      throw ArgumentError('رقم اللوحة مطلوب');
    }

    if (effectiveQuantity <= 0) {
      throw ArgumentError('الكمية يجب أن تكون أكبر من صفر');
    }

    if (effectiveUnitPrice != null && effectiveUnitPrice <= 0) {
      throw ArgumentError('سعر الوحدة يجب أن يكون أكبر من صفر');
    }

    if (clearanceFee != null && clearanceFee < 0) {
      throw ArgumentError('رسوم التخليص لا يمكن أن تكون أقل من صفر');
    }

    if (driverAdvance != null && driverAdvance < 0) {
      throw ArgumentError('سلفة السائق لا يمكن أن تكون أقل من صفر');
    }

    final effectiveUnit =
        cleanUnit == null || cleanUnit.trim().isEmpty ? null : cleanUnit;
    final normalizedMerchant =
        cleanMerchantName == null || cleanMerchantName.trim().isEmpty
            ? null
            : cleanMerchantName;
    final quantityChanged = quantity != null && quantity != record.quantity;
    final unitPriceChanged = unitPrice != null && unitPrice != record.unitPrice;
    final shouldKeepManualCustomsAmount = record.customsAmountManualOverride &&
        customsAmount == null &&
        !quantityChanged &&
        !unitPriceChanged;
    final calculatedCustomsAmount = (effectiveUnitPrice == null
            ? 0.0
            : effectiveQuantity * effectiveUnitPrice) +
        (record.radiologyFeeApplied ? 10000.0 : 0.0);
    final effectiveCustomsAmount = customsAmount ??
        (shouldKeepManualCustomsAmount
            ? record.customsAmount
            : calculatedCustomsAmount);
    final effectiveClearanceFee = clearanceFee ?? record.clearanceFee;
    final effectiveDriverAdvance = driverAdvance ?? record.driverAdvance;
    final manualOverride =
        customsAmount != null || shouldKeepManualCustomsAmount ? 1 : 0;
    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.update(
        'customs_records',
        {
          'agent_name': cleanAgentName,
          'driver_name': cleanDriverName,
          'plate_number': cleanPlateNumber,
          'quantity': effectiveQuantity,
          'pricing_unit': effectiveUnit,
          'unit_price': effectiveUnitPrice,
          'customs_amount': effectiveCustomsAmount,
          'clearance_fee': effectiveClearanceFee,
          'driver_advance': effectiveDriverAdvance,
          'customs_amount_manual_override': manualOverride,
          'beneficiary_merchant': normalizedMerchant,
          'updated_at': now,
          'sync_status': 'local',
        },
        where: 'id = ?',
        whereArgs: [record.id],
      );

      if (effectiveUnit != null && effectiveUnitPrice != null) {
        await txn.insert('pricing_history', {
          'id': _uuid.v4(),
          'customs_record_id': record.id,
          'quantity': effectiveQuantity,
          'unit': effectiveUnit,
          'unit_price': effectiveUnitPrice,
          'customs_amount': effectiveCustomsAmount,
          'created_at': now,
        });
      }
    });

    final updatedRecord = await getRecordById(record.id);
    if (updatedRecord != null) {
      await syncCustomsRecordChargeJournal(updatedRecord);
      final payments = await getPaymentsForRecord(record.id);
      for (final payment in payments) {
        await syncPaymentTransactionJournal(payment);
      }
    }
  }

  Future<double?> addRadiologyFeeToRecord(
    String recordId, {
    double amount = 10000,
  }) async {
    final db = await _appDatabase.database;
    final record = await getRecordById(recordId);
    if (record?.radiologyFeeApplied ?? false) {
      return null;
    }
    if (record == null) {
      throw StateError('لم يتم العثور على الحركة.');
    }

    final oldCustomsAmount = record.customsAmount;
    final newCustomsAmount = oldCustomsAmount + amount;
    final now = DateTime.now().toIso8601String();

    await db.update(
      'customs_records',
      {
        'customs_amount': newCustomsAmount,
        'radiology_fee_applied': 1,
        'customs_amount_manual_override': 1,
        'updated_at': now,
        'sync_status': 'local',
      },
      where: 'id = ?',
      whereArgs: [recordId],
    );

    final updatedRecord = await getRecordById(recordId);
    if (updatedRecord != null) {
      await syncCustomsRecordChargeJournal(updatedRecord);
    }

    return newCustomsAmount;
  }

  Future<void> deleteRecord(CustomsRecord record) async {
    final db = await _appDatabase.database;
    final blockReason = await getCustomsRecordDeleteBlockReason(record.id);
    if (blockReason != null) {
      throw StateError(blockReason);
    }

    final childCount = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM customs_records WHERE parent_record_id = ?',
            [record.id],
          ),
        ) ??
        0;

    if (childCount > 0) {
      throw StateError('لا يمكن حذف السطر الأصلي قبل حذف السطور التابعة له.');
    }

    await _deleteAccountingLinksForRecord(record.id);

    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      final latestRows = await txn.query(
        'customs_records',
        where: 'id = ?',
        whereArgs: [record.id],
        limit: 1,
      );

      if (latestRows.isEmpty) return;

      final latestRecord = CustomsRecord.fromMap(latestRows.first);
      final parentRecordId = latestRecord.parentRecordId;

      if (parentRecordId != null) {
        final parentRows = await txn.query(
          'customs_records',
          where: 'id = ?',
          whereArgs: [parentRecordId],
          limit: 1,
        );

        if (parentRows.isNotEmpty) {
          final parent = CustomsRecord.fromMap(parentRows.first);

          await txn.update(
            'customs_records',
            {
              'quantity': parent.quantity + latestRecord.quantity,
              'customs_amount':
                  parent.customsAmount + latestRecord.customsAmount,
              'clearance_fee': parent.clearanceFee + latestRecord.clearanceFee,
              'driver_advance':
                  parent.driverAdvance + latestRecord.driverAdvance,
              'updated_at': now,
              'sync_status': 'local',
            },
            where: 'id = ?',
            whereArgs: [parent.id],
          );
        }
      }

      await txn.delete(
        'payment_transactions',
        where: 'customs_record_id = ?',
        whereArgs: [latestRecord.id],
      );
      await txn.delete(
        'pricing_history',
        where: 'customs_record_id = ?',
        whereArgs: [latestRecord.id],
      );
      await txn.delete(
        'customs_records',
        where: 'id = ?',
        whereArgs: [latestRecord.id],
      );
    });

    final parentRecordId = record.parentRecordId;
    if (parentRecordId != null) {
      final parent = await getRecordById(parentRecordId);
      if (parent != null) {
        await syncCustomsRecordChargeJournal(parent);
      }
    }
  }

  Future<void> updatePaidAmount({
    required CustomsRecord record,
    required double paidAmount,
  }) async {
    if (paidAmount < 0) {
      throw ArgumentError('مبلغ السداد لا يمكن أن يكون أقل من صفر');
    }

    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    final existingPayments = await getPaymentsForRecord(record.id);
    for (final payment in existingPayments) {
      await deletePaymentTransactionJournal(payment.id);
    }
    final replacementPaymentId = _uuid.v4();

    await db.transaction((txn) async {
      await txn.delete(
        'payment_transactions',
        where: 'customs_record_id = ?',
        whereArgs: [record.id],
      );

      if (paidAmount > 0) {
        await txn.insert('payment_transactions', {
          'id': replacementPaymentId,
          'customs_record_id': record.id,
          'amount': paidAmount,
          'note': 'تعديل مبلغ السداد',
          'created_at': now,
        });
      }

      await _recalculatePaidAmountInTransaction(txn, record.id);
    });

    if (paidAmount > 0) {
      await syncPaymentTransactionJournal(
        PaymentTransaction(
          id: replacementPaymentId,
          customsRecordId: record.id,
          amount: paidAmount,
          note: 'تعديل مبلغ السداد',
          createdAt: DateTime.parse(now),
        ),
      );
    }
  }

  Future<void> updatePricing({
    required CustomsRecord record,
    required String unit,
    required double unitPrice,
  }) async {
    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    final customsAmount = record.quantity * unitPrice;

    await db.transaction((txn) async {
      await txn.update(
        'customs_records',
        {
          'pricing_unit': unit,
          'unit_price': unitPrice,
          'customs_amount': customsAmount,
          'paid_amount': record.paidAmount,
          'updated_at': now,
          'sync_status': 'local',
        },
        where: 'id = ?',
        whereArgs: [record.id],
      );

      await txn.insert('pricing_history', {
        'id': _uuid.v4(),
        'customs_record_id': record.id,
        'quantity': record.quantity,
        'unit': unit,
        'unit_price': unitPrice,
        'customs_amount': customsAmount,
        'created_at': now,
      });
    });

    final updatedRecord = await getRecordById(record.id);
    if (updatedRecord != null) {
      await syncCustomsRecordChargeJournal(updatedRecord);
    }
  }

  Future<void> splitQuantityForMerchant({
    required CustomsRecord record,
    required String merchantName,
    required double merchantQuantity,
  }) async {
    _ensurePricingExists(record);

    if (merchantName.trim().isEmpty) {
      throw ArgumentError('اسم التاجر مطلوب');
    }

    if (merchantQuantity <= 0) {
      throw ArgumentError('كمية التاجر يجب أن تكون أكبر من صفر');
    }

    if (merchantQuantity > record.quantity) {
      throw ArgumentError('كمية التاجر لا يمكن أن تكون أكبر من الكمية المتاحة');
    }

    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();

    final remainingQuantity = record.quantity - merchantQuantity;

    final merchantAmount = _calculateAmountForQuantity(
      record: record,
      quantity: merchantQuantity,
    );

    final remainingAmount = _calculateAmountForQuantity(
      record: record,
      quantity: remainingQuantity,
    );
    final merchantRatio = merchantQuantity / record.quantity;
    final merchantClearanceFee = record.clearanceFee * merchantRatio;
    final remainingClearanceFee = record.clearanceFee - merchantClearanceFee;
    final merchantDriverAdvance = record.driverAdvance * merchantRatio;
    final remainingDriverAdvance = record.driverAdvance - merchantDriverAdvance;
    String? newMerchantRecordId;

    await db.transaction((txn) async {
      if (remainingQuantity <= 0) {
        await txn.update(
          'customs_records',
          {
            'beneficiary_merchant': merchantName.trim(),
            'customs_amount': merchantAmount,
            'clearance_fee': record.clearanceFee,
            'driver_advance': record.driverAdvance,
            'paid_amount': record.paidAmount,
            'updated_at': now,
            'sync_status': 'local',
          },
          where: 'id = ?',
          whereArgs: [record.id],
        );

        return;
      }

      await txn.update(
        'customs_records',
        {
          'quantity': remainingQuantity,
          'customs_amount': remainingAmount,
          'clearance_fee': remainingClearanceFee,
          'driver_advance': remainingDriverAdvance,
          'paid_amount': record.paidAmount,
          'updated_at': now,
          'sync_status': 'local',
        },
        where: 'id = ?',
        whereArgs: [record.id],
      );

      final newRecordId = _uuid.v4();
      newMerchantRecordId = newRecordId;

      await txn.insert('customs_records', {
        'id': newRecordId,
        'request_id': record.requestId,
        'parent_record_id': record.id,
        'agent_name': record.agentName,
        'driver_name': record.driverName,
        'plate_number': record.plateNumber,
        'quantity': merchantQuantity,
        'customs_amount': merchantAmount,
        'clearance_fee': merchantClearanceFee,
        'driver_advance': merchantDriverAdvance,
        'paid_amount': 0,
        'beneficiary_merchant': merchantName.trim(),
        'pricing_unit': record.pricingUnit,
        'unit_price': record.unitPrice,
        'created_at': now,
        'updated_at': now,
        'display_order': record.displayOrder + 1,
        'sync_status': 'local',
        'server_id': null,
      });

      await txn.insert('pricing_history', {
        'id': _uuid.v4(),
        'customs_record_id': newRecordId,
        'quantity': merchantQuantity,
        'unit': record.pricingUnit!,
        'unit_price': record.unitPrice!,
        'customs_amount': merchantAmount,
        'created_at': now,
      });
    });

    final updatedOriginalRecord = await getRecordById(record.id);
    if (updatedOriginalRecord != null) {
      await syncCustomsRecordChargeJournal(updatedOriginalRecord);
    }

    final newRecordId = newMerchantRecordId;
    if (newRecordId != null) {
      final merchantRecord = await getRecordById(newRecordId);
      if (merchantRecord != null) {
        await syncCustomsRecordChargeJournal(merchantRecord);
      }
    }
  }

  Future<void> syncCustomsRecordChargeJournal(CustomsRecord record) async {
    final merchantName = record.beneficiaryMerchant?.trim();

    if (merchantName == null ||
        merchantName.isEmpty ||
        record.customsAmount <= 0) {
      await deleteCustomsRecordChargeJournal(record.id);
      return;
    }

    final merchantAccount =
        await _accountingRepository.getOrCreateMerchantAccount(merchantName);
    final customsPayableAccount =
        await _accountingRepository.getCustomsPayableAccount();

    await _accountingRepository.createOrReplaceAutoJournalEntry(
      sourceType: 'customs_record_charge',
      sourceId: record.id,
      entryDate: record.updatedAt,
      description:
          'إثبات جمارك على التاجر: $merchantName / الوكيل: ${record.agentName}',
      lines: [
        JournalLineInput(
          accountId: merchantAccount.id,
          debit: record.customsAmount,
          credit: 0,
        ),
        JournalLineInput(
          accountId: customsPayableAccount.id,
          debit: 0,
          credit: record.customsAmount,
        ),
      ],
    );
  }

  Future<void> deleteCustomsRecordChargeJournal(String customsRecordId) async {
    await _accountingRepository.deleteJournalEntryBySource(
      'customs_record_charge',
      customsRecordId,
    );
  }

  Future<void> syncPaymentTransactionJournal(
    PaymentTransaction payment,
  ) async {
    final record = await getRecordById(payment.customsRecordId);
    if (record == null) {
      await deletePaymentTransactionJournal(payment.id);
      return;
    }

    final merchantName = record.beneficiaryMerchant?.trim();
    if (merchantName == null || merchantName.isEmpty || payment.amount <= 0) {
      // The payment stays valid, but accounting cannot be posted without a merchant.
      developer.log(
        'لا يمكن إنشاء قيد سداد بدون تاجر: ${payment.id}',
        name: 'CustomsRepository',
      );
      await deletePaymentTransactionJournal(payment.id);
      return;
    }

    final cashAccount = await _cashAccount();
    final merchantAccount =
        await _accountingRepository.getOrCreateMerchantAccount(merchantName);

    await _accountingRepository.createOrReplaceAutoJournalEntry(
      sourceType: 'payment_transaction',
      sourceId: payment.id,
      entryDate: payment.createdAt,
      description:
          'سداد من التاجر: $merchantName / الوكيل: ${record.agentName}',
      lines: [
        JournalLineInput(
          accountId: cashAccount.id,
          debit: payment.amount,
          credit: 0,
        ),
        JournalLineInput(
          accountId: merchantAccount.id,
          debit: 0,
          credit: payment.amount,
        ),
      ],
    );
  }

  Future<void> deletePaymentTransactionJournal(
    String paymentTransactionId,
  ) async {
    await _accountingRepository.deleteJournalEntryBySource(
      'payment_transaction',
      paymentTransactionId,
    );
  }

  Future<void> resyncPaymentTransactionJournals() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'payment_transactions',
      orderBy: 'created_at ASC, id ASC',
    );

    for (final row in rows) {
      await syncPaymentTransactionJournal(PaymentTransaction.fromMap(row));
    }
  }

  Future<void> syncAutomaticAccountingJournals() async {
    final records = await getRecords();

    for (final record in records) {
      await syncCustomsRecordChargeJournal(record);

      final payments = await getPaymentsForRecord(record.id);
      for (final payment in payments) {
        await syncPaymentTransactionJournal(payment);
      }
    }
  }

  void _ensurePricingExists(CustomsRecord record) {
    final hasUnit =
        record.pricingUnit != null && record.pricingUnit!.trim().isNotEmpty;

    final hasUnitPrice = record.unitPrice != null && record.unitPrice! > 0;

    final hasAmount = record.customsAmount > 0;

    if (!(hasUnit && hasUnitPrice && hasAmount)) {
      throw StateError(
        'يجب إضافة التسعير الجمركي أولاً قبل إضافة التاجر أو توزيع الكمية',
      );
    }
  }

  double _calculateAmountForQuantity({
    required CustomsRecord record,
    required double quantity,
  }) {
    if (quantity <= 0) return 0;

    if (record.unitPrice != null && record.unitPrice! > 0) {
      return quantity * record.unitPrice!;
    }

    return 0;
  }

  Future<List<CustomsRecord>> _getRecordsInTransaction(
    DatabaseExecutor txn,
  ) async {
    final rows = await txn.query('customs_records');

    return rows.map(CustomsRecord.fromMap).toList();
  }

  Future<double> _sumPaymentsInTransaction(
    DatabaseExecutor txn,
    String customsRecordId,
  ) async {
    final result = await txn.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM payment_transactions
      WHERE customs_record_id = ?
      ''',
      [customsRecordId],
    );

    return (result.first['total'] as num).toDouble();
  }

  Future<void> _recalculatePaidAmountInTransaction(
    DatabaseExecutor txn,
    String customsRecordId,
  ) async {
    final total = await _sumPaymentsInTransaction(txn, customsRecordId);
    final rows = await txn.query(
      'customs_records',
      columns: ['paid_amount'],
      where: 'id = ?',
      whereArgs: [customsRecordId],
      limit: 1,
    );

    if (rows.isEmpty) return;

    final current = (rows.first['paid_amount'] as num?)?.toDouble() ?? 0;
    if ((current - total).abs() <= 0.01) return;

    await txn.update(
      'customs_records',
      {
        'paid_amount': total,
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': 'local',
      },
      where: 'id = ?',
      whereArgs: [customsRecordId],
    );
  }

  Future<void> _deleteAccountingLinksForRecord(String customsRecordId) async {
    final payments = await getPaymentsForRecord(customsRecordId);

    for (final payment in payments) {
      await deletePaymentTransactionJournal(payment.id);
    }

    await deleteCustomsRecordChargeJournal(customsRecordId);
  }

  Future<Account> _cashAccount() async {
    return _accountingRepository.getCashAccount();
  }

  Future<Account?> _findMerchantAccountByName(String merchantName) async {
    final wantedName = _normalizeName(merchantName);
    if (wantedName.isEmpty) return null;

    final accounts = await _accountingRepository.getAccounts();
    Account? debtorsParent;
    try {
      debtorsParent = await _accountingRepository.getDebtorsParentAccount();
    } catch (_) {
      debtorsParent = null;
    }

    for (final account in accounts) {
      final isDebtorChild = debtorsParent == null
          ? account.code.startsWith('1100-')
          : account.parentId == debtorsParent.id ||
              account.code.startsWith('${debtorsParent.code}-');
      if (!isDebtorChild) continue;

      if (_normalizeName(account.name) == wantedName) {
        return account;
      }
    }

    return null;
  }

  static String _cleanName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _normalizeName(String value) {
    return _cleanName(value).toLowerCase();
  }

  static String _paymentStatusLabel(double customsAmount, double paidAmount) {
    const tolerance = 0.01;
    if (customsAmount <= tolerance) {
      return paidAmount > tolerance ? 'credit' : 'missingPricing';
    }
    if (paidAmount <= tolerance) return 'unpaid';
    if (paidAmount + tolerance < customsAmount) return 'partial';
    if ((paidAmount - customsAmount).abs() <= tolerance) return 'paid';
    return 'credit';
  }
}

class AccountContact {
  const AccountContact({
    required this.id,
    required this.accountType,
    required this.accountName,
    this.phone,
    this.whatsapp,
    required this.whatsappSameAsPhone,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String accountType;
  final String accountName;
  final String? phone;
  final String? whatsapp;
  final bool whatsappSameAsPhone;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AccountContact.fromMap(Map<String, Object?> map) {
    return AccountContact(
      id: map['id'] as String,
      accountType: map['account_type'] as String,
      accountName: map['account_name'] as String,
      phone: map['phone'] as String?,
      whatsapp: map['whatsapp'] as String?,
      whatsappSameAsPhone:
          ((map['whatsapp_same_as_phone'] as num?)?.toInt() ?? 1) == 1,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
