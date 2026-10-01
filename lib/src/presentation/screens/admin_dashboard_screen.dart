import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/repository_provider.dart';
import '../../core/services/formatters.dart';
import '../../core/services/session_analytics.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/responsive.dart';
import '../../domain/models.dart';
import '../controllers/admin_controller.dart';
import '../controllers/auth_controller.dart';

enum AdminDateFilter { today, last7, last30, custom, monthly, yearly }

enum _ReportStatus { open, underReview, actionTaken, dismissed }

class _AdminSection {
  const _AdminSection(this.title, this.icon);

  final String title;
  final IconData icon;
}

class _ChartPoint {
  const _ChartPoint({required this.label, required this.value});

  final String label;
  final double value;
}

class _TimedValue {
  const _TimedValue({required this.at, required this.value});

  final DateTime at;
  final double value;
}

class _PieSlice {
  const _PieSlice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  final _globalRate = TextEditingController();
  final Map<JobCategory, TextEditingController> _categoryRates =
      <JobCategory, TextEditingController>{};
  final Set<String> _busyIds = <String>{};
  final Map<String, _ReportStatus> _reportStatuses = <String, _ReportStatus>{};
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _userSearchController = TextEditingController();
  final TextEditingController _transactionSearchController =
      TextEditingController();
  final TextEditingController _auditSearchController = TextEditingController();
  final TextEditingController _reportSearchController = TextEditingController();

  late final List<_AdminSection> _sections;
  late final List<GlobalKey> _sectionKeys;

  AdminDateFilter _dateFilter = AdminDateFilter.last7;
  DateTimeRange? _customRange;
  bool _darkMode = false;
  int _selectedNavIndex = 0;
  String _userRoleFilter = 'all';
  String _userStatusFilter = 'all';
  PaymentState? _paymentStateFilter;
  PaymentMethod? _paymentMethodFilter;
  int _reportCategoryIndex = 0;

  @override
  void initState() {
    super.initState();
    _syncRates();
    _sections = const <_AdminSection>[
      _AdminSection('Overview', Icons.dashboard_outlined),
      _AdminSection('Users', Icons.people_alt_outlined),
      _AdminSection('Finance', Icons.account_balance_wallet_outlined),
      _AdminSection('Reports', Icons.gpp_maybe_outlined),
      _AdminSection('Admin Roles', Icons.admin_panel_settings_outlined),
      _AdminSection('Activity Logs', Icons.receipt_long_outlined),
      _AdminSection('Support', Icons.support_agent_outlined),
      _AdminSection('Security', Icons.shield_outlined),
      _AdminSection('Notifications', Icons.notifications_active_outlined),
    ];
    _sectionKeys = List<GlobalKey>.generate(
      _sections.length,
      (_) => GlobalKey(),
    );
  }

  @override
  void dispose() {
    _globalRate.dispose();
    for (final controller in _categoryRates.values) {
      controller.dispose();
    }
    _scrollController.dispose();
    _userSearchController.dispose();
    _transactionSearchController.dispose();
    _auditSearchController.dispose();
    _reportSearchController.dispose();
    super.dispose();
  }

  void _syncRates() {
    final repository = ref.read(marketplaceRepositoryProvider);
    _globalRate.text = (repository.commissionRate * 100).toStringAsFixed(2);
    for (final category in JobCategory.values) {
      _categoryRates.putIfAbsent(category, () => TextEditingController());
      _categoryRates[category]!.text =
          (repository.commissionRateForCategory(category) * 100)
              .toStringAsFixed(2);
    }
  }

