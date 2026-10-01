import 'dart:convert';

import 'package:flutter/foundation.dart';

String _normalizeLookupToken(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_\-]+'), '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
}

DateTime? _parseDateTimeOrNull(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

List<dynamic> _asDynamicList(dynamic value) {
  if (value is List<dynamic>) {
    return value;
  }
  if (value is List) {
    return value.cast<dynamic>();
  }
  if (value is String && value.trim().isNotEmpty) {
    return value.split(',');
  }
  return const <dynamic>[];
}

enum UserRole { customer, pro, admin }

enum AdminRank { superAdmin, operations, support, finance, analyst }

enum AdminPermission {
  viewMetrics,
  viewAuditLogs,
  manageReports,
  manageUsers,
  manageProVerification,
  manageCommissions,
  exportData,
  manageAdminAccess,
}

enum JobStatus {
  posted,
  available,
  inProcess,
  completed,
  paidClosed,
  cancelled,
  disputed,
}

enum BidStatus { pending, accepted, rejected, withdrawn }

enum PaymentMethod { jazzCash, easyPaisa, cash }

enum PaymentState { initiated, completed, failed }

enum JobCategory {
  plumbing,
  electrician,
  acRepair,
  carpenter,
  painter,
  cleaning,
  applianceRepair,
  registeredNurse,
}

extension UserRoleX on UserRole {
  String get value => switch (this) {
    UserRole.customer => 'customer',
    UserRole.pro => 'pro',
    UserRole.admin => 'admin',
  };

  static UserRole fromValue(String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'customer' || 'client' => UserRole.customer,
      'pro' ||
      'professional' ||
      'provider' ||
      'service_provider' ||
      'worker' ||
      'service_worker' ||
      'serviceman' ||
      'technician' => UserRole.pro,
      'admin' || 'administrator' => UserRole.admin,
      _ => UserRole.customer,
    };
  }
}

extension AdminRankX on AdminRank {
  String get value => switch (this) {
    AdminRank.superAdmin => 'super_admin',
    AdminRank.operations => 'operations',
    AdminRank.support => 'support',
    AdminRank.finance => 'finance',
    AdminRank.analyst => 'analyst',
  };

  String get label => switch (this) {
    AdminRank.superAdmin => 'Super Admin',
    AdminRank.operations => 'Operations Manager',
    AdminRank.support => 'Support Lead',
    AdminRank.finance => 'Finance Manager',
    AdminRank.analyst => 'Analytics Admin',
  };

  static AdminRank fromValue(String? value) {
    return AdminRank.values.firstWhere(
      (rank) => rank.value == value,
      orElse: () => AdminRank.support,
    );
  }
}

extension AdminPermissionX on AdminPermission {
  String get value => switch (this) {
    AdminPermission.viewMetrics => 'view_metrics',
    AdminPermission.viewAuditLogs => 'view_audit_logs',
    AdminPermission.manageReports => 'manage_reports',
    AdminPermission.manageUsers => 'manage_users',
    AdminPermission.manageProVerification => 'manage_pro_verification',
    AdminPermission.manageCommissions => 'manage_commissions',
    AdminPermission.exportData => 'export_data',
    AdminPermission.manageAdminAccess => 'manage_admin_access',
  };

  String get label => switch (this) {
    AdminPermission.viewMetrics => 'View Metrics',
    AdminPermission.viewAuditLogs => 'View Audit Logs',
    AdminPermission.manageReports => 'Manage Reports',
    AdminPermission.manageUsers => 'Manage Users',
    AdminPermission.manageProVerification => 'Manage Pro Verification',
    AdminPermission.manageCommissions => 'Manage Commissions',
    AdminPermission.exportData => 'Export Data',
    AdminPermission.manageAdminAccess => 'Manage Admin Access',
  };

  static AdminPermission fromValue(String value) {
    return AdminPermission.values.firstWhere(
      (permission) => permission.value == value,
      orElse: () => AdminPermission.viewMetrics,
    );
  }
}

List<AdminPermission> defaultAdminPermissionsForRank(AdminRank rank) {
  return switch (rank) {
    AdminRank.superAdmin => AdminPermission.values,
    AdminRank.operations => <AdminPermission>[
      AdminPermission.viewMetrics,
      AdminPermission.viewAuditLogs,
      AdminPermission.manageReports,
      AdminPermission.manageUsers,
      AdminPermission.manageProVerification,
      AdminPermission.exportData,
    ],
    AdminRank.support => <AdminPermission>[
      AdminPermission.viewMetrics,
      AdminPermission.viewAuditLogs,
      AdminPermission.manageReports,
      AdminPermission.exportData,
    ],
    AdminRank.finance => <AdminPermission>[
      AdminPermission.viewMetrics,
      AdminPermission.viewAuditLogs,
      AdminPermission.manageCommissions,
      AdminPermission.exportData,
    ],
    AdminRank.analyst => <AdminPermission>[
      AdminPermission.viewMetrics,
      AdminPermission.viewAuditLogs,
      AdminPermission.exportData,
    ],
  };
}

