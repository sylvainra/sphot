import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Client du serveur PDF unique SPHOT. Ne transmet jamais de prix, de
/// territoire, de SIRET, d'identité d'émetteur ou de chemin Storage.
class AdminQuotePortalClient {
  const AdminQuotePortalClient();

  static const String endpoint =
      'https://us-central1-sphot-ab80b.cloudfunctions.net/'
      'adminQuotePortal';

  Future<Uint8List> consultPdf() => _post({'action': 'consult'});

  Future<Uint8List> downloadIssuedPdf(String documentId) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,220}$').hasMatch(documentId)) {
      throw StateError('Référence documentaire invalide.');
    }
    return _post({
      'action': 'download',
      'documentId': documentId,
    });
  }

  Future<Uint8List> _post(Map<String, dynamic> payload) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Session Firebase Admin absente.');
    }
    final token = await user.getIdToken();
    if (token == null || token.trim().isEmpty) {
      throw StateError('Jeton Firebase Admin absent.');
    }
    final response = await http.post(
      Uri.parse(endpoint),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 45));

    if (response.statusCode == 404) {
      throw const AdminQuoteEndpointUnavailable();
    }
    if (response.statusCode != 200) {
      throw StateError(
        response.statusCode == 403 || response.statusCode == 401 ?
          'Accès au devis refusé par le serveur.' :
          'Consultation du document indisponible '
          '(HTTP ' + response.statusCode.toString() + ').',
      );
    }
    final bytes = response.bodyBytes;
    if (bytes.length < 1024 ||
        String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw StateError('Document PDF reçu invalide.');
    }
    return Uint8List.fromList(bytes);
  }
}

class AdminQuoteEndpointUnavailable implements Exception {
  const AdminQuoteEndpointUnavailable();
}
