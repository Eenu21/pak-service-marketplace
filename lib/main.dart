import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'src/app.dart';
import 'src/core/config/app_config.dart';
import 'src/core/config/repository_provider.dart';
import 'src/core/services/auth_session_cache.dart';
import 'src/domain/models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  await _initializeFirebase();
  final bootstrappedUser = await AuthSessionCache.loadBootstrappedUser();
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final safeBootstrappedUser =
      firebaseUser != null && bootstrappedUser?.id == firebaseUser.uid
      ? bootstrappedUser
      : null;

  runApp(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(config),
        useFirebaseRepositoryProvider.overrideWithValue(true),
        bootstrappedAuthUserProvider.overrideWithValue(safeBootstrappedUser),
      ],
      child: AuthGateApp(bootstrappedUser: safeBootstrappedUser),
    ),
  );
}

class AuthGateApp extends StatelessWidget {
  const AuthGateApp({required this.bootstrappedUser, super.key});

  final AppUser? bootstrappedUser;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final firebaseUser = FirebaseAuth.instance.currentUser;
        final hasMatchingCachedSession =
            firebaseUser != null &&
            bootstrappedUser != null &&
            bootstrappedUser!.id == firebaseUser.uid;
        final shouldShowAuthenticatedApp =
            snapshot.hasData ||
            (snapshot.connectionState == ConnectionState.waiting &&
                hasMatchingCachedSession);
        final initialLocation = shouldShowAuthenticatedApp ? '/home' : '/login';

        return MarketplaceApp(
          key: ValueKey<String>(
            shouldShowAuthenticatedApp ? 'auth_gate_home' : 'auth_gate_login',
          ),
          initialLocation: initialLocation,
        );
      },
    );
  }
}

Future<void> _initializeFirebase() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _configureFirebaseClients();
}

Future<void> _configureFirebaseClients() async {
  try {
    FirebaseFirestore.instance.settings = Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      webExperimentalAutoDetectLongPolling: kIsWeb ? true : null,
    );
  } catch (error) {
    debugPrint('Firestore cache configuration skipped: $error');
  }

  if (!kIsWeb) {
    return;
  }

  try {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  } catch (error) {
    debugPrint('Firebase auth persistence configuration skipped: $error');
  }
}
