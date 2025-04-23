import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfileModel {
  final String uid;
  final String? displayName;
  final String? email;
  final String? photoURL;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  UserProfileModel({
    required this.uid,
    this.displayName,
    this.email,
    this.photoURL,
    this.createdAt,
    this.lastLoginAt,
  });

  // Create a UserProfileModel from a Firestore document
  factory UserProfileModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    
    if (data == null) {
      return UserProfileModel(uid: doc.id);
    }
    
    return UserProfileModel(
      uid: doc.id,
      displayName: data['displayName'],
      email: data['email'],
      photoURL: data['photoURL'],
      createdAt: data['createdAt'] != null 
          ? (data['createdAt'] as Timestamp).toDate() 
          : null,
      lastLoginAt: data['lastLoginAt'] != null 
          ? (data['lastLoginAt'] as Timestamp).toDate() 
          : null,
    );
  }

  // Convert UserProfileModel to a Map for Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'email': email,
      'photoURL': photoURL,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'lastLoginAt': lastLoginAt != null ? Timestamp.fromDate(lastLoginAt!) : null,
    };
  }

  // Create a new user profile
  factory UserProfileModel.createNew({
    required String uid,
    String? displayName,
    String? email,
    String? photoURL,
  }) {
    final now = DateTime.now();
    return UserProfileModel(
      uid: uid,
      displayName: displayName,
      email: email,
      photoURL: photoURL,
      createdAt: now,
      lastLoginAt: now,
    );
  }

  // Update last login time
  UserProfileModel updateLastLogin() {
    return UserProfileModel(
      uid: uid,
      displayName: displayName,
      email: email,
      photoURL: photoURL,
      createdAt: createdAt,
      lastLoginAt: DateTime.now(),
    );
  }
}