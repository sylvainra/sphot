import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Les cinq échelons validés pour la publicité française.
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
}

/// Une zone administrative reconnue, avec son code officiel.
class AdvertiserTerritory {
  const AdvertiserTerritory({
    required this.level,
    required this.code,
    required this.name,
  });

  final AdvertiserTerritoryLevel level;
  final String code;
  final String name;

  Map<String, String> toFirestore() => {
        'level': level.storageKey,
        'code': code,
        'name': name,
      };

  static AdvertiserTerritory? fromFirestore(Object? raw) {
    if (raw is! Map) return null;
    final levelValue = raw['level']?.toString() ?? '';
    final match = AdvertiserTerritoryLevel.values.where(
      (level) => level.storageKey == levelValue,
    );
    if (match.isEmpty) return null;
    final code = raw['code']?.toString().trim() ?? '';
    final name = raw['name']?.toString().trim() ?? '';
    if (code.isEmpty || name.isEmpty) return null;
    return AdvertiserTerritory(
      level: match.first,
      code: code,
      name: name,
    );
  }
}

/// Représente les différents territoires rattachés au même point.
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

/// API publique de découpage administratif : aucun document Firebase modifié.
class AdvertiserTerritoryService {
  AdvertiserTerritoryService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, dynamic>> _read(Uri uri) async {
    final response = await _client.get(uri).timeout(
      const Duration(seconds: 12),
    );
    if (response.statusCode != 200) {
      throw StateError('Découpage territorial indisponible (HTTP ${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Réponse territoriale incorrecte.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<String> _name(String kind, String code) async {
    if (code.isEmpty) return '';
    try {
      final response =
          await _read(Uri.https('geo.api.gouv.fr', '/$kind/$code'));
      return response['nom']?.toString().trim() ?? '';
    } catch (_) {
      // Un niveau indisponible ne doit pas bloquer les autres territoires.
      return '';
    }
  }

  Future<AdvertiserTerritoryOptions> resolve(LatLng position) async {
    final uri = Uri.https('geo.api.gouv.fr', '/communes', {
      'lat': position.latitude.toString(),
      'lon': position.longitude.toString(),
      'fields': 'nom,code,codeEpci,codeDepartement,codeRegion',
      'format': 'json',
    });
    final response = await _client.get(uri).timeout(
      const Duration(seconds: 12),
    );
    if (response.statusCode != 200) {
      throw StateError('Impossible de déterminer la commune.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty || decoded.first is! Map) {
      throw StateError('Aucune commune trouvée pour cet emplacement.');
    }
    final data = Map<String, dynamic>.from(decoded.first as Map);
    final communeCode = data['code']?.toString() ?? '';
    final communeName = data['nom']?.toString() ?? '';
    final epciCode = data['codeEpci']?.toString() ?? '';
    final departementCode = data['codeDepartement']?.toString() ?? '';
    final regionCode = data['codeRegion']?.toString() ?? '';
    if (communeCode.isEmpty || communeName.isEmpty) {
      throw const FormatException('Code commune manquant.');
    }

    final names = await Future.wait([
      _name('epcis', epciCode),
      _name('departements', departementCode),
      _name('regions', regionCode),
    ]);
    final items = <AdvertiserTerritoryLevel, AdvertiserTerritory>{
      AdvertiserTerritoryLevel.commune: AdvertiserTerritory(
        level: AdvertiserTerritoryLevel.commune,
        code: communeCode,
        name: communeName,
      ),
      if (epciCode.isNotEmpty && names[0].isNotEmpty)
        AdvertiserTerritoryLevel.intercommunalite: AdvertiserTerritory(
          level: AdvertiserTerritoryLevel.intercommunalite,
          code: epciCode,
          name: names[0],
        ),
      if (departementCode.isNotEmpty && names[1].isNotEmpty)
        AdvertiserTerritoryLevel.departement: AdvertiserTerritory(
          level: AdvertiserTerritoryLevel.departement,
          code: departementCode,
          name: names[1],
        ),
      if (regionCode.isNotEmpty && names[2].isNotEmpty)
        AdvertiserTerritoryLevel.region: AdvertiserTerritory(
          level: AdvertiserTerritoryLevel.region,
          code: regionCode,
          name: names[2],
        ),
      AdvertiserTerritoryLevel.national: const AdvertiserTerritory(
        level: AdvertiserTerritoryLevel.national,
        code: 'FR',
        name: 'France',
      ),
    };
    return AdvertiserTerritoryOptions(items);
  }

  Future<AdvertiserTerritoryGeometry> geometry(
    AdvertiserTerritory selection,
  ) async {
    if (selection.level == AdvertiserTerritoryLevel.national) {
      return const AdvertiserTerritoryGeometry([]);
    }
    final collection = switch (selection.level) {
      AdvertiserTerritoryLevel.commune => 'communes',
      AdvertiserTerritoryLevel.intercommunalite => 'epcis',
      AdvertiserTerritoryLevel.departement => 'departements',
      AdvertiserTerritoryLevel.region => 'regions',
      AdvertiserTerritoryLevel.national => 'regions',
    };
    final uri = Uri.https(
      'geo.api.gouv.fr',
      '/$collection/${selection.code}',
      {'format': 'geojson', 'geometry': 'contour'},
    );
    return AdvertiserTerritoryGeometry.fromGeoJson(await _read(uri));
  }

  void dispose() => _client.close();
}
