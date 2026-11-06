import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'web/advertiser/widgets/advertiser_legal_acceptance_section.dart';
import 'web/shared/web_colors.dart';
import 'widgets/sphot_local_legal_draft_card.dart';

/// Point d'entrée autonome pour la recette visuelle des CGV Publicitaire.
/// Pas d'initialisation Firebase, de session ou d'appel Odoo/Stripe.
void main() {
  const enabled = bool.fromEnvironment(
    'SPHOT_ADVERTISER_LEGAL_PREVIEW',
    defaultValue: false,
  );
  if (!kDebugMode || !enabled || !SphotLocalLegalDraftCard.available) {
    throw StateError('Aperçu Publicitaire réservé au DEBUG localhost.');
  }
  runApp(const _AdvertiserLegalPreview());
}

class _AdvertiserLegalPreview extends StatelessWidget {
  const _AdvertiserLegalPreview();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SPHOT PUBLICITAIRE — Validation juridique (brouillon)',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: WebColors.blue,
          scaffoldBackgroundColor: const Color(0xFFF3F6FA),
        ),
        home: Scaffold(
          appBar: AppBar(
            title: const Text('SPHOT PUBLICITAIRE · VALIDATIONS JURIDIQUES'),
            backgroundColor: WebColors.blue,
            foregroundColor: Colors.white,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'APERÇU LOCAL · BROUILLON 1.0 NON PUBLIÉ',
                      style: TextStyle(
                        color: WebColors.red,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 18),
                    AdvertiserLegalAcceptanceSection(
                      requestId: null,
                      requestStatus: 'draft',
                      readOnly: true,
                      draftOnly: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
