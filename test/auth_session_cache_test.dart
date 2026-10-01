import 'package:flutter_test/flutter_test.dart';
import 'package:pak_service_marketplace/src/core/services/auth_session_cache.dart';
import 'package:pak_service_marketplace/src/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'persists the selected professional role and profile across restart',
    () async {
      final cache = AuthSessionCache();
      final user = AppUser(
        id: 'professional-1',
        role: UserRole.pro,
        fullName: 'Ayesha Khan',
        email: 'ayesha@example.com',
        phone: '+923001234567',
        preferredCategories: const <JobCategory>[JobCategory.plumbing],
      );

      await cache.save(user);

      final restored = await AuthSessionCache().load();
      expect(restored?.id, user.id);
      expect(restored?.role, UserRole.pro);
      expect(restored?.fullName, user.fullName);
      expect(restored?.preferredCategories, user.preferredCategories);
    },
  );

  test(
    'persists the selected customer role and profile across restart',
    () async {
      final cache = AuthSessionCache();
      final user = AppUser(
        id: 'customer-1',
        role: UserRole.customer,
        fullName: 'Omar Ali',
        email: 'omar@example.com',
        phone: '+923001234567',
      );

      await cache.save(user);

      final restored = await AuthSessionCache().load();
      expect(restored?.id, user.id);
      expect(restored?.role, UserRole.customer);
      expect(restored?.fullName, user.fullName);
    },
  );
}
