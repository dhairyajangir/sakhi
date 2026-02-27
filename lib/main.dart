import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/theme.dart';
import 'config/router.dart';
import 'config/constants.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'services/hardware_trigger_service.dart';
import 'services/walk_with_me_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode (skip on web)
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  // Initialize Firebase
  bool firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize push notifications
    await NotificationService.instance.initialize();

    // Initialize hardware-button SOS listener (volume-button trigger).
    // This is intentionally fire-and-forget: initialize() is synchronous
    // (void) and sets up an internal stream listener. It handles its own
    // errors internally and does not need to block Firebase readiness.
    HardwareTriggerService.instance.initialize();

    // Prepare the Walk-with-Me background service (does NOT auto-start).
    if (!kIsWeb) {
      await WalkWithMeService.instance.initialize();
    }

    firebaseReady = true;
  } catch (e, st) {
    debugPrint('Firebase init error: $e\n$st');
  }

  if (!firebaseReady) {
    // Show a minimal error app so users aren't left on a blank screen
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Failed to initialise Firebase.\nPlease restart the app.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
    return;
  }

  runApp(const ProviderScope(child: SakhiApp()));
}

class SakhiApp extends StatelessWidget {
  const SakhiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: SakhiTheme.light,
      darkTheme: SakhiTheme.dark,
      themeMode: ThemeMode.light,
      routerConfig: appRouter,
    );
  }
}
