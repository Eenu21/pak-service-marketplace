import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pak_service_marketplace/src/app.dart';
import 'package:pak_service_marketplace/src/core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('App boots with local config', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(
            const AppConfig(
              firebaseApiKey: '',
              firebaseAuthDomain: '',
              firebaseProjectId: '',
              firebaseStorageBucket: '',
              firebaseMessagingSenderId: '',
              firebaseAppId: '',
              firebaseMeasurementId: '',
              googleMapsApiKey: '',
              termsVersion: 'v1.0',
              privacyVersion: 'v1.0',
              initialCommissionRate: 0.075,
              bootstrapAdminEmails: <String>[],
            ),
          ),
        ],
        child: const MarketplaceApp(initialLocation: '/login'),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Pak Service Marketplace'), findsOneWidget);
  });

  testWidgets('Urdu locale selects RTL layout and readable translations', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'locale_code': 'ur',
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(
            const AppConfig(
              firebaseApiKey: '',
              firebaseAuthDomain: '',
              firebaseProjectId: '',
              firebaseStorageBucket: '',
              firebaseMessagingSenderId: '',
              firebaseAppId: '',
              firebaseMeasurementId: '',
              googleMapsApiKey: '',
              termsVersion: 'v1.0',
              privacyVersion: 'v1.0',
              initialCommissionRate: 0.075,
              bootstrapAdminEmails: <String>[],
            ),
          ),
        ],
        child: const MarketplaceApp(initialLocation: '/login'),
      ),
    );

    await tester.pumpAndSettle();
    final appName = find.text('پاک سروس مارکیٹ پلیس');
    expect(appName, findsOneWidget);
    expect(Directionality.of(tester.element(appName)), TextDirection.rtl);
  });
}
