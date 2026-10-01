import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models.dart';
import 'voice_message_widget.dart';

class ChatInputPart extends StatefulWidget {
  const ChatInputPart({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onSendText,
    required this.onSendVoiceMessage,
    this.sending = false,
    this.replyingTo,
    this.currentUserId,
    this.peerName = 'User',
    this.onCancelReply,
  });

  final TextEditingController controller;
  final String hintText;
  final Future<void> Function() onSendText;
  final Future<void> Function(String encodedVoicePayload) onSendVoiceMessage;
  final bool sending;
  final ChatMessage? replyingTo;
  final String? currentUserId;
  final String peerName;
  final VoidCallback? onCancelReply;

  @override
  State<ChatInputPart> createState() => _ChatInputPartState();
}

class _ChatInputPartState extends State<ChatInputPart> {
  static const double _cancelSlideThreshold = 110;
  static const Duration _minVoiceDuration = Duration(milliseconds: 600);

  final AudioRecorder _recorder = AudioRecorder();
  final VoiceMessageSecureStore _secureStore = VoiceMessageSecureStore();
  final Uuid _uuid = const Uuid();

  Timer? _recordTicker;
  Timer? _pulseTicker;
  Duration _recorded = Duration.zero;
  bool _recording = false;
  bool _sendInFlight = false;
  bool _willCancel = false;
  bool _showPulse = true;
  double _dragLeft = 0;

  bool get _busy => widget.sending || _sendInFlight;

