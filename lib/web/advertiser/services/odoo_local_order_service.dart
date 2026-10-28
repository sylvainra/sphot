import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Uniquement Flutter Web en mode développement explicite.
/// La clé API Odoo reste dans le processus Node local, jamais dans Flutter.
class OdooLocalOrderService {
  const OdooLocalOrderService();

  static const bool enabled = kDebugMode && kIsWeb &&
      bool.fromEnvironment('SPHOT_ODOO_LOCAL', defaultValue: false);

  /// Nouveau parcours Odoo anti-doublons, uniquement activable en local.
  /// Les rubriques historiques restent inchangées par défaut.
  static const bool secureCheckoutEnabled = enabled &&
      bool.fromEnvironment('SPHOT_ODOO_SECURE_CHECKOUT', defaultValue: false);

  static const String _endpoint = 'http://127.0.0.1:8767/order';

  Future<Map<String, dynamic>> secureCheckoutStatus(String requestId) =>
      _secureCheckoutSend('secure_status', requestId);

  Future<Map<String, dynamic>> secureCheckoutDraft(String requestId) =>
      _secureCheckoutSend('secure_draft', requestId);

  Future<Map<String, dynamic>> secureCheckoutInvoice(String requestId) =>
      _secureCheckoutSend('secure_invoice', requestId);

  Future<Map<String, dynamic>> secureCheckoutStripeStatus(String requestId) =>
      _secureCheckoutSend('secure_stripe_status', requestId);

  Future<Uri> secureCheckoutStripePortal(String requestId) async {
    final result = await _secureCheckoutSend('secure_stripe_checkout', requestId);
    final raw = result['portalUrl'];
    final uri = raw is String ? Uri.tryParse(raw) : null;
    if (uri == null || uri.scheme != 'http' ||
        uri.host != '127.0.0.1' || uri.port != 8069 ||
        !RegExp(r'^/my/invoices/[0-9]+$').hasMatch(uri.path) ||
        !uri.queryParameters.containsKey('access_token')) {
      throw StateError('Portail Stripe TEST sécurisé non conforme.');
    }
    return uri;
  }

  Future<Map<String, dynamic>> _secureCheckoutSend(
      String action, String requestId) async {
    if (!secureCheckoutEnabled) {
      throw StateError('Passerelle Odoo sécurisée désactivée hors test local.');
    }
    final result = await _send({'action': action, 'requestId': requestId});
    if (result['testOnly'] != true ||
        result['campaignActivationAllowed'] != false ||
        (action == 'secure_stripe_status' &&
            result['paymentConfirmed'] is! bool)) {
      throw StateError('Réponse Odoo sécurisée non conforme.');
    }
    return result;
  }

  Future<Map<String, dynamic>?> lookup(String requestId) async {
    final response = await _send({'action': 'status', 'requestId': requestId});
    return response['found'] == true
        ? Map<String, dynamic>.from(response['order'] as Map)
        : null;
  }

  Future<Map<String, dynamic>> confirm({
    required String requestId,
    required String territory,
    required String offer,
    required String duration,
    required String startDate,
    required String pricingReference,
    required int payableExclTaxCents,
  }) async {
    final response = await _send({
      'action': 'confirm',
      'requestId': requestId,
      'expected': {
        'territory': territory,
        'offer': offer,
        'duration': duration,
        'startDate': startDate,
        'pricingReference': pricingReference,
        'payableExclTaxCents': payableExclTaxCents,
      },
    });
    final order = response['order'];
    if (order is! Map || order['testOnly'] != true ||
        order['campaignActivationAllowed'] != false ||
        order['paymentStatus'] != 'not_started' ||
        order['odooState'] != 'sale' || order['reference'] is! String ||
        order['odooOrderName'] is! String) {
      throw StateError('Réponse Odoo locale non conforme.');
    }
    return Map<String, dynamic>.from(order);
  }

  Future<Map<String, dynamic>> invoiceStatus(String requestId) async {
    return _send({'action': 'invoice_status', 'requestId': requestId});
  }

  Future<Map<String, dynamic>> createInvoice(String requestId) async {
    final result = await _send({'action': 'invoice', 'requestId': requestId});
    final raw = result['invoice'];
    if (raw is! Map || raw['testOnly'] != true ||
        raw['campaignActivationAllowed'] != false ||
        raw['paymentInitiated'] != false ||
        raw['state'] != 'posted' || raw['odooInvoiceId'] is! int ||
        raw['amountTotalCents'] is! int) {
      throw StateError('Facture Odoo locale non conforme.');
    }
    return result;
  }

  Future<Map<String, dynamic>> registerTestPayment(String requestId) async {
    final result = await _send({'action': 'payment', 'requestId': requestId});
    final raw = result['invoice'];
    if (raw is! Map || raw['testOnly'] != true ||
        raw['campaignActivationAllowed'] != false ||
        raw['paymentInitiated'] != false ||
        raw['odooPaymentRecorded'] != true ||
        !['in_payment', 'paid'].contains(raw['paymentState']) ||
        raw['state'] != 'posted') {
      throw StateError('Règlement Odoo de test non confirmé.');
    }
    return result;
  }

