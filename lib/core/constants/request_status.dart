class RequestStatus {
  static const String pending = 'pending';
  static const String accepted = 'accepted';
  static const String rejected = 'rejected';

  static String arabic(String value) {
    switch (value) {
      case pending:
        return 'بانتظار الموافقة';
      case accepted:
        return 'مقبولة';
      case rejected:
        return 'مرفوضة';
      default:
        return value;
    }
  }
}
