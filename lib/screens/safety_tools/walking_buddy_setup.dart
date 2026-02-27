import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/providers.dart';
import '../../services/location_service.dart';
import '../../services/walking_buddy_service.dart';

/// Walking Buddy setup screen.
///  1) Search for a destination via Google Places Autocomplete
///  2) Pin-drop the pickup location on an interactive map
///  3) Create the Firestore walking_session and navigate to the active view
class WalkingBuddySetupScreen extends ConsumerStatefulWidget {
  const WalkingBuddySetupScreen({super.key});

  @override
  ConsumerState<WalkingBuddySetupScreen> createState() =>
      _WalkingBuddySetupScreenState();
}

class _WalkingBuddySetupScreenState
    extends ConsumerState<WalkingBuddySetupScreen> {
  // ── Controllers ──
  final _destinationController = TextEditingController();
  // ignore: unused_field
  GoogleMapController? _mapController;

  // ── State ──
  LatLng? _pickupLocation;
  LatLng? _destinationLocation;
  String? _destinationName;
  bool _isLoading = false;
  bool _pickupConfirmed = false;

  // ── Places autocomplete ──
  List<_PlacePrediction> _predictions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadCurrentPosition();
  }

  @override
  void dispose() {
    _destinationController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentPosition() async {
    final pos = await LocationService.instance.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() => _pickupLocation = LatLng(pos.latitude, pos.longitude));
    }
  }

  // ─────────────────────────────────────────────
  // Google Places Autocomplete
  // ─────────────────────────────────────────────

  void _onDestinationChanged(String input) {
    _debounce?.cancel();
    if (input.trim().length < 3) {
      setState(() => _predictions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _fetchPredictions(input.trim());
    });
  }

  Future<void> _fetchPredictions(String input) async {
    final key = AppConstants.googleMapsApiKey;
    if (key == 'YOUR_GOOGLE_MAPS_API_KEY') {
      // Fallback: allow manual lat/lng entry or just use typed text
      debugPrint('[WalkingBuddySetup] No API key configured for Places API');
      return;
    }
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=${Uri.encodeComponent(input)}'
      '&key=$key'
      '&components=country:in',
    );
    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final list = (json['predictions'] as List?) ?? [];
        setState(() {
          _predictions = list
              .map((p) => _PlacePrediction(
                    description: p['description'] as String? ?? '',
                    placeId: p['place_id'] as String? ?? '',
                  ))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('[WalkingBuddySetup] Places API error: $e');
    }
  }

  Future<void> _selectPrediction(_PlacePrediction prediction) async {
    setState(() => _predictions = []);
    FocusScope.of(context).unfocus();

    final key = AppConstants.googleMapsApiKey;
    if (key == 'YOUR_GOOGLE_MAPS_API_KEY') {
      // Without a real API key, we cannot geocode. Set name optimistically.
      _destinationController.text = prediction.description;
      _destinationName = prediction.description;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tap the map to set the destination if Places API is unavailable.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=${prediction.placeId}'
      '&fields=geometry'
      '&key=$key',
    );
    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final loc = json['result']?['geometry']?['location'];
        if (loc != null) {
          final lat = (loc['lat'] as num).toDouble();
          final lng = (loc['lng'] as num).toDouble();
          // Set name/coordinates only after successful geocode
          setState(() {
            _destinationLocation = LatLng(lat, lng);
            _destinationName = prediction.description;
            _destinationController.text = prediction.description;
          });
        }
      }
    } catch (e) {
      debugPrint('[WalkingBuddySetup] Place details error: $e');
    }
  }

  // ─────────────────────────────────────────────
  // Map interactions
  // ─────────────────────────────────────────────

  void _onMapTap(LatLng pos) {
    if (!_pickupConfirmed) {
      setState(() => _pickupLocation = pos);
    } else if (_destinationLocation == null) {
      // Allow setting destination via map tap
      setState(() => _destinationLocation = pos);
    }
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    if (_pickupLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: _pickupLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        draggable: !_pickupConfirmed,
        onDragEnd: (pos) => setState(() => _pickupLocation = pos),
        infoWindow: const InfoWindow(title: 'Pickup Point'),
      ));
    }
    if (_destinationLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: _destinationLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Destination',
          snippet: _destinationName ?? '',
        ),
      ));
    }
    return markers;
  }

  // ─────────────────────────────────────────────
  // Create session
  // ─────────────────────────────────────────────

  Future<void> _createSession() async {
    if (_pickupLocation == null) {
      _showSnack('Please set your pickup location on the map.');
      return;
    }
    if (_destinationLocation == null) {
      _showSnack('Please select a destination.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      final userModel = ref.read(currentUserProvider).value;

      final session = await WalkingBuddyService.instance.createSession(
        userId: user.uid,
        userName: userModel?.name,
        userPhone: userModel?.phone,
        pickupCoords: GeoPoint(
          _pickupLocation!.latitude,
          _pickupLocation!.longitude,
        ),
        destinationCoords: GeoPoint(
          _destinationLocation!.latitude,
          _destinationLocation!.longitude,
        ),
        pickupName: 'Pickup',
        destinationName: _destinationName ?? 'Destination',
      );

      if (mounted) {
        context.pushReplacement('/walking-buddy-active', extra: {
          'sessionId': session.sessionId,
        });
      }
    } catch (e) {
      debugPrint('[WalkingBuddySetup] Error: $e');
      _showSnack('Failed to create session. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ─────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Walking Buddy'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // ── Map ──
          Expanded(
            flex: 3,
            child: _pickupLocation == null
                ? const Center(child: CircularProgressIndicator())
                : GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _pickupLocation!,
                      zoom: 16,
                    ),
                    markers: _buildMarkers(),
                    onTap: _onMapTap,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: false,
                    onMapCreated: (c) => _mapController = c,
                  ),
          ),

          // ── Bottom Sheet ──
          Expanded(
            flex: 4,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // ── Step 1: Pickup ──
                    _StepHeader(
                      step: 1,
                      title: 'Set Pickup Point',
                      subtitle: _pickupConfirmed
                          ? 'Pickup confirmed ✓'
                          : 'Drag the green marker or tap the map',
                      done: _pickupConfirmed,
                    ),
                    if (!_pickupConfirmed) ...[
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _pickupLocation == null
                            ? null
                            : () => setState(() => _pickupConfirmed = true),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Confirm Pickup'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SakhiTheme.safe,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // ── Step 2: Destination ──
                    _StepHeader(
                      step: 2,
                      title: 'Where are you going?',
                      subtitle: _destinationLocation != null
                          ? _destinationName ?? 'Destination set ✓'
                          : 'Search or tap the map',
                      done: _destinationLocation != null,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _destinationController,
                      onChanged: _onDestinationChanged,
                      decoration: const InputDecoration(
                        hintText: 'Search destination...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    // Predictions dropdown
                    if (_predictions.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _predictions.length,
                          separatorBuilder: (context, i) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final p = _predictions[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.place_rounded,
                                  size: 20),
                              title: Text(
                                p.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              onTap: () => _selectPrediction(p),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 28),

                    // ── Request Buddy ──
                    ElevatedButton.icon(
                      onPressed: (_pickupConfirmed &&
                              _destinationLocation != null &&
                              !_isLoading)
                          ? _createSession
                          : null,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.directions_walk_rounded),
                      label: Text(
                          _isLoading ? 'Creating...' : 'Request Walking Buddy'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SakhiTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 16),
                    // ── Info note ──
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color:
                            SakhiTheme.searching.withValues(alpha: 0.08),
                        border: Border.all(
                          color:
                              SakhiTheme.searching.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: SakhiTheme.searching, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'A verified volunteer will walk with you to your '
                              'destination. Your location is shared only during '
                              'the active session.',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────

class _StepHeader extends StatelessWidget {
  final int step;
  final String title;
  final String subtitle;
  final bool done;

  const _StepHeader({
    required this.step,
    required this.title,
    required this.subtitle,
    this.done = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? SakhiTheme.safe.withValues(alpha: 0.15)
                : SakhiTheme.primary.withValues(alpha: 0.12),
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, size: 16, color: SakhiTheme.safe)
                : Text(
                    '$step',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: SakhiTheme.primary,
                      fontSize: 13,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              Text(subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlacePrediction {
  final String description;
  final String placeId;
  const _PlacePrediction({required this.description, required this.placeId});
}
