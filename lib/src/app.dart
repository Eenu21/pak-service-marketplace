import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/repository_provider.dart';
import 'core/localization/app_localizations.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'presentation/controllers/app_settings_controller.dart';
import 'presentation/controllers/notification_runtime_controller.dart';
import 'presentation/controllers/work_timer_notification_controller.dart';

class MarketplaceApp extends ConsumerWidget {
  const MarketplaceApp({required this.initialLocation, super.key});

  final String initialLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider(initialLocation));
    final settings = ref.watch(appSettingsControllerProvider);
    final useFirebase = ref.watch(useFirebaseRepositoryProvider);
    ref.watch(notificationRuntimeProvider);
    ref.watch(workTimerNotificationProvider);

    return MaterialApp.router(
      title: 'Pak Service Marketplace',
      theme: AppTheme.light(locale: settings.locale),
      debugShowCheckedModeBanner: false,
      locale: settings.locale,
      builder: (context, child) {
        if (child == null) {
          return const SizedBox.shrink();
        }
        // Keep Urdu translation/font, but preserve the app's LTR layout.
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              child,
              if (!useFirebase)
                const Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: SafeArea(child: _RepositoryModeBanner()),
                ),
            ],
          ),
        );
      },
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}

class _RepositoryModeBanner extends StatelessWidget {
  const _RepositoryModeBanner();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFFDF3D6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE7C871)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                Icon(Icons.cloud_off_outlined, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Local mode only. Data is saved on this device, not in Firebase cloud yet.',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
