import 'journal_line.dart';

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.entryDate,
    required this.description,
    this.sourceType,
    this.sourceId,
    required this.createdAt,
    required this.updatedAt,
    this.lines = const [],
  });

  final String id;
  final DateTime entryDate;
  final String description;
  final String? sourceType;
  final String? sourceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<JournalLine> lines;

  double get totalDebit => lines.fold(0, (sum, line) => sum + line.debit);
  double get totalCredit => lines.fold(0, (sum, line) => sum + line.credit);

  factory JournalEntry.fromMap(
    Map<String, Object?> map, {
    List<JournalLine> lines = const [],
  }) {
    return JournalEntry(
      id: map['id'] as String,
      entryDate: DateTime.parse(map['entry_date'] as String),
      description: map['description'] as String,
      sourceType: map['source_type'] as String?,
      sourceId: map['source_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      lines: lines,
    );
  }
}
