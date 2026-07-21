import 'package:flutter/material.dart';

import '../data/accounting_repository.dart';

class TrialBalancePage extends StatefulWidget {
  const TrialBalancePage({super.key});

  @override
  State<TrialBalancePage> createState() => _TrialBalancePageState();
}

class _TrialBalancePageState extends State<TrialBalancePage> {
  final _repository = AccountingRepository();

  late Future<List<TrialBalanceRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.getTrialBalanceRows();
  }

  String _money(double value) => value.toStringAsFixed(2);

  double _totalDebit(List<TrialBalanceRow> rows) {
    return rows
        .where((row) => !row.isChild)
        .fold(0, (sum, row) => sum + row.debit);
  }

  double _totalCredit(List<TrialBalanceRow> rows) {
    return rows
        .where((row) => !row.isChild)
        .fold(0, (sum, row) => sum + row.credit);
  }

  double _totalClosingDebit(List<TrialBalanceRow> rows) {
    return rows
        .where((row) => !row.isChild)
        .fold(0, (sum, row) => sum + row.closingDebit);
  }

  double _totalClosingCredit(List<TrialBalanceRow> rows) {
    return rows
        .where((row) => !row.isChild)
        .fold(0, (sum, row) => sum + row.closingCredit);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ميزان المراجعة'),
          centerTitle: true,
        ),
        body: FutureBuilder<List<TrialBalanceRow>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final rows = snapshot.data ?? [];

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        Text(
                          'حركات مدينة: ${_money(_totalDebit(rows))}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'حركات دائنة: ${_money(_totalCredit(rows))}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'أرصدة مدينة: ${_money(_totalClosingDebit(rows))}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'أرصدة دائنة: ${_money(_totalClosingCredit(rows))}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('الكود')),
                      DataColumn(label: Text('الحساب')),
                      DataColumn(label: Text('النوع')),
                      DataColumn(label: Text('حركة مدينة')),
                      DataColumn(label: Text('حركة دائنة')),
                      DataColumn(label: Text('رصيد مدين')),
                      DataColumn(label: Text('رصيد دائن')),
                    ],
                    rows: rows.map((row) {
                      return DataRow(
                        cells: [
                          DataCell(Text(row.code)),
                          DataCell(
                            Text(
                              row.isChild ? '↳ ${row.name}' : row.name,
                              style: TextStyle(
                                fontWeight: row.isParentTotal
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          DataCell(Text(row.type)),
                          DataCell(Text(_money(row.debit))),
                          DataCell(Text(_money(row.credit))),
                          DataCell(Text(_money(row.closingDebit))),
                          DataCell(Text(_money(row.closingCredit))),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
