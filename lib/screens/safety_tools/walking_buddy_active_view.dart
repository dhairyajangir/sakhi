import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme.dart';
import '../../models/walking_session_model.dart';
import '../../services/walking_buddy_service.dart';
import '../../widgets/animated_gradient_bg.dart';

/// The active Walking Buddy session view.
/// Streams the Firestore session doc and renders status-specific UIs for
/// both the **User** and the **Volunteer** role.
class WalkingBuddyActiveView extends ConsumerStatefulWidget {
  final String sessionId;
  const WalkingBuddyActiveView({super.key, required this.sessionId});

  @override
  ConsumerState<WalkingBuddyActiveView> createState() =>
      _WalkingBuddyActiveViewState();
}

class _WalkingBuddyActiveViewState
    extends ConsumerState<WalkingBuddyActiveView> {
  late final Stream<WalkingSessionModel?> _sessionStream;
  StreamSubscription? _locationSub;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _sessionStream =
        WalkingBuddyService.instance.sessionStream(widget.sessionId);
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    super.dispose();
  }

  bool _isUser(WalkingSessionModel s) => s.userId == _myUid;

  // ───────────────────────────────────────────
  // Navigation helpers
  // ───────────────────────────────────────────

  Future<void> _openDirections(LatLng destination) async {
    final uri = Uri.parse(
      'google.navigation:q=${destination.latitude},${destination.longitude}&mode=w',
    );
    final fallback = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${destination.latitude},${destination.longitude}'
      '&travelmode=walking',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _makeCall(String? phone) async {
    if (phone == null || phone.isEmpty) {
      _showSnack('Phone number not available');
      return;
    }
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  // ───────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WalkingSessionModel?>(
      stream: _sessionStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final session = snap.data;
        if (session == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Walking Buddy')),
            body: const Center(child: Text('Session not found.')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Walking Buddy'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.go('/home'),
            ),
            actions: [
              if (session.isActive)
                IconButton(
                  icon: const Icon(Icons.cancel_outlined),
                  tooltip: 'Cancel session',
                  onPressed: () => _confirmCancel(session),
                ),
            ],
          ),
          body: _buildBody(session),
        );
      },
    );
  }

  Widget _buildBody(WalkingSessionModel session) {
    switch (session.status) {
      case WalkingSessionStatus.searching:
        return _SearchingView(session: session);

      case WalkingSessionStatus.volunteerAccepted:
        return _isUser(session)
            ? _MatchFoundView(
                session: session,
                onAccept: () => WalkingBuddyService.instance
                    .userConfirmVolunteer(session.sessionId),
                onCall: () => _makeCall(session.volunteerPhone),
              )
            : _WaitingForUserConfirmation(session: session);

      case WalkingSessionStatus.volunteerConfirmed:
      case WalkingSessionStatus.volunteerReached:
        return _HandshakeView(
          session: session,
          isUser: _isUser(session),
          onVolunteerSwipe: () => WalkingBuddyService.instance
              .volunteerConfirmsArrival(session.sessionId),
          onUserSwipe: () => WalkingBuddyService.instance
              .userConfirmsVolunteerArrival(session.sessionId),
          onGetDirections: () => _openDirections(
            LatLng(
              session.pickupCoords.latitude,
              session.pickupCoords.longitude,
            ),
          ),
        );

      case WalkingSessionStatus.inProgress:
        return _JourneyView(
          session: session,
          isUser: _isUser(session),
          onUserSwipe: () => WalkingBuddyService.instance
              .userConfirmsDestination(session.sessionId),
          onVolunteerSwipe: () => WalkingBuddyService.instance
              .volunteerConfirmsDestination(session.sessionId),
          onGetDirections: () => _openDirections(
            LatLng(
              session.destinationCoords.latitude,
              session.destinationCoords.longitude,
            ),
          ),
        );

      case WalkingSessionStatus.completed:
        return _CompletedView(session: session, onDone: () => context.go('/home'));

      case WalkingSessionStatus.cancelled:
        return _CancelledView(onDone: () => context.go('/home'));

      default:
        return const Center(child: Text('Unknown state'));
    }
  }

  Future<void> _confirmCancel(WalkingSessionModel session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel session?'),
        content: const Text('This will end the walking buddy request.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, cancel', style: TextStyle(color: SakhiTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await WalkingBuddyService.instance.cancelSession(session.sessionId);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// STATUS-SPECIFIC VIEWS
// ═══════════════════════════════════════════════════════════════════════

/// Phase 1 – Searching for a volunteer.
class _SearchingView extends StatelessWidget {
  final WalkingSessionModel session;
  const _SearchingView({required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedGradientBackground(
      colors: const [Color(0xFF1A0A2E), Color(0xFF16213E), Color(0xFF0F3460), Color(0xFF1A0A2E)],
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: SakhiTheme.searching,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Looking for a Walking Buddy...',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'A verified volunteer near your pickup point will be notified.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 32),
              _InfoChip(
                icon: Icons.place_rounded,
                label: session.destinationName ?? 'Destination',
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phase 2 – User sees the match card (Accept / Call / Video Call).
class _MatchFoundView extends StatelessWidget {
  final WalkingSessionModel session;
  final VoidCallback onAccept;
  final VoidCallback onCall;
  const _MatchFoundView({
    required this.session,
    required this.onAccept,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Match card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: SakhiTheme.safe.withValues(alpha: 0.12),
                    ),
                    child: const Icon(Icons.person_rounded,
                        size: 40, color: SakhiTheme.safe),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Match Found!',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: SakhiTheme.safe,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    session.volunteerName ?? 'Volunteer',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onCall,
                          icon: const Icon(Icons.phone_rounded, size: 18),
                          label: const Text('Call'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            // Video call placeholder
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Video call coming soon'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          icon: const Icon(Icons.videocam_rounded, size: 18),
                          label: const Text('Video'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.check_circle_rounded, size: 20),
                    label: const Text('Accept Volunteer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SakhiTheme.safe,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Volunteer waits for the user to confirm them.
class _WaitingForUserConfirmation extends StatelessWidget {
  final WalkingSessionModel session;
  const _WaitingForUserConfirmation({required this.session});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: SakhiTheme.connected),
            const SizedBox(height: 24),
            Text(
              'Waiting for ${session.userName ?? "the user"} to confirm...',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Phase 3 – The meetup handshake.
class _HandshakeView extends StatelessWidget {
  final WalkingSessionModel session;
  final bool isUser;
  final VoidCallback onVolunteerSwipe;
  final VoidCallback onUserSwipe;
  final VoidCallback onGetDirections;

  const _HandshakeView({
    required this.session,
    required this.isUser,
    required this.onVolunteerSwipe,
    required this.onUserSwipe,
    required this.onGetDirections,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final volunteerDone = session.volunteerReachedConfirmedByVolunteer;
    final userDone = session.volunteerReachedConfirmedByUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Status banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: SakhiTheme.connected.withValues(alpha: 0.08),
              border: Border.all(color: SakhiTheme.connected.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                const Icon(Icons.handshake_rounded, size: 48, color: SakhiTheme.connected),
                const SizedBox(height: 12),
                Text(
                  isUser
                      ? 'Your buddy is on the way!'
                      : 'Head to the pickup point',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  isUser
                      ? 'Once they arrive, both of you must confirm the meetup.'
                      : 'Navigate to the user\'s pickup location.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Directions button (for volunteer)
          if (!isUser)
            ElevatedButton.icon(
              onPressed: onGetDirections,
              icon: const Icon(Icons.directions_rounded),
              label: const Text('Get Directions to Pickup'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SakhiTheme.connected,
                foregroundColor: Colors.white,
              ),
            ),
          const SizedBox(height: 24),

          // Confirmation status
          _ConfirmationRow(
            label: 'Volunteer confirmed arrival',
            done: volunteerDone,
          ),
          const SizedBox(height: 8),
          _ConfirmationRow(
            label: 'User confirmed arrival',
            done: userDone,
          ),
          const SizedBox(height: 24),

          // Swipe button
          if (isUser && !userDone)
            _SwipeToConfirmButton(
              label: 'Slide to confirm: Buddy arrived',
              color: SakhiTheme.safe,
              onConfirmed: onUserSwipe,
            ),
          if (!isUser && !volunteerDone)
            _SwipeToConfirmButton(
              label: 'Slide to confirm: I reached the user',
              color: SakhiTheme.connected,
              onConfirmed: onVolunteerSwipe,
            ),
          if ((isUser && userDone) || (!isUser && volunteerDone))
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: SakhiTheme.safe.withValues(alpha: 0.08),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: SakhiTheme.safe, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Waiting for the other party...',
                    style: TextStyle(color: SakhiTheme.safe, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Phase 4 – Walking together to destination.
class _JourneyView extends StatelessWidget {
  final WalkingSessionModel session;
  final bool isUser;
  final VoidCallback onUserSwipe;
  final VoidCallback onVolunteerSwipe;
  final VoidCallback onGetDirections;

  const _JourneyView({
    required this.session,
    required this.isUser,
    required this.onUserSwipe,
    required this.onVolunteerSwipe,
    required this.onGetDirections,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userDone = session.destinationReachedConfirmedByUser;
    final volunteerDone = session.destinationReachedConfirmedByVolunteer;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Journey banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(colors: [
                SakhiTheme.safe.withValues(alpha: 0.1),
                SakhiTheme.connected.withValues(alpha: 0.05),
              ]),
            ),
            child: Column(
              children: [
                const Icon(Icons.directions_walk_rounded,
                    size: 48, color: SakhiTheme.safe),
                const SizedBox(height: 12),
                Text(
                  'Walking Together',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold, color: SakhiTheme.safe),
                ),
                const SizedBox(height: 4),
                Text(
                  session.destinationName ?? 'Destination',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Get Directions
          ElevatedButton.icon(
            onPressed: onGetDirections,
            icon: const Icon(Icons.navigation_rounded),
            label: const Text('Navigate to Destination'),
            style: ElevatedButton.styleFrom(
              backgroundColor: SakhiTheme.connected,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 24),

          // Destination confirmation status
          _ConfirmationRow(label: 'User reached destination', done: userDone),
          const SizedBox(height: 8),
          _ConfirmationRow(label: 'Volunteer confirmed destination', done: volunteerDone),
          const SizedBox(height: 24),

          // Swipe buttons
          if (isUser && !userDone)
            _SwipeToConfirmButton(
              label: 'Slide: I reached my destination',
              color: SakhiTheme.safe,
              onConfirmed: onUserSwipe,
            ),
          if (!isUser && !volunteerDone)
            _SwipeToConfirmButton(
              label: 'Slide: Reached destination',
              color: SakhiTheme.connected,
              onConfirmed: onVolunteerSwipe,
            ),
          if ((isUser && userDone) || (!isUser && volunteerDone))
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: SakhiTheme.safe.withValues(alpha: 0.08),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: SakhiTheme.safe, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Waiting for the other party...',
                    style: TextStyle(color: SakhiTheme.safe, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Session completed.
class _CompletedView extends StatelessWidget {
  final WalkingSessionModel session;
  final VoidCallback onDone;
  const _CompletedView({required this.session, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SakhiTheme.safe.withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.check_circle_rounded,
                  size: 56, color: SakhiTheme.safe),
            ),
            const SizedBox(height: 24),
            Text(
              'Walk Completed!',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: SakhiTheme.safe,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You reached your destination safely.',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onDone,
              icon: const Icon(Icons.home_rounded),
              label: const Text('Back to Home'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SakhiTheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Session cancelled.
class _CancelledView extends StatelessWidget {
  final VoidCallback onDone;
  const _CancelledView({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cancel_rounded, size: 64, color: SakhiTheme.danger),
            const SizedBox(height: 16),
            Text(
              'Session Cancelled',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onDone,
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// REUSABLE COMPONENTS
// ═══════════════════════════════════════════════════════════════════════

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: 0.12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmationRow extends StatelessWidget {
  final String label;
  final bool done;
  const _ConfirmationRow({required this.label, required this.done});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          size: 20,
          color: done ? SakhiTheme.safe : Colors.grey,
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: done ? FontWeight.w600 : FontWeight.w400,
            color: done ? SakhiTheme.safe : null,
          ),
        ),
      ],
    );
  }
}

/// A swipe-to-confirm button widget.
class _SwipeToConfirmButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onConfirmed;

  const _SwipeToConfirmButton({
    required this.label,
    required this.color,
    required this.onConfirmed,
  });

  @override
  State<_SwipeToConfirmButton> createState() => _SwipeToConfirmButtonState();
}

class _SwipeToConfirmButtonState extends State<_SwipeToConfirmButton> {
  double _dragPosition = 0;
  bool _confirmed = false;
  static const double _trackWidth = 300;
  static const double _thumbWidth = 60;
  static const double _threshold = 0.85;

  @override
  Widget build(BuildContext context) {
    final maxDrag = _trackWidth - _thumbWidth;
    final progress = (_dragPosition / maxDrag).clamp(0.0, 1.0);

    return Center(
      child: Container(
        width: _trackWidth,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: widget.color.withValues(alpha: 0.12),
          border: Border.all(color: widget.color.withValues(alpha: 0.3)),
        ),
        child: Stack(
          children: [
            // Background fill
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: _thumbWidth + _dragPosition,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: widget.color.withValues(alpha: 0.2 + progress * 0.3),
              ),
            ),
            // Label
            Center(
              child: Text(
                _confirmed ? 'Confirmed!' : widget.label,
                style: TextStyle(
                  color: widget.color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            // Draggable thumb
            Positioned(
              left: _dragPosition,
              top: 3,
              child: GestureDetector(
                onHorizontalDragUpdate: _confirmed
                    ? null
                    : (details) {
                        setState(() {
                          _dragPosition =
                              (_dragPosition + details.delta.dx).clamp(0.0, maxDrag);
                        });
                      },
                onHorizontalDragEnd: _confirmed
                    ? null
                    : (details) {
                        if (progress >= _threshold) {
                          setState(() => _confirmed = true);
                          widget.onConfirmed();
                        } else {
                          setState(() => _dragPosition = 0);
                        }
                      },
                child: Container(
                  width: _thumbWidth,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    color: widget.color,
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(
                    _confirmed
                        ? Icons.check_rounded
                        : Icons.arrow_forward_ios_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
