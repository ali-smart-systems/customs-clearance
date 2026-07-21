import 'package:flutter/material.dart';

import '../../../core/constants/demo_users.dart';
import '../../../features/shipments/data/shipment_repository.dart';
import '../../../features/shipments/domain/shipment_request.dart';
import '../../../shared/widgets/status_chip.dart';

class RequestDetailsPage extends StatefulWidget {
  const RequestDetailsPage({
    super.key,
    required this.requestId,
  });

  final String requestId;

  @override
  State<RequestDetailsPage> createState() => _RequestDetailsPageState();
}

class _RequestDetailsPageState extends State<RequestDetailsPage> {
  final _repository = ShipmentRepository();

  late Future<ShipmentRequest?> _future;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _repository.getRequestById(widget.requestId);
  }

  Future<void> _accept() async {
    setState(() => _saving = true);

    try {
      await _repository.acceptRequest(
        requestId: widget.requestId,
        managerId: DemoUsers.managerId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم قبول الرسالة وستظهر باسم الوكيل في الرئيسية'),
        ),
      );

      Navigator.pop(context, true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _reject() async {
    final reason = await _showRejectReasonDialog();
    if (reason == null) return;

    setState(() => _saving = true);

    try {
      await _repository.rejectRequest(
        requestId: widget.requestId,
        managerId: DemoUsers.managerId,
        reason: reason,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم رفض الرسالة')),
      );

      Navigator.pop(context, true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<String?> _showRejectReasonDialog() {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('سبب الرفض'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'اكتب سبب الرفض أو اتركه فارغاً',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('رفض'),
            ),
          ],
        );
      },
    );
  }

  Widget _infoRow(String title, String value) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تفاصيل الرسالة'),
          centerTitle: true,
        ),
        body: FutureBuilder<ShipmentRequest?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final request = snapshot.data;

            if (request == null) {
              return const Center(child: Text('الرسالة غير موجودة'));
            }

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(
                  children: [
                    const Text(
                      'حالة الرسالة: ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    StatusChip(status: request.status),
                  ],
                ),
                const SizedBox(height: 12),
                _infoRow('اسم الوكيل', request.agentName),
                _infoRow('اسم السائق', request.driverName),
                _infoRow('رقم اللوحة', request.plateNumber),
                _infoRow('الكمية', request.quantity.toString()),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _accept,
                        icon: const Icon(Icons.check),
                        label: const Text('قبول'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _reject,
                        icon: const Icon(Icons.close),
                        label: const Text('رفض'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
