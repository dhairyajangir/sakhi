import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firestore_service.dart';
import 'location_service.dart';

// ───────── Constants ─────────

const String _kNotificationChannelId = 'sakhi_walk_with_me';
const String _kNotificationChannelName = 'Walk With Me Timer';
const String _kNotificationChannelDesc =
    'Persistent notification for the Walk-with-Me heartbeat timer.';
const int _kNotificationId = 9001;

// Background-service ↔ UI event keys
const String kStartTimerEvent = 'start_timer';
const String kResetTimerEvent = 'reset_timer';
const String kStopTimerEvent = 'stop_timer';
const String kTickEvent = 'tick';
const String kTimerExpiredEvent = 'timer_expired';
const String kResetFromNotificationEvent = 'reset_from_notification';

// ───────── Top-level background entry point ─────────

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  // Ensure Flutter bindings are available in the background isolate.
  DartPluginRegistrant.ensureInitialized();

  final notifications = FlutterLocalNotificationsPlugin();

  Duration intervalDuration = Duration.zero;
  Duration remaining = Duration.zero;
  Timer? countdownTimer;

  // ── Helpers ──

  Future<void> updateNotification(Duration rem, Duration total) async {
    final minutes = rem.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = rem.inSeconds.remainder(60).toString().padLeft(2, '0');
    final pct = total.inSeconds > 0
        ? ((rem.inSeconds / total.inSeconds) * 100).round()
        : 0;

    final isWarning = total.inSeconds > 0 &&
        rem.inSeconds <= (total.inSeconds * 0.2).round();

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _kNotificationChannelId,
      _kNotificationChannelName,
      channelDescription: _kNotificationChannelDesc,
      importance: isWarning ? Importance.high : Importance.low,
      priority: isWarning ? Priority.high : Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      category: AndroidNotificationCategory.service,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'reset_timer',
          '✅ I Am Safe',
          showsUserInterface: false,
          cancelNotification: false,
        ),
        const AndroidNotificationAction(
          'stop_timer',
          '⏹ Stop',
          showsUserInterface: false,
          cancelNotification: false,
        ),
      ],
    );

    await notifications.show(
      _kNotificationId,
      isWarning ? '⚠️ Tap "I Am Safe" NOW!' : 'Walk With Me — $pct% left',
      'Time remaining: $minutes:$seconds',
      NotificationDetails(android: androidDetails),
    );
  }

  void stopTimer() {
    countdownTimer?.cancel();
    countdownTimer = null;
    notifications.cancel(_kNotificationId);
  }

  void startTimer(int totalSeconds) {
    stopTimer();
    intervalDuration = Duration(seconds: totalSeconds);
    remaining = intervalDuration;

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      remaining -= const Duration(seconds: 1);
      if (remaining.isNegative) remaining = Duration.zero;

      // Broadcast tick to UI
      service.invoke(kTickEvent, {
        'remaining': remaining.inSeconds,
        'total': intervalDuration.inSeconds,
      });

      updateNotification(remaining, intervalDuration);

      if (remaining.inSeconds <= 0) {
        stopTimer();
        service.invoke(kTimerExpiredEvent);
      }
    });

    updateNotification(remaining, intervalDuration);
  }

  void resetTimer() {
    if (intervalDuration.inSeconds <= 0) return;
    remaining = intervalDuration;
    service.invoke(kTickEvent, {
      'remaining': remaining.inSeconds,
      'total': intervalDuration.inSeconds,
    });
    updateNotification(remaining, intervalDuration);
  }

  // ── Listen for events from the UI ──

  service.on(kStartTimerEvent).listen((event) {
    final totalSeconds = event?['totalSeconds'] as int? ?? 0;
    if (totalSeconds > 0) startTimer(totalSeconds);
  });

  service.on(kResetTimerEvent).listen((_) => resetTimer());

  service.on(kStopTimerEvent).listen((_) {
    stopTimer();
    service.stopSelf();
  });

  // ── Listen for notification action taps ──
  service.on(kResetFromNotificationEvent).listen((_) => resetTimer());
}

// ───────── Notification action handler (foreground) ─────────

@pragma('vm:entry-point')
void onNotificationAction(NotificationResponse response) {
  final service = FlutterBackgroundService();
  switch (response.actionId) {
    case 'reset_timer':
      service.invoke(kResetFromNotificationEvent);
      break;
    case 'stop_timer':
      service.invoke(kStopTimerEvent);
      break;
  }
}

