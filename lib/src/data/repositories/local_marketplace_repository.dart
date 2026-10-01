import 'dart:async';
import 'dart:convert';

// ignore_for_file: use_null_aware_elements

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/device_context_service.dart';
import '../../core/services/payment_calculator.dart';
import '../../core/services/pro_balance_rules.dart';
import '../../domain/models.dart';
import 'marketplace_repository.dart';

class LocalMarketplaceRepository implements MarketplaceRepository {
  LocalMarketplaceRepository({
    double initialCommissionRate = 0.075,
    String? persistedStateJson,
  }) : _commissionRate = initialCommissionRate,
       _categoryCommissionRates = <JobCategory, double>{
         for (final category in JobCategory.values)
           category: initialCommissionRate,
       },
       _paymentCalculator = PaymentCalculator(initialCommissionRate) {
    final restored =
        persistedStateJson != null && _restoreState(persistedStateJson);
    if (!restored) {
      _seedUsers();
      _seedJobs();
    }
    _persistSoon();
  }

  static const String storageKey = 'local_marketplace_repository_state_v1';

  final _uuid = const Uuid();
  final String _sessionId = const Uuid().v4();
  final Map<String, AppUser> _users = <String, AppUser>{};
  final Map<String, String> _passwordByEmail = <String, String>{};
  final Map<String, Job> _jobs = <String, Job>{};
  final Map<String, Bid> _bids = <String, Bid>{};
  final Map<String, PaymentRecord> _payments = <String, PaymentRecord>{};
  final Map<String, List<ChatMessage>> _messagesByJob =
      <String, List<ChatMessage>>{};
  final Map<String, NotificationEvent> _notifications =
      <String, NotificationEvent>{};
  final Map<String, AuditEvent> _auditEvents = <String, AuditEvent>{};
  final Map<String, UserReport> _reports = <String, UserReport>{};

  final _currentUserController = StreamController<AppUser?>.broadcast();
  final _usersController = StreamController<List<AppUser>>.broadcast();
  final _jobsController = StreamController<List<Job>>.broadcast();
  final _paymentsController = StreamController<List<PaymentRecord>>.broadcast();
  final _auditController = StreamController<List<AuditEvent>>.broadcast();
  final _reportsController = StreamController<List<UserReport>>.broadcast();
  final _notificationsController =
      StreamController<List<NotificationEvent>>.broadcast();
  final Map<String, StreamController<Job?>> _jobById =
      <String, StreamController<Job?>>{};
  final Map<String, StreamController<List<Bid>>> _bidsByJob =
      <String, StreamController<List<Bid>>>{};
  final Map<String, StreamController<List<ChatMessage>>> _messagesStreams =
      <String, StreamController<List<ChatMessage>>>{};

  late PaymentCalculator _paymentCalculator;
  AppUser? _currentUser;
  double _commissionRate;
  final Map<JobCategory, double> _categoryCommissionRates;
  bool _disposed = false;

