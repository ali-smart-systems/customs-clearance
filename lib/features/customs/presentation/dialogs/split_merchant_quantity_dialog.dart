import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SplitMerchantQuantityInput {
  const SplitMerchantQuantityInput({required this.merchantName, required this.quantity});
  final String merchantName;
  final double quantity;
}

Future<SplitMerchantQuantityInput?> showSplitMerchantQuantityDialog(BuildContext context, {required double availableQuantity}) {
  return showDialog<SplitMerchantQuantityInput>(context: context, builder: (context) => _SplitMerchantQuantityDialog(availableQuantity: availableQuantity));
}

class _SplitMerchantQuantityDialog extends StatefulWidget {
  const _SplitMerchantQuantityDialog({required this.availableQuantity});
  final double availableQuantity;
  @override
  State<_SplitMerchantQuantityDialog> createState() => _SplitMerchantQuantityDialogState();
}

class _SplitMerchantQuantityDialogState extends State<_SplitMerchantQuantityDialog> {
  final _merchantController = TextEditingController();
  final _quantityController = TextEditingController();
  String? _error;
  @override
  void dispose() { _merchantController.dispose(); _quantityController.dispose(); super.dispose(); }
  void _submit() {
    final merchantName = _merchantController.text.trim();
    final quantity = double.tryParse(_quantityController.text.trim().replaceAll(',', ''));
    if (merchantName.isEmpty) { setState(() => _error = 'أدخل اسم التاجر المستفيد'); return; }
    if (quantity == null || quantity <= 0) { setState(() => _error = 'أدخل كمية صحيحة أكبر من صفر'); return; }
    if (quantity > widget.availableQuantity) { setState(() => _error = 'الكمية المدخلة أكبر من الكمية المتاحة'); return; }
    Navigator.pop(context, SplitMerchantQuantityInput(merchantName: merchantName, quantity: quantity));
  }
  String _formatNumber(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toString();
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تحديد كمية التاجر'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('الكمية المتاحة: ${_formatNumber(widget.availableQuantity)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(controller: _merchantController, autofocus: true, textDirection: TextDirection.rtl, decoration: const InputDecoration(labelText: 'اسم التاجر المستفيد', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _quantityController, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], decoration: const InputDecoration(labelText: 'الكمية الخاصة بهذا التاجر', border: OutlineInputBorder())),
          if (_error != null) ...[const SizedBox(height: 8), Align(alignment: Alignment.centerRight, child: Text(_error!, style: const TextStyle(color: Colors.red)))],
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: _submit, child: const Text('تطبيق'))],
    );
  }
}
