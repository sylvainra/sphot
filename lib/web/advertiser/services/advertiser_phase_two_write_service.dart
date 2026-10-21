import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Save only advertiser-owned Phase 2 fields through a verified server session.
class AdvertiserPhaseTwoWriteService {
  const AdvertiserPhaseTwoWriteService._();

  static const String _endpoint =
      'https://us-central1-sphot-ab80b.cloudfunctions.net/'
      'saveAdvertiserPhaseTwo';

  static Future<void> save({
    required String requestId,
    required String action,
    required Map<String, Object?> payload,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || requestId.isEmpty) {
      throw StateError('Connexion annonceur requise.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Session annonceur indisponible.');
    }
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'requestId': requestId,
        'action': action,
        'payload': payload,
      }),
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Enregistrement refusé. Réessayez.';
      try {
        final json = jsonDecode(response.body);
        if (json is Map && json['error'] is String) {
          message = json['error'] as String;
        }
      } catch (_) {
        // Network/proxy error: do not display raw response content.
      }
      throw StateError(message);
    }
  }
}
