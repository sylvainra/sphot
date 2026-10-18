import 'package:latlong2/latlong.dart';

/// Six rayons mondiaux indépendants des subdivisions administratives.
/// Les montants HT ne sont PAS calculés à partir de ces distances.
enum AdvertiserTerritoryLevel {
  radius5km,
  radius15km,
  radius50km,
  radius150km,
  radius300km,
  radius500km,
}

extension AdvertiserTerritoryLevelUi on AdvertiserTerritoryLevel {
  double get radiusKm => switch (this) {
        AdvertiserTerritoryLevel.radius5km => 5,
        AdvertiserTerritoryLevel.radius15km => 15,
        AdvertiserTerritoryLevel.radius50km => 50,
        AdvertiserTerritoryLevel.radius150km => 150,
        AdvertiserTerritoryLevel.radius300km => 300,
        AdvertiserTerritoryLevel.radius500km => 500,
      };

  String get label => '${radiusKm.toInt()} km';
  String get radiusLabel => label;

  String get storageKey => 'radius_${radiusKm.toInt()}km';

  /// Le zoom change uniquement la présentation du cercle sur la carte.
  double get suggestedZoom => switch (this) {
        AdvertiserTerritoryLevel.radius5km => 11.5,
        AdvertiserTerritoryLevel.radius15km => 10.5,
        AdvertiserTerritoryLevel.radius50km => 9.0,
        AdvertiserTerritoryLevel.radius150km => 7.3,
        AdvertiserTerritoryLevel.radius300km => 6.2,
        AdvertiserTerritoryLevel.radius500km => 5.5,
      };

  static AdvertiserTerritoryLevel? fromRadiusKm(num? value) {
    if (value == null) return null;
    for (final level in AdvertiserTerritoryLevel.values) {
      if (level.radiusKm == value.toDouble()) return level;
    }
    return null;
  }

  static AdvertiserTerritoryLevel? fromStorageKey(String? value) {
    for (final level in AdvertiserTerritoryLevel.values) {
      if (level.storageKey == value) return level;
    }
    return null;
  }
}

/// Choix d'une portée kilométrique centré sur la position du SPHOT.
class AdvertiserTerritory {
  const AdvertiserTerritory({
    required this.level,
    required this.code,
    required this.name,
  });

  final AdvertiserTerritoryLevel level;
  final String code;
  final String name;

  double get radiusKm => level.radiusKm;

  Map<String, Object> toFirestore() => {
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

    var level = AdvertiserTerritoryLevelUi.fromStorageKey(storedLevel);
    if (level == null) {
      // Les dossiers antérieurs restent inchangés dans Firestore.
      // On ne transpose jamais arbitrairement un ancien territoire en km.
      // Seuls les rayons historiques EXACTEMENT identiques sont relus.
      final rawRadius = raw['radiusKm'];
      if (rawRadius is num && model == 'worldwide_radius_v1') {
        level = AdvertiserTerritoryLevelUi.fromRadiusKm(rawRadius);
      }
    }
    if (level == null) return null;

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

/// Choix identiques pour toutes les coordonnées, sans appel à une API
/// française et sans filtrage par frontières nationales.
class AdvertiserTerritoryService {
  const AdvertiserTerritoryService();

  Future<AdvertiserTerritoryOptions> resolve(LatLng position) async {
    return AdvertiserTerritoryOptions({
      for (final level in AdvertiserTerritoryLevel.values)
        level: AdvertiserTerritory(
          level: level,
          code: 'WORLD_${level.storageKey}',
          name: level.label,
        ),
    });
  }

  void dispose() {}
}
