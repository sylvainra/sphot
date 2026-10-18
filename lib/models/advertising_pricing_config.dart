/// Libellés du parcours publicitaire et lecture des anciens dossiers.
/// Les prix sont EXCLUSIVEMENT calculés côté serveur à partir du
/// catalogue versionné commercialPricingMarkets/FR_ADVERTISER_RADIUS.
/// Aucun ancien tarif forfaitaire ou multiplicateur n'est autorisé ici.
class AdvertisingPricingConfig {
  const AdvertisingPricingConfig._();

  static const durations = <String>[
    '1 semaine',
    '2 semaines',
    '1 mois',
    '2 mois',
    '6 mois',
    '1 an',
  ];

  static const visibilityLabels = <String, String>{
    'map': 'CARTE SPHOT',
    'premium': 'FICHES SPHOT',
    'pack': 'PACK VISIBILITÉ TOTALE',
  };

  /// Uniquement pour RELIRE les demandes historiques, jamais pour
  /// proposer une nouvelle zone ni calculer un prix.
  static const radiusChoices = <double>[0, 0.05, 0.1, 0.15, 0.2];

  /// Affichage d'une ancienne demande uniquement.
  static String radiusLabel(num radiusKm) {
    final radius = radiusKm.toDouble();
    if (radius <= 0) return 'Ancien emplacement sans rayon';
    if (radius < 1) return '${(radius * 1000).round()} m (historique)';
    final label = radius == radius.roundToDouble()
        ? radius.toInt().toString()
        : radius.toString().replaceAll('.', ',');
    return '$label km';
  }
}
