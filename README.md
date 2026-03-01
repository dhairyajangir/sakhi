# SAKHI — सखी — Your Trusted Companion

> A cross-platform **women's safety app** built with **Flutter & Firebase** — real-time monitoring, volunteer assistance, covert SOS triggers, and anti-coercion safeguards.

---

## Table of Contents

- [Features](#features)
- [Tech Stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Running the App](#running-the-app)
- [Admin Access](#admin-access)
- [Project Structure](#project-structure)
- [Firestore Data Model](#firestore-data-model)
- [Security Rules](#security-rules)
- [Platform Support](#platform-support)
- [Environment Variables](#environment-variables)
- [User Roles](#user-roles)
- [Screens Overview](#screens-overview)
- [License](#license)

---

## Features

| Feature | Description |
|---|---|
| **Multi-Mode SOS** | Long-press button (1.5 s hold), hardware trigger (3 volume-button presses in 3 s), auto-SOS on timer expiry |
| **Walking Buddy** | Request a KYC-verified volunteer companion with real-time Google Maps tracking & dual handshake verification |
| **Virtual Companion** | Set destination + timer (15–90 min); auto-SOS if you don't confirm arrival |
| **Heartbeat Timer** | Configurable check-in interval (10 s – 60 min); auto-SOS on missed heartbeat with background service |
| **Fake Call** | Realistic incoming call simulation (5 s / 15 s / 1 min delay) with dialer UI, ringtone & call timer |
| **Duress PIN** | Safe PIN genuinely cancels SOS; Duress PIN *appears* to cancel but silently escalates — anti-coercion |
| **Evidence Vault** | Covert audio recording during SOS, SHA-256 hashed, uploaded to Firebase Storage *(disabled by default)* |
| **Community Broadcasts** | Geo-located safety alerts within 2 km radius (Unsafe Area, Suspicious Activity, Need Help, Road Issue) |
| **Location Sharing** | Time-bound live GPS sharing (15 min – 2 hrs) with auto-expiry |
| **Emergency Contacts** | CRUD management of trusted contacts stored in Firestore |
| **Volunteer System** | Role-based onboarding, KYC ID verification, availability toggle, live dashboard |
| **Camouflage Mode** | Disguise app icon as Calculator, Calendar, Notes, etc. |
| **Admin Dashboard** | Web-only god-mode live map, alerts table, user management, KYC approval/rejection |
| **SOS Overlay** | Floating draggable SOS button on top of all apps (Android) |

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart ^3.11.0) |
| State Management | Riverpod 3.x |
| Navigation | GoRouter |
| Backend | Firebase Auth · Firestore · Cloud Messaging · Storage |
| Maps & Location | Google Maps Flutter + Geolocator |
| Audio | `record` (AAC-LC via platform codecs) |
| Crypto | `crypto` (SHA-256 hashing) |
| Background | `flutter_background_service` (Android foreground service) |

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Flutter SDK | ^3.11.0 | [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install) |
| Dart SDK | ^3.11.0 | Bundled with Flutter |
| Firebase CLI | latest | `npm install -g firebase-tools` |
| FlutterFire CLI | latest | `dart pub global activate flutterfire_cli` |
| Android Studio / Xcode | latest | For emulators & build tools |
| Google Maps API Key | — | [console.cloud.google.com](https://console.cloud.google.com/apis/credentials) |

**Verify Flutter is ready:**

```bash
flutter doctor
```

---

## Initial Setup

### 1. Clone & install dependencies

```bash
git clone https://github.com/dhairyajangir/SAKHI.git
cd SAKHI
flutter pub get
```

### 2. Firebase project

1. Create a project at [console.firebase.google.com](https://console.firebase.google.com)
2. **Add Android app** (`com.example.sakhi`) → download `google-services.json` → place at `android/app/google-services.json`
3. **Add iOS app** (`com.example.sakhi`) → download `GoogleService-Info.plist` → place at `ios/Runner/GoogleService-Info.plist`
4. Enable these services in Firebase Console:
   - **Authentication** → Enable **Phone** provider + **Email/Password** provider
   - **Cloud Firestore** → Create database (choose region, start in test mode)
   - **Firebase Storage** → Enable
   - **Cloud Messaging** → Enabled by default

### 3. Generate Firebase config

```bash
flutterfire configure
```

This auto-generates `lib/firebase_options.dart`.

### 4. Deploy Firestore rules & indexes

```bash
firebase login
firebase deploy --only firestore
```

### 5. Android SHA fingerprints (required for Phone Auth)

```bash
cd android
./gradlew signingReport
```

Add SHA-1 and SHA-256 in **Firebase Console → Project Settings → Android App**.

### 6. Google Maps API key

Enable **Maps SDK for Android** and **Maps SDK for iOS** in Google Cloud Console, then:

- **Android:** set key in `android/app/src/main/AndroidManifest.xml` → `com.google.android.geo.API_KEY`
- **iOS:** set key in `ios/Runner/AppDelegate.swift` → `GMSServices.provideAPIKey("KEY")`

---

## Running the App

### Android (emulator or device)

```bash
flutter run
```

### Web (Admin Dashboard)

```bash
flutter run -d chrome
```

### With environment variables (PowerShell)

```powershell
flutter run `
  --dart-define=ADMIN_EMAIL=admin@sakhi.com `
  --dart-define=ADMIN_PASSWORD=Admin@123 `
  --dart-define=GOOGLE_MAPS_API_KEY=YOUR_KEY `
  --dart-define=EVIDENCE_VAULT_ENABLED=false
```

### With environment variables (Bash)

```bash
flutter run \
  --dart-define=ADMIN_EMAIL=admin@sakhi.com \
  --dart-define=ADMIN_PASSWORD=Admin@123 \
  --dart-define=GOOGLE_MAPS_API_KEY=YOUR_KEY \
  --dart-define=EVIDENCE_VAULT_ENABLED=false
```

### Convenience scripts (Windows)

| Script | Target |
|---|---|
| `.\run.ps1` | Android emulator |
| `.\run-device.ps1` | Physical Android device |
| `.\run-web.ps1` | Chrome (Admin Dashboard) |

---

## Admin Access

The **Admin Dashboard** is accessible only on **Web / Windows / macOS / Linux**.

### Default credentials

| Field | Value |
|---|---|
| **Email** | `admin@sakhi.com` |
| **Password** | `Admin@123` |

Override via compile-time flags:

```bash
--dart-define=ADMIN_EMAIL=your_admin@email.com
--dart-define=ADMIN_PASSWORD=YourSecurePassword
```

### How it works

1. Open the app on Web/Desktop → **Admin Login** panel appears
2. Enter admin email & password → routes to `/admin`
3. If the admin account doesn't exist in Firebase Auth, it's **auto-created** on first login
4. A Firestore user profile with `role: admin` is created automatically

### Admin capabilities

| Feature | Description |
|---|---|
| **God-Mode Live Map** | All active users, volunteers, SOS markers — color-coded in real time |
| **Live Alerts** | Active sessions & community broadcasts data tables |
| **User Management** | View users, change roles (user ↔ volunteer ↔ admin) |
| **KYC Verification** | Review volunteer ID submissions — approve or reject with zoomable document viewer |

---

## Project Structure

```
lib/
├── main.dart                    # App entry + Firebase init
├── firebase_options.dart        # Auto-generated Firebase config
├── config/
│   ├── constants.dart           # App-wide constants, collection names, feature flags
│   ├── router.dart              # GoRouter (20+ routes)
│   └── theme.dart               # Material 3 light/dark themes
├── models/
│   ├── user_model.dart          # User profile, roles, PIN hashes, KYC status
│   ├── session_model.dart       # Safety session state machine
│   ├── walking_session_model.dart # Walking buddy session
│   ├── broadcast_model.dart     # Community safety alert
│   ├── emergency_contact.dart   # Emergency contact
│   ├── location_update.dart     # GPS coordinate update
│   └── live_location_model.dart # Real-time tracker (admin map)
├── services/
│   ├── auth_service.dart        # Phone OTP + Email auth + admin override
│   ├── firestore_service.dart   # All Firestore CRUD operations
│   ├── location_service.dart    # GPS tracking + live Firestore writes
│   ├── notification_service.dart # FCM push notifications
│   ├── hardware_trigger_service.dart # Volume-button SOS detection
│   ├── evidence_service.dart    # Covert audio recording + SHA-256 + upload
│   ├── walking_buddy_service.dart # Walking buddy matching logic
│   ├── walk_with_me_service.dart  # Background heartbeat service
│   ├── camouflage_service.dart  # App icon disguise
│   ├── sos_overlay_service.dart # Floating SOS overlay (Android)
│   └── platform_helper.dart     # Web/desktop platform detection
├── providers/
│   └── providers.dart           # Riverpod providers + SessionController
├── widgets/
│   ├── sos_button.dart          # Animated long-press SOS with pulse ring
│   ├── session_status_card.dart # Color-coded session status card
│   └── animated_gradient_bg.dart # Gradient animation (splash)
└── screens/
    ├── splash_screen.dart       # Animated splash + role-based routing
    ├── auth/                    # Login, OTP, Email Login, Profile Setup
    ├── home/                    # Home Dashboard with quick actions
    ├── session/                 # Active Session, Volunteer Dashboard
    ├── safety_tools/            # Fake Call, Virtual Companion, Walking Buddy,
    │                            #   Heartbeat Timer, PIN Setup, Camouflage
    ├── broadcast/               # Community Alert form
    ├── contacts/                # Emergency Contacts CRUD
    ├── location/                # Location Sharing
    ├── notifications/           # Broadcast Feed
    ├── profile/                 # Profile, Volunteer KYC Verification
    └── admin/                   # Admin Dashboard (web/desktop only)
```

---

## Firestore Data Model

| Collection | Purpose |
|---|---|
| `users` | Profile, role, availability, PIN hashes, KYC status, photo URL |
| `users/{uid}/emergencyContacts` | Trusted emergency contacts |
| `sessions` | Safety sessions — status, timer, volunteer matching, SOS state |
| `sessions/{id}/locationUpdates` | GPS coordinate history for active sessions |
| `broadcasts` | Community safety alerts (geo-located, 2 km radius) |
| `locationShares` | Time-bound location sharing with auto-expiry |
| `liveLocations` | Real-time tracker data for admin map |
| `walkingSessions` | Walking Buddy — pickup, destination, handshake state machine |
| `sessionEvidence` | Audio recordings + SHA-256 hashes *(feature-flagged)* |

---

## Security Rules

- **Users:** authenticated can read; owner creates; owner + admin can update
- **Sessions:** authenticated can read; creator creates; creator/volunteer/admin update
- **Broadcasts:** authenticated can read/create; admin can update/delete
- **Location Shares:** owner CRUD; admin can update
- **Walking Sessions:** participants + admin can read; KYC-verified volunteers required

Full rules → [`firestore.rules`](firestore.rules) · Indexes → [`firestore.indexes.json`](firestore.indexes.json)

---

## Platform Support

| Platform | Scope |
|---|---|
| **Android** | Full app — all features including floating SOS overlay & camouflage icons |
| **iOS** | Full app — all features except floating SOS overlay |
| **Web** | Admin dashboard only |
| **Windows / macOS / Linux** | Admin dashboard only |

---

## Environment Variables

All passed via `--dart-define` at build/run time:

| Variable | Default | Description |
|---|---|---|
| `ADMIN_EMAIL` | `admin@sakhi.com` | Admin login email (web/desktop) |
| `ADMIN_PASSWORD` | `Admin@123` | Admin login password |
| `GOOGLE_MAPS_API_KEY` | *(empty)* | Google Maps API key |
| `EVIDENCE_VAULT_ENABLED` | `false` | Enable covert audio recording during SOS |

---

## User Roles

| Role | Access |
|---|---|
| **User** | All safety tools, sessions, community features, location sharing |
| **Volunteer** | Volunteer dashboard, accept SOS & walking buddy requests (KYC required) |
| **Admin** | Web dashboard, god-mode map, user management, role changes, KYC approval |

**Verification flow:** Unverified → Pending → Verified / Rejected

---

## Screens Overview

| Category | Screens |
|---|---|
| **Auth** | Splash, Phone Login, OTP Verification, Email Login, Profile Setup |
| **Core** | Home Dashboard, Active Session, Volunteer Dashboard, Profile, Notifications |
| **Safety Tools** | Fake Call, Virtual Companion, Walking Buddy, Heartbeat Timer, Duress PIN Setup, Camouflage |
| **Management** | Emergency Contacts, Location Sharing, Community Broadcast |
| **Admin** | Admin Dashboard (Live Map, Alerts, User Management, KYC Review) |
| **Verification** | Volunteer KYC (ID Upload) |

---

## License

Built for hackathon purposes.

---

*SAKHI — सखी — Your Trusted Companion · Built with Flutter & Firebase*
