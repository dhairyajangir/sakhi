import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../config/constants.dart';
import '../models/walking_session_model.dart';

/// Service that manages all Firestore state transitions for the Walking Buddy
/// feature. Follows the singleton pattern consistent with the rest of the app.
class WalkingBuddyService {
  WalkingBuddyService._();
  static final WalkingBuddyService instance = WalkingBuddyService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(AppConstants.walkingSessionsCollection);

  // ─────────────────────────────────────────────────────────────────────
  // CREATE
  // ─────────────────────────────────────────────────────────────────────

  /// Create a new walking session (Phase 1).
  Future<WalkingSessionModel> createSession({
    required String userId,
    String? userName,
    String? userPhone,
    required GeoPoint pickupCoords,
    required GeoPoint destinationCoords,
    String? pickupName,
    String? destinationName,
  }) async {
    final sessionId = _uuid.v4();
    final now = DateTime.now();

    final session = WalkingSessionModel(
      sessionId: sessionId,
      userId: userId,
      userName: userName,
      userPhone: userPhone,
      status: WalkingSessionStatus.searching,
      pickupCoords: pickupCoords,
      destinationCoords: destinationCoords,
      pickupName: pickupName,
      destinationName: destinationName,
      createdAt: now,
      lastUpdate: now,
      userCurrentLocation: pickupCoords,
    );

    await _col.doc(sessionId).set(session.toJson());
    debugPrint('[WalkingBuddyService] Session created: $sessionId');
    return session;
  }

  // ─────────────────────────────────────────────────────────────────────
  // STREAMS
  // ─────────────────────────────────────────────────────────────────────

