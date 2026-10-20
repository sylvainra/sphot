import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../models/advertising_pricing_config.dart';
import '../../../services/published_commercial_quote_service.dart';
import '../../shared/web_colors.dart';
import '../services/advertiser_territory_service.dart';

/// Préparation d'une nouvelle souscription APRÈS expiration réelle.
/// Aucun changement du rayon contractuel ni activation de diffusion ici.
class AdvertiserRenewalSection extends StatefulWidget {
  const AdvertiserRenewalSection({
    super.key,
    required this.requestId,
    required this.contractTerritory,
    required this.offer,
  });

  final String? requestId;
  final AdvertiserTerritory? contractTerritory;
  final String offer;

  @override
  State<AdvertiserRenewalSection> createState() =>
      _AdvertiserRenewalSectionState();
}

class _AdvertiserRenewalSectionState extends State<AdvertiserRenewalSection> {
  static const _endpoint =
      'https://europe-west1-sphot-ab80b.cloudfunctions.net/'
      'advertiserRenewalEligibility';
  static const _choices = <AdvertiserTerritoryLevel>[
    AdvertiserTerritoryLevel.radius5km,
    AdvertiserTerritoryLevel.radius15km,
    AdvertiserTerritoryLevel.radius50km,
    AdvertiserTerritoryLevel.radius150km,
    AdvertiserTerritoryLevel.radius300km,
  ];
  final _quoteService = const PublishedCommercialQuoteService();
  bool _loading = true;
  bool _eligible = false;
  bool _saving = false;
  bool _priceLoading = false;
  bool _prepared = false;
  String? _error;
  String? _endLabel;
  String? _eligibilityReason;
  AdvertiserTerritoryLevel? _selected;
  String _duration = AdvertisingPricingConfig.durations.first;
  String _offer = 'map';
  PublishedCommercialQuote? _quote;
  int _quoteTicket = 0;

  @override
  void initState() {
    super.initState();
    _offer = widget.offer;
    _refresh();
  }

