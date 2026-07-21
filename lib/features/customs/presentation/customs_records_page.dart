import 'package:flutter/material.dart';

import '../../../features/customs/data/customs_repository.dart';
import '../../../features/customs/domain/customs_record.dart';
import '../../../features/customs/presentation/dialogs/merchant_dialog.dart';
import '../../../features/customs/presentation/dialogs/pricing_dialog.dart';

class CustomsRecordsPage extends StatefulWidget {
  const CustomsRecordsPage({super.key});

  @override
  State<CustomsRecordsPage> createState() => _CustomsRecordsPageState();
}

class _CustomsRecordsPageState extends State<CustomsRecordsPage> {
  final _repository = CustomsRepository();
  final _horizontalScrollController = ScrollController();

  late Future<List<CustomsRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.getRecords();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _repository.getRecords();
    });
  }

  Future<void> _editMerchant(CustomsRecord record) async {
    final merchantName = await showMerchantDialog(
      context,
      currentName: record.beneficiaryMerchant,
    );

    if (merchantName == null) return;

    await _repository.updateBeneficiaryMerchant(
      recordId: record.id,
      merchantName: merchantName,
    );

    _reload();
  }

  Future<void> _editPricing(CustomsRecord record) async {
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

    _reload();
  }

  String _money(double value) {
    return value.toStringAsFixed(2);
  }

  String _number(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  DataCell _clickableCell({
    required String text,
    required VoidCallback onTap,
    bool isEmpty = false,
  }) {
    return DataCell(
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            text,
            style: TextStyle(
              color: isEmpty ? Colors.blue : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(CustomsRecord record) {
    return DataRow(
      cells: [
        DataCell(Text(record.agentName)),
        DataCell(Text(record.driverName)),
        DataCell(Text(record.plateNumber)),
        DataCell(Text(_number(record.quantity))),
        DataCell(Text(record.pricingUnit ?? '-')),
        DataCell(
            Text(record.unitPrice == null ? '-' : _money(record.unitPrice!))),
        DataCell(Text(_money(record.customsAmount))),
        _clickableCell(
          text: (record.beneficiaryMerchant == null ||
                  record.beneficiaryMerchant!.trim().isEmpty)
              ? 'اضغط لإضافة التاجر'
              : record.beneficiaryMerchant!,
          isEmpty: record.beneficiaryMerchant == null ||
              record.beneficiaryMerchant!.trim().isEmpty,
          onTap: () => _editMerchant(record),
        ),
        DataCell(
          FilledButton(
            onPressed: () => _editPricing(record),
            child: const Text('تسعير'),
          ),
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
          title: const Text('جدول التخليص'),
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
                child: Text(
                    'لا توجد سجلات تخليص. اقبل رسالة أولاً من شاشة المستخدم المستلم.'),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(12),
              child: Scrollbar(
                controller: _horizontalScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      border: TableBorder.all(
                        color: Colors.black26,
                        width: 1,
                      ),
                      headingRowColor: WidgetStateProperty.all(
                        const Color(0xFFE3F2FD),
                      ),
                      columns: const [
                        DataColumn(label: Text('اسم الوكيل')),
                        DataColumn(label: Text('اسم السائق')),
                        DataColumn(label: Text('رقم اللوحة')),
                        DataColumn(label: Text('الكمية')),
                        DataColumn(label: Text('الوحدة')),
                        DataColumn(label: Text('سعر الوحدة')),
                        DataColumn(label: Text('مبلغ الجمارك')),
                        DataColumn(label: Text('التاجر المستفيد')),
                        DataColumn(label: Text('التسعير')),
                      ],
                      rows: records.map(_buildRow).toList(),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
