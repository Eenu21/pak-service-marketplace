import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/avatar_utils.dart';
import '../../core/services/formatters.dart';
import '../../core/services/pro_balance_rules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/responsive.dart';
import '../../domain/models.dart';
import '../controllers/auth_controller.dart';
import '../controllers/chat_controller.dart';
import '../controllers/jobs_controller.dart';
import '../controllers/payments_controller.dart';

bool _shouldTreatAsPro(AppUser user) {
  if (user.role == UserRole.pro) {
    return true;
  }
  final hasPayment = (user.paymentAccount ?? '').trim().isNotEmpty;
  return user.preferredCategories.isNotEmpty ||
      user.cnicVerified ||
      user.policeVerified ||
      hasPayment;
}

class NearbyJobsScreen extends ConsumerWidget {
  const NearbyJobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final t = AppLocalizations.of(context);
    if (user == null) {
      return Scaffold(body: Center(child: Text(t.t('not_logged_in'))));
    }

    final isPro = _shouldTreatAsPro(user);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FF),
      body: SafeArea(
        child: ResponsiveContainer(
          child: isPro
              ? _ProJobsView(user: user)
              : _CustomerHomeView(user: user),
        ),
      ),
    );
  }
}

class _CustomerHomeView extends ConsumerStatefulWidget {
  const _CustomerHomeView({required this.user});

  final AppUser user;

  @override
  ConsumerState<_CustomerHomeView> createState() => _CustomerHomeViewState();
}

class _CustomerHomeViewState extends ConsumerState<_CustomerHomeView> {
  late final TextEditingController _searchController;
  String _searchQuery = '';
  JobCategory? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final myJobsAsync = ref.watch(jobsForCurrentUserProvider);
    final paymentsAsync = ref.watch(paymentsForCurrentUserProvider);
    final notificationsAsync = ref.watch(notificationsProvider(user.id));
    final unreadCount = notificationsAsync.maybeWhen(
      data: (events) => events.where((event) => !event.read).length,
      orElse: () => 0,
    );
    final recommendations = _recommendationsFor(
      category: _selectedCategory,
      query: _searchQuery,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 24),
      children: <Widget>[
        _TopLocationBar(
          user: user,
          isPro: false,
          unreadCount: unreadCount,
          onBellTap: () => context.push('/notifications'),
        ),
        const SizedBox(height: 22),
        Text(
          'Good morning, ${_firstName(user.fullName)}',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1C1B52),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'How can we help you today?',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF6E6C91),
          ),
        ),
        const SizedBox(height: 20),
        _SearchHero(
          controller: _searchController,
          onChanged: (value) => setState(() => _searchQuery = value),
        ),
        const SizedBox(height: 18),
        _CategoryRow(
          selectedCategory: _selectedCategory,
          onSelected: (value) {
            setState(() {
              _selectedCategory =
                  _selectedCategory == value ? null : value;
            });
          },
        ),
        const SizedBox(height: 20),
        _CustomerPromoCard(
          onPostJob: () => context.push('/post-job'),
        ).animate().fadeIn(duration: 320.ms).slideY(begin: 0.08, end: 0),
        const SizedBox(height: 18),
        myJobsAsync.when(
          loading: () => const _LoadingSection(height: 102),
          error: (error, _) => _InfoBanner(message: error.toString()),
          data: (jobs) => _QuickActionsRow(
            activeJobs: jobs
                .where(
                  (job) =>
                      job.status == JobStatus.available ||
                      job.status == JobStatus.inProcess,
                )
                .length,
            walletCount: paymentsAsync.valueOrNull?.length ?? 0,
          ),
        ),
        const SizedBox(height: 22),
        _SectionHeader(
          title: 'How it works',
          trailing: TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Post a job, review offers, schedule, and pay.'),
              ),
            ),
            child: const Text('View all steps'),
          ),
        ),
        const SizedBox(height: 12),
        const _HowItWorksStrip(),
        const SizedBox(height: 24),
        _SectionHeader(
          title: 'Recommended for you',
          trailing: TextButton(
            onPressed: () => setState(() {
              _selectedCategory = null;
              _searchQuery = '';
              _searchController.clear();
            }),
            child: const Text('See all'),
          ),
        ),
        const SizedBox(height: 12),
        if (recommendations.isEmpty)
          const _InfoBanner(
            message: 'No services matched your search. Try another keyword.',
          )
        else
          SizedBox(
            height: 282,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recommendations.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final item = recommendations[index];
                return SizedBox(
                  width: 212,
                  child: _RecommendedServiceCard(item: item),
                ).animate().fadeIn(delay: (index * 60).ms);
              },
            ),
          ),
      ],
    );
  }
}

