class JournalLine {
  const JournalLine({
    required this.id,
    required this.journalEntryId,
    required this.accountId,
    required this.debit,
    required this.credit,
    this.note,
    required this.createdAt,
    this.accountCode,
    this.accountName,
  });

  final String id;
  final String journalEntryId;
  final String accountId;
  final double debit;
  final double credit;
  final String? note;
  final DateTime createdAt;
  final String? accountCode;
  final String? accountName;

  factory JournalLine.fromMap(Map<String, Object?> map) {
    return JournalLine(
      id: map['id'] as String,
      journalEntryId: map['journal_entry_id'] as String,
      accountId: map['account_id'] as String,
      debit: (map['debit'] as num).toDouble(),
      credit: (map['credit'] as num).toDouble(),
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      accountCode: map['account_code'] as String?,
      accountName: map['account_name'] as String?,
    );
  }
}
