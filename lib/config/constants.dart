class AppConstants {
  AppConstants._();

  // ── App Info ──
  static const String appName = 'SAKHI';
  static const String tagline = 'Your Trusted Companion';

  // ── Location Settings ──
  static const int locationUpdateIntervalSec = 15;
  static const int heartbeatIntervalSec = 30;
  static const int heartbeatTimeoutSec = 120;

  // ── Session Settings ──
  static const int sessionSearchTimeoutMin = 5;
  static const int defaultSessionDurationMin = 30;

  // ── Broadcast Settings ──
  static const double broadcastRadiusKm = 2.0;
  static const double volunteerSearchRadiusKm = 5.0;

  // ── Firestore Collections ──
  static const String usersCollection = 'users';
  static const String sessionsCollection = 'sessions';
  static const String locationUpdatesSubcollection = 'locationUpdates';
  static const String broadcastsCollection = 'broadcasts';
  static const String locationSharesCollection = 'locationShares';
  static const String liveLocationsCollection = 'liveLocations';
  static const String walkingSessionsCollection = 'walkingSessions';
  static const String sessionEvidenceCollection = 'sessionEvidence';

  // ── Google Maps / Places API Key ──
  // Loaded from compile-time environment: --dart-define=GOOGLE_MAPS_API_KEY=...
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  // ── Feature Flags ──
  /// Evidence Vault (covert recording) is disabled by default until
  /// legal compliance for the target jurisdiction is confirmed.
  /// Enable via: --dart-define=EVIDENCE_VAULT_ENABLED=true
  static const bool evidenceVaultEnabled = bool.fromEnvironment(
    'EVIDENCE_VAULT_ENABLED',
    defaultValue: false,
  );

  // ── Live Tracking Settings ──
  static const int liveTrackingIntervalSec = 10;
  static const int liveTrackingDistanceFilterM = 15;
}
