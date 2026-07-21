class ShipmentRequest {
  const ShipmentRequest({
    required this.id,
    required this.workerId,
    required this.agentName,
    required this.driverName,
    required this.plateNumber,
    required this.quantity,
    required this.status,
    required this.createdAt,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectReason,
    this.syncStatus = 'local',
    this.serverId,
  });

  final String id;
  final String workerId;
  final String agentName;
  final String driverName;
  final String plateNumber;
  final double quantity;
  final String status;
  final DateTime createdAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectReason;
  final String syncStatus;
  final String? serverId;

  factory ShipmentRequest.fromMap(Map<String, Object?> map) {
    return ShipmentRequest(
      id: map['id'] as String,
      workerId: map['worker_id'] as String,
      agentName: map['agent_name'] as String,
      driverName: map['driver_name'] as String,
      plateNumber: map['plate_number'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      reviewedBy: map['reviewed_by'] as String?,
      reviewedAt: map['reviewed_at'] == null
          ? null
          : DateTime.parse(map['reviewed_at'] as String),
      rejectReason: map['reject_reason'] as String?,
      syncStatus: map['sync_status'] as String? ?? 'local',
      serverId: map['server_id'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'worker_id': workerId,
      'agent_name': agentName,
      'driver_name': driverName,
      'plate_number': plateNumber,
      'quantity': quantity,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'reviewed_by': reviewedBy,
      'reviewed_at': reviewedAt?.toIso8601String(),
      'reject_reason': rejectReason,
      'sync_status': syncStatus,
      'server_id': serverId,
    };
  }
}
