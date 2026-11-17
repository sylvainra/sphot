import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Consultation Odoo à travers le backend Firebase ; aucun accès direct Odoo.
class SphotOdooBillingStatusService {
  const SphotOdooBillingStatusService();

  static const String _endpoint = String.fromEnvironment(
    'SPHOT_ODOO_BILLING_STATUS_URL',
  );

  static Uri? get _uri {
    final uri = Uri.tryParse(_endpoint.trim());
    if (uri == null || uri.scheme != 'https' || uri.hasPort ||
        uri.userInfo.isNotEmpty || uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    final cloudFunction =
        uri.host == 'us-central1-sphot-ab80b.cloudfunctions.net' &&
        uri.path == '/getOdooBillingStatus';
    final sameOrigin = uri.host == 'sphot.app' &&
        uri.path == '/api/odoo/billing-status';
    return (cloudFunction || sameOrigin) ? uri : null;
  }

  static bool get configured => _uri != null;

  Future<Map<String, dynamic>> read({
    required String market,
    required String requestId,
  }) async {
    final uri = _uri;
    if (uri == null) throw StateError('Consultation Odoo indisponible.');
    if (!['ADMIN', 'ADVERTISER'].contains(market) ||
        !RegExp(r'^[A-Za-z0-9_-]{8,128}$').hasMatch(requestId)) {
      throw StateError('Dossier professionnel invalide.');
    }

    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (user == null || token == null || token.isEmpty) {
      throw StateError('Session professionnelle requise.');
    }

    final http.Response response;
    try {
      response = await http.post(
        uri,
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(<String, String>{
          'market': market,
          'requestId': requestId,
        }),
      ).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw StateError('Statut des factures momentanément indisponible.');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw StateError('Accès au dossier de facturation refusé.');
    }
    if (response.statusCode != 200) {
      throw StateError('Statut des factures momentanément indisponible.');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw StateError('Réponse de facturation illisible.');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['success'] != true ||
        !['not_linked', 'order_pending', 'order_found', 'invoice_found']
            .contains(decoded['status'])) {
      throw StateError('Réponse de facturation non conforme.');
    }
    return decoded;
  }
}