class _ProJobsView extends ConsumerStatefulWidget {
  const _ProJobsView({required this.user});

  final AppUser user;

  @override
  ConsumerState<_ProJobsView> createState() => _ProJobsViewState();
}

class _ProJobsViewState extends ConsumerState<_ProJobsView> {
  int _activeTab = 0;
  int _sortIndex = 0;

  @override
  Widget build(BuildContext context) {
    final category = ref.watch(selectedJobCategoryProvider);
    final jobsAsync = ref.watch(nearbyJobsProvider);
    final myJobsAsync = ref.watch(jobsForCurrentUserProvider);
    final notificationsAsync = ref.watch(notificationsProvider(widget.user.id));
    final financial = ref.watch(proFinancialStatusProvider);
    final unreadCount = notificationsAsync.maybeWhen(
      data: (events) =>
          events.where((event) => !event.read).length +
          ((financial != null && financial.level != ProDueLevel.clear) ? 1 : 0),
      orElse: () =>
          (financial != null && financial.level != ProDueLevel.clear) ? 1 : 0,
    );
    final allCategories = widget.user.preferredCategories.isEmpty
        ? JobCategory.values
        : widget.user.preferredCategories;

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 24),
      children: <Widget>[
        _TopLocationBar(
          user: widget.user,
          isPro: true,
          unreadCount: unreadCount,
          onBellTap: () => context.push('/notifications'),
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Good morning, ${_firstName(widget.user.fullName)}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFF1A1C52),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Find jobs. Earn more.',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: const Color(0xFF18184E),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'New jobs posted near you',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF78769A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 190,
              child: myJobsAsync.when(
                loading: () => const _StatsCard(
                  rating: 0,
                  jobsCompleted: 0,
                  loading: true,
                ),
                error: (_, __) => _StatsCard(
                  rating: widget.user.rating,
                  jobsCompleted: 0,
                ),
                data: (jobs) => _StatsCard(
                  rating: widget.user.rating,
                  jobsCompleted: jobs
                      .where(
                        (job) =>
                            job.status == JobStatus.completed ||
                            job.status == JobStatus.paidClosed,
                      )
                      .length,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: <Widget>[
            Expanded(
              child: _SegmentTab(
                label: 'Available Jobs',
                icon: Icons.work_outline_rounded,
                selected: _activeTab == 0,
                onTap: () => setState(() => _activeTab = 0),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SegmentTab(
                label: 'My Bids',
                icon: Icons.assignment_outlined,
                selected: _activeTab == 1,
                onTap: () => setState(() => _activeTab = 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_activeTab == 0) ...<Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _FilterChipButton(
                  icon: Icons.grid_view_rounded,
                  label: category.displayName,
                  onTap: () => _showCategorySheet(context, allCategories, category),
                ),
                const SizedBox(width: 10),
                _FilterChipButton(
                  icon: Icons.currency_rupee_rounded,
                  label: 'Price',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Price filtering can be added next.'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _FilterChipButton(
                  icon: Icons.place_outlined,
                  label: 'Distance',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Distance sorting is already reflected in the list.'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _FilterChipButton(
                  icon: Icons.swap_vert_rounded,
                  label: _sortIndex == 0 ? 'Newest' : 'Budget',
                  onTap: () => setState(() => _sortIndex = (_sortIndex + 1) % 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          jobsAsync.when(
            loading: () => const _LoadingSection(height: 340),
            error: (error, _) => _InfoBanner(message: error.toString()),
            data: (jobs) {
              final sorted = [...jobs];
              if (_sortIndex == 1) {
                sorted.sort((a, b) => b.fixedPrice.compareTo(a.fixedPrice));
              }
              if (sorted.isEmpty) {
                return const _InfoBanner(
                  message: 'No open jobs match your selected service right now.',
                );
              }
              return Column(
                children: List<Widget>.generate(sorted.length, (index) {
                  final job = sorted[index];
                  return Padding(
                    padding: EdgeInsets.only(bottom: index == sorted.length - 1 ? 0 : 14),
                    child: _FindJobCard(job: job),
                  ).animate().fadeIn(delay: (index * 55).ms).slideY(begin: 0.06, end: 0);
                }),
              );
            },
          ),
        ] else ...<Widget>[
          const _InfoBanner(
            message:
                'Bid submission is fully working from each job detail screen. This tab can be expanded into a dedicated bids dashboard next.',
          ),
          const SizedBox(height: 12),
          myJobsAsync.when(
            loading: () => const _LoadingSection(height: 180),
            error: (error, _) => _InfoBanner(message: error.toString()),
            data: (jobs) {
              if (jobs.isEmpty) {
                return const _InfoBanner(
                  message: 'Your accepted and in-progress jobs will appear here.',
                );
              }
              return Column(
                children: jobs.take(4).map((job) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CompactJobStatusCard(job: job),
                )).toList(growable: false),
              );
            },
          ),
        ],
      ],
    );
  }

  Future<void> _showCategorySheet(
    BuildContext context,
    List<JobCategory> categories,
    JobCategory selected,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: categories.map((item) {
              final active = item == selected;
              return ListTile(
                leading: Icon(
                  active ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: active ? const Color(0xFF7B5CFF) : Colors.grey,
                ),
                title: Text(item.displayName),
                onTap: () {
                  ref.read(selectedJobCategoryProvider.notifier).state = item;
                  Navigator.of(context).pop();
                },
              );
            }).toList(growable: false),
          ),
        );
      },
    );
  }
}

