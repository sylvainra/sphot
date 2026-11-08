import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Lecture seule : le navigateur transmet uniquement les identifiants de
/// postes choisis. Le serveur contrôle l'Admin, le territoire et le tarif.
class AdminOdooLocalPreflightService {
  const AdminOdooLocalPreflightService();

  static const String endpoint = String.fromEnvironment(
    'SPHOT_ADMIN_ODOO_TEST_PREFLIGHT_URL',
  );

  static bool get configured => endpoint.trim().isNotEmpty;

  // Visible uniquement sur lancement Flutter explicitement consacré aux tests.
  static const bool fixtureMode = bool.fromEnvironment(
    'SPHOT_ADMIN_ODOO_TEST_FIXTURE_READONLY',
    defaultValue: false,
  );

  static bool get fixtureConfigured => configured && fixtureMode;

  // Consultation facultative du cycle CARTE fictif C4 TEST déjà exercé
  // manuellement dans Odoo. Ne concerne jamais le compte connecté.
  static const bool cardStatusMode = bool.fromEnvironment(
    'SPHOT_ADMIN_ODOO_TEST_CARD_STATUS_READONLY',
    defaultValue: false,
  );

  static bool get cardStatusConfigured => configured && cardStatusMode;

  Future<Map<String, dynamic>> verifySelection({
    required List<String> stationIds,
  }) async {
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.host != '127.0.0.1' ||
        uri.port != 8768 ||
        uri.path != '/admin/preflight' ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw StateError('Passerelle locale ADMIN TEST non configurée.');
    }
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (user == null || token == null || token.isEmpty) {
      throw StateError('Session Firebase ADMIN requise.');
    }
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'stationIds': stationIds}),
    ).timeout(const Duration(seconds: 30));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Réponse du précontrôle ADMIN illisible.');
    }
    if (response.statusCode != 200 || decoded['ok'] != true) {
      throw StateError(decoded['error']?.toString() ??
          'Contrôle ADMIN serveur indisponible.');
    }
    if (decoded['testOnly'] != true ||
        decoded['action'] != 'read_only_preflight' ||
        decoded['odooOrderCreated'] != false ||
        decoded['odooInvoiceCreated'] != false ||
        decoded['firestoreWriteAttempted'] != false ||
        decoded['activationAllowed'] != false ||
        decoded['numberOfRescueStations'] != stationIds.length ||
        decoded['payableExclTaxCents'] is! int) {
      throw const FormatException('Contrat de précontrôle ADMIN incompatible.');
    }
    return decoded;
  }

  /// Dossier C4 TEST entièrement fictif : ni les postes, ni l'identité, ni
  /// les montants du compte connecté ne sont envoyés à cette route.
  Future<Map<String, dynamic>> verifyFixture() async {
    if (!fixtureConfigured) {
      throw StateError('Mode dossier fictif ADMIN TEST désactivé.');
    }
    final uri = Uri.tryParse(endpoint);
    if (uri == null || uri.scheme != 'http' ||
        uri.host != '127.0.0.1' || uri.port != 8768 ||
        uri.path != '/admin/preflight' || uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty || uri.userInfo.isNotEmpty) {
      throw StateError('Passerelle locale ADMIN TEST non configurée.');
    }
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (user == null || token == null || token.isEmpty) {
      throw StateError('Session Firebase ADMIN requise.');
    }
    final response = await http.post(
      uri.replace(path: '/admin/fixture-preflight'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: '{}',
    ).timeout(const Duration(seconds: 30));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Réponse du dossier fictif illisible.');
    }
    if (response.statusCode != 200 || decoded['ok'] != true) {
      throw StateError(decoded['error']?.toString() ??
          'Dossier fictif TEST indisponible.');
    }
    if (decoded['testOnly'] != true || decoded['fixtureOnly'] != true ||
        decoded['fixtureStationCount'] != 3 ||
        decoded['firestoreProject'] != 'sphot-c4-test-20261029' ||
        decoded['odooDatabase'] != 'sphot_publicitaire_checkout_test' ||
        decoded['prodFirestoreWritten'] != false ||
        decoded['odooWritten'] != false ||
        decoded['activationAttempted'] != false ||
        decoded['action'] != 'none') {
      throw const FormatException('Contrat de simulation ADMIN incompatible.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> verifyCardTestStatus() async {
    if (!cardStatusConfigured) {
      throw StateError('Contrôle du cycle CARTE fictif TEST désactivé.');
    }
    final uri = Uri.tryParse(endpoint);
    if (uri == null || uri.scheme != 'http' ||
        uri.host != '127.0.0.1' || uri.port != 8768 ||
        uri.path != '/admin/preflight' || uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty || uri.userInfo.isNotEmpty) {
      throw StateError('Passerelle locale ADMIN TEST non configurée.');
    }
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (user == null || token == null || token.isEmpty) {
      throw StateError('Session Firebase ADMIN requise.');
    }
    final response = await http.post(
      uri.replace(path: '/admin/card-test-status'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: '{}',
    ).timeout(const Duration(seconds: 30));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Statut CARTE TEST illisible.');
    }
    if (response.statusCode != 200 || decoded['ok'] != true) {
      throw StateError(decoded['error']?.toString() ??
          'Cycle CARTE TEST indisponible.');
    }
    if (decoded['testOnly'] != true || decoded['fixtureOnly'] != true ||
        decoded['action'] != 'none' ||
        decoded['firestoreProject'] != 'sphot-c4-test-20261029' ||
        decoded['odooDatabase'] != 'sphot_publicitaire_checkout_test' ||
        decoded['stationCount'] != 2 ||
        decoded['expectedHtCents'] != 89800 ||
        decoded['expectedTtcCents'] != 107760 ||
        decoded['prodFirestoreWritten'] != false ||
        decoded['odooWritten'] != false ||
        decoded['activationAttempted'] != false) {
      throw const FormatException('Contrat CARTE TEST incompatible.');
    }
    if (decoded['activationVerified'] == true &&
        (decoded['stripeVerified'] != true ||
        decoded['paymentStatus'] != 'paid' ||
        decoded['activationBasis'] != 'stripe_verified' ||
        decoded['nextGate'] != 'TEST_CYCLE_COMPLETE')) {
      throw const FormatException('Preuve d’activation CARTE TEST invalide.');
    }
    return decoded;
  }
}
