import 'package:flutter/material.dart';

import '../../customs/data/customs_repository.dart';
import '../../customs/domain/customs_record.dart';
import '../../customs/presentation/dialogs/edit_name_dialog.dart';
import '../../customs/presentation/dialogs/payment_dialog.dart';

class MerchantDetailsPage extends StatefulWidget {
  const MerchantDetailsPage({
    super.key,
    required this.merchantName,
  });

  final String merchantName;

  @override
  State<MerchantDetailsPage> createState() => _MerchantDetailsPageState();
}

class _MerchantDetailsPageState extends State<MerchantDetailsPage> {
  final _repository = CustomsRepository();
  final _horizontalScrollController = ScrollController();

  late Future<List<CustomsRecord>> _future;
  late String _merchantName;

  @override
  void initState() {
    super.initState();
    _merchantName = widget.merchantName;
    _future = _loadRecords();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  Future<List<CustomsRecord>> _loadRecords() {
    return _repository.getRecordsByMerchantName(_merchantName);
  }

  void _reload() {
    setState(() {
      _future = _loadRecords();
    });
  }

  Future<void> _editPayment(CustomsRecord record) async {
    final changed = await showPaymentDialog(
      context,
      record: record,
    );

    if (changed != true) return;

    if (!mounted) return;
    _reload();
  }

  Future<void> _renameMerchant() async {
    final newName = await showEditNameDialog(
      context,
      title: 'تعديل اسم التاجر',
      currentName: _merchantName,
      labelText: 'اسم التاجر',
    );

    if (newName == null) return;

    try {
      await _repository.renameMerchant(_merchantName, newName);

      if (!mounted) return;

      setState(() {
        _merchantName = newName;
        _future = _loadRecords();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تعديل اسم التاجر')),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _deleteMerchant() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('حذف التاجر'),
          content: const Text(
            'سيتم إزالة ارتباط هذا التاجر من السجلات. هل أنت متأكد؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _repository.deleteMerchant(_merchantName);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف ارتباط التاجر')),
      );

      _reload();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toString();
  }

  String _money(double value) {
    return value.toStringAsFixed(2);
  }

  String _formatDate(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');

    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  String _empty(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '-';
    }

    return value;
  }

  DataCell _cell(String value) {
    return DataCell(
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  DataCell _paymentCell(CustomsRecord record) {
    return DataCell(
      InkWell(
        onTap: () => _editPayment(record),
        child: Text(
          record.paidAmount <= 0 ? 'اضغط للسداد' : _money(record.paidAmount),
          style: TextStyle(
            color: record.paidAmount <= 0 ? Colors.blue : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  DataCell _balanceCell(double balance) {
    return DataCell(
      Text(
        _money(balance),
        style: TextStyle(
          color: balance <= 0 ? Colors.green : Colors.red,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  DataRow _buildRow(CustomsRecord record, double runningBalance) {
    return DataRow(
      cells: [
        _cell(_formatDate(record.createdAt)),
        _cell(record.beneficiaryMerchant ?? _merchantName),
        _cell(record.agentName),
        _cell(record.driverName),
        _cell(record.plateNumber),
        _cell(_formatNumber(record.quantity)),
        _cell(_empty(record.pricingUnit)),
        _cell(record.unitPrice == null ? '-' : _money(record.unitPrice!)),
        _cell(_money(record.customsAmount)),
        _paymentCell(record),
        _balanceCell(runningBalance),
      ],
    );
  }

  List<DataRow> _buildRows(List<CustomsRecord> records) {
    var runningBalance = 0.0;

    return records.map((record) {
      runningBalance += record.customsAmount - record.paidAmount;
      return _buildRow(record, runningBalance);
    }).toList();
  }

  Widget _buildTable(List<CustomsRecord> records) {
    return Scrollbar(
      controller: _horizontalScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _horizontalScrollController,
        scrollDirection: Axis.horizontal,
        child: DataTable(
          border: TableBorder.all(
            color: Colors.black26,
            width: 1,
          ),
          headingRowColor: WidgetStateProperty.all(
            const Color(0xFFE3F2FD),
          ),
          columns: const [
            DataColumn(label: Text('التاريخ')),
            DataColumn(label: Text('اسم التاجر')),
            DataColumn(label: Text('اسم الوكيل')),
            DataColumn(label: Text('اسم السائق')),
            DataColumn(label: Text('رقم اللوحة')),
            DataColumn(label: Text('الكمية')),
            DataColumn(label: Text('الوحدة')),
            DataColumn(label: Text('سعر الوحدة')),
            DataColumn(label: Text('مبلغ الجمارك')),
            DataColumn(label: Text('مبلغ السداد')),
            DataColumn(label: Text('الرصيد')),
          ],
          rows: _buildRows(records),
        ),
      ),
    );
  }

  double _totalQuantity(List<CustomsRecord> records) {
    return records.fold(0, (sum, record) => sum + record.quantity);
  }

  double _totalAmount(List<CustomsRecord> records) {
    return records.fold(0, (sum, record) => sum + record.customsAmount);
  }

  double _totalPaid(List<CustomsRecord> records) {
    return records.fold(0, (sum, record) => sum + record.paidAmount);
  }

  double _finalBalance(List<CustomsRecord> records) {
    return records.fold(0, (sum, record) => sum + record.balanceAmount);
  }

  Widget _summary(List<CustomsRecord> records) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            Text(
              'عدد العمليات: ${records.length}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'إجمالي الكمية: ${_formatNumber(_totalQuantity(records))}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'إجمالي الجمارك: ${_money(_totalAmount(records))}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'إجمالي السداد: ${_money(_totalPaid(records))}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'الرصيد النهائي: ${_money(_finalBalance(records))}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<CustomsRecord> records) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          _merchantName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'هذه الشاشة تعرض البيانات الخاصة بهذا التاجر فقط',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _renameMerchant,
              icon: const Icon(Icons.edit),
              label: const Text('تعديل اسم التاجر'),
            ),
            OutlinedButton.icon(
              onPressed: _deleteMerchant,
              icon: const Icon(Icons.delete_outline),
              label: const Text('حذف التاجر'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _summary(records),
        const SizedBox(height: 12),
        _buildTable(records),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('بيانات التاجر'),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<List<CustomsRecord>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final records = snapshot.data ?? [];

            if (records.isEmpty) {
              return const Center(
                child: Text('لا توجد بيانات لهذا التاجر'),
              );
            }

            return _buildBody(records);
          },
        ),
      ),
    );
  }
}
