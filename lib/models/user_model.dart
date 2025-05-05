import 'package:cloud_firestore/cloud_firestore.dart';

// Device model to represent a user's device
class DeviceModel {
  final String id;
  final String name;
  final String status;
  final bool state;  // New field for ON/OFF state
  final DateTime? lastActive;
  final Map<String, dynamic> settings;

  DeviceModel({
    required this.id,
    required this.name,
    required this.status,
    this.state = false,  // Default to OFF
    this.lastActive,
    required this.settings,
  });

  // Create a DeviceModel from a Map
  factory DeviceModel.fromMap(Map<String, dynamic> data) {
    // Handle timestamps that might be null or of different types
    DateTime? lastActiveDate;
    if (data['lastActive'] is Timestamp) {
      lastActiveDate = (data['lastActive'] as Timestamp).toDate();
    }

    return DeviceModel(
      id: data['id'] ?? '',
      name: data['name'] ?? 'Unknown Device',
      status: data['status'] ?? 'offline',
      state: data['state'] ?? false,  // Default to OFF if not present
      lastActive: lastActiveDate,
      settings: data['settings'] is Map
          ? Map<String, dynamic>.from(data['settings'] as Map)
          : {},
    );
  }

  // Convert DeviceModel to a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'status': status,
      'state': state,
      'lastActive': lastActive != null ? Timestamp.fromDate(lastActive!) : Timestamp.now(),
      'settings': settings,
    };
  }
}

class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String? photoURL;
  final DateTime? createdAt;
  final DateTime? lastLogin;
  final Map<String, dynamic> preferences;
  final List<DeviceModel> devices;

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoURL,
    this.createdAt,
    this.lastLogin,
    required this.preferences,
    required this.devices,
  });

  // Create a UserModel from a Firestore document
  factory UserModel.fromFirestore(Map<String, dynamic> data) {
    // Handle the case where preferences might be null
    Map<String, dynamic> prefs = {};
    if (data['preferences'] != null && data['preferences'] is Map) {
      prefs = Map<String, dynamic>.from(data['preferences'] as Map);
    }

    // Handle timestamps that might be null or of different types
    DateTime? createdAtDate;
    if (data['createdAt'] is Timestamp) {
      createdAtDate = (data['createdAt'] as Timestamp).toDate();
    }

    DateTime? lastLoginDate;
    if (data['lastLogin'] is Timestamp) {
      lastLoginDate = (data['lastLogin'] as Timestamp).toDate();
    }

    // Handle devices list
    List<DeviceModel> devicesList = [];
    if (data['devices'] != null && data['devices'] is List) {
      devicesList = (data['devices'] as List)
          .map((deviceData) => DeviceModel.fromMap(deviceData as Map<String, dynamic>))
          .toList();
    }

    return UserModel(
      uid: data['uid'] ?? '',
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? 'User',
      photoURL: data['photoURL'] as String?,
      createdAt: createdAtDate,
      lastLogin: lastLoginDate,
      preferences: prefs,
      devices: devicesList,
    );
  }

  // Convert UserModel to a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoURL': photoURL,
      // Don't include createdAt when updating to preserve the original value
      'lastLogin': FieldValue.serverTimestamp(),
      'preferences': preferences,
      'devices': devices.map((device) => device.toMap()).toList(),
    };
  }

  // Create a copy of the UserModel with updated fields
  UserModel copyWith({
    String? displayName,
    String? photoURL,
    Map<String, dynamic>? preferences,
    List<DeviceModel>? devices,
  }) {
    return UserModel(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      photoURL: photoURL ?? this.photoURL,
      createdAt: createdAt,
      lastLogin: lastLogin,
      preferences: preferences ?? this.preferences,
      devices: devices ?? this.devices,
    );
  }

  // Check if the user has any devices
  bool get hasDevices => devices.isNotEmpty;
}