import 'package:firebase_auth/firebase_auth.dart';

class UserModel {
  final String uid;
  final String? displayName;
  final String? email;
  final String? photoURL;

  UserModel({
    required this.uid,
    this.displayName,
    this.email,
    this.photoURL,
  });

  // Factory constructor to create a UserModel from a Firebase User
  factory UserModel.fromFirebaseUser(User? user) {
    if (user == null) {
      return UserModel(uid: '');
    }
    
    return UserModel(
      uid: user.uid,
      displayName: user.displayName,
      email: user.email,
      photoURL: user.photoURL,
    );
  }

  // Check if user is authenticated
  bool get isAuthenticated => uid.isNotEmpty;
}