extension JobStatusX on JobStatus {
  bool get allowsChat => switch (this) {
    JobStatus.inProcess ||
    JobStatus.completed ||
    JobStatus.paidClosed ||
    JobStatus.disputed => true,
    JobStatus.posted || JobStatus.available || JobStatus.cancelled => false,
  };

  String get value => switch (this) {
    JobStatus.posted => 'posted',
    JobStatus.available => 'available',
    JobStatus.inProcess => 'in_process',
    JobStatus.completed => 'completed',
    JobStatus.paidClosed => 'paid_closed',
    JobStatus.cancelled => 'cancelled',
    JobStatus.disputed => 'disputed',
  };

  static JobStatus fromValue(String value) => JobStatus.values.firstWhere(
    (status) => status.value == value,
    orElse: () => JobStatus.posted,
  );
}

extension JobCategoryX on JobCategory {
  String get value => switch (this) {
    JobCategory.plumbing => 'plumbing',
    JobCategory.electrician => 'electrician',
    JobCategory.acRepair => 'ac_repair',
    JobCategory.carpenter => 'carpenter',
    JobCategory.painter => 'painter',
    JobCategory.cleaning => 'cleaning',
    JobCategory.applianceRepair => 'appliance_repair',
    JobCategory.registeredNurse => 'registered_nurse',
  };

  String get displayName => switch (this) {
    JobCategory.plumbing => 'Plumbing',
    JobCategory.electrician => 'Electrician',
    JobCategory.acRepair => 'AC Repair',
    JobCategory.carpenter => 'Carpenter',
    JobCategory.painter => 'Painter',
    JobCategory.cleaning => 'Cleaning',
    JobCategory.applianceRepair => 'Appliance Repair',
    JobCategory.registeredNurse => 'Registered Nurse',
  };

  static JobCategory fromValue(String value) {
    final normalized = _normalizeLookupToken(value);
    return switch (normalized) {
      'plumbing' || 'plumber' => JobCategory.plumbing,
      'electrician' || 'electrical' => JobCategory.electrician,
      'acrepair' ||
      'airconditionerrepair' ||
      'airconditioningrepair' ||
      'hvac' => JobCategory.acRepair,
      'carpenter' || 'carpentry' || 'woodwork' => JobCategory.carpenter,
      'painter' || 'painting' => JobCategory.painter,
      'cleaning' ||
      'cleaner' ||
      'housecleaning' ||
      'housekeeping' => JobCategory.cleaning,
      'appliancerepair' ||
      'appliancefix' ||
      'appliance' => JobCategory.applianceRepair,
      // Backward compatibility with older datasets.
      'handyman' ||
      'registerednurse' ||
      'nurse' ||
      'nursing' => JobCategory.registeredNurse,
      _ => JobCategory.plumbing,
    };
  }
}

extension PaymentMethodX on PaymentMethod {
  String get value => switch (this) {
    PaymentMethod.jazzCash => 'jazzcash',
    PaymentMethod.easyPaisa => 'easypaisa',
    PaymentMethod.cash => 'cash',
  };

  String get displayName => switch (this) {
    PaymentMethod.jazzCash => 'JazzCash',
    PaymentMethod.easyPaisa => 'Easypaisa',
    PaymentMethod.cash => 'Cash',
  };

  static PaymentMethod fromValue(String value) =>
      PaymentMethod.values.firstWhere(
        (method) => method.value == value,
        orElse: () => PaymentMethod.cash,
      );
}

extension BidStatusX on BidStatus {
  String get value => switch (this) {
    BidStatus.pending => 'pending',
    BidStatus.accepted => 'accepted',
    BidStatus.rejected => 'rejected',
    BidStatus.withdrawn => 'withdrawn',
  };

  static BidStatus fromValue(String value) => BidStatus.values.firstWhere(
    (status) => status.value == value,
    orElse: () => BidStatus.pending,
  );
}

extension PaymentStateX on PaymentState {
  String get value => switch (this) {
    PaymentState.initiated => 'initiated',
    PaymentState.completed => 'completed',
    PaymentState.failed => 'failed',
  };

  static PaymentState fromValue(String value) => PaymentState.values.firstWhere(
    (state) => state.value == value,
    orElse: () => PaymentState.initiated,
  );
}

@immutable
class TermsAcceptance {
  const TermsAcceptance({
    required this.termsVersion,
    required this.privacyVersion,
    required this.acceptedAt,
    required this.ipAddress,
    required this.deviceInfo,
    required this.checkboxConfirmed,
  });

  final String termsVersion;
  final String privacyVersion;
  final DateTime acceptedAt;
  final String ipAddress;
  final String deviceInfo;
  final bool checkboxConfirmed;

