import 'dart:convert';

import 'package:http/http.dart' as http;

/// Catalogues Firestore isoles des tarifs historiques encore utilises
/// par les commandes, devis et abonnements des portails.
class CommercialPricingState {
  CommercialPricingState(Map<String, dynamic> data)
      : revision = (data['revision'] as num).toInt(),
        publishedVersion = (data['publishedVersion'] as num).toInt(),
        latestVersion = (data['latestVersion'] as num).toInt(),
        publishedPrices = data['publishedPrices'],
        publishedPersonalised = (data['publishedPersonalised'] as List<dynamic>?)
                ?.map((e) => e.toString()).toList() ??
            <String>[],
        draft = data['draft'] is Map
            ? Map<String, dynamic>.from(data['draft'] as Map)
            : null,
        scheduled = data['scheduled'] is Map
            ? Map<String, dynamic>.from(data['scheduled'] as Map)
            : null,
        history = (data['history'] as List<dynamic>? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(),
        isSeed = data['seeded'] == true;

  final int revision;
  final int publishedVersion;
  final int latestVersion;
  final dynamic publishedPrices;
  final List<String> publishedPersonalised;
  final Map<String, dynamic>? draft;
  final Map<String, dynamic>? scheduled;
  final List<Map<String, dynamic>> history;
  final bool isSeed;
}

/// Les requetes sont autorisees PAR LE SERVEUR avec une session Super Admin
/// courte, et non avec les permissions Firebase du navigateur.
class CommercialPricingService {
  CommercialPricingService(this.sessionToken);

  final String sessionToken;

  static const _endpoint =
      'https://us-central1-sphot-ab80b.cloudfunctions.net/manageCommercialPricing';

  Future<CommercialPricingState> _post(
    String market,
    String action, {
    int? revision,
    dynamic prices,
    List<String>? personalised,
    DateTime? effectiveAt,
    int? sourceVersion,
  }) async {
    if (sessionToken.isEmpty) {
      throw StateError('Session Super Admin absente. Reconnectez-vous.');
    }
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $sessionToken',
      },
      body: jsonEncode({
        'market': market,
        'action': action,
        if (sourceVersion != null) 'sourceVersion': sourceVersion,
        if (revision != null) 'revision': revision,
        if (prices != null) 'prices': prices,
        if (personalised != null) 'personalised': personalised,
        if (effectiveAt != null)
          'effectiveAt': effectiveAt.toUtc().toIso8601String(),
      }),
    ).timeout(const Duration(seconds: 25));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Réponse du service tarifaire invalide.');
    }
    if (response.statusCode != 200 || decoded['success'] != true) {
      throw StateError(decoded['error']?.toString() ??
          'Erreur de sauvegarde (HTTP ${response.statusCode}).');
    }
    return CommercialPricingState(
      Map<String, dynamic>.from(decoded['data'] as Map),
    );
  }

  /// Remise commerciale individuelle, accordée uniquement par Super Admin.
  /// Même dispositif pour les clients ADMIN et PUBLICITAIRE.
  Future<int> customerDiscount({
    required String market,
    required String uid,
  }) async {
    final response = await _discountRequest(
      action: 'getCustomerDiscount',
      market: market,
      uid: uid,
    );
    return (response['percent'] as num).toInt();
  }

  Future<int> setCustomerDiscount({
    required String market,
    required String uid,
    required int percent,
  }) async {
    final response = await _discountRequest(
      action: 'setCustomerDiscount',
      market: market,
      uid: uid,
      percent: percent,
    );
    return (response['percent'] as num).toInt();
  }

  Future<Map<String, dynamic>> _discountRequest({
    required String action,
    required String market,
    required String uid,
    int? percent,
  }) async {
    if (sessionToken.isEmpty) {
      throw StateError('Session Super Admin absente.');
    }
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $sessionToken',
      },
      body: jsonEncode({
        'market': market,
        'action': action,
        'customerMarket': market,
        'customerUid': uid,
        if (percent != null) 'percent': percent,
      }),
    ).timeout(const Duration(seconds: 25));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['success'] != true ||
        response.statusCode != 200 || decoded['data'] is! Map) {
      throw StateError(
        decoded is Map ? decoded['error']?.toString() ??
            'Remise non disponible.' : 'Réponse invalide.',
      );
    }
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }

  Future<CommercialPricingState> load(String market) =>
      _post(market, 'load');

  Future<CommercialPricingState> save(
    String market, {
    required int revision,
    required dynamic prices,
    List<String> personalised = const [],
  }) =>
      _post(market, 'save',
          revision: revision, prices: prices, personalised: personalised);

  Future<CommercialPricingState> publish(
    String market, {
    required int revision,
    DateTime? effectiveAt,
  }) =>
      _post(market, effectiveAt == null ? 'publish' : 'schedule',
          revision: revision, effectiveAt: effectiveAt);

  Future<CommercialPricingState> discard(
    String market, {
    required int revision,
  }) =>
      _post(market, 'discard', revision: revision);

  /// Reprend les prix EXACTS d'une version historique en un nouveau brouillon.
  /// Le serveur refuse si une autre version est déjà en brouillon/programmée.
  Future<CommercialPricingState> restoreVersion(
    String market, {
    required int revision,
    required int sourceVersion,
  }) =>
      _post(market, 'restoreVersion',
          revision: revision, sourceVersion: sourceVersion);

  Future<CommercialPricingState> cancelSchedule(
    String market, {
    required int revision,
  }) =>
      _post(market, 'cancelSchedule', revision: revision);
}
