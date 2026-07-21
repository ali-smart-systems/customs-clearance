import 'package:flutter/material.dart';

Future<String?> showMerchantDialog(
  BuildContext context, {
  String? currentName,
}) {
  final controller = TextEditingController(text: currentName ?? '');

  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('إضافة التاجر المستفيد'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(
            labelText: 'اسم التاجر المستفيد',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(context, value);
            },
            child: const Text('حفظ'),
          ),
        ],
      );
    },
  );
}
