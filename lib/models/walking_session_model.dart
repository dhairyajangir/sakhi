import 'package:cloud_firestore/cloud_firestore.dart';

/// State machine for the Walking Buddy feature.
/// Flow: searching → pendingVolunteer → volunteerAccepted → volunteerConfirmed
///       → volunteerReached → inProgress → completed
enum WalkingSessionStatus {
  searching,
  pendingVolunteer,
  volunteerAccepted,
  volunteerConfirmed,
  volunteerReached,
  inProgress,
  completed,
  cancelled,
}

class WalkingSessionModel {
  final String sessionId;
  final String userId;
  final String? userName;
  final String? userPhone;
  final WalkingSessionStatus status;
  final GeoPoint pickupCoords;
  final GeoPoint destinationCoords;
  final String? destinationName;
  final String? pickupName;
  final DateTime createdAt;
  final DateTime lastUpdate;

  // Volunteer info
  final String? volunteerId;
  final String? volunteerName;
  final String? volunteerPhone;

  // Handshake flags
  final bool volunteerReachedConfirmedByVolunteer;
  final bool volunteerReachedConfirmedByUser;
  final bool destinationReachedConfirmedByVolunteer;
  final bool destinationReachedConfirmedByUser;

  // Location tracking
  final GeoPoint? volunteerLocation;
  final GeoPoint? userCurrentLocation;

  const WalkingSessionModel({
    required this.sessionId,
    required this.userId,
    this.userName,
    this.userPhone,
    required this.status,
    required this.pickupCoords,
    required this.destinationCoords,
    this.destinationName,
    this.pickupName,
    required this.createdAt,
    required this.lastUpdate,
    this.volunteerId,
    this.volunteerName,
    this.volunteerPhone,
    this.volunteerReachedConfirmedByVolunteer = false,
    this.volunteerReachedConfirmedByUser = false,
    this.destinationReachedConfirmedByVolunteer = false,
    this.destinationReachedConfirmedByUser = false,
    this.volunteerLocation,
    this.userCurrentLocation,
  });

  factory WalkingSessionModel.fromJson(Map<String, dynamic> json) {
    return WalkingSessionModel(
      sessionId: json['sessionId'] as String,
      userId: json['userId'] as String,
      userName: json['userName'] as String?,
      userPhone: json['userPhone'] as String?,
      status: _parseStatus(json['status'] as String?),
      pickupCoords: json['pickupCoords'] as GeoPoint,
      destinationCoords: json['destinationCoords'] as GeoPoint,
      destinationName: json['destinationName'] as String?,
      pickupName: json['pickupName'] as String?,
      createdAt: _parseTimestamp(json['createdAt']),
      lastUpdate: _parseTimestamp(json['lastUpdate']),
      volunteerId: json['volunteerId'] as String?,
      volunteerName: json['volunteerName'] as String?,
      volunteerPhone: json['volunteerPhone'] as String?,
      volunteerReachedConfirmedByVolunteer:
          json['volunteerReachedConfirmedByVolunteer'] as bool? ?? false,
      volunteerReachedConfirmedByUser:
          json['volunteerReachedConfirmedByUser'] as bool? ?? false,
      destinationReachedConfirmedByVolunteer:
          json['destinationReachedConfirmedByVolunteer'] as bool? ?? false,
      destinationReachedConfirmedByUser:
          json['destinationReachedConfirmedByUser'] as bool? ?? false,
      volunteerLocation: json['volunteerLocation'] as GeoPoint?,
      userCurrentLocation: json['userCurrentLocation'] as GeoPoint?,
    );
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'userId': userId,
        'userName': userName,
        'userPhone': userPhone,
        'status': status.name,
        'pickupCoords': pickupCoords,
        'destinationCoords': destinationCoords,
        'destinationName': destinationName,
        'pickupName': pickupName,
        'createdAt': Timestamp.fromDate(createdAt),
        'lastUpdate': Timestamp.fromDate(lastUpdate),
        'volunteerId': volunteerId,
        'volunteerName': volunteerName,
        'volunteerPhone': volunteerPhone,
        'volunteerReachedConfirmedByVolunteer':
            volunteerReachedConfirmedByVolunteer,
        'volunteerReachedConfirmedByUser': volunteerReachedConfirmedByUser,
        'destinationReachedConfirmedByVolunteer':
            destinationReachedConfirmedByVolunteer,
        'destinationReachedConfirmedByUser': destinationReachedConfirmedByUser,
        'volunteerLocation': volunteerLocation,
        'userCurrentLocation': userCurrentLocation,
      };

