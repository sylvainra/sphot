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

  Stream<List<Map<String, dynamic>>> getTerritoriesStream() {
    return _firestore.collection('territoires').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return <String, dynamic>{
          ...doc.data(),
          '_docId': doc.id,
        };
      }).toList();
    });
  }
}
