import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/repository_provider.dart';
import '../../core/services/auth_abuse_protection.dart';
import '../../core/services/auth_session_cache.dart';
import '../../data/repositories/marketplace_repository.dart';
import '../../domain/models.dart';

class AuthController extends StateNotifier<AsyncValue<AppUser?>> {
  AuthController(Ref ref)
    : _repository = ref.read(marketplaceRepositoryProvider),
      _authAbuseProtection = ref.read(authAbuseProtectionProvider),
      _bootstrappedUser = ref.read(bootstrappedAuthUserProvider),
      super(AsyncValue<AppUser?>.data(ref.read(bootstrappedAuthUserProvider))) {
    _initialize();
  }

  final MarketplaceRepository _repository;
  final AuthAbuseProtection _authAbuseProtection;
  final AppUser? _bootstrappedUser;
  StreamSubscription<AppUser?>? _subscription;

  Future<void> _initialize() async {
    _subscription?.cancel();
    _subscription = _repository.watchCurrentUser().listen(
      (user) => state = AsyncValue.data(user),
      onError: (Object error, StackTrace stackTrace) {
        state = AsyncValue.error(error, stackTrace);
      },
    );

    try {
      final currentUser = await _repository.getCurrentUser();
      state = AsyncValue.data(currentUser);
    } catch (error, stackTrace) {
      // Do not restore stale bootstrapped users on read failures.
      // The live auth stream above is the source of truth for session state.
      if (state.valueOrNull == null && _bootstrappedUser == null) {
        state = AsyncValue.error(error, stackTrace);
      }
    }
  }

  Future<AppUser> register(RegisterInput input) async {
    state = const AsyncValue.loading();
    try {
      _authAbuseProtection.throwIfBlocked(AuthAction.register);
      final user = await _repository.register(input);
      _authAbuseProtection.recordSuccess(AuthAction.register);
      state = AsyncValue.data(user);
      return user;
    } catch (error, stackTrace) {
      if (_shouldCountAuthFailure(error)) {
        _authAbuseProtection.recordFailure(AuthAction.register);
      }
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }

  Future<AppUser> login(LoginInput input) async {
    state = const AsyncValue.loading();
    try {
      _authAbuseProtection.throwIfBlocked(AuthAction.login);
      final user = await _repository.signIn(input);
      _authAbuseProtection.recordSuccess(AuthAction.login);
      state = AsyncValue.data(user);
      return user;
    } catch (error, stackTrace) {
      if (_shouldCountAuthFailure(error)) {
        _authAbuseProtection.recordFailure(AuthAction.login);
      }
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }

  Future<void> logout() async {
    await _repository.signOut();
    state = const AsyncValue.data(null);
  }

  Future<void> updateProfile(AppUser user) async {
    final current =
        await _repository.getCurrentUser() ??
        state.maybeWhen(data: (value) => value, orElse: () => null);
    if (current == null) {
      throw StateError('Not authenticated.');
    }
    final normalized = current.copyWith(
      fullName: user.fullName,
      phone: user.phone,
      profileImageUrl: user.profileImageUrl,
      languageCode: user.languageCode,
      notificationsEnabled: user.notificationsEnabled,
      preciseLocationEnabled: user.preciseLocationEnabled,
      paymentAccount: user.paymentAccount,
      preferredCategories: user.preferredCategories,
      savedLocations: user.savedLocations,
    );
    await _repository.updateProfile(normalized);
    state = AsyncValue.data(normalized);
  }

  Future<AppUser> upgradeToProfessional({
    required List<JobCategory> preferredCategories,
  }) async {
    final upgraded = await _repository.upgradeToProfessional(
      preferredCategories: preferredCategories,
    );
    state = AsyncValue.data(upgraded);
    return upgraded;
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  bool _shouldCountAuthFailure(Object error) {
    final text = error.toString().toLowerCase();
    return !(text.contains('network') ||
        text.contains('internet') ||
        text.contains('timeout') ||
        text.contains('unavailable'));
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<AppUser?>>((ref) {
      return AuthController(ref);
    });

final currentUserProvider = Provider<AppUser?>((ref) {
  return ref
      .watch(authControllerProvider)
      .maybeWhen(data: (user) => user, orElse: () => null);
});