  Map<String, dynamic> toJson() => {
    'terms_version': termsVersion,
    'privacy_version': privacyVersion,
    'accepted_at': acceptedAt.toIso8601String(),
    'ip_address': ipAddress,
    'device_info': deviceInfo,
    'checkbox_confirmed': checkboxConfirmed,
  };

  factory TermsAcceptance.fromJson(Map<String, dynamic> json) {
    return TermsAcceptance(
      termsVersion: json['terms_version'] as String? ?? '',
      privacyVersion: json['privacy_version'] as String? ?? '',
      acceptedAt: DateTime.parse(json['accepted_at'] as String),
      ipAddress: json['ip_address'] as String? ?? '',
      deviceInfo: json['device_info'] as String? ?? '',
      checkboxConfirmed: json['checkbox_confirmed'] as bool? ?? false,
    );
  }
}

@immutable
class SavedLocation {
  const SavedLocation({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.createdAt,
  });

  final String id;
  final String label;
  final double latitude;
  final double longitude;
  final String address;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'latitude': latitude,
    'longitude': longitude,
    'address': address,
    'created_at': createdAt.toIso8601String(),
  };

  factory SavedLocation.fromJson(Map<String, dynamic> json) {
    return SavedLocation(
      id: json['id'] as String,
      label: json['label'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.role,
    required this.fullName,
    required this.email,
    required this.phone,
    this.username = '',
    this.adminRank,
    this.adminPermissions = const <AdminPermission>[],
    this.profileImageUrl,
    this.languageCode = 'en',
    this.cnicVerified = false,
    this.policeVerified = false,
    this.rating = 0,
    this.totalReviews = 0,
    this.notificationsEnabled = true,
    this.preciseLocationEnabled = false,
    this.paymentAccount,
    this.isOnline = false,
    this.lastSeenAt,
    this.lastActiveAt,
    this.savedLocations = const <SavedLocation>[],
    this.termsAcceptanceHistory = const <TermsAcceptance>[],
    this.createdAt,
    this.updatedAt,
    this.blocked = false,
    this.preferredCategories = const <JobCategory>[],
    this.totalEarnings = 0,
    this.dueToApp = 0,
  });

  final String id;
  final UserRole role;
  final String fullName;
  final String email;
  final String phone;
  final String username;
  final AdminRank? adminRank;
  final List<AdminPermission> adminPermissions;
  final String? profileImageUrl;
  final String languageCode;
  final bool cnicVerified;
  final bool policeVerified;
  final double rating;
  final int totalReviews;
  final bool notificationsEnabled;
  final bool preciseLocationEnabled;
  final String? paymentAccount;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final DateTime? lastActiveAt;
  final List<SavedLocation> savedLocations;
  final List<TermsAcceptance> termsAcceptanceHistory;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool blocked;
  final List<JobCategory> preferredCategories;
  final double totalEarnings;
  final double dueToApp;
  static const Object _keepExistingValue = Object();

  bool get isVerifiedPro => role == UserRole.pro && cnicVerified;
  AdminRank? get effectiveAdminRank {
    if (role != UserRole.admin) {
      return null;
    }
    return adminRank ?? AdminRank.superAdmin;
  }

  bool hasAdminPermission(AdminPermission permission) {
    if (role != UserRole.admin) {
      return false;
    }
    final rank = effectiveAdminRank;
    if (rank == AdminRank.superAdmin) {
      return true;
    }
    final configured = adminPermissions;
    if (configured.isEmpty) {
      return false;
    }
    return configured.contains(permission);
  }

  AppUser copyWith({
    UserRole? role,
    String? fullName,
    String? phone,
    String? username,
    AdminRank? adminRank,
    List<AdminPermission>? adminPermissions,
    Object? profileImageUrl = _keepExistingValue,
    String? languageCode,
    bool? notificationsEnabled,
    bool? preciseLocationEnabled,
    Object? paymentAccount = _keepExistingValue,
    bool? isOnline,
    DateTime? lastSeenAt,
    DateTime? lastActiveAt,
    List<SavedLocation>? savedLocations,
    List<TermsAcceptance>? termsAcceptanceHistory,
    bool? blocked,
    bool? cnicVerified,
    bool? policeVerified,
    double? rating,
    int? totalReviews,
    List<JobCategory>? preferredCategories,
    double? totalEarnings,
    double? dueToApp,
    DateTime? updatedAt,
  }) {
    return AppUser(
      id: id,
      role: role ?? this.role,
      fullName: fullName ?? this.fullName,
      email: email,
      phone: phone ?? this.phone,
      username: username ?? this.username,
      adminRank: adminRank ?? this.adminRank,
      adminPermissions: adminPermissions ?? this.adminPermissions,
      profileImageUrl: identical(profileImageUrl, _keepExistingValue)
          ? this.profileImageUrl
          : profileImageUrl as String?,
      languageCode: languageCode ?? this.languageCode,
      cnicVerified: cnicVerified ?? this.cnicVerified,
      policeVerified: policeVerified ?? this.policeVerified,
      rating: rating ?? this.rating,
      totalReviews: totalReviews ?? this.totalReviews,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      preciseLocationEnabled:
          preciseLocationEnabled ?? this.preciseLocationEnabled,
      paymentAccount: identical(paymentAccount, _keepExistingValue)
          ? this.paymentAccount
          : paymentAccount as String?,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      savedLocations: savedLocations ?? this.savedLocations,
      termsAcceptanceHistory:
          termsAcceptanceHistory ?? this.termsAcceptanceHistory,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      blocked: blocked ?? this.blocked,
      preferredCategories: preferredCategories ?? this.preferredCategories,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      dueToApp: dueToApp ?? this.dueToApp,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.value,
    'full_name': fullName,
    'email': email,
    'phone': phone,
    'username': username,
    'admin_rank': adminRank?.value,
    'admin_permissions': adminPermissions
        .map((permission) => permission.value)
        .toList(),
    'profile_image_url': profileImageUrl,
    'language_code': languageCode,
    'cnic_verified': cnicVerified,
    'police_verified': policeVerified,
    'rating': rating,
    'total_reviews': totalReviews,
    'notifications_enabled': notificationsEnabled,
    'precise_location_enabled': preciseLocationEnabled,
    'payment_account': paymentAccount,
    'is_online': isOnline,
    'last_seen_at': lastSeenAt?.toIso8601String(),
    'last_active_at': lastActiveAt?.toIso8601String(),
    'saved_locations': savedLocations
        .map((location) => location.toJson())
        .toList(),
    'terms_acceptance_history': termsAcceptanceHistory
        .map((acceptance) => acceptance.toJson())
        .toList(),
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'blocked': blocked,
    'preferred_categories': preferredCategories
        .map((category) => category.value)
        .toList(),
    'total_earnings': totalEarnings,
    'due_to_app': dueToApp,
  };

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final preferredRaw = _asDynamicList(
      json['preferred_categories'] ??
          json['preferredCategories'] ??
          json['preferred_services'] ??
          json['preferredServices'] ??
          json['services'] ??
          json['categories'],
    );
    final categories = preferredRaw
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .map(JobCategoryX.fromValue)
        .toSet()
        .toList(growable: false);
    final rawPermissions = _asDynamicList(json['admin_permissions'])
        .map((value) => AdminPermissionX.fromValue(value.toString()))
        .toList(growable: false);
    final fullName = (json['full_name'] ?? json['fullName'] ?? '')
        .toString()
        .trim();
    final phone = (json['phone'] ?? '').toString().trim();
    final email = (json['email'] ?? '').toString().trim();
    final username = (json['username'] ?? '').toString().trim();
    final role = (json['role'] ?? json['user_role'] ?? 'customer').toString();
    final adminRankValue = json['admin_rank']?.toString();
    return AppUser(
      id: (json['id'] ?? json['uid'] ?? '').toString(),
      role: UserRoleX.fromValue(role),
      fullName: fullName,
      email: email,
      phone: phone,
      username: username,
      adminRank: adminRankValue == null
          ? null
          : AdminRankX.fromValue(adminRankValue),
      adminPermissions: rawPermissions,
      profileImageUrl: (json['profile_image_url'] ?? json['profileImageUrl'])
          ?.toString(),
      languageCode: json['language_code'] as String? ?? 'en',
      cnicVerified: json['cnic_verified'] as bool? ?? false,
      policeVerified: json['police_verified'] as bool? ?? false,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      totalReviews:
          (json['total_reviews'] as num?)?.toInt() ??
          (json['totalReviews'] as num?)?.toInt() ??
          0,
      notificationsEnabled: json['notifications_enabled'] as bool? ?? true,
      preciseLocationEnabled:
          json['precise_location_enabled'] as bool? ?? false,
      paymentAccount: (json['payment_account'] ?? json['paymentAccount'])
          ?.toString(),
      isOnline: json['is_online'] as bool? ?? false,
      lastSeenAt:
          _parseDateTimeOrNull(json['last_seen_at']) ??
          _parseDateTimeOrNull(json['lastSeenAt']),
      lastActiveAt:
          _parseDateTimeOrNull(json['last_active_at']) ??
          _parseDateTimeOrNull(json['lastActiveAt']),
      savedLocations: (json['saved_locations'] as List<dynamic>? ?? <dynamic>[])
          .map((value) => SavedLocation.fromJson(value as Map<String, dynamic>))
          .toList(),
      termsAcceptanceHistory: _asDynamicList(json['terms_acceptance_history'])
          .map(
            (value) => TermsAcceptance.fromJson(value as Map<String, dynamic>),
          )
          .toList(),
      createdAt:
          _parseDateTimeOrNull(json['created_at']) ??
          _parseDateTimeOrNull(json['createdAt']),
      updatedAt:
          _parseDateTimeOrNull(json['updated_at']) ??
          _parseDateTimeOrNull(json['updatedAt']),
      blocked: json['blocked'] as bool? ?? false,
      preferredCategories: categories,
      totalEarnings: (json['total_earnings'] as num?)?.toDouble() ?? 0,
      dueToApp: (json['due_to_app'] as num?)?.toDouble() ?? 0,
    );
  }
}

