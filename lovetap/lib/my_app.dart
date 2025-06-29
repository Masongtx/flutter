// lib/my_app.dart
import 'package:flutter/material.dart';
import 'package:flutter_lovetap/auth_gate.dart'; // We'll create this next, it handles login/home view

// This is the root widget of your application.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LoveTap',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // AuthGate will handle showing login/home based on auth state
      home: const AuthGate(),
    );
  }
}
