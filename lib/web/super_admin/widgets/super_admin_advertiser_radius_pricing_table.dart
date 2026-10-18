import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/commercial_pricing_service.dart';

/// Catalogue de 108 prix, SÉPARÉ du catalogue historique de 90 tarifs.
/// Les montants ne sont jamais déduits des anciennes catégories.
class SuperAdminAdvertiserRadiusPricingTable extends StatefulWidget {
  const SuperAdminAdvertiserRadiusPricingTable({
    super.key,
    required this.sessionToken,
  });

  final String sessionToken;

  @override
  State<SuperAdminAdvertiserRadiusPricingTable> createState() =>
      _SuperAdminAdvertiserRadiusPricingTableState();
}

class _SuperAdminAdvertiserRadiusPricingTableState
    extends State<SuperAdminAdvertiserRadiusPricingTable> {
  static const _blue = Color(0xFF1E3A8A);
  static const _red = Color(0xFFDC2626);
  static const _market = 'ADVERTISER_RADIUS';
  static const _radii = ['5 km', '15 km', '50 km', '150 km', '300 km', '500 km'];
  static const _offers = ['CARTE SPHOT', 'FICHES SPHOT', 'PACK TOTAL'];
  static const _durations = [
    '1 semaine', '2 semaines', '1 mois', '2 mois', '6 mois', '1 an'
  ];

  late CommercialPricingService _service;
  final Map<String, TextEditingController> _fields = {};
  int _revision = 0;
  int _publishedVersion = 0;
  int? _draftVersion;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;
  Map<String, int> _publishedPrices = {};
  List<Map<String, dynamic>> _history = const [];

  String _key(int r, int o, int d) => '$r:$o:$d';

  @override
  void initState() {
    super.initState();
    _service = CommercialPricingService(widget.sessionToken);
    for (var r = 0; r < _radii.length; r++) {
      for (var o = 0; o < _offers.length; o++) {
        for (var d = 0; d < _durations.length; d++) {
          _fields[_key(r, o, d)] = TextEditingController();
        }
      }
    }
    _load();
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _apply(CommercialPricingState state) {
    _revision = state.revision;
    _publishedVersion = state.publishedVersion;
    _draftVersion = (state.draft?['version'] as num?)?.toInt();
    _history = state.history;
    final published = state.publishedPrices is Map
        ? Map<String, dynamic>.from(state.publishedPrices as Map)
        : <String, dynamic>{};
    _publishedPrices = {
      for (final entry in published.entries)
        if (entry.value is num) entry.key: (entry.value as num).toInt(),
    };
    final draft = state.draft?['prices'];
    final current = draft is Map ? Map<String, dynamic>.from(draft) : published;
    for (final field in _fields.entries) {
      field.value.text = current[field.key]?.toString() ?? '';
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.load(_market);
      if (!mounted) return;
      setState(() {
        _apply(data);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Catalogue indisponible : $error';
      });
    }
  }

  Map<String, int>? _validatedPrices() {
    final prices = <String, int>{};
    for (final field in _fields.entries) {
      final value = int.tryParse(field.value.text.trim());
      if (value == null || value <= 0 || value > 10000000) {
        setState(() {
          _error = 'Renseignez les 108 prix HT en euros entiers positifs. '
              'Aucune valeur ne sera calculée automatiquement.';
        });
        return null;
      }
      prices[field.key] = value;
    }
    return prices.length == 108 ? prices : null;
  }

  Future<void> _save() async {
    if (_busy) return;
    final prices = _validatedPrices();
    if (prices == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final data = await _service.save(
        _market,
        revision: _revision,
        prices: prices,
      );
      if (!mounted) return;
      setState(() {
        _apply(data);
        _notice = 'Brouillon enregistré. Aucun nouveau tarif publié.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Échec de sauvegarde : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    if (_busy || _draftVersion == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PUBLIER LES 108 TARIFS ?'),
        content: Text(
          'La référence FR_ADVERTISER_RADIUS-V$_draftVersion deviendra '
          'applicable aux nouvelles demandes. Les anciennes versions '
          'et commandes resteront inchangées. Confirmez-vous ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ANNULER'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('PUBLIER'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await _service.publish(_market, revision: _revision);
      if (!mounted) return;
      setState(() {
        _apply(result);
        _notice =
            'Publication confirmée : FR_ADVERTISER_RADIUS-V$_publishedVersion';
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Publication impossible : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'NOUVEAU CATALOGUE : 108 PRIX · 6 RAYONS × 3 OFFRES × 6 DURÉES',
          style: const TextStyle(
            color: _blue,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _publishedVersion == 0
              ? 'Aucune grille publiée. Ancien catalogue conservé.'
              : 'GRILLE PUBLIÉE : FR_ADVERTISER_RADIUS-V$_publishedVersion',
          style: const TextStyle(color: _red, fontWeight: FontWeight.w800),
        ),
        if (_draftVersion != null)
          Text(
            'BROUILLON : V$_draftVersion, non applicable aux paiements',
            style: const TextStyle(color: _blue),
          ),
        if (_history.isNotEmpty)
          Text(
            'Historique conservé : ${_history.length} version(s)',
            style: const TextStyle(color: _blue),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!, style: const TextStyle(color: _red)),
          ),
        if (_notice != null)
          Text(_notice!, style: const TextStyle(color: _blue)),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            itemCount: _radii.length,
            itemBuilder: (context, r) => Card(
              child: ExpansionTile(
                initiallyExpanded: r == 0,
                title: Text(
                  'RAYON ${_radii[r]}',
                  style: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                children: [
                  for (var o = 0; o < _offers.length; o++) ...[
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _offers[o],
                        style: const TextStyle(
                          color: _red,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (var d = 0; d < _durations.length; d++)
                            SizedBox(
                              width: 140,
                              child: TextField(
                                controller: _fields[_key(r, o, d)],
                                enabled: !_busy,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  labelText: _durations[d],
                                  suffixText: '€ HT',
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                  helperText: _publishedPrices.containsKey(
                                    _key(r, o, d),
                                  ) ? 'Publié : ${_publishedPrices[_key(r, o, d)]} €'
                                    : 'Non publié',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _load,
                child: const Text('ACTUALISER'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('ENREGISTRER BROUILLON'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _busy || _draftVersion == null ? null : _publish,
                style: FilledButton.styleFrom(backgroundColor: _red),
                child: const Text('PUBLIER'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
