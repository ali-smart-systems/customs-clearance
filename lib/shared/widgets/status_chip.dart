import 'package:flutter/material.dart';

import '../../core/constants/request_status.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
  });

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      RequestStatus.pending => Colors.orange,
      RequestStatus.accepted => Colors.green,
      RequestStatus.rejected => Colors.red,
      _ => Colors.grey,
    };

    return Chip(
      label: Text(RequestStatus.arabic(status)),
      side: BorderSide(color: color),
      labelStyle: TextStyle(color: color.shade700),
      backgroundColor: color.withAlpha(20),
    );
  }
}