class _TopLocationBar extends StatelessWidget {
  const _TopLocationBar({
    required this.user,
    required this.isPro,
    required this.unreadCount,
    required this.onBellTap,
  });

  final AppUser user;
  final bool isPro;
  final int unreadCount;
  final VoidCallback onBellTap;

  @override
  Widget build(BuildContext context) {
    final avatar = resolveAvatarProvider(user.profileImageUrl);
    final address = user.savedLocations.isEmpty
        ? 'Your saved location'
        : user.savedLocations.last.address;

    return Row(
      children: <Widget>[
        if (isPro)
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.menu_rounded, color: Color(0xFF27265B)),
          )
        else
          const Icon(Icons.location_on_rounded, color: Color(0xFF8A63FF)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _shortAddress(address),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF232456),
                ),
              ),
              if (isPro)
                Text(
                  'Change location',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF7A5DFF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        InkWell(
          onTap: onBellTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                const Center(
                  child: Icon(
                    Icons.notifications_none_rounded,
                    color: Color(0xFF27265B),
                  ),
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 10,
                    top: 10,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Color(0xFF8A63FF),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 18,
                backgroundImage: avatar,
                backgroundColor: const Color(0xFFECE7FF),
                child: avatar == null
                    ? Text(
                        _firstLetter(user.fullName),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2A2759),
                        ),
                      )
                    : null,
              ),
              if (isPro) ...<Widget>[
                const SizedBox(width: 8),
                const Icon(Icons.circle, size: 10, color: Color(0xFF63C36E)),
                const SizedBox(width: 6),
                const Text(
                  'Online',
                  style: TextStyle(
                    color: Color(0xFF2E2F61),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SearchHero extends StatelessWidget {
  const _SearchHero({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDDD9F5)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F6A54C6),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.search_rounded, color: Color(0xFFA3A0BC)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: 'Search for a service...',
                hintStyle: TextStyle(
                  color: Color(0xFFB3AFC7),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.selectedCategory,
    required this.onSelected,
  });

  final JobCategory? selectedCategory;
  final ValueChanged<JobCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    const order = <JobCategory>[
      JobCategory.cleaning,
      JobCategory.plumbing,
      JobCategory.electrician,
      JobCategory.applianceRepair,
      JobCategory.carpenter,
    ];

    return SizedBox(
      height: 106,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: order.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _CategoryCard(
              icon: Icons.handyman_rounded,
              label: 'All Services',
              selected: selectedCategory == null,
              onTap: () => onSelected(null),
            );
          }
          final category = order[index - 1];
          final isMore = index == order.length;
          return _CategoryCard(
            icon: isMore ? Icons.grid_view_rounded : _categoryIcon(category),
            label: isMore ? 'More' : _homeCategoryLabel(category),
            selected: !isMore && selectedCategory == category,
            onTap: () => onSelected(category),
          );
        },
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Column(
        children: <Widget>[
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFEAE1FF) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x0E6B5EC6),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: selected ? const Color(0xFF7B52FF) : const Color(0xFF515167),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 96,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? const Color(0xFF7B52FF) : const Color(0xFF52506A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerPromoCard extends StatelessWidget {
  const _CustomerPromoCard({required this.onPostJob});

  final VoidCallback onPostJob;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFEDE7FF), Color(0xFFF8F6FF), Color(0xFFE8E0F2)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'New',
                    style: TextStyle(
                      color: Color(0xFF7B52FF),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Professional\nService. Simplified.',
                  style: TextStyle(
                    fontSize: 21,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1F2056),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Trusted experts, on-time service and 100% satisfaction.',
                  style: TextStyle(
                    color: Color(0xFF666487),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: onPostJob,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A57),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text('Post a Job'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0xFFF7F2FF), Color(0xFFE7DDF8)],
                ),
              ),
              child: Stack(
                children: <Widget>[
                  Positioned(
                    right: 24,
                    bottom: 28,
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x18000000),
                            blurRadius: 18,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    top: 28,
                    child: Icon(
                      Icons.chair_rounded,
                      size: 86,
                      color: AppTheme.brandNavy.withValues(alpha: 0.22),
                    ),
                  ),
                  const Positioned(
                    right: 30,
                    top: 24,
                    child: Icon(
                      Icons.light_mode_outlined,
                      color: Color(0x88615577),
                      size: 38,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.activeJobs,
    required this.walletCount,
  });

  final int activeJobs;
  final int walletCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _QuickActionCard(
            color: const Color(0xFFEAE1FF),
            iconColor: const Color(0xFF7B52FF),
            icon: Icons.add_circle_outline_rounded,
            title: 'Post a Job',
            subtitle: 'Get started in 2 mins',
            onTap: () => context.push('/post-job'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionCard(
            color: const Color(0xFFE6F8E8),
            iconColor: const Color(0xFF55A962),
            icon: Icons.track_changes_rounded,
            title: 'Track Jobs',
            subtitle: '$activeJobs active',
            onTap: () => context.push('/history'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionCard(
            color: const Color(0xFFFFEEE0),
            iconColor: const Color(0xFFF28E3E),
            icon: Icons.calendar_today_outlined,
            title: 'My Bookings',
            subtitle: 'View upcoming jobs',
            onTap: () => context.push('/history'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionCard(
            color: const Color(0xFFE6EEFF),
            iconColor: const Color(0xFF5688FF),
            icon: Icons.account_balance_wallet_outlined,
            title: 'Wallet',
            subtitle: walletCount == 0
                ? 'Payments & invoices'
                : '$walletCount payment records',
            onTap: () => context.push('/history'),
          ),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.color,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color color;
  final Color iconColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x0C000000),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF212254),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF8985A2), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItWorksStrip extends StatelessWidget {
  const _HowItWorksStrip();

  @override
  Widget build(BuildContext context) {
    final items = <({IconData icon, String title, String subtitle, Color color})>[
      (
        icon: Icons.description_outlined,
        title: '1. Post a job',
        subtitle: 'Tell us what you need',
        color: const Color(0xFFE9E2FF),
      ),
      (
        icon: Icons.groups_outlined,
        title: '2. Get matched',
        subtitle: 'We find the best pros',
        color: const Color(0xFFE8F6E8),
      ),
      (
        icon: Icons.calendar_month_outlined,
        title: '3. Schedule',
        subtitle: 'Pick a time that suits you',
        color: const Color(0xFFFFEEE3),
      ),
      (
        icon: Icons.verified_user_outlined,
        title: '4. Get it done',
        subtitle: 'Sit back and relax',
        color: const Color(0xFFEAF0FF),
      ),
    ];

    return Row(
      children: items.map((item) {
        final index = items.indexOf(item);
        return Expanded(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        color: item.color,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(item.icon, color: const Color(0xFF5A50A5), size: 32),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      item.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF272657),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF8B87A3),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (index != items.length - 1)
                const Padding(
                  padding: EdgeInsets.only(bottom: 44),
                  child: Icon(Icons.more_horiz_rounded, color: Color(0xFFC5C1DA)),
                ),
            ],
          ),
        );
      }).toList(growable: false),
    );
  }
}

class _RecommendedServiceCard extends StatelessWidget {
  const _RecommendedServiceCard({required this.item});

  final _HomeServiceRecommendation item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/post-job'),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      item.accent.withValues(alpha: 0.22),
                      item.accent.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Stack(
                  children: <Widget>[
                    Positioned(
                      right: 16,
                      top: 14,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: Color(0x33FFFFFF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.bookmark_border_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Center(
                      child: Icon(
                        item.icon,
                        size: 58,
                        color: const Color(0xFFFDFDFF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF222253),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF7B731)),
                const SizedBox(width: 4),
                Text(
                  '${item.rating.toStringAsFixed(1)} (${item.reviews})',
                  style: const TextStyle(
                    color: Color(0xFF74718E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Text(
                  item.priceLabel,
                  style: const TextStyle(
                    color: Color(0xFF222253),
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                const Text(
                  'Onwards',
                  style: TextStyle(color: Color(0xFF8C89A3)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.rating,
    required this.jobsCompleted,
    this.loading = false,
  });

  final double rating;
  final int jobsCompleted;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 24,
            offset: Offset(0, 12),
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
                  'Your Stats',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2A295F),
                  ),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EAFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.insights_outlined, color: Color(0xFF8A63FF)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: _StatColumn(
                  value: loading ? '--' : rating.toStringAsFixed(1),
                  label: 'Rating',
                  trailingStar: true,
                ),
              ),
              Container(width: 1, height: 48, color: const Color(0xFFE8E5F5)),
              Expanded(
                child: _StatColumn(
                  value: loading ? '--' : '$jobsCompleted',
                  label: 'Jobs Completed',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.value,
    required this.label,
    this.trailingStar = false,
  });

  final String value;
  final String label;
  final bool trailingStar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF19194E),
              ),
            ),
            if (trailingStar) ...<Widget>[
              const SizedBox(width: 4),
              const Icon(Icons.star_rounded, size: 20, color: Color(0xFFF5B638)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF8A87A1),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF0EAFF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFF8563FF) : const Color(0xFFE2DEF1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: selected ? const Color(0xFF7B52FF) : const Color(0xFF7C7894)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? const Color(0xFF7B52FF) : const Color(0xFF77738E),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF595675),
        side: const BorderSide(color: Color(0xFFDFDAF0)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _FindJobCard extends StatelessWidget {
  const _FindJobCard({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final accent = _categoryAccent(job.category);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              _categoryIcon(job.category),
              color: accent,
              size: 34,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (_isFresh(job))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0EAFF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'New',
                      style: TextStyle(
                        color: Color(0xFF7B52FF),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                if (_isFresh(job)) const SizedBox(height: 10),
                Text(
                  job.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E1D55),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    const Icon(Icons.location_on_outlined, size: 17, color: Color(0xFF88849F)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        job.maskedAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF7F7A96),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  job.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF6E6A84),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _TagPill(
                      label: job.category.displayName,
                      background: accent.withValues(alpha: 0.14),
                      foreground: accent,
                    ),
                    _TagPill(
                      label: _jobTypeLabel(job),
                      background: const Color(0xFFF6F2FF),
                      foreground: const Color(0xFF8667F7),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Budget',
                  style: TextStyle(
                    color: Color(0xFF6C6883),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _budgetRange(job.fixedPrice),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1B1A54),
                  ),
                ),
                const SizedBox(height: 14),
                _MetaLine(
                  icon: Icons.access_time_rounded,
                  text: _postedAgo(job.createdAt),
                ),
                const SizedBox(height: 8),
                _MetaLine(
                  icon: Icons.place_outlined,
                  text: _distanceGuess(job),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7B52FF),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => context.push('/job/${job.id}', extra: job),
                    child: const Text('View Job'),
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

class _CompactJobStatusCard extends StatelessWidget {
  const _CompactJobStatusCard({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/job/${job.id}', extra: job),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _categoryAccent(job.category).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(_categoryIcon(job.category), color: _categoryAccent(job.category)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    job.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF242457),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    job.maskedAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF827E97)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1EBFF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                job.status.value.replaceAll('_', ' '),
                style: const TextStyle(
                  color: Color(0xFF7A59FF),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: const Color(0xFF8B88A2)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF7A7793),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF202154),
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _LoadingSection extends StatelessWidget {
  const _LoadingSection({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      alignment: Alignment.center,
      child: const CircularProgressIndicator(),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2DEF0)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF5F5B75),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HomeServiceRecommendation {
  const _HomeServiceRecommendation({
    required this.category,
    required this.title,
    required this.rating,
    required this.reviews,
    required this.priceLabel,
    required this.accent,
    required this.icon,
  });

  final JobCategory category;
  final String title;
  final double rating;
  final int reviews;
  final String priceLabel;
  final Color accent;
  final IconData icon;
}

const List<_HomeServiceRecommendation> _homeRecommendations =
    <_HomeServiceRecommendation>[
      _HomeServiceRecommendation(
        category: JobCategory.cleaning,
        title: 'Deep Home Cleaning',
        rating: 4.8,
        reviews: 246,
        priceLabel: 'Rs 1,499',
        accent: Color(0xFFE7B45D),
        icon: Icons.cleaning_services_rounded,
      ),
      _HomeServiceRecommendation(
        category: JobCategory.acRepair,
        title: 'AC Repair & Service',
        rating: 4.7,
        reviews: 189,
        priceLabel: 'Rs 799',
        accent: Color(0xFF63A6F8),
        icon: Icons.ac_unit_rounded,
      ),
      _HomeServiceRecommendation(
        category: JobCategory.plumbing,
        title: 'Plumbing Services',
        rating: 4.6,
        reviews: 312,
        priceLabel: 'Rs 599',
        accent: Color(0xFF8B6BFF),
        icon: Icons.plumbing_rounded,
      ),
      _HomeServiceRecommendation(
        category: JobCategory.electrician,
        title: 'Electrical Work',
        rating: 4.8,
        reviews: 156,
        priceLabel: 'Rs 699',
        accent: Color(0xFFF08A30),
        icon: Icons.bolt_rounded,
      ),
    ];

List<_HomeServiceRecommendation> _recommendationsFor({
  required JobCategory? category,
  required String query,
}) {
  final normalized = query.trim().toLowerCase();
  return _homeRecommendations.where((item) {
    final matchesCategory = category == null || item.category == category;
    final matchesQuery =
        normalized.isEmpty ||
        item.title.toLowerCase().contains(normalized) ||
        item.category.displayName.toLowerCase().contains(normalized);
    return matchesCategory && matchesQuery;
  }).toList(growable: false);
}

String _firstName(String fullName) {
  final value = fullName.trim();
  if (value.isEmpty) {
    return 'there';
  }
  return value.split(RegExp(r'\s+')).first;
}

String _firstLetter(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return '?';
  }
  return normalized.substring(0, 1).toUpperCase();
}

String _shortAddress(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'Set your location';
  }
  final parts = trimmed.split(',');
  return parts.take(math.min(parts.length, 2).toInt()).join(',').trim();
}

bool _isFresh(Job job) => DateTime.now().difference(job.createdAt).inMinutes <= 30;

String _postedAgo(DateTime createdAt) {
  final diff = DateTime.now().difference(createdAt);
  if (diff.inMinutes < 60) {
    return 'Posted ${diff.inMinutes.clamp(1, 59)} min ago';
  }
  if (diff.inHours < 24) {
    return 'Posted ${diff.inHours} hr ago';
  }
  return formatDateTime(createdAt);
}

String _distanceGuess(Job job) {
  final seed = (job.latitude.abs() + job.longitude.abs()) % 4.8;
  return '${(1.2 + seed).toStringAsFixed(1)} km away';
}

String _jobTypeLabel(Job job) {
  return switch (job.category) {
    JobCategory.plumbing => 'Repair',
    JobCategory.electrician => 'Installation',
    JobCategory.acRepair => 'Service',
    JobCategory.cleaning => 'Full Home',
    JobCategory.carpenter => 'Wood Work',
    JobCategory.painter => 'Paint',
    JobCategory.applianceRepair => 'Service',
    JobCategory.registeredNurse => 'Care',
  };
}

String _homeCategoryLabel(JobCategory category) {
  return switch (category) {
    JobCategory.electrician => 'Electrical',
    JobCategory.applianceRepair => 'Appliances',
    _ => category.displayName,
  };
}

String _budgetRange(double amount) {
  final lower = amount.round();
  final upper = (amount * 1.33).round();
  return 'Rs $lower - Rs $upper';
}

IconData _categoryIcon(JobCategory category) {
  return switch (category) {
    JobCategory.plumbing => Icons.plumbing_rounded,
    JobCategory.electrician => Icons.bolt_rounded,
    JobCategory.acRepair => Icons.ac_unit_rounded,
    JobCategory.carpenter => Icons.carpenter_rounded,
    JobCategory.painter => Icons.format_paint_rounded,
    JobCategory.cleaning => Icons.cleaning_services_rounded,
    JobCategory.applianceRepair => Icons.local_laundry_service_outlined,
    JobCategory.registeredNurse => Icons.medical_services_outlined,
  };
}

Color _categoryAccent(JobCategory category) {
  return switch (category) {
    JobCategory.plumbing => const Color(0xFF8D67FF),
    JobCategory.electrician => const Color(0xFFF08A30),
    JobCategory.acRepair => const Color(0xFF63B36B),
    JobCategory.carpenter => const Color(0xFFB97A41),
    JobCategory.painter => const Color(0xFFE05C74),
    JobCategory.cleaning => const Color(0xFFE5A225),
    JobCategory.applianceRepair => const Color(0xFF6F63D9),
    JobCategory.registeredNurse => const Color(0xFF2FA6A0),
  };
}
