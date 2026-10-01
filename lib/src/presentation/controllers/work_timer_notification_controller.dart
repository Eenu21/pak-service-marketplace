import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/job_timer_utils.dart';
import '../../core/services/local_notification_service.dart';
import '../../domain/models.dart';
import 'auth_controller.dart';
import 'jobs_controller.dart';

class WorkTimerNotificationController {
  WorkTimerNotificationController(this._ref)
    : _notifications = _ref.read(localNotificationServiceProvider) {
    _ref.listen<AppUser?>(
      currentUserProvider,
      (previous, next) => unawaited(_handleUser(next)),
    );
    _ref.listen<AsyncValue<List<Job>>>(
      jobsForCurrentUserProvider,
      (previous, next) => unawaited(_handleJobs(next)),
    );
    unawaited(_handleUser(_ref.read(currentUserProvider)));
  }

  final Ref _ref;
  final LocalNotificationService _notifications;
  final Set<String> _activeJobIds = <String>{};
  AppUser? _currentUser;

  Future<void> _handleUser(AppUser? user) async {
    _currentUser = user;
    if (user == null || user.role != UserRole.pro) {
      await _clearAll();
    }
  }

  Future<void> _handleJobs(AsyncValue<List<Job>> value) async {
    final user = _currentUser;
    if (user == null || user.role != UserRole.pro) {
      return;
    }
    final jobs = value.valueOrNull ?? const <Job>[];
    final nextActive = <String>{};
    for (final job in jobs) {
      if (job.status != JobStatus.inProcess) {
        continue;
      }
      final startedAt = workStartedAt(job);
      if (startedAt == null) {
        continue;
      }
      nextActive.add(job.id);
      try {
        await _notifications.showWorkTimerNotification(
          jobId: job.id,
          title: job.title,
          startedAt: startedAt,
        );
      } catch (_) {
        // Ignore notification failures.
      }
    }
    final toCancel = _activeJobIds.difference(nextActive);
    for (final jobId in toCancel) {
      try {
        await _notifications.cancelWorkTimerNotification(jobId);
      } catch (_) {
        // Ignore notification failures.
      }
    }
    _activeJobIds
      ..clear()
      ..addAll(nextActive);
  }

  Future<void> _clearAll() async {
    for (final jobId in _activeJobIds) {
      try {
        await _notifications.cancelWorkTimerNotification(jobId);
      } catch (_) {
        // Ignore notification failures.
      }
    }
    _activeJobIds.clear();
  }

  Future<void> dispose() async {
    await _clearAll();
  }
}

final workTimerNotificationProvider =
    Provider<WorkTimerNotificationController>((ref) {
      final controller = WorkTimerNotificationController(ref);
      ref.onDispose(() => unawaited(controller.dispose()));
      return controller;
    });
