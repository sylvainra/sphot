import 'dart:convert';

import 'package:http/http.dart' as http;

class CompanyRegistryException implements Exception {
  const CompanyRegistryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CompanyRegistryResult {
  const CompanyRegistryResult({
    required this.siret,
    required this.siren,
    required this.legalName,
    required this.businessName,
    required this.activityCode,
    required this.legalForm,
    required this.address,
    required this.postalCode,
    required this.city,
    required this.isActive,
  });

  final String siret;
  final String siren;
  final String legalName;
  final String businessName;
  final String activityCode;
  final String legalForm;
  final String address;
  final String postalCode;
  final String city;
  final bool isActive;

  static CompanyRegistryResult? fromSearchResponse(
    Map<String, dynamic> json,
    String expectedSiret,
  ) {
    final results = json['results'];
    if (results is! List) return null;

    for (final rawCompany in results) {
      if (rawCompany is! Map) continue;
      final company = Map<String, dynamic>.from(rawCompany);
      final candidates = <Map<String, dynamic>>[];
      final headOffice = company['siege'];
      if (headOffice is Map) {
        candidates.add(Map<String, dynamic>.from(headOffice));
      }
      final matching = company['matching_etablissements'];
      if (matching is List) {
        candidates.addAll(
          matching.whereType<Map>().map(Map<String, dynamic>.from),
        );
      }

      for (final establishment in candidates) {
        if (_digits(establishment['siret']) != expectedSiret) continue;
        final address = establishment['adresse'];
        final addressMap = address is Map
            ? Map<String, dynamic>.from(address)
            : <String, dynamic>{};
        final state = _text(establishment['etat_administratif']).toUpperCase();

        return CompanyRegistryResult(
          siret: expectedSiret,
          siren: _digits(company['siren']).isNotEmpty
              ? _digits(company['siren'])
              : expectedSiret.substring(0, 9),
          legalName: _first([
            company['nom_complet'],
            company['nom_raison_sociale'],
            company['personne_morale_attributs'] is Map
                ? company['personne_morale_attributs']['raison_sociale']
                : null,
          ]),
          businessName: _first([
            establishment['nom_commercial'],
            company['nom_commercial'],
          ]),
          activityCode: _first([
            establishment['activite_principale'],
            company['activite_principale'],
          ]),
          legalForm: _first([
            company['nature_juridique'],
            company['libelle_nature_juridique'],
          ]),
          address: _first([
            addressMap['libelle_voie'],
            establishment['adresse'],
          ]),
          postalCode: _text(addressMap['code_postal']),
          city: _first([addressMap['libelle_commune'], addressMap['commune']]),
          isActive: state.isEmpty || state == 'A',
        );
      }
    }
    return null;
  }

  static String _text(Object? value) => value?.toString().trim() ?? '';
  static String _digits(Object? value) =>
      _text(value).replaceAll(RegExp(r'[^0-9]'), '');
  static String _first(List<Object?> values) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }
}

class CompanyRegistryService {
  const CompanyRegistryService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<CompanyRegistryResult> findBySiret(String rawSiret) async {
    final siret = rawSiret.replaceAll(RegExp(r'[^0-9]'), '');
    if (siret.length != 14) {
      throw const CompanyRegistryException(
        'Le SIRET doit comporter exactement 14 chiffres.',
      );
    }

    final uri = Uri.https('recherche-entreprises.api.gouv.fr', '/search', {
      'q': siret,
      'per_page': '10',
    });
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw const CompanyRegistryException(
          'Le registre officiel est momentanément indisponible.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const CompanyRegistryException('Réponse du registre invalide.');
      }
      final result = CompanyRegistryResult.fromSearchResponse(
        Map<String, dynamic>.from(decoded),
        siret,
      );
      if (result == null) {
        throw const CompanyRegistryException(
          'Aucun établissement ne correspond exactement à ce SIRET.',
        );
      }
      return result;
    } on CompanyRegistryException {
      rethrow;
    } catch (_) {
      throw const CompanyRegistryException(
        'Impossible de joindre le registre officiel. Vous pourrez poursuivre avec un contrôle manuel.',
      );
    } finally {
      if (_client == null) client.close();
    }
  }
}
