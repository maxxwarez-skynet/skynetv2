// This file is used to initialize Firebase for web platforms
// It's a workaround for compatibility issues between Firebase JS SDK and Flutter plugins

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'firebase_options.dart';

/// Initialize Firebase with proper error handling
Future<void> initializeFirebase() async {
  try {
    if (kIsWeb) {
      // Web-specific initialization
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('Firebase initialized successfully for web');
    } else {
      // Mobile initialization
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('Firebase initialized successfully for mobile');
    }
  } catch (e) {
    print('Failed to initialize Firebase: $e');
    // You can show an error message to the user here
  }
}