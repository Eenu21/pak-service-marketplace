import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

@immutable
class VoiceMessagePayload {
  const VoiceMessagePayload({
    required this.id,
    required this.durationMs,
    required this.createdAtIso,
  });

  final String id;
  final int durationMs;
  final String createdAtIso;

  Duration get duration => Duration(milliseconds: durationMs.clamp(0, 3600000));

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'duration_ms': durationMs,
    'created_at': createdAtIso,
  };

  factory VoiceMessagePayload.fromJson(Map<String, dynamic> json) {
    return VoiceMessagePayload(
      id: (json['id'] ?? '').toString(),
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      createdAtIso: (json['created_at'] ?? '').toString(),
    );
  }
}

class VoiceMessageCodec {
  static const String _prefix = '__voice_v1__:';

  static String encode(VoiceMessagePayload payload) {
    return '$_prefix${jsonEncode(payload.toJson())}';
  }

  static VoiceMessagePayload? tryDecode(String rawText) {
    final value = rawText.trim();
    if (!value.startsWith(_prefix)) {
      return null;
    }
    final serialized = value.substring(_prefix.length);
    try {
      final decoded = jsonDecode(serialized);
      if (decoded is! Map) {
        return null;
      }
      final payload = VoiceMessagePayload.fromJson(
        Map<String, dynamic>.from(decoded as Map<Object?, Object?>),
      );
      if (payload.id.trim().isEmpty) {
        return null;
      }
      return payload;
    } catch (_) {
      return null;
    }
  }
}

class VoiceMessageSecureStore {
  VoiceMessageSecureStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const String _keyPrefix = 'voice_msg_path_v1_';

  String _keyFor(String messageId) => '$_keyPrefix$messageId';

  Future<void> savePath({
    required String messageId,
    required String localPath,
  }) async {
    await _storage.write(key: _keyFor(messageId), value: localPath);
  }

  Future<String?> readPath(String messageId) async {
    return _storage.read(key: _keyFor(messageId));
  }
}

String formatVoiceDuration(Duration duration) {
  final clamped = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final minutes = (clamped ~/ 60).toString();
  final seconds = (clamped % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class VoiceMessageWidget extends StatefulWidget {
  const VoiceMessageWidget({
    super.key,
    required this.payload,
    required this.isMine,
    this.secureStore,
  });

  final VoiceMessagePayload payload;
  final bool isMine;
  final VoiceMessageSecureStore? secureStore;

  @override
  State<VoiceMessageWidget> createState() => _VoiceMessageWidgetState();
}

class _VoiceMessageWidgetState extends State<VoiceMessageWidget> {
  late final AudioPlayer _audioPlayer;
  late final VoiceMessageSecureStore _secureStore;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;

  Duration _position = Duration.zero;
  Duration _detectedDuration = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;
  bool _resolvingPath = true;
  String? _localPath;

  Duration get _effectiveDuration => _detectedDuration > Duration.zero
      ? _detectedDuration
      : widget.payload.duration;

  bool get _canPlay => _localPath != null && _localPath!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _secureStore = widget.secureStore ?? VoiceMessageSecureStore();
    _bindStreams();
    unawaited(_resolveAudioPath());
  }

  void _bindStreams() {
    _positionSub = _audioPlayer.onPositionChanged.listen((position) {
      if (!mounted) {
        return;
      }
      setState(() => _position = position);
    });
    _durationSub = _audioPlayer.onDurationChanged.listen((duration) {
      if (!mounted) {
        return;
      }
      setState(() => _detectedDuration = duration);
    });
    _stateSub = _audioPlayer.onPlayerStateChanged.listen((playerState) {
      if (!mounted) {
        return;
      }
      setState(() {
        _playerState = playerState;
        if (playerState == PlayerState.completed) {
          _position = Duration.zero;
        }
      });
    });
  }

  Future<void> _resolveAudioPath() async {
    setState(() => _resolvingPath = true);
    try {
      final path = await _secureStore.readPath(widget.payload.id);
      if (path == null || path.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _localPath = null;
            _resolvingPath = false;
          });
        }
        return;
      }
      final file = File(path);
      final exists = await file.exists();
      if (!mounted) {
        return;
      }
      setState(() {
        _localPath = exists ? path : null;
        _resolvingPath = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _localPath = null;
        _resolvingPath = false;
      });
    }
  }

  Future<void> _togglePlayPause() async {
    if (!_canPlay) {
      return;
    }
    final sourcePath = _localPath!;
    if (_playerState == PlayerState.playing) {
      await _audioPlayer.pause();
      return;
    }
    if (_position >= _effectiveDuration && _effectiveDuration > Duration.zero) {
      await _audioPlayer.seek(Duration.zero);
    }
    await _audioPlayer.play(DeviceFileSource(sourcePath));
  }

  Future<void> _seekTo(double millis) async {
    final duration = Duration(milliseconds: millis.round());
    await _audioPlayer.seek(duration);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final iconColor = widget.isMine ? colors.onPrimary : colors.primary;
    final textColor = widget.isMine
        ? colors.onPrimary.withValues(alpha: 0.96)
        : colors.onSurface;
    final mutedTextColor = widget.isMine
        ? colors.onPrimary.withValues(alpha: 0.72)
        : colors.onSurface.withValues(alpha: 0.62);

    final maxMs = _effectiveDuration.inMilliseconds <= 0
        ? 1.0
        : _effectiveDuration.inMilliseconds.toDouble();
    final sliderValue = _position.inMilliseconds
        .toDouble()
        .clamp(0.0, maxMs)
        .toDouble();
    final isPlaying = _playerState == PlayerState.playing;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          color: widget.isMine
              ? colors.onPrimary.withValues(alpha: 0.14)
              : colors.primary.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          child: IconButton(
            onPressed: _resolvingPath ? null : _togglePlayPause,
            icon: _resolvingPath
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: iconColor,
                    ),
                  )
                : Icon(
                    !_canPlay
                        ? Icons.lock_outline_rounded
                        : (isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                    color: iconColor,
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                  activeTrackColor: widget.isMine
                      ? colors.onPrimary
                      : colors.primary,
                  inactiveTrackColor: widget.isMine
                      ? colors.onPrimary.withValues(alpha: 0.32)
                      : colors.primary.withValues(alpha: 0.25),
                  thumbColor: widget.isMine ? colors.onPrimary : colors.primary,
                ),
                child: Slider(
                  min: 0,
                  max: maxMs,
                  value: sliderValue,
                  onChanged: !_canPlay
                      ? null
                      : (value) {
                          setState(() {
                            _position = Duration(milliseconds: value.round());
                          });
                        },
                  onChangeEnd: !_canPlay ? null : _seekTo,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: <Widget>[
                  Text(
                    _canPlay
                        ? '${formatVoiceDuration(_position)} / ${formatVoiceDuration(_effectiveDuration)}'
                        : 'Voice unavailable',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _canPlay ? mutedTextColor : colors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!_canPlay) ...<Widget>[
                    const SizedBox(width: 6),
                    Text(
                      '(${formatVoiceDuration(widget.payload.duration)})',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
