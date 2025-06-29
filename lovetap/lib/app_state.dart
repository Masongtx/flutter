import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart'; // Moved to top
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async'; // Required for StreamSubscription

// Moved enum to top-level
enum TargetDevice { mine, partner }

class AppState extends ChangeNotifier {
  User? _currentUser; // Holds the currently authenticated Firebase user
  User? get currentUser => _currentUser;

  bool _isLoading = true; // Indicates if the app is currently loading data/initializing
  bool get isLoading => _isLoading;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // Firestore instance for database operations

  // --- Tap/Press Feature State (for other phones via Firestore) ---
  bool _isPartnerPressedFirestore = false; // Tracks if the partner's button is pressed (via Firestore)
  bool get isPartnerPressedFirestore => _isPartnerPressedFirestore;
  final String _demoPairId = 'love_tap_pair_123'; // A fixed ID for demonstration purposes (simulates a pair)

  // --- Partner Information and Remote Commands ---
  // String? _partnerUid; // UID of the paired partner - Temporarily removed for broadcast
  // String? get partnerUid => _partnerUid; // Temporarily removed
  Timestamp? _lastIncomingBroadcastCommandTimestamp; // To avoid re-processing old broadcast commands
  // --- BLE Specifics for ESP32 ---
  // For "My" Device
  BluetoothDevice? _myEsp32Device;
  BluetoothCharacteristic? _myEsp32Characteristic;
  bool _isConnectedToMyEsp32 = false;
  bool get isConnectedToMyEsp32 => _isConnectedToMyEsp32;
  BluetoothDevice? get myConnectedDevice => _myEsp32Device;
  bool _isScanningForMyDevice = false;
  bool get isScanningForMyDevice => _isScanningForMyDevice;
  bool _isConnectingToMyDevice = false;
  bool get isConnectingToMyDevice => _isConnectingToMyDevice;
  StreamSubscription<List<ScanResult>>? _myDeviceScanSubscription;

  // For "Partner's" Device
  BluetoothDevice? _partnerEsp32Device;
  BluetoothCharacteristic? _partnerEsp32Characteristic;
  bool _isConnectedToPartnerEsp32 = false;
  bool get isConnectedToPartnerEsp32 => _isConnectedToPartnerEsp32;
  BluetoothDevice? get partnerConnectedDevice => _partnerEsp32Device;
  bool _isScanningForPartnerDevice = false;
  bool get isScanningForPartnerDevice => _isScanningForPartnerDevice;
  bool _isConnectingToPartnerDevice = false;
  bool get isConnectingToPartnerDevice => _isConnectingToPartnerDevice;
  StreamSubscription<List<ScanResult>>? _partnerDeviceScanSubscription;

  // Common
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription; // Subscription to Bluetooth adapter state changes

