import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/repository_provider.dart';
import '../../domain/models.dart';

final adminMetricsProvider = FutureProvider<AdminMetrics>((ref) {
  return ref.watch(marketplaceRepositoryProvider).fetchAdminMetrics();
});

final allUsersProvider = StreamProvider<List<AppUser>>((ref) {
  return ref.watch(marketplaceRepositoryProvider).watchAllUsers(
        includeLocations: false,
      );
});

final allJobsProvider = StreamProvider<List<Job>>((ref) {
  return ref.watch(marketplaceRepositoryProvider).watchAllJobs();
});

final allPaymentsProvider = StreamProvider<List<PaymentRecord>>((ref) {
  return ref.watch(marketplaceRepositoryProvider).watchAllPayments();
});

final auditEventsProvider = StreamProvider<List<AuditEvent>>((ref) {
  return ref.watch(marketplaceRepositoryProvider).watchAuditEvents();
});

final userReportsProvider = StreamProvider<List<UserReport>>((ref) {
  return ref.watch(marketplaceRepositoryProvider).watchUserReports();
});
