import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Même première décision administrative depuis les deux écrans Super Admin.
/// Le serveur authentifie l'auteur et conserve une preuve immuable.
/// Aucun essai, abonnement ou paiement n'est créé par cette décision.
class SuperAdminInitialApprovalService {
  const SuperAdminInitialApprovalService._();

  // Le circuit d'approbation réel n'est autorisé que dans sphot-ab80b.
  // Une compilation C4 TEST ne peut jamais envoyer son jeton vers ce serveur.
  static const String _productionEndpoint =
      'https://us-central1-sphot-ab80b.cloudfunctions.net/'
      'approveAdminInitialRequest';
  static const String _configuredEndpoint = String.fromEnvironment(
    'SPHOT_ADMIN_INITIAL_APPROVAL_URL',
  );

  static String _value(Object? value) => (value ?? '').toString().trim();

  static Future<bool> approve(BuildContext context, String requestId) async {
    try {
      if (Firebase.app().options.projectId != 'sphot-ab80b') {
        throw StateError('Première approbation réservée au projet SPHOT.');
      }
      final endpointUrl = _configuredEndpoint.isNotEmpty
          ? _configuredEndpoint : _productionEndpoint;
      if (endpointUrl != _productionEndpoint) {
        throw StateError(
          'Point de validation ADMIN non autorisé pour ce projet.',
        );
      }
      final endpoint = Uri.parse(endpointUrl);
      if (requestId.trim().isEmpty) {
        throw StateError('Identifiant de la demande ADMIN absent.');
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
      if (response.statusCode != 200) {
        final result = jsonDecode(response.body);
        final reason = result is Map ? _value(result['error']) : '';
        if (reason == 'ADMIN_SIREN_SIRET_TERRITORY_INVALID' ||
            reason == 'IDENTITE_ADMIN_INCOHERENTE') {
          throw StateError(
            'SIREN, SIRET ou territoire incohérent dans le dossier. '
            'Demander une correction des données avant approbation.',
          );
        }
        throw StateError(
          'Validation serveur refusée${reason.isEmpty ? "." : " : $reason"}',
        );
      }
      final result = jsonDecode(response.body);
      if (result is! Map || result['success'] != true) {
        throw StateError('Validation serveur non confirmée.');
      }
      return true;
    } catch (error) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('VALIDATION ADMIN NON EFFECTUÉE'),
            content: Text(error.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('FERMER'),
              ),
            ],
          ),
        );
      }
      return false;
    }
  }
}
