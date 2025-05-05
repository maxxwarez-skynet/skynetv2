import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:skynet/screens/authenticate.dart';
import 'package:skynet/screens/home_page.dart';
import 'package:provider/provider.dart';

class Wrapper extends StatelessWidget {
  const Wrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Get user data from provider
    final user = Provider.of<User?>(context);

    // Print authentication state for debugging
    print('Authentication state changed: ${user != null ? 'Logged in' : 'Logged out'}');

    // Return either Home or Authenticate widget based on authentication state
    if (user == null) {
      return const Authenticate();
    } else {
      return const HomePage();
    }
  }
}