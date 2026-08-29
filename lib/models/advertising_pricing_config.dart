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
    'premium': 'FICHE SPHOT PREMIUM',
    'pack': 'PACK VISIBILITÉ TOTALE',
  };

  static const radiusChoices = <double>[0, 0.05, 0.1, 0.15, 0.2];

  static Map<String, dynamic> defaults() {
    return {
      'basePrices': <String, num>{
        '1 semaine': 49,
        '2 semaines': 99,
        '1 mois': 149,
        '2 mois': 249,
        '6 mois': 599,
        '1 an': 999,
      },
      'visibilityMultipliers': <String, num>{
        'map': 1,
        'premium': 2,
        'pack': 2.5,
      },
      'radiusMultipliers': <String, num>{
        '0': 1,
        '0.05': 1.15,
        '0.1': 1.3,
        '0.15': 1.45,
        '0.2': 1.6,
      },
      'nationalFlatPrices': <String, Map<String, num>>{
        'map': <String, num>{
          '1 semaine': 250,
          '2 semaines': 490,
          '1 mois': 790,
          '2 mois': 1390,
          '6 mois': 2900,
          '1 an': 4900,
        },
        'premium': <String, num>{
          '1 semaine': 450,
          '2 semaines': 890,
          '1 mois': 1490,
          '2 mois': 2600,
          '6 mois': 5400,
          '1 an': 8900,
        },
        'pack': <String, num>{
          '1 semaine': 590,
          '2 semaines': 1190,
          '1 mois': 1990,
          '2 mois': 3500,
          '6 mois': 7400,
          '1 an': 11900,
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
    final value = radiusKm.toDouble();
    if (value <= 0) return 'SPHOT ONLY';
    if (value < 1) return '${(value * 1000).round()} m';
    return '${radiusKey(value).replaceAll('.', ',')} km';
  }

  static int localPrice({
    required Map<String, dynamic> pricing,
    required String durationLabel,
    required String visibilityType,
    required num radiusKm,
  }) {
    final defaults = AdvertisingPricingConfig.defaults();
    final basePrices = _map(pricing['basePrices']);
    final visibilityMultipliers = _map(pricing['visibilityMultipliers']);
    final radiusMultipliers = _map(pricing['radiusMultipliers']);
    final radius = radiusKey(radiusKm);
    final base = _number(
      basePrices[durationLabel],
      _map(defaults['basePrices'])[durationLabel],
    );
    final visibility = _number(
      visibilityMultipliers[visibilityType],
      _map(defaults['visibilityMultipliers'])[visibilityType],
    );
    final radiusMultiplier = _number(
      radiusMultipliers[radius],
      _map(defaults['radiusMultipliers'])[radius],
    );
    return (base * visibility * radiusMultiplier).round();
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  static num _number(dynamic value, dynamic fallback) {
    if (value is num) return value;
    if (fallback is num) return fallback;
    return 1;
  }
}
