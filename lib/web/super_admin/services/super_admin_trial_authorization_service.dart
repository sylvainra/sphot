import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Autorisation distincte de la première approbation du dossier ADMIN.
/// Les dates de l'essai sont calculées côté serveur, jamais dans Flutter.
class SuperAdminTrialAuthorizationService {
  const SuperAdminTrialAuthorizationService._();

  static const String _endpointUrl = String.fromEnvironment(
    'SPHOT_ADMIN_TRIAL_AUTHORIZATION_URL',
  );

  static Future<void> authorize(String requestId) async {
    final endpoint = Uri.tryParse(_endpointUrl);
    if (endpoint == null || endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        !endpoint.path.endsWith('/authorizeAdminTrial')) {
      throw StateError('Point de validation d’essai non configuré.');
    }
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw StateError('Session Firebase du Super Admin absente.');
    }
    final response = await http.post(
      endpoint,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'requestId': requestId}),
    ).timeout(const Duration(seconds: 20));
    Map<String, dynamic> result;
    try {
      final json = jsonDecode(response.body);
      result = json is Map
          ? json.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
    } catch (_) {
      result = <String, dynamic>{};
    }
    if (response.statusCode != 200 || result['success'] != true) {
      throw StateError(
        'Autorisation serveur refusée : '
        '${result['error'] ?? response.statusCode}',
      );
    }
  }
}
