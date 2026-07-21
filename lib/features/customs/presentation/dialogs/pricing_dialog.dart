import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../customs/domain/pricing_input.dart';

Future<PricingInput?> showPricingDialog(
  BuildContext context, {
  required double quantity,
  String? currentUnit,
  double? currentUnitPrice,
}) {
  final priceController = TextEditingController(
    text: currentUnitPrice?.toString() ?? '',
  );

  String selectedUnit = currentUnit ?? 'كيس';

  return showDialog<PricingInput>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('التسعير الجمركي'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: quantity.toString(),
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'الكمية',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'سعر الوحدة',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedUnit,
                    decoration: const InputDecoration(
                      labelText: 'الوحدة',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'طن',
                        child: Text('طن'),
                      ),
                      DropdownMenuItem(
                        value: 'كيس',
                        child: Text('كيس'),
                      ),
                      DropdownMenuItem(
                        value: 'كيلو',
                        child: Text('كيلو'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedUnit = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (_) {
                      final price = double.tryParse(priceController.text);
                      final total = price == null ? 0 : quantity * price;

                      return Text(
                        'الناتج الحالي: ${total.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      );
                    },
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
                  final unitPrice = double.tryParse(priceController.text.trim());

                  if (unitPrice == null || unitPrice <= 0) return;

                  Navigator.pop(
                    context,
                    PricingInput(
                      unit: selectedUnit,
                      unitPrice: unitPrice,
                    ),
                  );
                },
                child: const Text('موافقة'),
              ),
            ],
          );
        },
      );
    },
  );
}
