import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../widgets/animated_gradient_bg.dart';
import '../../services/walk_with_me_service.dart';

/// Lets the user choose an interval (10 s – 60 min) and start a
/// Walk-with-Me heartbeat session.
class WalkWithMeSetupScreen extends StatefulWidget {
  const WalkWithMeSetupScreen({super.key});

  @override
  State<WalkWithMeSetupScreen> createState() => _WalkWithMeSetupScreenState();
}

class _WalkWithMeSetupScreenState extends State<WalkWithMeSetupScreen> {
  // Slider value in seconds (10 – 3600).
  double _intervalSeconds = 300; // default 5 minutes

  // ── Presets shown as quick-pick chips ──
  static const _presets = <_Preset>[
    _Preset(label: '10 s', seconds: 10),
    _Preset(label: '1 min', seconds: 60),
    _Preset(label: '5 min', seconds: 300),
    _Preset(label: '15 min', seconds: 900),
    _Preset(label: '30 min', seconds: 1800),
    _Preset(label: '60 min', seconds: 3600),
  ];

  String get _formattedInterval {
    final dur = Duration(seconds: _intervalSeconds.round());
    if (dur.inSeconds < 60) return '${dur.inSeconds} seconds';
    if (dur.inMinutes < 60) {
      final secs = dur.inSeconds.remainder(60);
      return secs == 0
          ? '${dur.inMinutes} min'
          : '${dur.inMinutes} min ${secs}s';
    }
    return '${dur.inMinutes} min';
  }

  Future<void> _startSession() async {
    final interval = Duration(seconds: _intervalSeconds.round());
    await WalkWithMeService.instance.startHeartbeat(interval);
    if (mounted) {
      context.pushReplacement('/walk-with-me-active');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Walk With Me',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: AnimatedGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 24),

                // ── Hero icon ──
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SakhiTheme.primary.withValues(alpha: 0.15),
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    size: 48,
                    color: SakhiTheme.primary,
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  'Interval Heartbeat',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Set how often you must confirm you are safe.\n'
                  'If you miss the check-in, an automatic SOS will '
                  'be sent to your emergency contacts and nearby volunteers.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),

                const Spacer(),

                // ── Current value badge ──
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _formattedInterval,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Slider ──
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: SakhiTheme.primary,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: SakhiTheme.primary.withValues(alpha: 0.2),
                    trackHeight: 6,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 10,
                    ),
                  ),
                  child: Slider(
                    min: 10,
                    max: 3600,
                    divisions: 359, // ~10-second steps
                    value: _intervalSeconds,
                    onChanged: (v) =>
                        setState(() => _intervalSeconds = v),
                  ),
                ),

                // ── Min / Max labels ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '10 sec',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '60 min',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Quick-pick chips ──
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: _presets.map((p) {
                    final selected =
                        _intervalSeconds.round() == p.seconds;
                    return ChoiceChip(
                      label: Text(p.label),
                      selected: selected,
                      selectedColor: SakhiTheme.primary,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                      ),
                      side: BorderSide.none,
                      onSelected: (_) =>
                          setState(() => _intervalSeconds = p.seconds.toDouble()),
                    );
                  }).toList(),
                ),

                const Spacer(),

                // ── Start button ──
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _startSession,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start Session'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SakhiTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Preset {
  final String label;
  final int seconds;
  const _Preset({required this.label, required this.seconds});
}
