import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/commercial_pricing_service.dart';
import '../services/advertiser_radius_pricing_import.dart';

/// Grille de référence SPHOT Publicitaire validée le 18/10/2026.
/// 108 montants HT éditables et publiés avec numéro de version.
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
  static const _radii = ['5 km', '15 km', '50 km', '150 km', '300 km', 'PAYS ENTIER'];
  static const _offers = ['CARTE SPHOT', 'FICHES SPHOT', 'PACK TOTAL'];
  static const _durations = [
    '1 semaine', '2 semaines', '1 mois', '2 mois', '6 mois', '1 an'
  ];

  late CommercialPricingService _service;
  final Map<String, TextEditingController> _fields = {};
  final Map<String, String> _lastSavedValues = {};
  bool _applyingSavedValues = false;
  bool _hasPendingEdits = false;
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
          _fields[_key(r, o, d)] = TextEditingController()
            ..addListener(_onPriceChanged);
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

  void _onPriceChanged() {
    if (_applyingSavedValues || !mounted) return;
    final dirty = _fields.entries.any(
      (entry) => entry.value.text != _lastSavedValues[entry.key],
    );
    if (dirty != _hasPendingEdits) {
      setState(() => _hasPendingEdits = dirty);
    }
  }

  void _apply(CommercialPricingState state) {
    _applyingSavedValues = true;
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
    _lastSavedValues.clear();
    for (final field in _fields.entries) {
      final value = current[field.key]?.toString() ?? '';
      field.value.text = value;
      _lastSavedValues[field.key] = value;
    }
    _hasPendingEdits = false;
    _applyingSavedValues = false;
  }

  Future<void> _copyPricingTable() async {
    final table = AdvertiserRadiusPricingImport.export({
      for (final entry in _fields.entries)
        entry.key: entry.value.text.trim(),
    });
    await Clipboard.setData(ClipboardData(text: table));
    if (!mounted) return;
    setState(() {
      _notice = 'Tableau de 18 lignes copié. Renseignez les six prix HT '
          'de chaque ligne dans un tableur, puis recollez-le ici.';
      _error = null;
    });
  }

  Future<void> _pastePricingTable() async {
    if (_busy) return;
    try {
      final clipboard = await Clipboard.getData('text/plain');
      final input = clipboard?.text ?? '';
      final parsed = AdvertiserRadiusPricingImport.parse(input);
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('IMPORTER LES 108 TARIFS ?'),
          content: const Text(
            'Les 108 cases actuellement affichées seront remplacées '
            'par celles du tableau collé. Aucun tarif ne sera enregistré '
            'ni publié avant votre validation séparée.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ANNULER'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('REMPLACER LES CASES'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      _applyingSavedValues = true;
      for (final entry in parsed.entries) {
        _fields[entry.key]!.text = entry.value.toString();
      }
      _applyingSavedValues = false;
      setState(() {
        _hasPendingEdits = true;
        _error = null;
        _notice = '108 prix chargés localement. '
            'Cliquez ENREGISTRER BROUILLON avant toute publication.';
      });
    } catch (error) {
      _applyingSavedValues = false;
      if (!mounted) return;
      setState(() {
        _error = 'Import refusé : $error';
        _notice = null;
      });
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
    if (_busy || _draftVersion == null || _hasPendingEdits) return;
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
          'GRILLE DE RÉFÉRENCE : 108 PRIX · 5 RAYONS + PAYS × 3 OFFRES × 6 DURÉES',
          style: const TextStyle(
            color: _blue,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _publishedVersion == 0
              ? 'Aucune version publiée. Les 108 tarifs validés sont prêts à enregistrer.'
              : 'GRILLE PUBLIÉE : FR_ADVERTISER_RADIUS-V$_publishedVersion',
          style: const TextStyle(color: _red, fontWeight: FontWeight.w800),
        ),
        if (_draftVersion != null)
          Text(
            'BROUILLON : V$_draftVersion, non applicable aux paiements',
            style: const TextStyle(color: _blue),
          ),
        if (_hasPendingEdits)
          const Text(
            'MODIFICATIONS NON ENREGISTRÉES : publier est désactivé.',
            style: TextStyle(color: _red, fontWeight: FontWeight.w800),
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _copyPricingTable,
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('COPIER LE TABLEAU (CSV)'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pastePricingTable,
              icon: const Icon(Icons.content_paste),
              label: const Text('COLLER LES 108 PRIX'),
            ),
          ],
        ),
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
                onPressed: _busy || _draftVersion == null ||
                        _hasPendingEdits ? null : _publish,
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
