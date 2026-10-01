import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/job_timer_utils.dart';

class WorkTimerBadge extends StatelessWidget {
  const WorkTimerBadge({
    super.key,
    required this.startedAt,
    required this.stoppedAt,
  });

  final DateTime? startedAt;
  final DateTime? stoppedAt;

  @override
  Widget build(BuildContext context) {
    if (startedAt == null) {
      return _buildBadge(context, '00:00');
    }
    if (stoppedAt != null) {
      return _buildBadge(
        context,
        formatWorkDuration(stoppedAt!.difference(startedAt!)),
      );
    }
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(const Duration(seconds: 1), (tick) => tick),
      builder: (context, _) {
        final elapsed = DateTime.now().difference(startedAt!);
        return _buildBadge(context, formatWorkDuration(elapsed));
      },
    );
  }

  Widget _buildBadge(BuildContext context, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFB9D6FF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF1E5AA7)),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E5AA7),
            ),
          ),
        ],
      ),
    );
  }
}