  static WalkingSessionStatus _parseStatus(String? status) {
    switch (status) {
      case 'searching':
        return WalkingSessionStatus.searching;
      case 'pendingVolunteer':
        return WalkingSessionStatus.pendingVolunteer;
      case 'volunteerAccepted':
        return WalkingSessionStatus.volunteerAccepted;
      case 'volunteerConfirmed':
        return WalkingSessionStatus.volunteerConfirmed;
      case 'volunteerReached':
        return WalkingSessionStatus.volunteerReached;
      case 'inProgress':
        return WalkingSessionStatus.inProgress;
      case 'completed':
        return WalkingSessionStatus.completed;
      case 'cancelled':
        return WalkingSessionStatus.cancelled;
      default:
        return WalkingSessionStatus.searching;
    }
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    throw FormatException(
      'WalkingSessionModel._parseTimestamp: expected Timestamp or DateTime, '
      'got ${value.runtimeType} ($value)',
    );
  }

  /// Nullable variant for optional timestamp fields.
  // ignore: unused_element
  static DateTime? _parseTimestampOrNull(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  WalkingSessionModel copyWith({
    String? sessionId,
    String? userId,
    String? userName,
    String? userPhone,
    WalkingSessionStatus? status,
    GeoPoint? pickupCoords,
    GeoPoint? destinationCoords,
    String? destinationName,
    String? pickupName,
    DateTime? createdAt,
    DateTime? lastUpdate,
    String? volunteerId,
    String? volunteerName,
    String? volunteerPhone,
    bool? volunteerReachedConfirmedByVolunteer,
    bool? volunteerReachedConfirmedByUser,
    bool? destinationReachedConfirmedByVolunteer,
    bool? destinationReachedConfirmedByUser,
    GeoPoint? volunteerLocation,
    GeoPoint? userCurrentLocation,
  }) {
    return WalkingSessionModel(
      sessionId: sessionId ?? this.sessionId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhone: userPhone ?? this.userPhone,
      status: status ?? this.status,
      pickupCoords: pickupCoords ?? this.pickupCoords,
      destinationCoords: destinationCoords ?? this.destinationCoords,
      destinationName: destinationName ?? this.destinationName,
      pickupName: pickupName ?? this.pickupName,
      createdAt: createdAt ?? this.createdAt,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      volunteerId: volunteerId ?? this.volunteerId,
      volunteerName: volunteerName ?? this.volunteerName,
      volunteerPhone: volunteerPhone ?? this.volunteerPhone,
      volunteerReachedConfirmedByVolunteer:
          volunteerReachedConfirmedByVolunteer ??
              this.volunteerReachedConfirmedByVolunteer,
      volunteerReachedConfirmedByUser:
          volunteerReachedConfirmedByUser ??
              this.volunteerReachedConfirmedByUser,
      destinationReachedConfirmedByVolunteer:
          destinationReachedConfirmedByVolunteer ??
              this.destinationReachedConfirmedByVolunteer,
      destinationReachedConfirmedByUser:
          destinationReachedConfirmedByUser ??
              this.destinationReachedConfirmedByUser,
      volunteerLocation: volunteerLocation ?? this.volunteerLocation,
      userCurrentLocation: userCurrentLocation ?? this.userCurrentLocation,
    );
  }

  // ── Convenience getters ──
  bool get isSearching => status == WalkingSessionStatus.searching;
  bool get isActive =>
      status != WalkingSessionStatus.completed &&
      status != WalkingSessionStatus.cancelled;
  bool get isInProgress => status == WalkingSessionStatus.inProgress;
  bool get isCompleted => status == WalkingSessionStatus.completed;

  bool get bothConfirmedArrival =>
      volunteerReachedConfirmedByVolunteer && volunteerReachedConfirmedByUser;

  bool get bothConfirmedDestination =>
      destinationReachedConfirmedByVolunteer &&
      destinationReachedConfirmedByUser;

  String get statusLabel {
    switch (status) {
      case WalkingSessionStatus.searching:
        return 'Searching for a buddy...';
      case WalkingSessionStatus.pendingVolunteer:
        return 'Notifying volunteers...';
      case WalkingSessionStatus.volunteerAccepted:
        return 'Match found!';
      case WalkingSessionStatus.volunteerConfirmed:
        return 'Buddy confirmed — en route';
      case WalkingSessionStatus.volunteerReached:
        return 'Buddy has arrived';
      case WalkingSessionStatus.inProgress:
        return 'Walking together';
      case WalkingSessionStatus.completed:
        return 'Walk completed';
      case WalkingSessionStatus.cancelled:
        return 'Cancelled';
    }
  }
}
