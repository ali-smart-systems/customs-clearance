import 'package:flutter/material.dart';

import '../data/accounting_repository.dart';
import '../domain/account.dart';

class AccountLedgerPage extends StatefulWidget {
  const AccountLedgerPage({super.key});

  @override
  State<AccountLedgerPage> createState() => _AccountLedgerPageState();
}

class _AccountLedgerPageState extends State<AccountLedgerPage> {
  final _repository = AccountingRepository();

  late Future<List<Account>> _accountsFuture;
  Future<List<LedgerRow>>? _ledgerFuture;
  String? _accountId;

  @override
  void initState() {
    super.initState();
    _accountsFuture = _repository.getAccounts();
  }

  String _money(double value) => value.toStringAsFixed(2);

  String _date(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');

    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  void _selectAccount(String? value) {
    if (value == null) return;

    setState(() {
      _accountId = value;
      _ledgerFuture = _repository.getLedgerRows(value);
    });
  }

  Widget _table(List<LedgerRow> rows) {
    if (rows.isEmpty) {
      return const Center(child: Text('لا توجد حركات لهذا الحساب'));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('التاريخ')),
          DataColumn(label: Text('الحساب')),
          DataColumn(label: Text('الوصف')),
          DataColumn(label: Text('مدين')),
          DataColumn(label: Text('دائن')),
          DataColumn(label: Text('الرصيد')),
          DataColumn(label: Text('ملاحظة')),
        ],
        rows: rows.map((row) {
          return DataRow(
            cells: [
              DataCell(Text(_date(row.entryDate))),
              DataCell(
                Text('${row.accountCode ?? '-'} - ${row.accountName ?? '-'}'),
              ),
              DataCell(Text(row.description)),
              DataCell(Text(_money(row.debit))),
              DataCell(Text(_money(row.credit))),
              DataCell(Text(_money(row.balance))),
              DataCell(Text(row.note ?? '-')),
            ],
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('دفتر الأستاذ'),
          centerTitle: true,
        ),
        body: FutureBuilder<List<Account>>(
          future: _accountsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final accounts = snapshot.data ?? [];

            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _accountId,
                    decoration: const InputDecoration(
                      labelText: 'اختر الحساب',
                      border: OutlineInputBorder(),
                    ),
                    items: accounts.map((account) {
                      return DropdownMenuItem(
                        value: account.id,
                        child: Text(account.displayName),
                      );
                    }).toList(),
                    onChanged: _selectAccount,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _ledgerFuture == null
                        ? const Center(child: Text('اختر حساباً لعرض الأستاذ'))
                        : FutureBuilder<List<LedgerRow>>(
                            future: _ledgerFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState !=
                                  ConnectionState.done) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              return _table(snapshot.data ?? []);
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
