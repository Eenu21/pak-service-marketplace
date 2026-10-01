import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/repository_provider.dart';
import '../../core/services/avatar_utils.dart';
import '../../core/services/formatters.dart';
import '../../domain/models.dart';
import '../controllers/auth_controller.dart';
import '../controllers/chat_controller.dart';

final _proJobsProvider = StreamProvider.family<List<Job>, String>((ref, proId) {
  return ref.watch(marketplaceRepositoryProvider).watchJobsForPro(proId);
});

final _proUserProvider = StreamProvider.family<AppUser?, String>((ref, userId) {
  return ref
      .watch(marketplaceRepositoryProvider)
      .watchAllUsers(includeLocations: false)
      .map((users) {
        for (final user in users) {
          if (user.id == userId) {
            return user;
          }
        }
        return null;
      });
});

class ProProfileScreen extends ConsumerWidget {
  const ProProfileScreen({super.key, required this.proId, this.initialPro});

  final String proId;
  final AppUser? initialPro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final liveProAsync = ref.watch(_proUserProvider(proId));
    final jobsAsync = ref.watch(_proJobsProvider(proId));
    final notificationsAsync = ref.watch(notificationsProvider(proId));
    final isSelf = currentUser?.id == proId;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FF),
      body: SafeArea(
        child: liveProAsync.when(
          loading: () {
            final fallback = initialPro;
            if (fallback == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _ProProfileBody(
              pro: fallback,
              jobsAsync: jobsAsync,
              notificationsAsync: notificationsAsync,
              showActions: isSelf,
            );
          },
          error: (error, _) {
            final fallback = initialPro;
            if (fallback == null) {
              return Center(child: Text(error.toString()));
            }
            return _ProProfileBody(
              pro: fallback,
              jobsAsync: jobsAsync,
              notificationsAsync: notificationsAsync,
              showActions: isSelf,
            );
          },
          data: (livePro) {
            final pro = livePro ?? initialPro;
            if (pro == null) {
              return const Center(child: Text('Profile not found.'));
            }
            return _ProProfileBody(
              pro: pro,
              jobsAsync: jobsAsync,
              notificationsAsync: notificationsAsync,
              showActions: isSelf,
            );
          },
        ),
      ),
    );
  }
}

class _ProProfileBody extends StatelessWidget {
  const _ProProfileBody({
    required this.pro,
    required this.jobsAsync,
    required this.notificationsAsync,
    required this.showActions,
  });