  /// Stream all sessions with `status == searching` (for volunteer dashboard).
  Stream<List<WalkingSessionModel>> searchingSessionsStream() {
    return _col
        .where('status', isEqualTo: WalkingSessionStatus.searching.name)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => WalkingSessionModel.fromJson(doc.data()))
            .toList());
  }

  /// Stream a single session by ID.
  Stream<WalkingSessionModel?> sessionStream(String sessionId) {
    return _col.doc(sessionId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return WalkingSessionModel.fromJson(doc.data()!);
    });
  }

  /// Stream the active walking session for a user (as creator or volunteer).
  Stream<WalkingSessionModel?> activeSessionForUser(String uid) {
    // Sessions created by the user
    final creatorStream = _col
        .where('userId', isEqualTo: uid)
        .where('status', whereNotIn: [
          WalkingSessionStatus.completed.name,
          WalkingSessionStatus.cancelled.name,
        ])
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
          if (snap.docs.isEmpty) return null;
          return WalkingSessionModel.fromJson(snap.docs.first.data());
        });

    // Sessions where user is the volunteer
    final volunteerStream = _col
        .where('volunteerId', isEqualTo: uid)
        .where('status', whereNotIn: [
          WalkingSessionStatus.completed.name,
          WalkingSessionStatus.cancelled.name,
        ])
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
          if (snap.docs.isEmpty) return null;
          return WalkingSessionModel.fromJson(snap.docs.first.data());
        });

    // Combine – prefer the more recently-created one
    return creatorStream.asyncExpand((creatorSession) {
      return volunteerStream.map((volunteerSession) {
        if (creatorSession == null) return volunteerSession;
        if (volunteerSession == null) return creatorSession;
        return creatorSession.createdAt.isAfter(volunteerSession.createdAt)
            ? creatorSession
            : volunteerSession;
      });
    });
  }

  // ─────────────────────────────────────────────────────────────────────
  // STATE TRANSITIONS (Phase 2 – Volunteer Dispatch)
  // ─────────────────────────────────────────────────────────────────────

  /// Volunteer clicks "Accept" — status → volunteerAccepted.
  /// Uses a transaction to prevent two volunteers from accepting simultaneously.
  Future<void> volunteerAccept({
    required String sessionId,
    required String volunteerId,
    required String volunteerName,
    String? volunteerPhone,
  }) async {
    final docRef = _col.doc(sessionId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) throw Exception('Session not found');
      final status = snap.data()?['status'] as String?;
      if (status != WalkingSessionStatus.searching.name) {
        throw Exception('Session is no longer searching (current: $status)');
      }
      tx.update(docRef, {
        'status': WalkingSessionStatus.volunteerAccepted.name,
        'volunteerId': volunteerId,
        'volunteerName': volunteerName,
        'volunteerPhone': volunteerPhone,
        'lastUpdate': FieldValue.serverTimestamp(),
      });
    });
    debugPrint('[WalkingBuddyService] Volunteer $volunteerId accepted $sessionId');
  }

  /// User clicks "Accept Volunteer" — status → volunteerConfirmed.
  Future<void> userConfirmVolunteer(String sessionId) async {
    await _col.doc(sessionId).update({
      'status': WalkingSessionStatus.volunteerConfirmed.name,
      'lastUpdate': FieldValue.serverTimestamp(),
    });
    debugPrint('[WalkingBuddyService] User confirmed volunteer for $sessionId');
  }

  // ─────────────────────────────────────────────────────────────────────
  // STATE TRANSITIONS (Phase 3 – Meetup Handshake)
  // ─────────────────────────────────────────────────────────────────────

  /// Volunteer swipes "I have reached the user."
  /// Uses a transaction for atomic read-modify-write.
  Future<void> volunteerConfirmsArrival(String sessionId) async {
    final docRef = _col.doc(sessionId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final data = snap.data();
      if (data == null) return;

      final userAlsoConfirmed =
          data['volunteerReachedConfirmedByUser'] as bool? ?? false;

      final updates = <String, dynamic>{
        'volunteerReachedConfirmedByVolunteer': true,
        'lastUpdate': FieldValue.serverTimestamp(),
      };

      // If BOTH have confirmed → inProgress
      if (userAlsoConfirmed) {
        updates['status'] = WalkingSessionStatus.inProgress.name;
      } else {
        updates['status'] = WalkingSessionStatus.volunteerReached.name;
      }

      tx.update(docRef, updates);
    });
    debugPrint('[WalkingBuddyService] Volunteer confirms arrival: $sessionId');
  }

  /// User swipes "Volunteer has arrived."
  /// Uses a transaction for atomic read-modify-write.
  Future<void> userConfirmsVolunteerArrival(String sessionId) async {
    final docRef = _col.doc(sessionId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final data = snap.data();
      if (data == null) return;

      final volunteerAlsoConfirmed =
          data['volunteerReachedConfirmedByVolunteer'] as bool? ?? false;

      final updates = <String, dynamic>{
        'volunteerReachedConfirmedByUser': true,
        'lastUpdate': FieldValue.serverTimestamp(),
      };

      // If BOTH have confirmed → inProgress
      if (volunteerAlsoConfirmed) {
        updates['status'] = WalkingSessionStatus.inProgress.name;
      } else {
        updates['status'] = WalkingSessionStatus.volunteerReached.name;
      }

      tx.update(docRef, updates);
    });
    debugPrint('[WalkingBuddyService] User confirms volunteer arrival: $sessionId');
  }

  // ─────────────────────────────────────────────────────────────────────
  // STATE TRANSITIONS (Phase 4 – Destination Reached)
  // ─────────────────────────────────────────────────────────────────────

  /// User swipes "Reached Destination."
  /// Uses a transaction for atomic read-modify-write.
  Future<void> userConfirmsDestination(String sessionId) async {
    final docRef = _col.doc(sessionId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final data = snap.data();
      if (data == null) return;

      final volunteerAlso =
          data['destinationReachedConfirmedByVolunteer'] as bool? ?? false;

      final updates = <String, dynamic>{
        'destinationReachedConfirmedByUser': true,
        'lastUpdate': FieldValue.serverTimestamp(),
      };

      if (volunteerAlso) {
        updates['status'] = WalkingSessionStatus.completed.name;
      }

      tx.update(docRef, updates);
    });
    debugPrint('[WalkingBuddyService] User confirms destination: $sessionId');
  }

  /// Volunteer swipes "Reached Destination."
  /// Uses a transaction for atomic read-modify-write.
  Future<void> volunteerConfirmsDestination(String sessionId) async {
    final docRef = _col.doc(sessionId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final data = snap.data();
      if (data == null) return;

      final userAlso =
          data['destinationReachedConfirmedByUser'] as bool? ?? false;

      final updates = <String, dynamic>{
        'destinationReachedConfirmedByVolunteer': true,
        'lastUpdate': FieldValue.serverTimestamp(),
      };

      if (userAlso) {
        updates['status'] = WalkingSessionStatus.completed.name;
      }

      tx.update(docRef, updates);
    });
    debugPrint('[WalkingBuddyService] Volunteer confirms destination: $sessionId');
  }

  // ─────────────────────────────────────────────────────────────────────
  // LOCATION UPDATES
  // ─────────────────────────────────────────────────────────────────────

  /// Update the user's current location on the session document.
  Future<void> updateUserLocation(
      String sessionId, GeoPoint location) async {
    await _col.doc(sessionId).update({
      'userCurrentLocation': location,
      'lastUpdate': FieldValue.serverTimestamp(),
    });
  }

  /// Update the volunteer's current location on the session document.
  Future<void> updateVolunteerLocation(
      String sessionId, GeoPoint location) async {
    await _col.doc(sessionId).update({
      'volunteerLocation': location,
      'lastUpdate': FieldValue.serverTimestamp(),
    });
  }

  // ─────────────────────────────────────────────────────────────────────
  // CANCEL
  // ─────────────────────────────────────────────────────────────────────

  /// Cancel a walking session.
  /// Uses a transaction to guard against cancelling completed sessions.
  Future<void> cancelSession(String sessionId) async {
    final docRef = _col.doc(sessionId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final status = snap.data()?['status'] as String?;
      if (status == WalkingSessionStatus.completed.name ||
          status == WalkingSessionStatus.cancelled.name) {
        return; // already terminal — no-op
      }
      tx.update(docRef, {
        'status': WalkingSessionStatus.cancelled.name,
        'lastUpdate': FieldValue.serverTimestamp(),
      });
    });
    debugPrint('[WalkingBuddyService] Session cancelled: $sessionId');
  }
}
