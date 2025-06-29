import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Example: Record a tap event for the current user
  Future<void> recordTap({String? userId}) async {
    final String? currentUserId = userId ?? _auth.currentUser?.uid;
    if (currentUserId == null) {
      print("FirebaseService: User not logged in. Cannot record tap.");
      return;
    }

    try {
      // Example: Store taps in a subcollection under the user's document
      // Or, you might have a global tap counter or a document per device pair.
      final userTapsCollection = _firestore.collection('users').doc(currentUserId).collection('taps');
      
      await userTapsCollection.add({
        'timestamp': FieldValue.serverTimestamp(),
        'source': 'flutter_app', // Or some identifier
      });
      print("FirebaseService: Tap recorded successfully for user $currentUserId");

      // Example: Increment a counter on the user's document
      // await _firestore.collection('users').doc(currentUserId).update({
      //   'tapCount': FieldValue.increment(1),
      // });

    } catch (e) {
      print("FirebaseService: Error recording tap: $e");
    }
  }

  // TODO: Add methods to get tap counts, listen to tap streams, etc.
}