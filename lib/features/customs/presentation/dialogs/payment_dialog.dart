import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/customs_repository.dart';
import '../../domain/customs_record.dart';
import '../../domain/payment_transaction.dart';

Future<bool?> showPaymentDialog(
  BuildContext context, {
  required CustomsRecord record,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return _PaymentDialog(record: record);
    },
  );
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.record,
  });

  final CustomsRecord record;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _repository = CustomsRepository();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  late Future<List<PaymentTransaction>> _future;

  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _future = _loadPayments();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<List<PaymentTransaction>> _loadPayments() {
    return _repository.getPaymentsForRecord(widget.record.id);
  }

  void _reload() {
    setState(() {
      _future = _loadPayments();
    });
  }

  String _money(double value) => value.toStringAsFixed(2);

  String _formatDate(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');

    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  double _totalPaid(List<PaymentTransaction> payments) {
    return payments.fold(0, (sum, payment) => sum + payment.amount);
  }

  Future<void> _addPayment() async {
    final text = _amountController.text.trim().replaceAll(',', '');
    final amount = double.tryParse(text);

    if (amount == null || amount <= 0) {
      setState(() {
        _error = 'أدخل مبلغ سداد أكبر من صفر';
      });
      return;
    }

    try {
      await _repository.addPayment(
        record: widget.record,
        amount: amount,
        note: _noteController.text,
      );

      _amountController.clear();
      _noteController.clear();

      if (!mounted) return;

      setState(() {
        _error = null;
        _changed = true;
      });
      _reload();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
      });
    }
  }

  Future<void> _deletePayment(PaymentTransaction payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('حذف دفعة'),
          content: Text('هل تريد حذف دفعة بقيمة ${_money(payment.amount)}؟'),
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

    try {
      await _repository.deletePayment(
        paymentId: payment.id,
        customsRecordId: widget.record.id,
      );

      if (!mounted) return;

      setState(() {
        _error = null;
        _changed = true;
      });
      _reload();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
      });
    }
  }

  Widget _paymentsList(List<PaymentTransaction> payments) {
    if (payments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('لا توجد دفعات مسجلة'),
      );
    }

    return SizedBox(
      height: 180,
      child: ListView.separated(
        itemCount: payments.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final payment = payments[index];
          final note = payment.note?.trim();

          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              _money(payment.amount),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              note == null || note.isEmpty
                  ? _formatDate(payment.createdAt)
                  : '${_formatDate(payment.createdAt)} - $note',
            ),
            trailing: IconButton(
              tooltip: 'حذف الدفعة',
              onPressed: () => _deletePayment(payment),
              icon: const Icon(Icons.delete_outline),
            ),
          );
        },
      ),
    );
  }

  Widget _summary(List<PaymentTransaction> payments) {
    final totalPaid = _totalPaid(payments);
    final balance = widget.record.customsAmount - totalPaid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'إجمالي السداد: ${_money(totalPaid)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(
          'مبلغ الجمارك: ${_money(widget.record.customsAmount)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(
          'الرصيد: ${_money(balance)}',
          style: TextStyle(
            color: balance < 0 ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _changed);
      },
      child: AlertDialog(
        title: const Text('سجل حركات السداد'),
        content: SizedBox(
          width: 520,
          child: FutureBuilder<List<PaymentTransaction>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final payments = snapshot.data ?? [];

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _paymentsList(payments),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'مبلغ الدفعة الجديدة',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظة اختيارية',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _addPayment,
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة دفعة'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _summary(payments),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, _changed),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
