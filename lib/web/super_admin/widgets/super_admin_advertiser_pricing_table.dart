import 'package:flutter/material.dart';
import '../services/commercial_pricing_service.dart';

/// Preview of the new advertiser tariff editor.
/// All changes (including SAVE and PUBLISH) are session-only in this test.
class SuperAdminAdvertiserPricingTable extends StatefulWidget {
  const SuperAdminAdvertiserPricingTable({super.key, required this.sessionToken});

  final String sessionToken;

  @override
  State<SuperAdminAdvertiserPricingTable> createState() =>
      _SuperAdminAdvertiserPricingTableState();
}

class _SuperAdminAdvertiserPricingTableState
    extends State<SuperAdminAdvertiserPricingTable> {
  static const _blue = Color(0xFF1E3A8A);
  static const _red = Color(0xFFDC2626);
  static const _grey = Color(0xFFF5F7FA);
  static const _durations = <String>[
    '1 SEMAINE', '2 SEMAINES', '1 MOIS', '2 MOIS', '6 MOIS', '1 AN',
  ];
  static const _levels = <String>[
    'COMMUNE', 'INTERCOMMUNALITÉ', 'DÉPARTEMENT', 'RÉGION', 'NATIONAL',
  ];
  static const _offers = <String>[
    'CARTE SPHOT', 'FICHES SPHOT', 'PACK VISIBILITÉ TOTALE',
  ];

  // Five administrative levels x three offers x six durations.
  static const _seed = <List<List<int>>>[
    [
      [49, 95, 149, 249, 599, 999],
      [99, 189, 299, 499, 1199, 1999],
      [129, 239, 379, 629, 1519, 2539],
    ],
    [
      [89, 159, 249, 419, 999, 1669],
      [159, 289, 449, 759, 1799, 3009],
      [199, 369, 569, 969, 2279, 3809],
    ],
    [
      [139, 259, 399, 679, 1599, 2669],
      [259, 489, 749, 1269, 2999, 5019],
      [329, 619, 949, 1609, 3799, 6359],
    ],
    [
      [209, 379, 590, 999, 2359, 3949],
      [379, 709, 1090, 1859, 4359, 7299],
      [489, 899, 1390, 2369, 5559, 9309],
    ],
    [
      [250, 490, 790, 1390, 2900, 4900],
      [450, 890, 1490, 2600, 5400, 8900],
      [590, 1150, 1990, 3500, 7400, 11900],
    ],
  ];

  final Map<String, TextEditingController> _fields = {};
  final Set<String> _personalised = {};
  final Set<String> _publishedPersonalised = {};
  final TextEditingController _pivotInput = TextEditingController(text: '49');
  Map<String, int> _published = {};
  int _publishedVersion = 1;
  int _workingVersion = 2;
  bool _editing = false;
  bool _draftSaved = false;
  DateTime? _scheduledFor;
  bool _simulatedScheduled = false;
  late final CommercialPricingService _service;
  int _revision = 0;
  bool _busy = true;
  String? _loadError;
  List<Map<String, dynamic>> _remoteHistory = [];

  String _key(int level, int offer, int duration) =>
      '$level:$offer:$duration';

  @override
  void initState() {
    super.initState();
    for (var level = 0; level < _levels.length; level++) {
      for (var offer = 0; offer < _offers.length; offer++) {
        for (var duration = 0; duration < _durations.length; duration++) {
          final key = _key(level, offer, duration);
          final price = _seed[level][offer][duration];
          _fields[key] = TextEditingController(text: price.toString());
          _published[key] = price;
        }
      }
    }
    _service = CommercialPricingService(widget.sessionToken);
    _loadRemote();
  }


  void _applyRemote(CommercialPricingState data) {
    final published = Map<String, dynamic>.from(data.publishedPrices as Map)
        .map((key, value) => MapEntry(key, (value as num).toInt()));
    final draft = data.draft;
    final working = draft == null ? published :
        Map<String, dynamic>.from(draft['prices'] as Map)
            .map((key, value) => MapEntry(key, (value as num).toInt()));
    setState(() {
      _published = published;
      _publishedVersion = data.publishedVersion;
      _workingVersion = (data.draft?['version'] as num?)?.toInt() ??
          (data.scheduled?['version'] as num?)?.toInt() ??
          data.latestVersion + 1;
      _revision = data.revision;
      _remoteHistory = data.history;
      _editing = draft != null;
      _draftSaved = draft != null;
      _simulatedScheduled = data.scheduled != null;
      _scheduledFor = data.scheduled?['effectiveAt'] is String
          ? DateTime.tryParse(data.scheduled!['effectiveAt'] as String) : null;
      _publishedPersonalised
        ..clear()
        ..addAll(data.publishedPersonalised);
      _personalised
        ..clear()
        ..addAll(draft == null ?
            data.publishedPersonalised :
            (draft['personalised'] as List<dynamic>? ?? [])
                .map((v) => v.toString()));
      for (final entry in working.entries) {
        _fields[entry.key]!.text = entry.value.toString();
      }
      _pivotInput.text = _fields[_key(0, 0, 0)]!.text;
      _busy = false;
      _loadError = null;
    });
  }

  Future<void> _loadRemote() async {
    try {
      final data = await _service.load('ADVERTISER');
      if (mounted) _applyRemote(data);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _persist(
    Future<CommercialPricingState> Function() operation,
  ) async {
    setState(() => _busy = true);
    try {
      final data = await operation();
      if (mounted) _applyRemote(data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _notice(e.toString());
      // Preserve the user's unsaved prices after a failed request.
    }
  }


  int? _amount(String key) {
    return int.tryParse(_fields[key]!.text.trim().replaceAll(' ', ''));
  }

  Map<String, int>? _validPrices() {
    final result = <String, int>{};
    for (final key in _fields.keys) {
      final number = _amount(key);
      if (number == null || number <= 0) return null;
      result[key] = number;
    }
    return result;
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _startDraft() {
    setState(() {
      _editing = true;
      _draftSaved = false;
      _simulatedScheduled = false;
      _scheduledFor = null;
      _pivotInput.text = _fields[_key(0, 0, 0)]!.text;
    });
  }

  Future<void> _discardDraft() async {
    if (_draftSaved) {
      await _persist(() => _service.discard('ADVERTISER', revision: _revision));
      return;
    }
    setState(() {
      _editing = false;
      _draftSaved = false;
      for (final entry in _published.entries) {
        _fields[entry.key]!.text = entry.value.toString();
      }
      _pivotInput.text = _published[_key(0, 0, 0)].toString();
      _personalised
        ..clear()
        ..addAll(_publishedPersonalised);
    });
  }

  Future<void> _recalculate() async {
    if (!_editing) return;
    final prices = _validPrices();
    if (prices == null) {
      _notice('Corrigez les montants invalides avant le recalcul.');
      return;
    }
    final nextPivot = int.tryParse(_pivotInput.text.trim());
    final originalPivot = prices[_key(0, 0, 0)]!;
    if (nextPivot == null || nextPivot <= 0) {
      _notice('Le tarif pivot doit être un entier supérieur à zéro.');
      return;
    }
    if (originalPivot == nextPivot) {
      _notice('Le tarif pivot est inchangé.');
      return;
    }
    final factor = nextPivot / originalPivot;
    final next = <String, int>{};
    for (final entry in prices.entries) {
      if (entry.key == _key(0, 0, 0)) {
        next[entry.key] = nextPivot;
      } else if (_personalised.contains(entry.key)) {
        next[entry.key] = entry.value;
      } else {
        next[entry.key] = (entry.value * factor).round().clamp(1, 99999999).toInt();
      }
    }
    final affected = 90 - _personalised.length;
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('CONFIRMER LE RECALCUL'),
        content: Text(
          'Pivot : $originalPivot € → $nextPivot €\n'
          'Variation : ${((factor - 1) * 100).toStringAsFixed(2)} %\n'
          '$affected tarifs recalculés, '
          '${_personalised.length} tarifs personnalisés protégés.\n\n'
          'Le recalcul sera appliqué au brouillon non publié.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ANNULER'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('RECALCULER'),
          ),
        ],
      ),
    );
    if (apply != true || !mounted) return;
    setState(() {
      for (final entry in next.entries) {
        _fields[entry.key]!.text = entry.value.toString();
      }
      _draftSaved = false;
    });
    _notice('Recalcul appliqué : enregistrez pour le conserver.');
  }

  void _resetCell(int level, int offer, int duration) {
    final key = _key(level, offer, duration);
    final currentPivot = _amount(_key(0, 0, 0)) ?? 49;
    final calculated =
        (_seed[level][offer][duration] * currentPivot / 49).round();
    setState(() {
      _fields[key]!.text = calculated.toString();
      _personalised.remove(key);
      _draftSaved = false;
    });
  }

  Future<void> _saveDraft() async {
    final prices = _validPrices();
    if (prices == null) {
      _notice('Les 90 montants doivent être positifs.');
      return;
    }
    await _persist(() => _service.save(
      'ADVERTISER', revision: _revision,
      prices: prices, personalised: _personalised.toList(),
    ));
  }

  List<String> _warnings(Map<String, int> prices) {
    final result = <String>[];
    for (var l = 0; l < _levels.length; l++) {
      for (var o = 0; o < _offers.length; o++) {
        for (var d = 1; d < _durations.length; d++) {
          if (prices[_key(l, o, d)]! < prices[_key(l, o, d - 1)]!) {
            result.add('Prix décroissant : ${_levels[l]}, ${_offers[o]}.');
          }
        }
      }
      for (var d = 0; d < _durations.length; d++) {
        if (prices[_key(l, 2, d)]! >
            prices[_key(l, 0, d)]! + prices[_key(l, 1, d)]!) {
          result.add('Pack plus cher que Carte + Fiches : ${_levels[l]}.');
        }
      }
    }
    return result;
  }

  Future<void> _publish() async {
    if (!_editing || !_draftSaved || _busy) return;
    final prices = _validPrices();
    if (prices == null) return;
    final changed = prices.keys.where((k) => prices[k] != _published[k]).length;
    final warnings = _warnings(prices);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PUBLIER LA GRILLE ANNONCEUR'),
        content: SingleChildScrollView(
          child: Text(
            'FRANCE · EUR · FR-V${_publishedVersion + 1}\n'
            '90 tarifs · $changed prix modifiés\n'
            '${warnings.isEmpty ? "Aucun avertissement." :
              warnings.take(5).join("\n")}\n\n'
            'La nouvelle grille sera enregistrée dans Firestore. '
            'Les devis et campagnes existants restent inchangés.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('ANNULER')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'schedule'),
              child: const Text('PROGRAMMER')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'now'),
              child: const Text('PUBLIER MAINTENANT')),
        ],
      ),
    );
    if (!mounted || action == null) return;
    DateTime? effectiveAt;
    if (action == 'schedule') {
      final today = DateTime.now();
      final date = await showDatePicker(
        context: context,
        initialDate: today.add(const Duration(days: 1)),
        firstDate: today.add(const Duration(days: 1)),
        lastDate: today.add(const Duration(days: 3650)),
        helpText: 'DATE DE PUBLICATION',
      );
      if (date == null || !mounted) return;
      effectiveAt = DateTime(date.year, date.month, date.day);
    }
    await _persist(() => _service.publish(
      'ADVERTISER', revision: _revision, effectiveAt: effectiveAt,
    ));
  }

  Widget _topButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      style: OutlinedButton.styleFrom(
        foregroundColor: primary ? Colors.white : _blue,
        backgroundColor: primary ? _blue : Colors.white,
        side: BorderSide(color: primary ? _blue : const Color(0xFFB9C6D9)),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
      ),
    );
  }


  /// French currency display for the before/after comparison.
  String _displayEuro(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return '${buffer.toString()} €';
  }

  Widget _previousPrice(int amount) {
    return Text(
      _displayEuro(amount),
      textAlign: TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFF64748B),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.lineThrough,
        decorationColor: Color(0xFF64748B),
        decorationThickness: 1.5,
      ),
    );
  }

  Widget _priceCell(int level, int offer, int duration) {
    final key = _key(level, offer, duration);
    final isPivot = level == 0 && offer == 0 && duration == 0;
    final personal = _personalised.contains(key);
    final price = _amount(key);
    final previousPrice = _published[key]!;
    // Compare against the published version, not the preceding edit.
    // This also stays visible after saving a draft; a publish clears it.
    final changed = _editing && price != null && price != previousPrice;

    if (!_editing || isPivot) {
      return Container(
        height: _editing ? 70 : 49,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (isPivot)
              const Icon(Icons.push_pin_outlined, size: 14, color: _red),
            if (personal && !isPivot)
              const Icon(Icons.lock_outline, size: 13, color: _red),
            const SizedBox(width: 3),
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (changed) ...[
                    _previousPrice(previousPrice),
                    const SizedBox(height: 3),
                  ],
                  Text(
                    price == null ? '—' : _displayEuro(price),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: isPivot ? _red : _blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (changed) ...[
            Align(
              alignment: Alignment.centerRight,
              child: _previousPrice(previousPrice),
            ),
            const SizedBox(height: 3),
          ],
          SizedBox(
            height: 43,
            child: TextField(
              controller: _fields[key],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                color: _blue,
                fontWeight: FontWeight.w700,
              ),
              onChanged: (_) => setState(() {
                _personalised.add(key);
                _draftSaved = false;
              }),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 12,
                ),
                filled: personal,
                fillColor: const Color(0xFFFFF0F0),
                suffixIcon: personal
                    ? IconButton(
                        tooltip: 'Réinitialiser au tarif calculé',
                        icon: const Icon(Icons.undo, size: 16, color: _red),
                        onPressed: () => _resetCell(level, offer, duration),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minHeight: 28,
                          minWidth: 28,
                        ),
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeading() {
    return Container(
      color: const Color(0xFFE6ECF6),
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: 193,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('OFFRE / TERRITOIRE', style: _headerStyle),
              ),
            ),
          ),
          for (final duration in _durations)
            SizedBox(
              width: 121,
              child: Center(child: Text(duration, style: _headerStyle)),
            ),
        ],
      ),
    );
  }

  static const _headerStyle = TextStyle(
    color: _blue, fontSize: 11, fontWeight: FontWeight.w900,
  );

  List<Widget> _tableRows() {
    final rows = <Widget>[];
    for (var l = 0; l < _levels.length; l++) {
      rows.add(Container(
        height: 34,
        color: const Color(0xFFE9EFF8),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text(_levels[l],
            style: const TextStyle(color: _blue, fontWeight: FontWeight.w900)),
      ));
      for (var o = 0; o < _offers.length; o++) {
        rows.add(Container(
          color: o.isEven ? Colors.white : const Color(0xFFF7F9FC),
          child: Row(
            children: [
              SizedBox(
                width: 193,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(_offers[o],
                      style: const TextStyle(
                          color: _blue, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
              for (var d = 0; d < _durations.length; d++)
                SizedBox(width: 121, child: _priceCell(l, o, d)),
            ],
          ),
        ));
        rows.add(const Divider(height: 1, thickness: 0.5));
      }
    }
    return rows;
  }

  Future<void> _showHistory() async {
    try {
      final data = await _service.load('ADVERTISER');
      if (!mounted) return;
      _remoteHistory = data.history;
    } catch (e) {
      if (!mounted) return;
      _notice(e.toString());
      return;
    }
    final records = _remoteHistory.map((item) =>
      'FR-V${item["version"]} · ${item["status"]} · 90 tarifs HT'
    ).join('\n');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('HISTORIQUE DES VERSIONS'),
        content: SingleChildScrollView(
          child: SelectableText(
            'FRANCE · ANNONCEUR · VERSIONS FIRESTORE\n'
            '${_editing ? "BROUILLON ENREGISTRÉ\n" : ""}'
            '${_simulatedScheduled ? "PUBLICATION PROGRAMMÉE\n" : ""}\n'
            '$records',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('FERMER')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _editing
        ? (_draftSaved ? 'BROUILLON ENREGISTRÉ' : 'BROUILLON NON ENREGISTRÉ')
        : _simulatedScheduled
            ? 'PROGRAMMÉE'
            : 'PUBLIÉE';
    return Container(
      color: _grey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEDC974)),
              ),
              child: const Text(
                'GRILLE ANNONCEUR — Les versions sont enregistrées dans Firestore. '
                'Les devis et paiements restent inchangés.',
                style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF775B13)),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_loadError != null)
              SelectableText('Service tarifaire indisponible : $_loadError',
                style: const TextStyle(color: _red, fontSize: 12)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('FRANCE · EUR (€)',
                    style: TextStyle(color: _blue, fontSize: 17,
                        fontWeight: FontWeight.w900)),
                Chip(label: Text('FR-V${_editing || _simulatedScheduled ? _workingVersion : _publishedVersion}')),
                Chip(label: Text(status)),
                _topButton(
                  label: 'HISTORIQUE',
                  icon: Icons.history,
                  onPressed: _busy ? null : _showHistory,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFCCD5E4)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TARIF PIVOT',
                            style: TextStyle(color: _blue, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        const Text('Commune · Carte SPHOT · 1 semaine',
                            style: TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 125,
                    child: TextField(
                      controller: _pivotInput,
                      enabled: _editing,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(), labelText: 'EUR HT',
                        isDense: true,
                      ),
                      onSubmitted: (_) {},
                    ),
                  ),
                  _topButton(
                    label: 'RECALCULER LES TARIFS',
                    icon: Icons.calculate_outlined,
                    onPressed: _editing ? _recalculate : null,
                    primary: _editing,
                  ),
                  Text('${_personalised.length} prix personnalisés',
                      style: const TextStyle(color: _blue, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('TABLEAU COMPLET DES 90 TARIFS HT',
                style: TextStyle(color: _blue, fontSize: 15, fontWeight: FontWeight.w900)),
            if (_editing) ...[
              const SizedBox(height: 4),
              const Row(
                children: [
                  Text(
                    'Ancien tarif',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  SizedBox(width: 7),
                  Text('→ nouveau tarif : seules les cellules modifiées affichent les deux montants',
                      style: TextStyle(fontSize: 11, color: _blue)),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: constraints.maxWidth > 919 ? constraints.maxWidth : 919,
                      child: Column(
                        children: [
                          _tableHeading(),
                          Expanded(
                            child: ListView(children: _tableRows()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (!_editing && !_simulatedScheduled)
                  _topButton(
                    label: 'CRÉER UNE NOUVELLE VERSION',
                    icon: Icons.copy,
                    onPressed: _busy || _loadError != null ? null : _startDraft,
                    primary: true,
                  ),
                if (_editing) ...[
                  _topButton(
                    label: 'ANNULER LE BROUILLON',
                    icon: Icons.undo,
                    onPressed: _busy ? null : _discardDraft,
                  ),
                  _topButton(
                    label: 'ENREGISTRER',
                    icon: Icons.save_outlined,
                    onPressed: _busy || _loadError != null ? null : _saveDraft,
                  ),
                  _topButton(
                    label: 'PUBLIER',
                    icon: Icons.send_outlined,
                    onPressed: _draftSaved && !_busy ? _publish : null,
                    primary: true,
                  ),
                ],
                if (_simulatedScheduled)
                  _topButton(
                    label: 'ANNULER LA PROGRAMMATION (TEST)',
                    icon: Icons.event_busy,
                    onPressed: _busy ? null : () => _persist(() =>
                      _service.cancelSchedule('ADVERTISER', revision: _revision)),
                  ),
              ],
            ),
            if (_simulatedScheduled && _scheduledFor != null)
              Text(
                'Date programmée (simulation) : ${_scheduledFor!.day}/${_scheduledFor!.month}/${_scheduledFor!.year}',
                style: const TextStyle(color: _blue),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pivotInput.dispose();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }
}
