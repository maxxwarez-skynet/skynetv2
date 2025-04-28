import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/user_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh user profile when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      if (userProvider.isAuthenticated) {
        userProvider.refreshUserProfile();
      }
    });
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Never';
    
    final formatter = DateFormat('MMM d, yyyy - h:mm a');
    return formatter.format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;
    
    return Scaffold(
      // Remove the app bar completely for a full screen layout
      appBar: null,
      body: Stack(
        children: [
          // Full screen content (currently empty as requested)
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Theme.of(context).scaffoldBackgroundColor,
          ),
          
          // Avatar at top left
          if (user.photoURL != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10, // Account for status bar
              left: 16,
              child: CircleAvatar(
                backgroundImage: NetworkImage(user.photoURL!),
                radius: 20,
              ),
            ),
            
          // Logout button at top right
          Positioned(
            top: MediaQuery.of(context).padding.top + 10, // Account for status bar
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await userProvider.signOut();
                // No need to navigate as we'll handle this in main.dart
              },
            ),
          ),
        ],
      ),
    );
  }
}