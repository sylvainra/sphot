import 'package:flutter/material.dart';
import '../services/commercial_pricing_service.dart';
import 'commercial_pricing_history_format.dart';

/// Grille ADMIN: les prix versionnes sont stockes dans un catalogue Firestore isole.
class SuperAdminAdminPricingTable extends StatefulWidget {
  const SuperAdminAdminPricingTable({super.key, required this.sessionToken});

  final String sessionToken;

  @override
  State<SuperAdminAdminPricingTable> createState() =>
      _SuperAdminAdminPricingTableState();
}

class _SuperAdminAdminPricingTableState
    extends State<SuperAdminAdminPricingTable> {
  static const _blue = Color(0xFF1E3A8A);
  static const _red = Color(0xFFDC2626);
  static const _bg = Color(0xFFF5F7FA);
  static const _labels = <String>[
    '1er poste',
    'Du 2e au 4e poste',
    'Du 5e au 9e poste',
    'À partir du 10e poste',
  ];
  static const _firstPost = <int>[1, 2, 5, 10];
  static const _lastPost = <int>[1, 4, 9, -1];
  static const _original = <int>[499, 399, 299, 199];

  late final List<TextEditingController> _controllers;
  List<int> _published = List<int>.from(_original);
  late final CommercialPricingService _service;
  int _revision = 0;
  bool _busy = true;
  String? _loadError;
  int _publishedVersion = 1;
  int _workingVersion = 2;
  int _stationCount = 10;
  bool _editing = false;
  bool _draftSaved = false;
  bool _scheduled = false;
  DateTime? _scheduledDate;

  @override
  void initState() {
    super.initState();
    _controllers = _published
        .map((value) => TextEditingController(text: value.toString()))
        .toList();
    _service = CommercialPricingService(widget.sessionToken);
    _loadRemote();
  }


  void _applyRemote(CommercialPricingState data) {
    final prices = (data.publishedPrices as List<dynamic>)
        .map((e) => (e as num).toInt()).toList();
    final draft = data.draft;
    final working = draft == null ? prices :
        (draft['prices'] as List<dynamic>).map((e) => (e as num).toInt()).toList();
    setState(() {
      _published = prices;
      _publishedVersion = data.publishedVersion;
      _workingVersion = (data.draft?['version'] as num?)?.toInt() ??
          (data.scheduled?['version'] as num?)?.toInt() ??
          data.latestVersion + 1;
      _revision = data.revision;
      _editing = draft != null;
      _draftSaved = draft != null;
      _scheduled = data.scheduled != null;
      _scheduledDate = data.scheduled?['effectiveAt'] is String
          ? DateTime.tryParse(data.scheduled!['effectiveAt'] as String) : null;
      for (var i = 0; i < 4; i++) {
        _controllers[i].text = working[i].toString();
      }
      _busy = false;
      _loadError = null;
    });
  }

  Future<void> _loadRemote() async {
    try {
      final data = await _service.load('ADMIN');
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
      _message(e.toString());
      // Preserve unsaved edits on network errors or revision conflicts.
    }
  }

  List<int>? _values() {
    final values = <int>[];
    for (final controller in _controllers) {
      final value = int.tryParse(controller.text.trim().replaceAll(' ', ''));
      if (value == null || value <= 0) return null;
      values.add(value);
    }
    return values;
  }

  int _total(int count, List<int> prices) {
    var total = 0;
    for (var i = 0; i < prices.length; i++) {
      final inTier = _lastPost[i] == -1
          ? (count - _firstPost[i] + 1).clamp(0, count).toInt()
          : (count.clamp(0, _lastPost[i]) - _firstPost[i] + 1)
              .clamp(0, count).toInt();
      total += inTier * prices[i];
    }
    return total;
  }

  String _money(int euros) {
    final digits = euros.toString();
    final output = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) output.write(' ');
      output.write(digits[i]);
    }
    return '${output.toString()} €';
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  void _newVersion() {
    setState(() {
      _editing = true;
      _draftSaved = false;
      for (var i = 0; i < _controllers.length; i++) {
        _controllers[i].text = _published[i].toString();
      }
    });
  }

  Future<void> _cancelDraft() async {
    if (_draftSaved) {
      await _persist(() => _service.discard('ADMIN', revision: _revision));
      return;
    }
    setState(() {
      _editing = false;
      _draftSaved = false;
      for (var i = 0; i < 4; i++) {
        _controllers[i].text = _published[i].toString();
      }
    });
  }

  Future<void> _save() async {
    final values = _values();
    if (values == null) {
      _message('Renseignez quatre montants annuels positifs.');
      return;
    }
    await _persist(() => _service.save(
      'ADMIN', revision: _revision, prices: values,
    ));
  }

  List<String> _warnings(List<int> prices) {
    final messages = <String>[];
    for (var i = 1; i < prices.length; i++) {
      if (prices[i] > prices[i - 1]) {
        messages.add('La tranche ${i + 1} dépasse la tranche précédente.');
      }
    }
    if (prices.asMap().entries.any(
      (entry) => (entry.value - _published[entry.key]).abs() >
          _published[entry.key] / 2,
    )) {
      messages.add('Au moins un prix varie de plus de 50 %.');
    }
    return messages;
  }

  Future<void> _publish() async {
    if (!_editing || !_draftSaved || _busy) return;
    final values = _values();
    if (values == null) return;
    final changes = List<int>.generate(4, (i) => i)
        .where((i) => values[i] != _published[i]).length;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PUBLIER LA GRILLE ADMIN'),
        content: Text(
          'France · EUR HT · ADMIN-V${_publishedVersion + 1}\n'
          'Quatre tranches, $changes modifications.\n'
          '${_warnings(values).join("\n")}\n\n'
          'La version sera enregistrée dans Firestore. '
          'Les abonnements existants restent inchangés.',
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
      final now = DateTime.now();
      final date = await showDatePicker(
        context: context,
        initialDate: now.add(const Duration(days: 1)),
        firstDate: now.add(const Duration(days: 1)),
        lastDate: now.add(const Duration(days: 3650)),
        helpText: 'DATE DE PUBLICATION',
      );
      if (!mounted || date == null) return;
      effectiveAt = DateTime(date.year, date.month, date.day);
    }
    await _persist(() => _service.publish('ADMIN',
        revision: _revision, effectiveAt: effectiveAt));
  }

  Future<void> _restoreHistoricalVersion(
    int sourceVersion,
    int expectedRevision,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('REPRENDRE ADMIN-V$sourceVersion'),
        content: Text(
          'Les quatre tarifs de la version ADMIN-V$sourceVersion seront '
          'copiés à l’identique dans un nouveau brouillon.\n\n'
          'Le nouveau brouillon sera immédiatement enregistré dans Firestore. '
          'La grille publiée et les archives resteront inchangées. '
          'Vous pourrez le contrôler et le modifier avant publication.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ANNULER'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('CRÉER LE BROUILLON'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _persist(() => _service.restoreVersion(
      'ADMIN', revision: expectedRevision, sourceVersion: sourceVersion,
    ));
  }

  Future<void> _history() async {
    CommercialPricingState data;
    try {
      data = await _service.load('ADMIN');
    } catch (e) {
      if (!mounted) return;
      _message(e.toString());
      return;
    }
    if (!mounted) return;
    final canRestore = !_busy && !_editing &&
        data.draft == null && data.scheduled == null;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('HISTORIQUE TARIFAIRE ADMIN'),
        content: SizedBox(
          width: 690,
          height: 430,
          child: ListView(
            children: [
              if (!canRestore)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    'Pour reprendre une version historique, terminez ou '
                    'annulez d’abord le brouillon ou la programmation en cours.',
                    style: TextStyle(fontSize: 12, color: _red),
                  ),
                ),
              if (data.draft != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ADMIN-V${data.draft!["version"]} · BROUILLON ENREGISTRÉ',
                          style: const TextStyle(
                            color: _blue, fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final event in
                            CommercialPricingHistoryFormat.draftEvents(data.draft!))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: SelectableText(event),
                          ),
                      ],
                    ),
                  ),
                ),
              for (final version in data.history)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ADMIN-V${version["version"]} · '
                          '${CommercialPricingHistoryFormat.status(version["status"])}',
                          style: const TextStyle(
                            color: _blue, fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          (version['prices'] as List<dynamic>)
                              .map((amount) => _money((amount as num).toInt()))
                              .join(' / '),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        for (final event in
                            CommercialPricingHistoryFormat.events(version))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: SelectableText(
                              event,
                              style: const TextStyle(
                                fontSize: 12, color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        if (version['status'] == 'archived' ||
                            version['status'] == 'published')
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed: canRestore
                                  ? () {
                                      Navigator.pop(dialogContext);
                                      _restoreHistoricalVersion(
                                        (version['version'] as num).toInt(),
                                        data.revision,
                                      );
                                    }
                                  : null,
                              icon: const Icon(Icons.restore_outlined, size: 17),
                              label: const Text('REPRENDRE CETTE VERSION'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('FERMER'),
          ),
        ],
      ),
    );
  }

  Widget _button(
    String title,
    IconData icon,
    VoidCallback? action, {
    bool primary = false,
  }) {
    return OutlinedButton.icon(
      onPressed: action,
      icon: Icon(icon, size: 18),
      label: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      style: OutlinedButton.styleFrom(
        foregroundColor: primary ? Colors.white : _blue,
        backgroundColor: primary ? _blue : Colors.white,
        side: BorderSide(color: primary ? _blue : const Color(0xFFBAC7DA)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      ),
    );
  }

  Widget _priceInput(int index) {
    final actual = int.tryParse(_controllers[index].text.trim());
    final changed = _editing && actual != null && actual != _published[index];
    return SizedBox(
      width: 155,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (changed)
            Text(
              _money(_published[index]),
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                decoration: TextDecoration.lineThrough,
                fontWeight: FontWeight.w600,
              ),
            ),
          TextField(
            controller: _controllers[index],
            enabled: _editing,
            textAlign: TextAlign.right,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              color: _blue, fontWeight: FontWeight.w800, fontSize: 16,
            ),
            onChanged: (_) => setState(() => _draftSaved = false),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              suffixText: '€',
            ),
          ),
        ],
      ),
    );
  }

  Widget _tariffCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFCCD5E4)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xFFE7EDF7),
            padding: const EdgeInsets.all(14),
            child: const Row(
              children: [
                Expanded(
                  child: Text('TRANCHE DE POSTES DE SECOURS',
                      style: TextStyle(color: _blue, fontWeight: FontWeight.w900)),
                ),
                Text('PRIX ANNUEL HT / POSTE',
                    style: TextStyle(color: _blue, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          for (var i = 0; i < _labels.length; i++) ...[
            Container(
              color: i.isEven ? Colors.white : _bg,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _labels[i],
                      style: const TextStyle(color: _blue, fontWeight: FontWeight.w800),
                    ),
                  ),
                  _priceInput(i),
                ],
              ),
            ),
            if (i < _labels.length - 1)
              const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _simulation(List<int> amounts) {
    final count = _stationCount;
    final total = _total(count, amounts);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFCCD5E4)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('SIMULATION DE L’ABONNEMENT ANNUEL',
              style: TextStyle(color: _blue, fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            '$count poste${count > 1 ? "s" : ""} de secours',
            style: const TextStyle(color: _blue, fontWeight: FontWeight.w800),
          ),
          Slider(
            value: _stationCount.toDouble(),
            min: 1,
            max: 30,
            divisions: 29,
            activeColor: _blue,
            label: '$_stationCount',
            onChanged: (number) => setState(() => _stationCount = number.round()),
          ),
          Text(
            '${_money(total)} HT / an',
            style: const TextStyle(
              color: _blue, fontSize: 26, fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text('Aucun frais de mise en place ni de formation.',
              style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          const Text('Repères de facturation (HT/an)',
              style: TextStyle(color: _blue, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final sample in const [1, 4, 5, 9, 10, 15])
                Chip(
                  label: Text('$sample poste${sample > 1 ? "s" : ""} · '
                      '${_money(_total(sample, amounts))}'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final values = _values() ?? _published;
    final status = _editing
        ? (_draftSaved ? 'BROUILLON ENREGISTRÉ' : 'BROUILLON NON ENREGISTRÉ')
        : _scheduled
            ? 'PROGRAMMÉE'
            : 'PUBLIÉE';
    return ColoredBox(
      color: _bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E7),
                border: Border.all(color: const Color(0xFFEDC974)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'GRILLE ADMIN — Les versions sont enregistrées dans Firestore. '
                'Les factures et abonnements restent inchangés.',
                style: TextStyle(
                  color: Color(0xFF775B13), fontWeight: FontWeight.w700,
                ),
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
                const Text('FRANCE · EUR (€) · ADMIN',
                    style: TextStyle(color: _blue, fontWeight: FontWeight.w900,
                        fontSize: 17)),
                Chip(label: Text(
                  'ADMIN-V${_editing || _scheduled ? _workingVersion : _publishedVersion}',
                )),
                Chip(label: Text(status)),
                _button('HISTORIQUE', Icons.history, _busy ? null : _history),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _blue.withValues(alpha: 0.28),
                            ),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Avec SPHOT, la diffusion sur la carte et les '
                                'caractéristiques descriptives des lieux '
                                'peuvent être publiées gratuitement*. '
                                'Les abonnements SPHOT ADMIN ajoutent les '
                                'fonctionnalités temps réel des SPHOTS surveillés.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _blue,
                                  fontWeight: FontWeight.w700,
                                  height: 1.4,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                '* La gratuité couvre les informations '
                                'descriptives. La diffusion des informations '
                                'de surveillance en temps réel nécessite '
                                'une période d’essai autorisée ou un '
                                'abonnement SPHOT ADMIN en vigueur.',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 11,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text('TARIFICATION DÉGRESSIVE PAR POSTE',
                            style: TextStyle(
                              color: _blue, fontSize: 16, fontWeight: FontWeight.w900,
                            )),
                        const SizedBox(height: 8),
                        _tariffCard(),
                        const SizedBox(height: 14),
                        _simulation(values),
                        const SizedBox(height: 12),
                        const Text(
                          'CGV ADMIN : version, acceptation et conditions de '
                          'renouvellement seront raccordées au parcours ADMIN '
                          'lors de l’activation réelle des tarifs.',
                          style: TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 9,
              runSpacing: 8,
              children: [
                if (!_editing && !_scheduled)
                  _button(
                    'CRÉER UNE NOUVELLE VERSION',
                    Icons.copy,
                    _busy || _loadError != null ? null : _newVersion,
                    primary: true,
                  ),
                if (_editing) ...[
                  _button('ANNULER LE BROUILLON', Icons.undo, _busy ? null : _cancelDraft),
                  _button('ENREGISTRER', Icons.save_outlined, _busy || _loadError != null ? null : _save),
                  _button('PUBLIER', Icons.send_outlined,
                      _draftSaved && !_busy ? _publish : null, primary: true),
                ],
                if (_scheduled)
                  _button(
                    'ANNULER LA PROGRAMMATION',
                    Icons.event_busy,
                    _busy ? null : () => _persist(() => _service.cancelSchedule(
                      'ADMIN', revision: _revision,
                    )),
                  ),
              ],
            ),
            if (_scheduledDate != null)
              Text(
                'Programmée : ${_scheduledDate!.day}/'
                '${_scheduledDate!.month}/${_scheduledDate!.year}',
                style: const TextStyle(color: _blue),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }
}
