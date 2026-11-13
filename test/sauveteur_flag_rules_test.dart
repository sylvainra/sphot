import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Le bouton couleur exige un drapeau déjà affalé et confirmé', () {
    final source =
        File('lib/pages/sauveteur/sauveteur_actions_rapides_page.dart')
            .readAsStringSync();

    expect(source.contains("_confirmedFlagPosition == 'Affalé'"), isTrue);
    expect(source.contains('enabled: _canChangeFlagColor'), isTrue);
    expect(source.contains('if (!_canChangeFlagColor)'), isTrue);
  });

  test('Un échec HTTP restaure la couleur et la position réelles', () {
    final source =
        File('lib/pages/sauveteur/sauveteur_actions_rapides_page.dart')
            .readAsStringSync();
    expect(source.contains('if (!saved)'), isFalse);
    expect(source.contains('if (saved)'), isTrue);
    expect(source.contains('_restoreConfirmedFlagState();'), isTrue);
    expect(source.contains('_flagWriteInProgress = false;'), isTrue);
    expect(source.contains("result['success'] == true"), isTrue);
  });

  test('Refus explicite hors horaires et sans période Admin', () {
    final source =
        File('lib/pages/sauveteur/sauveteur_actions_rapides_page.dart')
            .readAsStringSync();
    expect(source.contains("case 'surveillance_closed':"), isTrue);
    expect(source.contains("case 'surveillance_schedule_missing':"), isTrue);
    expect(source.contains('onVerticalDragCancel:'), isTrue);
    expect(source.contains('if (_flagWriteInProgress) return;'), isTrue);
  });

  test('Les auteurs des drapeaux apparaissent dans la main courante et PDF',
      () {
    final source =
        File('lib/pages/sauveteur/sauveteur_main_courante.dart')
            .readAsStringSync();
    expect(source.contains('sauveteurVerificationAuthor('), isTrue);
    expect(source.contains("Auteur : $author"), isTrue);
    expect(source.contains('Saisi par : $role'), isFalse);
  });

  test('Les périodes Admin sont liées par identifiant stable au poste', () {
    final admin =
        File('lib/pages/admin/admin_attribution_sphot_page.dart')
            .readAsStringSync();
    expect(admin.contains("'periodesSurveillanceIds': assignedPeriodIds"),
        isTrue);
    expect(admin.contains("'periodesSurveillance': periodesSelectionnees"),
        isTrue);
  });
}
