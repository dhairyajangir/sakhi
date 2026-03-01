# SAKHI — Architecture & Workflow

> End-to-end technical architecture of the SAKHI women's safety platform.

---

## Table of Contents

- [High-Level Architecture](#high-level-architecture)
- [App Initialization Flow](#app-initialization-flow)
- [Authentication Flow](#authentication-flow)
- [State Management](#state-management)
- [Navigation & Routing](#navigation--routing)
- [Core Workflows](#core-workflows)
  - [Safety Session (SOS)](#1-safety-session-sos)
  - [Walking Buddy](#2-walking-buddy)
  - [Virtual Companion](#3-virtual-companion)
  - [Heartbeat Timer](#4-heartbeat-timer-walk-with-me)
  - [Fake Call](#5-fake-call)
  - [Duress PIN](#6-duress-pin-anti-coercion)
  - [Evidence Vault](#7-evidence-vault)
  - [Community Broadcasts](#8-community-broadcasts)
  - [Location Sharing](#9-time-bound-location-sharing)
  - [Volunteer System](#10-volunteer-system)
  - [Admin Dashboard](#11-admin-dashboard)
- [Data Flow Diagram](#data-flow-diagram)
- [Service Layer Architecture](#service-layer-architecture)
- [Firestore Schema & Relationships](#firestore-schema--relationships)
- [Security Architecture](#security-architecture)
- [Background Services](#background-services)
- [Platform-Specific Architecture](#platform-specific-architecture)

---

## High-Level Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        CLIENT (Flutter)                       │
│                                                               │
│  ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │ Screens  │→ │ Widgets  │  │ Providers│←─│ Services     │  │
│  │ (UI)     │  │ (Reuse)  │  │ (Riverpod│  │ (Business    │  │
│  │          │  │          │  │  State)  │  │  Logic)      │  │
│  └─────────┘  └──────────┘  └──────────┘  └──────┬───────┘  │
│                                                    │          │
└────────────────────────────────────────────────────┼──────────┘
                                                     │
                                            Firebase SDK
                                                     │
┌────────────────────────────────────────────────────┼──────────┐
│                     FIREBASE BACKEND               │          │
│                                                    ▼          │
│  ┌────────────┐  ┌─────────────┐  ┌────────────┐  ┌───────┐  │
│  │ Firebase   │  │ Cloud       │  │ Firebase   │  │ FCM   │  │
│  │ Auth       │  │ Firestore   │  │ Storage    │  │ Push  │  │
│  │            │  │             │  │            │  │       │  │
│  │ • Phone    │  │ • users     │  │ • profiles │  │ • SOS │  │
│  │ • Email    │  │ • sessions  │  │ • KYC docs │  │ alerts│  │
│  │            │  │ • broadcasts│  │ • evidence │  │       │  │
│  └────────────┘  └─────────────┘  └────────────┘  └───────┘  │
└───────────────────────────────────────────────────────────────┘
```

---

## App Initialization Flow

```
main()
  │
  ├─ WidgetsFlutterBinding.ensureInitialized()
  ├─ Lock portrait orientation (mobile only)
  ├─ Firebase.initializeApp()
  │   ├─ Web: explicit options from DefaultFirebaseOptions
  │   └─ Native: auto from google-services.json / GoogleService-Info.plist
  ├─ NotificationService.initialize()          ← FCM token + listeners
  ├─ HardwareTriggerService.initialize()       ← Volume-button SOS listener
  ├─ WalkWithMeService.initialize()            ← Background service prep (mobile)
  │
  └─ runApp(ProviderScope(child: SakhiApp()))
       │
       └─ MaterialApp.router
            ├─ Theme: SakhiTheme.light / .dark
            └─ Router: GoRouter → /splash (initial)
```

**Splash Screen routing logic (after 2 s animation):**

```
SplashScreen
  │
  ├─ Not authenticated → /login
  ├─ Authenticated + admin override → /admin
  ├─ Authenticated + no Firestore profile → /profile-setup
  ├─ Authenticated + role == volunteer → /volunteer
  └─ Authenticated + role == user → /home
```

---

## Authentication Flow

### Mobile (Phone OTP)

```
LoginScreen (/login)
  │
  ├─ User enters phone (+91 XXXXXXXXXX)
  │
  ├─ AuthService.verifyPhoneNumber()
  │   ├─ Firebase sends SMS OTP
  │   ├─ onCodeSent → navigate to /otp
  │   └─ onAutoVerified → auto sign-in → check profile
  │
  └─ OtpScreen (/otp)
      ├─ User enters 6-digit OTP
      ├─ AuthService.verifyOTP() → FirebaseAuth.signInWithCredential()
      ├─ Profile exists? → /home or /volunteer
      └─ No profile? → /profile-setup
```

### Web/Desktop (Admin Only)

```
EmailLoginScreen (/login on web)
  │
  ├─ User enters email + password
  ├─ AuthService.signInWithEmail()
  │   ├─ Validates against hardcoded admin credentials
  │   │   (ADMIN_EMAIL / ADMIN_PASSWORD from --dart-define)
  │   ├─ Non-admin credentials → "Access Denied" error
  │   ├─ Signs in via Firebase Auth (creates account if first time)
  │   └─ Creates Firestore admin profile if missing
  │
  └─ Routes to /admin
```

### Profile Setup (First-Time Users)

```
ProfileSetupScreen (/profile-setup)
  │
  ├─ Enter name (required)
  ├─ Pick profile photo (optional, required for volunteers)
  │   └─ Upload to Firebase Storage: profile_photos/{uid}.jpg
  ├─ Select role: "Stay Safe" (user) or "Volunteer" (volunteer)
  │
  ├─ FirestoreService.createUser() → writes to users/{uid}
  │
  ├─ Role == volunteer → /volunteer
  └─ Role == user → /home
```

---

## State Management

**Riverpod 3.x** manages all reactive state:

```
┌─────────────────────────────────────────────────┐
│                  providers.dart                   │
├─────────────────────────────────────────────────┤
│                                                   │
│  authStateProvider (StreamProvider<User?>)         │
│       │                                           │
│       ├─ isLoggedInProvider (Provider<bool>)       │
│       │                                           │
│       └─ currentUserProvider (StreamProvider)      │
│            │                                      │
│            ├─ isVolunteerProvider                  │
│            └─ isAdminProvider                      │
│                                                   │
│  activeSessionProvider (StreamProvider)            │
│  searchingSessionsProvider (StreamProvider)        │
│  emergencyContactsProvider (StreamProvider)        │
│  nearbyBroadcastsProvider (StreamProvider)         │
│  activeLocationShareProvider (StreamProvider)      │
│  walkingSessionProvider (StreamProvider)           │
│  liveLocationsProvider (StreamProvider)            │
│                                                   │
│  sessionControllerProvider (NotifierProvider)      │
│       ├─ startSession()                           │
│       ├─ endSession()                             │
│       ├─ triggerSOS()                             │
│       ├─ cancelSOS()                              │
│       └─ _startHeartbeat() / _stopHeartbeat()     │
│                                                   │
│  walkingBuddyControllerProvider (Notifier)        │
│       ├─ createWalkingSession()                   │
│       ├─ acceptSession()                          │
│       └─ confirmHandshake()                       │
│                                                   │
│  walkWithMeControllerProvider (Notifier)           │
│       ├─ startTimer()                             │
│       ├─ confirmSafe()                            │
│       └─ onExpiry() → triggerSOS                  │
└─────────────────────────────────────────────────┘
```

**Data flow:** Firestore real-time streams → Riverpod `StreamProviders` → UI rebuilds reactively.

---

## Navigation & Routing

**GoRouter** with 20+ routes:

```
/splash          → SplashScreen
/login           → LoginScreen (mobile) / EmailLoginScreen (web)
/otp             → OtpScreen
/email-login     → EmailLoginScreen
/profile-setup   → ProfileSetupScreen
/home            → HomeScreen (fade transition)
/session         → ActiveSessionScreen
/volunteer       → VolunteerDashboardScreen
/broadcast       → BroadcastScreen
/profile         → ProfileScreen
/emergency-contacts → EmergencyContactsScreen
/location-sharing   → LocationSharingScreen
/notifications   → NotificationsScreen
/admin           → AdminDashboardScreen (web/desktop only)
/fake-call       → FakeCallScreen
/virtual-companion → VirtualCompanionSetup
/active-companion  → ActiveCompanionScreen
/pin-setup       → PinSetupScreen
/camouflage      → CamouflageScreen
/walking-buddy   → WalkingBuddySetup
/walking-buddy-active → WalkingBuddyActiveView
/walk-with-me    → WalkWithMeSetupScreen
/walk-with-me-active → WalkWithMeActiveScreen
/volunteer-verification → VolunteerVerificationScreen
```

---

## Core Workflows

### 1. Safety Session (SOS)

```
User taps "Walking Buddy" on Home
  │
  ├─ SessionController.startSession(timeLimitMinutes)
  │   ├─ LocationService.getCurrentPosition()
  │   ├─ FirestoreService.createSession(status: searching)
  │   ├─ LocationService.startLocationUpdates() → writes GPS to Firestore every 15s
  │   └─ Start heartbeat timer (30s intervals → writes lastHeartbeat)
  │
  ├─ Session status: SEARCHING (orange)
  │   └─ Nearby volunteers see the request on their dashboard
  │
  ├─ Volunteer accepts → status: ACTIVE (blue)
  │   ├─ volunteerId + volunteerName written to session
  │   └─ Both users see live map with location markers
  │
  ├─ SOS Trigger (any of 3 methods):
  │   ├─ Long-press SOS button (1.5s hold)
  │   ├─ Hardware: 3 volume presses in 3s
  │   └─ Auto: heartbeat timeout (120s no response)
  │   │
  │   └─ SessionController.triggerSOS()
  │       ├─ Session status → SOS_TRIGGERED (red)
  │       ├─ FirestoreService.createBroadcast(alertType: 'Need Help')
  │       │   └─ Geo-located alert within 2km radius
  │       ├─ EvidenceService.startRecording() (if feature-flagged)
  │       └─ Duress PIN dialog appears
  │
  └─ Session end:
      ├─ User taps "End Session"
      ├─ Safe PIN entered → genuinely cancels
      └─ Timer expires naturally
          └─ LocationService.stopLocationUpdates()
          └─ Heartbeat timer cancelled
```

### 2. Walking Buddy

Full state machine with dual handshake verification:

```
User sets pickup + destination on Google Maps
  │
  ├─ WalkingBuddyController.createWalkingSession()
  │   └─ Status: SEARCHING
  │       └─ Visible to KYC-verified volunteers on dashboard
  │
  ├─ Volunteer accepts → VOLUNTEER_ACCEPTED
  │   └─ User sees match card (name, call/video/accept buttons)
  │
  ├─ User confirms → VOLUNTEER_CONFIRMED
  │   └─ Volunteer navigates to pickup location
  │
  ├─ Meetup Handshake (dual confirmation):
  │   ├─ Volunteer swipes "I've reached" → volunteerReachedConfirmedByVolunteer = true
  │   └─ User swipes "Volunteer has arrived" → volunteerReachedConfirmedByUser = true
  │       └─ Both confirmed → Status: IN_PROGRESS
  │           └─ Journey view with Google Maps directions
  │
  ├─ Destination Handshake (dual confirmation):
  │   ├─ Volunteer confirms destination reached
  │   └─ User confirms destination reached
  │       └─ Both confirmed → Status: COMPLETED
  │
  └─ Cancel at any point → Status: CANCELLED
```

### 3. Virtual Companion

```
User selects destination + duration (15/30/45/60/90 min)
  │
  ├─ Creates session with isVirtualCompanionActive = true
  ├─ ActiveCompanionScreen shows:
  │   ├─ Circular countdown ring
  │   ├─ Destination display
  │   └─ "I've Arrived Safely" button
  │
  ├─ User taps "I've Arrived Safely" → session ends normally
  │
  └─ Timer expires (00:00)
      └─ Auto-SOS triggered
          ├─ Broadcast with GPS location sent to community
          └─ Session status → SOS_TRIGGERED
```

### 4. Heartbeat Timer (Walk With Me)

```
User configures interval (10s – 60min) via slider/presets
  │
  ├─ WalkWithMeService starts background service
  │   ├─ Android: foreground service with persistent notification
  │   └─ Notification actions: "✅ I Am Safe" / "⏹ Stop"
  │
  ├─ Countdown begins with animated circular ring
  │   ├─ At ≤ 20% remaining → WARNING MODE
  │   │   ├─ Red glow animation
  │   │   ├─ Vibration pattern
  │   │   └─ High-priority notification
  │   │
  │   ├─ User taps "I Am Safe" → timer resets
  │   └─ User taps notification "I Am Safe" → timer resets (background)
  │
  └─ Timer expires (no response)
      └─ Auto-SOS broadcast with GPS location
```

### 5. Fake Call

```
User taps "Fake Call" → selects delay (5s / 15s / 1min)
  │
  ├─ Timer counts down
  │
  ├─ Incoming Call UI:
  │   ├─ Ringtone plays (flutter_ringtone_player)
  │   ├─ Vibration pattern
  │   ├─ Pulsing green indicator + caller avatar
  │   ├─ Accept / Decline buttons
  │   │
  │   ├─ Decline → call ends
  │   └─ Accept → In-Call Screen:
  │       ├─ Live call timer (MM:SS)
  │       ├─ Mute / Keypad / Speaker / Hold / Add Call buttons (cosmetic)
  │       └─ End Call → returns to previous screen
```

### 6. Duress PIN (Anti-Coercion)

```
User sets up PINs (one-time):
  ├─ Safe PIN: 4 digits → SHA-256 hash → stored in Firestore (safePinHash)
  └─ Duress PIN: 4 digits (must differ) → SHA-256 hash → stored (duressPinHash)

During active SOS:
  │
  ├─ PIN dialog appears
  │
  ├─ Safe PIN entered:
  │   ├─ Hash matches safePinHash
  │   ├─ SOS genuinely cancelled
  │   ├─ Session status → ended
  │   └─ Evidence recording stops
  │
  └─ Duress PIN entered:
      ├─ Hash matches duressPinHash
      ├─ UI shows "SOS Cancelled" (appears normal)
      ├─ BUT silently:
      │   ├─ isDuressActive = true on broadcasts
      │   ├─ Session remains in SOS state internally
      │   ├─ Location tracking continues
      │   └─ Evidence recording continues
      └─ Coercer believes danger has passed
```

### 7. Evidence Vault

```
Feature flag check: EVIDENCE_VAULT_ENABLED == true?
  │
  ├─ No → feature entirely disabled
  │
  └─ Yes → during SOS trigger:
      │
      ├─ EvidenceService.startRecording()
      │   ├─ Format: AAC-LC, 128 kbps, 44,100 Hz, mono
      │   └─ Records to temp file
      │
      ├─ On session end / SOS cancel:
      │   ├─ EvidenceService.stopRecording()
      │   ├─ Read audio file bytes
      │   ├─ Compute SHA-256 hash (crypto package)
      │   ├─ Upload to Firebase Storage: evidence/{sessionId}/audio.m4a
      │   └─ Write metadata to Firestore sessionEvidence collection:
      │       { sessionId, downloadUrl, sha256Hash, recordedAt, uploadedAt }
      │
      └─ Chain-of-custody: hash proves file wasn't tampered after upload
```

### 8. Community Broadcasts

```
User taps "Community Alert" on Home
  │
  ├─ BroadcastScreen:
  │   ├─ Select alert type: Unsafe Area / Suspicious Activity / Need Help / Road Issue
  │   ├─ Enter message (200 char limit)
  │   └─ Current GPS auto-attached
  │
  ├─ FirestoreService.createBroadcast()
  │   └─ Writes to broadcasts collection with:
  │       { alertType, message, location (GeoPoint), radiusKm: 2.0, timestamp }
  │
  └─ All users within 2km radius see the alert:
      ├─ Home screen "Nearby Alerts" feed (latest 3)
      ├─ Notifications screen (full chronological feed)
      └─ Admin dashboard live alerts table
```

### 9. Time-Bound Location Sharing

```
User taps "Share Location" → selects duration (15/30/60/120 min)
  │
  ├─ FirestoreService.createLocationShare()
  │   └─ { uid, location, createdAt, expiresAt, durationMinutes, isActive: true }
  │
  ├─ LocationService.startLiveTracking()
  │   └─ GPS updates every 10s → Firestore locationShares document updated
  │
  ├─ Active sharing card shows live countdown
  │
  ├─ User taps "Stop Sharing" → manual end
  │
  └─ Timer expires → auto-deactivate
      └─ isActive = false, location updates stop
```

### 10. Volunteer System

```
User signs up with role: "Volunteer"
  │
  ├─ VolunteerVerificationScreen:
  │   ├─ Upload government ID (front + back) from gallery
  │   │   └─ Firebase Storage: verifications/{uid}/id_front.jpg, id_back.jpg
  │   └─ Status: unverified → pending
  │
  ├─ Admin reviews in Admin Dashboard:
  │   ├─ Zoomable document viewer (0.5x – 5x)
  │   ├─ Approve → status: verified (volunteer can now accept sessions)
  │   └─ Reject → status: rejected (ID images deleted from Storage)
  │
  ├─ Verified Volunteer Dashboard:
  │   ├─ Availability toggle (online/offline)
  │   ├─ Two tabs: SOS Sessions / Walking Buddy requests
  │   ├─ Mini Google Maps with session markers + distance labels
  │   └─ Accept/Decline buttons on request cards
  │
  └─ Volunteer accepts a session:
      ├─ Session: volunteerId + volunteerName written
      ├─ Session status: searching → active
      └─ Both parties see live Google Maps with location markers
```

### 11. Admin Dashboard

```
Admin logs in on Web/Desktop → /admin
  │
  ├─ Tab 1: GOD-MODE LIVE MAP
  │   ├─ Google Maps centered on India (20.5937°N, 78.9629°E, zoom 5)
  │   ├─ Real-time markers from liveLocations collection:
  │   │   ├─ 🔴 Red = SOS active
  │   │   ├─ 🟢 Green = Volunteer on duty
  │   │   └─ 🔵 Blue = Regular user session
  │   ├─ Stats ribbon: users, volunteers, tracking, SOS count, total markers
  │   └─ Tap marker → detail panel (avatar, name, role, battery, last update)
  │
  ├─ Tab 2: LIVE ALERTS
  │   ├─ Active Sessions table (ID, status badge, creator, volunteer, duration)
  │   └─ Community Broadcasts table (type, message, user, time)
  │
  ├─ Tab 3: USER MANAGEMENT
  │   ├─ Data table: name, phone, role badge, available, verified
  │   └─ Inline role-change menu: Set User / Set Volunteer / Set Admin
  │
  └─ Tab 4: VERIFICATION REQUESTS
      ├─ Pending volunteer table: name, phone, status, submitted date
      └─ Review dialog (900×700): profile info, zoomable ID viewer, Approve/Reject
```

---

## Data Flow Diagram

```
┌───────────┐   GPS    ┌─────────────────┐  Stream   ┌──────────────┐
│ Geolocator│────────→ │ LocationService │─────────→ │ Firestore    │
│ (Device)  │          │                 │           │ (liveLocations│
└───────────┘          └─────────────────┘           │  sessions/   │
                                                      │  locationUpd)│
┌───────────┐  Events  ┌─────────────────┐  Write    └──────┬───────┘
│ Volume    │────────→ │ HardwareTrigger │─────────→        │
│ Buttons   │          │ Service         │  (SOS     ┌──────▼───────┐
└───────────┘          └─────────────────┘  Trigger) │ StreamProvider│
                                                      │ (Riverpod)   │
┌───────────┐  Record  ┌─────────────────┐  Upload   └──────┬───────┘
│ Microphone│────────→ │ EvidenceService │─────────→        │
│           │          │ (SHA-256 hash)  │  Storage  ┌──────▼───────┐
└───────────┘          └─────────────────┘           │   UI Layer   │
                                                      │  (Screens +  │
┌───────────┐  Token   ┌─────────────────┐  Push     │   Widgets)   │
│ FCM SDK   │────────→ │ NotificationSvc │─────────→ └──────────────┘
└───────────┘          └─────────────────┘
```

---

## Service Layer Architecture

Each service is a **singleton** accessed via `ServiceName.instance`:

| Service | Responsibility |
|---|---|
| `AuthService` | Firebase Auth (phone OTP + email), admin credential validation, profile check |
| `FirestoreService` | All Firestore reads/writes — users, sessions, broadcasts, location shares, walking sessions, evidence |
| `LocationService` | GPS permissions, `getCurrentPosition()`, continuous tracking with configurable distance filters |
| `NotificationService` | FCM initialization, token management, push notification handling |
| `HardwareTriggerService` | Listens to `FlutterVolumeController` stream, detects 3 rapid presses within 3s → fires SOS callback |
| `EvidenceService` | Audio recording (AAC-LC), SHA-256 hashing, Firebase Storage upload, Firestore metadata write |
| `WalkingBuddyService` | Walking session CRUD, volunteer matching, handshake state transitions |
| `WalkWithMeService` | Background service (Android foreground notification), heartbeat timer, safe/warning/expired state transitions |
| `CamouflageService` | Activity-alias switching (Android) / alternate icon (iOS) via MethodChannel |
| `SOSOverlayService` | System-alert-window floating button (Android) via MethodChannel |
| `PlatformHelper` | `isWebOrDesktop` detection for platform-gated features |

---

## Firestore Schema & Relationships

```
users (collection)
├── {uid} (document)
│   ├── uid, name, phone, role, isAvailable
│   ├── currentLocation (GeoPoint), lastHeartbeat
│   ├── safePinHash, duressPinHash (SHA-256 hashes)
│   ├── photoUrl, verificationStatus, idFrontUrl, idBackUrl
│   │
│   └── emergencyContacts (subcollection)
│       └── {contactId}: { name, phone, relationship }
│
sessions (collection)
├── {sessionId} (document)
│   ├── sessionId, createdBy, status, startTime, endTime
│   ├── volunteerId, volunteerName, timeLimit
│   ├── userLocation, destinationLocation
│   ├── isVirtualCompanionActive, estimatedArrivalTime
│   │
│   └── locationUpdates (subcollection)
│       └── {updateId}: { uid, geoPoint, timestamp }
│
walkingSessions (collection)
├── {sessionId} (document)
│   ├── sessionId, userId, userName, userPhone, status
│   ├── pickupCoords, destinationCoords, pickupName, destinationName
│   ├── volunteerId, volunteerName, volunteerPhone
│   ├── volunteerReachedConfirmedByVolunteer/User (bool)
│   ├── destinationReachedConfirmedByVolunteer/User (bool)
│   └── volunteerLocation, userCurrentLocation
│
broadcasts (collection)
├── {broadcastId}: { uid, userName, alertType, message, location, timestamp, radiusKm, isDuressActive }
│
locationShares (collection)
├── {shareId}: { uid, userName, location, createdAt, expiresAt, durationMinutes, isActive }
│
liveLocations (collection)
├── {uid}: { uid, userName, role, latitude, longitude, lastUpdatedAt, isActive, trackingReason, sessionId, batteryLevel }
│
sessionEvidence (collection)
└── {evidenceId}: { sessionId, downloadUrl, sha256Hash, recordedAt, uploadedAt }
```

---

## Security Architecture

### Authentication Layers

```
Mobile Users:
  Phone OTP → Firebase Auth → Firestore user profile → role-based access

Admin (Web/Desktop):
  Hardcoded credentials (--dart-define) → validated locally →
  Firebase Auth sign-in → Firestore admin profile → full access
```

### Firestore Security Rules

| Collection | Read | Write | Special |
|---|---|---|---|
| `users` | Any authenticated | Owner create; owner + admin update | PIN hashes never exposed in queries |
| `emergencyContacts` | Owner + admin | Owner only | Subcollection of users |
| `sessions` | Any authenticated | Creator create; creator + volunteer + admin update | Volunteer can only accept `searching` sessions |
| `walkingSessions` | Participants + admin | Creator create; state machine transitions enforced | KYC verification required for volunteer acceptance |
| `broadcasts` | Any authenticated | Creator create; admin update/delete | UID must match on create |
| `locationShares` | Any authenticated | Owner create/update; admin update | — |
| `liveLocations` | Owner + admin | Owner only | Ephemeral documents |

### Data Protection

- **PINs:** stored as SHA-256 hashes only — never plaintext
- **KYC images:** Firebase Storage server-side encryption at rest + TLS in transit
- **Evidence recordings:** SHA-256 hash for tamper-proofing / chain-of-custody
- **Transport:** all data over HTTPS/TLS (Firebase SDK default)

---

## Background Services

### Android Foreground Service (Heartbeat Timer)

```
WalkWithMeService
  │
  ├─ flutter_background_service → persistent notification
  │   ├─ Notification channel: "Walk With Me"
  │   ├─ Actions: "✅ I Am Safe" / "⏹ Stop"
  │   └─ Keeps process alive during screen-off
  │
  ├─ Timer loop:
  │   ├─ Countdown tick every second
  │   ├─ At ≤ 20% → warning mode (vibration + red notification)
  │   ├─ "I Am Safe" action → reset timer
  │   └─ Expiry → SOS broadcast + stop service
  │
  └─ wakelock_plus → screen stays on during active timer (in-app)
```

### Location Tracking (Sessions)

```
LocationService.startLocationUpdates()
  │
  ├─ Geolocator.getPositionStream(locationSettings)
  │   ├─ Regular: distanceFilter 10m
  │   ├─ Live tracking: distanceFilter 15m, interval 10s
  │   └─ Walking buddy: distanceFilter 5m, interval 5s
  │
  ├─ Each position → Firestore write:
  │   ├─ sessions/{id}/locationUpdates → GPS history
  │   └─ liveLocations/{uid} → real-time marker for admin map
  │
  └─ Android: foreground notification during tracking
```

### Hardware SOS Listener

```
HardwareTriggerService
  │
  ├─ FlutterVolumeController.addListener()
  │   └─ Listens to system volume change events
  │
  ├─ Detection logic:
  │   ├─ Track timestamps of volume-button presses
  │   ├─ If ≥ 3 presses in same direction within 3 seconds → trigger
  │   └─ 10-second cooldown between triggers
  │
  └─ On trigger → SessionController.triggerSOS()
```

---

## Platform-Specific Architecture

| Feature | Android | iOS | Web/Desktop |
|---|---|---|---|
| **SOS Overlay** | `SYSTEM_ALERT_WINDOW` + MethodChannel | Not available (OS restriction) | N/A |
| **Camouflage** | Activity-alias toggling via MethodChannel | `setAlternateIconName` | N/A |
| **Background Timer** | Foreground service + notification actions | Background activity indicator | N/A |
| **Hardware SOS** | Volume button listener | Volume button listener | N/A |
| **Phone OTP** | Full support | Full support | Not available |
| **Admin Dashboard** | N/A (hidden) | N/A (hidden) | Full support |
| **Google Maps** | Maps SDK for Android | Maps SDK for iOS | Maps JavaScript API |
| **Fake Call** | Full dialer UI + ringtone + vibration | Full dialer UI + ringtone | N/A |

---

## Configuration Constants

Defined in `lib/config/constants.dart`:

| Parameter | Value | Usage |
|---|---|---|
| `locationUpdateIntervalSec` | 15 s | GPS write frequency during sessions |
| `heartbeatIntervalSec` | 30 s | Heartbeat write to Firestore |
| `heartbeatTimeoutSec` | 120 s | Auto-SOS if no heartbeat |
| `sessionSearchTimeoutMin` | 5 min | Max wait for volunteer match |
| `defaultSessionDurationMin` | 30 min | Default session length |
| `broadcastRadiusKm` | 2.0 km | Community alert visibility radius |
| `volunteerSearchRadiusKm` | 5.0 km | Volunteer matching radius |
| `liveTrackingIntervalSec` | 10 s | Admin map update frequency |
| `liveTrackingDistanceFilterM` | 15 m | Minimum distance for live update |

---

*SAKHI — सखी — Architecture Document · v1.0.0*
