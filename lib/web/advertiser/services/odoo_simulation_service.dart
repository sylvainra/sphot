import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Pont HTTP exclusivement local vers le simulateur JavaScript.
/// Aucun appel Odoo, Stripe, Firebase ou paiement réel n'est possible ici.
class OdooSimulationResult {
  const OdooSimulationResult({
    required this.scenario,
    required this.simulation,
  });

  final Map<String, dynamic> scenario;
  final Map<String, dynamic> simulation;

  factory OdooSimulationResult.fromJson(Map<String, dynamic> data) {
    final rawScenario = data['scenario'];
    final rawSimulation = data['simulation'];
    if (data['ok'] != true ||
        data['mode'] != 'SIMULATION_ONLY' ||
        rawScenario is! Map ||
        rawSimulation is! Map) {
      throw const FormatException('Réponse de simulation incorrecte.');
    }
    final simulation = Map<String, dynamic>.from(rawSimulation);
    if (simulation['mode'] != 'SIMULATION_ONLY' ||
        simulation['persisted'] != false ||
        simulation['odooApiCalled'] != false ||
        simulation['paymentProofVerified'] != false ||
        simulation['campaignActivationAllowed'] != false) {
      throw const FormatException('La réponse n’est pas une simulation isolée.');
    }
    return OdooSimulationResult(
      scenario: Map<String, dynamic>.from(rawScenario),
      simulation: simulation,
    );
  }
}

class OdooSimulationService {
  const OdooSimulationService();

  static const bool enabled = kDebugMode && bool.fromEnvironment(
    'SPHOT_ODOO_SIMULATION',
    defaultValue: false,
  );

  // Uniquement sur l'ordinateur du développeur ; jamais sphot.app.
  static const String endpoint = 'http://127.0.0.1:8765/purchase';

  Future<OdooSimulationResult> perform({
    required String action,
    required String sessionKey,
    String? territory,
    String? offer,
    String? duration,
    String? outcome,
    String? attemptKey,
  }) async {
    if (!enabled) {
      throw StateError('Simulation désactivée hors développement local.');
    }
    final body = <String, dynamic>{
      'action': action,
      'sessionKey': sessionKey,
      if (action == 'create') ...{
        'territory': territory,
        'offer': offer,
        'duration': duration,
      },
      if (action == 'payment') ...{
        'outcome': outcome,
        'attemptKey': attemptKey,
      },
    };

    late http.Response response;
    try {
      response = await http.post(
        Uri.parse(endpoint),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw StateError('Le serveur de simulation local ne répond pas.');
    } catch (error) {
      throw StateError(
        'Passerelle locale indisponible. Démarrez le serveur de test '
        'SPHOT/Odoo sur cet ordinateur. ($error)',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const FormatException('Réponse JSON locale illisible.');
    }
    if (decoded is! Map) {
      throw const FormatException('Réponse locale inattendue.');
    }
    final data = Map<String, dynamic>.from(decoded);
    if (response.statusCode != 200) {
      throw StateError(
        data['error']?.toString() ??
            'Erreur de simulation (HTTP ${response.statusCode}).',
      );
    }
    return OdooSimulationResult.fromJson(data);
  }
}
