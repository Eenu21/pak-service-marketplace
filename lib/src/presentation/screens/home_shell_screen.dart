import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/pro_balance_rules.dart';
import '../../core/theme/responsive.dart';
import '../../domain/models.dart';
import '../controllers/auth_controller.dart';
import '../controllers/chat_controller.dart';
import '../controllers/payments_controller.dart';
import 'create_job_screen.dart';
import 'inbox_screen.dart';
import 'job_history_screen.dart';
import 'nearby_jobs_screen.dart';
import 'profile_screen.dart';
import 'pro_earnings_screen.dart';
import 'pro_profile_screen.dart';

bool _shouldUseProShell(AppUser user) {
  if (user.role == UserRole.pro) {
    return true;
  }
  final hasPayment = (user.paymentAccount ?? '').trim().isNotEmpty;
  return user.preferredCategories.isNotEmpty ||
      user.cnicVerified ||
      user.policeVerified ||
      hasPayment;
}

class HomeShellScreen extends ConsumerStatefulWidget {
  const HomeShellScreen({super.key});

  @override
  ConsumerState<HomeShellScreen> createState() => _HomeShellScreenState();
}

class _HomeShellScreenState extends ConsumerState<HomeShellScreen> {
  int? _index;
  String? _seededIndexKey;
  ProDueLevel? _lastPromptedLevel;