  /// Deuxième achat Odoo, réservé au prestataire natif Démo (mode TEST).
  /// La première commande et sa facture déjà payée ne sont jamais réutilisées.
  Future<Map<String, dynamic>> demoStatus(String requestId) async {
    final raw = await _send({'action': 'demo_status', 'requestId': requestId});
    if (raw['testOnly'] != true ||
        (raw['found'] == true && raw['campaignActivationAllowed'] != false)) {
      throw StateError('Statut Odoo Démo non conforme.');
    }
    return raw;
  }

  Future<Map<String, dynamic>> demoConfirm(String requestId) async {
    final raw = await _send({'action': 'demo_confirm', 'requestId': requestId});
    final order = raw['order'];
    if (raw['testOnly'] != true || order is! Map ||
        order['odooState'] != 'sale' ||
        order['campaignActivationAllowed'] != false) {
      throw StateError('Commande Démo Odoo non conforme.');
    }
    return raw;
  }

  Future<Map<String, dynamic>> demoInvoice(String requestId) async {
    final raw = await _send({'action': 'demo_invoice', 'requestId': requestId});
    final invoice = raw['invoice'];
    if (raw['testOnly'] != true || invoice is! Map ||
        invoice['state'] != 'posted' ||
        invoice['campaignActivationAllowed'] != false) {
      throw StateError('Facture Démo Odoo non conforme.');
    }
    return raw;
  }

  Future<Uri> demoCheckout(String requestId) async {
    final raw = await _send({'action': 'demo_checkout', 'requestId': requestId});
    final text = raw['portalUrl'];
    final uri = text is String ? Uri.tryParse(text) : null;
    if (raw['testOnly'] != true ||
        raw['campaignActivationAllowed'] != false ||
        uri == null || uri.scheme != 'http' ||
        uri.host != '127.0.0.1' || uri.port != 8069 ||
        !RegExp(r'^/my/invoices/[0-9]+$').hasMatch(uri.path) ||
        !uri.queryParameters.containsKey('access_token')) {
      throw StateError('Lien de paiement Odoo Démo non conforme.');
    }
    return uri;
  }

  /// Troisième achat local : Stripe SANDBOX via le portail natif Odoo.
  /// Seul Odoo confirme le résultat ; aucune activation de campagne.
  Future<Map<String, dynamic>> stripeTestStatus(String requestId) async {
    final raw = await _send({
      'action': 'stripe_test_status', 'requestId': requestId,
    });
    if (raw['testOnly'] != true ||
        raw['campaignActivationAllowed'] != false ||
        raw['paymentConfirmed'] is! bool) {
      throw StateError('Statut Stripe TEST Odoo non conforme.');
    }
    return raw;
  }

  Future<Map<String, dynamic>> stripeTestConfirm(String requestId) async {
    final raw = await _send({
      'action': 'stripe_test_confirm', 'requestId': requestId,
    });
    final order = raw['order'];
    if (raw['testOnly'] != true ||
        raw['campaignActivationAllowed'] != false ||
        order is! Map || order['odooState'] != 'sale' ||
        order['campaignActivationAllowed'] != false) {
      throw StateError('Commande Stripe TEST non conforme.');
    }
    return raw;
  }

  Future<Map<String, dynamic>> stripeTestInvoice(String requestId) async {
    final raw = await _send({
      'action': 'stripe_test_invoice', 'requestId': requestId,
    });
    final invoice = raw['invoice'];
    if (raw['testOnly'] != true ||
        raw['campaignActivationAllowed'] != false ||
        invoice is! Map || invoice['state'] != 'posted' ||
        invoice['campaignActivationAllowed'] != false) {
      throw StateError('Facture Stripe TEST non conforme.');
    }
    return raw;
  }

  Future<Uri> stripeTestCheckout(String requestId) async {
    final raw = await _send({
      'action': 'stripe_test_checkout', 'requestId': requestId,
    });
    final text = raw['portalUrl'];
    final uri = text is String ? Uri.tryParse(text) : null;
    if (raw['testOnly'] != true ||
        raw['campaignActivationAllowed'] != false ||
        uri == null || uri.scheme != 'http' ||
        uri.host != '127.0.0.1' || uri.port != 8069 ||
        !RegExp(r'^/my/invoices/[0-9]+$').hasMatch(uri.path) ||
        !uri.queryParameters.containsKey('access_token')) {
      throw StateError('Lien du portail Stripe TEST non conforme.');
    }
    return uri;
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> request) async {
    if (!enabled) {
      throw StateError('Connexion Odoo désactivée hors du test local.');
    }
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Connexion annonceur SPHOT requise.');
    }
    late final http.Response response;
    try {
      response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(request),
      ).timeout(const Duration(seconds: 60));
    } catch (_) {
      throw StateError('Passerelle Odoo locale indisponible sur le port 8767.');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw StateError('Réponse de la passerelle Odoo illisible.');
    }
    if (decoded is! Map || response.statusCode != 200 ||
        decoded['ok'] != true) {
      throw StateError(decoded is Map && decoded['error'] is String
          ? decoded['error'] as String
          : 'Commande Odoo non traitée (HTTP ${response.statusCode}).');
    }
    return Map<String, dynamic>.from(decoded);
  }
}
