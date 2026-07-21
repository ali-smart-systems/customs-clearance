import 'package:flutter/material.dart';

Future<String?> showEditNameDialog(
  BuildContext context, {
  required String title,
  required String currentName,
  required String labelText,
}) {
  final controller = TextEditingController(text: currentName.trim());

  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
            labelText: labelText,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim().replaceAll(
                    RegExp(r'\s+'),
                    ' ',
                  );

              if (value.isEmpty) return;

              Navigator.pop(context, value);
            },
            child: const Text('حفظ'),
          ),
        ],
      );
    },
  ).whenComplete(controller.dispose);
}
