import 'package:bathing_spots_app/web/advertiser/services/advertiser_territory_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('les six rayons apparaissent seuls et dans le bon ordre', () {
    expect(
      AdvertiserTerritoryLevel.values.map((level) => level.label).toList(),
      ['5 km', '15 km', '50 km', '150 km', '300 km', '500 km'],
    );
    expect(
      AdvertiserTerritoryLevel.values
          .map((level) => level.storageKey)
          .toList(),
      [
        'radius_5km',
        'radius_15km',
        'radius_50km',
        'radius_150km',
        'radius_300km',
        'radius_500km',
      ],
    );
  });

  test('tous les rayons sont positifs et croissants', () {
    final radii = AdvertiserTerritoryLevel.values
        .map((level) => level.radiusKm)
        .toList();
    expect(radii, [5.0, 15.0, 50.0, 150.0, 300.0, 500.0]);
    for (var i = 1; i < radii.length; i++) {
      expect(radii[i], greaterThan(radii[i - 1]));
    }
  });

  test('les six choix sont identiques dans cinq pays', () async {
    const service = AdvertiserTerritoryService();
    const points = [
      LatLng(46.4, -1.5), // France
      LatLng(40.7, -74), // États-Unis
      LatLng(35.7, 139.7), // Japon
      LatLng(-33.9, 151.2), // Australie
      LatLng(-23.5, -46.6), // Brésil
    ];
    for (final point in points) {
      final options = await service.resolve(point);
      expect(options.options, hasLength(6));
      expect(
        AdvertiserTerritoryLevel.values
            .map((level) => options[level]!.radiusKm)
            .toList(),
        [5.0, 15.0, 50.0, 150.0, 300.0, 500.0],
      );
    }
  });

  test('les six choix ont un zoom associé', () {
    for (final level in AdvertiserTerritoryLevel.values) {
      expect(level.suggestedZoom, greaterThan(0));
    }
  });

  test('le rayon sélectionné est conservé lors de la sérialisation', () {
    const territory = AdvertiserTerritory(
      level: AdvertiserTerritoryLevel.radius300km,
      code: 'WORLD_radius_300km',
      name: '300 km',
    );
    final document = territory.toFirestore();
    expect(document['level'], 'radius_300km');
    expect(document['radiusKm'], 300.0);
    expect(document['coverageModel'], 'worldwide_radius_v2');

    final restored = AdvertiserTerritory.fromFirestore(document);
    expect(restored?.level, territory.level);
    expect(restored?.radiusKm, territory.radiusKm);
    expect(restored?.name, '300 km');
  });

  test('les six niveaux se rechargent depuis Firestore', () {
    for (final level in AdvertiserTerritoryLevel.values) {
      final data = AdvertiserTerritory(
        level: level,
        code: 'WORLD_${level.storageKey}',
        name: level.label,
      ).toFirestore();
      expect(AdvertiserTerritory.fromFirestore(data)?.level, level);
    }
  });

  test('les anciens rayons identiques sont lisibles sans conversion', () {
    final saved = AdvertiserTerritory.fromFirestore({
      'level': 'commune',
      'radiusKm': 5,
      'coverageModel': 'worldwide_radius_v1',
      'code': 'WORLD_commune',
      'name': 'Ancien périmètre',
    });
    expect(saved?.radiusKm, 5.0);
    expect(saved?.level, AdvertiserTerritoryLevel.radius5km);
  });

  test('aucune conversion arbitraire des anciens niveaux administratifs', () {
    expect(
      AdvertiserTerritory.fromFirestore({
        'level': 'region',
        'radiusKm': 1000,
        'coverageModel': 'worldwide_radius_v1',
      }),
      isNull,
    );
    expect(
      AdvertiserTerritory.fromFirestore({
        'level': 'commune',
        'code': '85000',
        'name': 'Commune historique',
      }),
      isNull,
    );
  });

  test('les valeurs inconnues restent rejetées', () {
    expect(AdvertiserTerritory.fromFirestore(null), isNull);
    expect(AdvertiserTerritory.fromFirestore({}), isNull);
    expect(AdvertiserTerritory.fromFirestore({'level': 'incorrect'}), isNull);
  });
}
