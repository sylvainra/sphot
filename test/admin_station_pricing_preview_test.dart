import 'package:flutter_test/flutter_test.dart';
import 'package:bathing_spots_app/web/admin/services/admin_station_pricing_preview.dart';

void main() {
  test('Longeville : 2 postes disponibles sans offre : simulation 2', () {
    final result = AdminStationPricingPreview.resolve(
      availableSpotIds: ['longe09', 'longe13'],
      subscription: {},
    );
    expect(result.availableCount, 2);
    expect(result.quotedCount, 2);
    expect(result.hasSavedSelection, false);
    expect(result.isValid, true);
  });

  test('Jard : compteur historique 2, mais 3 postes actuels sans offre', () {
    final result = AdminStationPricingPreview.resolve(
      availableSpotIds: ['jard01', 'jard09', 'jard13'],
      subscription: {'numberOfRescueStations': 2},
    );
    expect(result.availableCount, 3);
    expect(result.quotedCount, 3);
    expect(result.hasSavedSelection, false);
    expect(result.hasLegacyCountMismatch, true);
  });

  test('Offre explicite de 2 sur 3 postes : conserver la selection', () {
    final result = AdminStationPricingPreview.resolve(
      availableSpotIds: ['jard01', 'jard09', 'jard13'],
      subscription: {
        'numberOfRescueStations': 2,
        'selectedRescueStationIds': ['jard01', 'jard09'],
      },
    );
    expect(result.availableCount, 3);
    expect(result.quotedCount, 2);
    expect(result.hasSavedSelection, true);
    expect(result.isValid, true);
  });

  test('Offre obsolete : refuser de chiffrer des postes inexistants', () {
    final result = AdminStationPricingPreview.resolve(
      availableSpotIds: ['jard01', 'jard09', 'jard13'],
      subscription: {'selectedRescueStationIds': ['obsolete', 'jard09']},
    );
    expect(result.quotedCount, 1);
    expect(result.unmatchedSavedCount, 1);
    expect(result.isValid, false);
  });

  test('Zero postes : ne pas inventer de tarif', () {
    final result = AdminStationPricingPreview.resolve(
      availableSpotIds: [],
      subscription: {'numberOfRescueStations': 2},
    );
    expect(result.quotedCount, 0);
    expect(result.isValid, false);
  });
}
