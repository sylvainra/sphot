import 'package:bathing_spots_app/web/super_admin/services/advertiser_radius_pricing_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final complete = {
    for (var z = 0; z < 6; z++)
      for (var o = 0; o < 3; o++)
        for (var d = 0; d < 6; d++)
          '$z:$o:$d': (100 + z * 100 + o * 10 + d).toString(),
  };

  test('le modèle contient six zones et dix-huit lignes, sans prix', () {
    final lines = AdvertiserRadiusPricingImport.blankTemplate.split('\n');
    expect(lines.length, 19);
    expect(lines[0], AdvertiserRadiusPricingImport.header);
    expect(lines.last.startsWith('PAYS ENTIER;PACK TOTAL;'), isTrue);
    expect(
      () => AdvertiserRadiusPricingImport.parse(
        AdvertiserRadiusPricingImport.blankTemplate,
      ),
      throwsFormatException,
    );
  });

  test('accepte exactement les 108 prix et conserve les indices', () {
    final csv = AdvertiserRadiusPricingImport.export(complete);
    final loaded = AdvertiserRadiusPricingImport.parse(csv);
    expect(loaded.length, 108);
    expect(loaded['0:0:0'], 100);
    expect(loaded['5:2:5'], 625);
  });

  test('refuse un prix absent et ne produit aucune grille partielle', () {
    final values = Map<String, String>.from(complete)..remove('4:1:2');
    final csv = AdvertiserRadiusPricingImport.export(values);
    expect(
      () => AdvertiserRadiusPricingImport.parse(csv),
      throwsFormatException,
    );
  });

  test('refuse un montant négatif ou décimal', () {
    for (final invalid in ['-5', '12,50', '12.50', '0', '10000001']) {
      final values = Map<String, String>.from(complete)
        ..['2:0:3'] = invalid;
      expect(
        () => AdvertiserRadiusPricingImport.parse(
          AdvertiserRadiusPricingImport.export(values),
        ),
        throwsFormatException,
      );
    }
  });

  test('refuse les lignes dupliquées', () {
    final csv = AdvertiserRadiusPricingImport.export(complete);
    final firstRow = csv.split('\n')[1];
    expect(
      () => AdvertiserRadiusPricingImport.parse('$csv\n$firstRow'),
      throwsFormatException,
    );
  });

  test('refuse un ancien rayon de 500 km et un pays non prévu', () {
    final csv = AdvertiserRadiusPricingImport.export(complete);
    for (final changed in ['500 km', 'NATIONAL']) {
      expect(
        () => AdvertiserRadiusPricingImport.parse(
          csv.replaceFirst('PAYS ENTIER', changed),
        ),
        throwsFormatException,
      );
    }
  });

  test('la référence Super Admin reste indépendante du tableau', () {
    final parsed = AdvertiserRadiusPricingImport.parse(
      AdvertiserRadiusPricingImport.export(complete),
    );
    expect(parsed.containsKey('5:2:5'), isTrue);
    expect(parsed.values.every((value) => value > 0), isTrue);
    expect(
      () => parsed['5:2:5'] = 1,
      throwsUnsupportedError,
    );
  });
}
