import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/repository_provider.dart';
import '../../domain/models.dart';

final chatMessagesProvider = StreamProvider.family<List<ChatMessage>, String>((
  ref,
  jobId,
) {
  return ref.watch(marketplaceRepositoryProvider).watchMessages(jobId);
});

final notificationsProvider =
    StreamProvider.family<List<NotificationEvent>, String>((ref, userId) {
      return ref
          .watch(marketplaceRepositoryProvider)
          .watchNotifications(userId);
    });

final appUserByIdProvider = StreamProvider.family<AppUser?, String>((
  ref,
  userId,
) {
  return ref
      .watch(marketplaceRepositoryProvider)
      .watchAllUsers(includeLocations: false)
      .map((users) {
        for (final user in users) {
          if (user.id == userId) {
            return user;
          }
        }
        return null;
      });
});

class ChatController {
  ChatController(this._ref);

  final Ref _ref;

  Future<void> send({
    required String jobId,
    required String senderId,
    required String receiverId,
    required String text,
    String? replyToMessageId,
    String? replyToSenderId,
    String? replyToSenderName,
    String? replyToText,
  }) {
    return _ref
        .read(marketplaceRepositoryProvider)
        .sendMessage(
          jobId: jobId,
          senderId: senderId,
          receiverId: receiverId,
          text: text,
          replyToMessageId: replyToMessageId,
          replyToSenderId: replyToSenderId,
          replyToSenderName: replyToSenderName,
          replyToText: replyToText,
        );
  }

  Future<void> setReaction({
    required String messageId,
    required String userId,
    String? emoji,
  }) {
    return _ref
        .read(marketplaceRepositoryProvider)
        .setMessageReaction(messageId: messageId, userId: userId, emoji: emoji);
  }

  Future<void> markSeen({
    required String jobId,
    required String viewerId,
    required String peerId,
  }) {
    return _ref
        .read(marketplaceRepositoryProvider)
        .markMessagesSeen(jobId: jobId, viewerId: viewerId, peerId: peerId);
  }

  Future<void> deleteForMe({
    required String messageId,
    required String userId,
  }) {
    return _ref
        .read(marketplaceRepositoryProvider)
        .deleteMessageForMe(messageId: messageId, userId: userId);
  }

  Future<void> deleteForEveryone({
    required String messageId,
    required String userId,
  }) {
    return _ref
        .read(marketplaceRepositoryProvider)
        .deleteMessageForEveryone(messageId: messageId, userId: userId);
  }

  Future<void> markMessageNotificationsRead({
    required String userId,
    required String jobId,
    required String peerId,
  }) async {
    final events = await _ref
        .read(marketplaceRepositoryProvider)
        .watchNotifications(userId)
        .first;
    for (final event in events) {
      if (event.read || event.type != 'message') {
        continue;
      }
      final sameJob = event.metadata['job_id'] == jobId;
      final sameSender = event.metadata['sender_id'] == peerId;
      if (!sameJob || !sameSender) {
        continue;
      }
      await _ref
          .read(marketplaceRepositoryProvider)
          .markNotificationRead(event.id);
    }
  }
}

final chatControllerProvider = Provider<ChatController>((ref) {
  return ChatController(ref);
});