  // UUIDs for your ESP32's BLE Service and Characteristic.
  // THESE MUST MATCH THE UUIDS YOU DEFINED IN YOUR ESP32 FIRMWARE EXACTLY!
  static final Guid ESP32_SERVICE_UUID = Guid("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
  static final Guid ESP32_CHARACTERISTIC_UUID = Guid("beb5483e-36e1-4688-b7f5-ea07361b26a8");
  static const String myTargetDeviceName = "MyLoveTap_ESP32"; // Example name for your device
  static const String partnerTargetDeviceName = "PartnerLoveTap_ESP32"; // Example name for partner's device

  AppState() {
    _initializeUser(); // Initialize user authentication state
    _setupBleListeners(); // Set up Bluetooth listeners only
  }

  // Initializes the user by listening to Firebase authentication state changes.
  void _initializeUser() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      _currentUser = user;
      _isLoading = false;
      notifyListeners(); // Notify widgets of state change

      if (user != null) {
        _listenForPressStateFirestore(); // Start listening for Firestore updates if user is logged in
      }
    });
  }

  // // For demo purposes: allows setting the partner's UID - Temporarily removed
  // void setPartnerUid(String? uid) {
  //   _partnerUid = uid;
  //   notifyListeners(); // Notify if UI depends on partnerUid being set
  // }

  // --- User Authentication Methods ---
  Future<void> register(String email, String password) async {
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      print('Register Error: ${e.code}');
      rethrow; // Re-throw the error for UI to handle
    } catch (e) {
      print('Register Error: $e');
      rethrow;
    }
  }

  Future<void> signIn(String email, String password) async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      print('Sign In Error: ${e.code}');
      rethrow; // Re-throw the error for UI to handle
    } catch (e) {
      print('Sign In Error: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    await _disconnectDevice(TargetDevice.mine);
    await _disconnectDevice(TargetDevice.partner);
  }

  // Method for the current user's app to send a BROADCAST command for other users in the pair to vibrate their bracelet (via Firestore)
  Future<void> sendCommandToVibratePartnerBracelet() async {
    if (_currentUser == null) {
      print("AppState (Sender - ${_currentUser?.email}): Current user not logged in. Cannot send broadcast command.");
      return;
    }

    try {
      // Update the main pair document with broadcast command fields
      print("AppState (Sender - ${_currentUser?.email}): Attempting to send broadcast command to taps/$_demoPairId");
      await _firestore.collection('taps').doc(_demoPairId).set({
        'broadcastCommandByUid': _currentUser!.uid,
        'broadcastCommandTimestamp': FieldValue.serverTimestamp(), // Crucial for detecting new commands
      }, SetOptions(merge: true)); // Merge true to not overwrite isPressed fields
      print("AppState (Sender - ${_currentUser?.email}): Broadcast command successfully sent to taps/$_demoPairId");
    } catch (e) {
      print("AppState (Sender - ${_currentUser?.email}): Error sending remote tap command: $e");
    }
  }
  // --- Press Feature Methods (for both Firestore and BLE) ---
  // Sends the current press state (true when button is pressed, false when released)
  Future<void> sendPressState(bool isCurrentlyPressed, {required TargetDevice target}) async {
    if (_currentUser == null) {
      print("User not logged in, cannot send press state.");
      return;
    }

    // --- 1. Update Firestore (for other phone users) ---
    // This is wrapped in its own try-catch so a Firestore failure (like permission denied)
    // does not prevent the local BLE command from being sent.
    if (target == TargetDevice.mine) {
      try {
        await _firestore.collection('taps').doc(_demoPairId).set({
          'isPressed': isCurrentlyPressed,
          'pressedBy': _currentUser!.uid,
          'lastUpdateTime': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        print('Press state sent to Firestore: $isCurrentlyPressed by ${_currentUser!.email}');
      } catch (e) {
        print('Error sending press state to Firestore: $e');
      }
    }

    // --- 2. Send state to the target ESP32 via BLE if connected ---
    try {
      BluetoothCharacteristic? targetCharacteristic;
      String targetName = "";
      bool isConnected = false;

      if (target == TargetDevice.mine) {
        targetCharacteristic = _myEsp32Characteristic;
        targetName = "My ESP32";
        isConnected = _isConnectedToMyEsp32;
      } else if (target == TargetDevice.partner) {
        targetCharacteristic = _partnerEsp32Characteristic;
        targetName = "Partner's ESP32";
        isConnected = _isConnectedToPartnerEsp32;
      }

      if (isConnected && targetCharacteristic != null) {
        if (isCurrentlyPressed) { // Only send command on press, not release
          print("AppState: Attempting to send vibrate command for target: $target to characteristic: ${targetCharacteristic.uuid}");
          final List<int> vibrateCommand = [1]; // '1' to trigger vibration
          try {
            await targetCharacteristic.write(vibrateCommand, withoutResponse: true);
            print('AppState: Vibration command [1] successfully sent to $targetName via BLE.');
          } catch (e) {
            print('AppState: ERROR sending command to $targetName: $e');
          }
        }
      } else {
        // More detailed logging to pinpoint the issue
        if (!isConnected) {
          print('Target device ($target) is not connected, skipping BLE send.');
        } else { // isConnected is true, but characteristic is null
          print('Target device ($target) is connected, but the required characteristic was not found. Skipping BLE send.');
          print('Please check the debug console logs from when you connected. It may have failed to discover the characteristic.');
          print('Also, ensure the ESP32 Service UUID and Characteristic UUID in the app match the ESP32 firmware.');
        }
      }
    } catch (e) {
      print('Error sending BLE command for $target: $e');
    }
  }

  // Listens for incoming press states from Firestore in real-time.
  // This updates the UI when a partner presses their button.
  void _listenForPressStateFirestore() {
    // Listener for direct tap indication (isPartnerPressedFirestore)
    print("AppState (${_currentUser?.email}): Setting up listener for direct taps at taps/$_demoPairId");
    _firestore.collection('taps').doc(_demoPairId).snapshots().listen((snapshot) {
      print("AppState (${_currentUser?.email}): Listener for direct taps/$_demoPairId triggered. Snapshot exists: ${snapshot.exists}");
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        print("AppState (${_currentUser?.email}): Data from direct taps/$_demoPairId: $data");
        final bool? receivedIsPressed = data['isPressed'] as bool?;
        final String? pressedByUid = data['pressedBy'] as String?;

        // --- Handle direct tap indication for _isPartnerPressedFirestore ---
        if (receivedIsPressed != null && pressedByUid != null && pressedByUid != _currentUser!.uid) {
          _isPartnerPressedFirestore = receivedIsPressed;
          notifyListeners();
          print('AppState (${_currentUser?.email}): Partner isPressed (Firestore) updated to: $_isPartnerPressedFirestore by $pressedByUid. Current user: ${_currentUser!.uid}. Circle should react.');
        } else if (receivedIsPressed == null) {
          // If isPressed is explicitly null, consider resetting. If it's just not present, might not need to reset.
          // For now, let's only reset if it's explicitly null or document doesn't exist.
          if (data.containsKey('isPressed') && data['isPressed'] == null) {
            _isPartnerPressedFirestore = false;
            notifyListeners();
            print('AppState (${_currentUser?.email}): receivedIsPressed is null in direct taps listener. Resetting _isPartnerPressedFirestore.');
          }
        } else if (pressedByUid == _currentUser!.uid) {
            print('AppState (${_currentUser?.email}): Firestore update for direct taps/$_demoPairId is from self (UID: $pressedByUid). Ignoring for _isPartnerPressedFirestore.');
        }

        // --- Handle incoming broadcast command ---
        final String? broadcastSenderUid = data['broadcastCommandByUid'] as String?;
        final Timestamp? broadcastTimestamp = data['broadcastCommandTimestamp'] as Timestamp?;

        if (broadcastTimestamp != null && broadcastSenderUid != null && broadcastSenderUid != _currentUser!.uid) {
          print("AppState (${_currentUser?.email}): Processing broadcast command. Sender: $broadcastSenderUid, Timestamp: $broadcastTimestamp. Last Broadcast: $_lastIncomingBroadcastCommandTimestamp");
          if (_lastIncomingBroadcastCommandTimestamp == null || broadcastTimestamp.compareTo(_lastIncomingBroadcastCommandTimestamp!) > 0) {
            print("AppState (${_currentUser?.email}): Received NEW broadcast tap command from $broadcastSenderUid at $broadcastTimestamp");
            _lastIncomingBroadcastCommandTimestamp = broadcastTimestamp;
            // Trigger this user's own bracelet if connected
            if (isConnectedToMyEsp32 && _myEsp32Characteristic != null) {
              print("AppState (${_currentUser?.email}): Executing broadcast tap on MY bracelet. Characteristic UUID: ${_myEsp32Characteristic!.uuid}");
              sendPressState(true, target: TargetDevice.mine); // This will send [1] to local bracelet
            } else {
              String reason = !isConnectedToMyEsp32 ? "my bracelet is not connected" : "my bracelet characteristic is null";
              print("AppState (${_currentUser?.email}): Received broadcast tap command, but cannot execute on MY bracelet because $reason.");
            }
          } else {
            print("AppState (${_currentUser?.email}): Broadcast command timestamp is NOT newer. Ignoring. New: $broadcastTimestamp, Last Stored: $_lastIncomingBroadcastCommandTimestamp");
          }
        }

      } else {
        _isPartnerPressedFirestore = false; // Reset if document does not exist
        notifyListeners();
        print('AppState (${_currentUser?.email}): Firestore document taps/$_demoPairId does not exist or has no data.');
      }
    });
  }

  // --- BLE Communication Methods ---

  // Sets up listeners for Bluetooth adapter state changes and initiates scanning.
  void _setupBleListeners() {
    // Subscribes to changes in the Bluetooth adapter's state (e.g., ON, OFF).
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) async { // Added async
      print('Bluetooth Adapter State: $state');
      if (state == BluetoothAdapterState.on) {
          // Bluetooth turned ON.
          // If we were previously connected and lost connection because BT was off,
          // we might want to attempt a reconnect, but only if _esp32Device is not null.
          // For now, let's keep it simple: the UI will initiate scans.
          print('Bluetooth is now ON. UI can initiate scan if needed.');
      } else if (state == BluetoothAdapterState.off) {
        print('Bluetooth is OFF. Disconnecting devices and cancelling scans.');
        await _disconnectDevice(TargetDevice.mine, cancelScan: true);
        await _disconnectDevice(TargetDevice.partner, cancelScan: true);
      } else {
        await _disconnectDevice(TargetDevice.mine);
        await _disconnectDevice(TargetDevice.partner);
        _myDeviceScanSubscription?.cancel();
        _myDeviceScanSubscription = null;
        _partnerDeviceScanSubscription?.cancel();
        _partnerDeviceScanSubscription = null;
        print('Bluetooth is OFF. Scan cancelled and disconnected.');
      }
      });

    // Checks the initial Bluetooth adapter state when the app starts.
    FlutterBluePlus.adapterState.first.then((state) {
      if (state == BluetoothAdapterState.on) { // <-- This is where your selected 'if' statement goes
          print('Bluetooth is ON initially. UI can initiate scan if needed.');
      }
    });
  }

  // Generic method to connect to a specified device
  Future<void> connectToDevice(TargetDevice target) async {
    print("AppState: connectToDevice called for target: $target"); // ADDED THIS LINE
    String targetDeviceName;
    bool isCurrentlyScanning;
    bool isCurrentlyConnecting;
    Function(bool) setScanningState;
    Function(bool) setConnectingState;
    Function(BluetoothDevice?) setDevice;
    Function(bool) setIsConnected;
    Function(BluetoothCharacteristic?) setCharacteristic;
    StreamSubscription<List<ScanResult>>? scanSubscription;
    Function(StreamSubscription<List<ScanResult>>?) setScanSubscription;

    if (target == TargetDevice.mine) {
      targetDeviceName = myTargetDeviceName;
      isCurrentlyScanning = _isScanningForMyDevice;
      isCurrentlyConnecting = _isConnectingToMyDevice;
      setScanningState = (val) => _isScanningForMyDevice = val;
      setConnectingState = (val) => _isConnectingToMyDevice = val;
      setDevice = (dev) => _myEsp32Device = dev;
      setIsConnected = (val) => _isConnectedToMyEsp32 = val;
      setCharacteristic = (char) => _myEsp32Characteristic = char;
      scanSubscription = _myDeviceScanSubscription;
      setScanSubscription = (sub) => _myDeviceScanSubscription = sub;
    } else {
      targetDeviceName = partnerTargetDeviceName;
      isCurrentlyScanning = _isScanningForPartnerDevice;
      isCurrentlyConnecting = _isConnectingToPartnerDevice;
      setScanningState = (val) => _isScanningForPartnerDevice = val;
      setConnectingState = (val) => _isConnectingToPartnerDevice = val;
      setDevice = (dev) => _partnerEsp32Device = dev;
      setIsConnected = (val) => _isConnectedToPartnerEsp32 = val;
      setCharacteristic = (char) => _partnerEsp32Characteristic = char;
      scanSubscription = _partnerDeviceScanSubscription;
      setScanSubscription = (sub) => _partnerDeviceScanSubscription = sub;
    }

    if (isCurrentlyScanning || isCurrentlyConnecting) {
      print('Scan or connection already in progress for $targetDeviceName.');
      return;
    }
    print('Attempting to start BLE scan and connect for $targetDeviceName...');

    if (await FlutterBluePlus.isScanning.first) {
      print('Global scan in progress. Stopping previous global scan.');
      await FlutterBluePlus.stopScan();
    }
    scanSubscription?.cancel();
    setScanSubscription(null);

    setScanningState(true);
    notifyListeners(); // Notify UI that scanning has started
    print('Starting new BLE scan for "$targetDeviceName"...');
    
    scanSubscription = FlutterBluePlus.scanResults.listen(
      (results) async {
      for (ScanResult r in results) {
        if (r.device.platformName == targetDeviceName) {
          print('Found $targetDeviceName: ${r.device.platformName} (${r.device.remoteId})');
          scanSubscription?.cancel();
          setScanSubscription(null);
          
          if (await FlutterBluePlus.isScanning.first) {
             await FlutterBluePlus.stopScan();
          }
          setScanningState(false);
          notifyListeners();

          setDevice(r.device);
          setIsConnected(false);
          notifyListeners(); // Update UI to show not connected yet

          setConnectingState(true);
          notifyListeners();
          try {
            print('Attempting to connect to $targetDeviceName...');
            BluetoothDevice? currentDevice = (target == TargetDevice.mine) ? _myEsp32Device : _partnerEsp32Device;
            await currentDevice!.connect();
            setIsConnected(true);
            setConnectingState(false);
            notifyListeners(); // Update UI to show connected
            print('Connected to $targetDeviceName!');

            // In AppState's connectToDevice method, after successful currentDevice!.connect()
            print("AppState: Attempting to discover services for $targetDeviceName...");
            List<BluetoothService> services = await currentDevice.discoverServices();
            print("AppState: Services discovered for $targetDeviceName. Count: ${services.length}");
            for (BluetoothService service in services) {
              if (service.uuid == ESP32_SERVICE_UUID) {
                for (BluetoothCharacteristic characteristic in service.characteristics) {
                  if (characteristic.uuid == ESP32_CHARACTERISTIC_UUID) {
                    setCharacteristic(characteristic);
                    print('Found characteristic for $targetDeviceName!');
                    break; 
                  }
                }
                break; 
              }
            }
            BluetoothCharacteristic? currentCharacteristic = (target == TargetDevice.mine) ? _myEsp32Characteristic : _partnerEsp32Characteristic;
            if (currentCharacteristic == null) {
              print('Error: Could not find the required characteristic for $targetDeviceName. Disconnecting.');
              await _disconnectDevice(target);
            }

            currentDevice.connectionState.listen((BluetoothConnectionState state) async {
              if (state == BluetoothConnectionState.disconnected) {
                print('$targetDeviceName disconnected! Attempting to re-scan in 5 seconds...');
                setDevice(null);
                setCharacteristic(null);
                setIsConnected(false);
                setConnectingState(false);
                notifyListeners(); // Update UI to show disconnected
                await Future.delayed(const Duration(seconds: 5));
                connectToDevice(target);
              }
            });

          } catch (e) {
            print('Error connecting to $targetDeviceName: $e');
            setConnectingState(false);
            await _disconnectDevice(target);
          }
          return; // Device found and handled, exit for loop
        }
      }
    }, 
    onDone: () {
      if (scanSubscription != null) {
        setScanningState(false);
        if (!isCurrentlyConnecting) setDevice(null);
        notifyListeners();
        print('BLE scan for $targetDeviceName finished (onDone).');
      }
       setScanSubscription(null);
    }, onError: (e) {
      setScanningState(false);
      setConnectingState(false);
      notifyListeners();
      print('BLE scan for $targetDeviceName error: $e');
       setScanSubscription(null);
    });
    setScanSubscription(scanSubscription); // Store the subscription

    // Starts the actual BLE scan for a duration.
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    print('Global scan initiated for 10 seconds (will be filtered for $targetDeviceName).');
  }

  // Disconnects from the ESP32 device if currently connected.
  Future<void> _disconnectDevice(TargetDevice target, {bool cancelScan = false}) async {
    BluetoothDevice? deviceToDisconnect;
    String deviceName;
    Function(bool) setIsConnected;
    Function(bool) setConnectingState;
    Function(BluetoothDevice?) setDevice;
    Function(BluetoothCharacteristic?) setCharacteristic;
    StreamSubscription<List<ScanResult>>? scanSubToCancel;

    if (target == TargetDevice.mine) {
      deviceToDisconnect = _myEsp32Device;
      deviceName = myTargetDeviceName;
      setIsConnected = (val) => _isConnectedToMyEsp32 = val;
      setConnectingState = (val) => _isConnectingToMyDevice = val;
      setDevice = (dev) => _myEsp32Device = dev;
      setCharacteristic = (char) => _myEsp32Characteristic = char;
      scanSubToCancel = _myDeviceScanSubscription;
      if (cancelScan) _isScanningForMyDevice = false;
    } else {
      deviceToDisconnect = _partnerEsp32Device;
      deviceName = partnerTargetDeviceName;
      setIsConnected = (val) => _isConnectedToPartnerEsp32 = val;
      setConnectingState = (val) => _isConnectingToPartnerDevice = val;
      setDevice = (dev) => _partnerEsp32Device = dev;
      setCharacteristic = (char) => _partnerEsp32Characteristic = char;
      scanSubToCancel = _partnerDeviceScanSubscription;
      if (cancelScan) _isScanningForPartnerDevice = false;
    }

    if (cancelScan) {
      scanSubToCancel?.cancel();
      if (target == TargetDevice.mine) _myDeviceScanSubscription = null;
      else _partnerDeviceScanSubscription = null;
    }

    if (deviceToDisconnect != null) {
      try {
        await deviceToDisconnect.disconnect();
        setIsConnected(false);
        setConnectingState(false);
        notifyListeners();
        print('Disconnected from $deviceName.');
      } catch (e) {
        print('Error disconnecting from $deviceName: $e');
      }
    }
    setDevice(null);
    setCharacteristic(null);
    setConnectingState(false); // Ensure connecting flag is reset
    notifyListeners(); // Notify for UI update after clearing device refs
  }

  @override
  void dispose() {
    _myDeviceScanSubscription?.cancel();
    _partnerDeviceScanSubscription?.cancel();
    _adapterStateSubscription?.cancel(); // Cancel adapter state subscription
    if (FlutterBluePlus.isScanningNow) { // Check if scanning before stopping
      FlutterBluePlus.stopScan();
    }
    _disconnectDevice(TargetDevice.mine); // Ensure disconnection
    _disconnectDevice(TargetDevice.partner); // Ensure disconnection
    super.dispose();
  }
}