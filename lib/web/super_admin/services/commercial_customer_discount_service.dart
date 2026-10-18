import 'dart:convert';

import 'package:http/http.dart' as http;

/// Gestion des remises réservée au Super Admin.
class CommercialCustomerDiscountService {
  const CommercialCustomerDiscountService(this.sessionToken);

  final String sessionToken;

  static const endpoint =
      'https://us-central1-sphot-ab80b.cloudfunctions.net/'
      'manageCommercialPricing';

  Future<int> getDiscount({
    required String market,
    required String customerUid,
  }) async {
    final result = await _post(
      market: market,
      customerUid: customerUid,
      action: 'getCustomerDiscount',
    );
    return (result['percent'] as num).toInt();
  }

  Future<int> saveDiscount({
    required String market,
    required String customerUid,
    required int percent,
  }) async {
    final result = await _post(
      market: market,
      customerUid: customerUid,
      action: 'setCustomerDiscount',
      discountPercent: percent,
    );
    return (result['percent'] as num).toInt();
  }

  Future<Map<String, dynamic>> _post({
    required String market,
    required String customerUid,
    required String action,
    int? discountPercent,
  }) async {
    if (sessionToken.isEmpty) {
      throw StateError('Session Super Admin absente.');
    }
    if (market != 'ADMIN' && market != 'ADVERTISER_RADIUS') {
      throw ArgumentError('Type de client invalide.');
    }
    if (!RegExp(r'^[a-zA-Z0-9_-]{6,128}$').hasMatch(customerUid)) {
      throw ArgumentError('Identifiant client invalide.');
    }
    final response = await http.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $sessionToken',
      },
      body: jsonEncode({
        'market': market,
        'action': action,
        'customerUid': customerUid,
        if (discountPercent != null) 'discountPercent': discountPercent,
      }),
    ).timeout(const Duration(seconds: 25));
    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> ||
        response.statusCode != 200 ||
        payload['success'] != true ||
        payload['data'] is! Map) {
      throw StateError(
        payload is Map ? payload['error']?.toString() ??
            'Service de remise indisponible.' :
            'Réponse de remise invalide.',
      );
    }
    return Map<String, dynamic>.from(payload['data'] as Map);
  }
}
