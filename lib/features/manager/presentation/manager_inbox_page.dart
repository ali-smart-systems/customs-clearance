import 'package:flutter/material.dart';

import '../../../core/constants/request_status.dart';
import '../../../features/manager/presentation/request_details_page.dart';
import '../../../features/shipments/data/shipment_repository.dart';
import '../../../features/shipments/domain/shipment_request.dart';

class ManagerInboxPage extends StatefulWidget {
  const ManagerInboxPage({super.key});

  @override
  State<ManagerInboxPage> createState() => _ManagerInboxPageState();
}

class _ManagerInboxPageState extends State<ManagerInboxPage> {
  final _repository = ShipmentRepository();

  late Future<List<ShipmentRequest>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.getPendingRequests();
  }

  void _reload() {
    setState(() {
      _future = _repository.getPendingRequests();
    });
  }

  Future<void> _openDetails(ShipmentRequest request) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RequestDetailsPage(requestId: request.id),
      ),
    );

    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الرسائل الواردة'),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<List<ShipmentRequest>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final requests = snapshot.data ?? [];

            if (requests.isEmpty) {
              return const Center(
                child: Text('لا توجد رسائل بانتظار الموافقة'),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: requests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final request = requests[index];

                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person),
                    ),
                    title: Text(
                      request.agentName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(RequestStatus.arabic(request.status)),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => _openDetails(request),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
