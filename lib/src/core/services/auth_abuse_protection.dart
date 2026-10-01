import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AuthAction { login, register }

class AuthAbuseProtection {
  static const int _graceFailures = 4;
  static const Duration _baseLockout = Duration(seconds: 5);
  static const Duration _maxLockout = Duration(minutes: 5);

  final Map<AuthAction, _AuthActionState> _states =
      <AuthAction, _AuthActionState>{};

  void throwIfBlocked(AuthAction action) {
    final now = DateTime.now();
    final state = _states[action];
    if (state == null || state.blockedUntil == null) {
      return;
    }
    final blockedUntil = state.blockedUntil!;
    if (now.isAfter(blockedUntil)) {
      state.blockedUntil = null;
      return;
    }
    final retryAfter = blockedUntil.difference(now).inSeconds;
    final actionName = action == AuthAction.login ? 'Login' : 'Registration';
    throw StateError(
      '$actionName is temporarily locked. Try again in $retryAfter seconds.',
    );
  }

  void recordSuccess(AuthAction action) {
    _states.remove(action);
  }

  void recordFailure(AuthAction action) {
    final now = DateTime.now();
    final state = _states.putIfAbsent(action, () => _AuthActionState());
    state.failures += 1;

    if (state.failures <= _graceFailures) {
      state.blockedUntil = null;
      return;
    }

    final exponent = state.failures - _graceFailures;
    final backoffSeconds =
        _baseLockout.inSeconds * math.pow(2, exponent).toInt();
    final clampedSeconds = math.min(backoffSeconds, _maxLockout.inSeconds);
    state.blockedUntil = now.add(Duration(seconds: clampedSeconds));
  }
}

class _AuthActionState {
  int failures = 0;
  DateTime? blockedUntil;
}

final authAbuseProtectionProvider = Provider<AuthAbuseProtection>((_) {
  return AuthAbuseProtection();
});
