import 'package:flutter/material.dart';

/// La création contractuelle des commandes est momentanément désactivée.
///
/// L'ancien parcours calculait un prix unique par poste et écrivait une
/// commande directement depuis Flutter. Cela ne garantit ni la grille
/// tarifaire publiée, ni les CGV, ni une confirmation contractuelle sûre.
/// La nouvelle commande sera réalisée par une fonction serveur validant
/// le montant, l'engagement, les taxes et la version des CGV.
class AdminSubscriptionOrderService {
  static Future<void> showAndSubmit({
    required BuildContext context,
    required String adminUid,
    required Map<String, dynamic> data,
  }) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('VALIDATION DE COMMANDE EN PRÉPARATION'),
        content: const Text(
          'La simulation de la grille tarifaire publiée est disponible. '
          'La confirmation contractuelle reste désactivée pendant '
          'la mise en conformité de la facturation et des CGV. '
          'Aucune commande ni aucun paiement ne sera créé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('FERMER'),
          ),
        ],
      ),
    );
  }
}
