import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/auth_session_cache.dart';
import '../../core/services/device_context_service.dart';
import '../../core/services/payment_calculator.dart';
import '../../core/services/pro_balance_rules.dart';
import '../../domain/models.dart';
import 'marketplace_repository.dart';

class FirebaseMarketplaceRepository implements MarketplaceRepository {
  FirebaseMarketplaceRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required AuthSessionCache authSessionCache,
    required double initialCommissionRate,
    required List<String> bootstrapAdminEmails,
  }) : _firestore = firestore,
       _auth = auth,
       _authSessionCache = authSessionCache,
       _commissionRate = initialCommissionRate,
       _categoryCommissionRates = <JobCategory, double>{
         for (final category in JobCategory.values)
           category: initialCommissionRate,
       },
       _bootstrapAdminEmails = bootstrapAdminEmails
           .map((value) => value.trim().toLowerCase())
           .where((value) => value.isNotEmpty)
           .toSet(),
       _paymentCalculator = PaymentCalculator(initialCommissionRate) {
    _listenToSettings();
  }

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final AuthSessionCache _authSessionCache;
  final Uuid _uuid = const Uuid();
  final String _sessionId = const Uuid().v4();
  static const Duration _cacheReadTimeout = Duration(milliseconds: 450);
  static const Duration _authRequestTimeout = Duration(seconds: 15);
  static const Duration _signInTimeout = Duration(seconds: 10);
  static final RegExp _controlCharsPattern = RegExp(
    r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]',
  );
  static final RegExp _emailPattern = RegExp(
    r'^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$',
    caseSensitive: false,
  );
  static final RegExp _phonePattern = RegExp(r'^\+?[0-9]{7,15}$');
  final Map<String, AppUser> _pendingAuthProfiles = <String, AppUser>{};
  final Set<String> _bootstrapAdminEmails;

  late PaymentCalculator _paymentCalculator;
  double _commissionRate;
  final Map<JobCategory, double> _categoryCommissionRates;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _commissionRateSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _categoryCommissionSubscription;

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _firestore.collection('profiles');

  CollectionReference<Map<String, dynamic>> get _jobs =>
      _firestore.collection('jobs');

  CollectionReference<Map<String, dynamic>> get _bids =>
      _firestore.collection('bids');

  CollectionReference<Map<String, dynamic>> get _payments =>
      _firestore.collection('payments');

  CollectionReference<Map<String, dynamic>> get _messages =>
      _firestore.collection('chat_messages');

  CollectionReference<Map<String, dynamic>> get _notifications =>
      _firestore.collection('notifications');

  CollectionReference<Map<String, dynamic>> get _audits =>
      _firestore.collection('audit_logs');

  CollectionReference<Map<String, dynamic>> get _reports =>
      _firestore.collection('reports');

  CollectionReference<Map<String, dynamic>> get _settings =>
      _firestore.collection('app_settings');

  CollectionReference<Map<String, dynamic>> get _presence =>
      _firestore.collection('presence');

  CollectionReference<Map<String, dynamic>> get _financialLedger =>
      _firestore.collection('financial_ledger');

  CollectionReference<Map<String, dynamic>> get _financialSummary =>
      _firestore.collection('financial_summary');

  void _listenToSettings() {
    _commissionRateSubscription = _settings
        .doc('commission_rate')
        .snapshots()
        .listen(
          (snapshot) {
            final data = snapshot.data();
            final value = data == null ? null : data['value'];
            if (value is num) {
              _commissionRate = value.toDouble();
              _paymentCalculator = PaymentCalculator(_commissionRate);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Skipping Firebase commission settings stream: $error');
          },
        );

    _categoryCommissionSubscription = _settings
        .doc('commission_rate_by_category')
        .snapshots()
        .listen(
          (snapshot) {
            final data = snapshot.data();
            final value = data == null ? null : data['value'];
            if (value is! Map) {
              return;
            }
            final normalized = _normalizeValue(value);
            if (normalized is! Map<String, dynamic>) {
              return;
            }
            for (final category in JobCategory.values) {
              final rate = normalized[category.value];
              if (rate is num) {
                _categoryCommissionRates[category] = rate.toDouble();
              }
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint(
              'Skipping Firebase category commission settings stream: $error',
            );
          },
        );
  }

  String _requireCurrentUserId() {
    final userId = _auth.currentUser?.uid;
    if (userId == null || userId.isEmpty) {
      throw StateError('Not authenticated.');
    }
    return userId;
  }

  void _assertCurrentUser(String userId) {
    final current = _requireCurrentUserId();
    if (current != userId) {
      throw StateError('Not authenticated.');
    }
  }

  String _normalizeEmail(String value) => value.trim().toLowerCase();

  String _normalizePhone(String value) {
    final compact = value.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    if (!compact.startsWith('+')) {
      return compact.replaceAll('+', '');
    }
    final digits = compact.substring(1).replaceAll('+', '');
    return '+$digits';
  }

  String _sanitizeSingleLine(
    String value, {
    required String field,
    int minLength = 1,
    int maxLength = 160,
  }) {
    final cleaned = value
        .replaceAll(_controlCharsPattern, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.length < minLength) {
      throw StateError('$field is required.');
    }
    if (cleaned.length > maxLength) {
      throw StateError('$field is too long.');
    }
    return cleaned;
  }

  String _sanitizeMultiLine(
    String value, {
    required String field,
    int minLength = 1,
    int maxLength = 2000,
  }) {
    final cleaned = value.replaceAll(_controlCharsPattern, '').trim();
    if (cleaned.length < minLength) {
      throw StateError('$field is required.');
    }
    if (cleaned.length > maxLength) {
      throw StateError('$field is too long.');
    }
    return cleaned;
  }

  String? _sanitizeOptionalSingleLine(
    String? value, {
    required String field,
    int maxLength = 160,
  }) {
    if (value == null) {
      return null;
    }
    final cleaned = value
        .replaceAll(_controlCharsPattern, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) {
      return null;
    }
    if (cleaned.length > maxLength) {
      throw StateError('$field is too long.');
    }
    return cleaned;
  }

  void _assertValidEmail(String email) {
    if (!_emailPattern.hasMatch(email)) {
      throw StateError('Please enter a valid email address.');
    }
  }

  void _assertValidPhone(String phone) {
    if (!_phonePattern.hasMatch(phone)) {
      throw StateError('Please enter a valid phone number.');
    }
  }

  void _assertStrongPassword(String password) {
    final hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
    final hasLowercase = RegExp(r'[a-z]').hasMatch(password);
    final hasDigit = RegExp(r'[0-9]').hasMatch(password);
    final hasSpecial = RegExp(r'[^A-Za-z0-9]').hasMatch(password);
    if (password.length < 10 ||
        !hasUppercase ||
        !hasLowercase ||
        !hasDigit ||
        !hasSpecial) {
      throw StateError(
        'Password must have 10+ chars with upper, lower, number, and symbol.',
      );
    }
  }

  Map<String, dynamic> _profileSecurityUpdateContext({
    required String action,
    required String actorId,
    required String proId,
    String? jobId,
  }) {
    return <String, dynamic>{
      'action': action,
      'actor_id': actorId,
      'pro_id': proId,
      if (jobId != null && jobId.isNotEmpty) 'job_id': jobId,
      'at': DateTime.now().toIso8601String(),
    };
  }

  dynamic _normalizeValue(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }
    if (value is Map) {
      return value.map<String, dynamic>(
        (key, nestedValue) =>
            MapEntry(key.toString(), _normalizeValue(nestedValue)),
      );
    }
    if (value is Iterable) {
      return value
          .map<dynamic>((item) => _normalizeValue(item))
          .toList(growable: false);
    }
    return value;
  }

  Map<String, dynamic> _documentData(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Document not found.');
    }
    final normalized = _normalizeValue(<String, dynamic>{
      ...data,
      'id': doc.id,
    });
    return Map<String, dynamic>.from(normalized as Map<String, dynamic>);
  }

  AppUser _userFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AppUser.fromJson(_documentData(doc));
  }

  Job _jobFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Job.fromJson(_documentData(doc));
  }

  Bid _bidFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Bid.fromJson(_documentData(doc));
  }

  PaymentRecord _paymentFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return PaymentRecord.fromJson(_documentData(doc));
  }

  ChatMessage _messageFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return ChatMessage.fromJson(_documentData(doc));
  }

  NotificationEvent _notificationFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return NotificationEvent.fromJson(_documentData(doc));
  }

  AuditEvent _auditFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AuditEvent.fromJson(_documentData(doc));
  }

  UserReport _reportFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return UserReport.fromJson(_documentData(doc));
  }

  List<T> _safeParseDocs<T>(
    Iterable<DocumentSnapshot<Map<String, dynamic>>> docs,
    T Function(DocumentSnapshot<Map<String, dynamic>> doc) parser,
    String label,
  ) {
    final parsed = <T>[];
    for (final doc in docs) {
      try {
        parsed.add(parser(doc));
      } catch (error) {
        debugPrint('Skipping malformed $label ${doc.id}: $error');
      }
    }
    return parsed;
  }

  Future<AppUser> _loadProfileForAccess(String userId) async {
    final snapshot = await _profiles
        .doc(userId)
        .get(const GetOptions(source: Source.serverAndCache));
    if (!snapshot.exists) {
      throw StateError('User not found.');
    }
    return _userFromDoc(snapshot);
  }

  Future<Job> _loadJob(String jobId) async {
    final snapshot = await _jobs
        .doc(jobId)
        .get(const GetOptions(source: Source.serverAndCache));
    if (!snapshot.exists) {
      throw StateError('Job not found.');
    }
    return _jobFromDoc(snapshot);
  }

  Future<ChatMessage> _loadMessage(String messageId) async {
    final snapshot = await _messages
        .doc(messageId)
        .get(const GetOptions(source: Source.serverAndCache));
    if (!snapshot.exists) {
      throw StateError('Message not found.');
    }
    return _messageFromDoc(snapshot);
  }

  Future<void> _requireAdminPermission(
    String actorId,
    AdminPermission requiredPermission, {
    List<AdminPermission> anyOf = const <AdminPermission>[],
  }) async {
    _assertCurrentUser(actorId);
    final actor = await _loadProfileForAccess(actorId);
    if (actor.role != UserRole.admin) {
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

  String _fallbackFullNameForAuthUser(User firebaseUser) {
    final displayName = firebaseUser.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final email = firebaseUser.email?.trim().toLowerCase();
    if (email != null && email.contains('@')) {
      final localPart = email.split('@').first.trim();
      if (localPart.isNotEmpty) {
        return localPart;
      }
    }

    return 'New User';
  }

  String _normalizeUsernameToken(String value) {
    final compact = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return compact;
  }

  String _buildUsername({
    required String fullName,
    required String email,
    required String userId,
  }) {
    final localPart = email.contains('@') ? email.split('@').first : email;
    final baseSource = fullName.trim().isEmpty ? localPart : fullName;
    final normalized = _normalizeUsernameToken(baseSource);
    final safeBase = normalized.isEmpty ? 'user' : normalized;
    final rawSuffix = userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final suffixSeed = rawSuffix.isEmpty ? '0000' : rawSuffix;
    final suffix = suffixSeed
        .substring(0, suffixSeed.length >= 6 ? 6 : suffixSeed.length)
        .toLowerCase();
    return '${safeBase}_$suffix';
  }

  String _resolvedUsername(AppUser user) {
    final existing = user.username.trim();
    if (existing.isNotEmpty) {
      return existing;
    }
    return _buildUsername(
      fullName: user.fullName,
      email: user.email,
      userId: user.id,
    );
  }

  AppUser _withProfileMetadata(AppUser user, {required bool online}) {
    final now = DateTime.now();
    return user.copyWith(
      username: _resolvedUsername(user),
      isOnline: online,
      lastSeenAt: online ? (user.lastSeenAt ?? now) : now,
      lastActiveAt: now,
      updatedAt: now,
    );
  }

  AppUser _normalizeProfileIdentityIfNeeded(AppUser user) {
    final normalizedUsername = _resolvedUsername(user);
    if (normalizedUsername == user.username) {
      return user;
    }
    return user.copyWith(
      username: normalizedUsername,
      updatedAt: DateTime.now(),
    );
  }

  String _dayKey(DateTime at) {
    final year = at.year.toString().padLeft(4, '0');
    final month = at.month.toString().padLeft(2, '0');
    final day = at.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _monthKey(DateTime at) {
    final year = at.year.toString().padLeft(4, '0');
    final month = at.month.toString().padLeft(2, '0');
    return '$year-$month';
  }

  void _applyFinancialSummaryDelta({
    required WriteBatch batch,
    required DateTime at,
    required double grossRevenueDelta,
    required double platformRevenueDelta,
    required double proPayoutDelta,
    required double dueSettledDelta,
    required double estimatedProfitDelta,
    int paymentsDelta = 0,
    int settlementsDelta = 0,
  }) {
    final dayKey = _dayKey(at);
    final monthKey = _monthKey(at);
    final updatedAt = at.toIso8601String();

    void applyToDoc(
      String docId, {
      required String scope,
      required String scopeKey,
      String? explicitDayKey,
      String? explicitMonthKey,
    }) {
      batch.set(_financialSummary.doc(docId), <String, dynamic>{
        'scope': scope,
        'scope_key': scopeKey,
        ...?switch (explicitDayKey) {
          final dayKey? => <String, dynamic>{'day_key': dayKey},
          null => null,
        },
        ...?switch (explicitMonthKey) {
          final monthKey? => <String, dynamic>{'month_key': monthKey},
          null => null,
        },
        'total_gross_revenue': FieldValue.increment(grossRevenueDelta),
        'total_platform_revenue': FieldValue.increment(platformRevenueDelta),
        'total_pro_payout': FieldValue.increment(proPayoutDelta),
        'total_due_settled': FieldValue.increment(dueSettledDelta),
        'total_estimated_profit': FieldValue.increment(estimatedProfitDelta),
        'payments_count': FieldValue.increment(paymentsDelta),
        'settlements_count': FieldValue.increment(settlementsDelta),
        'last_event_at': updatedAt,
        'updated_at': updatedAt,
      }, SetOptions(merge: true));
    }

    applyToDoc('overall', scope: 'overall', scopeKey: 'overall');
    applyToDoc(
      'day_$dayKey',
      scope: 'day',
      scopeKey: dayKey,
      explicitDayKey: dayKey,
      explicitMonthKey: monthKey,
    );
    applyToDoc(
      'month_$monthKey',
      scope: 'month',
      scopeKey: monthKey,
      explicitMonthKey: monthKey,
    );
  }

  void _appendFinancialLedgerForPayment({
    required WriteBatch batch,
    required PaymentRecord payment,
    required Job job,
    required String actorId,
    required DateTime at,
  }) {
    final eventId = _uuid.v4();
    batch.set(_financialLedger.doc(eventId), <String, dynamic>{
      'id': eventId,
      'type': 'payment_recorded',
      'actor_id': actorId,
      'payment_id': payment.id,
      'job_id': payment.jobId,
      'customer_id': payment.customerId,
      'pro_id': payment.proId,
      'category': job.category.value,
      'method': payment.method.value,
      'gross_amount': payment.grossAmount,
      'platform_fee': payment.platformFee,
      'net_pro_amount': payment.netProAmount,
      'estimated_profit': payment.platformFee,
      'day_key': _dayKey(at),
      'month_key': _monthKey(at),
      'created_at': at.toIso8601String(),
      'updated_at': at.toIso8601String(),
    });

    _applyFinancialSummaryDelta(
      batch: batch,
      at: at,
      grossRevenueDelta: payment.grossAmount,
      platformRevenueDelta: payment.platformFee,
      proPayoutDelta: payment.netProAmount,
      dueSettledDelta: 0,
      estimatedProfitDelta: payment.platformFee,
      paymentsDelta: 1,
      settlementsDelta: 0,
    );
  }

  void _appendFinancialLedgerForDueSettlement({
    required WriteBatch batch,
    required String actorId,
    required String proId,
    required PaymentMethod method,
    required double amount,
    required DateTime at,
    String? externalReference,
  }) {
    final eventId = _uuid.v4();
    batch.set(_financialLedger.doc(eventId), <String, dynamic>{
      'id': eventId,
      'type': 'pro_due_settled',
      'actor_id': actorId,
      'pro_id': proId,
      'method': method.value,
      'amount': amount,
      if (externalReference != null && externalReference.isNotEmpty)
        'external_reference': externalReference,
      'day_key': _dayKey(at),
      'month_key': _monthKey(at),
      'created_at': at.toIso8601String(),
      'updated_at': at.toIso8601String(),
    });

    _applyFinancialSummaryDelta(
      batch: batch,
      at: at,
      grossRevenueDelta: 0,
      platformRevenueDelta: 0,
      proPayoutDelta: 0,
      dueSettledDelta: amount,
      estimatedProfitDelta: 0,
      paymentsDelta: 0,
      settlementsDelta: 1,
    );
  }

  Future<void> _setUserPresence(
    String userId, {
    required bool isOnline,
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    final nowIso = now.toIso8601String();
    final presencePatch = <String, dynamic>{
      'user_id': userId,
      'is_online': isOnline,
      'last_active_at': nowIso,
      'updated_at': nowIso,
      if (!isOnline) 'last_seen_at': nowIso,
    };
    final profilePatch = <String, dynamic>{
      'is_online': isOnline,
      'last_active_at': nowIso,
      'updated_at': nowIso,
      if (!isOnline) 'last_seen_at': nowIso,
    };
    try {
      await Future.wait<void>(<Future<void>>[
        _presence.doc(userId).set(presencePatch, SetOptions(merge: true)),
        _profiles.doc(userId).set(profilePatch, SetOptions(merge: true)),
      ]);
    } catch (error) {
      debugPrint('Skipping Firebase presence update for $userId: $error');
    }
  }

  Future<void> _touchUserPresence(String userId) {
    return _setUserPresence(userId, isOnline: true);
  }

  bool _isBootstrapAdminEmail(String? email) {
    final normalized = email?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }
    return _bootstrapAdminEmails.contains(normalized);
  }

  bool _hasSuperAdminAccess(AppUser user) {
    return user.role == UserRole.admin &&
        user.effectiveAdminRank == AdminRank.superAdmin;
  }

  AppUser _asSuperAdmin(AppUser user) {
    if (_hasSuperAdminAccess(user)) {
      return user;
    }
    final data = user.toJson();
    data['role'] = UserRole.admin.value;
    data['admin_rank'] = AdminRank.superAdmin.value;
    data['admin_permissions'] = defaultAdminPermissionsForRank(
      AdminRank.superAdmin,
    ).map((permission) => permission.value).toList(growable: false);
    data['updated_at'] = DateTime.now().toIso8601String();
    return AppUser.fromJson(data);
  }

  bool _looksLikeLegacyProProfile(AppUser user) {
    if (user.role != UserRole.customer) {
      return false;
    }
    final hasPaymentAccount = (user.paymentAccount ?? '').trim().isNotEmpty;
    return user.preferredCategories.isNotEmpty ||
        user.cnicVerified ||
        user.policeVerified ||
        hasPaymentAccount;
  }

  AppUser _normalizeLegacyRoleIfNeeded(AppUser user) {
    if (!_looksLikeLegacyProProfile(user)) {
      return user;
    }
    final data = user.toJson();
    data['role'] = UserRole.pro.value;
    data['updated_at'] = DateTime.now().toIso8601String();
    return AppUser.fromJson(data);
  }

  UserRole _resolvedRoleForAuthUser(User firebaseUser, UserRole fallbackRole) {
    if (_isBootstrapAdminEmail(firebaseUser.email)) {
      return UserRole.admin;
    }
    return fallbackRole;
  }

  AppUser _fallbackProfileForAuthUser(
    User firebaseUser, {
    UserRole role = UserRole.customer,
    String? fullName,
    String? phone,
    TermsAcceptance? acceptance,
    List<JobCategory> preferredCategories = const <JobCategory>[],
  }) {
    final now = DateTime.now();
    final resolvedFullName = (fullName == null || fullName.trim().isEmpty)
        ? _fallbackFullNameForAuthUser(firebaseUser)
        : fullName.trim();
    final resolvedEmail = firebaseUser.email?.trim().toLowerCase() ?? '';
    return AppUser(
      id: firebaseUser.uid,
      role: role,
      fullName: resolvedFullName,
      email: resolvedEmail,
      phone: phone?.trim() ?? '',
      username: _buildUsername(
        fullName: resolvedFullName,
        email: resolvedEmail,
        userId: firebaseUser.uid,
      ),
      isOnline: true,
      lastSeenAt: now,
      lastActiveAt: now,
      termsAcceptanceHistory: acceptance == null
          ? const <TermsAcceptance>[]
          : <TermsAcceptance>[acceptance],
      preferredCategories: preferredCategories,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<AppUser?> _loadProfileByUserId(String userId) async {
    try {
      final snapshot = await _profiles
          .doc(userId)
          .get(const GetOptions(source: Source.serverAndCache));
      if (!snapshot.exists) {
        return null;
      }
      return _userFromDoc(snapshot);
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage(error));
    }
  }

  Future<AppUser?> _loadCachedProfileByUserId(String userId) async {
    try {
      final snapshot = await _profiles
          .doc(userId)
          .get(const GetOptions(source: Source.cache))
          .timeout(_cacheReadTimeout);
      if (!snapshot.exists) {
        return null;
      }
      return _userFromDoc(snapshot);
    } catch (_) {
      return null;
    }
  }

  Future<AppUser?> _loadPersistedSessionUser(String userId) async {
    final cached = await _authSessionCache.load();
    if (cached == null || cached.id != userId) {
      return null;
    }
    return cached;
  }

  Future<void> _cacheSessionUser(AppUser user) async {
    try {
      await _authSessionCache.save(user);
    } catch (error) {
      debugPrint('Skipping auth session cache write: $error');
    }
  }

  Future<void> _signOutAndClearSession() async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId != null && currentUserId.isNotEmpty) {
      await _recordAuthSessionEvent(userId: currentUserId, action: 'logout');
      // Do not block logout on network/presence writes.
      unawaited(_setUserPresence(currentUserId, isOnline: false));
    }
    try {
      await _auth.signOut();
    } catch (error) {
      debugPrint(
        'Firebase sign-out failed, clearing local session anyway: $error',
      );
    }
    try {
      await _authSessionCache.clear();
    } catch (error) {
      debugPrint('Auth session cache clear skipped: $error');
    }
    _pendingAuthProfiles.clear();
  }

  Future<void> _writeProfileIfMissing(
    User firebaseUser,
    AppUser profile,
  ) async {
    final normalizedProfile = _normalizeProfileIdentityIfNeeded(profile);
    await _runFirebaseCall(
      () => _profiles
          .doc(firebaseUser.uid)
          .set(normalizedProfile.toJson(), SetOptions(merge: true)),
    );
  }

  Future<AppUser> _ensureProfileForAuthUser(
    User firebaseUser, {
    UserRole role = UserRole.customer,
    String? fullName,
    String? phone,
    TermsAcceptance? acceptance,
    List<JobCategory> preferredCategories = const <JobCategory>[],
  }) async {
    final resolvedRole = _resolvedRoleForAuthUser(firebaseUser, role);
    final existing = await _loadProfileByUserId(firebaseUser.uid);
    if (existing != null) {
      final enrichedExisting = _withProfileMetadata(existing, online: true);
      if (enrichedExisting.username != existing.username ||
          enrichedExisting.isOnline != existing.isOnline ||
          enrichedExisting.lastSeenAt != existing.lastSeenAt ||
          enrichedExisting.lastActiveAt != existing.lastActiveAt) {
        await _writeProfileIfMissing(firebaseUser, enrichedExisting);
      }
      if (_isBootstrapAdminEmail(firebaseUser.email)) {
        final promoted = _asSuperAdmin(enrichedExisting);
        if (!_hasSuperAdminAccess(existing)) {
          await _writeProfileIfMissing(firebaseUser, promoted);
        }
        return promoted;
      }
      return enrichedExisting;
    }

    var fallback = _withProfileMetadata(
      _fallbackProfileForAuthUser(
        firebaseUser,
        role: resolvedRole,
        fullName: fullName,
        phone: phone,
        acceptance: acceptance,
        preferredCategories: preferredCategories,
      ),
      online: true,
    );
    if (resolvedRole == UserRole.admin) {
      fallback = _asSuperAdmin(fallback);
    }

    await _writeProfileIfMissing(firebaseUser, fallback);
    unawaited(
      _writeAuditSafely(
        AuditEvent(
          id: _uuid.v4(),
          actorId: fallback.id,
          action: 'profile_auto_bootstrapped',
          entityType: 'user',
          entityId: fallback.id,
          createdAt: DateTime.now(),
          metadata: <String, dynamic>{'source': 'firebase_auth_bootstrap'},
        ),
      ),
    );
    return fallback;
  }

  Future<AppUser> _resolveSignedInUserForInstantAccess(
    User firebaseUser,
  ) async {
    final pending = _pendingAuthProfiles[firebaseUser.uid];
    if (pending != null) {
      final enriched = _withProfileMetadata(pending, online: true);
      return _isBootstrapAdminEmail(firebaseUser.email)
          ? _asSuperAdmin(enriched)
          : enriched;
    }
    final cached = await _loadCachedProfileByUserId(firebaseUser.uid);
    if (cached != null) {
      final enriched = _withProfileMetadata(cached, online: true);
      return _isBootstrapAdminEmail(firebaseUser.email)
          ? _asSuperAdmin(enriched)
          : enriched;
    }
    final persisted = await _loadPersistedSessionUser(firebaseUser.uid);
    if (persisted != null) {
      final enriched = _withProfileMetadata(persisted, online: true);
      return _isBootstrapAdminEmail(firebaseUser.email)
          ? _asSuperAdmin(enriched)
          : enriched;
    }
    final fallback = _withProfileMetadata(
      _fallbackProfileForAuthUser(
        firebaseUser,
        role: _resolvedRoleForAuthUser(firebaseUser, UserRole.customer),
      ),
      online: true,
    );
    return _isBootstrapAdminEmail(firebaseUser.email)
        ? _asSuperAdmin(fallback)
        : fallback;
  }

  Future<void> _bootstrapProfileWriteSafely(
    User firebaseUser,
    AppUser profile, {
    AuditEvent? audit,
  }) async {
    final normalizedProfile = _normalizeProfileIdentityIfNeeded(profile);
    try {
      await _profiles
          .doc(firebaseUser.uid)
          .set(normalizedProfile.toJson(), SetOptions(merge: true));
      if (audit != null) {
        await _writeAuditSafely(audit);
      }
    } catch (error) {
      debugPrint('Skipping Firebase profile bootstrap write: $error');
    }
  }

  Future<void> _syncProfileForSignedInUser(User firebaseUser) async {
    try {
      final pending = _pendingAuthProfiles[firebaseUser.uid];
      final persisted = await _loadPersistedSessionUser(firebaseUser.uid);
      final synced = await _ensureProfileForAuthUser(
        firebaseUser,
        role: _resolvedRoleForAuthUser(
          firebaseUser,
          pending?.role ?? persisted?.role ?? UserRole.customer,
        ),
        fullName: pending?.fullName ?? persisted?.fullName,
        phone: pending?.phone ?? persisted?.phone,
        preferredCategories:
            pending?.preferredCategories ??
            persisted?.preferredCategories ??
            const <JobCategory>[],
      );
      await _cacheSessionUser(synced);
      _pendingAuthProfiles.remove(firebaseUser.uid);
    } catch (error) {
      debugPrint('Skipping Firebase profile sync after auth: $error');
    }
  }

  Future<T> _runFirebaseCall<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (error) {
      throw StateError(_authErrorMessage(error));
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage(error));
    }
  }

  Future<T> _runFirebaseAuthCall<T>(
    Future<T> Function() action, {
    Duration timeout = _authRequestTimeout,
    String timeoutMessage = 'Authentication request timed out.',
  }) async {
    try {
      return await action().timeout(
        timeout,
        onTimeout: () => throw TimeoutException(timeoutMessage, timeout),
      );
    } on TimeoutException {
      throw StateError(timeoutMessage);
    } on FirebaseAuthException catch (error) {
      throw StateError(_authErrorMessage(error));
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage(error));
    }
  }

  String _firebaseErrorMessage(FirebaseException error) {
    return switch (error.code) {
      'permission-denied' =>
        'Firebase blocked access. Check your Firestore security rules.',
      'failed-precondition' =>
        'Firebase is not fully configured yet. Check Firestore and Authentication setup.',
      'unavailable' =>
        'Firebase is unavailable right now. Check your internet connection and try again.',
      'deadline-exceeded' =>
        'Firebase is temporarily unreachable. Please try again.',
      'not-found' => 'Required Firebase data was not found.',
      _ => error.message ?? 'Firebase request failed.',
    };
  }

  String _authErrorMessage(FirebaseAuthException error) {
    final message = (error.message ?? '').toLowerCase();
    return switch (error.code) {
      'account-exists-with-different-credential' =>
        'This email is linked to a different sign-in method.',
      'app-not-authorized' =>
        'App authorization failed. Please reinstall and try again.',
      'captcha-check-failed' => 'Security check failed. Please try again.',
      'credential-already-in-use' =>
        'These credentials are already linked to another account.',
      'email-already-in-use' => 'This email is already in use.',
      'expired-action-code' =>
        'This action code has expired. Request a new one.',
      'invalid-action-code' => 'Invalid or expired action code.',
      'invalid-credential' =>
        message.contains('password')
            ? 'Incorrect email or password.'
            : 'Invalid login credentials.',
      'invalid-email' => 'Please enter a valid email address.',
      'invalid-login-credentials' => 'Incorrect email or password.',
      'invalid-phone-number' => 'Please enter a valid phone number.',
      'invalid-user-token' => 'Your session has expired. Please log in again.',
      'missing-email' => 'Email is required.',
      'missing-password' => 'Password is required.',
      'network-request-failed' => 'Check your internet connection.',
      'no-such-provider' =>
        'This sign-in provider is not linked to your account.',
      'operation-not-allowed' =>
        'Email/password sign-in is disabled in Firebase Authentication.',
      'provider-already-linked' => 'This provider is already linked.',
      'requires-recent-login' =>
        'Please log in again before changing your password.',
      'session-expired' => 'Session expired. Request a new verification code.',
      'too-many-requests' => 'Account temporarily locked. Try later.',
      'user-disabled' => 'This account has been disabled.',
      'user-mismatch' => 'Signed-in user mismatch. Please try again.',
      'user-not-found' => 'Incorrect email or password.',
      'user-token-expired' => 'Your session has expired. Please log in again.',
      'weak-password' => 'Password is too weak.',
      'wrong-password' => 'Incorrect email or password.',
      _ => error.message ?? 'Authentication failed. Please try again.',
    };
  }

  Future<void> _writeNotification(NotificationEvent event) {
    return _notifications.doc(event.id).set(event.toJson());
  }

  Future<void> _writeAudit(AuditEvent event) {
    return _audits.doc(event.id).set(event.toJson());
  }

  Future<void> _writeAuditSafely(AuditEvent event) async {
    try {
      await _writeAudit(event);
    } catch (error) {
      debugPrint('Skipping Firebase audit log write: $error');
    }
  }

  Future<void> _recordAuthSessionEvent({
    required String userId,
    required String action,
  }) async {
    try {
      await _writeAuditSafely(
        AuditEvent(
          id: _uuid.v4(),
          actorId: userId,
          action: action,
          entityType: 'session',
          entityId: userId,
          createdAt: DateTime.now(),
          deviceInfo: DeviceContextService().describeDevice(),
          metadata: <String, dynamic>{
            'session_id': _sessionId,
            'auth_method': 'email_password',
          },
        ),
      );
    } catch (error) {
      debugPrint('Skipping Firebase auth session audit: $error');
    }
  }

  Future<void> _updateDisplayNameSafely(User user, String fullName) async {
    try {
      await user.updateDisplayName(fullName);
    } catch (error) {
      debugPrint('Skipping Firebase display name update: $error');
    }
  }

  Map<String, dynamic> _externalReferenceMap(String? externalReference) {
    if (externalReference == null || externalReference.isEmpty) {
      return const <String, dynamic>{};
    }
    return <String, dynamic>{'external_reference': externalReference};
  }

  List<NotificationEvent> _buildDueThresholdNotifications({
    required AppUser pro,
    required double previousDue,
    required double currentDue,
    String? jobId,
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
    final notifications = <NotificationEvent>[];
    if (crossedMild) {
      notifications.add(
        NotificationEvent(
          id: _uuid.v4(),
          userId: pro.id,
          type: 'due_warning_mild',
          title: '75% limit reached',
          body:
              "You're 75% of the way to your limit. Pay soon to keep working!",
          sentAt: now,
          metadata: <String, dynamic>{
            'due_to_app': currentDue,
            if (jobId != null && jobId.isNotEmpty) 'job_id': jobId,
          },
        ),
      );
    }
    if (crossedStrong) {
      notifications.add(
        NotificationEvent(
          id: _uuid.v4(),
          userId: pro.id,
          type: 'due_warning_strong',
          title: 'Urgent due warning',
          body:
              'Urgent: Pay your dues now or your account will be locked soon.',
          sentAt: now,
          metadata: <String, dynamic>{
            'due_to_app': currentDue,
            if (jobId != null && jobId.isNotEmpty) 'job_id': jobId,
          },
        ),
      );
    }
    if (crossedLock) {
      notifications.add(
        NotificationEvent(
          id: _uuid.v4(),
          userId: pro.id,
          type: 'due_locked',
          title: 'Account locked',
          body:
              'Account Locked. Please clear your 2,000 PKR due to continue bidding on jobs.',
          sentAt: now,
          metadata: <String, dynamic>{
            'due_to_app': currentDue,
            if (jobId != null && jobId.isNotEmpty) 'job_id': jobId,
          },
        ),
      );
    }
    return notifications;
  }

  bool _isProNearbyJob(AppUser pro, Job job, {double radiusKm = 25}) {
    if (pro.savedLocations.isEmpty) {
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

  @override
  Stream<AppUser?> watchCurrentUser() {
    late final StreamController<AppUser?> controller;
    StreamSubscription<User?>? authSubscription;
    StreamSubscription<AppUser?>? profileSubscription;
    var isClosed = false;
    var authEventSerial = 0;

    Future<void> handleAuthState(
      User? firebaseUser, {
      required bool isInitialAuthState,
    }) async {
      final currentSerial = ++authEventSerial;
      try {
        await profileSubscription?.cancel();
        profileSubscription = null;

        if (firebaseUser == null) {
          await _authSessionCache.clear();
          _pendingAuthProfiles.clear();
          if (!isClosed && currentSerial == authEventSerial) {
            controller.add(null);
          }
          return;
        }

        final initialUser = await _resolveSignedInUserForInstantAccess(
          firebaseUser,
        );
        if (isClosed || currentSerial != authEventSerial) {
          return;
        }
        if (initialUser.blocked) {
          await _signOutAndClearSession();
          if (!isClosed && currentSerial == authEventSerial) {
            controller.add(null);
          }
          return;
        }

        if (isInitialAuthState &&
            await _loadPersistedSessionUser(firebaseUser.uid) != null) {
          unawaited(
            _recordAuthSessionEvent(
              userId: firebaseUser.uid,
              action: 'session_resumed',
            ),
          );
        }
        unawaited(_setUserPresence(firebaseUser.uid, isOnline: true));
        controller.add(initialUser);
        unawaited(_syncProfileForSignedInUser(firebaseUser));

        profileSubscription = _profiles
            .doc(firebaseUser.uid)
            .snapshots(includeMetadataChanges: true)
            .asyncMap((snapshot) async {
              if (!snapshot.exists) {
                try {
                  final pending = _pendingAuthProfiles[firebaseUser.uid];
                  final persisted = await _loadPersistedSessionUser(
                    firebaseUser.uid,
                  );
                  return await _ensureProfileForAuthUser(
                    firebaseUser,
                    role: _resolvedRoleForAuthUser(
                      firebaseUser,
                      pending?.role ?? persisted?.role ?? UserRole.customer,
                    ),
                    fullName: pending?.fullName ?? persisted?.fullName,
                    phone: pending?.phone ?? persisted?.phone,
                    preferredCategories:
                        pending?.preferredCategories ??
                        persisted?.preferredCategories ??
                        const <JobCategory>[],
                  );
                } catch (_) {
                  return initialUser;
                }
              }
              var user = _userFromDoc(snapshot);
              final normalizedRoleUser = _normalizeLegacyRoleIfNeeded(user);
              if (normalizedRoleUser.role != user.role) {
                unawaited(
                  _profiles
                      .doc(firebaseUser.uid)
                      .set(
                        normalizedRoleUser.toJson(),
                        SetOptions(merge: true),
                      ),
                );
                user = normalizedRoleUser;
              }
              final normalizedIdentityUser = _normalizeProfileIdentityIfNeeded(
                user,
              );
              if (normalizedIdentityUser.username != user.username) {
                unawaited(
                  _profiles
                      .doc(firebaseUser.uid)
                      .set(
                        normalizedIdentityUser.toJson(),
                        SetOptions(merge: true),
                      ),
                );
                user = normalizedIdentityUser;
              }
              if (_isBootstrapAdminEmail(firebaseUser.email)) {
                final promoted = _asSuperAdmin(user);
                if (!_hasSuperAdminAccess(user)) {
                  unawaited(
                    _bootstrapProfileWriteSafely(firebaseUser, promoted),
                  );
                }
                user = promoted;
              }
              if (user.blocked) {
                await _signOutAndClearSession();
                return null;
              }
              unawaited(_cacheSessionUser(user));
              _pendingAuthProfiles.remove(firebaseUser.uid);
              return user;
            })
            .listen(
              (user) {
                if (!isClosed && currentSerial == authEventSerial) {
                  controller.add(user);
                }
              },
              onError: (Object error, StackTrace stackTrace) {
                debugPrint(
                  'Skipping Firebase auth profile stream error: $error',
                );
              },
            );
      } catch (error, stackTrace) {
        if (!isClosed && currentSerial == authEventSerial) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller = StreamController<AppUser?>(
      onListen: () {
        var isInitialAuthState = true;
        authSubscription = _auth.authStateChanges().listen(
          (firebaseUser) {
            final wasInitialAuthState = isInitialAuthState;
            isInitialAuthState = false;
            unawaited(
              handleAuthState(
                firebaseUser,
                isInitialAuthState: wasInitialAuthState,
              ),
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!isClosed) {
              controller.addError(error, stackTrace);
            }
          },
        );
      },
      onCancel: () async {
        isClosed = true;
        await profileSubscription?.cancel();
        await authSubscription?.cancel();
      },
    );

    return controller.stream;
  }

  @override
  Future<AppUser?> getCurrentUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) {
      return null;
    }
    var user = await _resolveSignedInUserForInstantAccess(firebaseUser);
    final normalizedRoleUser = _normalizeLegacyRoleIfNeeded(user);
    if (normalizedRoleUser.role != user.role) {
      user = normalizedRoleUser;
      unawaited(_bootstrapProfileWriteSafely(firebaseUser, user));
    }
    if (user.blocked) {
      await _signOutAndClearSession();
      return null;
    }
    unawaited(_setUserPresence(firebaseUser.uid, isOnline: true));
    unawaited(_syncProfileForSignedInUser(firebaseUser));
    return user;
  }

  @override
  Future<AppUser> register(RegisterInput input) async {
    if (!input.acceptance.checkboxConfirmed) {
      throw StateError('Terms and Privacy acceptance is required.');
    }

    final email = _normalizeEmail(input.email);
    _assertValidEmail(email);
    _assertStrongPassword(input.password);
    final phone = _normalizePhone(input.phone);
    _assertValidPhone(phone);
    final resolvedFullName = _sanitizeSingleLine(
      input.fullName,
      field: 'Full name',
      minLength: 2,
      maxLength: 100,
    );
    final targetRole = _isBootstrapAdminEmail(email)
        ? UserRole.admin
        : input.role;
    if (targetRole == UserRole.admin && !_isBootstrapAdminEmail(email)) {
      throw StateError('Admin registration is disabled.');
    }
    input.validateForRole(targetRole);
    final preferredCategories = input.normalizedPreferredCategoriesForRole(
      targetRole,
    );

    final credential = await _runFirebaseAuthCall(
      () => _auth.createUserWithEmailAndPassword(
        email: email,
        password: input.password,
      ),
      timeout: _signInTimeout,
      timeoutMessage: 'Network Timeout',
    );

    final authUser = credential.user;
    if (authUser == null) {
      throw StateError('Sign up failed.');
    }

    final now = DateTime.now();
    final isAdmin = targetRole == UserRole.admin;
    final profile = AppUser(
      id: authUser.uid,
      role: targetRole,
      fullName: resolvedFullName,
      email: email,
      phone: phone,
      username: _buildUsername(
        fullName: resolvedFullName,
        email: email,
        userId: authUser.uid,
      ),
      adminRank: isAdmin ? AdminRank.superAdmin : null,
      adminPermissions: isAdmin
          ? defaultAdminPermissionsForRank(AdminRank.superAdmin)
          : const <AdminPermission>[],
      isOnline: true,
      lastSeenAt: now,
      lastActiveAt: now,
      preferredCategories: preferredCategories,
      termsAcceptanceHistory: <TermsAcceptance>[input.acceptance],
      createdAt: now,
      updatedAt: now,
    );
    _pendingAuthProfiles[authUser.uid] = profile;
    final audit = AuditEvent(
      id: _uuid.v4(),
      actorId: profile.id,
      action: 'register',
      entityType: 'user',
      entityId: profile.id,
      createdAt: now,
      ipAddress: input.acceptance.ipAddress,
      deviceInfo: input.acceptance.deviceInfo,
      metadata: <String, dynamic>{
        'terms_version': input.acceptance.termsVersion,
        'privacy_version': input.acceptance.privacyVersion,
      },
    );

    await _cacheSessionUser(profile);
    await _writeProfileIfMissing(authUser, profile);
    await _writeAuditSafely(audit);
    unawaited(_updateDisplayNameSafely(authUser, profile.fullName));
    unawaited(_setUserPresence(authUser.uid, isOnline: true));
    return profile;
  }

  @override
  Future<AppUser> signIn(LoginInput input) async {
    final email = _normalizeEmail(input.email);
    _assertValidEmail(email);
    if (input.password.trim().isEmpty) {
      throw StateError('Password is required.');
    }
    if (input.password.length > 256) {
      throw StateError('Password is too long.');
    }

    final credential = await _runFirebaseAuthCall(
      () => _auth.signInWithEmailAndPassword(
        email: email,
        password: input.password,
      ),
      timeout: _signInTimeout,
      timeoutMessage: 'Network Timeout',
    );

    final authUser = credential.user;
    if (authUser == null) {
      throw StateError('Login failed.');
    }

    var user = await _resolveSignedInUserForInstantAccess(authUser);
    final normalizedRoleUser = _normalizeLegacyRoleIfNeeded(user);
    if (normalizedRoleUser.role != user.role) {
      user = normalizedRoleUser;
      unawaited(_bootstrapProfileWriteSafely(authUser, user));
    }
    if (_isBootstrapAdminEmail(email)) {
      user = _asSuperAdmin(user);
      unawaited(_bootstrapProfileWriteSafely(authUser, user));
    }
    if (user.blocked) {
      await _signOutAndClearSession();
      throw StateError('Account is blocked.');
    }
    await _cacheSessionUser(user);
    await _recordAuthSessionEvent(userId: user.id, action: 'login');
    unawaited(_syncProfileForSignedInUser(authUser));
    unawaited(_setUserPresence(authUser.uid, isOnline: true));
    return user;
  }

  @override
  Future<void> signOut() => _signOutAndClearSession();

  @override
  Future<AppUser> upgradeToProfessional({
    required List<JobCategory> preferredCategories,
  }) async {
    final currentUserId = _requireCurrentUserId();
    final current = await _loadProfileForAccess(currentUserId);
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
    await _profiles
        .doc(currentUserId)
        .set(upgraded.toJson(), SetOptions(merge: true));
    await _cacheSessionUser(upgraded);
    await _writeAudit(
      AuditEvent(
        id: _uuid.v4(),
        actorId: currentUserId,
        action: 'pro_profile_activated',
        entityType: 'user',
        entityId: currentUserId,
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
  Future<void> updateProfile(AppUser user) async {
    final currentUserId = _requireCurrentUserId();
    final current = await _loadProfileForAccess(currentUserId);
    final sanitizedFullName = _sanitizeSingleLine(
      user.fullName,
      field: 'Full name',
      minLength: 2,
      maxLength: 100,
    );
    final sanitizedPhone = _normalizePhone(user.phone);
    _assertValidPhone(sanitizedPhone);
    final sanitizedPaymentAccount = _sanitizeOptionalSingleLine(
      user.paymentAccount,
      field: 'Payment account',
      maxLength: 60,
    );

    final updated = current.copyWith(
      fullName: sanitizedFullName,
      phone: sanitizedPhone,
      username: current.username.trim().isEmpty
          ? _buildUsername(
              fullName: sanitizedFullName,
              email: current.email,
              userId: currentUserId,
            )
          : current.username,
      profileImageUrl: user.profileImageUrl,
      languageCode: user.languageCode,
      notificationsEnabled: user.notificationsEnabled,
      preciseLocationEnabled: user.preciseLocationEnabled,
      paymentAccount: sanitizedPaymentAccount,
      preferredCategories: user.preferredCategories,
      savedLocations: user.savedLocations,
      updatedAt: DateTime.now(),
    );
    await _profiles.doc(currentUserId).set(updated.toJson());
    unawaited(_touchUserPresence(currentUserId));
    unawaited(_cacheSessionUser(updated));
    await _writeAudit(
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
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (currentPassword.trim().isEmpty) {
      throw StateError('Current password is required.');
    }
    _assertStrongPassword(newPassword);

    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw StateError('Not authenticated.');
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(
          email: user.email!,
          password: currentPassword,
        ),
      );
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (error) {
      throw StateError(_authErrorMessage(error));
    }
  }

  @override
  Stream<List<AppUser>> watchAllUsers({bool includeLocations = false}) {
    return _profiles.snapshots().map((snapshot) {
      final users = snapshot.docs
          .map((doc) {
            final data = _documentData(doc);
            if (!includeLocations) {
              data['saved_locations'] = const <dynamic>[];
            }
            return AppUser.fromJson(data);
          })
          .toList(growable: false);
      users.sort((a, b) {
        final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return users;
    });
  }

  @override
  Future<void> verifyPro({
    required String userId,
    required bool cnicVerified,
    required bool policeVerified,
  }) async {
    final actorId = _requireCurrentUserId();
    await setProVerification(
      actorId: actorId,
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
    await _requireAdminPermission(
      actorId,
      AdminPermission.manageProVerification,
    );
    final target = await _loadProfileForAccess(userId);
    if (target.role != UserRole.pro) {
      throw StateError('Professional user not found.');
    }
    final updated = target.copyWith(
      cnicVerified: cnicVerified,
      policeVerified: policeVerified,
      updatedAt: DateTime.now(),
    );
    await _profiles.doc(userId).set(updated.toJson());
    await _writeAudit(
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
    _assertCurrentUser(userId);
    final normalizedLocation = SavedLocation(
      id: location.id,
      label: _sanitizeSingleLine(
        location.label,
        field: 'Location label',
        minLength: 1,
        maxLength: 40,
      ),
      latitude: location.latitude,
      longitude: location.longitude,
      address: _sanitizeSingleLine(
        location.address,
        field: 'Location address',
        minLength: 3,
        maxLength: 240,
      ),
      createdAt: location.createdAt,
    );

    await _firestore.runTransaction((transaction) async {
      final ref = _profiles.doc(userId);
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        throw StateError('User not found.');
      }
      final user = _userFromDoc(snapshot);
      final updatedLocations = <SavedLocation>[
        ...user.savedLocations.where(
          (existing) => existing.id != normalizedLocation.id,
        ),
        normalizedLocation,
      ];
      final updated = user.copyWith(
        savedLocations: updatedLocations,
        updatedAt: DateTime.now(),
      );
      transaction.set(ref, updated.toJson());
    });
  }

  @override
  Stream<List<Job>> watchNearbyJobs({
    required JobCategory category,
    required double latitude,
    required double longitude,
    double radiusKm = 25,
  }) {
    return _jobs.where('category', isEqualTo: category.value).snapshots().map((
      snapshot,
    ) {
      final jobs = _safeParseDocs(snapshot.docs, _jobFromDoc, 'job')
          .where((job) {
            if (job.status != JobStatus.available &&
                job.status != JobStatus.posted) {
              return false;
            }
            final meters = Geolocator.distanceBetween(
              latitude,
              longitude,
              job.latitude,
              job.longitude,
            );
            return (meters / 1000) <= radiusKm;
          })
          .toList(growable: false);
      jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return jobs;
    });
  }

  @override
  Stream<List<Job>> watchJobsForUser(String userId) {
    return _jobs.where('customer_id', isEqualTo: userId).snapshots().map((
      snapshot,
    ) {
      final jobs = _safeParseDocs(snapshot.docs, _jobFromDoc, 'job');
      jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return jobs;
    });
  }

  @override
  Stream<List<Job>> watchJobsForPro(String proId) {
    return _jobs.where('assigned_pro_id', isEqualTo: proId).snapshots().map((
      snapshot,
    ) {
      final jobs = _safeParseDocs(snapshot.docs, _jobFromDoc, 'job');
      jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return jobs;
    });
  }

  @override
  Stream<List<Job>> watchAllJobs() {
    return _jobs.snapshots().map((snapshot) {
      final jobs = _safeParseDocs(snapshot.docs, _jobFromDoc, 'job');
      jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return jobs;
    });
  }

  @override
  Stream<Job?> watchJob(String jobId) {
    return _jobs.doc(jobId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      return _jobFromDoc(snapshot);
    });
  }

  @override
  Stream<List<Bid>> watchBids(String jobId) {
    return _bids.where('job_id', isEqualTo: jobId).snapshots().map((snapshot) {
      final bids = _safeParseDocs(snapshot.docs, _bidFromDoc, 'bid');
      bids.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return bids;
    });
  }

  @override
  Future<Job> postJob(JobPostInput input) async {
    _assertCurrentUser(input.customerId);
    if (input.fixedPrice <= 0) {
      throw StateError('Price must be positive.');
    }
    final sanitizedTitle = _sanitizeSingleLine(
      input.title,
      field: 'Job title',
      minLength: 4,
      maxLength: 120,
    );
    final sanitizedDescription = _sanitizeMultiLine(
      input.description,
      field: 'Job description',
      minLength: 10,
      maxLength: 2000,
    );
    final sanitizedMaskedAddress = _sanitizeSingleLine(
      input.maskedAddress,
      field: 'Masked address',
      minLength: 4,
      maxLength: 220,
    );
    final sanitizedExactAddress = _sanitizeSingleLine(
      input.exactAddress,
      field: 'Exact address',
      minLength: 4,
      maxLength: 320,
    );

    final now = DateTime.now();
    final job = Job(
      id: _uuid.v4(),
      customerId: input.customerId,
      category: input.category,
      title: sanitizedTitle,
      description: sanitizedDescription,
      fixedPrice: input.fixedPrice,
      latitude: input.latitude,
      longitude: input.longitude,
      maskedAddress: sanitizedMaskedAddress,
      exactAddress: sanitizedExactAddress,
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

    await _jobs.doc(job.id).set(job.toJson());

    final prosSnapshot = await _profiles
        .where(
          'role',
          whereIn: <String>[
            'pro',
            'professional',
            'provider',
            'service_provider',
            'worker',
            'service_worker',
            'serviceman',
            'technician',
          ],
        )
        .get();
    final notifications = prosSnapshot.docs
        .map(_userFromDoc)
        .where((user) {
          return user.isVerifiedPro &&
              user.preferredCategories.contains(job.category) &&
              !user.blocked &&
              _isProNearbyJob(user, job);
        })
        .map(
          (pro) => NotificationEvent(
            id: _uuid.v4(),
            userId: pro.id,
            type: 'job_nearby',
            title: 'New ${job.category.displayName} job',
            body: 'Fixed price: PKR ${job.fixedPrice.toStringAsFixed(0)}',
            sentAt: now,
            metadata: <String, dynamic>{'job_id': job.id},
          ),
        )
        .toList(growable: false);
    for (final event in notifications) {
      await _writeNotification(event);
    }

    await _writeAudit(
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
    _assertCurrentUser(input.actorId);
    if (input.fixedPrice <= 0) {
      throw StateError('Price must be positive.');
    }
    final sanitizedTitle = _sanitizeSingleLine(
      input.title,
      field: 'Job title',
      minLength: 4,
      maxLength: 120,
    );
    final sanitizedDescription = _sanitizeMultiLine(
      input.description,
      field: 'Job description',
      minLength: 10,
      maxLength: 2000,
    );
    final sanitizedMaskedAddress = _sanitizeSingleLine(
      input.maskedAddress,
      field: 'Masked address',
      minLength: 4,
      maxLength: 220,
    );
    final sanitizedExactAddress = _sanitizeSingleLine(
      input.exactAddress,
      field: 'Exact address',
      minLength: 4,
      maxLength: 320,
    );

    final job = await _loadJob(input.jobId);
    final actor = await _loadProfileForAccess(input.actorId);
    final actorIsAdmin = actor.role == UserRole.admin;
    if (!actorIsAdmin && job.customerId != input.actorId) {
      throw StateError('Only the customer who posted this job can edit it.');
    }
    if (job.status != JobStatus.available && job.status != JobStatus.posted) {
      throw StateError('Job can only be edited while it is still open.');
    }

    final now = DateTime.now();
    final updated = job.copyWith(
      title: sanitizedTitle,
      description: sanitizedDescription,
      fixedPrice: input.fixedPrice,
      latitude: input.latitude,
      longitude: input.longitude,
      maskedAddress: sanitizedMaskedAddress,
      exactAddress: sanitizedExactAddress,
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

    await _jobs.doc(input.jobId).set(updated.toJson());
    await _writeAudit(
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
    _assertCurrentUser(input.proId);
    if (input.amount > 1000000000) {
      throw StateError('Bid amount is too large.');
    }
    final sanitizedNotes = _sanitizeOptionalSingleLine(
      input.notes,
      field: 'Bid note',
      maxLength: 280,
    );

    final pro = await _loadProfileForAccess(input.proId);
    if (pro.role != UserRole.pro) {
      throw StateError('Professional account not found.');
    }
    if (ProBalanceRules.isLocked(pro.dueToApp)) {
      throw StateError(
        'Account locked. Please clear your due to continue bidding.',
      );
    }

    final job = await _loadJob(input.jobId);
    if (job.status != JobStatus.available && job.status != JobStatus.posted) {
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

    final bidId = '${input.jobId}_${input.proId}';
    final bidRef = _bids.doc(bidId);
    final existingSnapshot = await bidRef.get();
    Map<String, dynamic> metadataForBid(Bid bid) {
      return <String, dynamic>{
        'job_id': job.id,
        'job_title': job.title,
        'bid_id': bid.id,
        'pro_id': pro.id,
        'pro_name': pro.fullName,
        'pro_rating': pro.rating,
        'pro_total_reviews': pro.totalReviews,
        'works_done': pro.totalReviews,
        'amount': bid.amount,
      };
    }

    if (existingSnapshot.exists) {
      final existing = _bidFromDoc(existingSnapshot);
      if (existing.status != BidStatus.pending) {
        throw StateError('Bid is already finalized and cannot be edited.');
      }
      final now = DateTime.now();
      final updatedBid = Bid(
        id: bidId,
        jobId: job.id,
        proId: input.proId,
        amount: input.amount,
        status: BidStatus.pending,
        createdAt: now,
        notes: sanitizedNotes,
      );
      await bidRef.set(updatedBid.toJson());
      await _writeNotification(
        NotificationEvent(
          id: _uuid.v4(),
          userId: job.customerId,
          type: 'bid_updated',
          title: '${pro.fullName} updated request',
          body:
              '${pro.fullName} requested your job for PKR ${updatedBid.amount.toStringAsFixed(0)}',
          sentAt: now,
          metadata: metadataForBid(updatedBid),
        ),
      );
      await _writeAudit(
        AuditEvent(
          id: _uuid.v4(),
          actorId: input.proId,
          action: 'bid_updated',
          entityType: 'bid',
          entityId: updatedBid.id,
          createdAt: now,
        ),
      );
      return updatedBid;
    }

    final now = DateTime.now();
    final newBid = Bid(
      id: bidId,
      jobId: job.id,
      proId: input.proId,
      amount: input.amount,
      status: BidStatus.pending,
      createdAt: now,
      notes: sanitizedNotes,
    );
    await bidRef.set(newBid.toJson());
    await _writeNotification(
      NotificationEvent(
        id: _uuid.v4(),
        userId: job.customerId,
        type: 'bid_received',
        title: '${pro.fullName} requested your job',
        body:
            '${pro.fullName} requested your job for PKR ${newBid.amount.toStringAsFixed(0)}',
        sentAt: now,
        metadata: metadataForBid(newBid),
      ),
    );
    await _writeAudit(
      AuditEvent(
        id: _uuid.v4(),
        actorId: input.proId,
        action: 'bid_submitted',
        entityType: 'bid',
        entityId: newBid.id,
        createdAt: now,
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
    _assertCurrentUser(customerId);
    final job = await _loadJob(jobId);
    final bidSnapshot = await _bids.doc(bidId).get();
    if (!bidSnapshot.exists) {
      throw StateError('Job or bid not found.');
    }
    final bid = _bidFromDoc(bidSnapshot);
    if (bid.jobId != jobId) {
      throw StateError('Job or bid not found.');
    }
    if (job.customerId != customerId) {
      throw StateError('Only job owner can accept bid.');
    }

    final now = DateTime.now();
    final allBids = await _bids.where('job_id', isEqualTo: jobId).get();
    final updatedJob = job.copyWith(
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

    final batch = _firestore.batch();
    for (final entry in allBids.docs) {
      final current = _bidFromDoc(entry);
      batch.set(
        entry.reference,
        current
            .copyWith(
              status: entry.id == bidId
                  ? BidStatus.accepted
                  : BidStatus.rejected,
            )
            .toJson(),
      );
    }
    batch.set(_jobs.doc(jobId), updatedJob.toJson());
    final audit = AuditEvent(
      id: _uuid.v4(),
      actorId: customerId,
      action: 'bid_accepted',
      entityType: 'job',
      entityId: jobId,
      createdAt: now,
      metadata: <String, dynamic>{
        'bid_id': bid.id,
        'customer_id': customerId,
        'pro_id': bid.proId,
        'job_title': job.title,
        'amount': bid.amount,
        'accepted_at': now.toIso8601String(),
      },
    );
    final proNotification = NotificationEvent(
      id: _uuid.v4(),
      userId: bid.proId,
      type: 'job_awarded',
      title: 'Job assigned',
      body: job.title,
      sentAt: now,
      metadata: <String, dynamic>{'job_id': jobId},
    );
    final customerNotification = NotificationEvent(
      id: _uuid.v4(),
      userId: job.customerId,
      type: 'bid_accepted',
      title: 'Bid accepted',
      body: 'Your job is now in process.',
      sentAt: now,
      metadata: <String, dynamic>{'job_id': jobId, 'bid_id': bid.id},
    );
    batch.set(_notifications.doc(proNotification.id), proNotification.toJson());
    batch.set(
      _notifications.doc(customerNotification.id),
      customerNotification.toJson(),
    );
    batch.set(_audits.doc(audit.id), audit.toJson());
    await batch.commit();
  }

  @override
  Future<void> updateJobStatus({
    required String jobId,
    required JobStatus status,
    required String actorId,
  }) async {
    _assertCurrentUser(actorId);
    final now = DateTime.now();
    final job = await _loadJob(jobId);
    final batch = _firestore.batch();
    final eventMetadata = <String, dynamic>{};
    final notifications = <NotificationEvent>[];

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
      final pro = await _loadProfileForAccess(proId);
      final completedAmount = job.finalAmount ?? job.fixedPrice;
      final dueIncrease = completedAmount * ProBalanceRules.commissionRate;
      final updatedPro = pro.copyWith(
        totalEarnings: pro.totalEarnings + completedAmount,
        dueToApp: pro.dueToApp + dueIncrease,
        updatedAt: now,
      );
      batch.update(_profiles.doc(proId), <String, dynamic>{
        'total_earnings': updatedPro.totalEarnings,
        'due_to_app': updatedPro.dueToApp,
        'updated_at': now.toIso8601String(),
        '_security_update': _profileSecurityUpdateContext(
          action: 'job_completion_financial',
          actorId: actorId,
          proId: proId,
          jobId: jobId,
        ),
      });
      notifications.addAll(
        _buildDueThresholdNotifications(
          pro: updatedPro,
          previousDue: pro.dueToApp,
          currentDue: updatedPro.dueToApp,
          jobId: jobId,
        ),
      );
      eventMetadata['completed_amount'] = completedAmount;
      eventMetadata['due_added'] = dueIncrease;
      eventMetadata['due_rate'] = ProBalanceRules.commissionRate;
    }

    final updatedJob = job.copyWith(
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
    batch.set(_jobs.doc(jobId), updatedJob.toJson());

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
      notifications.add(
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
      notifications.add(
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

    final audit = AuditEvent(
      id: _uuid.v4(),
      actorId: actorId,
      action: 'job_status_updated',
      entityType: 'job',
      entityId: jobId,
      createdAt: now,
      metadata: <String, dynamic>{'status': status.value},
    );
    for (final notification in notifications) {
      batch.set(_notifications.doc(notification.id), notification.toJson());
    }
    batch.set(_audits.doc(audit.id), audit.toJson());
    await batch.commit();
  }

  @override
  Future<void> requestJobCompletion({
    required String jobId,
    required String proId,
  }) async {
    _assertCurrentUser(proId);
    final job = await _loadJob(jobId);
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
    final updated = job.copyWith(
      updatedAt: now,
      timeline: <JobTimelineEvent>[
        ...job.timeline,
        JobTimelineEvent(type: 'completion_requested', at: now, actorId: proId),
      ],
    );
    final notification = NotificationEvent(
      id: _uuid.v4(),
      userId: job.customerId,
      type: 'completion_requested',
      title: 'Worker marked job as done',
      body: 'Please confirm whether the job is completed.',
      sentAt: now,
      metadata: <String, dynamic>{'job_id': jobId},
    );
    final audit = AuditEvent(
      id: _uuid.v4(),
      actorId: proId,
      action: 'job_completion_requested',
      entityType: 'job',
      entityId: jobId,
      createdAt: now,
    );

    final batch = _firestore.batch();
    batch.set(_jobs.doc(jobId), updated.toJson());
    batch.set(_notifications.doc(notification.id), notification.toJson());
    batch.set(_audits.doc(audit.id), audit.toJson());
    await batch.commit();
  }

  @override
  Future<void> respondToJobCompletion({
    required String jobId,
    required String customerId,
    required bool approved,
    double? rating,
  }) async {
    _assertCurrentUser(customerId);
    final job = await _loadJob(jobId);
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
        final pro = await _loadProfileForAccess(proId);
        final bounded = rating.clamp(1, 5).toDouble();
        final newTotalReviews = pro.totalReviews + 1;
        final newRating =
            ((pro.rating * pro.totalReviews) + bounded) / newTotalReviews;
        final now = DateTime.now();
        final notification = NotificationEvent(
          id: _uuid.v4(),
          userId: proId,
          type: 'job_rated',
          title: 'You received a new rating',
          body:
              'Customer rated your completed job ${bounded.toStringAsFixed(1)} stars.',
          sentAt: now,
          metadata: <String, dynamic>{'job_id': jobId, 'rating': bounded},
        );
        final audit = AuditEvent(
          id: _uuid.v4(),
          actorId: customerId,
          action: 'job_completion_rated',
          entityType: 'job',
          entityId: jobId,
          createdAt: now,
          metadata: <String, dynamic>{'rating': bounded},
        );
        final batch = _firestore.batch();
        batch.update(_profiles.doc(proId), <String, dynamic>{
          'rating': newRating,
          'total_reviews': newTotalReviews,
          'updated_at': now.toIso8601String(),
          '_security_update': _profileSecurityUpdateContext(
            action: 'job_completion_rating',
            actorId: customerId,
            proId: proId,
            jobId: jobId,
          ),
        });
        batch.set(_notifications.doc(notification.id), notification.toJson());
        batch.set(_audits.doc(audit.id), audit.toJson());
        await batch.commit();
      }
      return;
    }

    final now = DateTime.now();
    final updated = job.copyWith(
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
    final notifications = <NotificationEvent>[
      if (job.assignedProId != null)
        NotificationEvent(
          id: _uuid.v4(),
          userId: job.assignedProId!,
          type: 'completion_rejected',
          title: 'Completion was not approved',
          body: 'Customer marked the job as not completed yet.',
          sentAt: now,
          metadata: <String, dynamic>{'job_id': jobId},
        ),
    ];
    final audit = AuditEvent(
      id: _uuid.v4(),
      actorId: customerId,
      action: 'job_completion_rejected',
      entityType: 'job',
      entityId: jobId,
      createdAt: now,
    );
    final batch = _firestore.batch();
    batch.set(_jobs.doc(jobId), updated.toJson());
    for (final notification in notifications) {
      batch.set(_notifications.doc(notification.id), notification.toJson());
    }
    batch.set(_audits.doc(audit.id), audit.toJson());
    await batch.commit();
  }

  @override
  Future<void> startWork({
    required String jobId,
    required String actorId,
  }) async {
    _assertCurrentUser(actorId);
    final job = await _loadJob(jobId);
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
    final updated = job.copyWith(
      updatedAt: now,
      timeline: <JobTimelineEvent>[
        ...job.timeline,
        JobTimelineEvent(type: 'work_started', at: now, actorId: actorId),
      ],
    );
    final notification = NotificationEvent(
      id: _uuid.v4(),
      userId: actorId,
      type: 'work_started',
      title: 'Work started',
      body: job.title,
      sentAt: now,
      metadata: <String, dynamic>{'job_id': jobId},
    );
    final audit = AuditEvent(
      id: _uuid.v4(),
      actorId: actorId,
      action: 'work_started',
      entityType: 'job',
      entityId: jobId,
      createdAt: now,
    );

    final batch = _firestore.batch();
    batch.set(_jobs.doc(jobId), updated.toJson());
    batch.set(_notifications.doc(notification.id), notification.toJson());
    batch.set(_audits.doc(audit.id), audit.toJson());
    await batch.commit();
  }

  @override
  Future<void> cancelJob({
    required String jobId,
    required String actorId,
    required String reason,
  }) async {
    _assertCurrentUser(actorId);
    final sanitizedReason = _sanitizeMultiLine(
      reason,
      field: 'Cancel reason',
      minLength: 3,
      maxLength: 500,
    );
    final job = await _loadJob(jobId);
    final actor = await _loadProfileForAccess(actorId);
    final actorIsAdmin = actor.role == UserRole.admin;
    final canProCancel =
        job.assignedProId == actorId && job.status == JobStatus.inProcess;
    if (!actorIsAdmin && job.customerId != actorId && !canProCancel) {
      throw StateError('Only the job owner can cancel this job.');
    }
    final now = DateTime.now();
    final updated = job.copyWith(
      status: JobStatus.cancelled,
      cancelReason: sanitizedReason,
      updatedAt: now,
      timeline: <JobTimelineEvent>[
        ...job.timeline,
        JobTimelineEvent(
          type: 'cancelled',
          at: now,
          actorId: actorId,
          metadata: <String, dynamic>{'reason': sanitizedReason},
        ),
      ],
    );
    final audit = AuditEvent(
      id: _uuid.v4(),
      actorId: actorId,
      action: 'job_cancelled',
      entityType: 'job',
      entityId: jobId,
      createdAt: now,
      metadata: <String, dynamic>{
        'job_title': job.title,
        'customer_id': job.customerId,
        'pro_id': job.assignedProId,
        'reason': sanitizedReason,
        'cancelled_at': now.toIso8601String(),
      },
    );
    final batch = _firestore.batch();
    batch.set(_jobs.doc(jobId), updated.toJson());
    batch.set(_audits.doc(audit.id), audit.toJson());
    await batch.commit();
  }

  @override
  Future<void> raiseDispute({
    required String jobId,
    required String actorId,
    required String reason,
  }) async {
    _assertCurrentUser(actorId);
    final sanitizedReason = _sanitizeMultiLine(
      reason,
      field: 'Dispute reason',
      minLength: 3,
      maxLength: 500,
    );
    final job = await _loadJob(jobId);
    final actor = await _loadProfileForAccess(actorId);
    final canRaiseDispute =
        job.assignedProId != null &&
        (job.status == JobStatus.inProcess ||
            job.status == JobStatus.completed ||
            job.status == JobStatus.paidClosed);
    final isParticipant =
        actor.role == UserRole.admin ||
        job.customerId == actorId ||
        job.assignedProId == actorId;
    if (!canRaiseDispute) {
      throw StateError(
        'Disputes require an assigned job that is not cancelled or disputed.',
      );
    }
    if (!isParticipant) {
      throw StateError('Only job participants or admins can raise a dispute.');
    }
    final now = DateTime.now();
    final updated = job.copyWith(
      status: JobStatus.disputed,
      disputeReason: sanitizedReason,
      updatedAt: now,
      timeline: <JobTimelineEvent>[
        ...job.timeline,
        JobTimelineEvent(
          type: 'disputed',
          at: now,
          actorId: actorId,
          metadata: <String, dynamic>{'reason': sanitizedReason},
        ),
      ],
    );
    final audit = AuditEvent(
      id: _uuid.v4(),
      actorId: actorId,
      action: 'job_disputed',
      entityType: 'job',
      entityId: jobId,
      createdAt: now,
      metadata: <String, dynamic>{
        'job_title': job.title,
        'customer_id': job.customerId,
        'pro_id': job.assignedProId,
        'reason': sanitizedReason,
        'raised_at': now.toIso8601String(),
      },
    );
    final batch = _firestore.batch();
    batch.set(_jobs.doc(jobId), updated.toJson());
    batch.set(_audits.doc(audit.id), audit.toJson());
    await batch.commit();
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
    _assertCurrentUser(request.customerId);
    if (request.amount <= 0 || request.amount > 1000000000) {
      throw StateError('Invalid payment amount.');
    }
    final sanitizedExternalReference = _sanitizeOptionalSingleLine(
      request.externalReference,
      field: 'External reference',
      maxLength: 120,
    );

    final job = await _loadJob(request.jobId);
    if (job.status != JobStatus.completed) {
      throw StateError('Payment allowed after completed state only.');
    }
    if (job.customerId != request.customerId) {
      throw StateError(
        'Only the customer who owns this job can record payment.',
      );
    }
    if (job.assignedProId != request.proId) {
      throw StateError('Assigned professional does not match payment request.');
    }

    final calc = calculatePaymentForCategory(
      amount: request.amount,
      category: job.category,
    );
    final now = DateTime.now();
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
      recordedAt: now,
      externalReference: sanitizedExternalReference,
    );
    final updatedJob = job.copyWith(
      status: JobStatus.paidClosed,
      finalAmount: request.amount,
      updatedAt: now,
      timeline: <JobTimelineEvent>[
        ...job.timeline,
        JobTimelineEvent(
          type: 'paid_closed',
          at: now,
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
    final proNotification = NotificationEvent(
      id: _uuid.v4(),
      userId: request.proId,
      type: 'payment_received',
      title: 'Payment recorded',
      body: job.title,
      sentAt: now,
      metadata: <String, dynamic>{
        'job_id': request.jobId,
        'payment_id': payment.id,
      },
    );
    final customerNotification = NotificationEvent(
      id: _uuid.v4(),
      userId: request.customerId,
      type: 'job_status_update',
      title: 'Job closed',
      body: job.title,
      sentAt: now,
      metadata: <String, dynamic>{
        'job_id': request.jobId,
        'status': JobStatus.paidClosed.value,
      },
    );
    final audit = AuditEvent(
      id: _uuid.v4(),
      actorId: request.customerId,
      action: 'payment_recorded',
      entityType: 'payment',
      entityId: payment.id,
      createdAt: now,
      metadata: payment.toJson(),
    );

    final batch = _firestore.batch();
    batch.set(_payments.doc(payment.id), payment.toJson());
    batch.set(_jobs.doc(request.jobId), updatedJob.toJson());
    batch.set(_notifications.doc(proNotification.id), proNotification.toJson());
    batch.set(
      _notifications.doc(customerNotification.id),
      customerNotification.toJson(),
    );
    batch.set(_audits.doc(audit.id), audit.toJson());
    _appendFinancialLedgerForPayment(
      batch: batch,
      payment: payment,
      job: job,
      actorId: request.customerId,
      at: now,
    );
    await batch.commit();
    return payment;
  }

  @override
  Future<void> settleProDue({
    required String proId,
    required PaymentMethod method,
    String? externalReference,
  }) async {
    final actorId = _requireCurrentUserId();
    final actor = await _loadProfileForAccess(actorId);
    if (actorId != proId && actor.role != UserRole.admin) {
      throw StateError('Only the pro or an admin can settle this due.');
    }

    final pro = await _loadProfileForAccess(proId);
    if (pro.role != UserRole.pro) {
      throw StateError('Professional account not found.');
    }
    if (pro.dueToApp <= 0) {
      return;
    }

    final sanitizedExternalReference = _sanitizeOptionalSingleLine(
      externalReference,
      field: 'External reference',
      maxLength: 120,
    );
    final now = DateTime.now();
    final paidAmount = pro.dueToApp;
    final notification = NotificationEvent(
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
        ..._externalReferenceMap(sanitizedExternalReference),
      },
    );
    final audit = AuditEvent(
      id: _uuid.v4(),
      actorId: actorId,
      action: 'pro_due_settled',
      entityType: 'pro_balance',
      entityId: proId,
      createdAt: now,
      metadata: <String, dynamic>{
        'amount': paidAmount,
        'method': method.value,
        ..._externalReferenceMap(sanitizedExternalReference),
      },
    );

    final batch = _firestore.batch();
    batch.update(_profiles.doc(proId), <String, dynamic>{
      'due_to_app': 0,
      'updated_at': now.toIso8601String(),
      '_security_update': _profileSecurityUpdateContext(
        action: 'due_settlement',
        actorId: actorId,
        proId: proId,
      ),
    });
    batch.set(_notifications.doc(notification.id), notification.toJson());
    batch.set(_audits.doc(audit.id), audit.toJson());
    _appendFinancialLedgerForDueSettlement(
      batch: batch,
      actorId: actorId,
      proId: proId,
      method: method,
      amount: paidAmount,
      at: now,
      externalReference: sanitizedExternalReference,
    );
    await batch.commit();
  }

  @override
  Stream<List<PaymentRecord>> watchPaymentsForUser(String userId) {
    return _payments.where('customer_id', isEqualTo: userId).snapshots().map((
      snapshot,
    ) {
      final list = snapshot.docs.map(_paymentFromDoc).toList(growable: false);
      list.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      return list;
    });
  }

  @override
  Stream<List<PaymentRecord>> watchPaymentsForPro(String proId) {
    return _payments.where('pro_id', isEqualTo: proId).snapshots().map((
      snapshot,
    ) {
      final list = snapshot.docs.map(_paymentFromDoc).toList(growable: false);
      list.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      return list;
    });
  }

  @override
  Stream<List<PaymentRecord>> watchAllPayments() {
    return _payments.snapshots().map((snapshot) {
      final payments = snapshot.docs
          .map(_paymentFromDoc)
          .toList(growable: false);
      payments.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      return payments;
    });
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String jobId) {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      return Stream<List<ChatMessage>>.error(
        StateError('Sign in before opening a conversation.'),
      );
    }
    return Stream<Job>.fromFuture(_loadJob(jobId)).asyncExpand((job) {
      final assignedProId = job.assignedProId;
      if (assignedProId == null ||
          !job.status.allowsChat ||
          (currentUserId != job.customerId && currentUserId != assignedProId)) {
        return Stream<List<ChatMessage>>.value(const <ChatMessage>[]);
      }
      final customerId = job.customerId;
      final participantFilter = Filter.or(
        Filter.and(
          Filter('sender_id', isEqualTo: customerId),
          Filter('receiver_id', isEqualTo: assignedProId),
        ),
        Filter.and(
          Filter('sender_id', isEqualTo: assignedProId),
          Filter('receiver_id', isEqualTo: customerId),
        ),
      );
      return _messages
          .where('job_id', isEqualTo: jobId)
          .where(participantFilter)
          .snapshots()
          .map((snapshot) {
            final messages = snapshot.docs
                .map(_messageFromDoc)
                .toList(growable: false);
            messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
            return messages;
          });
    });
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
    _assertCurrentUser(senderId);
    final sanitizedMessage = _sanitizeMultiLine(
      text,
      field: 'Message',
      minLength: 1,
      maxLength: 1500,
    );
    final sanitizedReplyToSenderName = _sanitizeOptionalSingleLine(
      replyToSenderName,
      field: 'Reply sender name',
      maxLength: 100,
    );
    final sanitizedReplyToText = _sanitizeOptionalSingleLine(
      replyToText,
      field: 'Reply text',
      maxLength: 280,
    );
    unawaited(_touchUserPresence(senderId));
    final job = await _loadJob(jobId);
    final sender = await _loadProfileForAccess(senderId);
    final assignedProId = job.assignedProId;
    if (assignedProId == null || !job.status.allowsChat) {
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
      text: sanitizedMessage,
      sentAt: now,
      replyToMessageId: replyToMessageId,
      replyToSenderId: replyToSenderId,
      replyToSenderName: sanitizedReplyToSenderName,
      replyToText: sanitizedReplyToText,
    );
    final notification = NotificationEvent(
      id: _uuid.v4(),
      userId: receiverId,
      type: 'message',
      title: sender.fullName,
      body: message.text,
      sentAt: now,
      metadata: <String, dynamic>{
        'job_id': jobId,
        'job_title': job.title,
        'sender_id': senderId,
        'sender_name': sender.fullName,
        'sender_username': _resolvedUsername(sender),
        'sender_avatar_url': sender.profileImageUrl,
        'receiver_id': receiverId,
        'message_id': message.id,
        'navigate_route': '/chat/$jobId/$senderId',
      },
    );
    final audit = AuditEvent(
      id: _uuid.v4(),
      actorId: senderId,
      action: 'message_sent',
      entityType: 'chat_message',
      entityId: message.id,
      createdAt: now,
    );

    final batch = _firestore.batch();
    batch.update(_jobs.doc(jobId), <String, dynamic>{
      'updated_at': now.toIso8601String(),
    });
    batch.set(_messages.doc(message.id), message.toJson());
    batch.set(_notifications.doc(notification.id), notification.toJson());
    batch.set(_audits.doc(audit.id), audit.toJson());
    await batch.commit();
    return message;
  }

  @override
  Future<void> setMessageReaction({
    required String messageId,
    required String userId,
    String? emoji,
  }) async {
    _assertCurrentUser(userId);
    final message = await _loadMessage(messageId);
    if (message.senderId != userId && message.receiverId != userId) {
      throw StateError('Only chat participants can react to this message.');
    }
    final updatedReactions = <String, String>{...message.reactions};
    final normalizedEmoji = emoji?.trim();
    if (normalizedEmoji == null || normalizedEmoji.isEmpty) {
      updatedReactions.remove(userId);
    } else {
      if (normalizedEmoji.length > 16) {
        throw StateError('Reaction is too long.');
      }
      updatedReactions[userId] = normalizedEmoji;
    }
    await _messages.doc(messageId).update(<String, dynamic>{
      'reactions': updatedReactions,
    });
  }

  @override
  Future<void> markMessagesSeen({
    required String jobId,
    required String viewerId,
    required String peerId,
  }) async {
    _assertCurrentUser(viewerId);
    unawaited(_touchUserPresence(viewerId));
    final snapshot = await _messages
        .where('job_id', isEqualTo: jobId)
        .where('receiver_id', isEqualTo: viewerId)
        .where('sender_id', isEqualTo: peerId)
        .get();
    if (snapshot.docs.isEmpty) {
      return;
    }

    final now = DateTime.now().toIso8601String();
    final batch = _firestore.batch();
    var changed = false;
    for (final doc in snapshot.docs) {
      final message = _messageFromDoc(doc);
      if (message.seenAt != null || message.isDeletedForEveryone) {
        continue;
      }
      changed = true;
      batch.update(doc.reference, <String, dynamic>{'seen_at': now});
    }
    if (!changed) {
      return;
    }
    await batch.commit();
  }

  @override
  Future<void> deleteMessageForMe({
    required String messageId,
    required String userId,
  }) async {
    _assertCurrentUser(userId);
    final message = await _loadMessage(messageId);
    if (message.senderId != userId && message.receiverId != userId) {
      throw StateError('Only chat participants can delete this message.');
    }
    final updateColumn = userId == message.senderId
        ? 'deleted_by_sender_at'
        : 'deleted_by_receiver_at';
    await _messages.doc(messageId).update(<String, dynamic>{
      updateColumn: DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> deleteMessageForEveryone({
    required String messageId,
    required String userId,
  }) async {
    _assertCurrentUser(userId);
    final message = await _loadMessage(messageId);
    if (message.senderId != userId) {
      throw StateError('Only sender can delete message for everyone.');
    }
    await _messages.doc(messageId).update(<String, dynamic>{
      'deleted_for_everyone_at': DateTime.now().toIso8601String(),
      'deleted_for_everyone_by': userId,
    });
  }

  @override
  Stream<List<NotificationEvent>> watchNotifications(String userId) {
    return _notifications.where('user_id', isEqualTo: userId).snapshots().map((
      snapshot,
    ) {
      final notifications = snapshot.docs
          .map(_notificationFromDoc)
          .toList(growable: false);
      notifications.sort((a, b) => b.sentAt.compareTo(a.sentAt));
      return notifications;
    });
  }

  @override
  Future<void> markNotificationRead(String notificationId) {
    return _notifications.doc(notificationId).update(<String, dynamic>{
      'read': true,
    });
  }

  @override
  Stream<List<AuditEvent>> watchAuditEvents({
    String? entityType,
    String? entityId,
  }) {
    return _audits.snapshots().map((snapshot) {
      final events = snapshot.docs
          .map(_auditFromDoc)
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
      events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return events;
    });
  }

  @override
  Future<void> addAuditEvent(AuditEvent event) => _writeAudit(event);

  @override
  Stream<List<UserReport>> watchUserReports() {
    return _reports.snapshots().map((snapshot) {
      final reports = snapshot.docs.map(_reportFromDoc).toList(growable: false);
      reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return reports;
    });
  }

  @override
  Future<void> reportUser({
    required String reporterId,
    required String targetUserId,
    required String reasonCode,
    String? details,
  }) async {
    _assertCurrentUser(reporterId);
    final sanitizedReasonCode = _sanitizeSingleLine(
      reasonCode,
      field: 'Reason code',
      minLength: 2,
      maxLength: 60,
    );
    final sanitizedDetails = _sanitizeOptionalSingleLine(
      details,
      field: 'Report details',
      maxLength: 500,
    );
    final report = UserReport(
      id: _uuid.v4(),
      reporterId: reporterId,
      targetUserId: targetUserId,
      reasonCode: sanitizedReasonCode,
      details: sanitizedDetails,
      createdAt: DateTime.now(),
    );
    await _reports.doc(report.id).set(report.toJson());
    await _writeAudit(
      AuditEvent(
        id: _uuid.v4(),
        actorId: reporterId,
        action: 'user_reported',
        entityType: 'user',
        entityId: targetUserId,
        createdAt: DateTime.now(),
        metadata: <String, dynamic>{
          'reason_code': sanitizedReasonCode,
          if (sanitizedDetails != null && sanitizedDetails.isNotEmpty)
            'details': sanitizedDetails,
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
    final sanitizedReason = _sanitizeMultiLine(
      reason,
      field: 'Block reason',
      minLength: 3,
      maxLength: 300,
    );
    await _requireAdminPermission(
      actorId,
      AdminPermission.manageUsers,
      anyOf: <AdminPermission>[AdminPermission.manageReports],
    );
    final user = await _loadProfileForAccess(targetUserId);
    final updated = user.copyWith(blocked: blocked, updatedAt: DateTime.now());
    await _profiles.doc(targetUserId).set(updated.toJson());
    await _writeAudit(
      AuditEvent(
        id: _uuid.v4(),
        actorId: actorId,
        action: blocked ? 'user_blocked' : 'user_unblocked',
        entityType: 'user',
        entityId: targetUserId,
        createdAt: DateTime.now(),
        metadata: <String, dynamic>{'reason': sanitizedReason},
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
    await _requireAdminPermission(actorId, AdminPermission.manageAdminAccess);
    final target = await _loadProfileForAccess(targetUserId);
    if (target.role != UserRole.admin) {
      throw StateError('Target admin user not found.');
    }
    final assignedPermissions = permissions.isEmpty
        ? defaultAdminPermissionsForRank(rank)
        : permissions.toSet().toList(growable: false);
    final updated = target.copyWith(
      adminRank: rank,
      adminPermissions: assignedPermissions,
      updatedAt: DateTime.now(),
    );
    await _profiles.doc(targetUserId).set(updated.toJson());
    await _writeAudit(
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
    final paymentSnapshot = await _payments
        .where('pro_id', isEqualTo: proId)
        .get();
    final payments = paymentSnapshot.docs
        .map(_paymentFromDoc)
        .where((payment) => payment.state == PaymentState.completed)
        .toList(growable: false);

    final profile = await _loadProfileForAccess(proId);
    if (profile.role != UserRole.pro) {
      throw StateError('Professional account not found.');
    }

    final jobSnapshot = await _jobs
        .where('assigned_pro_id', isEqualTo: proId)
        .get();
    final completedJobs = jobSnapshot.docs
        .map(_jobFromDoc)
        .where(
          (job) =>
              job.status == JobStatus.completed ||
              job.status == JobStatus.paidClosed,
        )
        .toList(growable: false);

    final now = DateTime.now();
    double sum(Iterable<double> values) =>
        values.fold<double>(0, (total, value) => total + value);

    DateTime completionTime(Job job) {
      for (final event in job.timeline.reversed) {
        if (event.type == JobStatus.completed.value) {
          return event.at;
        }
      }
      return job.updatedAt;
    }

    double amountFor(Job job) => job.finalAmount ?? job.fixedPrice;

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
    final online = sum(
      payments
          .where((payment) => payment.method != PaymentMethod.cash)
          .map((payment) => payment.netProAmount),
    );
    final cash = sum(
      payments
          .where((payment) => payment.method == PaymentMethod.cash)
          .map((payment) => payment.netProAmount),
    );
    final platformFees = sum(payments.map((payment) => payment.platformFee));

    return ProEarningsSummary(
      today: today,
      month: month,
      lifetime: profile.totalEarnings,
      online: online,
      cash: cash,
      platformFees: platformFees,
      totalJobs: completedJobs.length,
      averageRating: profile.rating,
      totalReviews: profile.totalReviews,
      totalEarnings: profile.totalEarnings,
      dueToApp: profile.dueToApp,
    );
  }

  @override
  Future<AdminMetrics> fetchAdminMetrics() async {
    final now = DateTime.now();
    final since24h = now.subtract(const Duration(hours: 24));
    final results =
        await Future.wait(<Future<QuerySnapshot<Map<String, dynamic>>>>[
          _profiles.get(),
          _jobs.get(),
          _payments.get(),
          _reports.get(),
          _messages.get(),
          _audits.get(),
        ]);

    final profiles = results[0].docs.map(_userFromDoc).toList(growable: false);
    final jobs = results[1].docs.map(_jobFromDoc).toList(growable: false);
    final payments = results[2].docs
        .map(_paymentFromDoc)
        .toList(growable: false);
    final reports = results[3].docs.map(_reportFromDoc).toList(growable: false);
    final messages = results[4].docs
        .map(_messageFromDoc)
        .toList(growable: false);
    final audits = results[5].docs.map(_auditFromDoc).toList(growable: false);
    final financeSummarySnapshot = await _financialSummary.doc('overall').get();
    final financeSummary = financeSummarySnapshot.data() ?? <String, dynamic>{};

    double sum(Iterable<double> values) =>
        values.fold<double>(0, (total, value) => total + value);

    final reviewedReportIds = audits
        .where(
          (event) =>
              event.entityType == 'report' && event.action == 'report_reviewed',
        )
        .map((event) => event.entityId)
        .toSet();

    final onlineVolume = sum(
      payments
          .where((payment) => payment.method != PaymentMethod.cash)
          .map((payment) => payment.grossAmount),
    );
    final cashVolume = sum(
      payments
          .where((payment) => payment.method == PaymentMethod.cash)
          .map((payment) => payment.grossAmount),
    );
    final platformRevenue = sum(payments.map((payment) => payment.platformFee));
    final grossRevenue = onlineVolume + cashVolume;
    final totalDueSettled =
        (financeSummary['total_due_settled'] as num?)?.toDouble() ?? 0;
    final estimatedProfit =
        (financeSummary['total_estimated_profit'] as num?)?.toDouble() ??
        platformRevenue;

    return AdminMetrics(
      totalCustomers: profiles
          .where((profile) => profile.role == UserRole.customer)
          .length,
      totalPros: profiles
          .where((profile) => profile.role == UserRole.pro)
          .length,
      totalAdmins: profiles
          .where((profile) => profile.role == UserRole.admin)
          .length,
      verifiedPros: profiles
          .where(
            (profile) => profile.role == UserRole.pro && profile.cnicVerified,
          )
          .length,
      totalJobs: jobs.length,
      activeJobs: jobs.where((job) => job.status == JobStatus.inProcess).length,
      completedJobs: jobs
          .where(
            (job) =>
                job.status == JobStatus.completed ||
                job.status == JobStatus.paidClosed,
          )
          .length,
      cancelledJobs: jobs
          .where((job) => job.status == JobStatus.cancelled)
          .length,
      activeDisputes: jobs
          .where((job) => job.status == JobStatus.disputed)
          .length,
      totalReports: reports.length,
      openReports: reports
          .where((report) => !reviewedReportIds.contains(report.id))
          .length,
      messages24h: messages
          .where((message) => message.sentAt.isAfter(since24h))
          .length,
      audits24h: audits
          .where((audit) => audit.createdAt.isAfter(since24h))
          .length,
      onlineVolume: onlineVolume,
      cashVolume: cashVolume,
      platformRevenue: platformRevenue,
      grossRevenue: grossRevenue,
      totalDueSettled: totalDueSettled,
      estimatedProfit: estimatedProfit,
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
    await _requireAdminPermission(actorId, AdminPermission.manageCommissions);
    if (rate < 0 || rate > 1) {
      throw StateError('Rate should be between 0 and 1.');
    }
    _commissionRate = rate;
    for (final category in JobCategory.values) {
      _categoryCommissionRates[category] = rate;
    }
    _paymentCalculator = PaymentCalculator(rate);
    await _settings.doc('commission_rate').set(<String, dynamic>{
      'key': 'commission_rate',
      'value': rate,
      'updated_at': DateTime.now().toIso8601String(),
    });
    await _writeAudit(
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
    await _requireAdminPermission(actorId, AdminPermission.manageCommissions);
    if (rate < 0 || rate > 1) {
      throw StateError('Rate should be between 0 and 1.');
    }
    _categoryCommissionRates[category] = rate;
    final payload = <String, dynamic>{
      for (final entry in _categoryCommissionRates.entries)
        entry.key.value: entry.value,
    };
    await _settings.doc('commission_rate_by_category').set(<String, dynamic>{
      'key': 'commission_rate_by_category',
      'value': payload,
      'updated_at': DateTime.now().toIso8601String(),
    });
    await _writeAudit(
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

  @override
  void dispose() {
    _commissionRateSubscription?.cancel();
    _categoryCommissionSubscription?.cancel();
  }
}