  @override
  void dispose() {
    _recordTicker?.cancel();
    _pulseTicker?.cancel();
    _recorder.dispose();
    super.dispose();
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

  Future<void> _startVoiceCapture() async {
    if (_busy || _recording) {
      return;
    }
    final allowed = await _recorder.hasPermission();
    if (!allowed) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is required.')),
      );
      return;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final filePath =
          '${tempDir.path}${Platform.pathSeparator}voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );
      _recordTicker?.cancel();
      _pulseTicker?.cancel();
      _recordTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          return;
        }
        setState(() => _recorded += const Duration(seconds: 1));
      });
      _pulseTicker = Timer.periodic(const Duration(milliseconds: 420), (_) {
        if (!mounted) {
          return;
        }
        setState(() => _showPulse = !_showPulse);
      });
      HapticFeedback.mediumImpact();
      if (!mounted) {
        return;
      }
      setState(() {
        _recording = true;
        _recorded = Duration.zero;
        _willCancel = false;
        _dragLeft = 0;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start recording: $error')),
      );
    }
  }

  void _updateSlideCancelGesture(LongPressMoveUpdateDetails details) {
    if (!_recording) {
      return;
    }
    final drag = details.offsetFromOrigin.dx;
    final toLeft = drag < 0 ? drag.abs() : 0.0;
    final shouldCancel = toLeft >= _cancelSlideThreshold;
    if (!mounted) {
      return;
    }
    setState(() {
      _dragLeft = toLeft;
      _willCancel = shouldCancel;
    });
  }

  Future<void> _finishVoiceCapture({bool forceCancel = false}) async {
    if (!_recording) {
      return;
    }
    _recordTicker?.cancel();
    _recordTicker = null;
    _pulseTicker?.cancel();
    _pulseTicker = null;

    final shouldCancel = forceCancel || _willCancel;
    String? recordedPath;
    try {
      recordedPath = await _recorder.stop();
    } catch (_) {
      recordedPath = null;
    }

    if (shouldCancel || _recorded < _minVoiceDuration || recordedPath == null) {
      if (recordedPath != null) {
        final file = File(recordedPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      if (mounted) {
        setState(() {
          _recording = false;
          _recorded = Duration.zero;
          _willCancel = false;
          _dragLeft = 0;
          _showPulse = true;
        });
      }
      return;
    }

    final messageId = _uuid.v4();
    await _secureStore.savePath(messageId: messageId, localPath: recordedPath);
    final payload = VoiceMessagePayload(
      id: messageId,
      durationMs: _recorded.inMilliseconds,
      createdAtIso: DateTime.now().toIso8601String(),
    );
    final encoded = VoiceMessageCodec.encode(payload);
    if (!mounted) {
      return;
    }
    setState(() {
      _sendInFlight = true;
      _recording = false;
      _recorded = Duration.zero;
      _willCancel = false;
      _dragLeft = 0;
      _showPulse = true;
    });
    try {
      await widget.onSendVoiceMessage(encoded);
      HapticFeedback.lightImpact();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Voice message failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _sendInFlight = false);
      }
    }
  }

  Future<void> _sendTextIfPossible() async {
    if (_busy) {
      return;
    }
    if (widget.controller.text.trim().isEmpty) {
      return;
    }
    await widget.onSendText();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasDraft = widget.controller.text.trim().isNotEmpty;
    final replyingTo = widget.replyingTo;
    final slideProgress = (_dragLeft / _cancelSlideThreshold).clamp(0.0, 1.0);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.dividerColor),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (replyingTo != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(2, 2, 2, 8),
                        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border(
                            left: BorderSide(
                              color: replyingTo.senderId == widget.currentUserId
                                  ? colors.secondary
                                  : colors.tertiary,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    replyingTo.senderId == widget.currentUserId
                                        ? 'You'
                                        : widget.peerName,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color:
                                              replyingTo.senderId ==
                                                  widget.currentUserId
                                              ? colors.secondary
                                              : colors.tertiary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _replyPreviewText(replyingTo),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurface.withValues(
                                        alpha: 0.72,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: widget.onCancelReply,
                              icon: Icon(
                                Icons.close_rounded,
                                color: colors.onSurface.withValues(alpha: 0.7),
                              ),
                              tooltip: 'Cancel reply',
                            ),
                          ],
                        ),
                      ),
                    if (_recording)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(2, 2, 2, 8),
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        decoration: BoxDecoration(
                          color: colors.errorContainer.withValues(alpha: 0.42),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colors.error.withValues(alpha: 0.24),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _showPulse
                                        ? colors.error
                                        : colors.error.withValues(alpha: 0.35),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Recording ${formatVoiceDuration(_recorded)}',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: colors.onErrorContainer,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _willCancel
                                      ? 'Release to cancel'
                                      : 'Slide left to cancel',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: _willCancel
                                        ? colors.error
                                        : colors.onErrorContainer.withValues(
                                            alpha: 0.78,
                                          ),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              minHeight: 3,
                              value: slideProgress,
                              color: _willCancel
                                  ? colors.error
                                  : colors.primary,
                              backgroundColor: colors.onErrorContainer
                                  .withValues(alpha: 0.2),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        IconButton(
                          onPressed: _busy ? null : () {},
                          icon: Icon(
                            Icons.add_rounded,
                            color: colors.onSurface.withValues(alpha: 0.74),
                          ),
                        ),
                        IconButton(
                          onPressed: _busy ? null : () {},
                          icon: Icon(
                            Icons.emoji_emotions_outlined,
                            color: colors.onSurface.withValues(alpha: 0.74),
                          ),
                        ),
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 132),
                            child: TextField(
                              controller: widget.controller,
                              textInputAction: TextInputAction.send,
                              minLines: 1,
                              maxLines: 5,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurface,
                              ),
                              onSubmitted: (_) => _sendTextIfPossible(),
                              decoration: InputDecoration(
                                hintText: widget.hintText,
                                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (hasDraft)
                          IconButton.filled(
                            onPressed: _busy ? null : _sendTextIfPossible,
                            style: IconButton.styleFrom(
                              backgroundColor: colors.secondary,
                              foregroundColor: colors.onSecondary,
                            ),
                            icon: _busy
                                ? SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colors.onSecondary,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
                          )
                        else
                          GestureDetector(
                            onLongPressStart: (_) => _startVoiceCapture(),
                            onLongPressMoveUpdate: _updateSlideCancelGesture,
                            onLongPressEnd: (_) => _finishVoiceCapture(),
                            onLongPressCancel: () =>
                                _finishVoiceCapture(forceCancel: true),
                            child: IconButton.filled(
                              onPressed: _busy ? null : () {},
                              style: IconButton.styleFrom(
                                backgroundColor: _recording
                                    ? (_willCancel
                                          ? colors.error
                                          : colors.primary)
                                    : colors.primary,
                                foregroundColor: colors.onPrimary,
                              ),
                              icon: Icon(
                                _recording
                                    ? (_willCancel
                                          ? Icons.cancel_rounded
                                          : Icons.mic_rounded)
                                    : Icons.mic_none_rounded,
                              ),
                              tooltip: 'Hold to record',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
