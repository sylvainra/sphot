import 'package:flutter/material.dart';

/// Ecran ADMIN de test : aucun changement Firestore, abonnement ou facture.
class SuperAdminAdminPricingTable extends StatefulWidget {
  const SuperAdminAdminPricingTable({super.key});

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
  final List<List<int>> _archives = [];
  int _publishedVersion = 1;
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

  void _cancelDraft() {
    setState(() {
      _editing = false;
      _draftSaved = false;
      for (var i = 0; i < _controllers.length; i++) {
        _controllers[i].text = _published[i].toString();
      }
    });
  }

  void _save() {
    if (_values() == null) {
      _message('Renseignez les quatre tarifs annuels : entiers positifs.');
      return;
    }
    setState(() => _draftSaved = true);
    _message('Brouillon ADMIN enregistré en mémoire (sans Firebase).');
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
    if (!_editing || !_draftSaved) return;
    final prices = _values();
    if (prices == null) {
      _message('Un tarif est invalide ; publication impossible.');
      return;
    }
    final count = List<int>.generate(4, (i) => i)
        .where((i) => prices[i] != _published[i])
        .length;
    final warnings = _warnings(prices);
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('PUBLIER LA GRILLE ADMIN'),
        content: SingleChildScrollView(
          child: Text(
            'France · EUR HT · ADMIN-V${_publishedVersion + 1}\n'
            '4 tranches · $count tarifs modifiés\n'
            '1er poste : ${_money(prices[0])} / an\n'
            '2e–4e : ${_money(prices[1])} / poste / an\n'
            '5e–9e : ${_money(prices[2])} / poste / an\n'
            '10e et suivants : ${_money(prices[3])} / poste / an\n'
            'Frais de mise en place / formation : 0 €\n\n'
            '${warnings.isEmpty ? "Aucun avertissement." : warnings.join("\n")}\n\n'
            'SIMULATION LOCALE UNIQUEMENT : pas de mise à jour Firebase, '
            'de devis, d’abonnement ni de CGV.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('ANNULER'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'schedule'),
            child: const Text('PROGRAMMER'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'now'),
            child: const Text('PUBLIER MAINTENANT'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'schedule') {
      final today = DateTime.now();
      final date = await showDatePicker(
        context: context,
        initialDate: today.add(const Duration(days: 1)),
        firstDate: today.add(const Duration(days: 1)),
        lastDate: today.add(const Duration(days: 3650)),
        helpText: 'DATE DE PUBLICATION (MODE TEST)',
      );
      if (date == null || !mounted) return;
      setState(() {
        _scheduled = true;
        _scheduledDate = date;
        _editing = false;
      });
      _message('Publication ADMIN programmée en simulation seulement.');
      return;
    }
    setState(() {
      _archives.add(List<int>.from(_published));
      _published = List<int>.from(prices);
      _publishedVersion++;
      _editing = false;
      _draftSaved = false;
      _scheduled = false;
      _scheduledDate = null;
    });
    _message('Grille ADMIN publiée en simulation (aucune écriture Firebase).');
  }

  Future<void> _history() async {
    final archived = <String>[];
    for (var i = _archives.length - 1; i >= 0; i--) {
      archived.add(
        'ADMIN-V${i + 1} — ARCHIVÉE · '
        '${_archives[i].map(_money).join(" / ")}',
      );
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('HISTORIQUE TARIFAIRE ADMIN'),
        content: SingleChildScrollView(
          child: Text(
            'ADMIN-V$_publishedVersion — PUBLIÉE (simulation)\n'
            '${_editing ? "ADMIN-V${_publishedVersion + 1} — BROUILLON\n" : ""}'
            '${_scheduled ? "ADMIN-V${_publishedVersion + 1} — PROGRAMMÉE\n" : ""}'
            '${archived.join("\n")}\n\n'
            'Historique disponible seulement pendant cette session de test. '
            'Firestore et l’historisation juridique seront raccordés '
            'après validation.',
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
            ? 'PROGRAMMÉE (TEST)'
            : 'PUBLIÉE (TEST)';
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
                'MODE TEST — Grille ADMIN dégressive. Enregistrer, publier '
                'et programmer sont simulés ; aucune écriture Firebase.',
                style: TextStyle(
                  color: Color(0xFF775B13), fontWeight: FontWeight.w700,
                ),
              ),
            ),
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
                  'ADMIN-V${_editing || _scheduled ? _publishedVersion + 1 : _publishedVersion}',
                )),
                Chip(label: Text(status)),
                _button('HISTORIQUE', Icons.history, _history),
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
                    _newVersion,
                    primary: true,
                  ),
                if (_editing) ...[
                  _button('ANNULER LE BROUILLON', Icons.undo, _cancelDraft),
                  _button('ENREGISTRER', Icons.save_outlined, _save),
                  _button('PUBLIER', Icons.send_outlined,
                      _draftSaved ? _publish : null, primary: true),
                ],
                if (_scheduled)
                  _button(
                    'ANNULER LA PROGRAMMATION (TEST)',
                    Icons.event_busy,
                    () => setState(() {
                      _scheduled = false;
                      _scheduledDate = null;
                      _editing = true;
                      _draftSaved = true;
                    }),
                  ),
              ],
            ),
            if (_scheduledDate != null)
              Text(
                'Programmée (test) : ${_scheduledDate!.day}/'
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