// ───────── Service singleton (UI-side API) ─────────

class WalkWithMeService {
  WalkWithMeService._();
  static final WalkWithMeService instance = WalkWithMeService._();

  final FlutterBackgroundService _service = FlutterBackgroundService();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // ── State exposed to providers ──
  final ValueNotifier<bool> isActive = ValueNotifier(false);
  final ValueNotifier<int> remainingSeconds = ValueNotifier(0);
  final ValueNotifier<int> totalSeconds = ValueNotifier(0);

  StreamSubscription<Map<String, dynamic>?>? _tickSub;
  StreamSubscription<Map<String, dynamic>?>? _expiredSub;

  // ── Initialization ──

  /// Call once from main() to configure the background service and
  /// notification channel.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Create the Android notification channel.
    const androidChannel = AndroidNotificationChannel(
      _kNotificationChannelId,
      _kNotificationChannelName,
      description: _kNotificationChannelDesc,
      importance: Importance.low,
    );

    final androidPlugin =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(androidChannel);

    // Initialize flutter_local_notifications for foreground notification actions.
    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: onNotificationAction,
      onDidReceiveBackgroundNotificationResponse: onNotificationAction,
    );

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: true,
        autoStart: false,
        autoStartOnBoot: false,
        notificationChannelId: _kNotificationChannelId,
        initialNotificationTitle: 'Walk With Me',
        initialNotificationContent: 'Starting heartbeat timer…',
        foregroundServiceNotificationId: _kNotificationId,
        foregroundServiceTypes: [AndroidForegroundType.shortService],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
      ),
    );
  }

  // ── Public API ──

  /// Start the heartbeat with the given interval.
  Future<void> startHeartbeat(Duration interval) async {
    if (!_initialized) await initialize();

    totalSeconds.value = interval.inSeconds;
    remainingSeconds.value = interval.inSeconds;
    isActive.value = true;

    final running = await _service.isRunning();
    if (!running) {
      await _service.startService();
      // Give the isolate a moment to spin up.
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _service.invoke(kStartTimerEvent, {
      'totalSeconds': interval.inSeconds,
    });

    _listenToBackground();
  }

  /// Reset the countdown to the full interval (user taps "I Am Safe").
  void resetHeartbeat() {
    remainingSeconds.value = totalSeconds.value;
    _service.invoke(kResetTimerEvent);
  }

  /// Stop and tear down the heartbeat session completely.
  Future<void> stopHeartbeat() async {
    isActive.value = false;
    remainingSeconds.value = 0;
    totalSeconds.value = 0;
    _tickSub?.cancel();
    _expiredSub?.cancel();
    _service.invoke(kStopTimerEvent);
    await _notifications.cancel(_kNotificationId);
  }

  // ── SOS trigger (reuses existing infrastructure) ──

  /// Automatically fires when the timer expires.
  /// Creates a session + SOS broadcast using the existing services.
  Future<void> triggerAutomaticSOS() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final position = await LocationService.instance.getCurrentPosition();
      GeoPoint? geoPoint;
      if (position != null) {
        geoPoint = GeoPoint(position.latitude, position.longitude);
      }

      // Fetch user profile for name.
      final user = await FirestoreService.instance.getUser(uid);
      final name = user?.name ?? 'Unknown';

      // Send SOS broadcast to community.
      if (geoPoint != null) {
        await FirestoreService.instance.sendBroadcast(
          uid: uid,
          message:
              'Automatic SOS! $name did not confirm safety on Walk-with-Me.',
          alertType: 'need_help',
          location: geoPoint,
          userName: name,
        );
      }
    } catch (e) {
      debugPrint('[WalkWithMe] Automatic SOS failed: $e');
    }
  }

  // ── Internal ──

  void _listenToBackground() {
    _tickSub?.cancel();
    _expiredSub?.cancel();

    _tickSub = _service.on(kTickEvent).listen((event) {
      if (event == null) return;
      remainingSeconds.value = event['remaining'] as int? ?? 0;
      totalSeconds.value = event['total'] as int? ?? totalSeconds.value;
    });

    _expiredSub = _service.on(kTimerExpiredEvent).listen((_) async {
      await triggerAutomaticSOS();
      await stopHeartbeat();
    });
  }
}
