import 'package:bathing_spots_app/web/advertiser/models/diffusion_preview_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aucune zone sélectionnée au départ', () {
    const selection = DiffusionPlacementSelection();
    expect(selection.onMap, isFalse);
    expect(selection.inSpotPanels, isFalse);
    expect(selection.type, isNull);
  });

  test('CARTE SPHOT seule correspond au placement sur la carte', () {
    const initial = DiffusionPlacementSelection();
    final selection = initial.toggle(DiffusionPlacement.map);
    expect(selection.type, DiffusionPreviewType.map);
    expect(selection.onMap, isTrue);
    expect(selection.inSpotPanels, isFalse);
  });

  test('FICHES SPHOT seules correspondent aux six rubriques', () {
    const initial = DiffusionPlacementSelection();
    final selection = initial.toggle(DiffusionPlacement.spotPanels);
    expect(selection.type, DiffusionPreviewType.premium);
    expect(selection.onMap, isFalse);
    expect(selection.inSpotPanels, isTrue);
  });

  test('les deux zones réunies constituent le pack', () {
    const initial = DiffusionPlacementSelection();
    final selection = initial
        .toggle(DiffusionPlacement.map)
        .toggle(DiffusionPlacement.spotPanels);
    expect(selection.type, DiffusionPreviewType.pack);
    expect(selection.onMap, isTrue);
    expect(selection.inSpotPanels, isTrue);
  });

  test('décocher la carte à partir du pack conserve les volets', () {
    final selection = DiffusionPlacementSelection.fromType(
      DiffusionPreviewType.pack,
    ).toggle(DiffusionPlacement.map);
    expect(selection.type, DiffusionPreviewType.premium);
  });

  test('décocher les volets à partir du pack conserve la carte', () {
    final selection = DiffusionPlacementSelection.fromType(
      DiffusionPreviewType.pack,
    ).toggle(DiffusionPlacement.spotPanels);
    expect(selection.type, DiffusionPreviewType.map);
  });

  test('la lecture des valeurs historiques map, premium, pack est stable', () {
    for (final type in DiffusionPreviewType.values) {
      expect(DiffusionPlacementSelection.fromType(type).type, type);
    }
  });

  test('désélectionner la dernière zone revient à aucune sélection', () {
    const initial = DiffusionPlacementSelection();
    final selection = initial
        .toggle(DiffusionPlacement.map)
        .toggle(DiffusionPlacement.map);
    expect(selection.type, isNull);
  });
}