  Future<Map<String, dynamic>> _call(String action,
      {AdvertiserTerritoryLevel? selected}) async {
    final uid = widget.requestId;
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (uid == null || uid.isEmpty || token == null || token.isEmpty) {
      throw StateError('Connexion annonceur authentifiée nécessaire.');
    }
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': action,
        'requestId': uid,
        if (selected != null) ...{
          'territory': {'level': selected.storageKey},
          'offer': _offer,
          'duration': _duration,
        },
      }),
    ).timeout(const Duration(seconds: 25));
    final dynamic raw = jsonDecode(response.body);
    if (raw is! Map<String, dynamic>) {
      throw StateError('Réponse de renouvellement invalide.');
    }
    if (response.statusCode != 200) {
      throw StateError('Vérification du renouvellement impossible : '
          '${raw['error'] ?? response.statusCode}.');
    }
    return raw;
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _prepared = false;
      _quote = null;
    });
    try {
      final data = await _call('eligibility');
      if (!mounted) return;
      final end = DateTime.tryParse(data['endAt']?.toString() ?? '');
      final date = end?.toLocal();
      setState(() {
        _eligible = data['eligible'] == true;
        _eligibilityReason = data['reason']?.toString();
        _endLabel = date == null ? null :
            '${date.day.toString().padLeft(2, '0')}/'
            '${date.month.toString().padLeft(2, '0')}/'
            '${date.year} à '
            '${date.hour.toString().padLeft(2, '0')}:'
            '${date.minute.toString().padLeft(2, '0')}';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _eligible = false; // Verrouillage en cas d'erreur.
        _eligibilityReason = 'verification_failed';
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadPrice() async {
    final level = _selected;
    final ticket = ++_quoteTicket;
    if (level == null) return;
    setState(() {
      _quote = null;
      _prepared = false;
      _priceLoading = true;
      _error = null;
    });
    try {
      final quote = await _quoteService.advertiserRadius(
        radius: level.storageKey,
        offer: _offer,
        duration: _duration,
      );
      if (!mounted || ticket != _quoteTicket) return;
      setState(() {
        _quote = quote;
        _priceLoading = false;
      });
    } catch (e) {
      if (!mounted || ticket != _quoteTicket) return;
      setState(() {
        _quote = null;
        _priceLoading = false;
        _error = 'Tarification publiée indisponible : $e';
      });
    }
  }

  Future<void> _prepare() async {
    if (_selected == null || _quote == null || _saving || !_eligible) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await _call('prepare', selected: _selected);
      if (!mounted) return;
      setState(() {
        _prepared =
            response['draftStatus'] == 'awaiting_commercial_checkout';
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
        _eligible = false;
      });
      // En cas de refus serveur, ne jamais laisser une préparation possible.
      await _refresh();
    }
  }

  Widget _panel({required List<Widget> children}) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFCBD5E1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final contract = widget.contractTerritory?.level.label ??
        'Non renseigné';
    return _panel(children: [
      const Text('RENOUVELLEMENT — RAYON D’ACTION',
          style: TextStyle(
              color: WebColors.blue,
              fontWeight: FontWeight.w900,
              fontSize: 17)),
      const SizedBox(height: 10),
      Text('Rayon du contrat précédent : $contract',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      if (_endLabel != null)
        Text('Dernière échéance de campagne : $_endLabel'),
      const SizedBox(height: 12),
      if (_loading)
        const Center(child: CircularProgressIndicator())
      else if (!_eligible) ...[
        Text(
          _eligibilityReason == 'no_linked_campaign'
              ? 'Impossible de retrouver une campagne de diffusion liée '
                'à votre dossier. Le rayon reste verrouillé.'
              : _eligibilityReason == 'invalid_campaign_period'
                  ? 'Date contractuelle non vérifiable. '
                    'Le rayon reste verrouillé par sécurité.'
                  : 'RAYON VERROUILLÉ — La sélection d’un nouveau rayon '
                    'sera possible seulement après l’expiration de toutes '
                    'les campagnes liées au dossier.',
          style: const TextStyle(
              color: WebColors.red, fontWeight: FontWeight.w800),
        ),
      ] else ...[
        const Text(
          'PÉRIODE PRÉCÉDENTE TERMINÉE — Vous pouvez préparer '
          'une nouvelle souscription avec un autre rayon. '
          'Cela ne modifie pas votre ancienne campagne.',
          style: TextStyle(
              color: WebColors.blue, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final level in _choices)
            ChoiceChip(
              label: Text(level.label),
              selected: _selected == level,
              onSelected: (value) {
                if (!value) return;
                setState(() => _selected = level);
                _loadPrice();
              },
            ),
        ]),
        const SizedBox(height: 10),
        const Text(
          'Le choix PAYS ENTIER sera proposé après vérification '
          'du pays de diffusion lors du parcours de commande.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          value: _offer,
          decoration: const InputDecoration(
              labelText: 'Nouvelle visibilité'),
          items: [
            for (final item in AdvertisingPricingConfig.visibilityLabels.entries)
              DropdownMenuItem(value: item.key, child: Text(item.value)),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _offer = value);
            _loadPrice();
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _duration,
          decoration: const InputDecoration(
              labelText: 'Nouvelle période de diffusion'),
          items: [
            for (final item in AdvertisingPricingConfig.durations)
              DropdownMenuItem(value: item, child: Text(item)),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _duration = value);
            _loadPrice();
          },
        ),
        if (_priceLoading)
          const Padding(
            padding: EdgeInsets.all(10),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_quote != null && !_priceLoading) ...[
          const SizedBox(height: 14),
          Text(
            'Prix publié indicatif : '
            '${(_quote!.payableExclTaxCents / 100).toStringAsFixed(2)} € HT',
            style: const TextStyle(color: WebColors.red,
                fontSize: 18, fontWeight: FontWeight.w900),
          ),
          Text('Référence : ${_quote!.pricingReference}'),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _quote == null || _saving ? null : _prepare,
          icon: const Icon(Icons.shopping_cart_checkout_outlined),
          label: Text(_saving
              ? 'VÉRIFICATION EN COURS…'
              : 'PRÉPARER LA NOUVELLE SOUSCRIPTION'),
        ),
        if (_prepared) ...[
          const SizedBox(height: 12),
          const Text(
            'Préparation enregistrée. Aucun paiement n’a été effectué '
            'et le nouveau rayon n’est pas activé.',
            style: TextStyle(color: WebColors.blue,
                fontWeight: FontWeight.w800),
          ),
        ],
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: const TextStyle(color: WebColors.red)),
      ],
      TextButton.icon(
        onPressed: _loading ? null : _refresh,
        icon: const Icon(Icons.refresh),
        label: const Text('ACTUALISER L’ÉCHÉANCE'),
      ),
      const Divider(height: 22),
      const Text(
        'La nouvelle commande, sa facture et le paiement CB '
        'doivent être raccordés avant toute activation. '
        'Aucune modification du rayon contractuel ni de la carte '
        'SPHOT n’est effectuée par cette préparation.',
        style: TextStyle(fontSize: 12),
      ),
    ]);
  }
}
