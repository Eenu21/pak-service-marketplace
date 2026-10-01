import 'dart:async';

// ignore_for_file: use_null_aware_elements

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/device_context_service.dart';
import '../../core/services/payment_calculator.dart';
import '../../core/services/pro_balance_rules.dart';
import '../../domain/models.dart';
import 'marketplace_repository.dart';

class SupabaseMarketplaceRepository implements MarketplaceRepository {
  SupabaseMarketplaceRepository({
    required SupabaseClient client,
    required double initialCommissionRate,
  }) : _client = client,
       _commissionRate = initialCommissionRate,
       _categoryCommissionRates = <JobCategory, double>{
         for (final category in JobCategory.values)
           category: initialCommissionRate,
       },
       _paymentCalculator = PaymentCalculator(initialCommissionRate);

  final SupabaseClient _client;
  final _uuid = const Uuid();
  final String _sessionId = const Uuid().v4();
  late PaymentCalculator _paymentCalculator;
  double _commissionRate;
  final Map<JobCategory, double> _categoryCommissionRates;

  Future<AppUser> _loadProfileForAccess(String userId) async {
    final row = await _client
        .from('profiles')
        .select('id,role,full_name,email,phone,admin_rank,admin_permissions')
        .eq('id', userId)
        .maybeSingle();
    if (row == null) {
      throw StateError('User not found.');
    }
    final map = Map<String, dynamic>.from(row);
    return AppUser.fromJson(<String, dynamic>{
      'id': map['id'],
      'role': map['role'],
      'full_name': map['full_name'] ?? '',
      'email': map['email'] ?? '',
      'phone': map['phone'] ?? '',
      'admin_rank': map['admin_rank'],
      'admin_permissions': map['admin_permissions'] ?? <dynamic>[],
    });
  }

