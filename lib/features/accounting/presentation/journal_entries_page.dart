import 'package:flutter/material.dart';

import '../../customs/data/customs_repository.dart';
import '../data/accounting_repository.dart';
import '../domain/journal_entry.dart';
import 'journal_entry_form_page.dart';

class JournalEntriesPage extends StatefulWidget {
  const JournalEntriesPage({super.key});

  @override
  State<JournalEntriesPage> createState() => _JournalEntriesPageState();
}

class _JournalEntriesPageState extends State<JournalEntriesPage> {
  final _repository = AccountingRepository();
  final _customsRepository = CustomsRepository();

  late Future<List<JournalEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadEntries();
  }

  void _reload() {
    setState(() {
      _future = _loadEntries();
    });
  }

  Future<List<JournalEntry>> _loadEntries() async {
    await _customsRepository.resyncPaymentTransactionJournals();
    return _repository.getJournalEntries();
  }

  String _money(double value) => value.toStringAsFixed(2);

  String _date(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');

    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  Future<void> _openForm() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const JournalEntryFormPage(),
      ),
    );

    if (saved == true) {
      await _customsRepository.resyncPaymentsAndPaidAmounts();
      if (!mounted) return;
      _reload();
    }
  }

  Future<void> _deleteEntry(JournalEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('حذف القيد'),
          content: Text('هل تريد حذف القيد: ${entry.description}؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    if (entry.sourceType == 'payment_transaction' && entry.sourceId != null) {
      await _customsRepository.deletePaymentById(entry.sourceId!);
    } else {
      await _repository.deleteJournalEntry(entry.id);
    }
    if (!mounted) return;
    _reload();
  }

  Future<void> _editPaymentEntry(JournalEntry entry) async {
    final paymentId = entry.sourceId;
    if (entry.sourceType != 'payment_transaction' || paymentId == null) {
      return;
    }

    final payment = await _customsRepository.getPaymentById(paymentId);
    if (!mounted) return;
    if (payment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('دفعة السداد غير موجودة')),
      );
      return;
    }

    final amountController = TextEditingController(
      text: payment.amount.toStringAsFixed(2),
    );
    final noteController = TextEditingController(text: payment.note ?? '');

    final result = await showDialog<_PaymentEditResult>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تعديل سداد التخليص'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'مبلغ السداد',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(
                      amountController.text.trim().replaceAll(',', ''),
                    ) ??
                    0;
                Navigator.pop(
                  context,
                  _PaymentEditResult(
                    amount: amount,
                    note: noteController.text,
                  ),
                );
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );

    amountController.dispose();
    noteController.dispose();

    if (result == null) return;
    if (result.amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مبلغ سداد أكبر من صفر')),
      );
      return;
    }

    await _customsRepository.updatePayment(
      paymentId: paymentId,
      amount: result.amount,
      note: result.note,
    );
    if (!mounted) return;
    _reload();
  }

  Widget _entryCard(JournalEntry entry) {
    final isClearancePayment = entry.sourceType == 'payment_transaction';
    return Card(
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                entry.description,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (isClearancePayment)
              const Padding(
                padding: EdgeInsetsDirectional.only(start: 8),
                child: Chip(
                  label: Text('سداد تخليص'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${_date(entry.entryDate)} - مدين ${_money(entry.totalDebit)} / دائن ${_money(entry.totalCredit)}',
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            if (isClearancePayment)
              IconButton(
                tooltip: 'تعديل سداد التخليص',
                onPressed: () => _editPaymentEntry(entry),
                icon: const Icon(Icons.edit_outlined),
              ),
            IconButton(
              tooltip: 'حذف',
              onPressed: () => _deleteEntry(entry),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('الحساب')),
                DataColumn(label: Text('مدين')),
                DataColumn(label: Text('دائن')),
                DataColumn(label: Text('ملاحظة')),
              ],
              rows: entry.lines.map((line) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                          '${line.accountCode ?? ''} ${line.accountName ?? ''}'),
                    ),
                    DataCell(Text(_money(line.debit))),
                    DataCell(Text(_money(line.credit))),
                    DataCell(Text(line.note ?? '-')),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('القيود اليومية'),
          centerTitle: true,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openForm,
          icon: const Icon(Icons.add),
          label: const Text('قيد'),
        ),
        body: FutureBuilder<List<JournalEntry>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final entries = snapshot.data ?? [];

            if (entries.isEmpty) {
              return const Center(child: Text('لا توجد قيود يومية'));
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _entryCard(entries[index]),
            );
          },
        ),
      ),
    );
  }
}

class _PaymentEditResult {
  const _PaymentEditResult({
    required this.amount,
    required this.note,
  });

  final double amount;
  final String note;
}
