import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/config/repository_provider.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/avatar_utils.dart';
import '../../core/services/formatters.dart';
import '../../domain/models.dart';
import '../controllers/auth_controller.dart';
import '../controllers/chat_controller.dart';
import '../controllers/jobs_controller.dart';
import '../widgets/chat_input_part.dart';
import '../widgets/voice_message_widget.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.jobId, required this.peerId});

  final String jobId;
  final String peerId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  static const List<String> _reactionOptions = <String>[
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '🙏',
  ];
  final _messageController = TextEditingController();
  final _messageSearchController = TextEditingController();
  final Set<String> _knownMessageIds = <String>{};
  bool _sending = false;
  bool _seededMessages = false;
  bool _markingSeen = false;
  bool _markedNotificationsForThread = false;
  bool _searchVisible = false;
  String _messageSearchQuery = '';
  ChatMessage? _replyingTo;

  @override
  void dispose() {
    _messageController.dispose();
    _messageSearchController.dispose();
    super.dispose();
  }

  String _formatClock(DateTime value) {
    return DateFormat('h:mm a').format(value);
  }

  String _formatDay(DateTime value) {
    return DateFormat('EEE, d MMM').format(value);
  }

  String _replyPreviewText(ChatMessage message) {
    if (message.isDeletedForEveryone) {
      return 'This message was deleted';
    }
    final voice = VoiceMessageCodec.tryDecode(message.text);
    if (voice != null) {
      return 'Voice message (${formatVoiceDuration(voice.duration)})';
    }
    return message.text;
  }

  String _searchableMessageText(ChatMessage message) {
    if (message.isDeletedForEveryone) {
      return 'This message was deleted';
    }
    final voice = VoiceMessageCodec.tryDecode(message.text);
    if (voice != null) {
      return 'voice message ${formatVoiceDuration(voice.duration)}';
    }
    return message.text;
  }

  Future<void> _sendMessage({required String content}) async {
    final currentUser = ref.read(currentUserProvider);
    final peer = ref.read(appUserByIdProvider(widget.peerId)).valueOrNull;
    final text = content.trim();
    if (currentUser == null || text.isEmpty) {
      return;
    }
    final reply = _replyingTo;
    final replySenderName = reply == null
        ? null
        : reply.senderId == currentUser.id
        ? currentUser.fullName
        : (peer?.fullName ?? 'User');
    setState(() => _sending = true);
    try {
      await ref
          .read(chatControllerProvider)
          .send(
            jobId: widget.jobId,
            senderId: currentUser.id,
            receiverId: widget.peerId,
            text: text,
            replyToMessageId: reply?.id,
            replyToSenderId: reply?.senderId,
            replyToSenderName: replySenderName,
            replyToText: reply == null ? null : _replyPreviewText(reply),
          );
      if (content == _messageController.text.trim()) {
        _messageController.clear();
      }
      if (mounted) {
        setState(() => _replyingTo = null);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _send() async {
    await _sendMessage(content: _messageController.text);
  }

  Future<void> _sendVoice(String encodedVoicePayload) async {
    await _sendMessage(content: encodedVoicePayload);
  }

  bool _isChatUnlocked({required Job? job, required String? currentUserId}) {
    if (job == null || currentUserId == null) {
      return false;
    }
    final assignedProId = job.assignedProId;
    if (assignedProId == null || job.status.index < JobStatus.inProcess.index) {
      return false;
    }
    final participants = <String>{job.customerId, assignedProId};
    return participants.contains(currentUserId) &&
        participants.contains(widget.peerId) &&
        currentUserId != widget.peerId;
  }

  Future<void> _showReportDialog(AppUser currentUser) async {
    var selectedCode = _reportReasonOptions.first.code;
    final otherController = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              final isOther = selectedCode == 'other';
              return AlertDialog(
                title: const Text('Report User'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DropdownButtonFormField<String>(
                      initialValue: selectedCode,
                      decoration: const InputDecoration(labelText: 'Reason'),
                      items: _reportReasonOptions
                          .map(
                            (option) => DropdownMenuItem<String>(
                              value: option.code,
                              child: Text(option.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => selectedCode = value);
                      },
                    ),
                    if (isOther) ...<Widget>[
                      const SizedBox(height: 10),
                      TextField(
                        controller: otherController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Please describe the issue',
                        ),
                      ),
                    ],
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final details = selectedCode == 'other'
                          ? otherController.text.trim()
                          : null;
                      if (selectedCode == 'other' && details!.isEmpty) {
                        return;
                      }
                      try {
                        await ref
                            .read(marketplaceRepositoryProvider)
                            .reportUser(
                              reporterId: currentUser.id,
                              targetUserId: widget.peerId,
                              reasonCode: selectedCode,
                              details: details,
                            );
                        if (!context.mounted) {
                          return;
                        }
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Report submitted to admin.'),
                          ),
                        );
                      } catch (error) {
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error.toString())),
                        );
                      }
                    },
                    child: const Text('Submit'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      otherController.dispose();
    }
  }

  Future<void> _showMessageActions({
    required ChatMessage message,
    required String currentUserId,
  }) async {
    final canDeleteForEveryone =
        message.senderId == currentUserId && !message.isDeletedForEveryone;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _reactionOptions
                        .map(
                          (emoji) => InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () {
                              Navigator.of(context).pop('react:$emoji');
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 23),
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Reply'),
                onTap: () => Navigator.of(context).pop('reply'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete for me'),
                onTap: () => Navigator.of(context).pop('delete_me'),
              ),
              if (canDeleteForEveryone)
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined),
                  title: const Text('Delete for everyone'),
                  onTap: () => Navigator.of(context).pop('delete_everyone'),
                ),
            ],
          ),
        );
      },
    );

    if (selected == null) {
      return;
    }
    try {
      if (selected.startsWith('react:')) {
        final emoji = selected.substring('react:'.length);
        final currentEmoji = message.reactions[currentUserId];
        await ref
            .read(chatControllerProvider)
            .setReaction(
              messageId: message.id,
              userId: currentUserId,
              emoji: currentEmoji == emoji ? null : emoji,
            );
      } else if (selected == 'reply') {
        _setReplyTarget(message);
      } else if (selected == 'delete_me') {
        await ref
            .read(chatControllerProvider)
            .deleteForMe(messageId: message.id, userId: currentUserId);
      } else if (selected == 'delete_everyone') {
        await ref
            .read(chatControllerProvider)
            .deleteForEveryone(messageId: message.id, userId: currentUserId);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _setReplyTarget(ChatMessage message) {
    if (!mounted) {
      return;
    }
    setState(() => _replyingTo = message);
  }

  void _cancelReplyTarget() {
    if (!mounted) {
      return;
    }
    setState(() => _replyingTo = null);
  }

  Map<String, int> _reactionCounts(ChatMessage message) {
    final counts = <String, int>{};
    for (final emoji in message.reactions.values) {
      final normalized = emoji.trim();
      if (normalized.isEmpty) {
        continue;
      }
      counts[normalized] = (counts[normalized] ?? 0) + 1;
    }
    return counts;
  }

  void _handleIncomingMessageSound({
    required List<ChatMessage> messages,
    required String currentUserId,
  }) {
    final ids = messages.map((message) => message.id).toSet();
    if (!_seededMessages) {
      _knownMessageIds.addAll(ids);
      _seededMessages = true;
      return;
    }
    final newIds = ids.difference(_knownMessageIds);
    if (newIds.isEmpty) {
      return;
    }
    for (final message in messages) {
      if (!newIds.contains(message.id)) {
        continue;
      }
      if (message.senderId != currentUserId) {
        SystemSound.play(SystemSoundType.alert);
      }
    }
    _knownMessageIds
      ..clear()
      ..addAll(ids);
  }

  void _syncSeenIfNeeded({
    required List<ChatMessage> messages,
    required String currentUserId,
  }) {
    if (_markingSeen) {
      return;
    }
    final hasUnseenIncoming = messages.any(
      (message) =>
          message.receiverId == currentUserId &&
          message.senderId == widget.peerId &&
          message.seenAt == null &&
          !message.isDeletedForEveryone,
    );
    if (!hasUnseenIncoming) {
      return;
    }
    _markingSeen = true;
    unawaited(
      ref
          .read(chatControllerProvider)
          .markSeen(
            jobId: widget.jobId,
            viewerId: currentUserId,
            peerId: widget.peerId,
          )
          .catchError((_) {})
          .whenComplete(() => _markingSeen = false),
    );
    unawaited(
      ref
          .read(chatControllerProvider)
          .markMessageNotificationsRead(
            userId: currentUserId,
            jobId: widget.jobId,
            peerId: widget.peerId,
          ),
    );
  }

  void _markThreadNotificationsReadIfNeeded(String currentUserId) {
    if (_markedNotificationsForThread) {
      return;
    }
    _markedNotificationsForThread = true;
    unawaited(
      ref
          .read(chatControllerProvider)
          .markMessageNotificationsRead(
            userId: currentUserId,
            jobId: widget.jobId,
            peerId: widget.peerId,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final currentUser = ref.watch(currentUserProvider);
    final messagesAsync = ref.watch(chatMessagesProvider(widget.jobId));
    final peerAsync = ref.watch(appUserByIdProvider(widget.peerId));
    final jobAsync = ref.watch(jobByIdProvider(widget.jobId));
    final job = jobAsync.valueOrNull;
    final currentUserId = currentUser?.id;
    final canUseChat = _isChatUnlocked(job: job, currentUserId: currentUserId);
    final peerValue = peerAsync.valueOrNull;
    final canOpenProfile = peerValue?.role == UserRole.pro;
    final peerAvatar = resolveAvatarProvider(peerValue?.profileImageUrl);
    final peerSubtitle = peerValue?.isOnline == true
        ? 'Online'
        : peerValue?.lastSeenAt != null
        ? 'Last seen ${formatDateTime(peerValue!.lastSeenAt!)}'
        : canOpenProfile
        ? 'Tap to view profile'
        : 'Secure realtime chat';

    if (currentUserId != null && canUseChat) {
      _markThreadNotificationsReadIfNeeded(currentUserId);
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 8,
        title: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: canOpenProfile
              ? () => context.push('/pro/${peerValue!.id}', extra: peerValue)
              : null,
          child: Row(
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: peerAvatar,
                    backgroundColor: colors.surfaceContainerHighest,
                    child: peerAvatar == null
                        ? peerAsync.maybeWhen(
                            data: (peer) {
                              final char =
                                  peer?.fullName.trim().isNotEmpty == true
                                  ? peer!.fullName
                                        .trim()
                                        .substring(0, 1)
                                        .toUpperCase()
                                  : '?';
                              return Text(char);
                            },
                            orElse: () => const Text('?'),
                          )
                        : null,
                  ),
                  if (peerValue?.isOnline == true)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors.secondary,
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.surface, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: peerAsync.when(
                  loading: () => const Text('Loading...'),
                  error: (_, _) => const Text('Chat'),
                  data: (peer) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        peer?.fullName ?? 'User',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        peerSubtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: peerValue?.isOnline == true
                              ? colors.secondary
                              : colors.onSurface.withValues(alpha: 0.62),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: _searchVisible ? 'Close search' : 'Search in chat',
            onPressed: () {
              setState(() {
                _searchVisible = !_searchVisible;
                if (!_searchVisible) {
                  _messageSearchQuery = '';
                  _messageSearchController.clear();
                }
              });
            },
            icon: Icon(
              _searchVisible ? Icons.search_off_rounded : Icons.search_rounded,
            ),
          ),
          if (currentUser != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'report') {
                  _showReportDialog(currentUser);
                }
              },
              itemBuilder: (context) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'report',
                  child: Text('Report user'),
                ),
              ],
            ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (jobAsync.isLoading && job == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!canUseChat) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: const BorderRadius.all(Radius.circular(18)),
                    border: Border.all(color: theme.dividerColor),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: colors.shadow.withValues(alpha: 0.1),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 40,
                          color: colors.error,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Chat is locked for this job.',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Messaging unlocks only after a bid is approved and a pro is assigned.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  theme.scaffoldBackgroundColor,
                  theme.scaffoldBackgroundColor,
                ],
              ),
            ),
            child: Column(
              children: <Widget>[
                if (_searchVisible)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: TextField(
                        controller: _messageSearchController,
                        onChanged: (value) =>
                            setState(() => _messageSearchQuery = value),
                        style: theme.textTheme.bodyMedium,
                        decoration: InputDecoration(
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: colors.onSurface.withValues(alpha: 0.62),
                          ),
                          suffixIcon: _messageSearchQuery.trim().isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _messageSearchController.clear();
                                    setState(() => _messageSearchQuery = '');
                                  },
                                  icon: Icon(
                                    Icons.close_rounded,
                                    color: colors.onSurface.withValues(
                                      alpha: 0.62,
                                    ),
                                  ),
                                ),
                          hintText: 'Search messages',
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.6),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.only(top: 13),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: messagesAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Center(
                      child: Text(
                        error.toString(),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    data: (messages) {
                      if (currentUserId != null) {
                        _handleIncomingMessageSound(
                          messages: messages,
                          currentUserId: currentUserId,
                        );
                        _syncSeenIfNeeded(
                          messages: messages,
                          currentUserId: currentUserId,
                        );
                      }

                      final visibleMessages = currentUserId == null
                          ? messages
                          : messages
                                .where(
                                  (message) =>
                                      !message.isDeletedFor(currentUserId),
                                )
                                .toList(growable: false);
                      final normalizedSearch = _messageSearchQuery
                          .trim()
                          .toLowerCase();
                      final searchedMessages = normalizedSearch.isEmpty
                          ? visibleMessages
                          : visibleMessages
                                .where((message) {
                                  final text = _searchableMessageText(message);
                                  return text.toLowerCase().contains(
                                    normalizedSearch,
                                  );
                                })
                                .toList(growable: false);

                      if (visibleMessages.isEmpty) {
                        return Center(
                          child: Text(
                            t.t('no_messages_yet'),
                            style: theme.textTheme.bodyMedium,
                          ),
                        );
                      }
                      if (searchedMessages.isEmpty) {
                        return Center(
                          child: Text(
                            'No messages matched your search.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        );
                      }
                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                        itemCount: searchedMessages.length,
                        itemBuilder: (_, index) {
                          final reverseIndex =
                              searchedMessages.length - 1 - index;
                          final message = searchedMessages[reverseIndex];
                          final mine = message.senderId == currentUserId;
                          final showDateHeader =
                              reverseIndex == 0 ||
                              !_isSameDay(
                                message.sentAt,
                                searchedMessages[reverseIndex - 1].sentAt,
                              );
                          final width = MediaQuery.of(context).size.width;
                          final bubbleMaxWidth = width < 540
                              ? width * 0.82
                              : width < 900
                              ? width * 0.72
                              : 560.0;
                          final sentTop = colors.primary;
                          final sentBottom = Color.alphaBlend(
                            colors.secondary.withValues(alpha: 0.25),
                            colors.primary,
                          );
                          final receivedTop = Color.alphaBlend(
                            colors.primary.withValues(alpha: 0.05),
                            colors.surface,
                          );
                          final receivedBottom = Color.alphaBlend(
                            colors.primary.withValues(alpha: 0.09),
                            colors.surface,
                          );
                          final bubbleGradient = mine
                              ? LinearGradient(
                                  colors: <Color>[sentTop, sentBottom],
                                )
                              : LinearGradient(
                                  colors: <Color>[receivedTop, receivedBottom],
                                );
                          final reactions = _reactionCounts(message);
                          final replyName = message.replyToSenderName?.trim();
                          final voicePayload = message.isDeletedForEveryone
                              ? null
                              : VoiceMessageCodec.tryDecode(message.text);
                          final hasReply =
                              (message.replyToText ?? '').trim().isNotEmpty ||
                              (replyName ?? '').isNotEmpty;

                          return Column(
                            children: <Widget>[
                              if (showDateHeader)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: 10,
                                    top: 2,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colors.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      _formatDay(message.sentAt),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: colors.onSurface.withValues(
                                          alpha: 0.74,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Dismissible(
                                key: ValueKey<String>(
                                  'swipe_reply_${message.id}',
                                ),
                                direction: DismissDirection.startToEnd,
                                confirmDismiss: (_) async {
                                  if (currentUserId != null) {
                                    _setReplyTarget(message);
                                  }
                                  return false;
                                },
                                background: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 14),
                                    child: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: colors.primary,
                                      child: const Icon(
                                        Icons.reply_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                child: Align(
                                  alignment: mine
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: GestureDetector(
                                    onLongPress: currentUserId == null
                                        ? null
                                        : () => _showMessageActions(
                                            message: message,
                                            currentUserId: currentUserId,
                                          ),
                                    child: Column(
                                      crossAxisAlignment: mine
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Container(
                                          constraints: BoxConstraints(
                                            maxWidth: bubbleMaxWidth,
                                          ),
                                          margin: const EdgeInsets.only(
                                            bottom: 4,
                                          ),
                                          padding: const EdgeInsets.fromLTRB(
                                            12,
                                            9,
                                            12,
                                            7,
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: bubbleGradient,
                                            borderRadius: BorderRadius.only(
                                              topLeft: const Radius.circular(
                                                18,
                                              ),
                                              topRight: const Radius.circular(
                                                18,
                                              ),
                                              bottomLeft: Radius.circular(
                                                mine ? 18 : 5,
                                              ),
                                              bottomRight: Radius.circular(
                                                mine ? 5 : 18,
                                              ),
                                            ),
                                            border: Border.all(
                                              color: mine
                                                  ? colors.primary.withValues(
                                                      alpha: 0.75,
                                                    )
                                                  : theme.dividerColor,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: <Widget>[
                                              if (hasReply)
                                                Container(
                                                  width: double.infinity,
                                                  margin: const EdgeInsets.only(
                                                    bottom: 8,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                        8,
                                                        6,
                                                        8,
                                                        6,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: mine
                                                        ? colors.onPrimary
                                                              .withValues(
                                                                alpha: 0.14,
                                                              )
                                                        : colors.primary
                                                              .withValues(
                                                                alpha: 0.08,
                                                              ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    border: Border(
                                                      left: BorderSide(
                                                        color: mine
                                                            ? colors.onPrimary
                                                            : colors.tertiary,
                                                        width: 3,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: <Widget>[
                                                      Text(
                                                        (message.replyToSenderId ==
                                                                currentUserId
                                                            ? 'You'
                                                            : (replyName?.isNotEmpty ==
                                                                      true
                                                                  ? replyName!
                                                                  : 'User')),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: mine
                                                              ? colors.onPrimary
                                                              : colors.tertiary,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        (message.replyToText ??
                                                                '')
                                                            .trim(),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: mine
                                                              ? colors.onPrimary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.88,
                                                                    )
                                                              : colors.onSurface
                                                                    .withValues(
                                                                      alpha:
                                                                          0.7,
                                                                    ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: voicePayload != null
                                                    ? SizedBox(
                                                        width:
                                                            bubbleMaxWidth - 24,
                                                        child:
                                                            VoiceMessageWidget(
                                                              payload:
                                                                  voicePayload,
                                                              isMine: mine,
                                                            ),
                                                      )
                                                    : Text(
                                                        message.isDeletedForEveryone
                                                            ? 'This message was deleted'
                                                            : message.text,
                                                        style: TextStyle(
                                                          fontStyle:
                                                              message
                                                                  .isDeletedForEveryone
                                                              ? FontStyle.italic
                                                              : FontStyle
                                                                    .normal,
                                                          color: mine
                                                              ? colors.onPrimary
                                                              : colors
                                                                    .onSurface,
                                                          height: 1.3,
                                                        ),
                                                      ),
                                              ),
                                              const SizedBox(height: 5),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: <Widget>[
                                                  Text(
                                                    _formatClock(
                                                      message.sentAt,
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: mine
                                                          ? colors.onPrimary
                                                                .withValues(
                                                                  alpha: 0.86,
                                                                )
                                                          : colors.onSurface
                                                                .withValues(
                                                                  alpha: 0.58,
                                                                ),
                                                    ),
                                                  ),
                                                  if (mine) ...<Widget>[
                                                    const SizedBox(width: 4),
                                                    Icon(
                                                      message.seenAt != null
                                                          ? Icons
                                                                .done_all_rounded
                                                          : Icons.done_rounded,
                                                      size: 16,
                                                      color:
                                                          message.seenAt != null
                                                          ? colors.secondary
                                                          : colors.onPrimary
                                                                .withValues(
                                                                  alpha: 0.85,
                                                                ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (reactions.isNotEmpty)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  colors.surfaceContainerHigh,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                color: theme.dividerColor,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: reactions.entries
                                                  .map(
                                                    (entry) => Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            right: 6,
                                                          ),
                                                      child: Text(
                                                        '${entry.key} ${entry.value}',
                                                        style: TextStyle(
                                                          color:
                                                              colors.onSurface,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(growable: false),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                ChatInputPart(
                  controller: _messageController,
                  hintText: t.t('type_message'),
                  sending: _sending,
                  replyingTo: _replyingTo,
                  currentUserId: currentUserId,
                  peerName: peerValue?.fullName ?? 'User',
                  onCancelReply: _cancelReplyTarget,
                  onSendText: _send,
                  onSendVoiceMessage: _sendVoice,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _ReportReasonOption {
  const _ReportReasonOption({required this.code, required this.label});

  final String code;
  final String label;
}

const List<_ReportReasonOption> _reportReasonOptions = <_ReportReasonOption>[
  _ReportReasonOption(code: 'no_show', label: 'No-show after commitment'),
  _ReportReasonOption(code: 'fraud_or_scam', label: 'Fraud or scam behavior'),
  _ReportReasonOption(
    code: 'abusive_language',
    label: 'Abusive language or harassment',
  ),
  _ReportReasonOption(code: 'unsafe_behavior', label: 'Unsafe behavior'),
  _ReportReasonOption(code: 'price_manipulation', label: 'Price manipulation'),
  _ReportReasonOption(code: 'other', label: 'Other'),
];
