import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class SauveteurAssignedSpot {
  final String id;
  final String label;

  const SauveteurAssignedSpot({
    required this.id,
    required this.label,
  });
}

class SauveteurLivePublicationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<List<SauveteurAssignedSpot>> loadAssignedSpots({
    required String territoireId,
    required List<String> postesAffectes,
  }) async {
    final assigned = postesAffectes.toSet();

    final snapshot = await _firestore
        .collection('territoires')
        .doc(territoireId)
        .collection('spots')
        .get();

    final spots = snapshot.docs
        .where((doc) => assigned.contains(doc.id))
        .map((doc) {
          final data = doc.data();
          final nomSecours = (data['nomSecours'] ?? '').toString().trim();
          final nomSphot = (data['nomSphot'] ?? '').toString().trim();
          final idSphot = (data['idSphot'] ?? '').toString().trim();

          final label = [
            idSphot,
            nomSecours.isNotEmpty ? nomSecours : nomSphot,
          ].where((value) => value.isNotEmpty).join(' - ');

          return SauveteurAssignedSpot(
            id: doc.id,
            label: label.isEmpty ? doc.id : label,
          );
        })
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    return spots;
  }

  static Future<Map<String, dynamic>> loadLiveSpotState({
    required String spotId,
  }) async {
    final snapshot = await _firestore.collection('spots').doc(spotId).get();
    return snapshot.data() ?? <String, dynamic>{};
  }

  static Future<void> publish({
    required String sauveteurSessionToken,
    required String spotId,
    required Map<String, dynamic> changes,
  }) async {
    final response = await http.post(
      Uri.parse(
        'https://us-central1-sphot-ab80b.cloudfunctions.net/'
        'updateSauveteurLiveState',
      ),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sauveteurSessionToken': sauveteurSessionToken,
        'spotId': spotId,
        'changes': changes,
      }),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    var errorCode = 'publication_failed';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        errorCode = (decoded['error'] ?? errorCode).toString();
      }
    } catch (_) {}

    throw StateError(errorCode);
  }
}
