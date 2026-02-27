import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_stub.dart' if (dart.library.io) 'platform_io.dart';

/// Service that manages the System Alert Window overlay for displaying an SOS
/// button on top of other apps (e.g., Google Maps during navigation).
///
/// **Android only** — uses the `flutter_overlay_window` package which relies
/// on the `SYSTEM_ALERT_WINDOW` permission.
///
/// On iOS, overlay windows are not permitted by the OS. Instead, the app shows
/// a persistent notification with an SOS action.
class SosOverlayService {
  SosOverlayService._();
  static final SosOverlayService instance = SosOverlayService._();

  static const _channel = MethodChannel('sakhi/sos_overlay');

  bool _isShowing = false;
  bool get isShowing => _isShowing;

  /// Check & request the `SYSTEM_ALERT_WINDOW` permission (Android only).
  Future<bool> requestOverlayPermission() async {
    if (kIsWeb || !isAndroidPlatform) return false;
    try {
      final result = await _channel.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } on MissingPluginException {
      debugPrint('[SosOverlayService] Overlay channel not available');
      return false;
    } catch (e) {
      debugPrint('[SosOverlayService] Permission request error: $e');
      return false;
    }
  }

  /// Check if the overlay permission is already granted.
  Future<bool> hasOverlayPermission() async {
    if (kIsWeb || !isAndroidPlatform) return false;
    try {
      final result = await _channel.invokeMethod<bool>('hasPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Show the floating SOS button overlay.
  Future<void> showOverlay() async {
    if (kIsWeb || !isAndroidPlatform) return;
    if (_isShowing) return;
    try {
      await _channel.invokeMethod('showOverlay');
      _isShowing = true;
      debugPrint('[SosOverlayService] Overlay shown');
    } on MissingPluginException {
      debugPrint('[SosOverlayService] Overlay plugin not available — '
          'ensure flutter_overlay_window is configured in AndroidManifest.xml');
    } catch (e) {
      debugPrint('[SosOverlayService] Show overlay error: $e');
    }
  }

  /// Hide the floating SOS button overlay.
  Future<void> hideOverlay() async {
    if (kIsWeb || !isAndroidPlatform) return;
    if (!_isShowing) return;
    try {
      await _channel.invokeMethod('hideOverlay');
      _isShowing = false;
      debugPrint('[SosOverlayService] Overlay hidden');
    } catch (e) {
      debugPrint('[SosOverlayService] Hide overlay error: $e');
    }
  }

  /// Register the callback invoked when the overlay SOS button is tapped.
  /// The callback receives no arguments — the caller is responsible for
  /// triggering the actual broadcast/SOS logic.
  void registerSosTapCallback(VoidCallback onSosTapped) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSosTapped') {
        onSosTapped();
      }
    });
  }

  /// Clean up method channel handler.
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    if (_isShowing) await hideOverlay();
  }
}