  final AppUser pro;
  final AsyncValue<List<Job>> jobsAsync;
  final AsyncValue<List<NotificationEvent>> notificationsAsync;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final jobs = jobsAsync.valueOrNull ?? const <Job>[];
    final notifications = notificationsAsync.valueOrNull ?? const <NotificationEvent>[];
    final stats = _ProfileStats.fromJobs(pro, jobs);
    final latestLocation = pro.savedLocations.isEmpty
        ? null
        : pro.savedLocations.reduce(
            (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
          );
    final avatarProvider = resolveAvatarProvider(pro.profileImageUrl);
    final unreadCount = notifications.where((event) => !event.read).length;

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'My Profile',
                            style: TextStyle(
                              color: Color(0xFF1B1956),
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            showActions
                                ? 'Manage your profile and track your performance'
                                : 'Professional details and service performance',
                            style: const TextStyle(
                              color: Color(0xFF6C7197),
                              fontSize: 15,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _TopIconButton(
                      icon: Icons.notifications_none_rounded,
                      badgeCount: unreadCount,
                      onTap: () => context.push('/notifications'),
                    ),
                    const SizedBox(width: 10),
                    if (showActions)
                      _TopIconButton(
                        icon: Icons.settings_outlined,
                        onTap: () => context.push('/settings'),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x110E1330),
                        blurRadius: 28,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked = constraints.maxWidth < 620;
                      final profileSummary = Expanded(
                        child: _ProfileIdentity(
                          pro: pro,
                          avatarProvider: avatarProvider,
                          latestLocation: latestLocation?.address,
                        ),
                      );
                      final actions = showActions
                          ? Padding(
                              padding: EdgeInsets.only(
                                top: stacked ? 18 : 0,
                                left: stacked ? 0 : 16,
                              ),
                              child: Align(
                                alignment: stacked
                                    ? Alignment.centerLeft
                                    : Alignment.centerRight,
                                child: _InlineActionButton(
                                  label: 'Edit Profile',
                                  icon: Icons.edit_outlined,
                                  onTap: () => context.push('/profile/edit'),
                                ),
                              ),
                            )
                          : const SizedBox.shrink();

                      if (stacked) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[profileSummary, actions],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[profileSummary, actions],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                _PerformanceCard(stats: stats),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'My Services',
                  actionLabel: showActions ? 'Edit Profile' : null,
                  onActionTap: showActions
                      ? () => context.push('/profile/edit')
                      : null,
                  child: _ServicesGrid(categories: _serviceCategoriesFor(pro)),
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Account Overview',
                  actionLabel: 'View Jobs',
                  onActionTap: () => context.go('/history'),
                  child: Column(
                    children: <Widget>[
                      _OverviewRow(
                        icon: Icons.calendar_today_outlined,
                        iconBg: const Color(0xFFF1EAFF),
                        iconColor: const Color(0xFF7C5CFF),
                        title: 'Total Bookings',
                        subtitle: 'All time jobs assigned to you',
                        value: stats.totalAssigned.toString(),
                      ),
                      const _DividerSpace(),
                      _OverviewRow(
                        icon: Icons.event_available_outlined,
                        iconBg: const Color(0xFFEAF8EE),
                        iconColor: const Color(0xFF3FAF65),
                        title: 'Upcoming Jobs',
                        subtitle: stats.nextJobHint,
                        value: stats.upcomingJobs.toString(),
                      ),
                      const _DividerSpace(),
                      _OverviewRow(
                        icon: Icons.account_balance_wallet_outlined,
                        iconBg: const Color(0xFFFFF1E8),
                        iconColor: const Color(0xFFFF8A2A),
                        title: 'Wallet Balance',
                        subtitle: 'Closed and released earnings',
                        value: formatPkr(stats.walletBalance),
                      ),
                      const _DividerSpace(),
                      _OverviewRow(
                        icon: Icons.payments_outlined,
                        iconBg: const Color(0xFFEFF4FF),
                        iconColor: const Color(0xFF4B7CFF),
                        title: 'Pending Payments',
                        subtitle: 'Completed jobs waiting to close',
                        value: formatPkr(stats.pendingPayments),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _QuickActionsSection(showActions: showActions),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileIdentity extends StatelessWidget {
  const _ProfileIdentity({
    required this.pro,
    required this.avatarProvider,
    required this.latestLocation,
  });

  final AppUser pro;
  final ImageProvider<Object>? avatarProvider;
  final String? latestLocation;

  @override
  Widget build(BuildContext context) {
    final initials = pro.fullName.trim().isEmpty
        ? '?'
        : pro.fullName.trim().substring(0, 1).toUpperCase();
    final reviewText = pro.totalReviews <= 0
        ? 'No reviews yet'
        : '${pro.rating.toStringAsFixed(1)} (${pro.totalReviews} reviews)';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFD8C8FF), width: 3),
              ),
              child: CircleAvatar(
                radius: 46,
                backgroundColor: const Color(0xFFF2F4FB),
                backgroundImage: avatarProvider,
                child: avatarProvider == null
                    ? Text(
                        initials,
                        style: const TextStyle(
                          color: Color(0xFF1B1956),
                          fontWeight: FontWeight.w800,
                          fontSize: 28,
                        ),
                      )
                    : null,
              ),
            ),
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: pro.isOnline
                      ? const Color(0xFF5BC979)
                      : const Color(0xFFBAC4D3),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  Text(
                    pro.fullName,
                    style: const TextStyle(
                      color: Color(0xFF1B1956),
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  if (pro.isVerifiedPro)
                    const Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF7A5AF8),
                      size: 21,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  if (pro.role == UserRole.pro)
                    _IdentityTag(
                      icon: Icons.verified,
                      label: pro.isVerifiedPro ? 'Verified Pro' : 'Profile Active',
                    ),
                  _IdentityTag(
                    icon: Icons.star_rounded,
                    label: reviewText,
                    iconColor: const Color(0xFFF5A524),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (latestLocation != null && latestLocation!.trim().isNotEmpty)
                _InfoLine(
                  icon: Icons.location_on_outlined,
                  text: latestLocation!,
                ),
              if (pro.email.trim().isNotEmpty)
                _InfoLine(icon: Icons.mail_outline, text: pro.email.trim()),
            ],
          ),
        ),
      ],
    );
  }
}

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({required this.stats});

  final _ProfileStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2A58),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x160E1330),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Your Performance',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF413D70),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'All Time',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 18),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final items = <_MetricData>[
                _MetricData(
                  icon: Icons.work_outline_rounded,
                  value: stats.completedJobs.toString(),
                  label: 'Jobs Completed',
                  dotColor: const Color(0xFF7A5AF8),
                ),
                _MetricData(
                  icon: Icons.check_circle_outline_rounded,
                  value: '${stats.completionRate}%',
                  label: 'Completion Rate',
                  dotColor: const Color(0xFF7BDA94),
                ),
                _MetricData(
                  icon: Icons.star_rounded,
                  value: stats.ratingText,
                  label: 'Average Rating',
                  dotColor: const Color(0xFFFFA451),
                ),
                _MetricData(
                  icon: Icons.currency_rupee_rounded,
                  value: formatPkr(stats.totalEarnings),
                  label: 'Total Earnings',
                  dotColor: const Color(0xFF5A8BFF),
                ),
              ];

              if (compact) {
                return Column(
                  children: items
                      .map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _MetricTile(item: item, compact: true),
                          ))
                      .toList(growable: false),
                );
              }

              return Row(
                children: items
                    .map(
                      (item) => Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: item == items.first ? 0 : 10,
                          ),
                          child: _MetricTile(item: item),
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ServicesGrid extends StatelessWidget {
  const _ServicesGrid({required this.categories});

  final List<JobCategory> categories;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: categories
          .map((category) => _ServiceCard(category: category))
          .toList(growable: false),
    );
  }
}

