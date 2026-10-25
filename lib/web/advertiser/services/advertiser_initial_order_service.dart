import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Prépare une commande interne SPHOT TEST à partir des données déjà sauvées.
/// Aucun appel Odoo, aucune CB, aucune facture et aucune activation.
class AdvertiserInitialOrderService {
  const AdvertiserInitialOrderService();

  static const String _endpoint =
      'https://us-central1-sphot-ab80b.cloudfunctions.net/'
      'prepareAdvertiserInitialOrder';

  Future<Map<String, dynamic>> prepare({
    required String requestId,
    required String territory,
    required String offer,
    required String duration,
    required String startDate,
    required String pricingReference,
    required int payableExclTaxCents,
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
        'expected': {
          'territory': territory,
          'offer': offer,
          'duration': duration,
          'startDate': startDate,
          'pricingReference': pricingReference,
          'payableExclTaxCents': payableExclTaxCents,
        },
      }),
    ).timeout(const Duration(seconds: 30));
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw StateError('Réponse de commande illisible.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Réponse de commande incorrecte.');
    }
    if (response.statusCode != 200 || decoded['success'] != true) {
      throw StateError(decoded['error']?.toString() ??
          'Commande non enregistrée (HTTP ${response.statusCode}).');
    }
    final receipt = decoded['receipt'];
    if (receipt is! Map<String, dynamic> ||
        receipt['testOnly'] != true ||
        receipt['campaignActivationAllowed'] != false ||
        receipt['paymentStatus'] != 'not_started' ||
        receipt['reference'] is! String ||
        receipt['payableExclTaxCents'] is! int) {
      throw StateError('Justificatif de commande test non conforme.');
    }
    return receipt;
  }
}
