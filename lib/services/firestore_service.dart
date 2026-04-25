import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/flag_state.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<SpotFlagState>> getSpotsStream() {
    return _firestore.collection('spots').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return SpotFlagState.fromFirestore(doc.id, doc.data());
      }).toList();
    });
  }
}