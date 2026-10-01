import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pak_service_marketplace/src/app.dart';
import 'package:pak_service_marketplace/src/core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('registration offers distinct customer and professional roles', (
    tester,
  ) async {
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
        child: const MarketplaceApp(initialLocation: '/register'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Professional'), findsOneWidget);
    expect(find.text('Preferred Categories'), findsNothing);

    await tester.tap(find.text('Professional'));
    await tester.pumpAndSettle();

    expect(find.text('Preferred Categories'), findsOneWidget);
  });
}
