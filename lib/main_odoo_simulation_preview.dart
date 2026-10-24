import 'package:flutter/material.dart';

import 'web/advertiser/services/odoo_simulation_service.dart';
import 'web/advertiser/widgets/advertiser_payment_simulation_section.dart';
import 'web/shared/web_colors.dart';

/// Point d'entrée de démonstration locale du VRAI widget PAIEMENT CB.
/// À lancer uniquement dans Chrome en debug avec
/// --dart-define=SPHOT_ODOO_SIMULATION=true.
/// Ne dépend d'aucun compte Firebase ou abonnement Odoo.
void main() {
  runApp(const _OdooSimulationPreviewApp());
}

class _Choice {
  const _Choice(this.value, this.label);

  final String value;
  final String label;
}

class _OdooSimulationPreviewApp extends StatelessWidget {
  const _OdooSimulationPreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPHOT PUBLICITAIRE — PAIEMENT CB — TEST',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: WebColors.blue,
        scaffoldBackgroundColor: const Color(0xFFF3F6FA),
      ),
      home: OdooSimulationService.enabled
          ? const _OdooSimulationPreviewPage()
          : const Scaffold(
              body: Center(
                child: Text(
                  'Prévisualisation désactivée. Lancez Flutter en mode debug '
                  'avec --dart-define=SPHOT_ODOO_SIMULATION=true.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
    );
  }
}

class _OdooSimulationPreviewPage extends StatefulWidget {
  const _OdooSimulationPreviewPage();

  @override
  State<_OdooSimulationPreviewPage> createState() =>
      _OdooSimulationPreviewPageState();
}

class _OdooSimulationPreviewPageState
    extends State<_OdooSimulationPreviewPage> {
  static const _territories = <_Choice>[
    _Choice('radius_5km', '5 km'),
    _Choice('radius_15km', '15 km'),
    _Choice('radius_50km', '50 km'),
    _Choice('radius_150km', '150 km'),
    _Choice('radius_300km', '300 km'),
    _Choice('country', 'PAYS ENTIER'),
  ];
  static const _offers = <_Choice>[
    _Choice('map', 'CARTE SPHOT'),
    _Choice('premium', 'FICHES SPHOT'),
    _Choice('pack', 'PACK VISIBILITÉ TOTALE'),
  ];
  static const _durations = <_Choice>[
    _Choice('1 semaine', '1 semaine'),
    _Choice('2 semaines', '2 semaines'),
    _Choice('1 mois', '1 mois'),
    _Choice('2 mois', '2 mois'),
    _Choice('6 mois', '6 mois'),
    _Choice('1 an', '1 an'),
  ];

  String _territory = 'radius_5km';
  String _offer = 'pack';
  String _duration = '1 semaine';

  Widget _picker({
    required String label,
    required String value,
    required List<_Choice> values,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final item in values)
          DropdownMenuItem(value: item.value, child: Text(item.label)),
      ],
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: WebColors.blue,
        foregroundColor: Colors.white,
        title: const Text(
          'SPHOT PUBLICITAIRE · PAIEMENT CB · TEST LOCAL',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'PARCOURS D’ACHAT ODOO — SIMULATION',
                style: TextStyle(
                  color: WebColors.blue,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Cet aperçu utilise exactement le composant « PAIEMENT CB » '
                'du portail SPHOT Publicitaire. Aucun compte, SIRET, Odoo '
                'ou paiement réel n’est nécessaire. Modifiez les options '
                'ci-dessous pour essayer les différents tarifs fictifs.',
                style: TextStyle(color: Color(0xFF4B5F97), height: 1.4),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 680;
                  final pickers = <Widget>[
                    _picker(
                      label: 'RAYON',
                      value: _territory,
                      values: _territories,
                      onChanged: (next) => setState(() => _territory = next),
                    ),
                    _picker(
                      label: 'VISIBILITÉ',
                      value: _offer,
                      values: _offers,
                      onChanged: (next) => setState(() => _offer = next),
                    ),
                    _picker(
                      label: 'DURÉE',
                      value: _duration,
                      values: _durations,
                      onChanged: (next) => setState(() => _duration = next),
                    ),
                  ];
                  if (compact) {
                    return Column(
                      children: [
                        for (final picker in pickers) ...[
                          picker,
                          const SizedBox(height: 12),
                        ],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final picker in pickers) ...[
                        Expanded(child: picker),
                        if (picker != pickers.last) const SizedBox(width: 12),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              AdvertiserPaymentSimulationSection(
                key: ValueKey('$_territory-$_offer-$_duration'),
                territory: _territory,
                offer: _offer,
                duration: _duration,
                planningComplete: true,
                publishedPricingReference: null,
                publishedPayableExclTaxCents: 0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
