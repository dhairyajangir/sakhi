import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { user, volunteer, admin }

/// KYC verification status for volunteers.
enum VerificationStatus { unverified, pending, verified, rejected }

class UserModel {
  final String uid;
  final String name;
  final String phone;
  final UserRole role;
  final bool isAvailable;
  final GeoPoint? currentLocation;
  final DateTime? lastHeartbeat;
  final bool verifiedStatus;

  // ── Duress PIN fields (stored as hashes, never plaintext) ──
  final String? safePinHash;
  final String? duressPinHash;

  // ── Profile picture ──
  final String? photoUrl;

  // ── KYC verification ──
  final VerificationStatus verificationStatus;
  final String? idFrontUrl;
  final String? idBackUrl;
  final DateTime? verificationSubmittedAt;

  const UserModel({
    required this.uid,
    required this.name,
    required this.phone,
    this.role = UserRole.user,
    this.isAvailable = false,
    this.currentLocation,
    this.lastHeartbeat,
    this.verifiedStatus = false,
    this.safePinHash,
    this.duressPinHash,
    this.photoUrl,
    this.verificationStatus = VerificationStatus.unverified,
    this.idFrontUrl,
    this.idBackUrl,
    this.verificationSubmittedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      uid: json['uid'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String? ?? '',
      role: _parseRole(json['role'] as String?),
      isAvailable: json['isAvailable'] as bool? ?? false,
      currentLocation: json['currentLocation'] as GeoPoint?,
      lastHeartbeat: json['lastHeartbeat'] != null
          ? (json['lastHeartbeat'] as Timestamp).toDate()
          : null,
      verifiedStatus: json['verifiedStatus'] as bool? ?? false,
      safePinHash: json['safePinHash'] as String? ?? json['safePin'] as String?,
      duressPinHash: json['duressPinHash'] as String? ?? json['duressPin'] as String?,
      photoUrl: json['photoUrl'] as String?,
      verificationStatus: _parseVerificationStatus(
        json['verificationStatus'] as String?,
      ),
      idFrontUrl: json['idFrontUrl'] as String?,
      idBackUrl: json['idBackUrl'] as String?,
      verificationSubmittedAt: json['verificationSubmittedAt'] != null
          ? (json['verificationSubmittedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'name': name,
    'phone': phone,
    'role': role.name,
    'isAvailable': isAvailable,
    'currentLocation': currentLocation,
    'lastHeartbeat': lastHeartbeat != null
        ? Timestamp.fromDate(lastHeartbeat!)
        : null,
    'verifiedStatus': verifiedStatus,
    'safePinHash': safePinHash,
    'duressPinHash': duressPinHash,
    'photoUrl': photoUrl,
    'verificationStatus': verificationStatus.name,
    'idFrontUrl': idFrontUrl,
    'idBackUrl': idBackUrl,
    'verificationSubmittedAt': verificationSubmittedAt != null
        ? Timestamp.fromDate(verificationSubmittedAt!)
        : null,
  };

  static UserRole _parseRole(String? value) {
    switch (value) {
      case 'volunteer':
        return UserRole.volunteer;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.user;
    }
  }

  static VerificationStatus _parseVerificationStatus(String? value) {
    switch (value) {
      case 'pending':
        return VerificationStatus.pending;
      case 'verified':
        return VerificationStatus.verified;
      case 'rejected':
        return VerificationStatus.rejected;
      default:
        return VerificationStatus.unverified;
    }
  }

  UserModel copyWith({
    String? uid,
    String? name,
    String? phone,
    UserRole? role,
    bool? isAvailable,
    GeoPoint? currentLocation,
    DateTime? lastHeartbeat,
    bool? verifiedStatus,
    String? safePinHash,
    String? duressPinHash,
    String? photoUrl,
    VerificationStatus? verificationStatus,
    String? idFrontUrl,
    String? idBackUrl,
    DateTime? verificationSubmittedAt,
    bool clearSafePin = false,
    bool clearDuressPin = false,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      isAvailable: isAvailable ?? this.isAvailable,
      currentLocation: currentLocation ?? this.currentLocation,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
      verifiedStatus: verifiedStatus ?? this.verifiedStatus,
      safePinHash: clearSafePin ? null : (safePinHash ?? this.safePinHash),
      duressPinHash: clearDuressPin ? null : (duressPinHash ?? this.duressPinHash),
      photoUrl: photoUrl ?? this.photoUrl,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      idFrontUrl: idFrontUrl ?? this.idFrontUrl,
      idBackUrl: idBackUrl ?? this.idBackUrl,
      verificationSubmittedAt: verificationSubmittedAt ?? this.verificationSubmittedAt,
    );
  }

  /// Whether the user has configured both PINs for duress cancellation.
  /// Requires both PINs to be non-null, exactly 4 digits, numeric-only,
  /// and different from each other.
  bool get hasDuressPinSetup {
    return safePinHash != null &&
        safePinHash!.isNotEmpty &&
        duressPinHash != null &&
        duressPinHash!.isNotEmpty &&
        safePinHash != duressPinHash;
  }
}
