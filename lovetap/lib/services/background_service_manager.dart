import 'package:flutter/services.dart';

class BackgroundServiceManager {
  // Ensure this channel name matches the one in MainActivity.kt
  static const _platform = MethodChannel('com.example.flutter_lovetap/background_service');

  static Future<void> startService() async {
    try {
      final String? result = await _platform.invokeMethod('startBackgroundService');
      print('BackgroundServiceManager: Service start call result: $result');
    } on PlatformException catch (e) {
      // Handle error if the platform method couldn't be called
      print("BackgroundServiceManager: Failed to start native service: '${e.message}'.");
    }
  }
}