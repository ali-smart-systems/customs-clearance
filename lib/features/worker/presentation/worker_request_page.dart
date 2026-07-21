import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/demo_users.dart';
import '../../../features/shipments/data/shipment_repository.dart';
import '../../../shared/widgets/app_text_field.dart';

class WorkerRequestPage extends StatefulWidget {
  const WorkerRequestPage({super.key});

  @override
  State<WorkerRequestPage> createState() => _WorkerRequestPageState();
}

class _WorkerRequestPageState extends State<WorkerRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final _repository = ShipmentRepository();

  final _agentNameController = TextEditingController();
  final _driverNameController = TextEditingController();
  final _plateNumberController = TextEditingController();
  final _quantityController = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _agentNameController.dispose();
    _driverNameController.dispose();
    _plateNumberController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      await _repository.createRequest(
        workerId: DemoUsers.workerId,
        agentName: _agentNameController.text,
        driverName: _driverNameController.text,
        plateNumber: _plateNumberController.text,
        quantity: double.parse(_quantityController.text),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إرسال البيانات وستظهر كرسالة معلقة في الشاشة الرئيسية'),
        ),
      );

      Navigator.pop(context, true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _openBulkDialog() async {
    final result = await showDialog<List<ShipmentRequestInput>>(
      context: context,
      builder: (context) => const _BulkRequestsDialog(),
    );

    if (result == null || result.isEmpty) return;

    setState(() => _saving = true);

    try {
      final count = await _repository.createBulkRequests(
        workerId: DemoUsers.workerId,
        requests: result,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إرسال $count عملية وستظهر كرسائل معلقة في الرئيسية'),
        ),
      );

      Navigator.pop(context, true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'هذا الحقل مطلوب';
    }

    return null;
  }

  String? _quantityValidator(String? value) {
    final text = value?.trim() ?? '';
    final number = double.tryParse(text);

    if (number == null || number <= 0) {
      return 'أدخل كمية صحيحة أكبر من صفر';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('شاشة العامل'),
          centerTitle: true,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    const Text(
                      'إضافة بيانات التخليص',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'يمكن إرسال عملية واحدة، أو استخدام زر الإضافة الجماعية إذا كانت الرسالة تحتوي على أكثر من عملية.',
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _agentNameController,
                      label: 'اسم الوكيل',
                      validator: _requiredValidator,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _driverNameController,
                      label: 'اسم السائق',
                      validator: _requiredValidator,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _plateNumberController,
                      label: 'رقم اللوحة',
                      validator: _requiredValidator,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _quantityController,
                      label: 'الكمية',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9.]'),
                        ),
                      ],
                      validator: _quantityValidator,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: Text(_saving ? 'جاري الإرسال...' : 'إرسال عملية واحدة'),
                      onPressed: _saving ? null : _sendRequest,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _openBulkDialog,
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('إضافة جماعية من رسالة'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BulkRequestsDialog extends StatefulWidget {
  const _BulkRequestsDialog();

  @override
  State<_BulkRequestsDialog> createState() => _BulkRequestsDialogState();
}

class _BulkRequestsDialogState extends State<_BulkRequestsDialog> {
  final _messageController = TextEditingController(
    text: 'احمد على\nعبدالله محمد\n965/9\n1500\n'
        'صالح علي\nمحمد يحيى\n567/9\n1200\n'
        'محمد عبدالسلام\nعلي صالح\n768/9\n1300\n'
        'صالح محمد\nيحيى ابراهيم\n899/9\n1450',
  );

  String? _error;
  int _parsedCount = 0;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_preview);
    _preview();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _preview() {
    final result = _parseRequests(showErrors: false);

    setState(() {
      _parsedCount = result.requests.length;
      _error = result.error;
    });
  }

  _ParseResult _parseRequests({required bool showErrors}) {
    final lines = _messageController.text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return const _ParseResult(
        requests: [],
        error: null,
      );
    }

    if (lines.length % 4 != 0) {
      return _ParseResult(
        requests: const [],
        error: showErrors
            ? 'تنسيق الرسالة غير صحيح. كل عملية يجب أن تكون 4 أسطر: اسم الوكيل، اسم السائق، رقم اللوحة، الكمية.'
            : null,
      );
    }

    final requests = <ShipmentRequestInput>[];

    for (var index = 0; index < lines.length; index += 4) {
      final agentName = lines[index];
      final driverName = lines[index + 1];
      final plateNumber = lines[index + 2];
      final quantityText = lines[index + 3].replaceAll(',', '');
      final quantity = double.tryParse(quantityText);

      if (agentName.isEmpty ||
          driverName.isEmpty ||
          plateNumber.isEmpty ||
          quantity == null ||
          quantity <= 0) {
        return _ParseResult(
          requests: const [],
          error: showErrors
              ? 'يوجد خطأ في العملية رقم ${(index ~/ 4) + 1}. تأكد أن الكمية رقم صحيح أكبر من صفر.'
              : null,
        );
      }

      requests.add(
        ShipmentRequestInput(
          agentName: agentName,
          driverName: driverName,
          plateNumber: plateNumber,
          quantity: quantity,
        ),
      );
    }

    return _ParseResult(
      requests: requests,
      error: null,
    );
  }

  void _submit() {
    final result = _parseRequests(showErrors: true);

    if (result.error != null) {
      setState(() => _error = result.error);
      return;
    }

    if (result.requests.isEmpty) {
      setState(() => _error = 'أدخل رسالة تحتوي على عملية واحدة على الأقل');
      return;
    }

    Navigator.pop(context, result.requests);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة جماعية من رسالة'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'اكتب أو الصق الرسالة بحيث تكون كل عملية من 4 أسطر بالترتيب:\n'
              'اسم الوكيل، اسم السائق، رقم اللوحة، الكمية.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _messageController,
              autofocus: true,
              maxLines: 14,
              minLines: 8,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'اسم الوكيل\nاسم السائق\nرقم اللوحة\nالكمية',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'عدد العمليات المقروءة: $_parsedCount',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send),
          label: const Text('إرسال الكل'),
        ),
      ],
    );
  }
}

class _ParseResult {
  const _ParseResult({
    required this.requests,
    required this.error,
  });

  final List<ShipmentRequestInput> requests;
  final String? error;
}