  Future<void> _requireAdminPermission(
    String actorId,
    AdminPermission requiredPermission, {
    List<AdminPermission> anyOf = const <AdminPermission>[],
  }) async {
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

  Map<String, dynamic> _profileWriteMap(
    AppUser user, {
    required bool includeFinancials,
  }) {
    return <String, dynamic>{
      'id': user.id,
      'role': user.role.value,
      'full_name': user.fullName,
      'email': user.email,
      'phone': user.phone,
      'admin_rank': user.adminRank?.value,
      'admin_permissions': user.adminPermissions
          .map((permission) => permission.value)
          .toList(growable: false),
      'profile_image_url': user.profileImageUrl,
      'language_code': user.languageCode,
      'cnic_verified': user.cnicVerified,
      'police_verified': user.policeVerified,
      'rating': user.rating,
      'total_reviews': user.totalReviews,
      'notifications_enabled': user.notificationsEnabled,
      'precise_location_enabled': user.preciseLocationEnabled,
      'payment_account': user.paymentAccount,
      'blocked': user.blocked,
      'preferred_categories': user.preferredCategories
          .map((category) => category.value)
          .toList(growable: false),
      'created_at': user.createdAt?.toIso8601String(),
      'updated_at': user.updatedAt?.toIso8601String(),
      if (includeFinancials) ...<String, dynamic>{
        'total_earnings': user.totalEarnings,
        'due_to_app': user.dueToApp,
      },
    };
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
    StreamSubscription<AuthState>? authSub;
    StreamSubscription<List<Map<String, dynamic>>>? profileSub;
    StreamSubscription<List<Map<String, dynamic>>>? savedLocationsSub;

    Future<void> emitCurrentUser(String userId) async {
      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (profile == null) {
        controller.add(null);
        return;
      }
      final terms = await _client
          .from('terms_acceptances')
          .select()
          .eq('user_id', userId);
      final savedLocations = await _client
          .from('saved_locations')
          .select()
          .eq('user_id', userId);
      final enriched = Map<String, dynamic>.from(profile);
      enriched['terms_acceptance_history'] = terms;
      enriched['saved_locations'] = savedLocations;
      controller.add(AppUser.fromJson(enriched));
    }

    Future<void> attachProfileStream(String? userId) async {
      await profileSub?.cancel();
      profileSub = null;
      await savedLocationsSub?.cancel();
      savedLocationsSub = null;
      if (userId == null) {
        controller.add(null);
        return;
      }
      try {
        await emitCurrentUser(userId);
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      }
      profileSub = _client
          .from('profiles')
          .stream(primaryKey: <String>['id'])
          .eq('id', userId)
          .listen((rows) {
            if (rows.isEmpty) {
              controller.add(null);
              return;
            }
            emitCurrentUser(userId).catchError(
              (error, stackTrace) => controller.addError(error, stackTrace),
            );
          }, onError: controller.addError);
      savedLocationsSub = _client
          .from('saved_locations')
          .stream(primaryKey: <String>['id'])
          .eq('user_id', userId)
          .listen(
            (_) => emitCurrentUser(userId).catchError(
              (error, stackTrace) => controller.addError(error, stackTrace),
            ),
            onError: controller.addError,
          );
    }

    controller = StreamController<AppUser?>(
      onListen: () async {
        await attachProfileStream(_client.auth.currentUser?.id);
        authSub = _client.auth.onAuthStateChange.listen((_) async {
          await attachProfileStream(_client.auth.currentUser?.id);
        }, onError: controller.addError);
      },
      onCancel: () async {
        await authSub?.cancel();
        await profileSub?.cancel();
        await savedLocationsSub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<AppUser?> getCurrentUser() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      return null;
    }
    final profile = await _client
        .from('profiles')
        .select()
        .eq('id', authUser.id)
        .maybeSingle();
    if (profile == null) {
      return null;
    }
    final terms = await _client
        .from('terms_acceptances')
        .select()
        .eq('user_id', authUser.id);
    final savedLocations = await _client
        .from('saved_locations')
        .select()
        .eq('user_id', authUser.id);
    final enriched = Map<String, dynamic>.from(profile);
    enriched['terms_acceptance_history'] = terms;
    enriched['saved_locations'] = savedLocations;
    return AppUser.fromJson(enriched);
  }

  @override
  Future<AppUser> register(RegisterInput input) async {
    if (!input.acceptance.checkboxConfirmed) {
      throw StateError('Terms and Privacy acceptance is required.');
    }
    input.validateForRole(input.role);
    final preferredCategories = input.normalizedPreferredCategoriesForRole(
      input.role,
    );
    final response = await _client.auth.signUp(
      email: input.email.trim(),
      password: input.password,
      data: <String, dynamic>{'role': input.role.value},
    );
    final authUser = response.user;
    if (authUser == null) {
      throw StateError('Sign up failed.');
    }

    final profile = AppUser(
      id: authUser.id,
      role: input.role,
      fullName: input.fullName.trim(),
      email: input.email.trim().toLowerCase(),
      phone: input.phone.trim(),
      preferredCategories: preferredCategories,
      termsAcceptanceHistory: <TermsAcceptance>[input.acceptance],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _client
        .from('profiles')
        .insert(_profileWriteMap(profile, includeFinancials: true));
    await _client.from('terms_acceptances').insert(<String, dynamic>{
      'id': _uuid.v4(),
      'user_id': authUser.id,
      ...input.acceptance.toJson(),
    });

    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: authUser.id,
        action: 'register',
        entityType: 'user',
        entityId: authUser.id,
        createdAt: DateTime.now(),
        ipAddress: input.acceptance.ipAddress,
        deviceInfo: input.acceptance.deviceInfo,
        metadata: <String, dynamic>{
          'terms_version': input.acceptance.termsVersion,
          'privacy_version': input.acceptance.privacyVersion,
        },
      ),
    );

    return profile;
  }

  @override
  Future<AppUser> signIn(LoginInput input) async {
    await _client.auth.signInWithPassword(
      email: input.email.trim(),
      password: input.password,
    );
    final user = await getCurrentUser();
    if (user == null) {
      throw StateError('User profile is not available.');
    }
    await _recordAuthSessionEvent(userId: user.id, action: 'login');
    return user;
  }

  @override
  Future<void> signOut() async {
    final userId = _client.auth.currentUser?.id;
    if (userId != null) {
      await _recordAuthSessionEvent(userId: userId, action: 'logout');
    }
    await _client.auth.signOut();
  }

  Future<void> _recordAuthSessionEvent({
    required String userId,
    required String action,
  }) async {
    try {
      await addAuditEvent(
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
      debugPrint('Skipping Supabase auth session audit: $error');
    }
  }

  @override
  Future<void> updateProfile(AppUser user) async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      throw StateError('Not authenticated.');
    }
    final currentId = authUser.id;
    final currentProfile = await _client
        .from('profiles')
        .select()
        .eq('id', currentId)
        .maybeSingle();
    if (currentProfile == null) {
      throw StateError('User not found.');
    }
    final merged = AppUser.fromJson(Map<String, dynamic>.from(currentProfile))
        .copyWith(
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
    await _client
        .from('profiles')
        .update(_profileWriteMap(merged, includeFinancials: false))
        .eq('id', currentId);
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: currentId,
        action: 'profile_updated',
        entityType: 'user',
        entityId: currentId,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<AppUser> upgradeToProfessional({
    required List<JobCategory> preferredCategories,
  }) async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      throw StateError('Not authenticated.');
    }
    final categories = preferredCategories.toSet().toList(growable: false);
    if (categories.isEmpty) {
      throw StateError('Select at least one service category.');
    }
    final profile = await _client
        .from('profiles')
        .select()
        .eq('id', authUser.id)
        .maybeSingle();
    if (profile == null) {
      throw StateError('User not found.');
    }
    final current = AppUser.fromJson(Map<String, dynamic>.from(profile));
    if (current.role == UserRole.admin) {
      throw StateError(
        'Admin accounts cannot be converted to professional accounts.',
      );
    }
    final upgraded = current.copyWith(
      role: UserRole.pro,
      preferredCategories: categories,
      updatedAt: DateTime.now(),
    );
    await _client
        .from('profiles')
        .update(_profileWriteMap(upgraded, includeFinancials: false))
        .eq('id', authUser.id);
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: authUser.id,
        action: 'pro_profile_activated',
        entityType: 'user',
        entityId: authUser.id,
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
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  @override
  Stream<List<AppUser>> watchAllUsers({bool includeLocations = false}) {
    return _client.from('profiles').stream(primaryKey: <String>['id']).asyncMap((
      rows,
    ) async {
      final profiles = rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
      if (profiles.isEmpty) {
        return const <AppUser>[];
      }

      final groupedLocations = <String, List<SavedLocation>>{};
      if (includeLocations) {
        final userIds = profiles
            .where(
              (profile) =>
                  (profile['role'] as String? ?? UserRole.customer.value) ==
                  UserRole.pro.value,
            )
            .map((profile) => profile['id'] as String)
            .toList(growable: false);
        if (userIds.isNotEmpty) {
          try {
            final locationRows = await _client
                .from('saved_locations')
                .select()
                .inFilter('user_id', userIds);
            for (final row in (locationRows as List<dynamic>)) {
              final map = Map<String, dynamic>.from(row as Map);
              final userId = map['user_id'] as String;
              groupedLocations
                  .putIfAbsent(userId, () => <SavedLocation>[])
                  .add(SavedLocation.fromJson(map));
            }
          } catch (_) {
            // Location visibility can be restricted by RLS; continue with profile data.
          }
        }
      }

      return profiles
          .map((profile) {
            final enriched = Map<String, dynamic>.from(profile);
            if (includeLocations) {
              final userId = profile['id'] as String;
              enriched['saved_locations'] =
                  (groupedLocations[userId] ?? <SavedLocation>[])
                      .map((location) => location.toJson())
                      .toList(growable: false);
            }
            return AppUser.fromJson(enriched);
          })
          .toList(growable: false);
    });
  }

  @override
  Future<void> verifyPro({
    required String userId,
    required bool cnicVerified,
    required bool policeVerified,
  }) async {
    final actorId = _client.auth.currentUser?.id;
    if (actorId == null) {
      throw StateError('Not authenticated.');
    }
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
    await _client
        .from('profiles')
        .update(<String, dynamic>{
          'cnic_verified': cnicVerified,
          'police_verified': policeVerified,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);
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
    await _client.from('saved_locations').insert(<String, dynamic>{
      ...location.toJson(),
      'user_id': userId,
    });
  }

  @override
  Stream<List<Job>> watchNearbyJobs({
    required JobCategory category,
    required double latitude,
    required double longitude,
    double radiusKm = 25,
  }) {
    return _client
        .from('jobs')
        .stream(primaryKey: <String>['id'])
        .eq('category', category.value)
        .map((rows) {
          final jobs = rows
              .map((row) => Job.fromJson(Map<String, dynamic>.from(row)))
              .toList(growable: false);
          final nearby = jobs
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
          nearby.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return nearby;
        });
  }

  @override
  Stream<List<Job>> watchJobsForUser(String userId) {
    return _client
        .from('jobs')
        .stream(primaryKey: <String>['id'])
        .eq('customer_id', userId)
        .map(
          (rows) => rows
              .map((row) => Job.fromJson(Map<String, dynamic>.from(row)))
              .toList(growable: false),
        );
  }

  @override
  Stream<List<Job>> watchJobsForPro(String proId) {
    return _client
        .from('jobs')
        .stream(primaryKey: <String>['id'])
        .eq('assigned_pro_id', proId)
        .map((rows) {
          final jobs = rows
              .map((row) => Job.fromJson(Map<String, dynamic>.from(row)))
              .toList(growable: false);
          jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return jobs;
        });
  }

  @override
  Stream<List<Job>> watchAllJobs() {
    return _client.from('jobs').stream(primaryKey: <String>['id']).map((rows) {
      final jobs = rows
          .map((row) => Job.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false);
      jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return jobs;
    });
  }

  @override
  Stream<Job?> watchJob(String jobId) {
    Stream<Job?> realtime() {
      return _client
          .from('jobs')
          .stream(primaryKey: <String>['id'])
          .eq('id', jobId)
          .map((rows) {
            if (rows.isEmpty) {
              return null;
            }
            return Job.fromJson(Map<String, dynamic>.from(rows.first));
          });
    }

    return (() async* {
      final initial = await _client
          .from('jobs')
          .select()
          .eq('id', jobId)
          .maybeSingle();
      if (initial == null) {
        yield null;
      } else {
        yield Job.fromJson(Map<String, dynamic>.from(initial));
      }
      yield* realtime();
    })();
  }

  @override
  Stream<List<Bid>> watchBids(String jobId) {
    Stream<List<Bid>> realtime() {
      return _client
          .from('bids')
          .stream(primaryKey: <String>['id'])
          .eq('job_id', jobId)
          .map(
            (rows) => rows
                .map((row) => Bid.fromJson(Map<String, dynamic>.from(row)))
                .toList(growable: false),
          );
    }

    return (() async* {
      final initialRows = await _client
          .from('bids')
          .select()
          .eq('job_id', jobId);
      final initial = (initialRows as List<dynamic>)
          .map((row) => Bid.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(growable: false);
      yield initial;
      yield* realtime();
    })();
  }

  @override
  Future<Job> postJob(JobPostInput input) async {
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
    await _client.from('jobs').insert(job.toJson());
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
    final authId = _client.auth.currentUser?.id;
    if (authId == null || authId != input.actorId) {
      throw StateError('Not authenticated.');
    }
    if (input.fixedPrice <= 0) {
      throw StateError('Price must be positive.');
    }
    if (input.title.trim().isEmpty ||
        input.description.trim().isEmpty ||
        input.maskedAddress.trim().isEmpty ||
        input.exactAddress.trim().isEmpty) {
      throw StateError('All job details are required.');
    }

    final row = await _client
        .from('jobs')
        .select()
        .eq('id', input.jobId)
        .maybeSingle();
    if (row == null) {
      throw StateError('Job not found.');
    }
    final job = Job.fromJson(Map<String, dynamic>.from(row));
    final actor = await _loadProfileForAccess(input.actorId);
    final actorIsAdmin = actor.role == UserRole.admin;
    if (!actorIsAdmin && job.customerId != input.actorId) {
      throw StateError('Only the customer who posted this job can edit it.');
    }
    if (job.status != JobStatus.available && job.status != JobStatus.posted) {
      throw StateError('Job can only be edited while it is still open.');
    }

    final now = DateTime.now();
    await _client
        .from('jobs')
        .update(<String, dynamic>{
          'title': input.title.trim(),
          'description': input.description.trim(),
          'fixed_price': input.fixedPrice,
          'latitude': input.latitude,
          'longitude': input.longitude,
          'masked_address': input.maskedAddress.trim(),
          'exact_address': input.exactAddress.trim(),
          'updated_at': now.toIso8601String(),
          'timeline': <Map<String, dynamic>>[
            ...job.timeline.map((event) => event.toJson()),
            JobTimelineEvent(
              type: 'details_updated',
              at: now,
              actorId: input.actorId,
            ).toJson(),
          ],
        })
        .eq('id', input.jobId);

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
    final proRow = await _client
        .from('profiles')
        .select('id,role,due_to_app,preferred_categories')
        .eq('id', input.proId)
        .maybeSingle();
    if (proRow == null || proRow['role'] != UserRole.pro.value) {
      throw StateError('Professional account not found.');
    }
    final preferredRaw =
        (proRow['preferred_categories'] as List<dynamic>? ?? <dynamic>[])
            .map((value) => value.toString())
            .toSet();
    final due = (proRow['due_to_app'] as num?)?.toDouble() ?? 0;
    if (ProBalanceRules.isLocked(due)) {
      throw StateError(
        'Account locked. Please clear your due to continue bidding.',
      );
    }
    final jobRow = await _client
        .from('jobs')
        .select('status,category')
        .eq('id', input.jobId)
        .maybeSingle();
    final status = JobStatusX.fromValue(jobRow?['status'] as String? ?? '');
    if (jobRow == null ||
        (status != JobStatus.available && status != JobStatus.posted)) {
      throw StateError('Job is not open for bids.');
    }
    final jobCategory = JobCategoryX.fromValue(
      jobRow['category'] as String? ?? '',
    );
    if (!preferredRaw.contains(jobCategory.value)) {
      throw StateError(
        'You can only bid on jobs that match your registered categories.',
      );
    }
    final existingRows = await _client
        .from('bids')
        .select()
        .eq('job_id', input.jobId)
        .eq('pro_id', input.proId)
        .order('created_at', ascending: false)
        .limit(1);
    final existingList = (existingRows as List<dynamic>)
        .map((row) => Bid.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
    if (existingList.isNotEmpty) {
      final latest = existingList.first;
      if (latest.status != BidStatus.pending) {
        throw StateError('Bid is already finalized and cannot be edited.');
      }
      final updatedBid = Bid(
        id: latest.id,
        jobId: latest.jobId,
        proId: latest.proId,
        amount: input.amount,
        status: BidStatus.pending,
        createdAt: DateTime.now(),
        notes: input.notes,
      );
      await _client
          .from('bids')
          .update(<String, dynamic>{
            'amount': updatedBid.amount,
            'created_at': updatedBid.createdAt.toIso8601String(),
            'notes': updatedBid.notes,
            'status': BidStatus.pending.value,
          })
          .eq('id', updatedBid.id);
      return updatedBid;
    }

    final newBid = Bid(
      id: _uuid.v4(),
      jobId: input.jobId,
      proId: input.proId,
      amount: input.amount,
      status: BidStatus.pending,
      createdAt: DateTime.now(),
      notes: input.notes,
    );
    await _client.from('bids').insert(newBid.toJson());
    return newBid;
  }

  @override
  Future<void> acceptBid({
    required String jobId,
    required String bidId,
    required String customerId,
  }) async {
    final selected = await _client
        .from('bids')
        .select()
        .eq('id', bidId)
        .maybeSingle();
    if (selected == null) {
      throw StateError('Bid not found.');
    }
    final selectedBid = Bid.fromJson(Map<String, dynamic>.from(selected));
    final currentJob = await _client
        .from('jobs')
        .select()
        .eq('id', jobId)
        .single();
    final job = Job.fromJson(Map<String, dynamic>.from(currentJob));

    await _client
        .from('bids')
        .update(<String, dynamic>{'status': BidStatus.rejected.value})
        .eq('job_id', jobId);
    await _client
        .from('bids')
        .update(<String, dynamic>{'status': BidStatus.accepted.value})
        .eq('id', bidId);
    await _client
        .from('jobs')
        .update(<String, dynamic>{
          'assigned_pro_id': selectedBid.proId,
          'selected_bid_id': bidId,
          'final_amount': selectedBid.amount,
          'status': JobStatus.inProcess.value,
          'updated_at': DateTime.now().toIso8601String(),
          'timeline': <Map<String, dynamic>>[
            ...job.timeline.map((event) => event.toJson()),
            JobTimelineEvent(
              type: 'bid_accepted',
              at: DateTime.now(),
              actorId: customerId,
            ).toJson(),
            JobTimelineEvent(
              type: 'in_process',
              at: DateTime.now(),
              actorId: selectedBid.proId,
            ).toJson(),
          ],
        })
        .eq('id', jobId);
  }

  @override
  Future<void> updateJobStatus({
    required String jobId,
    required JobStatus status,
    required String actorId,
  }) async {
    final row = await _client.from('jobs').select().eq('id', jobId).single();
    final job = Job.fromJson(Map<String, dynamic>.from(row));
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
      final profileRow = await _client
          .from('profiles')
          .select('total_earnings,due_to_app')
          .eq('id', proId)
          .maybeSingle();
      final currentTotal =
          (profileRow?['total_earnings'] as num?)?.toDouble() ?? 0;
      final currentDue = (profileRow?['due_to_app'] as num?)?.toDouble() ?? 0;
      await _client
          .from('profiles')
          .update(<String, dynamic>{
            'total_earnings': currentTotal + completedAmount,
            'due_to_app': currentDue + dueIncrease,
            'updated_at': now.toIso8601String(),
          })
          .eq('id', proId);
      eventMetadata['completed_amount'] = completedAmount;
      eventMetadata['due_added'] = dueIncrease;
      eventMetadata['due_rate'] = ProBalanceRules.commissionRate;
    }

    await _client
        .from('jobs')
        .update(<String, dynamic>{
          'status': status.value,
          'updated_at': now.toIso8601String(),
          'timeline': <Map<String, dynamic>>[
            ...job.timeline.map((event) => event.toJson()),
            JobTimelineEvent(
              type: status.value,
              at: now,
              actorId: actorId,
              metadata: eventMetadata,
            ).toJson(),
          ],
        })
        .eq('id', jobId);
  }

  @override
  Future<void> requestJobCompletion({
    required String jobId,
    required String proId,
  }) async {
    final row = await _client.from('jobs').select().eq('id', jobId).single();
    final job = Job.fromJson(Map<String, dynamic>.from(row));
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
    await _client
        .from('jobs')
        .update(<String, dynamic>{
          'updated_at': now.toIso8601String(),
          'timeline': <Map<String, dynamic>>[
            ...job.timeline.map((event) => event.toJson()),
            JobTimelineEvent(
              type: 'completion_requested',
              at: now,
              actorId: proId,
            ).toJson(),
          ],
        })
        .eq('id', jobId);
    try {
      await _client.from('notifications').insert(<String, dynamic>{
        'id': _uuid.v4(),
        'user_id': job.customerId,
        'type': 'completion_requested',
        'title': 'Worker marked job as done',
        'body': 'Please confirm whether the job is completed.',
        'sent_at': now.toIso8601String(),
        'metadata': <String, dynamic>{'job_id': jobId},
        'read': false,
      });
    } catch (_) {
      // Ignore notification failures.
    }
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
    final row = await _client.from('jobs').select().eq('id', jobId).single();
    final job = Job.fromJson(Map<String, dynamic>.from(row));
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
        final bounded = rating.clamp(1, 5).toDouble();
        final profile = await _client
            .from('profiles')
            .select('rating,total_reviews')
            .eq('id', proId)
            .maybeSingle();
        final currentRating = (profile?['rating'] as num?)?.toDouble() ?? 0;
        final currentReviews = (profile?['total_reviews'] as int?) ?? 0;
        final newTotalReviews = currentReviews + 1;
        final newRating =
            ((currentRating * currentReviews) + bounded) / newTotalReviews;
        await _client
            .from('profiles')
            .update(<String, dynamic>{
              'rating': newRating,
              'total_reviews': newTotalReviews,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', proId);
        try {
          await _client.from('notifications').insert(<String, dynamic>{
            'id': _uuid.v4(),
            'user_id': proId,
            'type': 'job_rated',
            'title': 'You received a new rating',
            'body':
                'Customer rated your completed job ${bounded.toStringAsFixed(1)} stars.',
            'sent_at': DateTime.now().toIso8601String(),
            'metadata': <String, dynamic>{'job_id': jobId, 'rating': bounded},
            'read': false,
          });
        } catch (_) {
          // Ignore notification failures.
        }
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
      return;
    }

    final now = DateTime.now();
    await _client
        .from('jobs')
        .update(<String, dynamic>{
          'updated_at': now.toIso8601String(),
          'timeline': <Map<String, dynamic>>[
            ...job.timeline.map((event) => event.toJson()),
            JobTimelineEvent(
              type: 'completion_rejected',
              at: now,
              actorId: customerId,
            ).toJson(),
          ],
        })
        .eq('id', jobId);
    final proId = job.assignedProId;
    if (proId != null) {
      try {
        await _client.from('notifications').insert(<String, dynamic>{
          'id': _uuid.v4(),
          'user_id': proId,
          'type': 'completion_rejected',
          'title': 'Completion was not approved',
          'body': 'Customer marked the job as not completed yet.',
          'sent_at': now.toIso8601String(),
          'metadata': <String, dynamic>{'job_id': jobId},
          'read': false,
        });
      } catch (_) {
        // Ignore notification failures.
      }
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
    final row = await _client.from('jobs').select().eq('id', jobId).single();
    final job = Job.fromJson(Map<String, dynamic>.from(row));
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
    await _client
        .from('jobs')
        .update(<String, dynamic>{
          'updated_at': now.toIso8601String(),
          'timeline': <Map<String, dynamic>>[
            ...job.timeline.map((event) => event.toJson()),
            JobTimelineEvent(
              type: 'work_started',
              at: now,
              actorId: actorId,
            ).toJson(),
          ],
        })
        .eq('id', jobId);
    try {
      await _client.from('notifications').insert(<String, dynamic>{
        'id': _uuid.v4(),
        'user_id': actorId,
        'type': 'work_started',
        'title': 'Work started',
        'body': job.title,
        'sent_at': now.toIso8601String(),
        'metadata': <String, dynamic>{'job_id': jobId},
        'read': false,
      });
    } catch (_) {
      // Ignore notification failures.
    }
  }

  @override
  Future<void> cancelJob({
    required String jobId,
    required String actorId,
    required String reason,
  }) async {
    final row = await _client.from('jobs').select().eq('id', jobId).single();
    final job = Job.fromJson(Map<String, dynamic>.from(row));
    final actor = await _loadProfileForAccess(actorId);
    final actorIsAdmin = actor.role == UserRole.admin;
    final canProCancel =
        job.assignedProId == actorId && job.status == JobStatus.inProcess;
    if (!actorIsAdmin && job.customerId != actorId && !canProCancel) {
      throw StateError('Only the job owner can cancel this job.');
    }
    await _client
        .from('jobs')
        .update(<String, dynamic>{
          'status': JobStatus.cancelled.value,
          'cancel_reason': reason,
          'updated_at': DateTime.now().toIso8601String(),
          'timeline': <Map<String, dynamic>>[
            ...job.timeline.map((event) => event.toJson()),
            JobTimelineEvent(
              type: 'cancelled',
              at: DateTime.now(),
              actorId: actorId,
              metadata: <String, dynamic>{'reason': reason},
            ).toJson(),
          ],
        })
        .eq('id', jobId);
  }

  @override
  Future<void> raiseDispute({
    required String jobId,
    required String actorId,
    required String reason,
  }) async {
    final row = await _client.from('jobs').select().eq('id', jobId).single();
    final job = Job.fromJson(Map<String, dynamic>.from(row));
    final canRaiseDispute =
        job.assignedProId != null &&
        job.status.index >= JobStatus.inProcess.index;
    if (!canRaiseDispute) {
      throw StateError('Dispute can only be raised after a pro is assigned.');
    }
    await _client
        .from('jobs')
        .update(<String, dynamic>{
          'status': JobStatus.disputed.value,
          'dispute_reason': reason,
          'updated_at': DateTime.now().toIso8601String(),
          'timeline': <Map<String, dynamic>>[
            ...job.timeline.map((event) => event.toJson()),
            JobTimelineEvent(
              type: 'disputed',
              at: DateTime.now(),
              actorId: actorId,
              metadata: <String, dynamic>{'reason': reason},
            ).toJson(),
          ],
        })
        .eq('id', jobId);
  }

  @override
  PaymentCalculation calculatePayment(double amount) =>
      _paymentCalculator.calculate(amount);

  @override
  PaymentCalculation calculatePaymentForCategory({
    required double amount,
    required JobCategory category,
  }) {
    final calculator = PaymentCalculator(commissionRateForCategory(category));
    return calculator.calculate(amount);
  }

  @override
  Future<PaymentRecord> recordPayment(PaymentRequest request) async {
    final jobRow = await _client
        .from('jobs')
        .select('category')
        .eq('id', request.jobId)
        .single();
    final category = JobCategoryX.fromValue(
      jobRow['category'] as String? ?? JobCategory.plumbing.value,
    );
    final calc = calculatePaymentForCategory(
      amount: request.amount,
      category: category,
    );
    final record = PaymentRecord(
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
    await _client.from('payments').insert(record.toJson());
    await updateJobStatus(
      jobId: request.jobId,
      status: JobStatus.paidClosed,
      actorId: request.customerId,
    );
    return record;
  }

  @override
  Future<void> settleProDue({
    required String proId,
    required PaymentMethod method,
    String? externalReference,
  }) async {
    final profile = await _client
        .from('profiles')
        .select('due_to_app')
        .eq('id', proId)
        .maybeSingle();
    final dueAmount = (profile?['due_to_app'] as num?)?.toDouble() ?? 0;
    if (dueAmount <= 0) {
      return;
    }

    await _client
        .from('profiles')
        .update(<String, dynamic>{
          'due_to_app': 0,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', proId);

    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: proId,
        action: 'pro_due_settled',
        entityType: 'pro_balance',
        entityId: proId,
        createdAt: DateTime.now(),
        metadata: <String, dynamic>{
          'amount': dueAmount,
          'method': method.value,
          if (externalReference case final value?) 'external_reference': value,
        },
      ),
    );
  }

  @override
  Stream<List<PaymentRecord>> watchPaymentsForUser(String userId) {
    return _client
        .from('payments')
        .stream(primaryKey: <String>['id'])
        .eq('customer_id', userId)
        .map(
          (rows) => rows
              .map(
                (row) => PaymentRecord.fromJson(Map<String, dynamic>.from(row)),
              )
              .toList(growable: false),
        );
  }

  @override
  Stream<List<PaymentRecord>> watchPaymentsForPro(String proId) {
    return _client
        .from('payments')
        .stream(primaryKey: <String>['id'])
        .eq('pro_id', proId)
        .map(
          (rows) => rows
              .map(
                (row) => PaymentRecord.fromJson(Map<String, dynamic>.from(row)),
              )
              .toList(growable: false),
        );
  }

  @override
  Stream<List<PaymentRecord>> watchAllPayments() {
    return _client.from('payments').stream(primaryKey: <String>['id']).map((
      rows,
    ) {
      final payments = rows
          .map((row) => PaymentRecord.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false);
      payments.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      return payments;
    });
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String jobId) {
    return _client
        .from('chat_messages')
        .stream(primaryKey: <String>['id'])
        .eq('job_id', jobId)
        .map((rows) {
          final messages = rows
              .map(
                (row) => ChatMessage.fromJson(Map<String, dynamic>.from(row)),
              )
              .toList(growable: false);
          messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
          return messages;
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
    final jobRow = await _client
        .from('jobs')
        .select('customer_id,assigned_pro_id,status')
        .eq('id', jobId)
        .maybeSingle();
    if (jobRow == null) {
      throw StateError('Job not found.');
    }
    final assignedProId = jobRow['assigned_pro_id'] as String?;
    final status = JobStatusX.fromValue(jobRow['status'] as String? ?? '');
    if (assignedProId == null || status.index < JobStatus.inProcess.index) {
      throw StateError(
        'Messaging unlocks only after bid approval and assignment.',
      );
    }
    final customerId = jobRow['customer_id'] as String? ?? '';
    final participants = <String>{customerId, assignedProId};
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
    await _client
        .from('jobs')
        .update(<String, dynamic>{'updated_at': now.toIso8601String()})
        .eq('id', jobId);
    await _client.from('chat_messages').insert(message.toJson());
    try {
      await _client.from('notifications').insert(<String, dynamic>{
        'id': _uuid.v4(),
        'user_id': receiverId,
        'type': 'message',
        'title': 'New message',
        'body': message.text,
        'sent_at': now.toIso8601String(),
        'metadata': <String, dynamic>{
          'job_id': jobId,
          'sender_id': senderId,
          'receiver_id': receiverId,
          'message_id': message.id,
          'navigate_route': '/chat/$jobId/$senderId',
        },
        'read': false,
      });
    } catch (_) {
      // Keep chat delivery working if notification policy/migration is pending.
    }
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
    final row = await _client
        .from('chat_messages')
        .select('sender_id,receiver_id,reactions')
        .eq('id', messageId)
        .maybeSingle();
    if (row == null) {
      throw StateError('Message not found.');
    }
    final senderId = row['sender_id'] as String;
    final receiverId = row['receiver_id'] as String;
    if (userId != senderId && userId != receiverId) {
      throw StateError('Only chat participants can react to this message.');
    }
    final currentReactions = row['reactions'] is Map
        ? Map<String, dynamic>.from(row['reactions'] as Map)
        : <String, dynamic>{};
    final normalizedEmoji = emoji?.trim();
    if (normalizedEmoji == null || normalizedEmoji.isEmpty) {
      currentReactions.remove(userId);
    } else {
      currentReactions[userId] = normalizedEmoji;
    }
    await _client
        .from('chat_messages')
        .update(<String, dynamic>{'reactions': currentReactions})
        .eq('id', messageId);
  }

  @override
  Future<void> markMessagesSeen({
    required String jobId,
    required String viewerId,
    required String peerId,
  }) async {
    await _client
        .from('chat_messages')
        .update(<String, dynamic>{'seen_at': DateTime.now().toIso8601String()})
        .eq('job_id', jobId)
        .eq('receiver_id', viewerId)
        .eq('sender_id', peerId)
        .isFilter('seen_at', null)
        .isFilter('deleted_for_everyone_at', null);
  }

  @override
  Future<void> deleteMessageForMe({
    required String messageId,
    required String userId,
  }) async {
    final row = await _client
        .from('chat_messages')
        .select('sender_id,receiver_id')
        .eq('id', messageId)
        .maybeSingle();
    if (row == null) {
      throw StateError('Message not found.');
    }
    final senderId = row['sender_id'] as String;
    final receiverId = row['receiver_id'] as String;
    if (userId != senderId && userId != receiverId) {
      throw StateError('Only chat participants can delete this message.');
    }
    final updateColumn = userId == senderId
        ? 'deleted_by_sender_at'
        : 'deleted_by_receiver_at';
    await _client
        .from('chat_messages')
        .update(<String, dynamic>{
          updateColumn: DateTime.now().toIso8601String(),
        })
        .eq('id', messageId);
  }

  @override
  Future<void> deleteMessageForEveryone({
    required String messageId,
    required String userId,
  }) async {
    await _client
        .from('chat_messages')
        .update(<String, dynamic>{
          'deleted_for_everyone_at': DateTime.now().toIso8601String(),
          'deleted_for_everyone_by': userId,
        })
        .eq('id', messageId)
        .eq('sender_id', userId);
  }

  @override
  Stream<List<NotificationEvent>> watchNotifications(String userId) {
    return _client
        .from('notifications')
        .stream(primaryKey: <String>['id'])
        .eq('user_id', userId)
        .map(
          (rows) => rows
              .map(
                (row) =>
                    NotificationEvent.fromJson(Map<String, dynamic>.from(row)),
              )
              .toList(growable: false),
        );
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {
    await _client
        .from('notifications')
        .update(<String, dynamic>{'read': true})
        .eq('id', notificationId);
  }

  @override
  Stream<List<AuditEvent>> watchAuditEvents({
    String? entityType,
    String? entityId,
  }) {
    return _client.from('audit_logs').stream(primaryKey: <String>['id']).map((
      rows,
    ) {
      final events = rows
          .map((row) => AuditEvent.fromJson(Map<String, dynamic>.from(row)))
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
  Future<void> addAuditEvent(AuditEvent event) async {
    await _client.from('audit_logs').insert(event.toJson());
  }

  @override
  Stream<List<UserReport>> watchUserReports() {
    return _client.from('reports').stream(primaryKey: <String>['id']).map((
      rows,
    ) {
      final reports = rows
          .map((row) => UserReport.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false);
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
    final report = UserReport(
      id: _uuid.v4(),
      reporterId: reporterId,
      targetUserId: targetUserId,
      reasonCode: reasonCode,
      details: details,
      createdAt: DateTime.now(),
    );
    await _client.from('reports').insert(report.toJson());
    await addAuditEvent(
      AuditEvent(
        id: _uuid.v4(),
        actorId: reporterId,
        action: 'user_reported',
        entityType: 'user',
        entityId: targetUserId,
        createdAt: DateTime.now(),
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
  }) async {
    await setUserBlockStatus(
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
    await _requireAdminPermission(
      actorId,
      AdminPermission.manageUsers,
      anyOf: <AdminPermission>[AdminPermission.manageReports],
    );
    await _client
        .from('profiles')
        .update(<String, dynamic>{'blocked': blocked})
        .eq('id', targetUserId);
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
    await _requireAdminPermission(actorId, AdminPermission.manageAdminAccess);
    final target = await _client
        .from('profiles')
        .select('id,role')
        .eq('id', targetUserId)
        .maybeSingle();
    if (target == null || target['role'] != UserRole.admin.value) {
      throw StateError('Target admin user not found.');
    }
    final assignedPermissions = permissions.isEmpty
        ? defaultAdminPermissionsForRank(rank)
        : permissions.toSet().toList(growable: false);
    await _client
        .from('profiles')
        .update(<String, dynamic>{
          'admin_rank': rank.value,
          'admin_permissions': assignedPermissions
              .map((permission) => permission.value)
              .toList(growable: false),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', targetUserId);
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
    final paymentRows = await _client
        .from('payments')
        .select()
        .eq('pro_id', proId)
        .eq('state', PaymentState.completed.value);
    final payments = (paymentRows as List<dynamic>)
        .map(
          (row) =>
              PaymentRecord.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);

    final profile = await _client
        .from('profiles')
        .select('rating,total_reviews,total_earnings,due_to_app,role')
        .eq('id', proId)
        .maybeSingle();
    if (profile == null || profile['role'] != UserRole.pro.value) {
      throw StateError('Professional account not found.');
    }

    final completedJobRows = await _client
        .from('jobs')
        .select('status,final_amount,fixed_price,timeline,updated_at')
        .eq('assigned_pro_id', proId)
        .inFilter('status', <String>[
          JobStatus.completed.value,
          JobStatus.paidClosed.value,
        ]);

    final now = DateTime.now();
    double sum(Iterable<double> values) =>
        values.fold<double>(0, (total, value) => total + value);
    DateTime completionAt(Map<String, dynamic> row) {
      final timelineRaw = row['timeline'];
      if (timelineRaw is List<dynamic>) {
        for (final event in timelineRaw.reversed) {
          final value = Map<String, dynamic>.from(event as Map);
          if (value['type'] == JobStatus.completed.value &&
              value['at'] is String) {
            return DateTime.parse(value['at'] as String);
          }
        }
      }
      return DateTime.parse(row['updated_at'] as String);
    }

    final completedJobs = (completedJobRows as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    double amountFor(Map<String, dynamic> row) =>
        ((row['final_amount'] ?? row['fixed_price']) as num).toDouble();
    final today = sum(
      completedJobs
          .where((row) {
            final at = completionAt(row);
            return at.year == now.year &&
                at.month == now.month &&
                at.day == now.day;
          })
          .map(amountFor),
    );
    final month = sum(
      completedJobs
          .where((row) {
            final at = completionAt(row);
            return at.year == now.year && at.month == now.month;
          })
          .map(amountFor),
    );

    final online = sum(
      payments
          .where((p) => p.method != PaymentMethod.cash)
          .map((p) => p.netProAmount),
    );
    final cash = sum(
      payments
          .where((p) => p.method == PaymentMethod.cash)
          .map((p) => p.netProAmount),
    );
    final platformFees = sum(payments.map((p) => p.platformFee));
    final totalEarnings = (profile['total_earnings'] as num?)?.toDouble() ?? 0;
    final dueToApp = (profile['due_to_app'] as num?)?.toDouble() ?? 0;

    return ProEarningsSummary(
      today: today,
      month: month,
      lifetime: totalEarnings,
      online: online,
      cash: cash,
      platformFees: platformFees,
      totalJobs: completedJobs.length,
      averageRating: (profile['rating'] as num?)?.toDouble() ?? 0,
      totalReviews: profile['total_reviews'] as int? ?? 0,
      totalEarnings: totalEarnings,
      dueToApp: dueToApp,
    );
  }

  @override
  Future<AdminMetrics> fetchAdminMetrics() async {
    final now = DateTime.now();
    final since24h = now.subtract(const Duration(hours: 24));
    final profiles = await _client
        .from('profiles')
        .select('role,cnic_verified');
    final jobs = await _client.from('jobs').select('status');
    final payments = await _client
        .from('payments')
        .select('method,gross_amount,platform_fee');
    final reports = await _client.from('reports').select('id');
    final messageRows = await _client.from('chat_messages').select('sent_at');
    final auditRows = await _client
        .from('audit_logs')
        .select('created_at,entity_type,entity_id,action');
    final profileList = (profiles as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final jobList = (jobs as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final paymentList = (payments as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final reportList = (reports as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    final messages = (messageRows as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    final audits = (auditRows as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);

    double sum(Iterable<double> values) =>
        values.fold<double>(0, (total, value) => total + value);
    DateTime parseAt(Map<String, dynamic> row, String key) {
      final raw = row[key] as String? ?? '';
      return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }

    final onlineVolume = sum(
      paymentList
          .where((row) => row['method'] != PaymentMethod.cash.value)
          .map((row) => (row['gross_amount'] as num).toDouble()),
    );
    final cashVolume = sum(
      paymentList
          .where((row) => row['method'] == PaymentMethod.cash.value)
          .map((row) => (row['gross_amount'] as num).toDouble()),
    );
    final revenue = sum(
      paymentList.map((row) => (row['platform_fee'] as num).toDouble()),
    );
    final reviewedReportIds = audits
        .where(
          (row) =>
              row['entity_type'] == 'report' &&
              row['action'] == 'report_reviewed' &&
              row['entity_id'] is String,
        )
        .map((row) => row['entity_id'] as String)
        .toSet();
    final openReports = reportList
        .where((row) => !reviewedReportIds.contains(row['id']))
        .length;
    final messages24h = messages
        .where((row) => parseAt(row, 'sent_at').isAfter(since24h))
        .length;
    final audits24h = audits
        .where((row) => parseAt(row, 'created_at').isAfter(since24h))
        .length;

    return AdminMetrics(
      totalCustomers: profileList
          .where((row) => row['role'] == UserRole.customer.value)
          .length,
      totalPros: profileList
          .where((row) => row['role'] == UserRole.pro.value)
          .length,
      totalAdmins: profileList
          .where((row) => row['role'] == UserRole.admin.value)
          .length,
      verifiedPros: profileList
          .where(
            (row) =>
                row['role'] == UserRole.pro.value &&
                row['cnic_verified'] == true,
          )
          .length,
      totalJobs: jobList.length,
      activeJobs: jobList
          .where((row) => row['status'] == JobStatus.inProcess.value)
          .length,
      completedJobs: jobList
          .where(
            (row) =>
                row['status'] == JobStatus.completed.value ||
                row['status'] == JobStatus.paidClosed.value,
          )
          .length,
      cancelledJobs: jobList
          .where((row) => row['status'] == JobStatus.cancelled.value)
          .length,
      activeDisputes: jobList
          .where((row) => row['status'] == JobStatus.disputed.value)
          .length,
      totalReports: reportList.length,
      openReports: openReports,
      messages24h: messages24h,
      audits24h: audits24h,
      onlineVolume: onlineVolume,
      cashVolume: cashVolume,
      platformRevenue: revenue,
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
    await _client
        .from('app_settings')
        .update(<String, dynamic>{
          'value': rate,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('key', 'commission_rate');
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
    await _requireAdminPermission(actorId, AdminPermission.manageCommissions);
    if (rate < 0 || rate > 1) {
      throw StateError('Rate should be between 0 and 1.');
    }
    _categoryCommissionRates[category] = rate;
    final payload = <String, dynamic>{
      for (final entry in _categoryCommissionRates.entries)
        entry.key.value: entry.value,
    };
    await _client
        .from('app_settings')
        .update(<String, dynamic>{
          'value': payload,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('key', 'commission_rate_by_category');
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

  @override
  void dispose() {}
}
