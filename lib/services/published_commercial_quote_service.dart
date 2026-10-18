import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// Apercu en lecture seule des grilles tarifaires PUBLIEES.
/// Ne cree ni devis contractuel, ni commande, ni facture.
class PublishedCommercialQuote {
  PublishedCommercialQuote._({
    required this.market,
    required this.version,
    required this.pricingReference,
    required this.country,
    required this.currency,
    required this.amountExclTax,
    required this.details,
    required this.calculatedAt,
  });

  final String market;
  final int version;
  final String pricingReference;
  final String country;
  final String currency;
  final int amountExclTax;
  final Map<String, dynamic> details;
  final DateTime calculatedAt;

  /// Montants fournis en centimes par le serveur, après éventuelle remise.
  int get discountPercent => (details['discountPercent'] as num?)?.toInt() ?? 0;
  int get payableExclTaxCents =>
      (details['payableExclTaxCents'] as num?)?.toInt() ??
      amountExclTax * 100;
  int get discountAmountCents =>
      (details['discountAmountCents'] as num?)?.toInt() ?? 0;

  factory PublishedCommercialQuote.fromResponse(Map<String, dynamic> data) {
    if (data['previewOnly'] != true) {
      throw const FormatException('La réponse tarifaire n’est pas un aperçu.');
    }
    final market = data['market'];
    final version = data['version'];
    final amount = data['amountExclTax'];
    final reference = data['pricingReference'];
    final date = DateTime.tryParse(data['calculatedAt']?.toString() ?? '');
    if ((market != 'ADMIN' &&
            market != 'ADVERTISER' &&
            market != 'ADVERTISER_RADIUS') ||
        version is! int ||
        version <= 0 ||
        amount is! int ||
        amount <= 0 ||
        reference != 'FR_$market-V$version' ||
        data['country'] != 'FR' ||
        data['currency'] != 'EUR' ||
        date == null) {
      throw const FormatException('Réponse tarifaire publiée incomplète.');
    }
    return PublishedCommercialQuote._(
      market: market as String,
      version: version,
      pricingReference: reference as String,
      country: 'FR',
      currency: 'EUR',
      amountExclTax: amount,
      details: Map<String, dynamic>.unmodifiable(data),
      calculatedAt: date,
    );
  }
}

class PublishedCommercialQuoteService {
  const PublishedCommercialQuoteService();

  static const String endpoint =
      'https://us-central1-sphot-ab80b.cloudfunctions.net/'
      'previewPublishedCommercialQuote';

  Future<PublishedCommercialQuote> admin({
    required int numberOfRescueStations,
  }) =>
      _request({
        'market': 'ADMIN',
        'numberOfRescueStations': numberOfRescueStations,
      });

  /// territory: commune, intercommunalite, departement, region, national
  /// offer: map, premium, pack
  /// duration: 1 semaine, 2 semaines, 1 mois, 2 mois, 6 mois, 1 an
  Future<PublishedCommercialQuote> advertiser({
    required String territory,
    required String offer,
    required String duration,
  }) =>
      _request({
        'market': 'ADVERTISER',
        'territory': territory,
        'offer': offer,
        'duration': duration,
      });

  /// Nouveau catalogue indépendant : 6 rayons × 3 offres × 6 durées.
  /// Aucun prix n'est retourné tant qu'une version complète
  /// n'a pas été explicitement publiée par le Super Admin.
  Future<PublishedCommercialQuote> advertiserRadius({
    required String radius,
    required String offer,
    required String duration,
  }) =>
      _request({
        'market': 'ADVERTISER_RADIUS',
        'territory': radius,
        'offer': offer,
        'duration': duration,
      });

  Future<PublishedCommercialQuote> _request(Map<String, dynamic> body) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final response = await http.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty)
          'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 20));
    final dynamic json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Format de réponse tarifaire incorrect.');
    }
    if (response.statusCode != 200 || json['success'] != true) {
      throw StateError(
        json['error']?.toString() ??
            'Tarifs publiés indisponibles (HTTP ${response.statusCode}).',
      );
    }
    final value = json['quote'];
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Détail du tarif publié manquant.');
    }
    final quote = PublishedCommercialQuote.fromResponse(value);
    if (quote.market != body['market']) {
      throw const FormatException('Le marché tarifaire reçu est incorrect.');
    }
    return quote;
  }
}
