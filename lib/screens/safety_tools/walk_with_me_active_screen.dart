import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../config/theme.dart';
import '../../widgets/animated_gradient_bg.dart';
import '../../services/walk_with_me_service.dart';

/// Active heartbeat screen — shows a countdown and a pulsing "I Am Safe"
/// button. If the timer reaches zero, an automatic SOS is triggered.
class WalkWithMeActiveScreen extends StatefulWidget {
  const WalkWithMeActiveScreen({super.key});

  @override
  State<WalkWithMeActiveScreen> createState() =>
      _WalkWithMeActiveScreenState();
}

class _WalkWithMeActiveScreenState extends State<WalkWithMeActiveScreen>
    with TickerProviderStateMixin {
  final _service = WalkWithMeService.instance;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  late final AnimationController _warningGlowController;
  late final Animation<double> _warningGlowAnim;

  bool _hasVibrated = false; // track whether we already vibrated this cycle
  bool _expired = false;

  @override
  void initState() {
    super.initState();

    // Keep screen on while this screen is active.
    WakelockPlus.enable();

    // Pulse animation for the "I Am Safe" button.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Warning glow ring (faster, only used when < 20%).
    _warningGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _warningGlowAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _warningGlowController,
        curve: Curves.easeInOut,
      ),
    );

    // Listen for value changes.
    _service.remainingSeconds.addListener(_onTick);
    _service.isActive.addListener(_onActiveChanged);
  }

  @override
  void dispose() {
    _service.remainingSeconds.removeListener(_onTick);
    _service.isActive.removeListener(_onActiveChanged);
    _pulseController.dispose();
    _warningGlowController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  // ── Listeners ──

  void _onTick() {
    if (!mounted) return;
    final rem = _service.remainingSeconds.value;
    final total = _service.totalSeconds.value;

    // Trigger haptic in warning zone (once per cycle).
    if (total > 0 && rem <= (total * 0.2).round() && rem > 0) {
      if (!_hasVibrated) {
        _hasVibrated = true;
        _vibratePulse();
      }
    }

    if (rem <= 0 && total > 0 && !_expired) {
      _expired = true;
      _onTimerExpired();
    }

    setState(() {});
  }

  void _onActiveChanged() {
    if (!_service.isActive.value && mounted && !_expired) {
      // Service was stopped externally (e.g. from notification).
      context.go('/home');
    }
  }

  // ── Actions ──

  void _resetTimer() {
    HapticFeedback.mediumImpact();
    _service.resetHeartbeat();
    _hasVibrated = false;
    _expired = false;
    setState(() {});
  }

  Future<void> _stopSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Stop Session?'),
        content: const Text(
          'Are you sure you want to end the Walk-with-Me heartbeat? '
          'Automatic SOS protection will be turned off.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: SakhiTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Stop'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _service.stopHeartbeat();
      if (mounted) context.go('/home');
    }
  }

  Future<void> _onTimerExpired() async {
    // SOS is triggered inside the service's background listener, but we also
    // trigger from the UI side in case the background isolate was killed.
    await _service.triggerAutomaticSOS();
    await _service.stopHeartbeat();
    if (!mounted) return;

    // Navigate to the home screen with a warning
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(
            Icons.warning_rounded,
            color: SakhiTheme.danger,
            size: 48,
          ),
          title: const Text('Automatic SOS Sent'),
          content: const Text(
            'You did not confirm your safety in time. '
            'An emergency broadcast has been sent to nearby volunteers.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.go('/home');
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _vibratePulse() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        await Vibration.vibrate(
          pattern: [0, 150, 100, 150, 100, 150],
          intensities: [0, 200, 0, 200, 0, 200],
        );
      }
    } catch (_) {
      // Vibration not available — ignore.
    }
  }

  // ── UI helpers ──

  double get _progress {
    final total = _service.totalSeconds.value;
    final rem = _service.remainingSeconds.value;
    if (total <= 0) return 1.0;
    return (rem / total).clamp(0.0, 1.0);
  }

  bool get _isWarning => _progress < 0.2 && _progress > 0;

  String get _formattedTime {
    final rem = _service.remainingSeconds.value;
    final m = (rem ~/ 60).toString().padLeft(2, '0');
    final s = (rem % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Color get _progressColor {
    if (_progress <= 0) return SakhiTheme.danger;
    if (_isWarning) return SakhiTheme.searching;
    return SakhiTheme.safe;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final ringSize = screenWidth * 0.65;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: _stopSession,
        ),
        title: const Text(
          'Walk With Me',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton.icon(
            onPressed: _stopSession,
            icon: const Icon(Icons.stop_rounded, color: Colors.white70),
            label: const Text(
              'Stop',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
      body: AnimatedGradientBackground(
        colors: _isWarning
            ? const [
                Color(0xFF4A0E0E),
                Color(0xFF2E0505),
                Color(0xFF1A0000),
                Color(0xFF4A0E0E),
              ]
            : null,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),

              // ── Status label ──
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Container(
                  key: ValueKey(_isWarning),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _isWarning
                        ? SakhiTheme.danger.withValues(alpha: 0.2)
                        : SakhiTheme.safe.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isWarning
                          ? SakhiTheme.danger.withValues(alpha: 0.4)
                          : SakhiTheme.safe.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isWarning
                            ? Icons.warning_rounded
                            : Icons.shield_rounded,
                        size: 16,
                        color: _isWarning
                            ? SakhiTheme.searching
                            : SakhiTheme.safe,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isWarning
                            ? 'TAP NOW to confirm safety!'
                            : 'Session Active — You are protected',
                        style: TextStyle(
                          color: _isWarning
                              ? SakhiTheme.searching
                              : SakhiTheme.safe,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // ── Circular countdown + "I Am Safe" button ──
              SizedBox(
                width: ringSize,
                height: ringSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Warning glow ring
                    if (_isWarning)
                      AnimatedBuilder(
                        animation: _warningGlowAnim,
                        builder: (context, child) {
                          return Container(
                            width: ringSize + 20,
                            height: ringSize + 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: SakhiTheme.danger.withValues(
                                    alpha: _warningGlowAnim.value * 0.5,
                                  ),
                                  blurRadius: 40,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                    // Progress ring
                    SizedBox(
                      width: ringSize,
                      height: ringSize,
                      child: CustomPaint(
                        painter: _CountdownRingPainter(
                          progress: _progress,
                          color: _progressColor,
                          trackColor: Colors.white.withValues(alpha: 0.1),
                          strokeWidth: 10,
                        ),
                      ),
                    ),

                    // "I Am Safe" pulse button
                    ScaleTransition(
                      scale: _pulseAnim,
                      child: GestureDetector(
                        onTap: _resetTimer,
                        child: Container(
                          width: ringSize * 0.72,
                          height: ringSize * 0.72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: _isWarning
                                  ? [
                                      SakhiTheme.danger,
                                      SakhiTheme.danger.withValues(alpha: 0.7),
                                    ]
                                  : [
                                      SakhiTheme.primary,
                                      SakhiTheme.primaryDark,
                                    ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (_isWarning
                                        ? SakhiTheme.danger
                                        : SakhiTheme.primary)
                                    .withValues(alpha: 0.4),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.favorite_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'I Am Safe',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tap to reset',
                                style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.7),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Digital countdown ──
              Text(
                _formattedTime,
                style: TextStyle(
                  color: _progressColor,
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'remaining',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                ),
              ),

              const Spacer(),

              // ── Bottom info ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Colors.white.withValues(alpha: 0.5),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'If the timer reaches zero without a tap, '
                          'an SOS broadcast will be sent automatically.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────── Custom painter for the countdown ring ─────────

class _CountdownRingPainter extends CustomPainter {
  final double progress; // 0.0 → 1.0
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  _CountdownRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    // Progress arc (starts from top, goes clockwise)
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // start at 12 o'clock
      2 * math.pi * progress, // sweep
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CountdownRingPainter old) {
    return old.progress != progress || old.color != color;
  }
}
