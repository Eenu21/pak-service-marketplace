import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsState {
  const AppSettingsState({
    required this.locale,
    required this.pushNotifications,
    required this.privacyMode,
  });

  final Locale locale;
  final bool pushNotifications;
  final bool privacyMode;

  AppSettingsState copyWith({Locale? locale, bool? pushNotifications, bool? privacyMode}) {
    return AppSettingsState(
      locale: locale ?? this.locale,
      pushNotifications: pushNotifications ?? this.pushNotifications,
      privacyMode: privacyMode ?? this.privacyMode,
    );
  }
}

class AppSettingsController extends StateNotifier<AppSettingsState> {
  AppSettingsController()
      : super(
          const AppSettingsState(
            locale: Locale('en'),
            pushNotifications: true,
            privacyMode: true,
          ),
        ) {
    _load();
  }

  static const _localeKey = 'locale_code';
  static const _pushKey = 'push_notifications';
  static const _privacyKey = 'privacy_mode';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final localeCode = prefs.getString(_localeKey) ?? 'en';
    final push = prefs.getBool(_pushKey) ?? true;
    final privacy = prefs.getBool(_privacyKey) ?? true;
    state = state.copyWith(
      locale: Locale(localeCode),
      pushNotifications: push,
      privacyMode: privacy,
    );
  }

  Future<void> setLocale(String code) async {
    state = state.copyWith(locale: Locale(code));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, code);
  }

  Future<void> setPushNotifications(bool value) async {
    state = state.copyWith(pushNotifications: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pushKey, value);
  }

  Future<void> setPrivacyMode(bool value) async {
    state = state.copyWith(privacyMode: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_privacyKey, value);
  }
}

final appSettingsControllerProvider = StateNotifierProvider<AppSettingsController, AppSettingsState>((_) {
  return AppSettingsController();
});