class _QuickActionsSection extends StatelessWidget {
  const _QuickActionsSection({required this.showActions});

  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final actions = <_QuickActionData>[
      _QuickActionData(
        icon: Icons.edit_note_rounded,
        title: 'Edit Profile',
        subtitle: 'Update photo, contact and default address',
        background: const Color(0xFFF3EDFF),
        iconColor: const Color(0xFF7C5CFF),
        onTap: () => context.push('/profile/edit'),
      ),
      _QuickActionData(
        icon: Icons.notifications_active_outlined,
        title: 'Notifications',
        subtitle: 'Check messages, nearby jobs and reminders',
        background: const Color(0xFFEFF4FF),
        iconColor: const Color(0xFF4E78FF),
        onTap: () => context.push('/notifications'),
      ),
      _QuickActionData(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Earnings',
        subtitle: 'Review withdrawals and app commission status',
        background: const Color(0xFFFFF1E8),
        iconColor: const Color(0xFFFF8A2A),
        onTap: () => context.push('/earnings'),
      ),
      _QuickActionData(
        icon: Icons.settings_suggest_outlined,
        title: showActions ? 'App Settings' : 'Open Settings',
        subtitle: 'Language, privacy and notification controls',
        background: const Color(0xFFEAF8EE),
        iconColor: const Color(0xFF37A95E),
        onTap: () => context.push('/settings'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Quick Actions',
          style: TextStyle(
            color: Color(0xFF1B1956),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = constraints.maxWidth < 720
                ? (constraints.maxWidth - 12) / 2
                : (constraints.maxWidth - 36) / 4;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: actions
                  .map(
                    (action) => _QuickActionCard(
                      data: action,
                      width: tileWidth,
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.actionLabel,
    this.onActionTap,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x100E1330),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF1B1956),
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              if (actionLabel != null && onActionTap != null)
                TextButton(
                  onPressed: onActionTap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        actionLabel!,
                        style: const TextStyle(
                          color: Color(0xFF7A5AF8),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 13,
                        color: Color(0xFF7A5AF8),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x100E1330),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF1B1956)),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF8A63FF),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFF8F6FF), width: 2),
                ),
                child: Text(
                  badgeCount > 9 ? '9+' : '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InlineActionButton extends StatelessWidget {
  const _InlineActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        backgroundColor: const Color(0xFFF8F6FF),
        foregroundColor: const Color(0xFF1B1956),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _IdentityTag extends StatelessWidget {
  const _IdentityTag({
    required this.icon,
    required this.label,
    this.iconColor = const Color(0xFF7A5AF8),
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3EEFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF5F52A5),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 17, color: const Color(0xFF8589A9)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF6C7197),
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.icon,
    required this.value,
    required this.label,
    required this.dotColor,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color dotColor;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.item, this.compact = false});

  final _MetricData item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3A3767),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: item.dotColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, color: item.dotColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.label,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFC4C3E6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.category});

  final JobCategory category;

  @override
  Widget build(BuildContext context) {
    final palette = _servicePalette(category);
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(palette.icon, color: palette.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  category.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1B1956),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    const CircleAvatar(
                      radius: 4,
                      backgroundColor: Color(0xFF59C77B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Active',
                      style: TextStyle(
                        color: palette.accent.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewRow extends StatelessWidget {
  const _OverviewRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF1B1956),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF7B7F9C),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF23215F),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        const SizedBox(width: 8),
        const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: Color(0xFFB3B6CB),
        ),
      ],
    );
  }
}

class _DividerSpace extends StatelessWidget {
  const _DividerSpace();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Divider(height: 1, color: Color(0xFFEDECF6)),
    );
  }
}

