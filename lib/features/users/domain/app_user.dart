class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.role,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String role;
  final DateTime createdAt;

  factory AppUser.fromMap(Map<String, Object?> map) {
    return AppUser(
      id: map['id'] as String,
      name: map['name'] as String,
      role: map['role'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
