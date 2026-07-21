import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/request_status.dart';
import '../../../core/db/app_database.dart';
import '../../shipments/domain/shipment_request.dart';

class ShipmentRepository {
  ShipmentRepository({
    AppDatabase? appDatabase,
    Uuid? uuid,
  })  : _appDatabase = appDatabase ?? AppDatabase.instance,
        _uuid = uuid ?? const Uuid();

  final AppDatabase _appDatabase;
  final Uuid _uuid;

  Future<String> createRequest({
    required String workerId,
    required String agentName,
    required String driverName,
    required String plateNumber,
    required double quantity,
  }) async {
    final db = await _appDatabase.database;
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    await db.insert('shipment_requests', {
      'id': id,
      'worker_id': workerId,
      'agent_name': agentName.trim(),
      'driver_name': driverName.trim(),
      'plate_number': plateNumber.trim(),
      'quantity': quantity,
      'status': RequestStatus.pending,
      'created_at': now,
      'reviewed_by': null,
      'reviewed_at': null,
      'reject_reason': null,
      'sync_status': 'local',
      'server_id': null,
    });

    return id;
  }

  Future<int> createBulkRequests({
    required String workerId,
    required List<ShipmentRequestInput> requests,
  }) async {
    if (requests.isEmpty) return 0;

    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (final request in requests) {
        await txn.insert('shipment_requests', {
          'id': _uuid.v4(),
          'worker_id': workerId,
          'agent_name': request.agentName.trim(),
          'driver_name': request.driverName.trim(),
          'plate_number': request.plateNumber.trim(),
          'quantity': request.quantity,
          'status': RequestStatus.pending,
          'created_at': now,
          'reviewed_by': null,
          'reviewed_at': null,
          'reject_reason': null,
          'sync_status': 'local',
          'server_id': null,
        });
      }
    });

    return requests.length;
  }

  Future<List<ShipmentRequest>> getPendingRequests() async {
    final db = await _appDatabase.database;

    final rows = await db.query(
      'shipment_requests',
      where: 'status = ?',
      whereArgs: [RequestStatus.pending],
      orderBy: 'created_at DESC',
    );

    return rows.map(ShipmentRequest.fromMap).toList();
  }

  Future<List<ShipmentRequest>> getAllRequests() async {
    final db = await _appDatabase.database;

    final rows = await db.query(
      'shipment_requests',
      orderBy: 'created_at DESC',
    );

    return rows.map(ShipmentRequest.fromMap).toList();
  }

  Future<ShipmentRequest?> getRequestById(String id) async {
    final db = await _appDatabase.database;

    final rows = await db.query(
      'shipment_requests',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return ShipmentRequest.fromMap(rows.first);
  }

  Future<void> acceptRequest({
    required String requestId,
    required String managerId,
  }) async {
    final db = await _appDatabase.database;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'shipment_requests',
        where: 'id = ? AND status = ?',
        whereArgs: [requestId, RequestStatus.pending],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError('الطلب غير موجود أو تمت مراجعته سابقاً');
      }

      final request = ShipmentRequest.fromMap(rows.first);
      final now = DateTime.now().toIso8601String();

      await txn.update(
        'shipment_requests',
        {
          'status': RequestStatus.accepted,
          'reviewed_by': managerId,
          'reviewed_at': now,
          'sync_status': 'local',
        },
        where: 'id = ?',
        whereArgs: [requestId],
      );

      await txn.insert(
        'customs_records',
        {
          'id': _uuid.v4(),
          'request_id': request.id,
          'agent_name': request.agentName,
          'driver_name': request.driverName,
          'plate_number': request.plateNumber,
          'quantity': request.quantity,
          'customs_amount': 0,
          'clearance_fee': 0,
          'driver_advance': 0,
          'beneficiary_merchant': null,
          'pricing_unit': null,
          'unit_price': null,
          'created_at': now,
          'updated_at': now,
          'sync_status': 'local',
          'server_id': null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
  }

  Future<void> rejectRequest({
    required String requestId,
    required String managerId,
    String? reason,
  }) async {
    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();

    await db.update(
      'shipment_requests',
      {
        'status': RequestStatus.rejected,
        'reviewed_by': managerId,
        'reviewed_at': now,
        'reject_reason': reason?.trim(),
        'sync_status': 'local',
      },
      where: 'id = ? AND status = ?',
      whereArgs: [requestId, RequestStatus.pending],
    );
  }
}

class ShipmentRequestInput {
  const ShipmentRequestInput({
    required this.agentName,
    required this.driverName,
    required this.plateNumber,
    required this.quantity,
  });

  final String agentName;
  final String driverName;
  final String plateNumber;
  final double quantity;
}
