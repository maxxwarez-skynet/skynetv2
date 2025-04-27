import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile_model.dart';
import '../utils/logger.dart';

class UserFirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Logger _logger = Logger('UserFirestoreService');
  
  // Collection reference
  CollectionReference get usersCollection => _firestore.collection('users');
  
  // Get user document reference
  DocumentReference getUserDocRef(String uid) => usersCollection.doc(uid);
  
  // Get user profile
  Future<UserProfileModel?> getUserProfile(String uid) async {
    try {
      DocumentSnapshot doc = await getUserDocRef(uid).get();
      if (doc.exists) {
        return UserProfileModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      _logger.e('Error getting user profile', e);
      return null;
    }
  }
  
  // Create or update user profile
  Future<void> createOrUpdateUserProfile(User firebaseUser) async {
    try {
      // Check if user exists
      DocumentSnapshot doc = await getUserDocRef(firebaseUser.uid).get();
      
      if (doc.exists) {
        // User exists, update last login time
        UserProfileModel existingProfile = UserProfileModel.fromFirestore(doc);
        existingProfile.updateLastLogin();
        
        await getUserDocRef(firebaseUser.uid).update({
          'lastLoginAt': Timestamp.fromDate(DateTime.now()),
        });
      } else {
        // User doesn't exist, create new profile
        UserProfileModel newProfile = UserProfileModel.createNew(
          uid: firebaseUser.uid,
          displayName: firebaseUser.displayName,
          email: firebaseUser.email,
          photoURL: firebaseUser.photoURL,
        );
        
        await getUserDocRef(firebaseUser.uid).set(newProfile.toFirestore());
      }
    } catch (e) {
      _logger.e('Error creating/updating user profile', e);
      rethrow;
    }
  }
}