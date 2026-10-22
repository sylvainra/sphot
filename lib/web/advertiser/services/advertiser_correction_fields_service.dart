import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Envoie uniquement les champs de correction autorisés par le Super Admin.
/// La validation des champs et de la session se fait côté serveur.
class AdvertiserCorrectionFieldsService {
  static final Uri _endpoint = Uri.parse(
    'https://us-central1-sphot-ab80b.cloudfunctions.net/'
    'saveAdvertiserCorrectionFields',
  );

  static Future<void> save({
    required String requestId,
    required Map<String, Object?> fields,
  }) async {
    if (fields.isEmpty) return;
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError(
        'Session de correction expirée. Rouvrez votre lien de correction.',
      );
    }
    final response = await http.post(
      _endpoint,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(<String, Object?>{
        'requestId': requestId,
        'fields': fields,
      }),
    ).timeout(const Duration(seconds: 25));

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      // Le code HTTP est conservé pour le diagnostic.
    }
    final body = decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body?['success'] != true) {
      throw StateError(
        (body?['error'] ?? 'Échec de l’enregistrement (HTTP ' +
          response.statusCode.toString() + ').').toString(),
      );
    }
  }
}