class _QuickActionData {
  const _QuickActionData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.background,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color background;
  final Color iconColor;
  final VoidCallback onTap;
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.data, required this.width});

  final _QuickActionData data;
  final double width;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: data.onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: data.background,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(data.icon, color: data.iconColor),
            ),
            const SizedBox(height: 16),
            Text(
              data.title,
              style: const TextStyle(
                color: Color(0xFF1B1956),
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              data.subtitle,
              style: const TextStyle(
                color: Color(0xFF70759B),
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStats {
  const _ProfileStats({
    required this.totalAssigned,
    required this.completedJobs,
    required this.upcomingJobs,
    required this.completionRate,
    required this.totalEarnings,
    required this.walletBalance,
    required this.pendingPayments,
    required this.averageRating,
    required this.nextJobHint,
  });

  final int totalAssigned;
  final int completedJobs;
  final int upcomingJobs;
  final int completionRate;
  final double totalEarnings;
  final double walletBalance;
  final double pendingPayments;
  final double averageRating;
  final String nextJobHint;

  String get ratingText => averageRating <= 0
      ? 'New'
      : averageRating.toStringAsFixed(1);

  factory _ProfileStats.fromJobs(AppUser pro, List<Job> jobs) {
    final completed = jobs.where((job) {
      return job.status == JobStatus.completed ||
          job.status == JobStatus.paidClosed;
    }).toList(growable: false);
    final closed = jobs
        .where((job) => job.status == JobStatus.paidClosed)
        .toList(growable: false);
    final pending = jobs
        .where((job) => job.status == JobStatus.completed)
        .toList(growable: false);
    final upcoming = jobs.where((job) {
      return job.status == JobStatus.posted ||
          job.status == JobStatus.available ||
          job.status == JobStatus.inProcess;
    }).toList(growable: false);
    upcoming.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final walletBalance = closed.fold<double>(
      0,
      (sum, job) => sum + (job.finalAmount ?? job.fixedPrice),
    );
    final pendingPayments = pending.fold<double>(
      0,
      (sum, job) => sum + (job.finalAmount ?? job.fixedPrice),
    );

    return _ProfileStats(
      totalAssigned: jobs.length,
      completedJobs: completed.length,
      upcomingJobs: upcoming.length,
      completionRate: jobs.isEmpty
          ? 0
          : ((completed.length / jobs.length) * 100).round(),
      totalEarnings: pro.totalEarnings,
      walletBalance: walletBalance,
      pendingPayments: pendingPayments,
      averageRating: pro.rating,
      nextJobHint: upcoming.isEmpty
          ? 'No active job scheduled right now'
          : 'Latest active job ${formatDateTime(upcoming.first.createdAt)}',
    );
  }
}

class _ServicePalette {
  const _ServicePalette({
    required this.background,
    required this.accent,
    required this.icon,
  });

  final Color background;
  final Color accent;
  final IconData icon;
}

List<JobCategory> _serviceCategoriesFor(AppUser pro) {
  if (pro.preferredCategories.isNotEmpty) {
    return pro.preferredCategories.take(4).toList(growable: false);
  }
  return const <JobCategory>[
    JobCategory.electrician,
    JobCategory.plumbing,
    JobCategory.cleaning,
    JobCategory.applianceRepair,
  ];
}

_ServicePalette _servicePalette(JobCategory category) {
  return switch (category) {
    JobCategory.electrician => const _ServicePalette(
      background: Color(0xFFF2ECFF),
      accent: Color(0xFF7C5CFF),
      icon: Icons.bolt_rounded,
    ),
    JobCategory.plumbing => const _ServicePalette(
      background: Color(0xFFEEF4FF),
      accent: Color(0xFF4E78FF),
      icon: Icons.plumbing_rounded,
    ),
    JobCategory.cleaning => const _ServicePalette(
      background: Color(0xFFFFF2EA),
      accent: Color(0xFFFF8A2A),
      icon: Icons.cleaning_services_rounded,
    ),
    JobCategory.applianceRepair || JobCategory.acRepair => const _ServicePalette(
      background: Color(0xFFEAF8EE),
      accent: Color(0xFF37A95E),
      icon: Icons.kitchen_rounded,
    ),
    JobCategory.carpenter => const _ServicePalette(
      background: Color(0xFFFFF4E8),
      accent: Color(0xFFCC7A00),
      icon: Icons.handyman_rounded,
    ),
    JobCategory.painter => const _ServicePalette(
      background: Color(0xFFEFF4FF),
      accent: Color(0xFF3F6DF6),
      icon: Icons.format_paint_rounded,
    ),
    JobCategory.registeredNurse => const _ServicePalette(
      background: Color(0xFFFFEEF1),
      accent: Color(0xFFE14D77),
      icon: Icons.medical_services_outlined,
    ),
  };
}
