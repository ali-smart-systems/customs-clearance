class PaymentTransaction {
  const PaymentTransaction({
    required this.id,
    required this.customsRecordId,
    required this.amount,
    this.note,
    required this.createdAt,
  });

  final String id;
  final String customsRecordId;
  final double amount;
  final String? note;
  final DateTime createdAt;

  factory PaymentTransaction.fromMap(Map<String, Object?> map) {
    return PaymentTransaction(
      id: map['id'] as String,
      customsRecordId: map['customs_record_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
