import 'package:latlong2/latlong.dart';

import 'advertiser_country_boundary_service.dart';

/// Cinq cercles universels, plus une couverture PAYS ENTIER.
/// Aucun nom administratif français dans le sélecteur.
enum AdvertiserTerritoryLevel {
  radius5km,
  radius15km,
  radius50km,
  radius150km,
  radius300km,
  wholeCountry,
}

extension AdvertiserTerritoryLevelUi on AdvertiserTerritoryLevel {
  bool get isCountry => this == AdvertiserTerritoryLevel.wholeCountry;

  double get radiusKm => switch (this) {
        AdvertiserTerritoryLevel.radius5km => 5,
        AdvertiserTerritoryLevel.radius15km => 15,
        AdvertiserTerritoryLevel.radius50km => 50,
        AdvertiserTerritoryLevel.radius150km => 150,
        AdvertiserTerritoryLevel.radius300km => 300,
        AdvertiserTerritoryLevel.wholeCountry => 0,
      };

  String get label => isCountry ? 'PAYS ENTIER' : '${radiusKm.toInt()} km';
  String get radiusLabel => label;
  String get storageKey =>
      isCountry ? 'country' : 'radius_${radiusKm.toInt()}km';

  double get suggestedZoom => switch (this) {
        AdvertiserTerritoryLevel.radius5km => 11.5,
        AdvertiserTerritoryLevel.radius15km => 10.5,
        AdvertiserTerritoryLevel.radius50km => 9,
        AdvertiserTerritoryLevel.radius150km => 7.3,
        AdvertiserTerritoryLevel.radius300km => 6.2,
        AdvertiserTerritoryLevel.wholeCountry => 4,
      };

  static AdvertiserTerritoryLevel? fromStorageKey(String? key) {
    for (final level in AdvertiserTerritoryLevel.values) {
      if (level.storageKey == key) return level;
    }
    return null;
  }

  static AdvertiserTerritoryLevel? fromRadiusKm(num? radius) {
    if (radius == null) return null;
    for (final level in AdvertiserTerritoryLevel.values) {
      if (!level.isCountry && radius.toDouble() == level.radiusKm) {
        return level;
      }
    }
    return null;
  }
}

class AdvertiserTerritory {
  const AdvertiserTerritory({
    required this.level,
    required this.code,
    required this.name,
  });

  final AdvertiserTerritoryLevel level;
  final String code;
  final String name;

  bool get isWholeCountry => level.isCountry;
  double get radiusKm => level.radiusKm;

  Map<String, Object> toFirestore() => isWholeCountry
      ? {
          'level': 'country',
          'code': code,
          'name': name,
          'countryIso3': code,
          'coverageModel': 'country_whole_v1',
          'boundarySource': 'Natural Earth (indicative 1:110m)',
        }
      : {
          'level': level.storageKey,
          'code': 'WORLD_${level.storageKey}',
          'name': level.label,
          'radiusKm': radiusKm,
          'coverageModel': 'worldwide_radius_v2',
        };

  static AdvertiserTerritory? fromFirestore(Object? raw) {
    if (raw is! Map) return null;
    final storedLevel = raw['level']?.toString();
    final model = raw['coverageModel']?.toString();
    if (storedLevel == 'country') {
      final code = (raw['countryIso3'] ?? raw['code'] ?? '')
          .toString()
          .toUpperCase();
      final name = (raw['name'] ?? '').toString().trim();
      if (model != 'country_whole_v1' ||
          !RegExp(r'^[A-Z]{3}$').hasMatch(code) ||
          name.isEmpty) {
        return null;
      }
      return AdvertiserTerritory(
        level: AdvertiserTerritoryLevel.wholeCountry,
        code: code,
        name: name,
      );
    }

    var level = AdvertiserTerritoryLevelUi.fromStorageKey(storedLevel);
    if (level == null && model == 'worldwide_radius_v1') {
      final rawRadius = raw['radiusKm'];
      if (rawRadius is num) {
        level = AdvertiserTerritoryLevelUi.fromRadiusKm(rawRadius);
      }
    }
    // Un ancien rayon de 500 km ne devient jamais un pays entier
    // automatiquement : une nouvelle sélection explicite est exigée.
    if (level == null || level.isCountry) return null;
    return AdvertiserTerritory(
      level: level,
      code: 'WORLD_${level.storageKey}',
      name: level.label,
    );
  }
}

class AdvertiserTerritoryOptions {
  const AdvertiserTerritoryOptions(this.options);
  final Map<AdvertiserTerritoryLevel, AdvertiserTerritory> options;

  AdvertiserTerritory? operator [](AdvertiserTerritoryLevel level) =>
      options[level];
}

class AdvertiserTerritoryService {
  AdvertiserTerritoryService({AdvertiserCountryBoundaryService? countryService})
      : _countryService =
            countryService ?? AdvertiserCountryBoundaryService();

  final AdvertiserCountryBoundaryService _countryService;

  Future<AdvertiserTerritoryOptions> resolve(LatLng position) async {
    final available = <AdvertiserTerritoryLevel, AdvertiserTerritory>{
      for (final level in AdvertiserTerritoryLevel.values)
        if (!level.isCountry)
          level: AdvertiserTerritory(
            level: level,
            code: 'WORLD_${level.storageKey}',
            name: level.label,
          ),
    };
    try {
      final country = await _countryService.findAt(position);
      if (country != null) {
        available[AdvertiserTerritoryLevel.wholeCountry] =
            AdvertiserTerritory(
          level: AdvertiserTerritoryLevel.wholeCountry,
          code: country.iso3,
          name: country.name,
        );
      }
    } catch (_) {
      // Les cinq rayons demeurent accessibles en cas de panne réseau.
      // Ne jamais inventer de pays en cas de frontière indisponible.
    }
    return AdvertiserTerritoryOptions(available);
  }

  void dispose() {}
}
