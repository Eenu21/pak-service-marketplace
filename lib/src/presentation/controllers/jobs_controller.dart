import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/config/repository_provider.dart';
import '../../core/services/location_service.dart';
import '../../data/repositories/marketplace_repository.dart';
import '../../domain/models.dart';
import 'auth_controller.dart';

bool _isEffectivePro(AppUser? user) {
  if (user == null) {
    return false;
  }
  if (user.role == UserRole.pro) {
    return true;
  }
  final hasPayment = (user.paymentAccount ?? '').trim().isNotEmpty;
  return user.preferredCategories.isNotEmpty ||
      user.cnicVerified ||
      user.policeVerified ||
      hasPayment;
}

final selectedJobCategoryProvider = StateProvider<JobCategory>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user != null &&
      _isEffectivePro(user) &&
      user.preferredCategories.isNotEmpty) {
    return user.preferredCategories.first;
  }
  return JobCategory.plumbing;
});

class NearbyPro {
  const NearbyPro({
    required this.user,
    required this.location,
    required this.distanceKm,
  });

  final AppUser user;
  final SavedLocation? location;
  final double? distanceKm;
}

final currentPositionProvider = FutureProvider.autoDispose<LocationResult>((
  ref,
) async {
  final locationService = ref.read(locationServiceProvider);
  final userRole = ref.watch(currentUserProvider.select((user) => user?.role));
  final aggressive = userRole == UserRole.customer;
  return locationService.getCurrentPosition(
    aggressive: aggressive,
    requestPermissionIfNeeded: false,
  );
});

final nearbyJobsProvider = StreamProvider.autoDispose<List<Job>>((ref) {
  final repository = ref.watch(marketplaceRepositoryProvider);
  final selectedCategory = ref.watch(selectedJobCategoryProvider);
  final user = ref.watch(currentUserProvider);
  if (!_isEffectivePro(user)) {
    return const Stream<List<Job>>.empty();
  }
  return repository
      .watchAllJobs()
      .map((jobs) {
        final openJobs = jobs
            .where(
              (job) =>
                  job.status == JobStatus.available ||
                  job.status == JobStatus.posted,
            )
            .toList(growable: false);
        final preferred = user!.preferredCategories.toSet();
        if (preferred.isNotEmpty && !preferred.contains(selectedCategory)) {
          return const <Job>[];
        }
        final visibleJobs = openJobs
            .where((job) => job.category == selectedCategory)
            .toList(growable: false);
        visibleJobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return visibleJobs;
      })
      .distinct(_sameJobList);
});

final nearbyProsProvider = StreamProvider.autoDispose<List<NearbyPro>>((ref) {
  final repository = ref.watch(marketplaceRepositoryProvider);
  final category = ref.watch(selectedJobCategoryProvider);
  final position = ref.watch(currentPositionProvider).value?.position;
  final user = ref.watch(currentUserProvider);
  if (_isEffectivePro(user)) {
    return const Stream<List<NearbyPro>>.empty();
  }

  return repository
      .watchAllUsers(includeLocations: true)
      .map((users) {
        final filtered = users
            .where((candidate) {
              if (candidate.role != UserRole.pro || candidate.blocked) {
                return false;
              }
              if (!candidate.isVerifiedPro) {
                return false;
              }
              if (!candidate.preferredCategories.contains(category)) {
                return false;
              }
              return true;
            })
            .map((pro) {
              if (pro.savedLocations.isEmpty) {
                return NearbyPro(user: pro, location: null, distanceKm: null);
              }
              final latestLocation = pro.savedLocations.reduce(
                (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
              );
              if (position == null) {
                return NearbyPro(
                  user: pro,
                  location: latestLocation,
                  distanceKm: null,
                );
              }
              final distanceMeters = Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                latestLocation.latitude,
                latestLocation.longitude,
              );
              return NearbyPro(
                user: pro,
                location: latestLocation,
                distanceKm: distanceMeters / 1000,
              );
            })
            .where(
              (pro) =>
                  position == null ||
                  pro.distanceKm == null ||
                  pro.distanceKm! <= 20,
            )
            .toList(growable: false);

        filtered.sort((a, b) {
          if (position == null) {
            final ratingCompare = b.user.rating.compareTo(a.user.rating);
            if (ratingCompare != 0) {
              return ratingCompare;
            }
            return b.user.totalReviews.compareTo(a.user.totalReviews);
          }
          final aDistance = a.distanceKm;
          final bDistance = b.distanceKm;
          if (aDistance == null && bDistance == null) {
            return 0;
          }
          if (aDistance == null) {
            return 1;
          }
          if (bDistance == null) {
            return -1;
          }
          return aDistance.compareTo(bDistance);
        });
        return filtered;
      })
      .distinct(_sameNearbyProsList);
});

