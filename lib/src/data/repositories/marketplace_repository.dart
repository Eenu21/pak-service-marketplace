import '../../domain/models.dart';

class RegisterInput {
  const RegisterInput({
    required this.fullName,
    required this.email,
    required this.phone,
    required this.password,
    required this.role,
    required this.acceptance,
    this.preferredCategories = const <JobCategory>[],
  });

  final String fullName;
  final String email;
  final String phone;
  final String password;
  final UserRole role;
  final TermsAcceptance acceptance;
  final List<JobCategory> preferredCategories;

  List<JobCategory> normalizedPreferredCategoriesForRole(UserRole role) {
    if (role != UserRole.pro) {
      return const <JobCategory>[];
    }
    return preferredCategories.toSet().toList(growable: false);
  }

  void validateForRole(UserRole role) {
    final normalized = normalizedPreferredCategoriesForRole(role);
    if (role == UserRole.pro && normalized.isEmpty) {
      throw StateError('Please select at least one preferred category.');
    }
  }
}

class LoginInput {
  const LoginInput({required this.email, required this.password});

  final String email;
  final String password;
}

class JobPostInput {
  const JobPostInput({
    required this.customerId,
    required this.category,
    required this.title,
    required this.description,
    required this.fixedPrice,
    required this.latitude,
    required this.longitude,
    required this.maskedAddress,
    required this.exactAddress,
    this.imageAttachments = const <String>[],
  });

  final String customerId;
  final JobCategory category;
  final String title;
  final String description;
  final double fixedPrice;
  final double latitude;
  final double longitude;
  final String maskedAddress;
  final String exactAddress;
  final List<String> imageAttachments;
}

class JobUpdateInput {
  const JobUpdateInput({
    required this.jobId,
    required this.actorId,
    required this.title,
    required this.description,
    required this.fixedPrice,
    required this.latitude,
    required this.longitude,
    required this.maskedAddress,
    required this.exactAddress,
  });

  final String jobId;
  final String actorId;
  final String title;
  final String description;
  final double fixedPrice;
  final double latitude;
  final double longitude;
  final String maskedAddress;
  final String exactAddress;
}

class BidInput {
  const BidInput({
    required this.jobId,
    required this.proId,
    required this.amount,
    this.notes,
  });

  final String jobId;
  final String proId;
  final double amount;
  final String? notes;
}

class PaymentRequest {
  const PaymentRequest({
    required this.jobId,
    required this.customerId,
    required this.proId,
    required this.amount,
    required this.method,
    this.externalReference,
  });

  final String jobId;
  final String customerId;
  final String proId;
  final double amount;
  final PaymentMethod method;
  final String? externalReference;
}

class PaymentCalculation {
  const PaymentCalculation({
    required this.gross,
    required this.fee,
    required this.net,
  });

  final double gross;
  final double fee;
  final double net;
}

abstract class MarketplaceRepository {
  Stream<AppUser?> watchCurrentUser();
  Future<AppUser?> getCurrentUser();
  Future<AppUser> register(RegisterInput input);
  Future<AppUser> signIn(LoginInput input);
  Future<void> signOut();
  Future<void> updateProfile(AppUser user);
  Future<AppUser> upgradeToProfessional({
    required List<JobCategory> preferredCategories,
  });
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  Stream<List<AppUser>> watchAllUsers({bool includeLocations = false});
  Future<void> verifyPro({
    required String userId,
    required bool cnicVerified,
    required bool policeVerified,
  });
  Future<void> setProVerification({
    required String actorId,
    required String userId,
    required bool cnicVerified,
    required bool policeVerified,
  });
  Future<void> setUserBlockStatus({
    required String actorId,
    required String targetUserId,
    required bool blocked,
    required String reason,
  });

  Future<void> saveLocation({
    required String userId,
    required SavedLocation location,
  });

  Stream<List<Job>> watchNearbyJobs({
    required JobCategory category,
    required double latitude,
    required double longitude,
    double radiusKm,
  });

  Stream<List<Job>> watchJobsForUser(String userId);
  Stream<List<Job>> watchJobsForPro(String proId);
  Stream<List<Job>> watchAllJobs();
  Stream<Job?> watchJob(String jobId);
  Stream<List<Bid>> watchBids(String jobId);
  Future<Job> postJob(JobPostInput input);
  Future<void> updateJobDetails(JobUpdateInput input);
  Future<Bid> submitBid(BidInput input);
  Future<void> acceptBid({
    required String jobId,
    required String bidId,
    required String customerId,
  });
  Future<void> updateJobStatus({
    required String jobId,
    required JobStatus status,
    required String actorId,
  });
  Future<void> requestJobCompletion({
    required String jobId,
    required String proId,
  });
  Future<void> respondToJobCompletion({
    required String jobId,
    required String customerId,
    required bool approved,
    double? rating,
  });
  Future<void> startWork({required String jobId, required String actorId});
  Future<void> cancelJob({
    required String jobId,
    required String actorId,
    required String reason,
  });
  Future<void> raiseDispute({
    required String jobId,
    required String actorId,
    required String reason,
  });

  PaymentCalculation calculatePayment(double amount);
  PaymentCalculation calculatePaymentForCategory({
    required double amount,
    required JobCategory category,
  });
  Future<PaymentRecord> recordPayment(PaymentRequest request);
  Future<void> settleProDue({
    required String proId,
    required PaymentMethod method,
    String? externalReference,
  });
  Stream<List<PaymentRecord>> watchPaymentsForUser(String userId);
  Stream<List<PaymentRecord>> watchPaymentsForPro(String proId);
  Stream<List<PaymentRecord>> watchAllPayments();

  Stream<List<ChatMessage>> watchMessages(String jobId);
  Future<ChatMessage> sendMessage({
    required String jobId,
    required String senderId,
    required String receiverId,
    required String text,
    String? replyToMessageId,
    String? replyToSenderId,
    String? replyToSenderName,
    String? replyToText,
  });
  Future<void> setMessageReaction({
    required String messageId,
    required String userId,
    String? emoji,
  });
  Future<void> markMessagesSeen({
    required String jobId,
    required String viewerId,
    required String peerId,
  });
  Future<void> deleteMessageForMe({
    required String messageId,
    required String userId,
  });
  Future<void> deleteMessageForEveryone({
    required String messageId,
    required String userId,
  });

  Stream<List<NotificationEvent>> watchNotifications(String userId);
  Future<void> markNotificationRead(String notificationId);

  Stream<List<AuditEvent>> watchAuditEvents({
    String? entityType,
    String? entityId,
  });
  Future<void> addAuditEvent(AuditEvent event);

  Stream<List<UserReport>> watchUserReports();
  Future<void> reportUser({
    required String reporterId,
    required String targetUserId,
    required String reasonCode,
    String? details,
  });
  Future<void> blockUser({
    required String actorId,
    required String targetUserId,
    required String reason,
  });
  Future<void> setAdminAccess({
    required String actorId,
    required String targetUserId,
    required AdminRank rank,
    required List<AdminPermission> permissions,
  });

  Future<ProEarningsSummary> fetchEarningsSummary(String proId);
  Future<AdminMetrics> fetchAdminMetrics();

  double get commissionRate;
  Map<JobCategory, double> get commissionRatesByCategory;
  double commissionRateForCategory(JobCategory category);
  Future<void> setCommissionRate(double rate, {required String actorId});
  Future<void> setCategoryCommissionRate({
    required JobCategory category,
    required double rate,
    required String actorId,
  });

  void dispose();
}
