import 'package:flutter/material.dart';

import '../../merchants/presentation/merchant_details_page.dart';
import '../data/customs_repository.dart';
import '../domain/customs_record.dart';
import 'dialogs/merchant_dialog.dart';
import 'dialogs/payment_dialog.dart';
import 'dialogs/pricing_dialog.dart';
import 'dialogs/split_merchant_quantity_dialog.dart';

class CustomsRecordDetailsPage extends StatefulWidget {
  const CustomsRecordDetailsPage({
    super.key,
    required this.agentName,
  });

  final String agentName;

  @override
  State<CustomsRecordDetailsPage> createState() =>
      _CustomsRecordDetailsPageState();
}

class _CustomsRecordDetailsPageState extends State<CustomsRecordDetailsPage> {
  final _repository = CustomsRepository();
  final _horizontalScrollController = ScrollController();

  late Future<List<CustomsRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadRecords();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  Future<List<CustomsRecord>> _loadRecords() {
    return _repository.getRecordsByAgentName(widget.agentName);
  }

  void _reload() {
    setState(() {
      _future = _loadRecords();
    });
  }

  bool _hasPricing(CustomsRecord record) {
    final hasUnit =
        record.pricingUnit != null && record.pricingUnit!.trim().isNotEmpty;

    final hasUnitPrice = record.unitPrice != null && record.unitPrice! > 0;

    final hasAmount = record.customsAmount > 0;

    return hasUnit && hasUnitPrice && hasAmount;
  }

  bool _hasMerchant(CustomsRecord record) {
    return record.beneficiaryMerchant != null &&
        record.beneficiaryMerchant!.trim().isNotEmpty;
  }

