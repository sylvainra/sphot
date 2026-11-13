import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final forms = <String, int>{
    'lib/pages/sauveteur/sauveteur_materiel_verification_page.dart': 1,
    // Le même formulaire sert aux catégories PHONIE, ROULANT et FLOTTANT.
    'lib/pages/sauveteur/sauveteur_materiel_category_verification_page.dart':
        3,
  };

  for (final entry in forms.entries) {
    test('Validation rouge pour les ${entry.value} catégorie(s) de ${entry.key}',
        () {
      final content = File(entry.key).readAsStringSync();

      expect(content.contains('bool _saved = false;'), isTrue);
      expect(content.contains('if (_saving || _saved) return;'), isTrue);
      expect(content.contains("decoded['success'] == true"), isTrue);
      expect(content.contains("decoded['entryId']"), isTrue);
      expect(content.contains('_saved = true;'), isTrue);
      expect(content.contains("'VÉRIFICATION ENREGISTRÉE'"), isTrue);
      expect(content.contains("'ENREGISTRER LA VÉRIFICATION'"), isTrue);
      expect(content.contains('disabledBackgroundColor: _saved'), isTrue);
      expect(content.contains('disabledForegroundColor: _saved'), isTrue);
      expect(content.contains('_red'), isTrue);
      expect(content.contains('Colors.white'), isTrue);
      expect(content.contains('_saving || _saved'), isTrue);
    });
  }

  test('La lecture main courante explique le refus serveur', () {
    final page =
        File('lib/pages/sauveteur/sauveteur_main_courante.dart')
            .readAsStringSync();
    expect(page.contains("failure['error']"), isTrue);
    expect(page.contains('main_courante_not_available'), isTrue);
    expect(page.contains('insufficient_role'), isTrue);
    expect(page.contains('response.statusCode'), isTrue);
    expect(page.contains("'sauveteurSessionToken':"), isTrue);
  });

  test('La lecture serveur conserve les droits du sauveteur ordinaire', () {
    final functions = File('functions/index.js').readAsStringSync();
    final begin = functions.indexOf('exports.getSauveteurMainCourante =');
    final end = functions.indexOf('exports.', begin + 30);
    expect(begin, greaterThanOrEqualTo(0));
    expect(end, greaterThan(begin));
    final route = functions.substring(begin, end);
    expect(route.contains('resolveSauveteurSession'), isTrue);
    expect(route.contains('context.realtimeSpotIds.includes(spotId)'), isTrue);
    expect(route.contains('entry.visibility !== "restricted"'), isTrue);
    expect(route.contains('|| canSeeRestricted'), isTrue);
    expect(route.contains('mainCouranteAccessLogs'), isTrue);
    // La consultation n'est jamais réservée aux chefs et adjoints.
    expect(route.contains('if (!context.canManageRestrictedOperationalData)'),
        isFalse);
  });
}
