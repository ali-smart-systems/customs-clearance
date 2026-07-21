import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../customs/data/customs_repository.dart';
import '../../customs/domain/customs_record.dart';
import '../data/accounting_repository.dart';
import '../domain/account.dart';

class JournalEntryFormPage extends StatefulWidget {
  const JournalEntryFormPage({super.key});

  @override
  State<JournalEntryFormPage> createState() => _JournalEntryFormPageState();
}

class _JournalEntryFormPageState extends State<JournalEntryFormPage> {
  final _repository = AccountingRepository();
  final _customsRepository = CustomsRepository();
  final _descriptionController = TextEditingController();
  final _paymentAmountController = TextEditingController();
  final _paymentNoteController = TextEditingController();
  final List<_LineDraft> _lines = [_LineDraft(), _LineDraft()];

  late Future<List<Account>> _accountsFuture;
  late Future<List<CustomsRecord>> _recordsFuture;
  DateTime _entryDate = DateTime.now();
  _JournalFormMode _mode = _JournalFormMode.manual;
  String? _selectedMerchant;
  String? _selectedRecordId;

  @override
  void initState() {
    super.initState();
    _accountsFuture = _repository.getAccounts(activeOnly: true);
    _recordsFuture = _customsRepository.getRecords();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _paymentAmountController.dispose();
    _paymentNoteController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  String _money(double value) => value.toStringAsFixed(2);

  double _parse(TextEditingController controller) {
    return double.tryParse(controller.text.trim().replaceAll(',', '')) ?? 0;
  }

  double get _totalDebit {
    return _lines.fold(0, (sum, line) => sum + _parse(line.debitController));
  }

  double get _totalCredit {
    return _lines.fold(0, (sum, line) => sum + _parse(line.creditController));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _entryDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() => _entryDate = picked);
  }

  void _addLine() {
    setState(() {
      _lines.add(_LineDraft());
    });
  }

  void _removeLine(int index) {
    if (_lines.length <= 2) return;

    setState(() {
      _lines.removeAt(index).dispose();
    });
  }