  Future<void> _showStrongWarningDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Urgent Warning'),
          content: const Text(
            'Urgent: Pay your dues now or your account will be locked soon.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/earnings');
              },
              child: const Text('Go to Balance'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLockedDialog() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Account Locked',
      pageBuilder: (context, animation, secondaryAnimation) {
        return Scaffold(
          backgroundColor: const Color(0xFFF6F8FC),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.lock_outline_rounded,
                            size: 54,
                            color: Color(0xFFB3261E),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Account Locked',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Account Locked. Please clear your 2,000 PKR due to continue bidding on jobs.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                context.push('/earnings');
                              },
                              child: const Text('Open Balance Page'),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Continue in Read-Only Mode'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _promptIfRequired(ProFinancialStatus status) {
    if (!mounted) {
      return;
    }
    final level = status.level;
    if (level == ProDueLevel.clear || level == ProDueLevel.mild) {
      _lastPromptedLevel = null;
      return;
    }
    if (_lastPromptedLevel == level) {
      return;
    }
    _lastPromptedLevel = level;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (level == ProDueLevel.locked) {
        _showLockedDialog();
      } else if (level == ProDueLevel.strong) {
        _showStrongWarningDialog();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.valueOrNull;
    if (authState.isLoading && user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (user.role == UserRole.admin) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/admin'));
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final useProShell = _shouldUseProShell(user);
    final seededIndexKey = '${user.id}:${user.role.name}';
    if (_seededIndexKey != seededIndexKey) {
      _seededIndexKey = seededIndexKey;
      _index = _preferredInitialIndexFor(user);
    }
    final financial = ref.watch(proFinancialStatusProvider);
    if (useProShell && financial != null) {
      _promptIfRequired(financial);
    }
    final notificationsAsync = ref.watch(notificationsProvider(user.id));
    final unreadInboxCount =
        notificationsAsync.valueOrNull
            ?.where((event) => !event.read && event.type == 'message')
            .length ??
        0;

    final destinations = _destinationsFor(
      context,
      user,
      useProShell: useProShell,
      unreadInboxCount: unreadInboxCount,
    );
    final safeIndex = (_index ?? _preferredInitialIndexFor(user)).clamp(
      0,
      destinations.length - 1,
    );
    final isExpanded = Responsive.isExpanded(context);
    final currentScreen = AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(
        key: ValueKey<int>(safeIndex),
        child: destinations[safeIndex].screen,
      ),
    );

    if (isExpanded) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                child: NavigationRail(
                  selectedIndex: safeIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _index = index),
                  labelType: NavigationRailLabelType.all,
                  groupAlignment: -0.7,
                  destinations: destinations
                      .map(
                        (item) => NavigationRailDestination(
                          icon: _buildNavIcon(
                            icon: item.icon,
                            badgeCount: item.badgeCount,
                          ),
                          selectedIcon: _buildNavIcon(
                            icon: item.selectedIcon,
                            badgeCount: item.badgeCount,
                            selected: true,
                          ),
                          label: Text(
                            item.label,
                            style: item.badgeCount > 0 && item.isInbox
                                ? const TextStyle(
                                    color: Color(0xFFB00020),
                                    fontWeight: FontWeight.w700,
                                  )
                                : null,
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: currentScreen),
          ],
        ),
      );
    }

    return Scaffold(
      body: currentScreen,
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: destinations
            .map(
              (item) => NavigationDestination(
                icon: _buildNavIcon(
                  icon: item.icon,
                  badgeCount: item.badgeCount,
                ),
                selectedIcon: _buildNavIcon(
                  icon: item.selectedIcon,
                  badgeCount: item.badgeCount,
                  selected: true,
                ),
                label: item.label,
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  int _preferredInitialIndexFor(AppUser _) {
    return 0;
  }

  Widget _buildNavIcon({
    required IconData icon,
    required int badgeCount,
    bool selected = false,
  }) {
    if (badgeCount <= 0) {
      return Icon(icon);
    }
    final text = badgeCount > 99 ? '99+' : '$badgeCount';
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Icon(icon),
        Positioned(
          right: -9,
          top: -8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFB00020)
                  : const Color(0xFFD32F2F),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<_HomeDestination> _destinationsFor(
    BuildContext context,
    AppUser user, {
    required bool useProShell,
    required int unreadInboxCount,
  }) {
    final t = AppLocalizations.of(context);
    final inboxLabel = unreadInboxCount > 0
        ? 'Inbox($unreadInboxCount)'
        : 'Inbox';
    if (useProShell) {
      return <_HomeDestination>[
        _HomeDestination(
          label: 'Home',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          screen: const NearbyJobsScreen(),
        ),
        _HomeDestination(
          label: 'My Jobs',
          icon: Icons.work_outline,
          selectedIcon: Icons.work,
          screen: const JobHistoryScreen(),
        ),
        _HomeDestination(
          label: 'Find Jobs',
          icon: Icons.business_center_outlined,
          selectedIcon: Icons.business_center,
          screen: const NearbyJobsScreen(),
        ),
        _HomeDestination(
          label: t.t('earnings'),
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet,
          screen: ProEarningsScreen(),
        ),
        _HomeDestination(
          label: t.t('profile'),
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          screen: ProProfileScreen(proId: user.id, initialPro: user),
        ),
      ];
    }

    return <_HomeDestination>[
      _HomeDestination(
        label: 'Home',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        screen: const NearbyJobsScreen(),
      ),
      _HomeDestination(
        label: 'Bookings',
        icon: Icons.calendar_month_outlined,
        selectedIcon: Icons.calendar_month,
        screen: const JobHistoryScreen(),
      ),
      _HomeDestination(
        label: 'Post a Job',
        icon: Icons.add_circle_outline_rounded,
        selectedIcon: Icons.add_circle_rounded,
        screen: const CreateJobScreen(),
      ),
      _HomeDestination(
        label: 'Messages',
        icon: Icons.chat_bubble_outline_rounded,
        selectedIcon: Icons.chat_bubble_rounded,
        screen: const InboxScreen(),
        badgeCount: unreadInboxCount,
        isInbox: true,
      ),
      _HomeDestination(
        label: t.t('profile'),
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        screen: const ProfileScreen(),
      ),
    ];
  }
}

class _HomeDestination {
  const _HomeDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
    this.badgeCount = 0,
    this.isInbox = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
  final int badgeCount;
  final bool isInbox;
}
