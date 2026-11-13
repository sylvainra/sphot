import 'dart:io';

import 'package:bathing_spots_app/pages/sauveteur/sauveteur_verification_author.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Auteur enregistré identifié même sans recherche de nom', () {
    final entry = <String, dynamic>{
      'type': 'Vérifications',
      'verificationCategory': 'medical',
      'createdBy': <String, dynamic>{
        'login': 'bslsm',
        'role': 'SAUVETEUR',
      },
    };

    expect(sauveteurVerificationAuthor(entry), 'bslsm');
  });

  test('Nom du sauveteur avec identifiant original conservé', () {
    final entry = <String, dynamic>{
      'createdBy': <String, dynamic>{'login': 'bslsm'},
    };
    final personnel = <Map<String, dynamic>>[
      {'login': 'BSLSM', 'label': 'B SLSM'},
    ];

    expect(
      sauveteurVerificationAuthor(entry, personnel: personnel),
      'B SLSM (bslsm)',
    );
  });

  test('Quatre catégories, auteurs différents : aucune confusion', () {
    final entries = <Map<String, dynamic>>[
      {
        'verificationCategory': 'medical',
        'createdBy': {'login': 'sauveteur_a'},
      },
      {
        'verificationCategory': 'phonie',
        'createdBy': {'login': 'sauveteur_b'},
      },
      {
        'verificationCategory': 'roulant',
        'createdBy': {'login': 'sauveteur_a'},
      },
      {
        'verificationCategory': 'flottant',
        'createdBy': {'login': 'sauveteur_c'},
      },
    ];

    expect(
      entries.map(sauveteurVerificationAuthor).toList(),
      ['sauveteur_a', 'sauveteur_b', 'sauveteur_a', 'sauveteur_c'],
    );
  });

  test('Auteur historique disponible même après suppression du profil', () {
    final entry = <String, dynamic>{
      'createdBy': <String, dynamic>{'login': 'ancien_sauveteur'},
    };

    expect(
      sauveteurVerificationAuthor(entry, personnel: []),
      'ancien_sauveteur',
    );
  });

  test('Métadonnées manquantes : ne jamais attribuer au lecteur', () {
    expect(sauveteurVerificationAuthor(<String, dynamic>{}),
        'Non renseigné');
    expect(
      sauveteurVerificationAuthor(<String, dynamic>{
        'createdBy': <String, dynamic>{'sauveteurId': 'id-historique'},
      }),
      'Référence sauveteur : id-historique',
    );
  });

  test('Auteur affiché pour chaque carte ET exporté dans le PDF', () {
    final source =
        File('lib/pages/sauveteur/sauveteur_main_courante.dart')
            .readAsStringSync();
    expect(source.contains(r"'Auteur : $author'"), isTrue);
    expect(source.contains(r'Auteur : $author\n$body'), isTrue);
    expect(
      source.split('sauveteurVerificationAuthor(').length - 1,
      2,
    );
  });

  test('Le serveur transmet encore le créateur des inscriptions', () {
    final code = File('functions/index.js').readAsStringSync();
    final start = code.indexOf('exports.getSauveteurMainCourante =');
    final end = code.indexOf('exports.', start + 30);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = code.substring(start, end);
    expect(method.contains('createdBy: entry.createdBy || {}'), isTrue);
  });
}
