import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models.dart';

class AuthSessionCache {
  static const String storageKey = 'auth_session_cache_v2';
  static const String legacyStorageKey = 'auth_session_cache_v1';
  static const Duration _maxCacheAge = Duration(hours: 12);

  static Future<AppUser?> loadBootstrappedUser() async {
    return AuthSessionCache().load();
  }

  Future<AppUser?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getString(storageKey) ?? prefs.getString(legacyStorageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await clear();
        return null;
      }

      final payload = Map<String, dynamic>.from(
        decoded as Map<Object?, Object?>,
      );
      final userJsonRaw = payload['user'];
      final cachedAtRaw = payload['cached_at'];

      final userJson = userJsonRaw is Map
          ? Map<String, dynamic>.from(userJsonRaw as Map<Object?, Object?>)
          : payload;
      final cachedAt = cachedAtRaw is String
          ? DateTime.tryParse(cachedAtRaw)
          : null;

      if (cachedAt != null &&
          DateTime.now().difference(cachedAt) > _maxCacheAge) {
        await clear();
        return null;
      }

      final user = AppUser.fromJson(userJson);
      if (user.role == UserRole.admin) {
        await clear();
        return null;
      }
      return user;
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> save(AppUser user) async {
    if (user.role == UserRole.admin) {
      await clear();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode(<String, dynamic>{
        'cached_at': DateTime.now().toIso8601String(),
        'user': user.toJson(),
      }),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
    await prefs.remove(legacyStorageKey);
  }
}

final authSessionCacheProvider = Provider<AuthSessionCache>((_) {
  return AuthSessionCache();
});

final bootstrappedAuthUserProvider = Provider<AppUser?>((_) => null);
