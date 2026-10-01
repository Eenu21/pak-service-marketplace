import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/repository_provider.dart';
import '../../core/services/local_notification_service.dart';
import '../../domain/models.dart';
import 'app_settings_controller.dart';
import 'auth_controller.dart';

class NotificationRuntimeController {
  NotificationRuntimeController(this._ref)
    : _localNotifications = _ref.read(localNotificationServiceProvider) {
    _localNotifications.setNotificationActionHandler(_handleNotificationAction);
    _ref.listen<AppSettingsState>(
      appSettingsControllerProvider,
      (previous, next) => unawaited(_sync()),
    );
    _ref.listen<AppUser?>(
      currentUserProvider,
      (previous, next) => unawaited(_sync()),
    );
    unawaited(_sync());
  }

  final Ref _ref;
  final LocalNotificationService _localNotifications;

  StreamSubscription<List<NotificationEvent>>? _subscription;
  final Set<String> _seenEventIds = <String>{};
  String? _activeUserId;
  bool _seeded = false;
  bool _permissionAsked = false;
  bool _permissionGranted = false;
  bool _disposed = false;

  Future<void> _handleNotificationAction(
    NotificationResponse response,
    Map<String, dynamic>? payload,
  ) async {
    if (_disposed) {
      return;
    }
    if (response.actionId != LocalNotificationService.replyActionId) {
      return;
    }
    final replyText = response.input?.trim();
    if (replyText == null || replyText.isEmpty) {
      return;
    }
    if (payload == null) {
      return;
    }
    final metadataRaw = payload['metadata'];
    if (metadataRaw is! Map) {
      return;
    }
    final metadata = Map<String, dynamic>.from(metadataRaw);
    final jobId = metadata['job_id'] as String?;
    final senderId = metadata['sender_id'] as String?;
    final activeUser = _ref.read(currentUserProvider);
    if (jobId == null ||
        senderId == null ||
        activeUser == null ||
        activeUser.id == senderId) {
      return;
    }
    try {
      await _ref
          .read(marketplaceRepositoryProvider)
          .sendMessage(
            jobId: jobId,
            senderId: activeUser.id,
            receiverId: senderId,
            text: replyText,
          );
    } catch (_) {
      // Ignore quick-reply failures to avoid crashing notification handlers.
    }
  }

  Future<bool> requestPermissionFromSettings() async {
    await _localNotifications.initialize();
    _permissionAsked = true;
    _permissionGranted = await _localNotifications.requestPermission();
    if (_permissionGranted) {
      await _sync();
    } else {
      await _stop();
    }
    return _permissionGranted;
  }

  Future<bool> sendWorkerJobTestNotification({
    required String workerUserId,
  }) async {
    if (_disposed) {
      return false;
    }

    await _localNotifications.initialize();
    _permissionAsked = true;
    _permissionGranted = await _localNotifications.requestPermission();
    if (!_permissionGranted) {
      return false;
    }

    final now = DateTime.now();
    final event = NotificationEvent(
      id: 'test_worker_job_${now.microsecondsSinceEpoch}',
      userId: workerUserId,
      type: 'job_posted',
      title: 'New Plumbing Job Nearby',
      body:
          'Umar posted a plumbing job: Kitchen pipe leakage in Gulshan-e-Iqbal. Budget PKR 3,500. Tap to view and send offer.',
      sentAt: now,
      metadata: <String, dynamic>{
        'test': true,
        'category': 'plumbing',
      },
    );
    await _localNotifications.showNotification(event);
    return true;
  }

  Future<void> _sync() async {
    if (_disposed) {
      return;
    }
    final user = _ref.read(currentUserProvider);
    final settings = _ref.read(appSettingsControllerProvider);
    final enabled =
        user != null &&
        settings.pushNotifications &&
        user.notificationsEnabled &&
        !user.blocked;

    if (!enabled) {
      await _stop();
      return;
    }

    await _localNotifications.initialize();
    if (!_permissionAsked) {
      _permissionAsked = true;
      _permissionGranted = await _localNotifications.requestPermission();
    }
    if (!_permissionGranted) {
      await _stop();
      return;
    }

    if (_activeUserId == user.id && _subscription != null) {
      return;
    }
    await _startForUser(user.id);
  }

  Future<void> _startForUser(String userId) async {
    await _subscription?.cancel();
    _subscription = null;
    _activeUserId = userId;
    _seeded = false;
    _seenEventIds.clear();

    _subscription = _ref
        .read(marketplaceRepositoryProvider)
        .watchNotifications(userId)
        .listen((events) async {
          if (!_seeded) {
            _seenEventIds.addAll(events.map((e) => e.id));
            _seeded = true;
            return;
          }
          final ordered = events.toList(growable: false)
            ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
          for (final event in ordered) {
            if (_seenEventIds.contains(event.id)) {
              continue;
            }
            _seenEventIds.add(event.id);
            await _localNotifications.showNotification(event);
          }
        });
  }

  Future<void> _stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _activeUserId = null;
    _seeded = false;
    _seenEventIds.clear();
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
  }
}

final notificationRuntimeProvider = Provider<NotificationRuntimeController>((
  ref,
) {
  final controller = NotificationRuntimeController(ref);
  ref.onDispose(() => unawaited(controller.dispose()));
  return controller;
});
