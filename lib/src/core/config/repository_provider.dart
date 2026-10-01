import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_session_cache.dart';
import '../../data/repositories/firebase_marketplace_repository.dart';
import '../../data/repositories/local_marketplace_repository.dart';
import '../../data/repositories/marketplace_repository.dart';
import 'app_config.dart';

final useFirebaseRepositoryProvider = Provider<bool>((_) => false);
final localRepositoryStateProvider = Provider<String?>((_) => null);

final marketplaceRepositoryProvider = Provider<MarketplaceRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  final useFirebase = ref.watch(useFirebaseRepositoryProvider);
  final localStateJson = ref.watch(localRepositoryStateProvider);
  final authSessionCache = ref.read(authSessionCacheProvider);

  final repository = useFirebase
      ? FirebaseMarketplaceRepository(
          firestore: FirebaseFirestore.instance,
          auth: FirebaseAuth.instance,
          authSessionCache: authSessionCache,
          initialCommissionRate: config.initialCommissionRate,
          bootstrapAdminEmails: config.bootstrapAdminEmails,
        )
      : LocalMarketplaceRepository(
          initialCommissionRate: config.initialCommissionRate,
          persistedStateJson: localStateJson,
        );

  ref.onDispose(repository.dispose);
  return repository;
});
