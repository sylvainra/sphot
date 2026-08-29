class AdvertisingPricingConfig {
  const AdvertisingPricingConfig._();

  static const durations = <String>[
    '15 jours',
    '1 mois',
    '3 mois',
    '6 mois',
    '12 mois',
  ];

  static const visibilityLabels = <String, String>{
    'map': 'CARTE SPHOT',
    'premium': 'FICHE SPHOT PREMIUM',
    'pack': 'PACK VISIBILITÉ TOTALE',
  };

  static const radiusChoices = <double>[0.5, 2, 5, 10, 20, 50, 100];

  static Map<String, dynamic> defaults() {
    return {
      'basePrices': <String, num>{
        '15 jours': 99,
        '1 mois': 149,
        '3 mois': 349,
        '6 mois': 599,
        '12 mois': 999,
      },
      'visibilityMultipliers': <String, num>{
        'map': 1,
        'premium': 2,
        'pack': 2.5,
      },
      'radiusMultipliers': <String, num>{
        '0.5': 1,
        '2': 1.5,
        '5': 2,
        '10': 2.8,
        '20': 3.8,
        '50': 5.5,
        '100': 8,
      },
      'nationalFlatPrices': <String, Map<String, num>>{
        'map': <String, num>{
          '15 jours': 490,
          '1 mois': 790,
          '3 mois': 1900,
          '6 mois': 2900,
          '12 mois': 4900,
        },
        'premium': <String, num>{
          '15 jours': 890,
          '1 mois': 1490,
          '3 mois': 3400,
          '6 mois': 5400,
          '12 mois': 8900,
        },
        'pack': <String, num>{
          '15 jours': 1190,
          '1 mois': 1990,
          '3 mois': 4500,
          '6 mois': 7400,
          '12 mois': 11900,
        },
      },
    };
  }

  static String radiusKey(num radiusKm) {
    final value = radiusKm.toDouble();
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  static String radiusLabel(num radiusKm) {
    return '${radiusKey(radiusKm).replaceAll('.', ',')} km';
  }
}