@immutable
class JobTimelineEvent {
  const JobTimelineEvent({
    required this.type,
    required this.at,
    required this.actorId,
    this.metadata = const <String, dynamic>{},
  });

  final String type;
  final DateTime at;
  final String actorId;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
    'type': type,
    'at': at.toIso8601String(),
    'actor_id': actorId,
    'metadata': metadata,
  };

  factory JobTimelineEvent.fromJson(Map<String, dynamic> json) {
    return JobTimelineEvent(
      type: json['type'] as String,
      at: DateTime.parse(json['at'] as String),
      actorId: json['actor_id'] as String,
      metadata: Map<String, dynamic>.from(
        json['metadata'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
    );
  }
}

@immutable
class Job {
  const Job({
    required this.id,
    required this.customerId,
    required this.category,
    required this.title,
    required this.description,
    required this.fixedPrice,
    required this.latitude,
    required this.longitude,
    required this.maskedAddress,
    required this.exactAddress,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.assignedProId,
    this.selectedBidId,
    this.finalAmount,
    this.timeline = const <JobTimelineEvent>[],
    this.cancelReason,
    this.disputeReason,
  });

  final String id;
  final String customerId;
  final JobCategory category;
  final String title;
  final String description;
  final double fixedPrice;
  final double latitude;
  final double longitude;
  final String maskedAddress;
  final String exactAddress;
  final JobStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? assignedProId;
  final String? selectedBidId;
  final double? finalAmount;
  final List<JobTimelineEvent> timeline;
  final String? cancelReason;
  final String? disputeReason;

  Job copyWith({
    String? title,
    String? description,
    double? fixedPrice,
    double? latitude,
    double? longitude,
    String? maskedAddress,
    String? exactAddress,
    JobStatus? status,
    String? assignedProId,
    String? selectedBidId,
    double? finalAmount,
    List<JobTimelineEvent>? timeline,
    DateTime? updatedAt,
    String? cancelReason,
    String? disputeReason,
  }) {
    return Job(
      id: id,
      customerId: customerId,
      category: category,
      title: title ?? this.title,
      description: description ?? this.description,
      fixedPrice: fixedPrice ?? this.fixedPrice,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      maskedAddress: maskedAddress ?? this.maskedAddress,
      exactAddress: exactAddress ?? this.exactAddress,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      assignedProId: assignedProId ?? this.assignedProId,
      selectedBidId: selectedBidId ?? this.selectedBidId,
      finalAmount: finalAmount ?? this.finalAmount,
      timeline: timeline ?? this.timeline,
      cancelReason: cancelReason ?? this.cancelReason,
      disputeReason: disputeReason ?? this.disputeReason,
    );
  }

  bool canRevealExactAddress(String userId) {
    if (customerId == userId) {
      return true;
    }
    final isAssignedPro = assignedProId == userId;
    final accepted = status.allowsChat;
    return isAssignedPro && accepted;
  }

  String visibleAddressFor(String userId) {
    return canRevealExactAddress(userId) ? exactAddress : maskedAddress;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'customer_id': customerId,
    'category': category.value,
    'title': title,
    'description': description,
    'fixed_price': fixedPrice,
    'latitude': latitude,
    'longitude': longitude,
    'masked_address': maskedAddress,
    'exact_address': exactAddress,
    'status': status.value,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'assigned_pro_id': assignedProId,
    'selected_bid_id': selectedBidId,
    'final_amount': finalAmount,
    'timeline': timeline.map((event) => event.toJson()).toList(),
    'cancel_reason': cancelReason,
    'dispute_reason': disputeReason,
  };

  factory Job.fromJson(Map<String, dynamic> json) {
    final timelineRaw = json['timeline'];
    final timelineList = timelineRaw is String
        ? (jsonDecode(timelineRaw) as List<dynamic>)
        : _asDynamicList(timelineRaw);
    final categoryRaw =
        json['category'] ?? json['service_category'] ?? json['serviceCategory'];
    final createdAt =
        _parseDateTimeOrNull(json['created_at']) ??
        _parseDateTimeOrNull(json['createdAt']) ??
        DateTime.now();
    final updatedAt =
        _parseDateTimeOrNull(json['updated_at']) ??
        _parseDateTimeOrNull(json['updatedAt']) ??
        createdAt;
    return Job(
      id: (json['id'] ?? '').toString(),
      customerId: (json['customer_id'] ?? json['customerId'] ?? '').toString(),
      category: JobCategoryX.fromValue(
        categoryRaw == null ? 'plumbing' : categoryRaw.toString(),
      ),
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      fixedPrice:
          (json['fixed_price'] as num?)?.toDouble() ??
          (json['fixedPrice'] as num?)?.toDouble() ??
          0,
      latitude:
          (json['latitude'] as num?)?.toDouble() ??
          (json['lat'] as num?)?.toDouble() ??
          0,
      longitude:
          (json['longitude'] as num?)?.toDouble() ??
          (json['lng'] as num?)?.toDouble() ??
          0,
      maskedAddress: json['masked_address'] as String? ?? '',
      exactAddress: json['exact_address'] as String? ?? '',
      status: JobStatusX.fromValue(json['status'] as String? ?? 'posted'),
      createdAt: createdAt,
      updatedAt: updatedAt,
      assignedProId: (json['assigned_pro_id'] ?? json['assignedProId'])
          ?.toString(),
      selectedBidId: (json['selected_bid_id'] ?? json['selectedBidId'])
          ?.toString(),
      finalAmount: (json['final_amount'] as num?)?.toDouble(),
      timeline: timelineList
          .whereType<Map>()
          .map(
            (value) =>
                JobTimelineEvent.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
      cancelReason: json['cancel_reason'] as String?,
      disputeReason: json['dispute_reason'] as String?,
    );
  }
}

@immutable
class Bid {
  const Bid({
    required this.id,
    required this.jobId,
    required this.proId,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.notes,
  });

  final String id;
  final String jobId;
  final String proId;
  final double amount;
  final BidStatus status;
  final DateTime createdAt;
  final String? notes;

  Bid copyWith({BidStatus? status}) {
    return Bid(
      id: id,
      jobId: jobId,
      proId: proId,
      amount: amount,
      status: status ?? this.status,
      createdAt: createdAt,
      notes: notes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'job_id': jobId,
    'pro_id': proId,
    'amount': amount,
    'status': status.value,
    'created_at': createdAt.toIso8601String(),
    'notes': notes,
  };

  factory Bid.fromJson(Map<String, dynamic> json) {
    return Bid(
      id: json['id'] as String,
      jobId: json['job_id'] as String,
      proId: json['pro_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      status: BidStatusX.fromValue(json['status'] as String? ?? 'pending'),
      createdAt: DateTime.parse(json['created_at'] as String),
      notes: json['notes'] as String?,
    );
  }
}

@immutable
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.jobId,
    required this.customerId,
    required this.proId,
    required this.method,
    required this.state,
    required this.grossAmount,
    required this.platformFee,
    required this.netProAmount,
    required this.recordedAt,
    this.externalReference,
  });

  final String id;
  final String jobId;
  final String customerId;
  final String proId;
  final PaymentMethod method;
  final PaymentState state;
  final double grossAmount;
  final double platformFee;
  final double netProAmount;
  final DateTime recordedAt;
  final String? externalReference;

  Map<String, dynamic> toJson() => {
    'id': id,
    'job_id': jobId,
    'customer_id': customerId,
    'pro_id': proId,
    'method': method.value,
    'state': state.value,
    'gross_amount': grossAmount,
    'platform_fee': platformFee,
    'net_pro_amount': netProAmount,
    'recorded_at': recordedAt.toIso8601String(),
    'external_reference': externalReference,
  };

  factory PaymentRecord.fromJson(Map<String, dynamic> json) {
    return PaymentRecord(
      id: json['id'] as String,
      jobId: json['job_id'] as String,
      customerId: json['customer_id'] as String,
      proId: json['pro_id'] as String,
      method: PaymentMethodX.fromValue(json['method'] as String? ?? 'cash'),
      state: PaymentStateX.fromValue(json['state'] as String? ?? 'initiated'),
      grossAmount: (json['gross_amount'] as num).toDouble(),
      platformFee: (json['platform_fee'] as num).toDouble(),
      netProAmount: (json['net_pro_amount'] as num).toDouble(),
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      externalReference: json['external_reference'] as String?,
    );
  }
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.jobId,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.sentAt,
    this.seenAt,
    this.deletedForEveryoneAt,
    this.deletedForEveryoneBy,
    this.deletedBySenderAt,
    this.deletedByReceiverAt,
    this.replyToMessageId,
    this.replyToSenderId,
    this.replyToSenderName,
    this.replyToText,
    this.reactions = const <String, String>{},
  });

  final String id;
  final String jobId;
  final String senderId;
  final String receiverId;
  final String text;
  final DateTime sentAt;
  final DateTime? seenAt;
  final DateTime? deletedForEveryoneAt;
  final String? deletedForEveryoneBy;
  final DateTime? deletedBySenderAt;
  final DateTime? deletedByReceiverAt;
  final String? replyToMessageId;
  final String? replyToSenderId;
  final String? replyToSenderName;
  final String? replyToText;
  final Map<String, String> reactions;

  bool get isDeletedForEveryone => deletedForEveryoneAt != null;

  bool isDeletedFor(String userId) {
    if (isDeletedForEveryone) {
      return false;
    }
    if (userId == senderId) {
      return deletedBySenderAt != null;
    }
    if (userId == receiverId) {
      return deletedByReceiverAt != null;
    }
    return false;
  }

  ChatMessage copyWith({
    String? id,
    String? jobId,
    String? senderId,
    String? receiverId,
    String? text,
    DateTime? sentAt,
    DateTime? seenAt,
    DateTime? deletedForEveryoneAt,
    String? deletedForEveryoneBy,
    DateTime? deletedBySenderAt,
    DateTime? deletedByReceiverAt,
    String? replyToMessageId,
    String? replyToSenderId,
    String? replyToSenderName,
    String? replyToText,
    Map<String, String>? reactions,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      jobId: jobId ?? this.jobId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      text: text ?? this.text,
      sentAt: sentAt ?? this.sentAt,
      seenAt: seenAt ?? this.seenAt,
      deletedForEveryoneAt: deletedForEveryoneAt ?? this.deletedForEveryoneAt,
      deletedForEveryoneBy: deletedForEveryoneBy ?? this.deletedForEveryoneBy,
      deletedBySenderAt: deletedBySenderAt ?? this.deletedBySenderAt,
      deletedByReceiverAt: deletedByReceiverAt ?? this.deletedByReceiverAt,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToSenderId: replyToSenderId ?? this.replyToSenderId,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      replyToText: replyToText ?? this.replyToText,
      reactions: reactions ?? this.reactions,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'job_id': jobId,
    'sender_id': senderId,
    'receiver_id': receiverId,
    'text': text,
    'sent_at': sentAt.toIso8601String(),
    'seen_at': seenAt?.toIso8601String(),
    'deleted_for_everyone_at': deletedForEveryoneAt?.toIso8601String(),
    'deleted_for_everyone_by': deletedForEveryoneBy,
    'deleted_by_sender_at': deletedBySenderAt?.toIso8601String(),
    'deleted_by_receiver_at': deletedByReceiverAt?.toIso8601String(),
    'reply_to_message_id': replyToMessageId,
    'reply_to_sender_id': replyToSenderId,
    'reply_to_sender_name': replyToSenderName,
    'reply_to_text': replyToText,
    'reactions': reactions,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    DateTime? parseNullableDate(String key) {
      final value = json[key];
      if (value == null) {
        return null;
      }
      return DateTime.parse(value as String);
    }

    final rawReactions = json['reactions'];
    final parsedReactions = rawReactions is Map
        ? rawReactions.map<String, String>(
            (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
          )
        : const <String, String>{};

    return ChatMessage(
      id: json['id'] as String,
      jobId: json['job_id'] as String,
      senderId: json['sender_id'] as String,
      receiverId: json['receiver_id'] as String,
      text: json['text'] as String,
      sentAt: DateTime.parse(json['sent_at'] as String),
      seenAt: parseNullableDate('seen_at'),
      deletedForEveryoneAt: parseNullableDate('deleted_for_everyone_at'),
      deletedForEveryoneBy: json['deleted_for_everyone_by'] as String?,
      deletedBySenderAt: parseNullableDate('deleted_by_sender_at'),
      deletedByReceiverAt: parseNullableDate('deleted_by_receiver_at'),
      replyToMessageId: json['reply_to_message_id']?.toString(),
      replyToSenderId: json['reply_to_sender_id']?.toString(),
      replyToSenderName: json['reply_to_sender_name']?.toString(),
      replyToText: json['reply_to_text']?.toString(),
      reactions: parsedReactions,
    );
  }
}

@immutable
class NotificationEvent {
  const NotificationEvent({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.sentAt,
    this.metadata = const <String, dynamic>{},
    this.read = false,
  });

  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final DateTime sentAt;
  final Map<String, dynamic> metadata;
  final bool read;

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'type': type,
    'title': title,
    'body': body,
    'sent_at': sentAt.toIso8601String(),
    'metadata': metadata,
    'read': read,
  };

  factory NotificationEvent.fromJson(Map<String, dynamic> json) {
    return NotificationEvent(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      sentAt: DateTime.parse(json['sent_at'] as String),
      metadata: Map<String, dynamic>.from(
        json['metadata'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      read: json['read'] as bool? ?? false,
    );
  }
}

@immutable
class UserReport {
  const UserReport({
    required this.id,
    required this.reporterId,
    required this.targetUserId,
    required this.reasonCode,
    required this.createdAt,
    this.details,
  });

  final String id;
  final String reporterId;
  final String targetUserId;
  final String reasonCode;
  final String? details;
  final DateTime createdAt;

  String get reasonText {
    final value = details?.trim();
    if (value == null || value.isEmpty) {
      return reasonCode;
    }
    return '$reasonCode: $value';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'reporter_id': reporterId,
    'target_user_id': targetUserId,
    'reason': _encodeReason(reasonCode, details),
    'created_at': createdAt.toIso8601String(),
  };

  factory UserReport.fromJson(Map<String, dynamic> json) {
    final decoded = _decodeReason(json['reason'] as String? ?? '');
    return UserReport(
      id: json['id'] as String,
      reporterId: json['reporter_id'] as String,
      targetUserId: json['target_user_id'] as String,
      reasonCode: decoded.$1,
      details: decoded.$2,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  static String _encodeReason(String reasonCode, String? details) {
    final normalizedReason = reasonCode.trim();
    final normalizedDetails = details?.trim();
    if (normalizedDetails == null || normalizedDetails.isEmpty) {
      return normalizedReason;
    }
    return '$normalizedReason|||$normalizedDetails';
  }

  static (String, String?) _decodeReason(String value) {
    final parts = value.split('|||');
    if (parts.length < 2) {
      return (value, null);
    }
    final code = parts.first.trim();
    final details = parts.sublist(1).join('|||').trim();
    return (code, details.isEmpty ? null : details);
  }
}

@immutable
class ServiceReview {
  const ServiceReview({
    required this.id,
    required this.jobId,
    required this.customerId,
    required this.proId,
    required this.stars,
    required this.createdAt,
    this.comment,
  });

  final String id;
  final String jobId;
  final String customerId;
  final String proId;
  final int stars;
  final String? comment;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'job_id': jobId,
    'customer_id': customerId,
    'pro_id': proId,
    'stars': stars,
    'comment': comment,
    'created_at': createdAt.toIso8601String(),
  };

  factory ServiceReview.fromJson(Map<String, dynamic> json) {
    return ServiceReview(
      id: json['id'] as String,
      jobId: json['job_id'] as String,
      customerId: json['customer_id'] as String,
      proId: json['pro_id'] as String,
      stars: json['stars'] as int,
      comment: json['comment'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

@immutable
class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.actorId,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.createdAt,
    this.metadata = const <String, dynamic>{},
    this.ipAddress,
    this.deviceInfo,
  });

  final String id;
  final String actorId;
  final String action;
  final String entityType;
  final String entityId;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;
  final String? ipAddress;
  final String? deviceInfo;

  Map<String, dynamic> toJson() => {
    'id': id,
    'actor_id': actorId,
    'action': action,
    'entity_type': entityType,
    'entity_id': entityId,
    'created_at': createdAt.toIso8601String(),
    'metadata': metadata,
    'ip_address': ipAddress,
    'device_info': deviceInfo,
  };

  factory AuditEvent.fromJson(Map<String, dynamic> json) {
    return AuditEvent(
      id: json['id'] as String,
      actorId: json['actor_id'] as String,
      action: json['action'] as String,
      entityType: json['entity_type'] as String,
      entityId: json['entity_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      metadata: Map<String, dynamic>.from(
        json['metadata'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      ipAddress: json['ip_address'] as String?,
      deviceInfo: json['device_info'] as String?,
    );
  }
}

@immutable
class ProEarningsSummary {
  const ProEarningsSummary({
    required this.today,
    required this.month,
    required this.lifetime,
    required this.online,
    required this.cash,
    required this.platformFees,
    required this.totalJobs,
    required this.averageRating,
    required this.totalReviews,
    required this.totalEarnings,
    required this.dueToApp,
  });

  final double today;
  final double month;
  final double lifetime;
  final double online;
  final double cash;
  final double platformFees;
  final int totalJobs;
  final double averageRating;
  final int totalReviews;
  final double totalEarnings;
  final double dueToApp;
}

@immutable
class AdminMetrics {
  const AdminMetrics({
    required this.totalCustomers,
    required this.totalPros,
    required this.totalAdmins,
    required this.verifiedPros,
    required this.totalJobs,
    required this.activeJobs,
    required this.completedJobs,
    required this.cancelledJobs,
    required this.activeDisputes,
    required this.totalReports,
    required this.openReports,
    required this.messages24h,
    required this.audits24h,
    required this.onlineVolume,
    required this.cashVolume,
    required this.platformRevenue,
    this.grossRevenue = 0,
    this.totalDueSettled = 0,
    this.estimatedProfit = 0,
  });

  final int totalCustomers;
  final int totalPros;
  final int totalAdmins;
  final int verifiedPros;
  final int totalJobs;
  final int activeJobs;
  final int completedJobs;
  final int cancelledJobs;
  final int activeDisputes;
  final int totalReports;
  final int openReports;
  final int messages24h;
  final int audits24h;
  final double onlineVolume;
  final double cashVolume;
  final double platformRevenue;
  final double grossRevenue;
  final double totalDueSettled;
  final double estimatedProfit;
}
