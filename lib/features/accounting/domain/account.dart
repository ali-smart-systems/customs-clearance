class Account {
  const Account({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    this.parentId,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String code;
  final String name;
  final String type;
  final String? parentId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayName => '$code - $name';

  factory Account.fromMap(Map<String, Object?> map) {
    return Account(
      id: map['id'] as String,
      code: map['code'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      parentId: map['parent_id'] as String?,
      isActive: (map['is_active'] as num).toInt() == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
