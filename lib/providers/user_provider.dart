import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/user_profile_model.dart';
import '../services/auth_service.dart';
import '../services/user_firestore_service.dart';

class UserProvider with ChangeNotifier {
  UserModel _currentUser = UserModel(uid: '');
  UserProfileModel? _userProfile;
  final AuthService _authService = AuthService();
  final UserFirestoreService _userFirestoreService = UserFirestoreService();
  bool _isLoading = false;

  UserModel get currentUser => _currentUser;
  UserProfileModel? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser.isAuthenticated;
  DateTime? get lastLoginAt => _userProfile?.lastLoginAt;

  UserProvider() {
    // Initialize by listening to auth state changes
    _authService.authStateChanges.listen((User? user) async {
      if (user != null) {
        // User is signed in, update Firestore
        await _handleUserSignIn(user);
      } else {
        // User is signed out
        _userProfile = null;
        updateUser(null);
      }
    });
  }

  // Handle user sign in and Firestore operations
  Future<void> _handleUserSignIn(User user) async {
    try {
      // Create or update user profile in Firestore
      await _userFirestoreService.createOrUpdateUserProfile(user);
      
      // Get the updated user profile
      _userProfile = await _userFirestoreService.getUserProfile(user.uid);
      
      // Update the current user
      updateUser(user);
    } catch (e) {
      print('Error handling user sign in: $e');
      // Still update the user even if Firestore operations fail
      updateUser(user);
    }
  }

  // Update user data
  void updateUser(User? user) {
    _currentUser = UserModel.fromFirebaseUser(user);
    notifyListeners();
  }

  // Sign in with Google
  Future<void> signInWithGoogle() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.signInWithGoogle();
      // Auth state listener will handle Firestore operations
    } catch (e) {
      // Handle error
      print('Error signing in with Google: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Sign out
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.signOut();
      // Auth state listener will handle cleanup
    } catch (e) {
      print('Error signing out: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Refresh user profile from Firestore
  Future<void> refreshUserProfile() async {
    if (!isAuthenticated) return;
    
    try {
      _userProfile = await _userFirestoreService.getUserProfile(_currentUser.uid);
      notifyListeners();
    } catch (e) {
      print('Error refreshing user profile: $e');
    }
  }
}