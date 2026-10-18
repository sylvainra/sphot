import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:bathing_spots_app/web/advertiser/services/advertiser_territory_service.dart';

void main() {

  test('les cinq rayons sont disponibles dans chaque pays', () async {
    const service = AdvertiserTerritoryService();
    final locations = [
      const LatLng(46.4, -1.5),  // France
      const LatLng(40.7, -74.0), // États-Unis
      const LatLng(35.7, 139.7), // Japon
      const LatLng(-33.9, 151.2), // Australie
      const LatLng(0, 0), // Équateur
    ];
    for (final position in locations) {
      final choices = await service.resolve(position);
      expect(choices.options.length, 5);
      expect(
        AdvertiserTerritoryLevel.values
            .map((level) => choices[level]!.radiusKm)
            .toList(),
        [5.0, 20.0, 100.0, 300.0, 1000.0],
      );
      for (final level in AdvertiserTerritoryLevel.values) {
        expect(choices[level]!.code, 'WORLD_${level.storageKey}');
      }
    }
  });

  test('les cinq rayons sont strictement croissants et positifs', () {
    final radii = AdvertiserTerritoryLevel.values
        .map((level) => level.radiusKm)
        .toList();
    expect(radii.every((radius) => radius > 0), isTrue);
    for (var i = 1; i < radii.length; i++) {
      expect(radii[i], greaterThan(radii[i - 1]));
    }
  });

  test('le document conserve le niveau et son rayon mondial', () {
    const level = AdvertiserTerritoryLevel.region;
    const selected = AdvertiserTerritory(
      level: level,
      code: 'WORLD_region',
      name: 'Rayon de 300 km autour du SPHOT',
    );
    final data = selected.toFirestore();
    expect(data['radiusKm'], 300.0);
    expect(data['coverageModel'], 'worldwide_radius_v1');
    final restored = AdvertiserTerritory.fromFirestore(data);
    expect(restored?.level, level);
    expect(restored?.radiusKm, 300.0);
  });

  test('les anciens codes administratifs restent lisibles', () {
    final restored = AdvertiserTerritory.fromFirestore({
      'level': 'departement',
      'code': '85',
      'name': 'Vendée',
    });
    expect(restored?.level, AdvertiserTerritoryLevel.departement);
    expect(restored?.radiusKm, 100.0);
    expect(restored?.code, 'WORLD_departement');
  });

  test('les cinq niveaux territoriaux sont conservés dans l’ordre', () {
    expect(
      AdvertiserTerritoryLevel.values.map((v) => v.storageKey).toList(),
      ['commune', 'intercommunalite', 'departement', 'region', 'national'],
    );
  });

  test('le choix est archivé avec son code territorial officiel', () {
    const selection = AdvertiserTerritory(
      level: AdvertiserTerritoryLevel.intercommunalite,
      code: '248500191',
      name: 'Intercommunalité test',
    );
    expect(
      AdvertiserTerritory.fromFirestore(selection.toFirestore())?.code,
      '248500191',
    );
    expect(AdvertiserTerritory.fromFirestore(null), isNull);
    expect(
      AdvertiserTerritory.fromFirestore(
        {'level': 'radius', 'code': '0.1', 'name': 'Rayon'},
      ),
      isNull,
    );
  });

  test('les coordonnées GeoJSON sont longitude puis latitude', () {
    final geometry = AdvertiserTerritoryGeometry.fromGeoJson({
      'type': 'Feature',
      'geometry': {
        'type': 'Polygon',
        'coordinates': [
          [
            [-1.51, 46.40],
            [-1.50, 46.40],
            [-1.50, 46.41],
            [-1.51, 46.40],
          ],
        ],
      },
    });
    expect(geometry.polygons, hasLength(1));
    expect(geometry.polygons.single.first.latitude, closeTo(46.40, 0.001));
    expect(geometry.polygons.single.first.longitude, closeTo(-1.51, 0.001));
  });

  test('GeoJSON multipolygone prend les anneaux extérieurs', () {
    final geometry = AdvertiserTerritoryGeometry.fromGeoJson({
      'type': 'MultiPolygon',
      'coordinates': [
        [
          [
            [0, 0], [1, 0], [1, 1],
          ],
        ],
        [
          [
            [2, 2], [3, 2], [3, 3],
          ],
        ],
      ],
    });
    expect(geometry.polygons, hasLength(2));
  });

  test('aucune géométrie fictive pour territoire inconnu', () {
    expect(
      AdvertiserTerritoryGeometry.fromGeoJson(null).polygons,
      isEmpty,
    );
  });
}
