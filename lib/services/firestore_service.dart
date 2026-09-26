import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../models/flag_state.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<SpotFlagState>> getSpotsStream() {
    return _firestore.collection('publicSpots').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return SpotFlagState.fromFirestore(doc.id, doc.data());
      }).toList();
    });
  }

  Future<List<Map<String, dynamic>>> getPublicAdvertisingSpots() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://europe-west1-sphot-ab80b.cloudfunctions.net/'
              'getPublicAdvertisingSpots',
            ),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return const [];

      final payload = jsonDecode(response.body);
      if (payload is! Map || payload['spots'] is! List) return const [];

      return (payload['spots'] as List)
          .whereType<Map>()
          .map((spot) => Map<String, dynamic>.from(spot))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> recordPublicClick({
    required String territoireId,
    required String targetId,
    required String targetType,
    required String targetName,
    required String source,
  }) async {
    if (territoireId.trim().isEmpty ||
        targetId.trim().isEmpty ||
        targetName.trim().isEmpty) {
      return;
    }

    try {
      await http
          .post(
            Uri.parse(
              'https://europe-west1-sphot-ab80b.cloudfunctions.net/'
              'recordPublicClick',
            ),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'territoireId': territoireId,
              'targetId': targetId,
              'targetType': targetType,
              'targetName': targetName,
              'source': source,
            }),
          )
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Le comptage ne doit jamais bloquer la consultation publique.
    }
  }
}
