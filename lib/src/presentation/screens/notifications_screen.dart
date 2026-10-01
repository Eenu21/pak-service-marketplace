import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/repository_provider.dart';
import '../../core/services/formatters.dart';
import '../../core/services/pro_balance_rules.dart';
import '../../domain/models.dart';
import '../controllers/auth_controller.dart';
import '../controllers/chat_controller.dart';
import '../controllers/payments_controller.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('You need to log in first.')),
      );
    }

    final notificationsAsync = ref.watch(notificationsProvider(user.id));
    final financial = ref.watch(proFinancialStatusProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FF),
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              final events = notificationsAsync.valueOrNull ?? const <NotificationEvent>[];
              for (final event in events.where((event) => !event.read)) {
                await ref
                    .read(marketplaceRepositoryProvider)
                    .markNotificationRead(event.id);
              }
            },
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (events) {
          final synthetic = _syntheticDueReminder(user, financial);
          final merged = <NotificationEvent>[
            if (synthetic != null) synthetic,
            ...events,
          ]..sort((a, b) => b.sentAt.compareTo(a.sentAt));

          if (merged.isEmpty) {
            return const Center(
              child: Text('No notifications yet. New updates will show here.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: merged.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final event = merged[index];
              final syntheticDue = event.id == 'synthetic_due_reminder';
              return _NotificationCard(
                event: event,
                syntheticDue: syntheticDue,
                onTap: () async {
                  if (!syntheticDue && !event.read) {
                    await ref
                        .read(marketplaceRepositoryProvider)
                        .markNotificationRead(event.id);
                  }
                  if (!context.mounted) {
                    return;
                  }
                  _openNotification(context, event);
                },
              );
            },
          );
        },
      ),
    );
  }

  NotificationEvent? _syntheticDueReminder(
    AppUser user,
    ProFinancialStatus? financial,
  ) {
    if (user.role != UserRole.pro || financial == null) {
      return null;
    }
    if (financial.level == ProDueLevel.clear) {
      return null;
    }
    final title = switch (financial.level) {
      ProDueLevel.mild => 'Commission reminder',
      ProDueLevel.strong => 'Urgent commission reminder',
      ProDueLevel.locked => 'Account locked for pending commission',
      ProDueLevel.clear => '',
    };
    final body = switch (financial.level) {
      ProDueLevel.mild =>
        'Your current app due is ${formatPkr(financial.dueToApp)}. Please pay soon.',
      ProDueLevel.strong =>
        'Your due is ${formatPkr(financial.dueToApp)} and your account is close to being locked.',
      ProDueLevel.locked =>
        'Your due is ${formatPkr(financial.dueToApp)}. Pay now to continue bidding on jobs.',
      ProDueLevel.clear => '',
    };
    return NotificationEvent(
      id: 'synthetic_due_reminder',
      userId: user.id,
      type: 'commission_due',
      title: title,
      body: body,
      sentAt: DateTime.now(),
      metadata: const <String, dynamic>{'target': 'earnings'},
      read: false,
    );
  }

  void _openNotification(BuildContext context, NotificationEvent event) {
    final jobId = event.metadata['job_id'] as String?;
    final senderId = event.metadata['sender_id'] as String?;
    if (event.type == 'message' &&
        jobId != null &&
        senderId != null &&
        jobId.isNotEmpty &&
        senderId.isNotEmpty) {
      context.push('/chat/$jobId/$senderId');
      return;
    }
    if (event.type == 'commission_due') {
      context.push('/earnings');
      return;
    }
    if (jobId != null && jobId.isNotEmpty) {
      context.push('/job/$jobId');
    }
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.event,
    required this.syntheticDue,
    required this.onTap,
  });

  final NotificationEvent event;
  final bool syntheticDue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _notificationColor(event.type);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: event.read && !syntheticDue ? Colors.white : const Color(0xFFF2ECFF),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: event.read && !syntheticDue
                  ? const Color(0xFFE4DDF4)
                  : accent.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(_notificationIcon(event.type), color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            event.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF222255),
                            ),
                          ),
                        ),
                        if (!event.read || syntheticDue)
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      event.body,
                      style: const TextStyle(
                        color: Color(0xFF6E6A84),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      formatDateTime(event.sentAt),
                      style: const TextStyle(
                        color: Color(0xFF9A95AD),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _notificationIcon(String type) {
  return switch (type) {
    'message' => Icons.chat_bubble_outline_rounded,
    'job_nearby' => Icons.work_outline_rounded,
    'bid_received' => Icons.local_offer_outlined,
    'bid_updated' => Icons.edit_note_rounded,
    'payment_recorded' => Icons.payments_outlined,
    'commission_due' => Icons.warning_amber_rounded,
    _ => Icons.notifications_none_rounded,
  };
}

Color _notificationColor(String type) {
  return switch (type) {
    'message' => const Color(0xFF6D5DF6),
    'job_nearby' => const Color(0xFF28A86B),
    'bid_received' => const Color(0xFFF39A36),
    'bid_updated' => const Color(0xFF8A63FF),
    'payment_recorded' => const Color(0xFF3F83F8),
    'commission_due' => const Color(0xFFE55555),
    _ => const Color(0xFF7A7694),
  };
}
