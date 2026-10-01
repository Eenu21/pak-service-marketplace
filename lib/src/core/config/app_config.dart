import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppConfig {
  const AppConfig({
    required this.firebaseApiKey,
    required this.firebaseAuthDomain,
    required this.firebaseProjectId,
    required this.firebaseStorageBucket,
    required this.firebaseMessagingSenderId,
    required this.firebaseAppId,
    required this.firebaseMeasurementId,
    required this.googleMapsApiKey,
    required this.termsVersion,
    required this.privacyVersion,
    required this.initialCommissionRate,
    required this.bootstrapAdminEmails,
  });

  final String firebaseApiKey;
  final String firebaseAuthDomain;
  final String firebaseProjectId;
  final String firebaseStorageBucket;
  final String firebaseMessagingSenderId;
  final String firebaseAppId;
  final String firebaseMeasurementId;
  final String googleMapsApiKey;
  final String termsVersion;
  final String privacyVersion;
  final double initialCommissionRate;
  final List<String> bootstrapAdminEmails;

  bool get hasFirebaseWebConfig =>
      firebaseApiKey.isNotEmpty &&
      firebaseProjectId.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty &&
      firebaseAppId.isNotEmpty;

  factory AppConfig.fromEnvironment() {
    return AppConfig(
      firebaseApiKey: const String.fromEnvironment(
        'FIREBASE_API_KEY',
        defaultValue: 'AIzaSyBkwchDsoHm8FG-ybKGHxg2wl0-gt8uZwI',
      ),
      firebaseAuthDomain: const String.fromEnvironment(
        'FIREBASE_AUTH_DOMAIN',
        defaultValue: 'servicemenphoneapp.firebaseapp.com',
      ),
      firebaseProjectId: const String.fromEnvironment(
        'FIREBASE_PROJECT_ID',
        defaultValue: 'servicemenphoneapp',
      ),
      firebaseStorageBucket: const String.fromEnvironment(
        'FIREBASE_STORAGE_BUCKET',
        defaultValue: 'servicemenphoneapp.firebasestorage.app',
      ),
      firebaseMessagingSenderId: const String.fromEnvironment(
        'FIREBASE_MESSAGING_SENDER_ID',
        defaultValue: '863539075914',
      ),
      firebaseAppId: const String.fromEnvironment(
        'FIREBASE_APP_ID',
        defaultValue: '1:863539075914:web:e3c91ca536d5c37f68ffb3',
      ),
      firebaseMeasurementId: const String.fromEnvironment(
        'FIREBASE_MEASUREMENT_ID',
        defaultValue: 'G-NB2G7FDRKR',
      ),
      googleMapsApiKey: const String.fromEnvironment(
        'GOOGLE_MAPS_API_KEY',
        defaultValue: '',
      ),
      termsVersion: const String.fromEnvironment(
        'TERMS_VERSION',
        defaultValue: 'v1.0',
      ),
      privacyVersion: const String.fromEnvironment(
        'PRIVACY_VERSION',
        defaultValue: 'v1.0',
      ),
      initialCommissionRate:
          double.tryParse(
            const String.fromEnvironment(
              'PLATFORM_FEE_RATE',
              defaultValue: '0.075',
            ),
          ) ??
          0.075,
      bootstrapAdminEmails: _parseBootstrapAdminEmails(
        const String.fromEnvironment(
          'BOOTSTRAP_ADMIN_EMAILS',
          defaultValue: '',
        ),
      ),
    );
  }
}

List<String> _parseBootstrapAdminEmails(String raw) {
  return raw
      .split(',')
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

final appConfigProvider = Provider<AppConfig>(
  (_) => throw UnimplementedError('AppConfig override missing.'),
);
