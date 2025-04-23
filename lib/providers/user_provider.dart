import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class UserProvider with ChangeNotifier {
  UserModel _currentUser = UserModel(uid: '');
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  UserModel get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser.isAuthenticated;

  UserProvider() {
    // Initialize by listening to auth state changes
    _authService.authStateChanges.listen((User? user) {
      updateUser(user);
    });
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
      // No need to update user here as the auth state listener will handle it
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
      // No need to update user here as the auth state listener will handle it
    } catch (e) {
      print('Error signing out: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}