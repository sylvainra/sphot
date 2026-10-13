import 'package:flutter_test/flutter_test.dart';
import 'package:bathing_spots_app/services/published_commercial_quote_service.dart';

void main() {
  final calculatedAt = '2026-10-13T16:00:00.000Z';

  test('Lecture devis indicatif ADMIN V3 à 10 postes', () {
    final quote = PublishedCommercialQuote.fromResponse({
      'previewOnly': true,
      'market': 'ADMIN',
      'version': 3,
      'pricingReference': 'FR_ADMIN-V3',
      'country': 'FR',
      'currency': 'EUR',
      'amountExclTax': 3390,
      'numberOfRescueStations': 10,
      'rateSnapshot': [499, 399, 299, 199],
      'calculatedAt': calculatedAt,
    });
    expect(quote.pricingReference, 'FR_ADMIN-V3');
    expect(quote.amountExclTax, 3390);
    expect(quote.version, 3);
  });

  test('Lecture devis indicatif ANNONCEUR V3', () {
    final quote = PublishedCommercialQuote.fromResponse({
      'previewOnly': true,
      'market': 'ADVERTISER',
      'version': 3,
      'pricingReference': 'FR_ADVERTISER-V3',
      'country': 'FR',
      'currency': 'EUR',
      'amountExclTax': 11900,
      'tariffKey': '4:2:5',
      'calculatedAt': calculatedAt,
    });
    expect(quote.amountExclTax, 11900);
    expect(quote.details['tariffKey'], '4:2:5');
  });

  test('Ne pas confondre grille publiée et version non conforme', () {
    expect(
      () => PublishedCommercialQuote.fromResponse({
        'previewOnly': true,
        'market': 'ADMIN',
        'version': 3,
        'pricingReference': 'FR_ADMIN-V2',
        'country': 'FR',
        'currency': 'EUR',
        'amountExclTax': 3390,
        'calculatedAt': calculatedAt,
      }),
      throwsFormatException,
    );
  });

  test('Refus des réponses tarifaires non indiquées comme aperçu', () {
    expect(
      () => PublishedCommercialQuote.fromResponse({
        'previewOnly': false,
        'market': 'ADMIN',
        'version': 3,
        'pricingReference': 'FR_ADMIN-V3',
        'country': 'FR',
        'currency': 'EUR',
        'amountExclTax': 3390,
        'calculatedAt': calculatedAt,
      }),
      throwsFormatException,
    );
  });
}
