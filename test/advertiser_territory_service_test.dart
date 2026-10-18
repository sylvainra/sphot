import 'dart:convert';

import 'package:bathing_spots_app/web/advertiser/services/advertiser_country_boundary_service.dart';
import 'package:bathing_spots_app/web/advertiser/services/advertiser_territory_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

Map<String, dynamic> _feature(
  String iso,
  String country,
  List<List<num>> ring,
) =>
    {
      'type': 'Feature',
      'properties': {'ADM0_A3': iso, 'ADMIN': country},
      'geometry': {
        'type': 'Polygon',
        'coordinates': [ring],
      },
    };

Map<String, dynamic> _world() => {
      'type': 'FeatureCollection',
      'features': [
        _feature('FRA', 'France', [
          [-3, 44], [8, 44], [8, 52], [-3, 52], [-3, 44]
        ]),
        _feature('FRA', 'France', [
          [-53, 3], [-51, 3], [-51, 5], [-53, 5], [-53, 3]
        ]),
        _feature('BRA', 'Brazil', [
          [-75, -35], [-35, -35], [-35, 5], [-75, 5], [-75, -35]
        ]),
        _feature('JPN', 'Japan', [
          [129, 30], [146, 30], [146, 46], [129, 46], [129, 30]
        ]),
      ],
    };

AdvertiserCountryBoundaryService _fakeBoundaries() =>
    AdvertiserCountryBoundaryService(
      client: MockClient((request) async =>
          http.Response(jsonEncode(_world()), 200)),
    );

void main() {
  test('cinq rayons inchangés et PAYS ENTIER en sixième position', () {
    final levels = AdvertiserTerritoryLevel.values;
    expect(
      levels.map((level) => level.label).toList(),
      ['5 km', '15 km', '50 km', '150 km', '300 km', 'PAYS ENTIER'],
    );
    expect(
      levels.map((level) => level.storageKey).toList(),
      [
        'radius_5km', 'radius_15km', 'radius_50km',
        'radius_150km', 'radius_300km', 'country',
      ],
    );
    expect(
      levels.where((level) => !level.isCountry)
          .map((level) => level.radiusKm).toList(),
      [5.0, 15.0, 50.0, 150.0, 300.0],
    );
  });

  test('détecte la France et le Brésil par la position du SPHOT', () async {
    final service = AdvertiserTerritoryService(
      countryService: _fakeBoundaries(),
    );
    final france = await service.resolve(const LatLng(46.5, 2));
    final brazil = await service.resolve(const LatLng(-20, -50));
    expect(france.options, hasLength(6));
    expect(brazil.options, hasLength(6));
    expect(france[AdvertiserTerritoryLevel.wholeCountry]?.code, 'FRA');
    expect(france[AdvertiserTerritoryLevel.wholeCountry]?.name, 'France');
    expect(brazil[AdvertiserTerritoryLevel.wholeCountry]?.code, 'BRA');
    expect(brazil[AdvertiserTerritoryLevel.wholeCountry]?.name, 'Brazil');
  });

  test('plusieurs composantes du même pays sont conservées', () async {
    final boundaries = _fakeBoundaries();
    final france = await boundaries.findByIso3('FRA');
    expect(france?.polygons, hasLength(2));
    expect(france?.contains(const LatLng(4, -52)), isTrue);
  });

  test('le cadrage de France évite la Guyane pour un SPHOT métropolitain', () async {
    final boundary = await _fakeBoundaries().findByIso3('FRA');
    expect(boundary, isNotNull);

    final focus = boundary!.focusPointsNear(const LatLng(46.5, -1.5));
    expect(focus, isNotEmpty);
    expect(
      focus.every((point) => point.latitude > 40 && point.longitude > -10),
      isTrue,
    );
    // L'ensemble du pays (y compris les autres territoires) reste conservé.
    expect(boundary.polygons, hasLength(2));
  });

  test('le cadrage suit la composante locale pour un SPHOT en Guyane', () async {
    final boundary = await _fakeBoundaries().findByIso3('FRA');
    final focus = boundary!.focusPointsNear(const LatLng(4, -52));
    expect(focus, isNotEmpty);
    expect(
      focus.every((point) => point.latitude < 10 && point.longitude < -40),
      isTrue,
    );
  });

  test('SPHOT proche du littoral : cadre la composante la plus proche', () async {
    final boundary = await _fakeBoundaries().findByIso3('FRA');
    // Juste à l'ouest du contour simplifié métropolitain.
    final focus = boundary!.focusPointsNear(const LatLng(46.5, -3.01));
    expect(focus.first.latitude, 44);
    expect(focus.first.longitude, -3);
  });

  test('aucun pays n’est attribué arbitrairement en haute mer', () async {
    final service = AdvertiserTerritoryService(
      countryService: _fakeBoundaries(),
    );
    final result = await service.resolve(const LatLng(-20, -120));
    expect(result.options, hasLength(5));
    expect(result[AdvertiserTerritoryLevel.wholeCountry], isNull);
    expect(result[AdvertiserTerritoryLevel.radius300km], isNotNull);
  });

  test('PAYS ENTIER conserve son code ISO3 dans Firestore', () {
    const chosen = AdvertiserTerritory(
      level: AdvertiserTerritoryLevel.wholeCountry,
      code: 'JPN',
      name: 'Japan',
    );
    final saved = chosen.toFirestore();
    expect(saved['level'], 'country');
    expect(saved['countryIso3'], 'JPN');
    expect(saved.containsKey('radiusKm'), isFalse);
    expect(saved['coverageModel'], 'country_whole_v1');
    final restored = AdvertiserTerritory.fromFirestore(saved);
    expect(restored?.isWholeCountry, isTrue);
    expect(restored?.code, 'JPN');
    expect(restored?.name, 'Japan');
  });

  test('l’ancien rayon 500 km ne devient jamais PAYS ENTIER', () {
    expect(
      AdvertiserTerritory.fromFirestore({
        'level': 'radius_500km',
        'radiusKm': 500,
        'coverageModel': 'worldwide_radius_v2',
      }),
      isNull,
    );
    expect(
      AdvertiserTerritory.fromFirestore({
        'level': 'national',
        'radiusKm': 1000,
        'coverageModel': 'worldwide_radius_v1',
      }),
      isNull,
    );
  });

  test('les anciens rayons compatibles restent lisibles', () {
    for (final km in [5, 15, 50, 150, 300]) {
      final restored = AdvertiserTerritory.fromFirestore({
        'level': 'commune',
        'radiusKm': km,
        'coverageModel': 'worldwide_radius_v1',
      });
      expect(restored?.radiusKm, km.toDouble());
      expect(restored?.isWholeCountry, isFalse);
    }
  });

  test('GeoJSON invalide rejeté, aucun pays inventé', () {
    expect(
      () => AdvertiserCountryBoundaryService.parseFeatureCollection(null),
      throwsFormatException,
    );
    expect(
      AdvertiserTerritory.fromFirestore({
        'level': 'country',
        'code': '???',
        'name': 'Pays',
        'coverageModel': 'country_whole_v1',
      }),
      isNull,
    );
  });

  test('les cinq rayons restent accessibles si la source tombe', () async {
    final source = AdvertiserCountryBoundaryService(
      client: MockClient((_) async => http.Response('erreur', 503)),
    );
    final choices = await AdvertiserTerritoryService(
      countryService: source,
    ).resolve(const LatLng(48.8, 2.3));
    expect(choices.options, hasLength(5));
    expect(choices[AdvertiserTerritoryLevel.wholeCountry], isNull);
  });
}
