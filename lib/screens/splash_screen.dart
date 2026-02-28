import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/platform_helper.dart';
import '../models/user_model.dart';
import '../widgets/animated_gradient_bg.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ── Master stagger controller (drives all entrance animations) ──
  late final AnimationController _staggerController;

  // Individual element animations (staggered intervals)
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _hindiFade;
  late final Animation<Offset> _hindiSlide;
  late final Animation<double> _taglineFade;
  late final Animation<Offset> _taglineSlide;
  late final Animation<double> _loaderFade;

  // Pulsing glow behind logo
  late final AnimationController _glowController;
  late final Animation<double> _glowScale;
  late final Animation<double> _glowOpacity;

  // Shimmer sweep across title
  late final AnimationController _shimmerController;

  // Floating particles
  late final AnimationController _particleController;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();

    // ── Random particles ──
    final rng = math.Random(42);
    _particles = List.generate(18, (_) => _Particle.random(rng));

    // ── Stagger controller: 1.6s total entrance ──
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    // Logo: 0% → 35%
    _logoFade = CurvedAnimation(
      parent: _staggerController,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _staggerController,
        curve: const Interval(0.0, 0.40, curve: Curves.elasticOut),
      ),
    );

    // Title "SAKHI": 20% → 55%
    _titleFade = CurvedAnimation(
      parent: _staggerController,
      curve: const Interval(0.20, 0.55, curve: Curves.easeOut),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _staggerController,
      curve: const Interval(0.20, 0.55, curve: Curves.easeOutCubic),
    ));

    // Hindi text: 35% → 65%
    _hindiFade = CurvedAnimation(
      parent: _staggerController,
      curve: const Interval(0.35, 0.65, curve: Curves.easeOut),
    );
    _hindiSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _staggerController,
      curve: const Interval(0.35, 0.65, curve: Curves.easeOutCubic),
    ));

    // Tagline: 50% → 80%
    _taglineFade = CurvedAnimation(
      parent: _staggerController,
      curve: const Interval(0.50, 0.80, curve: Curves.easeOut),
    );
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _staggerController,
      curve: const Interval(0.50, 0.80, curve: Curves.easeOutCubic),
    ));

    // Loader dots: 70% → 100%
    _loaderFade = CurvedAnimation(
      parent: _staggerController,
      curve: const Interval(0.70, 1.0, curve: Curves.easeOut),
    );

    // ── Glow pulse behind logo ──
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowScale = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _glowOpacity = Tween<double>(begin: 0.25, end: 0.55).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // ── Shimmer sweep ──
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    // ── Floating particles ──
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Start entrance
    _staggerController.forward();

    _navigateAfterDelay();
  }

  Future<void> _navigateAfterDelay() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    try {
      // On Web/Desktop, if admin override is still active, go straight to admin.
      if (isWebOrDesktop && AuthService.instance.isAdminOverrideActive) {
        if (mounted) context.go('/admin');
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final hasProfile = await AuthService.instance.hasProfile();
        if (!mounted) return;
        if (!hasProfile) {
          context.go('/profile-setup');
          return;
        }
        // Fetch role and redirect accordingly
        // TODO(security): The `role` field lives in the user-writable Firestore
        // document. For production, verify admin status server-side (e.g. via
        // Firebase Custom Claims on the ID token) to prevent privilege
        // escalation by a user editing their own document.
        final userModel = await FirestoreService.instance.getUser(user.uid);
        if (!mounted) return;
        switch (userModel?.role ?? UserRole.user) {
          case UserRole.admin:
            if (kIsWeb) {
              context.go('/admin');
            } else {
              // Admin cannot access from mobile — sign out
              await AuthService.instance.signOut();
              if (mounted) context.go('/login');
            }
          case UserRole.volunteer:
            context.go('/volunteer');
          case UserRole.user:
            context.go('/home');
        }
      } else {
        // On Web/Desktop, go directly to email login (admin portal).
        if (isWebOrDesktop) {
          if (mounted) context.go('/email-login');
        } else {
          if (mounted) context.go('/login');
        }
      }
    } catch (e) {
      // Firebase not configured – go to login
      if (mounted) context.go('/login');
    }
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _glowController.dispose();
    _shimmerController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedGradientBackground(
        child: Stack(
          children: [
            // ── Floating particles layer ──
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _particleController,
                builder: (context, _) => CustomPaint(
                  painter: _ParticlePainter(
                    particles: _particles,
                    progress: _particleController.value,
                  ),
                ),
              ),
            ),

            // ── Main content ──
            SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Logo with pulsing glow ──
                    FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: AnimatedBuilder(
                          animation: _glowController,
                          builder: (context, child) => Stack(
                            alignment: Alignment.center,
                            children: [
                              // Glow ring
                              Transform.scale(
                                scale: _glowScale.value,
                                child: Container(
                                  width: 160,
                                  height: 160,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFE91E63)
                                            .withValues(
                                                alpha: _glowOpacity.value),
                                        blurRadius: 40,
                                        spreadRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Actual logo
                              child!,
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.asset(
                              'assets/images/sakhi-logo-3.png',
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 36),

                    // ── Title "SAKHI" with shimmer ──
                    SlideTransition(
                      position: _titleSlide,
                      child: FadeTransition(
                        opacity: _titleFade,
                        child: AnimatedBuilder(
                          animation: _shimmerController,
                          builder: (context, child) => ShaderMask(
                            shaderCallback: (bounds) {
                              final dx = _shimmerController.value * 3.0 - 1.0;
                              return LinearGradient(
                                begin: Alignment(dx - 0.3, 0),
                                end: Alignment(dx + 0.3, 0),
                                colors: const [
                                  Color(0xFFE91E63),
                                  Color(0xFFFFFFFF),
                                  Color(0xFFE91E63),
                                ],
                                stops: const [0.0, 0.5, 1.0],
                              ).createShader(bounds);
                            },
                            blendMode: BlendMode.srcATop,
                            child: child,
                          ),
                          child: const Text(
                            'SAKHI',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    // ── Hindi subtitle ──
                    SlideTransition(
                      position: _hindiSlide,
                      child: FadeTransition(
                        opacity: _hindiFade,
                        child: Text(
                          'सखी',
                          style: TextStyle(
                            fontSize: 22,
                            letterSpacing: 6,
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ── Tagline ──
                    SlideTransition(
                      position: _taglineSlide,
                      child: FadeTransition(
                        opacity: _taglineFade,
                        child: Text(
                          'Your Trusted Friend & Protector',
                          style: TextStyle(
                            fontSize: 14,
                            letterSpacing: 3,
                            color: Colors.white.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 52),

                    // ── Animated dot loader ──
                    FadeTransition(
                      opacity: _loaderFade,
                      child: const _AnimatedDotLoader(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Floating-particle data & painter
// ═══════════════════════════════════════════════════════════════════

class _Particle {
  final double startX; // 0-1
  final double startY; // 0-1
  final double radius;
  final double speed; // multiplier
  final double phase; // 0–2π offset
  final double opacity;

  const _Particle({
    required this.startX,
    required this.startY,
    required this.radius,
    required this.speed,
    required this.phase,
    required this.opacity,
  });

  factory _Particle.random(math.Random rng) {
    return _Particle(
      startX: rng.nextDouble(),
      startY: rng.nextDouble(),
      radius: 1.5 + rng.nextDouble() * 2.5,
      speed: 0.3 + rng.nextDouble() * 0.7,
      phase: rng.nextDouble() * 2 * math.pi,
      opacity: 0.15 + rng.nextDouble() * 0.35,
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress; // 0-1

  _ParticlePainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = (progress * p.speed + p.phase) % 1.0;
      final x = (p.startX + math.sin(t * 2 * math.pi) * 0.06) * size.width;
      final y = (p.startY - t * 0.3) % 1.0 * size.height;
      final paint = Paint()
        ..color = const Color(0xFFF48FB1).withValues(alpha: p.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(Offset(x, y), p.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════
// Animated dot loader (three bouncing dots)
// ═══════════════════════════════════════════════════════════════════

class _AnimatedDotLoader extends StatefulWidget {
  const _AnimatedDotLoader();

  @override
  State<_AnimatedDotLoader> createState() => _AnimatedDotLoaderState();
}

class _AnimatedDotLoaderState extends State<_AnimatedDotLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each dot is offset by 0.2 in phase
            final t = (_ctrl.value + i * 0.2) % 1.0;
            // Bounce: sin gives a smooth up-down
            final bounce = math.sin(t * math.pi);
            final opacity = 0.3 + 0.7 * bounce;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Transform.translate(
                offset: Offset(0, -6 * bounce),
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE91E63)
                              .withValues(alpha: 0.4 * bounce),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
