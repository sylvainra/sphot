import 'package:latlong2/latlong.dart';

/// Les cinq niveaux SPHOT sont utilisables dans TOUS les pays.
/// Ils définissent des distances, pas des frontières administratives.
enum AdvertiserTerritoryLevel {
  commune,
  intercommunalite,
  departement,
  region,
  national,
}

extension AdvertiserTerritoryLevelUi on AdvertiserTerritoryLevel {
  String get label => switch (this) {
        AdvertiserTerritoryLevel.commune => 'COMMUNE',
        AdvertiserTerritoryLevel.intercommunalite => 'INTERCOMMUNALITÉ',
        AdvertiserTerritoryLevel.departement => 'DÉPARTEMENT',
        AdvertiserTerritoryLevel.region => 'RÉGION',
        AdvertiserTerritoryLevel.national => 'NATIONAL',
      };

  String get storageKey => name;

  /// Barème géographique indépendant des tarifs, identique mondialement.
  /// Valeurs de travail à contrôler visuellement avant validation finale.
  double get radiusKm => switch (this) {
        AdvertiserTerritoryLevel.commune => 5,
        AdvertiserTerritoryLevel.intercommunalite => 20,
        AdvertiserTerritoryLevel.departement => 100,
        AdvertiserTerritoryLevel.region => 300,
        AdvertiserTerritoryLevel.national => 1000,
      };

  String get radiusLabel => '${radiusKm.toInt()} km';

  /// Zoom indicatif permettant de voir un cercle de cette échelle.
  double get suggestedZoom => switch (this) {
        AdvertiserTerritoryLevel.commune => 11.0,
        AdvertiserTerritoryLevel.intercommunalite => 9.2,
        AdvertiserTerritoryLevel.departement => 7.0,
        AdvertiserTerritoryLevel.region => 5.4,
        AdvertiserTerritoryLevel.national => 3.5,
      };
}

/// Un niveau géographique commercial, et non une division administrative.
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
        'code': code,
        'name': name,
        'radiusKm': radiusKm,
        'coverageModel': 'worldwide_radius_v1',
      };

  static AdvertiserTerritory? fromFirestore(Object? raw) {
    if (raw is! Map) return null;
    final levelValue = raw['level']?.toString() ?? '';
    final match = AdvertiserTerritoryLevel.values.where(
      (level) => level.storageKey == levelValue,
    );
    if (match.isEmpty) return null;
    // Les anciens documents territoriaux restent lisibles et non supprimés.
    final level = match.first;
    return AdvertiserTerritory(
      level: level,
      code: raw['coverageModel'] == 'worldwide_radius_v1'
          ? (raw['code']?.toString() ?? 'WORLD_${level.storageKey}')
          : 'WORLD_${level.storageKey}',
      name: 'Rayon de ${level.radiusLabel} autour du SPHOT',
    );
  }
}

class AdvertiserTerritoryOptions {
  const AdvertiserTerritoryOptions(this.options);
  final Map<AdvertiserTerritoryLevel, AdvertiserTerritory> options;

  AdvertiserTerritory? operator [](AdvertiserTerritoryLevel level) =>
      options[level];
}

/// Convertit la géométrie GeoJSON officielle en contours sur flutter_map.
class AdvertiserTerritoryGeometry {
  const AdvertiserTerritoryGeometry(this.polygons);
  final List<List<LatLng>> polygons;

  static AdvertiserTerritoryGeometry fromGeoJson(Object? raw) {
    if (raw is! Map) return const AdvertiserTerritoryGeometry([]);
    final geometry = raw['type'] == 'Feature' ? raw['geometry'] : raw;
    if (geometry is! Map) return const AdvertiserTerritoryGeometry([]);

    final type = geometry['type']?.toString();
    final coordinates = geometry['coordinates'];
    if (coordinates is! List) return const AdvertiserTerritoryGeometry([]);

    final polygons = <List<LatLng>>[];
    final List<dynamic> figures = type == 'Polygon'
        ? [coordinates]
        : type == 'MultiPolygon'
            ? coordinates
            : const [];

    for (final figure in figures) {
      if (figure is! List || figure.isEmpty) continue;
      // L'anneau externe de chaque polygone : aucun rayon fictif.
      final outerRing = figure.first;
      if (outerRing is! List) continue;
      final ring = <LatLng>[];
      for (final point in outerRing) {
        if (point is! List || point.length < 2) continue;
        final lng = point[0];
        final lat = point[1];
        if (lat is num && lng is num &&
            lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
          ring.add(LatLng(lat.toDouble(), lng.toDouble()));
        }
      }
      if (ring.length >= 3) polygons.add(ring);
    }
    return AdvertiserTerritoryGeometry(polygons);
  }
}



/// Les cinq rayons sont toujours disponibles, y compris hors de France.
/// Aucun accès réseau ni dépendance à geo.api.gouv.fr pour ce choix.
class AdvertiserTerritoryService {
  const AdvertiserTerritoryService();

  Future<AdvertiserTerritoryOptions> resolve(LatLng position) async {
    return AdvertiserTerritoryOptions({
      for (final level in AdvertiserTerritoryLevel.values)
        level: AdvertiserTerritory(
          level: level,
          code: 'WORLD_${level.storageKey}',
          name: 'Rayon de ${level.radiusLabel} autour du SPHOT',
        ),
    });
  }

  void dispose() {}
}
