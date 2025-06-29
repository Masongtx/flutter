import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
// REQUIRED: Import the provider package
// Your AppState class
import 'package:flutter_lovetap/screens/home_screen.dart'; // Your home screen widget
import 'package:flutter_lovetap/screens/login_screen.dart'; // Your login screen widget

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // StreamBuilder listens to changes in the user's authentication state from Firebase.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show a loading indicator while waiting for the authentication state.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        // If there's user data in the snapshot, the user is signed in.
        if (snapshot.hasData) {
          // Since AppState is already provided higher up in MyApp (main.dart),
          // we can directly return the HomeScreen.
          return const HomeScreen(); // Return the HomeScreen widget
        } else {
          // If no user data, the user is not signed in. Show the LoginScreen.
          return const LoginScreen(); // Return the LoginScreen widget
        }
      },
    );
  }
}