  static Future<String?> loadPersistedState() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(storageKey);
  }

  void _persistSoon() {
    if (_disposed) {
      return;
    }
    unawaited(_persistState());
  }

  Future<void> _persistState() async {
    if (_disposed) {
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(storageKey, jsonEncode(_snapshotJson()));
  }

  Map<String, dynamic> _snapshotJson() {
    return <String, dynamic>{
      'current_user_id': _currentUser?.id,
      'commission_rate': _commissionRate,
      'category_commission_rates': <String, double>{
        for (final entry in _categoryCommissionRates.entries)
          entry.key.value: entry.value,
      },
      'users': _users.values
          .map((user) => user.toJson())
          .toList(growable: false),
      'password_by_email': Map<String, String>.from(_passwordByEmail),
      'jobs': _jobs.values.map((job) => job.toJson()).toList(growable: false),
      'bids': _bids.values.map((bid) => bid.toJson()).toList(growable: false),
      'payments': _payments.values
          .map((payment) => payment.toJson())
          .toList(growable: false),
      'messages_by_job': <String, List<Map<String, dynamic>>>{
        for (final entry in _messagesByJob.entries)
          entry.key: entry.value
              .map((message) => message.toJson())
              .toList(growable: false),
      },
      'notifications': _notifications.values
          .map((notification) => notification.toJson())
          .toList(growable: false),
      'audit_events': _auditEvents.values
          .map((event) => event.toJson())
          .toList(growable: false),
      'reports': _reports.values
          .map((report) => report.toJson())
          .toList(growable: false),
    };
  }

  bool _restoreState(String persistedStateJson) {
    try {
      final payload = jsonDecode(persistedStateJson) as Map<String, dynamic>;

      _users.clear();
      _passwordByEmail.clear();
      _jobs.clear();
      _bids.clear();
      _payments.clear();
      _messagesByJob.clear();
      _notifications.clear();
      _auditEvents.clear();
      _reports.clear();

      final users = payload['users'] as List<dynamic>? ?? <dynamic>[];
      for (final value in users) {
        final user = AppUser.fromJson(Map<String, dynamic>.from(value as Map));
        _users[user.id] = user;
      }

      final passwords = Map<String, dynamic>.from(
        payload['password_by_email'] as Map? ?? <String, dynamic>{},
      );
      for (final entry in passwords.entries) {
        _passwordByEmail[entry.key] = '${entry.value}';
      }

      final jobs = payload['jobs'] as List<dynamic>? ?? <dynamic>[];
      for (final value in jobs) {
        final job = Job.fromJson(Map<String, dynamic>.from(value as Map));
        _jobs[job.id] = job;
      }

      final bids = payload['bids'] as List<dynamic>? ?? <dynamic>[];
      for (final value in bids) {
        final bid = Bid.fromJson(Map<String, dynamic>.from(value as Map));
        _bids[bid.id] = bid;
      }

      final payments = payload['payments'] as List<dynamic>? ?? <dynamic>[];
      for (final value in payments) {
        final payment = PaymentRecord.fromJson(
          Map<String, dynamic>.from(value as Map),
        );
        _payments[payment.id] = payment;
      }

      final rawMessages = Map<String, dynamic>.from(
        payload['messages_by_job'] as Map? ?? <String, dynamic>{},
      );
      for (final entry in rawMessages.entries) {
        final messages = (entry.value as List<dynamic>? ?? <dynamic>[])
            .map(
              (value) =>
                  ChatMessage.fromJson(Map<String, dynamic>.from(value as Map)),
            )
            .toList(growable: false);
        _messagesByJob[entry.key] = messages;
      }

      final notifications =
          payload['notifications'] as List<dynamic>? ?? <dynamic>[];
      for (final value in notifications) {
        final event = NotificationEvent.fromJson(
          Map<String, dynamic>.from(value as Map),
        );
        _notifications[event.id] = event;
      }

      final auditEvents =
          payload['audit_events'] as List<dynamic>? ?? <dynamic>[];
      for (final value in auditEvents) {
        final event = AuditEvent.fromJson(
          Map<String, dynamic>.from(value as Map),
        );
        _auditEvents[event.id] = event;
      }

      final reports = payload['reports'] as List<dynamic>? ?? <dynamic>[];
      for (final value in reports) {
        final report = UserReport.fromJson(
          Map<String, dynamic>.from(value as Map),
        );
        _reports[report.id] = report;
      }

      _commissionRate =
          (payload['commission_rate'] as num?)?.toDouble() ?? _commissionRate;
      _categoryCommissionRates
        ..clear()
        ..addEntries(
          JobCategory.values.map(
            (category) => MapEntry(category, _commissionRate),
          ),
        );
      final rawCategoryRates = Map<String, dynamic>.from(
        payload['category_commission_rates'] as Map? ?? <String, dynamic>{},
      );
      for (final category in JobCategory.values) {
        _categoryCommissionRates[category] =
            (rawCategoryRates[category.value] as num?)?.toDouble() ??
            _commissionRate;
      }
      _paymentCalculator = PaymentCalculator(_commissionRate);

      final currentUserId = payload['current_user_id'] as String?;
      _currentUser = currentUserId == null ? null : _users[currentUserId];
      return _users.isNotEmpty;
    } catch (_) {
      _users.clear();
      _passwordByEmail.clear();
      _jobs.clear();
      _bids.clear();
      _payments.clear();
      _messagesByJob.clear();
      _notifications.clear();
      _auditEvents.clear();
      _reports.clear();
      _currentUser = null;
      return false;
    }
  }

  void _seedUsers() {
    final now = DateTime.now();
    final users = <AppUser>[
      AppUser(
        id: 'admin-1',
        role: UserRole.admin,
        fullName: 'Admin',
        email: 'admin@pakservice.pk',
        phone: '+92 300 0000000',
        adminRank: AdminRank.superAdmin,
        adminPermissions: defaultAdminPermissionsForRank(AdminRank.superAdmin),
        cnicVerified: true,
        policeVerified: true,
        createdAt: now,
        updatedAt: now,
      ),
      AppUser(
        id: 'admin-support-1',
        role: UserRole.admin,
        fullName: 'Support Admin',
        email: 'support@pakservice.pk',
        phone: '+92 300 0000001',
        adminRank: AdminRank.support,
        adminPermissions: defaultAdminPermissionsForRank(AdminRank.support),
        cnicVerified: true,
        policeVerified: true,
        createdAt: now,
        updatedAt: now,
      ),
      AppUser(
        id: 'pro-1',
        role: UserRole.pro,
        fullName: 'Ahmed Electrician',
        email: 'pro@pakservice.pk',
        phone: '+92 301 1111111',
        cnicVerified: true,
        policeVerified: true,
        rating: 4.7,
        totalReviews: 128,
        paymentAccount: 'JazzCash-03011111111',
        savedLocations: <SavedLocation>[
          SavedLocation(
            id: 'loc-pro-1',
            label: 'Home',
            latitude: 33.6844,
            longitude: 73.0479,
            address: 'Blue Area, Islamabad',
            createdAt: now,
          ),
        ],
        preferredCategories: const <JobCategory>[
          JobCategory.electrician,
          JobCategory.acRepair,
          JobCategory.registeredNurse,
        ],
        createdAt: now,
        updatedAt: now,
      ),
      AppUser(
        id: 'pro-locked-1',
        role: UserRole.pro,
        fullName: 'Locked Demo Pro',
        email: 'prolocked@pakservice.pk',
        phone: '+92 303 3333333',
        cnicVerified: true,
        policeVerified: true,
        rating: 4.5,
        totalReviews: 64,
        paymentAccount: 'EasyPaisa-03033333333',
        totalEarnings: 22500,
        dueToApp: 2150,
        savedLocations: <SavedLocation>[
          SavedLocation(
            id: 'loc-pro-locked-1',
            label: 'Office',
            latitude: 33.6900,
            longitude: 73.0551,
            address: 'F-8 Markaz, Islamabad',
            createdAt: now,
          ),
        ],
        preferredCategories: const <JobCategory>[
          JobCategory.electrician,
          JobCategory.plumbing,
          JobCategory.acRepair,
        ],
        createdAt: now,
        updatedAt: now,
      ),
      AppUser(
        id: 'customer-1',
        role: UserRole.customer,
        fullName: 'Sara Customer',
        email: 'user@pakservice.pk',
        phone: '+92 302 2222222',
        createdAt: now,
        updatedAt: now,
      ),
    ];

    for (final user in users) {
      _users[user.id] = user;
    }
    _passwordByEmail['admin@pakservice.pk'] = 'Admin123!';
    _passwordByEmail['support@pakservice.pk'] = 'Support123!';
    _passwordByEmail['pro@pakservice.pk'] = 'Pro12345!';
    _passwordByEmail['prolocked@pakservice.pk'] = 'Locked123!';
    _passwordByEmail['user@pakservice.pk'] = 'User12345!';
  }

  void _seedJobs() {
    final now = DateTime.now();
    final jobs = <Job>[
      Job(
        id: 'job-seed-1',
        customerId: 'customer-1',
        category: JobCategory.electrician,
        title: 'Ceiling fan rewiring needed',
        description:
            'Two ceiling fans stopped working after voltage fluctuation.',
        fixedPrice: 4000,
        latitude: 33.6849,
        longitude: 73.0479,
        maskedAddress: 'Blue Area, Islamabad',
        exactAddress: 'Office 24-B, Blue Area, Islamabad',
        status: JobStatus.available,
        createdAt: now.subtract(const Duration(hours: 3)),
        updatedAt: now.subtract(const Duration(hours: 3)),
        timeline: <JobTimelineEvent>[
          JobTimelineEvent(
            type: JobStatus.posted.value,
            at: now.subtract(const Duration(hours: 3)),
            actorId: 'customer-1',
          ),
          JobTimelineEvent(
            type: JobStatus.available.value,
            at: now.subtract(const Duration(hours: 3)),
            actorId: 'customer-1',
          ),
        ],
      ),
      Job(
        id: 'job-seed-2',
        customerId: 'customer-1',
        category: JobCategory.plumbing,
        title: 'Kitchen sink leakage repair',
        description: 'Sink pipe is leaking heavily, need urgent fix.',
        fixedPrice: 2500,
        latitude: 33.7000,
        longitude: 73.0500,
        maskedAddress: 'F-7, Islamabad',
        exactAddress: 'Street 15, House 9, F-7, Islamabad',
        status: JobStatus.available,
        createdAt: now.subtract(const Duration(hours: 1)),
        updatedAt: now.subtract(const Duration(hours: 1)),
        timeline: <JobTimelineEvent>[
          JobTimelineEvent(
            type: JobStatus.posted.value,
            at: now.subtract(const Duration(hours: 1)),
            actorId: 'customer-1',
          ),
          JobTimelineEvent(
            type: JobStatus.available.value,
            at: now.subtract(const Duration(hours: 1)),
            actorId: 'customer-1',
          ),
        ],
      ),
    ];
    for (final job in jobs) {
      _jobs[job.id] = job;
    }
  }

  @override
  Stream<AppUser?> watchCurrentUser() async* {
    yield _currentUser;
    yield* _currentUserController.stream;
  }

  @override
  Future<AppUser?> getCurrentUser() async => _currentUser;

  @override
  Future<AppUser> register(RegisterInput input) async {
    if (!input.acceptance.checkboxConfirmed) {
      throw StateError('Terms and Privacy acceptance is required.');
    }
    final email = input.email.trim().toLowerCase();
    input.validateForRole(input.role);
    final preferredCategories = input.normalizedPreferredCategoriesForRole(
      input.role,
    );
    if (_passwordByEmail.containsKey(email)) {
      throw StateError('Email already exists.');
    }

    final now = DateTime.now();
    final user = AppUser(
      id: _uuid.v4(),
      role: input.role,
      fullName: input.fullName.trim(),
      email: email,
      phone: input.phone.trim(),
      preferredCategories: preferredCategories,
      termsAcceptanceHistory: <TermsAcceptance>[input.acceptance],
      createdAt: now,
      updatedAt: now,
    );
    _users[user.id] = user;
    _passwordByEmail[email] = input.password;
    _currentUser = user;
    _currentUserController.add(user);
    _emitUsers();

    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: user.id,
        action: 'register',
        entityType: 'user',
        entityId: user.id,
        createdAt: now,
        metadata: <String, dynamic>{
          'terms_version': input.acceptance.termsVersion,
          'privacy_version': input.acceptance.privacyVersion,
          'accepted_at': input.acceptance.acceptedAt.toIso8601String(),
        },
        ipAddress: input.acceptance.ipAddress,
        deviceInfo: input.acceptance.deviceInfo,
      ),
    );
    return user;
  }

  @override
  Future<AppUser> signIn(LoginInput input) async {
    final email = input.email.trim().toLowerCase();
    if (_passwordByEmail[email] != input.password) {
      throw StateError('Invalid email or password.');
    }
    final user = _users.values.firstWhere(
      (u) => u.email.toLowerCase() == email,
    );
    if (user.blocked) {
      throw StateError('Account is blocked.');
    }
    _currentUser = user;
    _currentUserController.add(user);
    _persistSoon();
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: user.id,
        action: 'login',
        entityType: 'session',
        entityId: user.id,
        createdAt: DateTime.now(),
        deviceInfo: DeviceContextService().describeDevice(),
        metadata: <String, dynamic>{'session_id': _sessionId},
      ),
    );
    return user;
  }

  @override
  Future<void> signOut() async {
    final user = _currentUser;
    _currentUser = null;
    _currentUserController.add(null);
    _persistSoon();
    if (user == null) {
      return;
    }
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: user.id,
        action: 'logout',
        entityType: 'session',
        entityId: user.id,
        createdAt: DateTime.now(),
        deviceInfo: DeviceContextService().describeDevice(),
        metadata: <String, dynamic>{'session_id': _sessionId},
      ),
    );
  }

  @override
  Future<void> updateProfile(AppUser user) async {
    final currentUserId = _currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw StateError('Not authenticated.');
    }
    final existing = _users[currentUserId];
    if (existing == null) {
      throw StateError('User not found.');
    }
    final updated = existing.copyWith(
      fullName: user.fullName,
      phone: user.phone,
      profileImageUrl: user.profileImageUrl,
      languageCode: user.languageCode,
      notificationsEnabled: user.notificationsEnabled,
      preciseLocationEnabled: user.preciseLocationEnabled,
      paymentAccount: user.paymentAccount,
      preferredCategories: user.preferredCategories,
      savedLocations: user.savedLocations,
      updatedAt: DateTime.now(),
    );
    _users[currentUserId] = updated;
    if (_currentUser?.id == currentUserId) {
      _currentUser = updated;
      _currentUserController.add(updated);
    }
    _emitUsers();
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: currentUserId,
        action: 'profile_updated',
        entityType: 'user',
        entityId: currentUserId,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<AppUser> upgradeToProfessional({
    required List<JobCategory> preferredCategories,
  }) async {
    final current = _currentUser;
    if (current == null) {
      throw StateError('Not authenticated.');
    }
    if (current.role == UserRole.admin) {
      throw StateError(
        'Admin accounts cannot be converted to professional accounts.',
      );
    }
    final categories = preferredCategories.toSet().toList(growable: false);
    if (categories.isEmpty) {
      throw StateError('Select at least one service category.');
    }

    final upgraded = current.copyWith(
      role: UserRole.pro,
      preferredCategories: categories,
      updatedAt: DateTime.now(),
    );
    _users[upgraded.id] = upgraded;
    _currentUser = upgraded;
    _currentUserController.add(upgraded);
    _emitUsers();
    _persistSoon();
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: upgraded.id,
        action: 'pro_profile_activated',
        entityType: 'user',
        entityId: upgraded.id,
        createdAt: DateTime.now(),
        metadata: <String, dynamic>{
          'preferred_categories': categories
              .map((category) => category.value)
              .toList(growable: false),
        },
      ),
    );
    return upgraded;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _currentUser;
    if (user == null) {
      throw StateError('Not authenticated.');
    }
    if (_passwordByEmail[user.email.toLowerCase()] != currentPassword) {
      throw StateError('Current password does not match.');
    }
    _passwordByEmail[user.email.toLowerCase()] = newPassword;
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: user.id,
        action: 'password_changed',
        entityType: 'user',
        entityId: user.id,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Stream<List<AppUser>> watchAllUsers({bool includeLocations = false}) async* {
    yield _users.values.toList(growable: false);
    yield* _usersController.stream;
  }

  @override
  Future<void> verifyPro({
    required String userId,
    required bool cnicVerified,
    required bool policeVerified,
  }) {
    return setProVerification(
      actorId: _currentUser?.id ?? 'admin',
      userId: userId,
      cnicVerified: cnicVerified,
      policeVerified: policeVerified,
    );
  }

  @override
  Future<void> setProVerification({
    required String actorId,
    required String userId,
    required bool cnicVerified,
    required bool policeVerified,
  }) async {
    _requireAdminPermission(actorId, AdminPermission.manageProVerification);
    final user = _users[userId];
    if (user == null || user.role != UserRole.pro) {
      throw StateError('Professional user not found.');
    }
    _users[userId] = user.copyWith(
      cnicVerified: cnicVerified,
      policeVerified: policeVerified,
      updatedAt: DateTime.now(),
    );
    _emitUsers();
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: actorId,
        action: 'pro_verification_updated',
        entityType: 'user',
        entityId: userId,
        createdAt: DateTime.now(),
        metadata: <String, dynamic>{
          'cnic_verified': cnicVerified,
          'police_verified': policeVerified,
        },
      ),
    );
  }

  @override
  Future<void> saveLocation({
    required String userId,
    required SavedLocation location,
  }) async {
    final user = _users[userId];
    if (user == null) {
      throw StateError('User not found.');
    }
    _users[userId] = user.copyWith(
      savedLocations: <SavedLocation>[...user.savedLocations, location],
      updatedAt: DateTime.now(),
    );
    if (_currentUser?.id == userId) {
      _currentUser = _users[userId];
      _currentUserController.add(_currentUser);
    }
    _emitUsers();
  }

  @override
  Stream<List<Job>> watchNearbyJobs({
    required JobCategory category,
    required double latitude,
    required double longitude,
    double radiusKm = 25,
  }) async* {
    List<Job> filter(List<Job> jobs) {
      final filtered = jobs
          .where((job) {
            if (job.category != category) {
              return false;
            }
            if (job.status != JobStatus.available &&
                job.status != JobStatus.posted) {
              return false;
            }
            final distanceMeters = Geolocator.distanceBetween(
              latitude,
              longitude,
              job.latitude,
              job.longitude,
            );
            return (distanceMeters / 1000) <= radiusKm;
          })
          .toList(growable: false);
      filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return filtered;
    }

    yield filter(_jobs.values.toList(growable: false));
    yield* _jobsController.stream.map(filter);
  }

  @override
  Stream<List<Job>> watchJobsForUser(String userId) async* {
    List<Job> filter(List<Job> jobs) {
      final mine = jobs
          .where((job) => job.customerId == userId)
          .toList(growable: false);
      mine.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return mine;
    }

    yield filter(_jobs.values.toList(growable: false));
    yield* _jobsController.stream.map(filter);
  }

  @override
  Stream<List<Job>> watchJobsForPro(String proId) async* {
    List<Job> filter(List<Job> jobs) {
      final mine = jobs.where((job) => job.assignedProId == proId).toList();
      mine.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return mine;
    }

    yield filter(_jobs.values.toList(growable: false));
    yield* _jobsController.stream.map(filter);
  }

  @override
  Stream<List<Job>> watchAllJobs() async* {
    List<Job> sort(List<Job> jobs) {
      final sorted = List<Job>.from(jobs);
      sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return sorted;
    }

    yield sort(_jobs.values.toList(growable: false));
    yield* _jobsController.stream.map(sort);
  }

  @override
  Stream<Job?> watchJob(String jobId) {
    final controller = _jobById.putIfAbsent(
      jobId,
      () => StreamController<Job?>.broadcast(
        onListen: () {
          _jobById[jobId]?.add(_jobs[jobId]);
        },
      ),
    );
    return controller.stream;
  }

  @override
  Stream<List<Bid>> watchBids(String jobId) {
    final controller = _bidsByJob.putIfAbsent(
      jobId,
      () => StreamController<List<Bid>>.broadcast(
        onListen: () {
          _bidsByJob[jobId]?.add(
            _bids.values
                .where((bid) => bid.jobId == jobId)
                .toList(growable: false),
          );
        },
      ),
    );
    return controller.stream;
  }

  @override
  Future<Job> postJob(JobPostInput input) async {
    if (input.fixedPrice <= 0) {
      throw StateError('Price must be positive.');
    }
    final now = DateTime.now();
    final job = Job(
      id: _uuid.v4(),
      customerId: input.customerId,
      category: input.category,
      title: input.title.trim(),
      description: input.description.trim(),
      fixedPrice: input.fixedPrice,
      latitude: input.latitude,
      longitude: input.longitude,
      maskedAddress: input.maskedAddress,
      exactAddress: input.exactAddress,
      status: JobStatus.available,
      createdAt: now,
      updatedAt: now,
      timeline: <JobTimelineEvent>[
        JobTimelineEvent(
          type: 'posted',
          at: now,
          actorId: input.customerId,
          metadata: <String, dynamic>{
            if (input.imageAttachments.isNotEmpty)
              'image_attachments': input.imageAttachments,
          },
        ),
        JobTimelineEvent(type: 'available', at: now, actorId: input.customerId),
      ],
    );
    _jobs[job.id] = job;
    _emitJobs(job.id);

    final pros = _users.values.where(
      (u) =>
          u.role == UserRole.pro &&
          u.isVerifiedPro &&
          u.preferredCategories.contains(job.category) &&
          _isProNearbyJob(u, job) &&
          !u.blocked,
    );
    for (final pro in pros) {
      _addNotification(
        NotificationEvent(
          id: _uuid.v4(),
          userId: pro.id,
          type: 'job_nearby',
          title: 'New ${job.category.displayName} job',
          body: 'Fixed price: PKR ${job.fixedPrice.toStringAsFixed(0)}',
          sentAt: now,
          metadata: <String, dynamic>{'job_id': job.id},
        ),
      );
    }

    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: input.customerId,
        action: 'job_posted',
        entityType: 'job',
        entityId: job.id,
        createdAt: now,
      ),
    );
    return job;
  }

  @override
  Future<void> updateJobDetails(JobUpdateInput input) async {
    if (input.fixedPrice <= 0) {
      throw StateError('Price must be positive.');
    }
    if (input.title.trim().isEmpty ||
        input.description.trim().isEmpty ||
        input.maskedAddress.trim().isEmpty ||
        input.exactAddress.trim().isEmpty) {
      throw StateError('All job details are required.');
    }
    final job = _jobs[input.jobId];
    if (job == null) {
      throw StateError('Job not found.');
    }
    final actor = _users[input.actorId];
    final actorIsAdmin = actor?.role == UserRole.admin;
    if (!actorIsAdmin && job.customerId != input.actorId) {
      throw StateError('Only the customer who posted this job can edit it.');
    }
    if (job.status != JobStatus.available && job.status != JobStatus.posted) {
      throw StateError('Job can only be edited while it is still open.');
    }

    final now = DateTime.now();
    final updatedJob = job.copyWith(
      title: input.title.trim(),
      description: input.description.trim(),
      fixedPrice: input.fixedPrice,
      latitude: input.latitude,
      longitude: input.longitude,
      maskedAddress: input.maskedAddress.trim(),
      exactAddress: input.exactAddress.trim(),
      updatedAt: now,
      timeline: <JobTimelineEvent>[
        ...job.timeline,
        JobTimelineEvent(
          type: 'details_updated',
          at: now,
          actorId: input.actorId,
        ),
      ],
    );
    _jobs[input.jobId] = updatedJob;
    _emitJobs(input.jobId);
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: input.actorId,
        action: 'job_details_updated',
        entityType: 'job',
        entityId: input.jobId,
        createdAt: now,
      ),
    );
  }

  @override
  Future<Bid> submitBid(BidInput input) async {
    final pro = _users[input.proId];
    if (pro == null || pro.role != UserRole.pro) {
      throw StateError('Professional account not found.');
    }
    if (ProBalanceRules.isLocked(pro.dueToApp)) {
      throw StateError(
        'Account locked. Please clear your due to continue bidding.',
      );
    }
    final job = _jobs[input.jobId];
    if (job == null ||
        (job.status != JobStatus.available && job.status != JobStatus.posted)) {
      throw StateError('Job is not open for bids.');
    }
    if (!pro.preferredCategories.contains(job.category)) {
      throw StateError(
        'You can only bid on jobs that match your registered categories.',
      );
    }
    if (input.amount < job.fixedPrice) {
      throw StateError('Bid must be >= fixed price.');
    }
    final existingBids =
        _bids.values
            .where((bid) => bid.jobId == job.id && bid.proId == input.proId)
            .toList(growable: false)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (existingBids.isNotEmpty) {
      final latest = existingBids.first;
      if (latest.status != BidStatus.pending) {
        throw StateError('Bid is already finalized and cannot be edited.');
      }
      final updatedBid = Bid(
        id: latest.id,
        jobId: latest.jobId,
        proId: latest.proId,
        amount: input.amount,
        status: latest.status,
        createdAt: DateTime.now(),
        notes: input.notes,
      );
      _bids[updatedBid.id] = updatedBid;
      _bidsByJob[job.id]?.add(
        _bids.values.where((b) => b.jobId == job.id).toList(growable: false),
      );
      _addNotification(
        NotificationEvent(
          id: _uuid.v4(),
          userId: job.customerId,
          type: 'bid_updated',
          title: 'Bid updated',
          body: 'Updated bid: PKR ${updatedBid.amount.toStringAsFixed(0)}',
          sentAt: DateTime.now(),
          metadata: <String, dynamic>{
            'job_id': job.id,
            'bid_id': updatedBid.id,
          },
        ),
      );
      await addAuditEvent(
        AuditEvent(
          id: _uuid.v4(),
          actorId: input.proId,
          action: 'bid_updated',
          entityType: 'bid',
          entityId: updatedBid.id,
          createdAt: DateTime.now(),
        ),
      );
      return updatedBid;
    }

    final newBid = Bid(
      id: _uuid.v4(),
      jobId: job.id,
      proId: input.proId,
      amount: input.amount,
      status: BidStatus.pending,
      createdAt: DateTime.now(),
      notes: input.notes,
    );
    _bids[newBid.id] = newBid;
    _bidsByJob[job.id]?.add(
      _bids.values.where((b) => b.jobId == job.id).toList(growable: false),
    );

    _addNotification(
      NotificationEvent(
        id: _uuid.v4(),
        userId: job.customerId,
        type: 'bid_received',
        title: 'New bid',
        body: 'PKR ${newBid.amount.toStringAsFixed(0)} by a pro',
        sentAt: DateTime.now(),
        metadata: <String, dynamic>{'job_id': job.id, 'bid_id': newBid.id},
      ),
    );

    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: input.proId,
        action: 'bid_submitted',
        entityType: 'bid',
        entityId: newBid.id,
        createdAt: DateTime.now(),
      ),
    );
    return newBid;
  }

  @override
  Future<void> acceptBid({
    required String jobId,
    required String bidId,
    required String customerId,
  }) async {
    final job = _jobs[jobId];
    final bid = _bids[bidId];
    if (job == null || bid == null || bid.jobId != jobId) {
      throw StateError('Job or bid not found.');
    }
    if (job.customerId != customerId) {
      throw StateError('Only job owner can accept bid.');
    }
    for (final entry in _bids.entries.where((e) => e.value.jobId == jobId)) {
      _bids[entry.key] = entry.value.copyWith(
        status: entry.key == bidId ? BidStatus.accepted : BidStatus.rejected,
      );
    }
    _bidsByJob[jobId]?.add(
      _bids.values.where((e) => e.jobId == jobId).toList(growable: false),
    );
    final now = DateTime.now();
    _jobs[jobId] = job.copyWith(
      selectedBidId: bid.id,
      assignedProId: bid.proId,
      finalAmount: bid.amount,
      status: JobStatus.inProcess,
      updatedAt: now,
      timeline: <JobTimelineEvent>[
        ...job.timeline,
        JobTimelineEvent(
          type: 'bid_accepted',
          at: now,
          actorId: customerId,
          metadata: <String, dynamic>{'bid_id': bid.id},
        ),
        JobTimelineEvent(type: 'in_process', at: now, actorId: bid.proId),
      ],
    );
    _emitJobs(jobId);

    _addNotification(
      NotificationEvent(
        id: _uuid.v4(),
        userId: bid.proId,
        type: 'job_awarded',
        title: 'Job assigned',
        body: job.title,
        sentAt: now,
        metadata: <String, dynamic>{'job_id': jobId},
      ),
    );
    _addNotification(
      NotificationEvent(
        id: _uuid.v4(),
        userId: job.customerId,
        type: 'bid_accepted',
        title: 'Bid accepted',
        body: 'Your job is now in process.',
        sentAt: now,
        metadata: <String, dynamic>{'job_id': jobId, 'bid_id': bid.id},
      ),
    );
  }

  @override
  Future<void> updateJobStatus({
    required String jobId,
    required JobStatus status,
    required String actorId,
  }) async {
    final job = _jobs[jobId];
    if (job == null) {
      throw StateError('Job not found.');
    }
    final now = DateTime.now();
    final eventMetadata = <String, dynamic>{};

    final shouldApplyCompletionMath =
        status == JobStatus.completed &&
        job.status != JobStatus.completed &&
        job.status != JobStatus.paidClosed;
    if (shouldApplyCompletionMath) {
      final proId = job.assignedProId;
      if (proId == null) {
        throw StateError('Cannot complete a job without an assigned pro.');
      }
      final customerApprovedCompletion =
          actorId == job.customerId && _hasPendingCompletionRequest(job);
      if (actorId != proId && !customerApprovedCompletion) {
        throw StateError(
          'Only the assigned pro or the job owner after completion request can mark a job completed.',
        );
      }
      final completedAmount = job.finalAmount ?? job.fixedPrice;
      final dueIncrease = completedAmount * ProBalanceRules.commissionRate;
      final pro = _users[proId];
      if (pro != null) {
        final previousDue = pro.dueToApp;
        final updatedPro = pro.copyWith(
          totalEarnings: pro.totalEarnings + completedAmount,
          dueToApp: previousDue + dueIncrease,
          updatedAt: now,
        );
        _users[updatedPro.id] = updatedPro;
        _syncCurrentUserIfNeeded(updatedPro.id);
        _emitUsers();
        _sendDueThresholdNotifications(
          pro: updatedPro,
          previousDue: previousDue,
          currentDue: updatedPro.dueToApp,
        );
      }
      eventMetadata['completed_amount'] = completedAmount;
      eventMetadata['due_added'] = dueIncrease;
      eventMetadata['due_rate'] = ProBalanceRules.commissionRate;
    }
    _jobs[jobId] = job.copyWith(
      status: status,
      updatedAt: now,
      timeline: <JobTimelineEvent>[
        ...job.timeline,
        JobTimelineEvent(
          type: status.value,
          at: now,
          actorId: actorId,
          metadata: eventMetadata,
        ),
      ],
    );
    _emitJobs(jobId);
    if (job.customerId != actorId &&
        (status == JobStatus.inProcess ||
            status == JobStatus.completed ||
            status == JobStatus.paidClosed)) {
      final title = switch (status) {
        JobStatus.inProcess => 'Job in progress',
        JobStatus.completed => 'Job marked completed',
        JobStatus.paidClosed => 'Job closed',
        _ => 'Job updated',
      };
      _addNotification(
        NotificationEvent(
          id: _uuid.v4(),
          userId: job.customerId,
          type: 'job_status_update',
          title: title,
          body: job.title,
          sentAt: now,
          metadata: <String, dynamic>{'job_id': jobId, 'status': status.value},
        ),
      );
    }
    if (job.assignedProId != null &&
        job.assignedProId != actorId &&
        (status == JobStatus.completed || status == JobStatus.paidClosed)) {
      _addNotification(
        NotificationEvent(
          id: _uuid.v4(),
          userId: job.assignedProId!,
          type: status == JobStatus.completed
              ? 'job_completion_confirmed'
              : 'payment_received',
          title: status == JobStatus.completed
              ? 'Job completed confirmed'
              : 'Payment recorded',
          body: job.title,
          sentAt: now,
          metadata: <String, dynamic>{'job_id': jobId, 'status': status.value},
        ),
      );
    }
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: actorId,
        action: 'job_status_updated',
        entityType: 'job',
        entityId: jobId,
        createdAt: now,
        metadata: <String, dynamic>{'status': status.value},
      ),
    );
  }

  @override
  Future<void> requestJobCompletion({
    required String jobId,
    required String proId,
  }) async {
    final job = _jobs[jobId];
    if (job == null) {
      throw StateError('Job not found.');
    }
    if (job.assignedProId != proId) {
      throw StateError('Only the assigned pro can request completion.');
    }
    if (job.status != JobStatus.inProcess) {
      throw StateError(
        'Completion can only be requested while work is in process.',
      );
    }
    if (_hasPendingCompletionRequest(job)) {
      return;
    }

    final now = DateTime.now();
    final updatedJob = job.copyWith(
      updatedAt: now,
      timeline: <JobTimelineEvent>[
        ...job.timeline,
        JobTimelineEvent(type: 'completion_requested', at: now, actorId: proId),
      ],
    );
    _jobs[jobId] = updatedJob;
    _emitJobs(jobId);

    _addNotification(
      NotificationEvent(
        id: _uuid.v4(),
        userId: job.customerId,
        type: 'completion_requested',
        title: 'Worker marked job as done',
        body: 'Please confirm whether the job is completed.',
        sentAt: now,
        metadata: <String, dynamic>{'job_id': jobId},
      ),
    );

    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: proId,
        action: 'job_completion_requested',
        entityType: 'job',
        entityId: jobId,
        createdAt: now,
      ),
    );
  }

  @override
  Future<void> respondToJobCompletion({
    required String jobId,
    required String customerId,
    required bool approved,
    double? rating,
  }) async {
    final job = _jobs[jobId];
    if (job == null) {
      throw StateError('Job not found.');
    }
    if (job.customerId != customerId) {
      throw StateError('Only the job owner can respond to completion request.');
    }
    if (job.status != JobStatus.inProcess) {
      throw StateError(
        'Completion response is only valid while job is in process.',
      );
    }
    if (!_hasPendingCompletionRequest(job)) {
      throw StateError('No pending completion request found.');
    }

    if (approved) {
      await updateJobStatus(
        jobId: jobId,
        status: JobStatus.completed,
        actorId: customerId,
      );
      final proId = job.assignedProId;
      if (proId != null && rating != null) {
        final pro = _users[proId];
        if (pro != null) {
          final bounded = rating.clamp(1, 5).toDouble();
          final newTotalReviews = pro.totalReviews + 1;
          final newRating =
              ((pro.rating * pro.totalReviews) + bounded) / newTotalReviews;
          final updatedPro = pro.copyWith(
            rating: newRating,
            totalReviews: newTotalReviews,
            updatedAt: DateTime.now(),
          );
          _users[proId] = updatedPro;
          _syncCurrentUserIfNeeded(proId);
          _emitUsers();
          _addNotification(
            NotificationEvent(
              id: _uuid.v4(),
              userId: proId,
              type: 'job_rated',
              title: 'You received a new rating',
              body:
                  'Customer rated your completed job ${bounded.toStringAsFixed(1)} stars.',
              sentAt: DateTime.now(),
              metadata: <String, dynamic>{'job_id': jobId, 'rating': bounded},
            ),
          );
          await addAuditEvent(
            AuditEvent(
              id: _uuid.v4(),
              actorId: customerId,
              action: 'job_completion_rated',
              entityType: 'job',
              entityId: jobId,
              createdAt: DateTime.now(),
              metadata: <String, dynamic>{'rating': bounded},
            ),
          );
        }
      }
      return;
    }

    final now = DateTime.now();
    final updatedJob = job.copyWith(
      updatedAt: now,
      timeline: <JobTimelineEvent>[
        ...job.timeline,
        JobTimelineEvent(
          type: 'completion_rejected',
          at: now,
          actorId: customerId,
        ),
      ],
    );
    _jobs[jobId] = updatedJob;
    _emitJobs(jobId);
    if (job.assignedProId != null) {
      _addNotification(
        NotificationEvent(
          id: _uuid.v4(),
          userId: job.assignedProId!,
          type: 'completion_rejected',
          title: 'Completion was not approved',
          body: 'Customer marked the job as not completed yet.',
          sentAt: now,
          metadata: <String, dynamic>{'job_id': jobId},
        ),
      );
    }
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: customerId,
        action: 'job_completion_rejected',
        entityType: 'job',
        entityId: jobId,
        createdAt: now,
      ),
    );
  }

  @override
  Future<void> startWork({
    required String jobId,
    required String actorId,
  }) async {
    final job = _jobs[jobId];
    if (job == null) {
      throw StateError('Job not found.');
    }
    if (job.assignedProId != actorId) {
      throw StateError('Only the assigned pro can start work.');
    }
    if (job.status != JobStatus.inProcess) {
      throw StateError('Work can only start after the job is in process.');
    }
    final alreadyStarted = job.timeline.any(
      (event) => event.type == 'work_started',
    );
    if (alreadyStarted) {
      return;
    }
    final now = DateTime.now();
    final updatedJob = job.copyWith(
      updatedAt: now,
      timeline: <JobTimelineEvent>[
        ...job.timeline,
        JobTimelineEvent(type: 'work_started', at: now, actorId: actorId),
      ],
    );
    _jobs[jobId] = updatedJob;
    _emitJobs(jobId);
    _addNotification(
      NotificationEvent(
        id: _uuid.v4(),
        userId: actorId,
        type: 'work_started',
        title: 'Work started',
        body: job.title,
        sentAt: now,
        metadata: <String, dynamic>{'job_id': jobId},
      ),
    );
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: actorId,
        action: 'work_started',
        entityType: 'job',
        entityId: jobId,
        createdAt: now,
      ),
    );
  }

  @override
  Future<void> cancelJob({
    required String jobId,
    required String actorId,
    required String reason,
  }) async {
    final job = _jobs[jobId];
    if (job == null) {
      throw StateError('Job not found.');
    }
    final actor = _users[actorId];
    final actorIsAdmin = actor?.role == UserRole.admin;
    final canProCancel =
        job.assignedProId == actorId && job.status == JobStatus.inProcess;
    if (!actorIsAdmin && job.customerId != actorId && !canProCancel) {
      throw StateError('Only the job owner can cancel this job.');
    }
    _jobs[jobId] = job.copyWith(
      status: JobStatus.cancelled,
      cancelReason: reason,
      updatedAt: DateTime.now(),
      timeline: <JobTimelineEvent>[
        ...job.timeline,
        JobTimelineEvent(
          type: 'cancelled',
          at: DateTime.now(),
          actorId: actorId,
          metadata: <String, dynamic>{'reason': reason},
        ),
      ],
    );
    _emitJobs(jobId);
  }

  @override
  Future<void> raiseDispute({
    required String jobId,
    required String actorId,
    required String reason,
  }) async {
    final job = _jobs[jobId];
    if (job == null) {
      throw StateError('Job not found.');
    }
    final canRaiseDispute =
        job.assignedProId != null &&
        job.status.index >= JobStatus.inProcess.index;
    if (!canRaiseDispute) {
      throw StateError('Dispute can only be raised after a pro is assigned.');
    }
    _jobs[jobId] = job.copyWith(
      status: JobStatus.disputed,
      disputeReason: reason,
      updatedAt: DateTime.now(),
      timeline: <JobTimelineEvent>[
        ...job.timeline,
        JobTimelineEvent(
          type: 'disputed',
          at: DateTime.now(),
          actorId: actorId,
          metadata: <String, dynamic>{'reason': reason},
        ),
      ],
    );
    _emitJobs(jobId);
  }

  @override
  PaymentCalculation calculatePayment(double amount) =>
      _paymentCalculator.calculate(amount);

  @override
  PaymentCalculation calculatePaymentForCategory({
    required double amount,
    required JobCategory category,
  }) {
    final categoryCalculator = PaymentCalculator(
      commissionRateForCategory(category),
    );
    return categoryCalculator.calculate(amount);
  }

  @override
  Future<PaymentRecord> recordPayment(PaymentRequest request) async {
    final job = _jobs[request.jobId];
    if (job == null || job.status != JobStatus.completed) {
      throw StateError('Payment allowed after completed state only.');
    }
    final calc = calculatePaymentForCategory(
      amount: request.amount,
      category: job.category,
    );
    final payment = PaymentRecord(
      id: _uuid.v4(),
      jobId: request.jobId,
      customerId: request.customerId,
      proId: request.proId,
      method: request.method,
      state: PaymentState.completed,
      grossAmount: calc.gross,
      platformFee: calc.fee,
      netProAmount: calc.net,
      recordedAt: DateTime.now(),
      externalReference: request.externalReference,
    );
    _payments[payment.id] = payment;
    _paymentsController.add(_payments.values.toList(growable: false));
    _jobs[request.jobId] = job.copyWith(
      status: JobStatus.paidClosed,
      finalAmount: request.amount,
      updatedAt: DateTime.now(),
      timeline: <JobTimelineEvent>[
        ...job.timeline,
        JobTimelineEvent(
          type: 'paid_closed',
          at: DateTime.now(),
          actorId: request.customerId,
          metadata: <String, dynamic>{
            'method': request.method.value,
            'platform_fee': calc.fee,
            'net_pro_amount': calc.net,
            'commission_rate': commissionRateForCategory(job.category),
            'category': job.category.value,
            'payout_mode': request.method == PaymentMethod.cash
                ? 'direct_cash'
                : 'instant_account_transfer',
          },
        ),
      ],
    );
    _emitJobs(request.jobId);
    _addNotification(
      NotificationEvent(
        id: _uuid.v4(),
        userId: request.proId,
        type: 'payment_received',
        title: 'Payment recorded',
        body: job.title,
        sentAt: DateTime.now(),
        metadata: <String, dynamic>{
          'job_id': request.jobId,
          'payment_id': payment.id,
        },
      ),
    );
    _addNotification(
      NotificationEvent(
        id: _uuid.v4(),
        userId: request.customerId,
        type: 'job_status_update',
        title: 'Job closed',
        body: job.title,
        sentAt: DateTime.now(),
        metadata: <String, dynamic>{
          'job_id': request.jobId,
          'status': JobStatus.paidClosed.value,
        },
      ),
    );

    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: request.customerId,
        action: 'payment_recorded',
        entityType: 'payment',
        entityId: payment.id,
        createdAt: DateTime.now(),
        metadata: payment.toJson(),
      ),
    );
    return payment;
  }

  @override
  Future<void> settleProDue({
    required String proId,
    required PaymentMethod method,
    String? externalReference,
  }) async {
    final pro = _users[proId];
    if (pro == null || pro.role != UserRole.pro) {
      throw StateError('Professional account not found.');
    }
    if (pro.dueToApp <= 0) {
      return;
    }

    final now = DateTime.now();
    final paidAmount = pro.dueToApp;
    _users[proId] = pro.copyWith(dueToApp: 0, updatedAt: now);
    _syncCurrentUserIfNeeded(proId);
    _emitUsers();

    _addNotification(
      NotificationEvent(
        id: _uuid.v4(),
        userId: proId,
        type: 'due_cleared',
        title: 'Due paid successfully',
        body:
            'PKR ${paidAmount.toStringAsFixed(0)} settled via ${method.displayName}.',
        sentAt: now,
        metadata: <String, dynamic>{
          'method': method.value,
          'amount': paidAmount,
          if (externalReference case final value?) 'external_reference': value,
        },
      ),
    );

    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: proId,
        action: 'pro_due_settled',
        entityType: 'pro_balance',
        entityId: proId,
        createdAt: now,
        metadata: <String, dynamic>{
          'amount': paidAmount,
          'method': method.value,
          if (externalReference case final value?) 'external_reference': value,
        },
      ),
    );
  }

  @override
  Stream<List<PaymentRecord>> watchPaymentsForUser(String userId) async* {
    List<PaymentRecord> filter(List<PaymentRecord> values) {
      final list = values
          .where((p) => p.customerId == userId)
          .toList(growable: false);
      list.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      return list;
    }

    yield filter(_payments.values.toList(growable: false));
    yield* _paymentsController.stream.map(filter);
  }

  @override
  Stream<List<PaymentRecord>> watchPaymentsForPro(String proId) async* {
    List<PaymentRecord> filter(List<PaymentRecord> values) {
      final list = values
          .where((p) => p.proId == proId)
          .toList(growable: false);
      list.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      return list;
    }

    yield filter(_payments.values.toList(growable: false));
    yield* _paymentsController.stream.map(filter);
  }

  @override
  Stream<List<PaymentRecord>> watchAllPayments() async* {
    List<PaymentRecord> sort(List<PaymentRecord> payments) {
      final sorted = List<PaymentRecord>.from(payments);
      sorted.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      return sorted;
    }

    yield sort(_payments.values.toList(growable: false));
    yield* _paymentsController.stream.map(sort);
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String jobId) {
    final controller = _messagesStreams.putIfAbsent(
      jobId,
      () => StreamController<List<ChatMessage>>.broadcast(
        onListen: () {
          final initial = <ChatMessage>[
            ...(_messagesByJob[jobId] ?? <ChatMessage>[]),
          ]..sort((a, b) => a.sentAt.compareTo(b.sentAt));
          _messagesStreams[jobId]?.add(initial);
        },
      ),
    );
    return controller.stream;
  }

  @override
  Future<ChatMessage> sendMessage({
    required String jobId,
    required String senderId,
    required String receiverId,
    required String text,
    String? replyToMessageId,
    String? replyToSenderId,
    String? replyToSenderName,
    String? replyToText,
  }) async {
    final job = _jobs[jobId];
    if (job == null) {
      throw StateError('Job not found.');
    }
    final assignedProId = job.assignedProId;
    if (assignedProId == null || job.status.index < JobStatus.inProcess.index) {
      throw StateError(
        'Messaging unlocks only after bid approval and assignment.',
      );
    }
    final participants = <String>{job.customerId, assignedProId};
    if (!participants.contains(senderId) ||
        !participants.contains(receiverId) ||
        senderId == receiverId) {
      throw StateError('Only assigned customer and pro can chat on this job.');
    }

    final now = DateTime.now();
    final message = ChatMessage(
      id: _uuid.v4(),
      jobId: jobId,
      senderId: senderId,
      receiverId: receiverId,
      text: text.trim(),
      sentAt: now,
      replyToMessageId: replyToMessageId,
      replyToSenderId: replyToSenderId,
      replyToSenderName: replyToSenderName,
      replyToText: replyToText,
    );
    final all = <ChatMessage>[
      ...(_messagesByJob[jobId] ?? <ChatMessage>[]),
      message,
    ]..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    _messagesByJob[jobId] = all;
    _messagesStreams[jobId]?.add(all);
    _jobs[jobId] = job.copyWith(updatedAt: now);
    _emitJobs(jobId);
    _addNotification(
      NotificationEvent(
        id: _uuid.v4(),
        userId: receiverId,
        type: 'message',
        title: 'New message',
        body: message.text,
        sentAt: now,
        metadata: <String, dynamic>{
          'job_id': jobId,
          'sender_id': senderId,
          'receiver_id': receiverId,
          'message_id': message.id,
          'navigate_route': '/chat/$jobId/$senderId',
        },
      ),
    );
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: senderId,
        action: 'message_sent',
        entityType: 'chat_message',
        entityId: message.id,
        createdAt: now,
      ),
    );
    return message;
  }

  @override
  Future<void> setMessageReaction({
    required String messageId,
    required String userId,
    String? emoji,
  }) async {
    for (final entry in _messagesByJob.entries) {
      final index = entry.value.indexWhere(
        (message) => message.id == messageId,
      );
      if (index < 0) {
        continue;
      }
      final message = entry.value[index];
      if (message.senderId != userId && message.receiverId != userId) {
        throw StateError('Only chat participants can react to this message.');
      }
      final updatedReactions = <String, String>{...message.reactions};
      final normalizedEmoji = emoji?.trim();
      if (normalizedEmoji == null || normalizedEmoji.isEmpty) {
        updatedReactions.remove(userId);
      } else {
        updatedReactions[userId] = normalizedEmoji;
      }
      final updatedMessage = message.copyWith(reactions: updatedReactions);
      final updatedList = <ChatMessage>[...entry.value]
        ..[index] = updatedMessage;
      _messagesByJob[entry.key] = updatedList;
      _messagesStreams[entry.key]?.add(updatedList);
      _persistSoon();
      return;
    }
    throw StateError('Message not found.');
  }

  @override
  Future<void> markMessagesSeen({
    required String jobId,
    required String viewerId,
    required String peerId,
  }) async {
    final messages = _messagesByJob[jobId];
    if (messages == null || messages.isEmpty) {
      return;
    }
    var changed = false;
    final now = DateTime.now();
    final updated = messages
        .map((message) {
          final shouldMarkSeen =
              message.receiverId == viewerId &&
              message.senderId == peerId &&
              message.seenAt == null &&
              !message.isDeletedForEveryone;
          if (!shouldMarkSeen) {
            return message;
          }
          changed = true;
          return message.copyWith(seenAt: now);
        })
        .toList(growable: false);
    if (!changed) {
      return;
    }
    _messagesByJob[jobId] = updated;
    _messagesStreams[jobId]?.add(updated);
    _persistSoon();
  }

  @override
  Future<void> deleteMessageForMe({
    required String messageId,
    required String userId,
  }) async {
    for (final entry in _messagesByJob.entries) {
      final index = entry.value.indexWhere(
        (message) => message.id == messageId,
      );
      if (index < 0) {
        continue;
      }
      final message = entry.value[index];
      if (message.senderId != userId && message.receiverId != userId) {
        throw StateError('Only chat participants can delete this message.');
      }
      final now = DateTime.now();
      final updatedMessage = ChatMessage(
        id: message.id,
        jobId: message.jobId,
        senderId: message.senderId,
        receiverId: message.receiverId,
        text: message.text,
        sentAt: message.sentAt,
        seenAt: message.seenAt,
        deletedForEveryoneAt: message.deletedForEveryoneAt,
        deletedForEveryoneBy: message.deletedForEveryoneBy,
        deletedBySenderAt: userId == message.senderId
            ? now
            : message.deletedBySenderAt,
        deletedByReceiverAt: userId == message.receiverId
            ? now
            : message.deletedByReceiverAt,
        replyToMessageId: message.replyToMessageId,
        replyToSenderId: message.replyToSenderId,
        replyToSenderName: message.replyToSenderName,
        replyToText: message.replyToText,
        reactions: message.reactions,
      );
      final updatedList = <ChatMessage>[...entry.value]
        ..[index] = updatedMessage;
      _messagesByJob[entry.key] = updatedList;
      _messagesStreams[entry.key]?.add(updatedList);
      _persistSoon();
      return;
    }
    throw StateError('Message not found.');
  }

  @override
  Future<void> deleteMessageForEveryone({
    required String messageId,
    required String userId,
  }) async {
    for (final entry in _messagesByJob.entries) {
      final index = entry.value.indexWhere(
        (message) => message.id == messageId,
      );
      if (index < 0) {
        continue;
      }
      final message = entry.value[index];
      if (message.senderId != userId) {
        throw StateError('Only sender can delete message for everyone.');
      }
      final now = DateTime.now();
      final updatedMessage = ChatMessage(
        id: message.id,
        jobId: message.jobId,
        senderId: message.senderId,
        receiverId: message.receiverId,
        text: message.text,
        sentAt: message.sentAt,
        seenAt: message.seenAt,
        deletedForEveryoneAt: now,
        deletedForEveryoneBy: userId,
        deletedBySenderAt: message.deletedBySenderAt,
        deletedByReceiverAt: message.deletedByReceiverAt,
        replyToMessageId: message.replyToMessageId,
        replyToSenderId: message.replyToSenderId,
        replyToSenderName: message.replyToSenderName,
        replyToText: message.replyToText,
        reactions: message.reactions,
      );
      final updatedList = <ChatMessage>[...entry.value]
        ..[index] = updatedMessage;
      _messagesByJob[entry.key] = updatedList;
      _messagesStreams[entry.key]?.add(updatedList);
      _persistSoon();
      return;
    }
    throw StateError('Message not found.');
  }

  @override
  Stream<List<NotificationEvent>> watchNotifications(String userId) async* {
    List<NotificationEvent> filter(List<NotificationEvent> source) {
      final list = source
          .where((event) => event.userId == userId)
          .toList(growable: false);
      list.sort((a, b) => b.sentAt.compareTo(a.sentAt));
      return list;
    }

    yield filter(_notifications.values.toList(growable: false));
    yield* _notificationsController.stream.map(filter);
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {
    final current = _notifications[notificationId];
    if (current == null) {
      return;
    }
    _notifications[notificationId] = NotificationEvent(
      id: current.id,
      userId: current.userId,
      type: current.type,
      title: current.title,
      body: current.body,
      sentAt: current.sentAt,
      metadata: current.metadata,
      read: true,
    );
    _notificationsController.add(_notifications.values.toList(growable: false));
    _persistSoon();
  }

  @override
  Stream<List<AuditEvent>> watchAuditEvents({
    String? entityType,
    String? entityId,
  }) async* {
    List<AuditEvent> filter(List<AuditEvent> events) {
      final filtered = events
          .where((event) {
            if (entityType != null && event.entityType != entityType) {
              return false;
            }
            if (entityId != null && event.entityId != entityId) {
              return false;
            }
            return true;
          })
          .toList(growable: false);
      filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return filtered;
    }

    yield filter(_auditEvents.values.toList(growable: false));
    yield* _auditController.stream.map(filter);
  }

  @override
  Future<void> addAuditEvent(AuditEvent event) async {
    _auditEvents[event.id] = event;
    _auditController.add(_auditEvents.values.toList(growable: false));
    _persistSoon();
  }

  @override
  Stream<List<UserReport>> watchUserReports() async* {
    List<UserReport> sortReports(List<UserReport> reports) {
      final sorted = List<UserReport>.from(reports);
      sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return sorted;
    }

    yield sortReports(_reports.values.toList(growable: false));
    yield* _reportsController.stream.map(sortReports);
  }

  @override
  Future<void> reportUser({
    required String reporterId,
    required String targetUserId,
    required String reasonCode,
    String? details,
  }) async {
    final now = DateTime.now();
    final report = UserReport(
      id: _uuid.v4(),
      reporterId: reporterId,
      targetUserId: targetUserId,
      reasonCode: reasonCode,
      details: details,
      createdAt: now,
    );
    _reports[report.id] = report;
    _reportsController.add(_reports.values.toList(growable: false));

    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: reporterId,
        action: 'user_reported',
        entityType: 'user',
        entityId: targetUserId,
        createdAt: now,
        metadata: <String, dynamic>{
          'reason_code': reasonCode,
          if (details != null && details.trim().isNotEmpty)
            'details': details.trim(),
        },
      ),
    );
  }

  @override
  Future<void> blockUser({
    required String actorId,
    required String targetUserId,
    required String reason,
  }) {
    return setUserBlockStatus(
      actorId: actorId,
      targetUserId: targetUserId,
      blocked: true,
      reason: reason,
    );
  }

  @override
  Future<void> setUserBlockStatus({
    required String actorId,
    required String targetUserId,
    required bool blocked,
    required String reason,
  }) async {
    _requireAdminPermission(
      actorId,
      AdminPermission.manageUsers,
      anyOf: <AdminPermission>[AdminPermission.manageReports],
    );
    final user = _users[targetUserId];
    if (user == null) {
      throw StateError('User not found.');
    }
    _users[targetUserId] = user.copyWith(
      blocked: blocked,
      updatedAt: DateTime.now(),
    );
    _emitUsers();
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: actorId,
        action: blocked ? 'user_blocked' : 'user_unblocked',
        entityType: 'user',
        entityId: targetUserId,
        createdAt: DateTime.now(),
        metadata: <String, dynamic>{'reason': reason},
      ),
    );
  }

  @override
  Future<void> setAdminAccess({
    required String actorId,
    required String targetUserId,
    required AdminRank rank,
    required List<AdminPermission> permissions,
  }) async {
    _requireAdminPermission(actorId, AdminPermission.manageAdminAccess);
    final target = _users[targetUserId];
    if (target == null || target.role != UserRole.admin) {
      throw StateError('Target admin user not found.');
    }
    final assignedPermissions = permissions.isEmpty
        ? defaultAdminPermissionsForRank(rank)
        : permissions.toSet().toList(growable: false);
    _users[targetUserId] = target.copyWith(
      adminRank: rank,
      adminPermissions: assignedPermissions,
      updatedAt: DateTime.now(),
    );
    _emitUsers();
    _syncCurrentUserIfNeeded(targetUserId);
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: actorId,
        action: 'admin_access_updated',
        entityType: 'user',
        entityId: targetUserId,
        createdAt: DateTime.now(),
        metadata: <String, dynamic>{
          'rank': rank.value,
          'permissions': assignedPermissions
              .map((permission) => permission.value)
              .toList(growable: false),
        },
      ),
    );
  }

  @override
  Future<ProEarningsSummary> fetchEarningsSummary(String proId) async {
    final now = DateTime.now();
    final pro = _users[proId];
    if (pro == null || pro.role != UserRole.pro) {
      throw StateError('Professional account not found.');
    }
    final completedJobs = _jobs.values
        .where(
          (job) =>
              job.assignedProId == proId &&
              (job.status == JobStatus.completed ||
                  job.status == JobStatus.paidClosed),
        )
        .toList(growable: false);
    double amountFor(Job job) => job.finalAmount ?? job.fixedPrice;
    DateTime completionTime(Job job) {
      for (final event in job.timeline.reversed) {
        if (event.type == JobStatus.completed.value) {
          return event.at;
        }
      }
      return job.updatedAt;
    }

    double sum(Iterable<double> values) =>
        values.fold<double>(0, (total, value) => total + value);
    final today = sum(
      completedJobs
          .where((job) {
            final at = completionTime(job);
            return at.year == now.year &&
                at.month == now.month &&
                at.day == now.day;
          })
          .map(amountFor),
    );
    final month = sum(
      completedJobs
          .where((job) {
            final at = completionTime(job);
            return at.year == now.year && at.month == now.month;
          })
          .map(amountFor),
    );
    final lifetime = pro.totalEarnings;

    final proPayments = _payments.values.where(
      (p) => p.proId == proId && p.state == PaymentState.completed,
    );
    final online = sum(
      proPayments
          .where((p) => p.method != PaymentMethod.cash)
          .map((p) => p.netProAmount),
    );
    final cash = sum(
      proPayments
          .where((p) => p.method == PaymentMethod.cash)
          .map((p) => p.netProAmount),
    );
    final fees = sum(proPayments.map((p) => p.platformFee));

    return ProEarningsSummary(
      today: today,
      month: month,
      lifetime: lifetime,
      online: online,
      cash: cash,
      platformFees: fees,
      totalJobs: completedJobs.length,
      averageRating: pro.rating,
      totalReviews: pro.totalReviews,
      totalEarnings: pro.totalEarnings,
      dueToApp: pro.dueToApp,
    );
  }

  @override
  Future<AdminMetrics> fetchAdminMetrics() async {
    final now = DateTime.now();
    final since24h = now.subtract(const Duration(hours: 24));
    final totalCustomers = _users.values
        .where((u) => u.role == UserRole.customer)
        .length;
    final totalPros = _users.values.where((u) => u.role == UserRole.pro).length;
    final totalAdmins = _users.values
        .where((u) => u.role == UserRole.admin)
        .length;
    final verifiedPros = _users.values
        .where((u) => u.role == UserRole.pro && u.cnicVerified)
        .length;
    final totalJobs = _jobs.length;
    final activeJobs = _jobs.values
        .where((job) => job.status == JobStatus.inProcess)
        .length;
    final completedJobs = _jobs.values
        .where(
          (job) =>
              job.status == JobStatus.completed ||
              job.status == JobStatus.paidClosed,
        )
        .length;
    final cancelledJobs = _jobs.values
        .where((job) => job.status == JobStatus.cancelled)
        .length;
    final activeDisputes = _jobs.values
        .where((j) => j.status == JobStatus.disputed)
        .length;
    final reviewedReportIds = _auditEvents.values
        .where(
          (event) =>
              event.entityType == 'report' && event.action == 'report_reviewed',
        )
        .map((event) => event.entityId)
        .toSet();
    final totalReports = _reports.length;
    final openReports = _reports.values
        .where((report) => !reviewedReportIds.contains(report.id))
        .length;
    final messages24h = _messagesByJob.values
        .expand((messages) => messages)
        .where((message) => message.sentAt.isAfter(since24h))
        .length;
    final audits24h = _auditEvents.values
        .where((event) => event.createdAt.isAfter(since24h))
        .length;
    double sum(Iterable<double> values) =>
        values.fold<double>(0, (total, value) => total + value);
    final onlineVolume = sum(
      _payments.values
          .where((p) => p.method != PaymentMethod.cash)
          .map((p) => p.grossAmount),
    );
    final cashVolume = sum(
      _payments.values
          .where((p) => p.method == PaymentMethod.cash)
          .map((p) => p.grossAmount),
    );
    final platformRevenue = sum(_payments.values.map((p) => p.platformFee));
    return AdminMetrics(
      totalCustomers: totalCustomers,
      totalPros: totalPros,
      totalAdmins: totalAdmins,
      verifiedPros: verifiedPros,
      totalJobs: totalJobs,
      activeJobs: activeJobs,
      completedJobs: completedJobs,
      cancelledJobs: cancelledJobs,
      activeDisputes: activeDisputes,
      totalReports: totalReports,
      openReports: openReports,
      messages24h: messages24h,
      audits24h: audits24h,
      onlineVolume: onlineVolume,
      cashVolume: cashVolume,
      platformRevenue: platformRevenue,
    );
  }

  @override
  double get commissionRate => _commissionRate;

  @override
  Map<JobCategory, double> get commissionRatesByCategory =>
      Map<JobCategory, double>.unmodifiable(_categoryCommissionRates);

  @override
  double commissionRateForCategory(JobCategory category) {
    return _categoryCommissionRates[category] ?? _commissionRate;
  }

  @override
  Future<void> setCommissionRate(double rate, {required String actorId}) async {
    _requireAdminPermission(actorId, AdminPermission.manageCommissions);
    if (rate < 0 || rate > 1) {
      throw StateError('Rate should be between 0 and 1.');
    }
    _commissionRate = rate;
    for (final category in JobCategory.values) {
      _categoryCommissionRates[category] = rate;
    }
    _paymentCalculator = PaymentCalculator(rate);
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: actorId,
        action: 'commission_updated',
        entityType: 'settings',
        entityId: 'commission_rate',
        createdAt: DateTime.now(),
        metadata: <String, dynamic>{'rate': rate},
      ),
    );
  }

  @override
  Future<void> setCategoryCommissionRate({
    required JobCategory category,
    required double rate,
    required String actorId,
  }) async {
    _requireAdminPermission(actorId, AdminPermission.manageCommissions);
    if (rate < 0 || rate > 1) {
      throw StateError('Rate should be between 0 and 1.');
    }
    _categoryCommissionRates[category] = rate;
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: actorId,
        action: 'commission_category_updated',
        entityType: 'settings',
        entityId: category.value,
        createdAt: DateTime.now(),
        metadata: <String, dynamic>{'category': category.value, 'rate': rate},
      ),
    );
  }

  void _emitJobs(String jobId) {
    _jobsController.add(_jobs.values.toList(growable: false));
    _jobById[jobId]?.add(_jobs[jobId]);
    _persistSoon();
  }

  void _emitUsers() {
    _usersController.add(_users.values.toList(growable: false));
    _persistSoon();
  }

  void _syncCurrentUserIfNeeded(String userId) {
    if (_currentUser?.id == userId) {
      _currentUser = _users[userId];
      _currentUserController.add(_currentUser);
    }
  }

  void _requireAdminPermission(
    String actorId,
    AdminPermission requiredPermission, {
    List<AdminPermission> anyOf = const <AdminPermission>[],
  }) {
    final actor = _users[actorId];
    if (actor == null || actor.role != UserRole.admin) {
      throw StateError('Admin access required.');
    }
    final hasRequired = actor.hasAdminPermission(requiredPermission);
    final hasAnyAlternate = anyOf.any(actor.hasAdminPermission);
    if (!hasRequired && !hasAnyAlternate) {
      throw StateError(
        'Missing admin permission: ${requiredPermission.label}.',
      );
    }
  }

  void _sendDueThresholdNotifications({
    required AppUser pro,
    required double previousDue,
    required double currentDue,
  }) {
    final crossedMild =
        previousDue < ProBalanceRules.mildWarning &&
        currentDue >= ProBalanceRules.mildWarning;
    final crossedStrong =
        previousDue < ProBalanceRules.strongWarning &&
        currentDue >= ProBalanceRules.strongWarning;
    final crossedLock =
        previousDue < ProBalanceRules.dueLimit &&
        currentDue >= ProBalanceRules.dueLimit;

    final now = DateTime.now();
    if (crossedMild) {
      _addNotification(
        NotificationEvent(
          id: _uuid.v4(),
          userId: pro.id,
          type: 'due_warning_mild',
          title: '75% limit reached',
          body:
              "You're 75% of the way to your limit. Pay soon to keep working!",
          sentAt: now,
          metadata: <String, dynamic>{'due_to_app': currentDue},
        ),
      );
    }
    if (crossedStrong) {
      _addNotification(
        NotificationEvent(
          id: _uuid.v4(),
          userId: pro.id,
          type: 'due_warning_strong',
          title: 'Urgent due warning',
          body:
              'Urgent: Pay your dues now or your account will be locked soon.',
          sentAt: now,
          metadata: <String, dynamic>{'due_to_app': currentDue},
        ),
      );
    }
    if (crossedLock) {
      _addNotification(
        NotificationEvent(
          id: _uuid.v4(),
          userId: pro.id,
          type: 'due_locked',
          title: 'Account locked',
          body:
              'Account Locked. Please clear your 2,000 PKR due to continue bidding on jobs.',
          sentAt: now,
          metadata: <String, dynamic>{'due_to_app': currentDue},
        ),
      );
    }
  }

  bool _hasPendingCompletionRequest(Job job) {
    const resolvedTypes = <String>{
      'completion_rejected',
      'completed',
      'paid_closed',
      'cancelled',
      'disputed',
    };
    for (final event in job.timeline.reversed) {
      if (event.type == 'completion_requested') {
        return true;
      }
      if (resolvedTypes.contains(event.type)) {
        return false;
      }
    }
    return false;
  }

  bool _isProNearbyJob(AppUser pro, Job job, {double radiusKm = 25}) {
    if (pro.savedLocations.isEmpty) {
      // If no saved location exists, fall back to category-only matching.
      return true;
    }
    final latest = pro.savedLocations.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    final meters = Geolocator.distanceBetween(
      latest.latitude,
      latest.longitude,
      job.latitude,
      job.longitude,
    );
    return (meters / 1000) <= radiusKm;
  }

  void _addNotification(NotificationEvent event) {
    _notifications[event.id] = event;
    _notificationsController.add(_notifications.values.toList(growable: false));
    _persistSoon();
  }

  @override
  void dispose() {
    _disposed = true;
    _currentUserController.close();
    _usersController.close();
    _jobsController.close();
    _paymentsController.close();
    _auditController.close();
    _reportsController.close();
    _notificationsController.close();
    for (final stream in _jobById.values) {
      stream.close();
    }
    for (final stream in _bidsByJob.values) {
      stream.close();
    }
    for (final stream in _messagesStreams.values) {
      stream.close();
    }
  }
}
