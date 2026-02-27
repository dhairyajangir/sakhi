import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/platform_helper.dart';
import '../screens/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/otp_screen.dart';
import '../screens/auth/email_login_screen.dart';
import '../screens/auth/profile_setup_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/session/active_session_screen.dart';
import '../screens/session/volunteer_dashboard_screen.dart';
import '../screens/broadcast/broadcast_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/contacts/emergency_contacts_screen.dart';
import '../screens/location/location_sharing_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/safety_tools/fake_call_screen.dart';
import '../screens/safety_tools/virtual_companion_setup.dart';
import '../screens/safety_tools/active_companion_screen.dart';
import '../screens/safety_tools/pin_setup_screen.dart';
import '../screens/safety_tools/camouflage_screen.dart';
import '../screens/safety_tools/walking_buddy_setup.dart';
import '../screens/safety_tools/walking_buddy_active_view.dart';
import '../screens/safety_tools/walk_with_me_setup_screen.dart';
import '../screens/safety_tools/walk_with_me_active_screen.dart';
import '../screens/profile/volunteer_verification_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  debugLogDiagnostics: true,
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(
      path: '/login',
      builder: (context, state) {
        // On Web/Desktop, skip the phone login and show email login directly.
        if (isWebOrDesktop) return const EmailLoginScreen();
        return const LoginScreen();
      },
    ),
    GoRoute(
      path: '/otp',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return OtpScreen(
          verificationId: extra['verificationId'] as String? ?? '',
          phoneNumber: extra['phoneNumber'] as String? ?? '',
        );
      },
    ),
    GoRoute(
      path: '/email-login',
      builder: (context, state) => const EmailLoginScreen(),
    ),
    GoRoute(
      path: '/profile-setup',
      builder: (context, state) => const ProfileSetupScreen(),
    ),
    GoRoute(
      path: '/home',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    ),
    GoRoute(
      path: '/session',
      builder: (context, state) => const ActiveSessionScreen(),
    ),
    GoRoute(
      path: '/volunteer',
      builder: (context, state) => const VolunteerDashboardScreen(),
    ),
    GoRoute(
      path: '/broadcast',
      builder: (context, state) => const BroadcastScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/emergency-contacts',
      builder: (context, state) => const EmergencyContactsScreen(),
    ),
    GoRoute(
      path: '/location-sharing',
      builder: (context, state) => const LocationSharingScreen(),
    ),
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/admin',
      builder: (context, state) {
        // Guard: Admin Dashboard is only available on Web / Desktop.
        if (!isWebOrDesktop) {
          return Scaffold(
            appBar: AppBar(title: const Text('Unavailable')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.block_rounded, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Admin Dashboard is only available on Web or Desktop.',
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => context.go('/home'),
                    icon: const Icon(Icons.home_rounded),
                    label: const Text('Go Home'),
                  ),
                ],
              ),
            ),
          );
        }
        return const AdminDashboardScreen();
      },
    ),
    GoRoute(
      path: '/fake-call',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return FakeCallScreen(
          callerName: extra['callerName'] as String? ?? 'Mom',
          callerLabel: extra['callerLabel'] as String? ?? 'Mobile',
        );
      },
    ),
    GoRoute(
      path: '/virtual-companion-setup',
      builder: (context, state) => const VirtualCompanionSetupScreen(),
    ),
    GoRoute(
      path: '/active-companion',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return ActiveCompanionScreen(
          destination: extra['destination'] as String? ?? 'Unknown',
          durationMinutes: extra['durationMinutes'] as int? ?? 30,
        );
      },
    ),
    GoRoute(
      path: '/pin-setup',
      builder: (context, state) => const PinSetupScreen(),
    ),
    GoRoute(
      path: '/volunteer-verification',
      builder: (context, state) => const VolunteerVerificationScreen(),
    ),
    GoRoute(
      path: '/camouflage',
      builder: (context, state) => const CamouflageScreen(),
    ),
    GoRoute(
      path: '/walking-buddy-setup',
      builder: (context, state) => const WalkingBuddySetupScreen(),
    ),
    GoRoute(
      path: '/walking-buddy-active',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final sessionId = extra['sessionId'] as String? ?? '';
        if (sessionId.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Walking Buddy')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Invalid or missing session ID.'),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('Go Home'),
                  ),
                ],
              ),
            ),
          );
        }
        return WalkingBuddyActiveView(sessionId: sessionId);
      },
    ),
    GoRoute(
      path: '/walk-with-me-setup',
      builder: (context, state) => const WalkWithMeSetupScreen(),
    ),
    GoRoute(
      path: '/walk-with-me-active',
      builder: (context, state) => const WalkWithMeActiveScreen(),
    ),
  ],
);