  double? _parsePercent(String value) {
    final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
    if (parsed == null || parsed < 0 || parsed > 100) return null;
    return parsed / 100;
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    if (_busyIds.contains(id)) return;
    setState(() => _busyIds.add(id));
    try {
      await action();
      ref.invalidate(allUsersProvider);
      ref.invalidate(allJobsProvider);
      ref.invalidate(allPaymentsProvider);
      ref.invalidate(adminMetricsProvider);
      ref.invalidate(auditEventsProvider);
      ref.invalidate(userReportsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> _exportCsv({
    required String prefix,
    required List<String> header,
    required List<List<String>> rows,
  }) async {
    String esc(String v) => '"${v.replaceAll('"', '""')}"';
    final csv = StringBuffer()..writeln(header.map(esc).join(','));
    for (final row in rows) {
      csv.writeln(row.map(esc).join(','));
    }
    final file = File(
      '${Directory.systemTemp.path}/$prefix-${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await file.writeAsString(csv.toString());
    await Clipboard.setData(ClipboardData(text: csv.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('CSV saved to ${file.path} and copied.')),
    );
  }

  Future<String?> _askReason({
    required String title,
    required String actionLabel,
    String hint = 'Provide a reason',
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final canSubmit = controller.text.trim().isNotEmpty;
            return AlertDialog(
              title: Text(title),
              content: TextField(
                controller: controller,
                maxLines: 3,
                decoration: InputDecoration(hintText: hint),
                onChanged: (_) => setState(() {}),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: canSubmit
                      ? () => Navigator.of(context).pop(controller.text.trim())
                      : null,
                  child: Text(actionLabel),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _jumpToSection(int index) {
    if (index < 0 || index >= _sectionKeys.length) {
      return;
    }
    setState(() => _selectedNavIndex = index);
    final context = _sectionKeys[index].currentContext;
    if (context == null) {
      return;
    }
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  DateTimeRange _currentRange(DateTime now) {
    DateTime startOfDay(DateTime value) =>
        DateTime(value.year, value.month, value.day);
    final todayStart = startOfDay(now);
    switch (_dateFilter) {
      case AdminDateFilter.today:
        return DateTimeRange(start: todayStart, end: now);
      case AdminDateFilter.last7:
        return DateTimeRange(
          start: startOfDay(now.subtract(const Duration(days: 6))),
          end: now,
        );
      case AdminDateFilter.last30:
        return DateTimeRange(
          start: startOfDay(now.subtract(const Duration(days: 29))),
          end: now,
        );
      case AdminDateFilter.custom:
        return _customRange ??
            DateTimeRange(
              start: startOfDay(now.subtract(const Duration(days: 6))),
              end: now,
            );
      case AdminDateFilter.monthly:
        final monthStart = DateTime(now.year, now.month - 11, 1);
        return DateTimeRange(start: monthStart, end: now);
      case AdminDateFilter.yearly:
        final yearStart = DateTime(now.year - 4, 1, 1);
        return DateTimeRange(start: yearStart, end: now);
    }
  }

  String _formatShortDate(DateTime value) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  String _rangeLabel(DateTimeRange range) {
    return '${_formatShortDate(range.start)} - ${_formatShortDate(range.end)}';
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 1 << 31);
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m ${seconds % 60}s';
  }

  ThemeData _buildAdminTheme(BuildContext context) {
    final base = Theme.of(context);
    if (!_darkMode) {
      return base;
    }
    final scheme = const ColorScheme.dark(
      primary: AppTheme.brandTeal,
      secondary: AppTheme.brandBlue,
      tertiary: AppTheme.accentOrange,
      surface: Color(0xFF0E1724),
      onSurface: Color(0xFFE7EEF9),
      error: Color(0xFFE16C83),
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0E1724),
      cardTheme: base.cardTheme.copyWith(
        color: const Color(0xFF141E2C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF1F2A3D)),
        ),
      ),
      dividerColor: const Color(0xFF1F2A3D),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: const Color(0xFF162235),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: const Color(0xFF0E1724),
        foregroundColor: scheme.onSurface,
      ),
    );
  }

  List<_ChartPoint> _buildSeries({
    required DateTimeRange range,
    required List<_TimedValue> values,
    required int buckets,
  }) {
    final totalMs = max(1, range.duration.inMilliseconds);
    final bucketMs = max(1, totalMs ~/ buckets);
    final points = <_ChartPoint>[];
    for (var i = 0; i < buckets; i += 1) {
      final start = range.start.add(Duration(milliseconds: bucketMs * i));
      final end = i == buckets - 1
          ? range.end
          : range.start.add(Duration(milliseconds: bucketMs * (i + 1)));
      final sum = values
          .where((entry) => !entry.at.isBefore(start) && entry.at.isBefore(end))
          .fold<double>(0, (total, entry) => total + entry.value);
      points.add(
        _ChartPoint(label: _formatBucketLabel(start, end, range), value: sum),
      );
    }
    return points;
  }

  String _formatBucketLabel(DateTime start, DateTime end, DateTimeRange range) {
    if (range.duration.inDays <= 1) {
      return '${start.hour.toString().padLeft(2, '0')}:00';
    }
    if (range.duration.inDays <= 31) {
      return '${start.day}/${start.month}';
    }
    if (range.duration.inDays <= 370) {
      return '${start.month}/${start.year % 100}';
    }
    return '${start.year}';
  }

  List<_ChartPoint> _buildMonthlySeries({
    required DateTime start,
    required int months,
    required List<_TimedValue> values,
  }) {
    final points = <_ChartPoint>[];
    for (var i = 0; i < months; i += 1) {
      final monthStart = DateTime(start.year, start.month + i, 1);
      final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 1);
      final sum = values
          .where(
            (entry) =>
                !entry.at.isBefore(monthStart) && entry.at.isBefore(monthEnd),
          )
          .fold<double>(0, (total, entry) => total + entry.value);
      points.add(
        _ChartPoint(
          label: '${monthStart.month}/${monthStart.year % 100}',
          value: sum,
        ),
      );
    }
    return points;
  }

  List<_ChartPoint> _buildYearlySeries({
    required DateTime start,
    required int years,
    required List<_TimedValue> values,
  }) {
    final points = <_ChartPoint>[];
    for (var i = 0; i < years; i += 1) {
      final yearStart = DateTime(start.year + i, 1, 1);
      final yearEnd = DateTime(yearStart.year + 1, 1, 1);
      final sum = values
          .where(
            (entry) =>
                !entry.at.isBefore(yearStart) && entry.at.isBefore(yearEnd),
          )
          .fold<double>(0, (total, entry) => total + entry.value);
      points.add(_ChartPoint(label: '${yearStart.year}', value: sum));
    }
    return points;
  }

  List<_ChartPoint> _buildSeriesForFilter({
    required AdminDateFilter filter,
    required DateTimeRange range,
    required List<_TimedValue> values,
  }) {
    switch (filter) {
      case AdminDateFilter.monthly:
        return _buildMonthlySeries(
          start: DateTime(range.start.year, range.start.month, 1),
          months: 12,
          values: values,
        );
      case AdminDateFilter.yearly:
        return _buildYearlySeries(
          start: DateTime(range.start.year, 1, 1),
          years: 5,
          values: values,
        );
      case AdminDateFilter.today:
        return _buildSeries(range: range, values: values, buckets: 8);
      case AdminDateFilter.last7:
        return _buildSeries(range: range, values: values, buckets: 7);
      case AdminDateFilter.last30:
        return _buildSeries(range: range, values: values, buckets: 10);
      case AdminDateFilter.custom:
        final days = range.duration.inDays;
        final buckets = days <= 1 ? 8 : min(14, max(6, days));
        return _buildSeries(range: range, values: values, buckets: buckets);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final admin = authState.valueOrNull;
    if (authState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (authState.hasError) {
      return Scaffold(
        body: Center(
          child: Text(
            'Failed to load admin profile.\n${authState.error}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (admin == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        context.go('/login');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (admin.role != UserRole.admin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        context.go('/home');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final metrics = ref.watch(adminMetricsProvider).valueOrNull;
    final users = ref.watch(allUsersProvider).valueOrNull ?? const <AppUser>[];
    final jobs = ref.watch(allJobsProvider).valueOrNull ?? const <Job>[];
    final payments =
        ref.watch(allPaymentsProvider).valueOrNull ?? const <PaymentRecord>[];
    final reports =
        ref.watch(userReportsProvider).valueOrNull ?? const <UserReport>[];
    final audits =
        ref.watch(auditEventsProvider).valueOrNull ?? const <AuditEvent>[];
    final usersById = <String, AppUser>{
      for (final user in users) user.id: user,
    };

    final canViewMetrics = admin.hasAdminPermission(
      AdminPermission.viewMetrics,
    );
    final canViewAudit = admin.hasAdminPermission(
      AdminPermission.viewAuditLogs,
    );
    final canManageReports = admin.hasAdminPermission(
      AdminPermission.manageReports,
    );
    final canManageUsers = admin.hasAdminPermission(
      AdminPermission.manageUsers,
    );
    final canManageCommissions = admin.hasAdminPermission(
      AdminPermission.manageCommissions,
    );
    final canManageAdmins = admin.hasAdminPermission(
      AdminPermission.manageAdminAccess,
    );
    final canExport = admin.hasAdminPermission(AdminPermission.exportData);

    final now = DateTime.now();
    final range = _currentRange(now);

    bool inRange(DateTime? value) =>
        value != null &&
        (value.isAfter(range.start) || value.isAtSameMomentAs(range.start)) &&
        value.isBefore(range.end.add(const Duration(seconds: 1)));

    final totalCustomers = users.isNotEmpty
        ? users.where((u) => u.role == UserRole.customer).length
        : metrics?.totalCustomers ?? 0;
    final totalPros = users.isNotEmpty
        ? users.where((u) => u.role == UserRole.pro).length
        : metrics?.totalPros ?? 0;
    final totalAdmins = users.isNotEmpty
        ? users.where((u) => u.role == UserRole.admin).length
        : metrics?.totalAdmins ?? 0;
    final totalUsers = totalCustomers + totalPros;
    final completedSessions = SessionAnalytics.completedSessions(audits);
    final sessionsInRange = completedSessions
        .where((session) => inRange(session.startedAt))
        .toList(growable: false);
    final rangeDurations = sessionsInRange
        .map((session) => session.duration)
        .toList(growable: false);
    final allTimeDurations = completedSessions
        .map((session) => session.duration)
        .toList(growable: false);
    final averageSessionDuration = rangeDurations.isEmpty
        ? Duration.zero
        : Duration(
            microseconds:
                rangeDurations.fold<int>(
                  0,
                  (total, value) => total + value.inMicroseconds,
                ) ~/
                rangeDurations.length,
          );
    final averageSessionDurationAllTime = allTimeDurations.isEmpty
        ? Duration.zero
        : Duration(
            microseconds:
                allTimeDurations.fold<int>(
                  0,
                  (total, value) => total + value.inMicroseconds,
                ) ~/
                allTimeDurations.length,
          );
    final longestSessionDuration = rangeDurations.isEmpty
        ? Duration.zero
        : rangeDurations.reduce((a, b) => a > b ? a : b);
    final shortestSessionDuration = rangeDurations.isEmpty
        ? Duration.zero
        : rangeDurations.reduce((a, b) => a < b ? a : b);
    final suspendedAccounts = users.isNotEmpty
        ? users.where((u) => u.blocked).length
        : 0;
    final disputes = jobs.where((j) => j.status == JobStatus.disputed).length;
    final failedTransactions = payments
        .where((p) => p.state == PaymentState.failed)
        .length;
    final totalTransactions = payments.length;
    final totalMoneySent = payments.fold<double>(
      0,
      (total, payment) => total + payment.grossAmount,
    );
    final platformFees = payments.fold<double>(
      0,
      (total, payment) => total + payment.platformFee,
    );
    final averageTransaction = totalTransactions == 0
        ? 0.0
        : totalMoneySent / totalTransactions;
    final onlineVolume = payments
        .where((payment) => payment.method != PaymentMethod.cash)
        .fold<double>(0, (total, payment) => total + payment.grossAmount);
    final cashVolume = payments
        .where((payment) => payment.method == PaymentMethod.cash)
        .fold<double>(0, (total, payment) => total + payment.grossAmount);

    final reportMessages = reports.where(_isMessageReport).length;
    final reportFraud = reports.where(_isFraudReport).length;
    final reportAccounts = reports.length - reportMessages - reportFraud;

    final activeDaily = _activeUsers(
      audits: audits,
      usersById: usersById,
      since: now.subtract(const Duration(days: 1)),
    );
    final activeWeekly = _activeUsers(
      audits: audits,
      usersById: usersById,
      since: now.subtract(const Duration(days: 7)),
    );
    final activeMonthly = _activeUsers(
      audits: audits,
      usersById: usersById,
      since: now.subtract(const Duration(days: 30)),
    );

    final newRegistrations = users
        .where((user) => inRange(user.createdAt))
        .length;

    final registrationSeries = _buildSeriesForFilter(
      filter: _dateFilter,
      range: range,
      values: users
          .where((user) => user.createdAt != null)
          .map((user) => _TimedValue(at: user.createdAt!, value: 1))
          .toList(growable: false),
    );
    final growthSeries = _cumulativeSeries(registrationSeries);
    final transactionSeries = _buildSeriesForFilter(
      filter: _dateFilter,
      range: range,
      values: payments
          .map((payment) => _TimedValue(at: payment.recordedAt, value: 1))
          .toList(growable: false),
    );
    final revenueSlices = <_PieSlice>[
      _PieSlice(
        label: 'Online',
        value: onlineVolume,
        color: const Color(0xFF42A5F5),
      ),
      _PieSlice(
        label: 'Cash',
        value: cashVolume,
        color: const Color(0xFF26A69A),
      ),
    ];

    final activityFeed = _buildActivityFeed(
      audits: audits,
      reports: reports,
      usersById: usersById,
    );

    final filteredUsers = _filterUsers(
      users: users,
      query: _userSearchController.text,
      roleFilter: _userRoleFilter,
      statusFilter: _userStatusFilter,
    );

    final filteredPayments = _filterPayments(
      payments: payments,
      range: range,
      query: _transactionSearchController.text,
      stateFilter: _paymentStateFilter,
      methodFilter: _paymentMethodFilter,
    );

    final filteredReports = _filterReports(
      reports: reports,
      query: _reportSearchController.text,
      categoryIndex: _reportCategoryIndex,
    );

    final filteredAudits = _filterAudits(
      audits: audits,
      query: _auditSearchController.text,
      range: range,
    );

    final theme = _buildAdminTheme(context);
    final isCompact = Responsive.isCompact(context);

    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          return Scaffold(
            drawer: isCompact ? _buildDrawer(context) : null,
            appBar: AppBar(
              leading: IconButton(
                tooltip: 'Back',
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                    return;
                  }
                  context.go('/home');
                },
                icon: const Icon(Icons.arrow_back),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Admin Command Center'),
                  Text(
                    'Servicemen Platform',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                IconButton(
                  tooltip: _darkMode ? 'Switch to light' : 'Switch to dark',
                  onPressed: () => setState(() => _darkMode = !_darkMode),
                  icon: Icon(
                    _darkMode
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                  ),
                ),
                IconButton(
                  tooltip: 'Logout',
                  onPressed: () async {
                    await ref.read(authControllerProvider.notifier).logout();
                    if (!context.mounted) {
                      return;
                    }
                    context.go('/login');
                  },
                  icon: const Icon(Icons.logout),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (!isCompact)
                  NavigationRail(
                    selectedIndex: _selectedNavIndex,
                    onDestinationSelected: _jumpToSection,
                    extended: Responsive.isExpanded(context),
                    labelType: NavigationRailLabelType.all,
                    destinations: _sections
                        .map(
                          (section) => NavigationRailDestination(
                            icon: Icon(section.icon),
                            label: Text(section.title),
                          ),
                        )
                        .toList(growable: false),
                  ),
                if (!isCompact) const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: ResponsiveContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            key: _sectionKeys[0],
                            child: _buildOverviewSection(
                              context: context,
                              range: range,
                              canViewMetrics: canViewMetrics,
                              totalUsers: totalUsers,
                              totalCustomers: totalCustomers,
                              totalPros: totalPros,
                              totalAdmins: totalAdmins,
                              sessionsInRange: sessionsInRange.length,
                              averageSessionDuration: sessionsInRange.isEmpty
                                  ? '—'
                                  : _formatDuration(averageSessionDuration),
                              averageSessionDurationAllTime:
                                  allTimeDurations.isEmpty
                                  ? '—'
                                  : _formatDuration(
                                      averageSessionDurationAllTime,
                                    ),
                              longestSessionDuration: rangeDurations.isEmpty
                                  ? '—'
                                  : _formatDuration(longestSessionDuration),
                              shortestSessionDuration: rangeDurations.isEmpty
                                  ? '—'
                                  : _formatDuration(shortestSessionDuration),
                              activeDaily: activeDaily,
                              activeWeekly: activeWeekly,
                              activeMonthly: activeMonthly,
                              newRegistrations: newRegistrations,
                              totalTransactions: totalTransactions,
                              totalRevenue:
                                  metrics?.platformRevenue ?? platformFees,
                              totalMoneySent: totalMoneySent,
                              appFees: metrics?.platformRevenue ?? platformFees,
                              averageTransaction: averageTransaction,
                              failedTransactions: failedTransactions,
                              disputedTransactions: disputes,
                              suspendedAccounts: suspendedAccounts,
                              reportedAccounts: reportAccounts,
                              reportedMessages: reportMessages,
                              registrationSeries: growthSeries,
                              transactionSeries: transactionSeries,
                              revenueSlices: revenueSlices,
                              activityFeed: activityFeed,
                            ),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            key: _sectionKeys[1],
                            child: _buildUsersSection(
                              context: context,
                              admin: admin,
                              users: filteredUsers,
                              audits: audits,
                              sessions: completedSessions,
                              payments: payments,
                              canManageUsers: canManageUsers,
                              canManageCommissions: canManageCommissions,
                              canExport: canExport,
                            ),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            key: _sectionKeys[2],
                            child: _buildFinanceSection(
                              context: context,
                              payments: filteredPayments,
                              canExport: canExport,
                              range: range,
                            ),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            key: _sectionKeys[3],
                            child: _buildReportsSection(
                              context: context,
                              admin: admin,
                              reports: filteredReports,
                              usersById: usersById,
                              canManageReports: canManageReports,
                              canManageUsers: canManageUsers,
                            ),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            key: _sectionKeys[4],
                            child: _buildAdminRolesSection(
                              context: context,
                              admin: admin,
                              users: users,
                              canManageAdmins: canManageAdmins,
                            ),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            key: _sectionKeys[5],
                            child: _buildAuditSection(
                              context: context,
                              audits: filteredAudits,
                              canViewAudit: canViewAudit,
                              usersById: usersById,
                            ),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            key: _sectionKeys[6],
                            child: _buildSupportSection(
                              context: context,
                              reports: reports,
                              usersById: usersById,
                            ),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            key: _sectionKeys[7],
                            child: _buildSecuritySection(context),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            key: _sectionKeys[8],
                            child: _buildNotificationsSection(
                              context: context,
                              payments: payments,
                              reports: reports,
                              disputes: disputes,
                            ),
                          ),
                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: <Widget>[
            Text(
              'Admin Navigation',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ..._sections.asMap().entries.map((entry) {
              final isSelected = entry.key == _selectedNavIndex;
              return ListTile(
                selected: isSelected,
                leading: Icon(entry.value.icon),
                title: Text(entry.value.title),
                onTap: () {
                  Navigator.of(context).pop();
                  _jumpToSection(entry.key);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewSection({
    required BuildContext context,
    required DateTimeRange range,
    required bool canViewMetrics,
    required int totalUsers,
    required int totalCustomers,
    required int totalPros,
    required int totalAdmins,
    required int sessionsInRange,
    required String averageSessionDuration,
    required String averageSessionDurationAllTime,
    required String longestSessionDuration,
    required String shortestSessionDuration,
    required int activeDaily,
    required int activeWeekly,
    required int activeMonthly,
    required int newRegistrations,
    required int totalTransactions,
    required double totalRevenue,
    required double totalMoneySent,
    required double appFees,
    required double averageTransaction,
    required int failedTransactions,
    required int disputedTransactions,
    required int suspendedAccounts,
    required int reportedAccounts,
    required int reportedMessages,
    required List<_ChartPoint> registrationSeries,
    required List<_ChartPoint> transactionSeries,
    required List<_PieSlice> revenueSlices,
    required List<_ActivityEntry> activityFeed,
  }) {
    final now = DateTime.now();
    final metricCards = <_MetricCardData>[
      _MetricCardData(
        label: 'Total Users',
        value: totalUsers.toString(),
        icon: Icons.people_alt_outlined,
        tone: const Color(0xFF1C5FA8),
      ),
      _MetricCardData(
        label: 'Active Users (Daily)',
        value: activeDaily.toString(),
        icon: Icons.flash_on_outlined,
        tone: const Color(0xFF0FA589),
      ),
      _MetricCardData(
        label: 'Active Users (Weekly)',
        value: activeWeekly.toString(),
        icon: Icons.calendar_view_week_outlined,
        tone: const Color(0xFFE18D37),
      ),
      _MetricCardData(
        label: 'Active Users (Monthly)',
        value: activeMonthly.toString(),
        icon: Icons.calendar_month_outlined,
        tone: const Color(0xFF7B61FF),
      ),
      _MetricCardData(
        label: 'New Registrations',
        value: newRegistrations.toString(),
        icon: Icons.person_add_alt_1_outlined,
        tone: const Color(0xFF2F80ED),
      ),
      _MetricCardData(
        label: 'Total Transactions',
        value: totalTransactions.toString(),
        icon: Icons.receipt_long_outlined,
        tone: const Color(0xFF3E7CB1),
      ),
      _MetricCardData(
        label: 'Total Revenue',
        value: formatPkr(totalRevenue),
        icon: Icons.stacked_line_chart_outlined,
        tone: const Color(0xFF00A896),
      ),
      _MetricCardData(
        label: 'Total Money Sent',
        value: formatPkr(totalMoneySent),
        icon: Icons.account_balance_wallet_outlined,
        tone: const Color(0xFF3D5A80),
      ),
      _MetricCardData(
        label: 'App Fees Collected',
        value: formatPkr(appFees),
        icon: Icons.payments_outlined,
        tone: const Color(0xFFF4A261),
      ),
      _MetricCardData(
        label: 'Average Transaction',
        value: formatPkr(averageTransaction),
        icon: Icons.multiline_chart_outlined,
        tone: const Color(0xFF5C6BC0),
      ),
      _MetricCardData(
        label: 'Failed Transactions',
        value: failedTransactions.toString(),
        icon: Icons.error_outline,
        tone: const Color(0xFFE53935),
      ),
      _MetricCardData(
        label: 'Disputed Transactions',
        value: disputedTransactions.toString(),
        icon: Icons.report_problem_outlined,
        tone: const Color(0xFFEF6C00),
      ),
      _MetricCardData(
        label: 'Suspended Accounts',
        value: suspendedAccounts.toString(),
        icon: Icons.lock_person_outlined,
        tone: const Color(0xFF6D4C41),
      ),
      _MetricCardData(
        label: 'Reported Accounts',
        value: reportedAccounts.toString(),
        icon: Icons.flag_outlined,
        tone: const Color(0xFF8E24AA),
      ),
      _MetricCardData(
        label: 'Reported Messages',
        value: reportedMessages.toString(),
        icon: Icons.mark_chat_unread_outlined,
        tone: const Color(0xFF3949AB),
      ),
      _MetricCardData(
        label: 'Total Customers',
        value: totalCustomers.toString(),
        icon: Icons.person_outline,
        tone: const Color(0xFF2A9D8F),
      ),
      _MetricCardData(
        label: 'Total Professionals',
        value: totalPros.toString(),
        icon: Icons.handyman_outlined,
        tone: const Color(0xFF1D3557),
      ),
      _MetricCardData(
        label: 'Admin Accounts',
        value: totalAdmins.toString(),
        icon: Icons.admin_panel_settings_outlined,
        tone: const Color(0xFF6A4C93),
      ),
      _MetricCardData(
        label: 'Completed Sessions (Selected Range)',
        value: sessionsInRange.toString(),
        icon: Icons.login_outlined,
        tone: const Color(0xFF00897B),
      ),
      _MetricCardData(
        label: 'Average Session (Selected Range)',
        value: averageSessionDuration,
        icon: Icons.timelapse_outlined,
        tone: const Color(0xFF3949AB),
      ),
      _MetricCardData(
        label: 'Average Session (All Time)',
        value: averageSessionDurationAllTime,
        icon: Icons.history_rounded,
        tone: const Color(0xFF607D8B),
      ),
      _MetricCardData(
        label: 'Longest Session (Selected Range)',
        value: longestSessionDuration,
        icon: Icons.trending_up_outlined,
        tone: const Color(0xFFEF6C00),
      ),
      _MetricCardData(
        label: 'Shortest Session (Selected Range)',
        value: shortestSessionDuration,
        icon: Icons.trending_down_outlined,
        tone: const Color(0xFF6D4C41),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionHeader(
          context,
          title: 'Dashboard Overview',
          subtitle: 'Realtime health of users, jobs, transactions, and risk.',
          trailing: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Text(
                  _rangeLabel(range),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AdminDateFilter.values
              .map((filter) {
                final label = switch (filter) {
                  AdminDateFilter.today => 'Today',
                  AdminDateFilter.last7 => 'Last 7 Days',
                  AdminDateFilter.last30 => 'Last 30 Days',
                  AdminDateFilter.custom => 'Custom Range',
                  AdminDateFilter.monthly => 'Monthly',
                  AdminDateFilter.yearly => 'Yearly',
                };
                return ChoiceChip(
                  label: Text(label),
                  selected: _dateFilter == filter,
                  onSelected: (_) async {
                    if (filter == AdminDateFilter.custom) {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(now.year - 3, 1, 1),
                        lastDate: DateTime(now.year + 1, 12, 31),
                        initialDateRange: _customRange ?? range,
                      );
                      if (picked == null) {
                        return;
                      }
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _dateFilter = filter;
                        _customRange = picked;
                      });
                      return;
                    }
                    setState(() => _dateFilter = filter);
                  },
                );
              })
              .toList(growable: false),
        ),
        const SizedBox(height: 12),
        if (!canViewMetrics)
          _LockedCard(
            message: 'Metrics visibility is locked for your admin role.',
          ),
        if (canViewMetrics)
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 1200
                  ? 4
                  : width >= 900
                  ? 3
                  : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: 132,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: metricCards.length,
                itemBuilder: (context, index) {
                  final metric = metricCards[index];
                  return _MetricCard(metric: metric);
                },
              );
            },
          ),
        if (canViewMetrics)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Session averages and highs/lows use recorded logouts only; force-closed sessions have no inferred end time.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 980;
            final growthCard = _ChartCard(
              title: 'User Growth',
              subtitle: 'Cumulative registrations over selected range.',
              child: _LineChart(points: registrationSeries),
            );
            final transactionCard = _ChartCard(
              title: 'Transactions',
              subtitle: 'Volume by period.',
              child: _BarChart(points: transactionSeries),
            );
            return isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: growthCard),
                      const SizedBox(width: 16),
                      Expanded(child: transactionCard),
                    ],
                  )
                : Column(
                    children: <Widget>[
                      growthCard,
                      const SizedBox(height: 16),
                      transactionCard,
                    ],
                  );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 980;
            final revenueCard = _ChartCard(
              title: 'Revenue Breakdown',
              subtitle: 'Online vs Cash collections.',
              child: _PieChart(slices: revenueSlices),
            );
            final activityCard = _ChartCard(
              title: 'Live Activity Feed',
              subtitle: 'Most recent platform events.',
              child: _ActivityFeed(entries: activityFeed),
            );
            return isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: revenueCard),
                      const SizedBox(width: 16),
                      Expanded(child: activityCard),
                    ],
                  )
                : Column(
                    children: <Widget>[
                      revenueCard,
                      const SizedBox(height: 16),
                      activityCard,
                    ],
                  );
          },
        ),
      ],
    );
  }

  Widget _buildUsersSection({
    required BuildContext context,
    required AppUser admin,
    required List<AppUser> users,
    required List<AuditEvent> audits,
    required List<UserSessionRecord> sessions,
    required List<PaymentRecord> payments,
    required bool canManageUsers,
    required bool canManageCommissions,
    required bool canExport,
  }) {
    final endUsers = users.where((u) => u.role != UserRole.admin).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionHeader(
          context,
          title: 'User Management',
          subtitle: 'Search, verify, suspend, and review user account history.',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (canExport)
                OutlinedButton.icon(
                  onPressed: () {
                    _exportCsv(
                      prefix: 'users',
                      header: const <String>[
                        'id',
                        'role',
                        'full_name',
                        'email',
                        'phone',
                        'blocked',
                        'cnic_verified',
                        'created_at',
                      ],
                      rows: endUsers
                          .map(
                            (user) => <String>[
                              user.id,
                              user.role.value,
                              user.fullName,
                              user.email,
                              user.phone,
                              user.blocked.toString(),
                              user.cnicVerified.toString(),
                              user.createdAt?.toIso8601String() ?? '',
                            ],
                          )
                          .toList(growable: false),
                    );
                  },
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export Users'),
                ),
              _FilterChip(
                label: _userRoleFilter == 'all' ? 'All Roles' : _userRoleFilter,
                onTap: () => _showRoleFilterDialog(context),
              ),
              _FilterChip(
                label: _userStatusFilter == 'all'
                    ? 'All Status'
                    : _userStatusFilter,
                onTap: () => _showStatusFilterDialog(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _userSearchController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search by ID, email, phone, or name',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (endUsers.isEmpty) const Text('No users matched your filters.'),
        if (endUsers.isNotEmpty)
          Column(
            children: endUsers
                .map(
                  (user) => _UserCard(
                    user: user,
                    audits: audits,
                    sessions: sessions,
                    payments: payments,
                    canManageUsers: canManageUsers,
                    onAction: (action) => _handleUserAction(
                      admin: admin,
                      user: user,
                      action: action,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        const SizedBox(height: 16),
        _sectionHeader(
          context,
          title: 'Commission Control',
          subtitle: 'Global and category-specific platform fees.',
        ),
        const SizedBox(height: 12),
        if (!canManageCommissions)
          _LockedCard(
            message: 'Commission settings are locked for your admin role.',
          ),
        if (canManageCommissions)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _globalRate,
                          decoration: const InputDecoration(
                            labelText: 'Global Commission (%)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () {
                          final rate = _parsePercent(_globalRate.text);
                          if (rate == null) return;
                          _run(
                            'commission-global',
                            () => ref
                                .read(marketplaceRepositoryProvider)
                                .setCommissionRate(rate, actorId: admin.id),
                          );
                        },
                        child: const Text('Update'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...JobCategory.values.map((category) {
                    final controller = _categoryRates[category]!;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: <Widget>[
                          Expanded(child: Text(category.displayName)),
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                labelText: 'Rate %',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              final rate = _parsePercent(controller.text);
                              if (rate == null) return;
                              _run(
                                'commission-${category.value}',
                                () => ref
                                    .read(marketplaceRepositoryProvider)
                                    .setCategoryCommissionRate(
                                      category: category,
                                      rate: rate,
                                      actorId: admin.id,
                                    ),
                              );
                            },
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFinanceSection({
    required BuildContext context,
    required List<PaymentRecord> payments,
    required bool canExport,
    required DateTimeRange range,
  }) {
    final isCompact = Responsive.isCompact(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionHeader(
          context,
          title: 'Financial & Transaction Monitoring',
          subtitle: 'Real-time oversight of revenue, fees, and payment status.',
          trailing: Row(
            children: <Widget>[
              if (canExport)
                OutlinedButton.icon(
                  onPressed: payments.isEmpty
                      ? null
                      : () => _exportCsv(
                          prefix: 'transactions',
                          header: const <String>[
                            'id',
                            'job_id',
                            'customer_id',
                            'pro_id',
                            'method',
                            'state',
                            'gross_amount',
                            'platform_fee',
                            'net_pro_amount',
                            'recorded_at',
                          ],
                          rows: payments
                              .map(
                                (payment) => <String>[
                                  payment.id,
                                  payment.jobId,
                                  payment.customerId,
                                  payment.proId,
                                  payment.method.value,
                                  payment.state.value,
                                  payment.grossAmount.toStringAsFixed(2),
                                  payment.platformFee.toStringAsFixed(2),
                                  payment.netProAmount.toStringAsFixed(2),
                                  payment.recordedAt.toIso8601String(),
                                ],
                              )
                              .toList(growable: false),
                        ),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 720;
            if (isNarrow) {
              return Column(
                children: <Widget>[
                  TextField(
                    controller: _transactionSearchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by user, job, or transaction ID',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _FilterChip(
                        label: _paymentStateFilter?.name ?? 'All Status',
                        onTap: () => _showPaymentStateFilter(context),
                      ),
                      _FilterChip(
                        label:
                            _paymentMethodFilter?.displayName ?? 'All Methods',
                        onTap: () => _showPaymentMethodFilter(context),
                      ),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _transactionSearchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by user, job, or transaction ID',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                _FilterChip(
                  label: _paymentStateFilter?.name ?? 'All Status',
                  onTap: () => _showPaymentStateFilter(context),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: _paymentMethodFilter?.displayName ?? 'All Methods',
                  onTap: () => _showPaymentMethodFilter(context),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        if (payments.isEmpty)
          _EmptyStateCard(
            title: 'No transactions found for ${_rangeLabel(range)}.',
            subtitle: 'Filtered results will appear here.',
          ),
        if (payments.isNotEmpty && isCompact)
          Column(
            children: payments
                .map(
                  (payment) => Card(
                    child: ListTile(
                      title: Text(
                        '${payment.method.displayName} · ${payment.state.name}',
                      ),
                      subtitle: Text(
                        '${formatPkr(payment.grossAmount)} gross · ${formatPkr(payment.platformFee)} fee',
                      ),
                      trailing: Text(
                        formatDateTime(payment.recordedAt),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        if (payments.isNotEmpty && !isCompact)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const <DataColumn>[
                DataColumn(label: Text('Transaction')),
                DataColumn(label: Text('Customer')),
                DataColumn(label: Text('Professional')),
                DataColumn(label: Text('Method')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Gross')),
                DataColumn(label: Text('Fee')),
                DataColumn(label: Text('Net Pro')),
                DataColumn(label: Text('Recorded')),
              ],
              rows: payments
                  .map(
                    (payment) => DataRow(
                      cells: <DataCell>[
                        DataCell(Text(payment.id)),
                        DataCell(Text(payment.customerId)),
                        DataCell(Text(payment.proId)),
                        DataCell(Text(payment.method.displayName)),
                        DataCell(Text(payment.state.name)),
                        DataCell(Text(formatPkr(payment.grossAmount))),
                        DataCell(Text(formatPkr(payment.platformFee))),
                        DataCell(Text(formatPkr(payment.netProAmount))),
                        DataCell(Text(formatDateTime(payment.recordedAt))),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
      ],
    );
  }

  Widget _buildReportsSection({
    required BuildContext context,
    required AppUser admin,
    required List<UserReport> reports,
    required Map<String, AppUser> usersById,
    required bool canManageReports,
    required bool canManageUsers,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionHeader(
          context,
          title: 'Reports & Moderation Center',
          subtitle:
              'Handle user, chat, and fraud complaints with clear actions.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: <Widget>[
            ChoiceChip(
              label: const Text('Message Reports'),
              selected: _reportCategoryIndex == 0,
              onSelected: (_) => setState(() => _reportCategoryIndex = 0),
            ),
            ChoiceChip(
              label: const Text('Account Reports'),
              selected: _reportCategoryIndex == 1,
              onSelected: (_) => setState(() => _reportCategoryIndex = 1),
            ),
            ChoiceChip(
              label: const Text('Fraud Reports'),
              selected: _reportCategoryIndex == 2,
              onSelected: (_) => setState(() => _reportCategoryIndex = 2),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _reportSearchController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search reports by user or reason',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (!canManageReports)
          _LockedCard(
            message: 'Report moderation is locked for your admin role.',
          ),
        if (canManageReports && reports.isEmpty)
          const Text('No reports matched your filters.'),
        if (canManageReports && reports.isNotEmpty)
          Column(
            children: reports
                .map(
                  (report) => _ReportCard(
                    report: report,
                    reporter: usersById[report.reporterId],
                    target: usersById[report.targetUserId],
                    status: _reportStatuses[report.id] ?? _ReportStatus.open,
                    onStatusChange: (status) => setState(() {
                      _reportStatuses[report.id] = status;
                    }),
                    onAction: (action) => _handleReportAction(
                      admin: admin,
                      report: report,
                      action: action,
                      target: usersById[report.targetUserId],
                      canManageUsers: canManageUsers,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }

  Widget _buildAdminRolesSection({
    required BuildContext context,
    required AppUser admin,
    required List<AppUser> users,
    required bool canManageAdmins,
  }) {
    final admins = users.where((u) => u.role == UserRole.admin).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionHeader(
          context,
          title: 'Admin Roles & Permissions',
          subtitle: 'Assign permissions and manage administrative access.',
        ),
        const SizedBox(height: 12),
        if (!canManageAdmins)
          _LockedCard(
            message: 'Admin role management is locked for your admin role.',
          ),
        if (canManageAdmins)
          Column(
            children: admins
                .map(
                  (user) => LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 720;
                      final permissions = Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: user.adminPermissions
                            .map(
                              (permission) =>
                                  Chip(label: Text(permission.label)),
                            )
                            .toList(growable: false),
                      );
                      final rankDropdown = DropdownButton<AdminRank>(
                        value: user.effectiveAdminRank ?? AdminRank.support,
                        items: AdminRank.values
                            .map(
                              (rank) => DropdownMenuItem<AdminRank>(
                                value: rank,
                                child: Text(rank.label),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (next) {
                          if (next == null) return;
                          _run(
                            'admin-rank-${user.id}',
                            () => ref
                                .read(marketplaceRepositoryProvider)
                                .setAdminAccess(
                                  actorId: admin.id,
                                  targetUserId: user.id,
                                  rank: next,
                                  permissions: defaultAdminPermissionsForRank(
                                    next,
                                  ),
                                ),
                          );
                        },
                      );
                      final editButton = TextButton(
                        onPressed: () => _editPermissions(
                          context,
                          admin: admin,
                          target: user,
                        ),
                        child: const Text('Edit Permissions'),
                      );

                      if (isNarrow) {
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '${user.fullName} (${user.email})',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                permissions,
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: <Widget>[rankDropdown, editButton],
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return Card(
                        child: ListTile(
                          title: Text('${user.fullName} (${user.email})'),
                          subtitle: permissions,
                          trailing: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: <Widget>[rankDropdown, editButton],
                          ),
                        ),
                      );
                    },
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }

  Widget _buildAuditSection({
    required BuildContext context,
    required List<AuditEvent> audits,
    required bool canViewAudit,
    required Map<String, AppUser> usersById,
  }) {
    final isCompact = Responsive.isCompact(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionHeader(
          context,
          title: 'Activity Logs & Audit Trails',
          subtitle: 'Track every admin action for compliance and security.',
        ),
        const SizedBox(height: 12),
        if (!canViewAudit)
          _LockedCard(message: 'Audit logs are locked for your admin role.'),
        if (canViewAudit)
          TextField(
            controller: _auditSearchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by admin, action, or entity',
            ),
            onChanged: (_) => setState(() {}),
          ),
        const SizedBox(height: 12),
        if (canViewAudit && audits.isEmpty)
          const Text('No audit events found for this filter.'),
        if (canViewAudit && audits.isNotEmpty && isCompact)
          Column(
            children: audits
                .map(
                  (event) => Card(
                    child: ListTile(
                      title: Text(_auditActionLabel(event.action)),
                      subtitle: Text(
                        '${usersById[event.actorId]?.fullName ?? event.actorId} · ${event.entityType} ${event.entityId}',
                      ),
                      trailing: Text(formatDateTime(event.createdAt)),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        if (canViewAudit && audits.isNotEmpty && !isCompact)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const <DataColumn>[
                DataColumn(label: Text('Admin')),
                DataColumn(label: Text('Action')),
                DataColumn(label: Text('Entity')),
                DataColumn(label: Text('IP Address')),
                DataColumn(label: Text('Device')),
                DataColumn(label: Text('Timestamp')),
              ],
              rows: audits
                  .map(
                    (event) => DataRow(
                      cells: <DataCell>[
                        DataCell(
                          Text(
                            usersById[event.actorId]?.fullName ?? event.actorId,
                          ),
                        ),
                        DataCell(Text(_auditActionLabel(event.action))),
                        DataCell(Text('${event.entityType} ${event.entityId}')),
                        DataCell(Text(event.ipAddress ?? '—')),
                        DataCell(Text(event.deviceInfo ?? '—')),
                        DataCell(Text(formatDateTime(event.createdAt))),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
      ],
    );
  }

  Widget _buildSupportSection({
    required BuildContext context,
    required List<UserReport> reports,
    required Map<String, AppUser> usersById,
  }) {
    final openReports = reports.take(5).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionHeader(
          context,
          title: 'Support & Issue Resolution',
          subtitle: 'Track escalations and respond to customer needs.',
        ),
        const SizedBox(height: 12),
        if (openReports.isEmpty)
          _EmptyStateCard(
            title: 'No open tickets yet.',
            subtitle: 'Customer escalations will surface here.',
          ),
        if (openReports.isNotEmpty)
          Column(
            children: openReports
                .map(
                  (report) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.support_agent_outlined),
                      title: Text(
                        '${usersById[report.targetUserId]?.fullName ?? report.targetUserId}',
                      ),
                      subtitle: Text(report.reasonText),
                      trailing: Text(formatDateTime(report.createdAt)),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }

  Widget _buildSecuritySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionHeader(
          context,
          title: 'Security Controls',
          subtitle: 'Protect admin access and monitor suspicious activity.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: const <Widget>[
            _SecurityTile(
              title: 'Admin 2FA',
              value: 'Enabled',
              description: 'Two-factor required for all admins.',
            ),
            _SecurityTile(
              title: 'IP Monitoring',
              value: 'Active',
              description: 'IP risk scoring and geofence alerts.',
            ),
            _SecurityTile(
              title: 'Session Tracking',
              value: 'Live',
              description: 'Realtime admin session telemetry.',
            ),
            _SecurityTile(
              title: 'Suspicious Login Alerts',
              value: 'On',
              description: 'Auto-alert on anomaly detection.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNotificationsSection({
    required BuildContext context,
    required List<PaymentRecord> payments,
    required List<UserReport> reports,
    required int disputes,
  }) {
    final now = DateTime.now();
    final last24h = now.subtract(const Duration(hours: 24));
    final largeTransactions = payments
        .where(
          (payment) =>
              payment.recordedAt.isAfter(last24h) &&
              payment.grossAmount >= 50000,
        )
        .length;
    final reportSpike = reports
        .where((report) => report.createdAt.isAfter(last24h))
        .length;
    final alerts = <_AlertTile>[
      _AlertTile(
        title: 'Large Transactions',
        value: largeTransactions,
        tone: const Color(0xFF2563EB),
        description: 'Payments above PKR 50,000 in the last 24h.',
      ),
      _AlertTile(
        title: 'Spike in Reports',
        value: reportSpike,
        tone: const Color(0xFFB45309),
        description: 'Reports created in the last 24h.',
      ),
      _AlertTile(
        title: 'Disputed Jobs',
        value: disputes,
        tone: const Color(0xFFDC2626),
        description: 'Jobs currently marked as disputed.',
      ),
      const _AlertTile(
        title: 'System Errors',
        value: 0,
        tone: Color(0xFF6B7280),
        description: 'No system alerts linked yet.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionHeader(
          context,
          title: 'Notifications & Alerts',
          subtitle: 'High-priority signals and health checks.',
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: alerts),
      ],
    );
  }

  void _showRoleFilterDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: const Text('All Roles'),
              onTap: () {
                setState(() => _userRoleFilter = 'all');
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              title: const Text('Customers'),
              onTap: () {
                setState(() => _userRoleFilter = 'customer');
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              title: const Text('Professionals'),
              onTap: () {
                setState(() => _userRoleFilter = 'pro');
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showStatusFilterDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: const Text('All Status'),
              onTap: () {
                setState(() => _userStatusFilter = 'all');
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              title: const Text('Active'),
              onTap: () {
                setState(() => _userStatusFilter = 'active');
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              title: const Text('Suspended'),
              onTap: () {
                setState(() => _userStatusFilter = 'blocked');
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentStateFilter(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: const Text('All Status'),
              onTap: () {
                setState(() => _paymentStateFilter = null);
                Navigator.of(context).pop();
              },
            ),
            ...PaymentState.values.map(
              (state) => ListTile(
                title: Text(state.name),
                onTap: () {
                  setState(() => _paymentStateFilter = state);
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentMethodFilter(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: const Text('All Methods'),
              onTap: () {
                setState(() => _paymentMethodFilter = null);
                Navigator.of(context).pop();
              },
            ),
            ...PaymentMethod.values.map(
              (method) => ListTile(
                title: Text(method.displayName),
                onTap: () {
                  setState(() => _paymentMethodFilter = method);
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editPermissions(
    BuildContext context, {
    required AppUser admin,
    required AppUser target,
  }) async {
    final current = target.adminPermissions.toSet();
    final selected = await showDialog<Set<AdminPermission>>(
      context: context,
      builder: (context) {
        final working = current.toSet();
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Permissions'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: AdminPermission.values
                      .map(
                        (permission) => CheckboxListTile(
                          value: working.contains(permission),
                          title: Text(permission.label),
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                working.add(permission);
                              } else {
                                working.remove(permission);
                              }
                            });
                          },
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(working),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    if (selected == null) return;
    await _run(
      'admin-permissions-${target.id}',
      () => ref
          .read(marketplaceRepositoryProvider)
          .setAdminAccess(
            actorId: admin.id,
            targetUserId: target.id,
            rank: target.effectiveAdminRank ?? AdminRank.support,
            permissions: selected.toList(growable: false),
          ),
    );
  }

  Future<void> _handleUserAction({
    required AppUser admin,
    required AppUser user,
    required _UserAction action,
  }) async {
    switch (action) {
      case _UserAction.verifyPro:
        final reason = await _askReason(
          title: 'Verify Professional',
          actionLabel: 'Verify',
          hint: 'Reason for verification',
        );
        if (reason == null) return;
        await _run('verify-${user.id}', () async {
          await ref
              .read(marketplaceRepositoryProvider)
              .setProVerification(
                actorId: admin.id,
                userId: user.id,
                cnicVerified: true,
                policeVerified: true,
              );
          await ref
              .read(marketplaceRepositoryProvider)
              .addAuditEvent(
                AuditEvent(
                  id: 'verification-${user.id}-${DateTime.now().millisecondsSinceEpoch}',
                  actorId: admin.id,
                  action: 'pro_verified_reason',
                  entityType: 'user',
                  entityId: user.id,
                  createdAt: DateTime.now(),
                  metadata: <String, dynamic>{'reason': reason},
                ),
              );
        });
      case _UserAction.unverifyPro:
        final reason = await _askReason(
          title: 'Unverify Professional',
          actionLabel: 'Unverify',
          hint: 'Reason for unverification',
        );
        if (reason == null) return;
        await _run('unverify-${user.id}', () async {
          await ref
              .read(marketplaceRepositoryProvider)
              .setProVerification(
                actorId: admin.id,
                userId: user.id,
                cnicVerified: false,
                policeVerified: false,
              );
          await ref
              .read(marketplaceRepositoryProvider)
              .addAuditEvent(
                AuditEvent(
                  id: 'unverify-${user.id}-${DateTime.now().millisecondsSinceEpoch}',
                  actorId: admin.id,
                  action: 'pro_unverified_reason',
                  entityType: 'user',
                  entityId: user.id,
                  createdAt: DateTime.now(),
                  metadata: <String, dynamic>{'reason': reason},
                ),
              );
        });
      case _UserAction.suspend:
        final reason = await _askReason(
          title: 'Suspend Account',
          actionLabel: 'Suspend',
          hint: 'Reason for suspension',
        );
        if (reason == null) return;
        await _run(
          'suspend-${user.id}',
          () => ref
              .read(marketplaceRepositoryProvider)
              .setUserBlockStatus(
                actorId: admin.id,
                targetUserId: user.id,
                blocked: true,
                reason: reason,
              ),
        );
      case _UserAction.restore:
        final reason = await _askReason(
          title: 'Restore Account',
          actionLabel: 'Restore',
          hint: 'Reason for restoring access',
        );
        if (reason == null) return;
        await _run(
          'restore-${user.id}',
          () => ref
              .read(marketplaceRepositoryProvider)
              .setUserBlockStatus(
                actorId: admin.id,
                targetUserId: user.id,
                blocked: false,
                reason: reason,
              ),
        );
      case _UserAction.flag:
        final reason = await _askReason(
          title: 'Flag Suspicious Activity',
          actionLabel: 'Flag',
          hint: 'Reason for flagging',
        );
        if (reason == null) return;
        await _run(
          'flag-${user.id}',
          () => ref
              .read(marketplaceRepositoryProvider)
              .addAuditEvent(
                AuditEvent(
                  id: 'flag-${user.id}-${DateTime.now().millisecondsSinceEpoch}',
                  actorId: admin.id,
                  action: 'user_flagged',
                  entityType: 'user',
                  entityId: user.id,
                  createdAt: DateTime.now(),
                  metadata: <String, dynamic>{'reason': reason},
                ),
              ),
        );
    }
  }

  Future<void> _handleReportAction({
    required AppUser admin,
    required UserReport report,
    required _ReportAction action,
    required AppUser? target,
    required bool canManageUsers,
  }) async {
    switch (action) {
      case _ReportAction.review:
        setState(() => _reportStatuses[report.id] = _ReportStatus.underReview);
        await _run(
          'review-${report.id}',
          () => ref
              .read(marketplaceRepositoryProvider)
              .addAuditEvent(
                AuditEvent(
                  id: 'report-review-${report.id}-${DateTime.now().millisecondsSinceEpoch}',
                  actorId: admin.id,
                  action: 'report_reviewed',
                  entityType: 'report',
                  entityId: report.id,
                  createdAt: DateTime.now(),
                ),
              ),
        );
      case _ReportAction.actionTaken:
        setState(() => _reportStatuses[report.id] = _ReportStatus.actionTaken);
      case _ReportAction.dismiss:
        setState(() => _reportStatuses[report.id] = _ReportStatus.dismissed);
      case _ReportAction.blockUser:
        if (!canManageUsers || target == null) {
          return;
        }
        final reason = await _askReason(
          title: 'Block Reported User',
          actionLabel: 'Block',
          hint: 'Reason for blocking user',
        );
        if (reason == null) return;
        await _run(
          'report-block-${target.id}',
          () => ref
              .read(marketplaceRepositoryProvider)
              .setUserBlockStatus(
                actorId: admin.id,
                targetUserId: target.id,
                blocked: true,
                reason: reason,
              ),
        );
        setState(() => _reportStatuses[report.id] = _ReportStatus.actionTaken);
    }
  }

  List<AppUser> _filterUsers({
    required List<AppUser> users,
    required String query,
    required String roleFilter,
    required String statusFilter,
  }) {
    final normalized = query.trim().toLowerCase();
    bool hasWordPrefix(String source) {
      final words = source
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList(growable: false);
      return words.any((part) => part.startsWith(normalized));
    }

    int relevance(AppUser user) {
      if (normalized.isEmpty) {
        return 0;
      }
      final fullName = user.fullName.toLowerCase();
      final email = user.email.toLowerCase();
      final phone = user.phone.toLowerCase();
      final id = user.id.toLowerCase();

      final startsWithName = fullName.startsWith(normalized);
      final startsWithWord = hasWordPrefix(fullName);
      final startsWithEmail = email.startsWith(normalized);
      final startsWithPhone = phone.startsWith(normalized);
      final startsWithId = id.startsWith(normalized);
      if (startsWithName ||
          startsWithWord ||
          startsWithEmail ||
          startsWithPhone ||
          startsWithId) {
        return 0;
      }
      return 1;
    }

    final filtered = users
        .where((user) {
          if (user.role == UserRole.admin) {
            return false;
          }
          if (roleFilter == 'customer' && user.role != UserRole.customer) {
            return false;
          }
          if (roleFilter == 'pro' && user.role != UserRole.pro) {
            return false;
          }
          if (statusFilter == 'active' && user.blocked) {
            return false;
          }
          if (statusFilter == 'blocked' && !user.blocked) {
            return false;
          }
          if (normalized.isEmpty) {
            return true;
          }
          return user.id.toLowerCase().contains(normalized) ||
              user.fullName.toLowerCase().contains(normalized) ||
              user.email.toLowerCase().contains(normalized) ||
              user.phone.toLowerCase().contains(normalized);
        })
        .toList(growable: false);
    filtered.sort((a, b) {
      final scoreCompare = relevance(a).compareTo(relevance(b));
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });
    return filtered;
  }

  List<PaymentRecord> _filterPayments({
    required List<PaymentRecord> payments,
    required DateTimeRange range,
    required String query,
    PaymentState? stateFilter,
    PaymentMethod? methodFilter,
  }) {
    final normalized = query.trim().toLowerCase();
    return payments
        .where((payment) {
          if (payment.recordedAt.isBefore(range.start) ||
              payment.recordedAt.isAfter(range.end)) {
            return false;
          }
          if (stateFilter != null && payment.state != stateFilter) {
            return false;
          }
          if (methodFilter != null && payment.method != methodFilter) {
            return false;
          }
          if (normalized.isEmpty) {
            return true;
          }
          return payment.id.toLowerCase().contains(normalized) ||
              payment.jobId.toLowerCase().contains(normalized) ||
              payment.customerId.toLowerCase().contains(normalized) ||
              payment.proId.toLowerCase().contains(normalized);
        })
        .toList(growable: false);
  }

  List<UserReport> _filterReports({
    required List<UserReport> reports,
    required String query,
    required int categoryIndex,
  }) {
    final normalized = query.trim().toLowerCase();
    return reports
        .where((report) {
          final matchesCategory = switch (categoryIndex) {
            0 => _isMessageReport(report),
            1 => !_isMessageReport(report) && !_isFraudReport(report),
            2 => _isFraudReport(report),
            _ => true,
          };
          if (!matchesCategory) {
            return false;
          }
          if (normalized.isEmpty) {
            return true;
          }
          return report.reporterId.toLowerCase().contains(normalized) ||
              report.targetUserId.toLowerCase().contains(normalized) ||
              report.reasonText.toLowerCase().contains(normalized);
        })
        .toList(growable: false);
  }

  List<AuditEvent> _filterAudits({
    required List<AuditEvent> audits,
    required String query,
    required DateTimeRange range,
  }) {
    final normalized = query.trim().toLowerCase();
    return audits
        .where((event) {
          final isInRange =
              (event.createdAt.isAfter(range.start) ||
                  event.createdAt.isAtSameMomentAs(range.start)) &&
              event.createdAt.isBefore(
                range.end.add(const Duration(seconds: 1)),
              );
          if (!isInRange) {
            return false;
          }
          if (normalized.isEmpty) {
            return true;
          }
          return event.actorId.toLowerCase().contains(normalized) ||
              event.action.toLowerCase().contains(normalized) ||
              event.entityType.toLowerCase().contains(normalized) ||
              event.entityId.toLowerCase().contains(normalized);
        })
        .toList(growable: false);
  }

  int _activeUsers({
    required List<AuditEvent> audits,
    required Map<String, AppUser> usersById,
    required DateTime since,
  }) {
    final ids = audits
        .where((event) => event.createdAt.isAfter(since))
        .map((event) => event.actorId)
        .where((id) => usersById[id]?.role != UserRole.admin)
        .toSet();
    return ids.length;
  }

  List<_ChartPoint> _cumulativeSeries(List<_ChartPoint> points) {
    var running = 0.0;
    return points
        .map((point) {
          running += point.value;
          return _ChartPoint(label: point.label, value: running);
        })
        .toList(growable: false);
  }

  List<_ActivityEntry> _buildActivityFeed({
    required List<AuditEvent> audits,
    required List<UserReport> reports,
    required Map<String, AppUser> usersById,
  }) {
    final entries = <_ActivityEntry>[
      ...audits.map(
        (event) => _ActivityEntry(
          title: _auditActionLabel(event.action),
          subtitle:
              '${usersById[event.actorId]?.fullName ?? event.actorId} · ${event.entityType}',
          timestamp: event.createdAt,
          icon: Icons.shield_outlined,
        ),
      ),
      ...reports.map(
        (report) => _ActivityEntry(
          title: 'Report submitted',
          subtitle: report.reasonText,
          timestamp: report.createdAt,
          icon: Icons.report_outlined,
        ),
      ),
    ];
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries.take(8).toList(growable: false);
  }

  bool _isMessageReport(UserReport report) {
    final reason = report.reasonText.toLowerCase();
    return reason.contains('message') ||
        reason.contains('chat') ||
        reason.contains('abuse') ||
        reason.contains('harass') ||
        reason.contains('spam');
  }

  bool _isFraudReport(UserReport report) {
    final reason = report.reasonText.toLowerCase();
    return reason.contains('fraud') ||
        reason.contains('scam') ||
        reason.contains('payment') ||
        reason.contains('charge') ||
        reason.contains('money');
  }

  String _auditActionLabel(String action) {
    return action.replaceAll('_', ' ').toUpperCase();
  }

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 720;
        final headerContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        );
        if (trailing == null) {
          return headerContent;
        }
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              headerContent,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: trailing),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: headerContent),
            trailing,
          ],
        );
      },
    );
  }
}

class _MetricCardData {
  const _MetricCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tone;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _MetricCardData metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            metric.tone.withOpacity(0.18),
            Theme.of(context).cardColor,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: metric.tone.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(metric.icon, color: metric.tone),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerRight,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    metric.value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            metric.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({required this.points});

  final List<_ChartPoint> points;

  @override
  Widget build(BuildContext context) {
    final values = points.map((point) => point.value).toList(growable: false);
    return SizedBox(
      height: 180,
      child: CustomPaint(
        painter: _LineChartPainter(
          values: values,
          color: Theme.of(context).colorScheme.primary,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 120),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: points
                  .map(
                    (point) => Text(
                      point.label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      return;
    }
    final maxValue = values
        .reduce((a, b) => a > b ? a : b)
        .clamp(1, double.infinity);
    final stepX = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i += 1) {
      final x = stepX * i;
      final y = size.height - (values[i] / maxValue) * (size.height - 30);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;
    canvas.drawPath(path, paint);

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: <Color>[color.withOpacity(0.22), color.withOpacity(0.0)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.points});

  final List<_ChartPoint> points;

  @override
  Widget build(BuildContext context) {
    final maxValue = points.isEmpty
        ? 1.0
        : points.map((p) => p.value).reduce(max).clamp(1, double.infinity);
    return SizedBox(
      height: 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: points
            .map(
              (point) => Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: point.value / maxValue,
                          widthFactor: 0.5,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.secondary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      point.label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _PieChart extends StatelessWidget {
  const _PieChart({required this.slices});

  final List<_PieSlice> slices;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(constraints.maxWidth, 200.0);
        return Row(
          children: <Widget>[
            SizedBox(
              width: size,
              height: size,
              child: CustomPaint(painter: _PieChartPainter(slices: slices)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: slices
                    .map(
                      (slice) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: slice.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(slice.label)),
                            Text(formatPkr(slice.value)),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PieChartPainter extends CustomPainter {
  _PieChartPainter({required this.slices});

  final List<_PieSlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (sum, slice) => sum + slice.value);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    var startAngle = -pi / 2;
    for (final slice in slices) {
      final sweep = total == 0 ? 0.0 : (slice.value / total) * 2 * pi;
      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.fill;
      canvas.drawArc(rect, startAngle, sweep, true, paint);
      startAngle += sweep;
    }
    final holePaint = Paint()..color = Colors.white.withOpacity(0.92);
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * 0.22,
      holePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.slices != slices;
  }
}

class _ActivityEntry {
  const _ActivityEntry({
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final DateTime timestamp;
  final IconData icon;
}

class _ActivityFeed extends StatelessWidget {
  const _ActivityFeed({required this.entries});

  final List<_ActivityEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Text('No recent activity.');
    }
    return Column(
      children: entries
          .map(
            (entry) => ListTile(
              leading: Icon(entry.icon),
              title: Text(entry.title),
              subtitle: Text(entry.subtitle),
              trailing: Text(formatDateTime(entry.timestamp)),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _LockedCard extends StatelessWidget {
  const _LockedCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.lock_outline),
        title: Text(message),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.inbox_outlined),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 16),
          ],
        ),
      ),
    );
  }
}

enum _UserAction { verifyPro, unverifyPro, suspend, restore, flag }

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.audits,
    required this.sessions,
    required this.payments,
    required this.canManageUsers,
    required this.onAction,
  });

  final AppUser user;
  final List<AuditEvent> audits;
  final List<UserSessionRecord> sessions;
  final List<PaymentRecord> payments;
  final bool canManageUsers;
  final void Function(_UserAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final recentEvents =
        audits
            .where((event) => event.actorId == user.id)
            .toList(growable: false)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final visibleEvents = recentEvents.take(3).toList(growable: false);
    final userSessions = sessions
        .where((session) => session.userId == user.id)
        .toList(growable: false);
    final averageSession = userSessions.isEmpty
        ? Duration.zero
        : Duration(
            microseconds:
                userSessions.fold<int>(
                  0,
                  (total, session) => total + session.duration.inMicroseconds,
                ) ~/
                userSessions.length,
          );
    final transactionCount = payments
        .where(
          (payment) =>
              payment.customerId == user.id || payment.proId == user.id,
        )
        .length;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: user.blocked
              ? const Color(0xFFFFE3E3)
              : const Color(0xFFE3F2FD),
          child: Icon(
            user.role == UserRole.pro
                ? Icons.handyman_outlined
                : Icons.person_outline,
            color: user.blocked ? const Color(0xFFC62828) : AppTheme.brandBlue,
          ),
        ),
        title: Text(user.fullName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${user.email} · ${user.phone}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            _StatusChip(
              label: user.blocked ? 'Suspended' : 'Active',
              tone: user.blocked
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF10B981),
            ),
          ],
        ),
        trailing: PopupMenuButton<_UserAction>(
          onSelected: onAction,
          itemBuilder: (context) => <PopupMenuEntry<_UserAction>>[
            if (user.role == UserRole.pro)
              const PopupMenuItem(
                value: _UserAction.verifyPro,
                child: Text('Verify Pro'),
              ),
            if (user.role == UserRole.pro)
              const PopupMenuItem(
                value: _UserAction.unverifyPro,
                child: Text('Unverify Pro'),
              ),
            if (canManageUsers && !user.blocked)
              const PopupMenuItem(
                value: _UserAction.suspend,
                child: Text('Suspend Account'),
              ),
            if (canManageUsers && user.blocked)
              const PopupMenuItem(
                value: _UserAction.restore,
                child: Text('Restore Account'),
              ),
            const PopupMenuItem(
              value: _UserAction.flag,
              child: Text('Flag Suspicious Activity'),
            ),
          ],
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('User ID: ${user.id}', softWrap: true),
                Text('Role: ${user.role.name}'),
                Text(
                  'Completed sessions: ${userSessions.length} · Average: ${_formatSessionDuration(averageSession)}',
                  softWrap: true,
                ),
                Text(
                  'Preferred categories: ${user.preferredCategories.map((c) => c.displayName).join(', ')}',
                  softWrap: true,
                ),
                Text('Transactions: $transactionCount'),
                const SizedBox(height: 8),
                Text(
                  'Recent Activity',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (visibleEvents.isEmpty)
                  const Text('No recent activity recorded.'),
                if (visibleEvents.isNotEmpty)
                  Column(
                    children: visibleEvents
                        .map(
                          (event) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(event.action),
                            subtitle: Text(formatDateTime(event.createdAt)),
                          ),
                        )
                        .toList(growable: false),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatSessionDuration(Duration duration) {
  final seconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  return '${minutes}m ${seconds % 60}s';
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: tone, fontWeight: FontWeight.w600),
      ),
    );
  }
}

enum _ReportAction { review, actionTaken, dismiss, blockUser }

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.reporter,
    required this.target,
    required this.status,
    required this.onStatusChange,
    required this.onAction,
  });

  final UserReport report;
  final AppUser? reporter;
  final AppUser? target;
  final _ReportStatus status;
  final void Function(_ReportStatus status) onStatusChange;
  final void Function(_ReportAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (status) {
      _ReportStatus.open => 'Open',
      _ReportStatus.underReview => 'Under Review',
      _ReportStatus.actionTaken => 'Action Taken',
      _ReportStatus.dismissed => 'Dismissed',
    };
    final tone = switch (status) {
      _ReportStatus.open => const Color(0xFFF59E0B),
      _ReportStatus.underReview => const Color(0xFF2563EB),
      _ReportStatus.actionTaken => const Color(0xFF10B981),
      _ReportStatus.dismissed => const Color(0xFF6B7280),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.report_outlined),
        title: Text(
          '${reporter?.fullName ?? report.reporterId} reported ${target?.fullName ?? report.targetUserId}',
        ),
        subtitle: Text(
          '${report.reasonText}\n${formatDateTime(report.createdAt)}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _StatusChip(label: statusLabel, tone: tone),
            PopupMenuButton<_ReportAction>(
              onSelected: (action) {
                onAction(action);
                if (action == _ReportAction.review) {
                  onStatusChange(_ReportStatus.underReview);
                }
                if (action == _ReportAction.actionTaken) {
                  onStatusChange(_ReportStatus.actionTaken);
                }
                if (action == _ReportAction.dismiss) {
                  onStatusChange(_ReportStatus.dismissed);
                }
              },
              itemBuilder: (context) => <PopupMenuEntry<_ReportAction>>[
                const PopupMenuItem(
                  value: _ReportAction.review,
                  child: Text('Mark Under Review'),
                ),
                const PopupMenuItem(
                  value: _ReportAction.actionTaken,
                  child: Text('Mark Action Taken'),
                ),
                const PopupMenuItem(
                  value: _ReportAction.dismiss,
                  child: Text('Dismiss'),
                ),
                if (target != null)
                  const PopupMenuItem(
                    value: _ReportAction.blockUser,
                    child: Text('Block User'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SecurityTile extends StatelessWidget {
  const _SecurityTile({
    required this.title,
    required this.value,
    required this.description,
  });

  final String title;
  final String value;
  final String description;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.brandTeal,
                ),
              ),
              const SizedBox(height: 6),
              Text(description),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.title,
    required this.value,
    required this.tone,
    required this.description,
  });

  final String title;
  final int value;
  final Color tone;
  final String description;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: tone.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.notifications_active_outlined,
                      color: tone,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value.toString(),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(description),
            ],
          ),
        ),
      ),
    );
  }
}