  void _showPricingRequiredMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'يجب إضافة التسعير الجمركي أولاً قبل إضافة التاجر أو توزيع الكمية',
        ),
      ),
    );
  }

  void _showCompletedRowMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'هذا السطر تم ربطه بتاجر. التوزيع يكون فقط من سطر الكمية المتبقية.',
        ),
      ),
    );
  }

  Future<void> _openMerchant(CustomsRecord record) async {
    final merchantName = record.beneficiaryMerchant?.trim();

    if (merchantName == null || merchantName.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MerchantDetailsPage(
          merchantName: merchantName,
        ),
      ),
    );

    _reload();
  }

  Future<void> _editMerchant(CustomsRecord record) async {
    if (!_hasPricing(record)) {
      _showPricingRequiredMessage();
      return;
    }

    if (_hasMerchant(record)) {
      await _openMerchant(record);
      return;
    }

    final merchantName = await showMerchantDialog(
      context,
      currentName: record.beneficiaryMerchant,
    );

    if (merchantName == null) return;

    try {
      await _repository.updateBeneficiaryMerchant(
        recordId: record.id,
        merchantName: merchantName,
      );

      if (!mounted) return;
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _editPricing(CustomsRecord record) async {
    if (_hasMerchant(record)) {
      _showCompletedRowMessage();
      return;
    }

    final result = await showPricingDialog(
      context,
      quantity: record.quantity,
      currentUnit: record.pricingUnit,
      currentUnitPrice: record.unitPrice,
    );

    if (result == null) return;

    await _repository.updatePricing(
      record: record,
      unit: result.unit,
      unitPrice: result.unitPrice,
    );

    if (!mounted) return;
    _reload();
  }

  Future<void> _editPayment(CustomsRecord record) async {
    if (!_hasMerchant(record)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب إضافة اسم التاجر أولاً قبل تسجيل السداد'),
        ),
      );
      return;
    }

    final changed = await showPaymentDialog(
      context,
      record: record,
    );

    if (changed != true) return;

    if (!mounted) return;
    _reload();
  }

  Future<void> _splitQuantityForMerchant(CustomsRecord record) async {
    if (_hasMerchant(record)) {
      _showCompletedRowMessage();
      return;
    }

    if (!_hasPricing(record)) {
      _showPricingRequiredMessage();
      return;
    }

    final result = await showSplitMerchantQuantityDialog(
      context,
      availableQuantity: record.quantity,
    );

    if (result == null) return;

    try {
      await _repository.splitQuantityForMerchant(
        record: record,
        merchantName: result.merchantName,
        merchantQuantity: result.quantity,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم توزيع الكمية وإنشاء سطر جديد للتاجر'),
        ),
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

  DataCell _textCell(String value) {
    return DataCell(
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  DataCell _paymentCell(CustomsRecord record) {
    final hasMerchant = _hasMerchant(record);

    if (!hasMerchant) {
      return _textCell('-');
    }

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

  Widget _merchantCellContent(CustomsRecord record) {
    final hasMerchant = _hasMerchant(record);
    final hasPricing = _hasPricing(record);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          hasMerchant ? Icons.check_circle : Icons.pending_actions,
          color: hasMerchant ? Colors.green : Colors.orange,
          size: 18,
        ),
        const SizedBox(width: 6),
        Text(
          hasMerchant
              ? record.beneficiaryMerchant!
              : hasPricing
                  ? 'اضغط لإضافة اسم التاجر'
                  : 'أضف التسعير أولاً',
          style: TextStyle(
            color: hasMerchant
                ? Colors.black
                : hasPricing
                    ? Colors.blue
                    : Colors.red,
            fontWeight: FontWeight.bold,
            decoration: hasMerchant ? TextDecoration.underline : null,
          ),
        ),
      ],
    );
  }

  Widget _actionsCellContent(CustomsRecord record) {
    final hasMerchant = _hasMerchant(record);
    final hasPricing = _hasPricing(record);

    if (hasMerchant) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: 18, color: Colors.green),
          SizedBox(width: 6),
          Text(
            'مكتمل',
            style: TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          onPressed: () => _editPricing(record),
          child: const Text('تسعير'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed:
              hasPricing ? () => _splitQuantityForMerchant(record) : null,
          icon: const Icon(Icons.call_split, size: 18),
          label: const Text('توزيع كمية'),
        ),
      ],
    );
  }

  DataRow _buildRow(CustomsRecord record, double runningBalance) {
    final hasMerchant = _hasMerchant(record);

    return DataRow(
      cells: [
        _textCell(_formatDate(record.createdAt)),
        _textCell(record.agentName),
        _textCell(record.driverName),
        _textCell(record.plateNumber),
        _textCell(_formatNumber(record.quantity)),
        _textCell(_empty(record.pricingUnit)),
        _textCell(record.unitPrice == null ? '-' : _money(record.unitPrice!)),
        _textCell(_money(record.customsAmount)),
        _paymentCell(record),
        _balanceCell(runningBalance),
        DataCell(
          hasMerchant
              ? InkWell(
                  onTap: () => _openMerchant(record),
                  child: _merchantCellContent(record),
                )
              : InkWell(
                  onTap: () => _editMerchant(record),
                  child: _merchantCellContent(record),
                ),
        ),
        DataCell(_actionsCellContent(record)),
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

  Widget _buildRecordsTable(List<CustomsRecord> records) {
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
            DataColumn(label: Text('اسم الوكيل')),
            DataColumn(label: Text('اسم السائق')),
            DataColumn(label: Text('رقم اللوحة')),
            DataColumn(label: Text('الكمية')),
            DataColumn(label: Text('الوحدة')),
            DataColumn(label: Text('سعر الوحدة')),
            DataColumn(label: Text('مبلغ الجمارك')),
            DataColumn(label: Text('مبلغ السداد')),
            DataColumn(label: Text('الرصيد')),
            DataColumn(label: Text('التاجر المستفيد')),
            DataColumn(label: Text('إجراءات')),
          ],
          rows: _buildRows(records),
        ),
      ),
    );
  }

  Widget _buildRecords(List<CustomsRecord> records) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          widget.agentName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'كل البيانات الخاصة بهذا الوكيل فقط - عدد العمليات: ${records.length}',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        _buildRecordsTable(records),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('بيانات الوكيل'),
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
                child: Text('لم يتم العثور على بيانات هذا الوكيل'),
              );
            }

            return _buildRecords(records);
          },
        ),
      ),
    );
  }
}
