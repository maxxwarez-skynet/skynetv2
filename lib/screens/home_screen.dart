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
    final userProfile = userProvider.userProfile;
    
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Welcome to Skynet!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'You are signed in as:',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 10),
              if (user.photoURL != null)
                CircleAvatar(
                  radius: 40,
                  backgroundImage: NetworkImage(user.photoURL!),
                ),
              const SizedBox(height: 10),
              Text(
                user.displayName ?? 'User',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                user.email ?? '',
                style: const TextStyle(
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 20),
              // Last login information
              if (userProfile != null) ...[
                const Divider(),
                const SizedBox(height: 10),
                Text(
                  'Account created: ${_formatDateTime(userProfile.createdAt)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Previous login: ${_formatDateTime(userProfile.lastLoginAt)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const Divider(),
              ],

            ],
          ),
        ),
      ),
    );
  }
}