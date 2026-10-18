import 'package:flutter_test/flutter_test.dart';
import 'package:bathing_spots_app/web/advertiser/services/advertiser_territory_service.dart';

void main() {
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
