import 'package:flutter/material.dart';

import 'pages/sauveteur/sauveteur_legal_acceptance_page.dart';
import 'widgets/sphot_local_legal_draft_card.dart';

/// Prévisualisation locale de la véritable page juridique SPHOT SAUVETEUR.
/// Sans Firebase.initializeApp, sans compte, sans écriture ni validation.
void main() {
  const enabled = bool.fromEnvironment(
    'SPHOT_SAUVETEUR_LEGAL_PREVIEW',
    defaultValue: false,
  );
  if (!enabled || !SphotLocalLegalDraftCard.available) {
    throw StateError('Aperçu Sauveteur réservé à Flutter DEBUG sur localhost.');
  }

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SPHOT SAUVETEUR — CGU et charte (brouillons)',
      home: const SauveteurLegalAcceptancePage(
        login: 'APERÇU LOCAL',
        territoireId: '',
        userRole: 'sauveteur',
        sphotMode: 'OFF',
        sphotModeReason: 'aperçu juridique uniquement',
        sauveteurSessionToken: '',
        postesAffectes: <String>[],
        canManageRestrictedOperationalData: false,
      ),
    ),
  );
}
