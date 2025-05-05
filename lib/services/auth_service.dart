import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:skynet/services/database_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final DatabaseService _database = DatabaseService();

  // Auth change user stream
  Stream<User?> get user {
    return _auth.authStateChanges();
  }

  // Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Check if running on web
      if (kIsWeb) {
        print('Running on web platform, using web sign-in flow');

        // Create a new provider
        GoogleAuthProvider googleProvider = GoogleAuthProvider();

        // Add scopes if needed
        googleProvider.addScope('https://www.googleapis.com/auth/contacts.readonly');
        googleProvider.setCustomParameters({
          'login_hint': 'user@example.com'
        });

        // Sign in using a popup
        try {
          final UserCredential userCredential = await _auth.signInWithPopup(googleProvider);
          print('Web sign-in successful: ${userCredential.user?.displayName}');
          
          // Update last login timestamp
          if (userCredential.user != null) {
            await _database.updateLastLogin(userCredential.user!.uid);
          }
          
          return userCredential;
        } catch (e) {
          print('Error with web popup sign-in: $e');

          // Fallback to redirect method
          print('Trying redirect method instead...');
          await _auth.signInWithRedirect(googleProvider);

          // This won't be reached immediately after redirect
          return null;
        }
      } else {
        print('Running on mobile platform, using native sign-in flow');

        // Mobile flow
        // Trigger the authentication flow
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

        if (googleUser == null) {
          // User canceled the sign-in flow
          print('User canceled Google sign-in');
          return null;
        }

        // Obtain the auth details from the request
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

        // Create a new credential
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        // Sign in to Firebase with the Google credential
        final UserCredential userCredential = await _auth.signInWithCredential(credential);

        // Print user info for debugging
        print('Signed in: ${userCredential.user?.displayName}');
        
        // Update last login timestamp
        if (userCredential.user != null) {
          await _database.updateLastLogin(userCredential.user!.uid);
        }

        return userCredential;
      }
    } catch (e) {
      print('Error signing in with Google: $e');
      return null;
    }
  }

  // Check if user is already signed in
  Future<bool> isUserSignedIn() async {
    return _auth.currentUser != null;
  }

  // Sign out
  Future<void> signOut() async {
    try {
      if (!kIsWeb) {
        // Only sign out from Google on mobile platforms
        await _googleSignIn.signOut();
      }
      // Sign out from Firebase (works on all platforms)
      return await _auth.signOut();
    } catch (e) {
      print('Error signing out: $e');
      return;
    }
  }
}