import 'package:flutter/material.dart';

import 'map/app_info_page.dart';
import 'widgets/sphot_local_legal_draft_card.dart';

/// Aperçu de la page publique SPHOT partagée avec le parcours mobile.
/// Aucun Firebase, aucune session ni consentement n'est initialisé.
void main() {
  const enabled = bool.fromEnvironment(
    'SPHOT_PUBLIC_LEGAL_PREVIEW',
    defaultValue: false,
  );
  if (!enabled || !SphotLocalLegalDraftCard.available) {
    throw StateError('Aperçu CGU Public réservé au DEBUG localhost.');
  }

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SPHOT — CGU Grand Public (brouillon)',
      home: AppInfoPage(),
    ),
  );
}