  Future<void> _save() async {
    if (_mode == _JournalFormMode.clearancePayment) {
      await _saveClearancePayment();
      return;
    }

    try {
      await _repository.createJournalEntry(
        entryDate: _entryDate,
        description: _descriptionController.text,
        lines: _lines.map((line) {
          return JournalLineInput(
            accountId: line.accountId ?? '',
            debit: _parse(line.debitController),
            credit: _parse(line.creditController),
            note: line.noteController.text,
          );
        }).toList(),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _saveClearancePayment() async {
    final recordId = _selectedRecordId;
    final amount = double.tryParse(
          _paymentAmountController.text.trim().replaceAll(',', ''),
        ) ??
        0;

    if (recordId == null || recordId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر عملية التخليص')),
      );
      return;
    }

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مبلغ سداد أكبر من صفر')),
      );
      return;
    }

    try {
      final beforeRecord = await _customsRepository.getRecordById(recordId);
      final beforePaidAmount = beforeRecord?.paidAmount ?? 0;
      debugPrint(
        'ClearancePayment save start: selectedRecordId=$recordId, '
        'selectedMerchantName=$_selectedMerchant, '
        'amount=$amount, '
        'paidAmountBefore=$beforePaidAmount',
      );

      final payment = await _customsRepository.addPaymentForRecordId(
        customsRecordId: recordId,
        amount: amount,
        note: _paymentNoteController.text,
      );
      final afterRecord = await _customsRepository.getRecordById(recordId);
      debugPrint(
        'ClearancePayment save done: selectedRecordId=$recordId, '
        'selectedMerchantName=$_selectedMerchant, '
        'amount=$amount, '
        'paymentTransactionId=${payment.id}, '
        'paidAmountBefore=$beforePaidAmount, '
        'paidAmountAfter=${afterRecord?.paidAmount}',
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  String _date(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');

    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  Widget _lineEditor(
    List<Account> accounts,
    _LineDraft line,
    int index,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: line.accountId,
                    decoration: const InputDecoration(
                      labelText: 'الحساب',
                      border: OutlineInputBorder(),
                    ),
                    items: accounts.map((account) {
                      return DropdownMenuItem(
                        value: account.id,
                        child: Text(account.displayName),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => line.accountId = value);
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'حذف السطر',
                  onPressed:
                      _lines.length <= 2 ? null : () => _removeLine(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: line.debitController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'مدين',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: line.creditController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'دائن',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: line.noteController,
              decoration: const InputDecoration(
                labelText: 'ملاحظة',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _merchants(List<CustomsRecord> records) {
    return records
        .map((record) => record.beneficiaryMerchant?.trim())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  List<CustomsRecord> _recordsForSelectedMerchant(List<CustomsRecord> records) {
    final merchant = _selectedMerchant;
    if (merchant == null || merchant.isEmpty) return const [];

    return records.where((record) {
      return record.beneficiaryMerchant?.trim() == merchant;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  String _recordLabel(CustomsRecord record) {
    final balance = record.customsAmount - record.paidAmount;
    return '${_date(record.createdAt)} - ${record.agentName} - ${record.driverName} - ${record.plateNumber} - المتبقي ${_money(balance)}';
  }

  Widget _modeSelector() {
    return SegmentedButton<_JournalFormMode>(
      segments: const [
        ButtonSegment(
          value: _JournalFormMode.manual,
          label: Text('قيد يدوي'),
          icon: Icon(Icons.edit_note),
        ),
        ButtonSegment(
          value: _JournalFormMode.clearancePayment,
          label: Text('سداد عملية تخليص'),
          icon: Icon(Icons.payments_outlined),
        ),
      ],
      selected: {_mode},
      onSelectionChanged: (values) {
        setState(() {
          _mode = values.first;
        });
      },
    );
  }

  Widget _clearancePaymentForm(List<CustomsRecord> records) {
    final merchants = _merchants(records);
    final merchantRecords = _recordsForSelectedMerchant(records);

    if (_selectedMerchant != null && !merchants.contains(_selectedMerchant)) {
      _selectedMerchant = null;
      _selectedRecordId = null;
    }
    if (_selectedRecordId != null &&
        !merchantRecords.any((record) => record.id == _selectedRecordId)) {
      _selectedRecordId = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedMerchant,
          decoration: const InputDecoration(
            labelText: 'التاجر',
            border: OutlineInputBorder(),
          ),
          items: merchants.map((merchant) {
            return DropdownMenuItem(
              value: merchant,
              child: Text(merchant),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedMerchant = value;
              _selectedRecordId = null;
            });
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedRecordId,
          decoration: const InputDecoration(
            labelText: 'عملية التخليص',
            border: OutlineInputBorder(),
          ),
          items: merchantRecords.map((record) {
            return DropdownMenuItem(
              value: record.id,
              child: Text(_recordLabel(record)),
            );
          }).toList(),
          onChanged: (value) => setState(() => _selectedRecordId = value),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _paymentAmountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: const InputDecoration(
            labelText: 'مبلغ السداد',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _paymentNoteController,
          decoration: const InputDecoration(
            labelText: 'ملاحظة اختيارية',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saveClearancePayment,
          icon: const Icon(Icons.save),
          label: const Text('حفظ سداد التخليص'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إضافة قيد يومي'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'حفظ',
              onPressed: _save,
              icon: const Icon(Icons.save),
            ),
          ],
        ),
        body: FutureBuilder<List<Account>>(
          future: _accountsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final accounts = snapshot.data ?? [];

            if (accounts.isEmpty) {
              return const Center(child: Text('أضف حسابات أولاً'));
            }

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _modeSelector(),
                if (_mode == _JournalFormMode.clearancePayment) ...[
                  const SizedBox(height: 12),
                  FutureBuilder<List<CustomsRecord>>(
                    future: _recordsFuture,
                    builder: (context, recordsSnapshot) {
                      if (recordsSnapshot.connectionState !=
                          ConnectionState.done) {
                        return const SizedBox(
                          height: 160,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final records = recordsSnapshot.data ?? [];
                      if (records.isEmpty) {
                        return const Card(
                          child: ListTile(
                            leading: Icon(Icons.info_outline),
                            title: Text('لا توجد عمليات تخليص متاحة للسداد'),
                          ),
                        );
                      }

                      return _clearancePaymentForm(records);
                    },
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text('تاريخ القيد: ${_date(_entryDate)}'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'وصف القيد',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ..._lines.asMap().entries.map(
                      (entry) => _lineEditor(accounts, entry.value, entry.key),
                    ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _addLine,
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة سطر'),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        Text('إجمالي المدين: ${_money(_totalDebit)}'),
                        Text('إجمالي الدائن: ${_money(_totalCredit)}'),
                        Text(
                          'الفرق: ${_money((_totalDebit - _totalCredit).abs())}',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('حفظ القيد'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LineDraft {
  String? accountId;
  final debitController = TextEditingController();
  final creditController = TextEditingController();
  final noteController = TextEditingController();

  void dispose() {
    debitController.dispose();
    creditController.dispose();
    noteController.dispose();
  }
}

enum _JournalFormMode {
  manual,
  clearancePayment,
}
