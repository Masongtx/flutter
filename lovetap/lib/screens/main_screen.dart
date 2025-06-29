import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart'; // This now correctly imports AppState and the top-level TargetDevice enum
import 'package:permission_handler/permission_handler.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // final TextEditingController _partnerUidController = TextEditingController(); // Temporarily removed

  @override
  void initState() {
    super.initState();
    // Request permissions when the screen is initialized if not already handled
    // Or ensure AppState handles this upon successful login if preferred
    _requestPermissionsAndInitialScan();
  }

 @override
  void dispose() {
    // _partnerUidController.dispose(); // Temporarily removed
    super.dispose();
  }



  Future<void> _requestPermissionsAndInitialScan() async {
    final appState = Provider.of<AppState>(context, listen: false);
    // Check if already scanning or connected to avoid redundant requests if coming back to screen
    // Commenting out this line as isScanning and isConnectedToESP32 are no longer direct properties of AppState
    // if (appState.isScanning || appState.isConnectedToESP32) return; 

    Map<Permission, PermissionStatus> statuses = await [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.notification,
    ].request();

    bool permissionsGranted = statuses.values.every((status) => status.isGranted);

    if (permissionsGranted) {
      print("MainScreen: All required BLE permissions granted.");
      // Optionally, you can trigger a scan here if it's the desired behavior
      // No automatic scan on permission grant; user will press buttons.
    } else {
      print("MainScreen: Not all BLE permissions were granted.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Permissions are required for BLE features.")),
        );
      }
    }
  }

  void _sendTap(BuildContext context, TargetDevice target) { // Use TargetDevice directly
    final appState = Provider.of<AppState>(context, listen: false);
    // Send press state true, then false after a short delay to simulate a tap
    appState.sendPressState(true, target: target);
    Future.delayed(const Duration(milliseconds: 200), () {
      appState.sendPressState(false, target: target); // Though ESP32 handles duration, good for consistency
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final user = appState.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("LoveTap"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await appState.signOut();
              // AuthGate will handle navigation
            },
          )
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text("Welcome, ${user?.email ?? 'User'}!", style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 30),

              // // --- Demo: Set Partner UID --- // Temporarily removed
              // Padding(
              //   padding: const EdgeInsets.symmetric(vertical: 8.0),
              //   child: TextField(
              //     controller: _partnerUidController,
              //     decoration: InputDecoration(
              //       labelText: "Partner's User ID (for demo)",
              //       hintText: "Enter your partner's Firebase UID",
              //       suffixIcon: IconButton(
              //         icon: const Icon(Icons.save),
              //         onPressed: () {
              //           Provider.of<AppState>(context, listen: false).setPartnerUid(_partnerUidController.text.trim());
              //           FocusScope.of(context).unfocus(); // Dismiss keyboard
              //           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Partner UID set for this session.")));
              //         },
              //       )
              //     ),
              //   ),
              // ),
              // Text(appState.partnerUid != null && appState.partnerUid!.isNotEmpty ? "Partner UID: ${appState.partnerUid}" : "Partner UID not set", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              // const SizedBox(height: 20),

              // --- My Bracelet Controls ---
              ElevatedButton.icon(
                icon: Icon(appState.isScanningForMyDevice ? Icons.bluetooth_searching : Icons.bluetooth_audio),
                onPressed: () {
                  print("MainScreen: 'Connect My Bracelet' button pressed. Calling connectToDevice(TargetDevice.mine).");
                  appState.connectToDevice(TargetDevice.mine);
                },
                label: Text(appState.isScanningForMyDevice ? "Scanning My Bracelet..." : "Connect My Bracelet"),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)),
              ),
              const SizedBox(height: 20),
              if (appState.isConnectedToMyEsp32)
                Text("My Bracelet: Connected to ${appState.myConnectedDevice?.platformName ?? AppState.myTargetDeviceName}", style: const TextStyle(color: Colors.green))
              else if (appState.isConnectingToMyDevice)
                const Text("My Bracelet: Connecting...", style: TextStyle(color: Colors.blue))
              else if (appState.isScanningForMyDevice)
                const Text("My Bracelet: Scanning...", style: TextStyle(color: Colors.orange))
              else
                const Text("My Bracelet: Not connected.", style: TextStyle(color: Colors.red)),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: appState.isConnectedToMyEsp32 ? () => _sendTap(context, TargetDevice.mine) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: appState.isPartnerPressedFirestore ? Colors.pinkAccent : Colors.blue, // Firestore state for partner's tap on *their* phone
                  padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: const Text("TAP MY BRACELET"),
              ),
              const SizedBox(height: 30),
              const Divider(),
              const SizedBox(height: 30),

              // --- Partner's Bracelet Controls ---
              ElevatedButton.icon(
                icon: Icon(appState.isScanningForPartnerDevice ? Icons.bluetooth_searching : Icons.bluetooth_audio),
                onPressed: () {
                  print("MainScreen: 'Connect Partner's Bracelet' button pressed. Calling connectToDevice(TargetDevice.partner).");
                  appState.connectToDevice(TargetDevice.partner);
                },
                label: Text(appState.isScanningForPartnerDevice ? "Scanning Partner's Bracelet..." : "Connect Partner's Bracelet"),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)),
              ),
              const SizedBox(height: 20),
              if (appState.isConnectedToPartnerEsp32)
                Text("Partner's Bracelet: Connected to ${appState.partnerConnectedDevice?.platformName ?? AppState.partnerTargetDeviceName}", style: const TextStyle(color: Colors.green))
              else if (appState.isConnectingToPartnerDevice)
                const Text("Partner's Bracelet: Connecting...", style: TextStyle(color: Colors.blue))
              else if (appState.isScanningForPartnerDevice)
                const Text("Partner's Bracelet: Scanning...", style: TextStyle(color: Colors.orange))
              else
                const Text("Partner's Bracelet: Not connected.", style: TextStyle(color: Colors.red)),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: appState.isConnectedToPartnerEsp32 ? () => _sendTap(context, TargetDevice.partner) : null,
                style: ElevatedButton.styleFrom(
                  // You might want a different visual cue for this button or no specific color change based on Firestore
                  backgroundColor: Colors.deepPurpleAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: const Text("TAP PARTNER'S BRACELET"),
              ),
              const SizedBox(height: 10),
              Text(appState.isPartnerPressedFirestore ? "Partner is tapping!" : "Waiting for partner's tap..."),
              // This Firestore status is for when your partner taps THEIR button on THEIR phone,
              // and it updates via the cloud. It's separate from you tapping their bracelet via BLE from your phone.
            ],
          ), // Closes Column
        ), // Closes Padding
      ), // Closes Center (which is the body of the Scaffold)
      // Add a new button for sending remote tap command
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (appState.currentUser != null) // Enable if user is logged in
            ? () {
                print("MainScreen: 'Remotely Tap Partner's Bracelet' button pressed.");
                appState.sendCommandToVibratePartnerBracelet();
              }
            : null, // Disable if user is not logged in
        label: const Text("Tap Partner (Cloud)"),
        icon: const Icon(Icons.cloud_upload),
        backgroundColor: (appState.currentUser != null) ? Colors.amber : Colors.grey,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat, // This is a property of Scaffold
    );
  }
}