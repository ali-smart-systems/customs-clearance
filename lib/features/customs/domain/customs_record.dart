class CustomsRecord {
  const CustomsRecord({
    required this.id,
    required this.requestId,
    this.parentRecordId,
    required this.agentName,
    required this.driverName,
    required this.plateNumber,
    required this.quantity,
    required this.customsAmount,
    this.clearanceFee = 0,
    this.driverAdvance = 0,
    this.radiologyFeeApplied = false,
    this.customsAmountManualOverride = false,
    this.paidAmount = 0,
    this.beneficiaryMerchant,
    this.pricingUnit,
    this.unitPrice,
    required this.createdAt,
    required this.updatedAt,
    this.displayOrder = 0,
    this.syncStatus = 'local',
    this.serverId,
  });

  final String id;
  final String requestId;
  final String? parentRecordId;
  final String agentName;
  final String driverName;
  final String plateNumber;
  final double quantity;
  final double customsAmount;
  final double clearanceFee;
  final double driverAdvance;
  final bool radiologyFeeApplied;
  final bool customsAmountManualOverride;
  final double paidAmount;
  final String? beneficiaryMerchant;
  final String? pricingUnit;
  final double? unitPrice;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int displayOrder;
  final String syncStatus;
  final String? serverId;

  double get radiologyAmount => radiologyFeeApplied ? 10000.0 : 0.0;

  double get customsBaseAmount {
    final baseAmount = customsAmount - radiologyAmount;
    return baseAmount < 0 ? 0 : baseAmount;
  }

  double get customsAndClearanceAmount => customsBaseAmount + clearanceFee;

  double get grandTotal =>
      customsAndClearanceAmount + radiologyAmount + driverAdvance;

  double get balanceAmount => grandTotal - paidAmount;

  CustomsRecord copyWith({
    String? id,
    String? requestId,
    String? parentRecordId,
    String? agentName,
    String? driverName,
    String? plateNumber,
    double? quantity,
    double? customsAmount,
    double? clearanceFee,
    double? driverAdvance,
    bool? radiologyFeeApplied,
    bool? customsAmountManualOverride,
    double? paidAmount,
    String? beneficiaryMerchant,
    String? pricingUnit,
    double? unitPrice,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? displayOrder,
    String? syncStatus,
    String? serverId,
  }) {
    return CustomsRecord(
      id: id ?? this.id,
      requestId: requestId ?? this.requestId,
      parentRecordId: parentRecordId ?? this.parentRecordId,
      agentName: agentName ?? this.agentName,
      driverName: driverName ?? this.driverName,
      plateNumber: plateNumber ?? this.plateNumber,
      quantity: quantity ?? this.quantity,
      customsAmount: customsAmount ?? this.customsAmount,
      clearanceFee: clearanceFee ?? this.clearanceFee,
      driverAdvance: driverAdvance ?? this.driverAdvance,
      radiologyFeeApplied: radiologyFeeApplied ?? this.radiologyFeeApplied,
      customsAmountManualOverride:
          customsAmountManualOverride ?? this.customsAmountManualOverride,
      paidAmount: paidAmount ?? this.paidAmount,
      beneficiaryMerchant: beneficiaryMerchant ?? this.beneficiaryMerchant,
      pricingUnit: pricingUnit ?? this.pricingUnit,
      unitPrice: unitPrice ?? this.unitPrice,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      displayOrder: displayOrder ?? this.displayOrder,
      syncStatus: syncStatus ?? this.syncStatus,
      serverId: serverId ?? this.serverId,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'request_id': requestId,
      'parent_record_id': parentRecordId,
      'agent_name': agentName,
      'driver_name': driverName,
      'plate_number': plateNumber,
      'quantity': quantity,
      'customs_amount': customsAmount,
      'clearance_fee': clearanceFee,
      'driver_advance': driverAdvance,
      'radiology_fee_applied': radiologyFeeApplied ? 1 : 0,
      'customs_amount_manual_override': customsAmountManualOverride ? 1 : 0,
      'paid_amount': paidAmount,
      'beneficiary_merchant': beneficiaryMerchant,
      'pricing_unit': pricingUnit,
      'unit_price': unitPrice,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'display_order': displayOrder,
      'sync_status': syncStatus,
      'server_id': serverId,
    };
  }

  factory CustomsRecord.fromMap(Map<String, Object?> map) {
    return CustomsRecord(
      id: map['id'] as String,
      requestId: map['request_id'] as String,
      parentRecordId: map['parent_record_id'] as String?,
      agentName: map['agent_name'] as String,
      driverName: map['driver_name'] as String,
      plateNumber: map['plate_number'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      customsAmount: (map['customs_amount'] as num).toDouble(),
      clearanceFee: map['clearance_fee'] == null
          ? 0
          : (map['clearance_fee'] as num).toDouble(),
      driverAdvance: map['driver_advance'] == null
          ? 0
          : (map['driver_advance'] as num).toDouble(),
      radiologyFeeApplied:
          ((map['radiology_fee_applied'] as num?)?.toInt() ?? 0) == 1,
      customsAmountManualOverride:
          ((map['customs_amount_manual_override'] as num?)?.toInt() ?? 0) == 1,
      paidAmount: map['paid_amount'] == null
          ? 0
          : (map['paid_amount'] as num).toDouble(),
      beneficiaryMerchant: map['beneficiary_merchant'] as String?,
      pricingUnit: map['pricing_unit'] as String?,
      unitPrice: map['unit_price'] == null
          ? null
          : (map['unit_price'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      displayOrder: map['display_order'] == null
          ? 0
          : (map['display_order'] as num).toInt(),
      syncStatus: map['sync_status'] as String? ?? 'local',
      serverId: map['server_id'] as String?,
    );
  }
}
