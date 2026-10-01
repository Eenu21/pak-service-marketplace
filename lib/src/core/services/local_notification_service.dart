import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';

const String _replyActionId = 'reply_action';
const String _openChatActionId = 'open_chat_action';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  LocalNotificationService.pushBackgroundNotificationResponse(response);
}

class LocalNotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  StreamSubscription<NotificationResponse>? _backgroundSubscription;
  Future<void> Function(
    NotificationResponse response,
    Map<String, dynamic>? payload,
  )?
  _notificationActionHandler;

  static final StreamController<NotificationResponse> _backgroundResponses =
      StreamController<NotificationResponse>.broadcast();

  static void pushBackgroundNotificationResponse(
    NotificationResponse response,
  ) {
    if (_backgroundResponses.isClosed) {
      return;
    }
    _backgroundResponses.add(response);
  }

  static String get replyActionId => _replyActionId;

  void setNotificationActionHandler(
    Future<void> Function(
      NotificationResponse response,
      Map<String, dynamic>? payload,
    ) handler,
  ) {
    _notificationActionHandler = handler;
  }

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'marketplace_events',
    'Marketplace Alerts',
    description: 'Job, bid, message, and status notifications.',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _workTimerChannel =
      AndroidNotificationChannel(
    'work_timer',
    'Work Timer',
    description: 'Ongoing job timer notifications.',
    importance: Importance.low,
  );

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    if (kIsWeb) {
      _initialized = true;
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    _backgroundSubscription ??= _backgroundResponses.stream.listen(
      _handleNotificationResponse,
    );

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.createNotificationChannel(_channel);
    await androidImpl?.createNotificationChannel(_workTimerChannel);

    _initialized = true;
  }

  Map<String, dynamic>? _decodePayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _handleNotificationResponse(NotificationResponse response) async {
    final handler = _notificationActionHandler;
    if (handler == null) {
      return;
    }
    await handler(response, _decodePayload(response.payload));
  }

  Future<bool> requestPermission() async {
    if (kIsWeb) {
      return true;
    }
    await initialize();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await androidImpl?.requestNotificationsPermission() ?? true;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosImpl = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await iosImpl?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      final macImpl = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      return await macImpl?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return true;
  }

  Future<void> showNotification(NotificationEvent event) async {
    if (kIsWeb) {
      return;
    }
    await initialize();

    final payload = jsonEncode(event.toJson());
    final metadata = event.metadata;
    Uint8List? messageAvatarBytes() {
      final avatar = metadata['sender_avatar_url'];
      if (avatar is! String || avatar.trim().isEmpty) {
        return null;
      }
      final normalized = avatar.trim();
      final comma = normalized.indexOf(',');
      final base64Text = normalized.startsWith('data:')
          ? (comma < 0 ? '' : normalized.substring(comma + 1))
          : normalized;
      if (base64Text.isEmpty) {
        return null;
      }
      try {
        return base64Decode(base64Text);
      } catch (_) {
        return null;
      }
    }

    AndroidNotificationDetails androidDetails;
    if (event.type == 'message') {
      final senderName =
          (metadata['sender_name'] as String?)?.trim().isNotEmpty == true
          ? (metadata['sender_name'] as String).trim()
          : event.title;
      final jobTitle = (metadata['job_title'] as String?)?.trim();
      final avatarBytes = messageAvatarBytes();
      final sender = Person(
        name: senderName,
        icon: avatarBytes == null ? null : ByteArrayAndroidIcon(avatarBytes),
      );
      final messagingStyle = MessagingStyleInformation(
        const Person(name: 'You'),
        conversationTitle: jobTitle,
        groupConversation: false,
        messages: <Message>[
          Message(event.body, event.sentAt, sender),
        ],
      );
      androidDetails = AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        styleInformation: messagingStyle,
        largeIcon: avatarBytes == null ? null : ByteArrayAndroidBitmap(avatarBytes),
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            _replyActionId,
            'Reply',
            allowGeneratedReplies: true,
            semanticAction: SemanticAction.reply,
            inputs: <AndroidNotificationActionInput>[
              AndroidNotificationActionInput(label: 'Type message'),
            ],
          ),
          AndroidNotificationAction(
            _openChatActionId,
            'Open chat',
            showsUserInterface: true,
          ),
        ],
      );
    } else {
      androidDetails = AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
      );
    }

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.show(
      event.id.hashCode & 0x7fffffff,
      event.title,
      event.body,
      details,
      payload: payload,
    );
  }

  int _workTimerId(String jobId) =>
      'work_timer_$jobId'.hashCode & 0x7fffffff;

  Future<void> showWorkTimerNotification({
    required String jobId,
    required String title,
    required DateTime startedAt,
  }) async {
    if (kIsWeb) {
      return;
    }
    await initialize();

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _workTimerChannel.id,
        _workTimerChannel.name,
        channelDescription: _workTimerChannel.description,
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        onlyAlertOnce: true,
        showWhen: true,
        when: startedAt.millisecondsSinceEpoch,
        usesChronometer: true,
        category: AndroidNotificationCategory.stopwatch,
        playSound: false,
        enableVibration: false,
        visibility: NotificationVisibility.public,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
      ),
    );

    await _plugin.show(
      _workTimerId(jobId),
      'Work in progress',
      title,
      details,
    );
  }

  Future<void> cancelWorkTimerNotification(String jobId) async {
    if (kIsWeb) {
      return;
    }
    await initialize();
    await _plugin.cancel(_workTimerId(jobId));
  }
}

final localNotificationServiceProvider = Provider<LocalNotificationService>((
  _,
) {
  return LocalNotificationService();
});