final jobsForCurrentUserProvider = StreamProvider<List<Job>>((ref) {
  final repository = ref.watch(marketplaceRepositoryProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return const Stream<List<Job>>.empty();
  }
  if (_isEffectivePro(user)) {
    return repository.watchJobsForPro(user.id);
  }
  return repository.watchJobsForUser(user.id);
});

final jobByIdProvider = StreamProvider.family<Job?, String>((ref, jobId) {
  return ref.watch(marketplaceRepositoryProvider).watchJob(jobId);
});

final bidsForJobProvider = StreamProvider.family<List<Bid>, String>((
  ref,
  jobId,
) {
  return ref.watch(marketplaceRepositoryProvider).watchBids(jobId);
});

final usersByIdProvider = StreamProvider<Map<String, AppUser>>((ref) {
  final repository = ref.watch(marketplaceRepositoryProvider);
  return repository.watchAllUsers(includeLocations: false).map((users) {
    final map = <String, AppUser>{};
    for (final user in users) {
      map[user.id] = user;
    }
    return map;
  });
});

final completedJobsByProProvider = StreamProvider<Map<String, int>>((ref) {
  final repository = ref.watch(marketplaceRepositoryProvider);
  return repository.watchAllJobs().map((jobs) {
    final counts = <String, int>{};
    for (final job in jobs) {
      final proId = job.assignedProId;
      if (proId == null) {
        continue;
      }
      final completed =
          job.status == JobStatus.completed ||
          job.status == JobStatus.paidClosed;
      if (!completed) {
        continue;
      }
      counts[proId] = (counts[proId] ?? 0) + 1;
    }
    return counts;
  });
});

bool _sameJobList(List<Job> previous, List<Job> next) {
  if (identical(previous, next)) {
    return true;
  }
  if (previous.length != next.length) {
    return false;
  }
  for (var i = 0; i < previous.length; i++) {
    final a = previous[i];
    final b = next[i];
    if (a.id != b.id || a.updatedAt != b.updatedAt || a.status != b.status) {
      return false;
    }
  }
  return true;
}

bool _sameNearbyProsList(List<NearbyPro> previous, List<NearbyPro> next) {
  if (identical(previous, next)) {
    return true;
  }
  if (previous.length != next.length) {
    return false;
  }
  for (var i = 0; i < previous.length; i++) {
    final a = previous[i];
    final b = next[i];
    final aLocation = a.location;
    final bLocation = b.location;
    if (a.user.id != b.user.id) {
      return false;
    }
    if (a.user.updatedAt != b.user.updatedAt) {
      return false;
    }
    if (aLocation?.id != bLocation?.id ||
        aLocation?.createdAt != bLocation?.createdAt) {
      return false;
    }
  }
  return true;
}

class JobsController {
  JobsController(this._repository);

  final MarketplaceRepository _repository;

  Future<Job> postJob(JobPostInput input) => _repository.postJob(input);

  Future<void> updateJobDetails(JobUpdateInput input) =>
      _repository.updateJobDetails(input);

  Future<Bid> submitBid(BidInput input) => _repository.submitBid(input);

  Future<void> acceptBid({
    required String jobId,
    required String bidId,
    required String customerId,
  }) {
    return _repository.acceptBid(
      jobId: jobId,
      bidId: bidId,
      customerId: customerId,
    );
  }

  Future<void> updateStatus({
    required String jobId,
    required JobStatus status,
    required String actorId,
  }) {
    return _repository.updateJobStatus(
      jobId: jobId,
      status: status,
      actorId: actorId,
    );
  }

  Future<void> requestCompletion({
    required String jobId,
    required String proId,
  }) {
    return _repository.requestJobCompletion(jobId: jobId, proId: proId);
  }

  Future<void> respondToCompletion({
    required String jobId,
    required String customerId,
    required bool approved,
    double? rating,
  }) {
    return _repository.respondToJobCompletion(
      jobId: jobId,
      customerId: customerId,
      approved: approved,
      rating: rating,
    );
  }

  Future<void> startWork({required String jobId, required String actorId}) {
    return _repository.startWork(jobId: jobId, actorId: actorId);
  }

  Future<void> cancelJob({
    required String jobId,
    required String actorId,
    required String reason,
  }) {
    return _repository.cancelJob(
      jobId: jobId,
      actorId: actorId,
      reason: reason,
    );
  }

  Future<void> raiseDispute({
    required String jobId,
    required String actorId,
    required String reason,
  }) {
    return _repository.raiseDispute(
      jobId: jobId,
      actorId: actorId,
      reason: reason,
    );
  }
}

final jobsControllerProvider = Provider<JobsController>((ref) {
  return JobsController(ref.watch(marketplaceRepositoryProvider));
});
