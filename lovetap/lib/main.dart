import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode, defaultTargetPlatform; // Added kIsWeb and defaultTargetPlatform
import 'package:flutter/services.dart'; // Import for PlatformException
import 'package:provider/provider.dart';
import 'firebase_options.dart'; // Auto-generated Firebase configuration file
import 'auth_gate.dart'; // Handles authentication routing
import 'app_state.dart'; // Your application's main state management class
import 'screens/login_screen.dart'; // Import LoginScreen
import 'screens/main_screen.dart'; // Import MainScreen
import 'services/background_service_manager.dart'; // To start the native service
import 'package:device_preview/device_preview.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    print("MAIN.DART: Error initializing Firebase: $e");
    // Optionally, you could show an error UI or prevent app from running
  }

  // Attempt to start the native Android background service
  // This helps keep the app alive for BLE/Firebase operations when backgrounded.
  // Add a platform check if this service is Android-specific
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) { // Added platform check
    try {
      await BackgroundServiceManager.startService();
    } on MissingPluginException catch (e) {
      print("MAIN.DART: MissingPluginException for background service: ${e.message}");
      // Decide if you want to proceed without the service or show an error
    } catch (e) {
      print("MAIN.DART: Error starting background service: $e");
    }
  }

  runApp(
    DevicePreview(
      enabled: !kReleaseMode, // Only enable DevicePreview in debug mode
      builder: (context) => const MyApp(), // Wrap your app
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>(
          create: (_) => AppState(),
        ),
        // You can add other providers here if needed, for example, for BleManager
        // if you want to access it via Provider throughout the app.
        // ChangeNotifierProvider<BleManager>(
        //   create: (_) => BleManager(),
        // ),
        // Provider<FirebaseService>(
        //   create: (_) => FirebaseService(),
        // ),
      ],
      child: MaterialApp(
        useInheritedMediaQuery: true, // Required for DevicePreview
        locale: DevicePreview.locale(context), // Required for DevicePreview
        builder: DevicePreview.appBuilder, // Required for DevicePreview
        title: 'LoveTap', // Title of your application
        theme: ThemeData(
          primarySwatch: Colors.blue, // Defines the primary color palette for the app
          visualDensity: VisualDensity.adaptivePlatformDensity, // Adjusts density based on platform
        ),
        home: const AuthGate(),
        routes: {
          '/login': (context) => const LoginScreen(), // Route for the LoginScreen
          '/main': (context) => const MainScreen(),   // Route for the MainScreen
        },
      ),
    );
  }
} // This closing brace correctly closes the MyApp class.
