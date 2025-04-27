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
      appBar: AppBar(
        // Remove the title to make space for the avatar on the left
        title: const Text(''),
        leading: user.photoURL != null
            ? Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircleAvatar(
                  backgroundImage: NetworkImage(user.photoURL!),
                ),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await userProvider.signOut();
              // No need to navigate as we'll handle this in main.dart
            },
          ),
        ],
      ),
      body: Container(), // Empty body as requested
    );
  }
}