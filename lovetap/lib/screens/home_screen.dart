import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
// import 'package:permission_handler/permission_handler.dart'; // For permission requests, if needed elsewhere
// import '../services/firebase_service.dart'; // Import your FirebaseService

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // late FirebaseService _firebaseService;
  User? _user;

  @override
  void initState() {
    super.initState();
    // _firebaseService = FirebaseService();
    _user = FirebaseAuth.instance.currentUser;
    // Permissions for BLE are now primarily handled in MainScreen
    // If HomeScreen needs other permissions, request them here.
  }

  @override
  Widget build(BuildContext context) {
    // Watch AppState for changes to rebuild the UI accordingly
    final appState = Provider.of<AppState>(context);
    // final user = appState.currentUser; // Already fetched _user in initState

    return Scaffold(
      appBar: AppBar(
        title: const Text("LoveTap Home"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              // AuthGate will handle navigation
            },
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text("Welcome, ${_user?.email ?? 'User'}!"),
            const SizedBox(height: 20),
            const Text("This is the HomeScreen."),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/main');
              },
              child: const Text("Go to Bracelet Testing Screen"),
            ),
          ],
        ),
      ),
    );
  }
}