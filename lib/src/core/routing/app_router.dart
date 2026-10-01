import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/screens/admin_dashboard_screen.dart';
import '../../presentation/screens/auth_screens.dart';
import '../../presentation/screens/chat_screen.dart';
import '../../presentation/screens/create_job_screen.dart';
import '../../presentation/screens/home_shell_screen.dart';
import '../../presentation/screens/inbox_screen.dart';
import '../../presentation/screens/job_detail_screen.dart';
import '../../presentation/screens/job_history_screen.dart';
import '../../presentation/screens/notifications_screen.dart';
import '../../presentation/screens/pro_earnings_screen.dart';
import '../../presentation/screens/pro_profile_screen.dart';
import '../../presentation/screens/profile_screen.dart';
import '../../presentation/screens/settings_screen.dart';
import '../../domain/models.dart';

final appRouterProvider = Provider.family<GoRouter, String>((ref, initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (context, state) => const LaunchScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(path: '/terms', builder: (context, state) => const TermsScreen()),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeShellScreen(),
      ),
      GoRoute(
        path: '/post-job',
        builder: (context, state) => const CreateJobScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const JobHistoryScreen(),
      ),
      GoRoute(path: '/inbox', builder: (context, state) => const InboxScreen()),
      GoRoute(
        path: '/earnings',
        builder: (context, state) => const ProEarningsScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/job/:jobId',
        builder: (context, state) => JobDetailScreen(
          jobId: state.pathParameters['jobId']!,
          initialJob: state.extra is Job ? state.extra as Job : null,
        ),
      ),
      GoRoute(
        path: '/chat/:jobId/:peerId',
        builder: (context, state) => ChatScreen(
          jobId: state.pathParameters['jobId']!,
          peerId: state.pathParameters['peerId']!,
        ),
      ),
      GoRoute(
        path: '/pro/:proId',
        builder: (context, state) => ProProfileScreen(
          proId: state.pathParameters['proId']!,
          initialPro: state.extra is AppUser ? state.extra as AppUser : null,
        ),
      ),
    ],
  );
});
