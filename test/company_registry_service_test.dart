import 'package:bathing_spots_app/services/company_registry_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const siret = '13002526500013';

  test('sélectionne uniquement le SIRET exact et actif', () {
    final result = CompanyRegistryResult.fromSearchResponse({
      'results': [
        {
          'siren': '130025265',
          'nom_complet': 'DIRECTION INTERMINISTERIELLE DU NUMERIQUE',
          'activite_principale': '62.01Z',
          'siege': {
            'siret': siret,
            'etat_administratif': 'A',
            'adresse': {
              'libelle_voie': '20 AVENUE DE SEGUR',
              'code_postal': '75007',
              'libelle_commune': 'PARIS',
            },
          },
        },
      ],
    }, siret);

    expect(result, isNotNull);
    expect(result!.siret, siret);
    expect(result.siren, '130025265');
    expect(result.city, 'PARIS');
    expect(result.isActive, isTrue);
  });

  test('signale un établissement fermé', () {
    final result = CompanyRegistryResult.fromSearchResponse({
      'results': [
        {
          'siren': '130025265',
          'nom_complet': 'ENTREPRISE FERMEE',
          'matching_etablissements': [
            {'siret': siret, 'etat_administratif': 'F'},
          ],
        },
      ],
    }, siret);

    expect(result, isNotNull);
    expect(result!.isActive, isFalse);
  });

  test('refuse un résultat ne correspondant pas exactement au SIRET', () {
    final result = CompanyRegistryResult.fromSearchResponse({
      'results': [
        {
          'siren': '130025265',
          'siege': {'siret': '13002526599999', 'etat_administratif': 'A'},
        },
      ],
    }, siret);

    expect(result, isNull);
  });
}
