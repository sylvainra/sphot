import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/advertising_pricing_config.dart';

class SuperAdminPricingPanel extends StatefulWidget {
  const SuperAdminPricingPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<SuperAdminPricingPanel> createState() => _SuperAdminPricingPanelState();
}

class _SuperAdminPricingPanelState extends State<SuperAdminPricingPanel> {
  static const _blue = Color(0xFF1E3A8A);
  static const _red = Color(0xFFDC2626);

  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 560,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        border: Border(
          left: BorderSide(color: _blue.withOpacity(0.25), width: 1.5),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
              color: Colors.white,
              child: Row(
                children: [
                  const Icon(Icons.euro_rounded, color: _blue, size: 28),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'GRILLES TARIFAIRES',
                      style: TextStyle(
                        color: _blue,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded, color: _blue),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Expanded(child: _tabButton('ADMIN', 0)),
                  const SizedBox(width: 10),
                  Expanded(child: _tabButton('ANNONCEUR', 1)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: IndexedStack(
                  index: _selectedTab,
                  children: const [
                    _AdminPricingEditor(),
                    _AdvertiserPricingEditor(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final selected = _selectedTab == index;
    return OutlinedButton(
      onPressed: () => setState(() => _selectedTab = index),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? _red.withOpacity(0.08) : Colors.white,
        foregroundColor: selected ? _red : _blue,
        side: BorderSide(color: selected ? _red : _blue, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

class _AdminPricingEditor extends StatefulWidget {
  const _AdminPricingEditor();

  @override
  State<_AdminPricingEditor> createState() => _AdminPricingEditorState();
}

class _AdminPricingEditorState extends State<_AdminPricingEditor> {
  static const _blue = Color(0xFF1E3A8A);
  static const _red = Color(0xFFDC2626);
  final _priceController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('subscriptionPricing')
          .get();
      final value = snapshot.data()?['annualPricePerRescueStationExclTax'];
      _priceController.text = _numberText(value is num ? value : 500);
    } catch (error) {
      _priceController.text = '500';
      _error = 'Impossible de charger le tarif Admin.';
    }
    if (mounted) setState(() => _loading = false);
  }

  String _numberText(num value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(2).replaceAll('.', ',');

  double? get _price =>
      double.tryParse(_priceController.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final price = _price;
    if (price == null || price <= 0) {
      setState(() => _error = 'Saisissez un tarif annuel HT valide.');
      return;
    }
    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });
    try {
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('subscriptionPricing')
          .set({
            'annualPricePerRescueStationExclTax': price,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (mounted) setState(() => _saved = true);
    } catch (error) {
      if (mounted) setState(() => _error = 'Enregistrement impossible.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _red));
    }
    return ListView(
      children: [
        _pricingCard(
          title: 'ABONNEMENT ADMIN',
          subtitle: 'Le montant annuel est calculé selon le nombre de postes de secours déclarés.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _priceController,
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w800,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {
                  _saved = false;
                  _error = null;
                }),
                decoration: _tariffInputDecoration(
                  label: 'PRIX PAR POSTE DE SECOURS',
                  suffix: '€ HT / an',
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'APERÇU DE LA GRILLE',
                style: TextStyle(color: _blue, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              for (final count in const [1, 2, 3, 5, 10])
                _priceRow(
                  '$count poste${count > 1 ? 's' : ''}',
                  '${((_price ?? 0) * count).round()} € HT / an',
                ),
            ],
          ),
        ),
        if (_error != null) _errorText(_error!),
        const SizedBox(height: 12),
        _saveButton(
          saving: _saving,
          saved: _saved,
          label: 'ENREGISTRER LE TARIF ADMIN',
          onPressed: _save,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }
}

class _AdvertiserPricingEditor extends StatefulWidget {
  const _AdvertiserPricingEditor();

  @override
  State<_AdvertiserPricingEditor> createState() =>
      _AdvertiserPricingEditorState();
}

class _AdvertiserPricingEditorState extends State<_AdvertiserPricingEditor> {
  static const _blue = Color(0xFF1E3A8A);
  static const _red = Color(0xFFDC2626);

  final Map<String, TextEditingController> _controllers = {};
  final _visibilityFieldKey = GlobalKey();
  final _radiusFieldKey = GlobalKey();
  Map<String, dynamic> _pricing = AdvertisingPricingConfig.defaults();
  String _visibility = 'map';
  double _radiusKm = 0;
  bool _loading = true;
  bool _saving = false;
  bool _saved = false;
  String? _error;
  OverlayEntry? _choiceOverlay;
  String? _openChoiceId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _key(String visibility, double radius, String duration) =>
      '$visibility|${AdvertisingPricingConfig.radiusKey(radius)}|$duration';

  Future<void> _load() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('advertisingPricing')
          .get();
      _pricing = snapshot.data() ?? AdvertisingPricingConfig.defaults();
    } catch (error) {
      _error = 'Impossible de charger les tarifs Annonceur.';
    }
    for (final visibility in AdvertisingPricingConfig.visibilityLabels.keys) {
      for (final radius in AdvertisingPricingConfig.radiusChoices) {
        for (final duration in AdvertisingPricingConfig.durations) {
          final value = AdvertisingPricingConfig.localPrice(
            pricing: _pricing,
            durationLabel: duration,
            visibilityType: visibility,
            radiusKm: radius,
          );
          _controllers[_key(visibility, radius, duration)] =
              TextEditingController(text: value.toString());
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  TextEditingController _controller(String duration) =>
      _controllers[_key(_visibility, _radiusKm, duration)]!;

  InputDecoration _dropdownDecoration(String label, {required bool open}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: open ? _red : _blue, width: 1.6),
    );
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _blue, fontWeight: FontWeight.w800),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: border,
    );
  }

  void _closeChoiceMenu() {
    _choiceOverlay?.remove();
    _choiceOverlay = null;
    if (mounted && _openChoiceId != null) {
      setState(() => _openChoiceId = null);
    }
  }

  void _openChoiceMenu<T>({
    required String id,
    required GlobalKey fieldKey,
    required T selectedValue,
    required List<_PricingChoice<T>> choices,
    required ValueChanged<T> onSelected,
  }) {
    _closeChoiceMenu();

    final renderObject = fieldKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;

    final position = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    setState(() => _openChoiceId = id);

    _choiceOverlay = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeChoiceMenu,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned(
            left: position.dx,
            top: position.dy + size.height - 10,
            width: size.width,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 260),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.98),
                  border: const Border(
                    left: BorderSide(color: _blue, width: 1.6),
                    right: BorderSide(color: _blue, width: 1.6),
                    bottom: BorderSide(color: _blue, width: 1.6),
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  children: [
                    for (final choice in choices)
                      InkWell(
                        onTap: () {
                          _closeChoiceMenu();
                          onSelected(choice.value);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  choice.label,
                                  style: const TextStyle(
                                    color: _blue,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (choice.value == selectedValue)
                                const Icon(
                                  Icons.check_rounded,
                                  color: _red,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_choiceOverlay!);
  }

  Widget _choiceField<T>({
    required String id,
    required GlobalKey fieldKey,
    required String label,
    required T value,
    required List<_PricingChoice<T>> choices,
    required ValueChanged<T> onSelected,
  }) {
    final selectedLabel = choices
        .firstWhere((choice) => choice.value == value)
        .label;
    final open = _openChoiceId == id;

    return GestureDetector(
      key: fieldKey,
      behavior: HitTestBehavior.opaque,
      onTap: () => open
          ? _closeChoiceMenu()
          : _openChoiceMenu<T>(
              id: id,
              fieldKey: fieldKey,
              selectedValue: value,
              choices: choices,
              onSelected: onSelected,
            ),
      child: InputDecorator(
        decoration: _dropdownDecoration(label, open: open),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selectedLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _blue,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(
              open
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: _red,
              size: 25,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final grid = <String, Map<String, Map<String, double>>>{};
    for (final visibility in AdvertisingPricingConfig.visibilityLabels.keys) {
      grid[visibility] = {};
      for (final radius in AdvertisingPricingConfig.radiusChoices) {
        final radiusKey = AdvertisingPricingConfig.radiusKey(radius);
        grid[visibility]![radiusKey] = {};
        for (final duration in AdvertisingPricingConfig.durations) {
          final value = double.tryParse(
            _controllers[_key(visibility, radius, duration)]!.text
                .trim()
                .replaceAll(',', '.'),
          );
          if (value == null || value <= 0) {
            setState(() {
              _saved = false;
              _error = 'Tous les montants de la grille doivent être supérieurs à zéro.';
            });
            return;
          }
          grid[visibility]![radiusKey]![duration] = value;
        }
      }
    }
    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });
    try {
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('advertisingPricing')
          .set({
            'localFlatPrices': grid,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (mounted) setState(() => _saved = true);
    } catch (error) {
      if (mounted) setState(() => _error = 'Enregistrement impossible.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _red));
    }
    return ListView(
      children: [
        _pricingCard(
          title: 'CAMPAGNES ANNONCEURS',
          subtitle: 'Sélectionnez une diffusion et un rayon, puis modifiez le prix HT de chaque durée.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _choiceField<String>(
                id: 'visibility',
                fieldKey: _visibilityFieldKey,
                label: 'DIFFUSION',
                value: _visibility,
                choices: AdvertisingPricingConfig.visibilityLabels.entries
                    .map((entry) => _PricingChoice(entry.key, entry.value))
                    .toList(),
                onSelected: (value) => setState(() {
                  _visibility = value;
                  _saved = false;
                  _error = null;
                }),
              ),
              const SizedBox(height: 12),
              _choiceField<double>(
                id: 'radius',
                fieldKey: _radiusFieldKey,
                label: 'RAYON D’ACTION',
                value: _radiusKm,
                choices: AdvertisingPricingConfig.radiusChoices
                    .map(
                      (radius) => _PricingChoice(
                        radius,
                        AdvertisingPricingConfig.radiusLabel(radius),
                      ),
                    )
                    .toList(),
                onSelected: (value) => setState(() {
                  _radiusKm = value;
                  _saved = false;
                  _error = null;
                }),
              ),
              const SizedBox(height: 18),
              for (final duration in AdvertisingPricingConfig.durations) ...[
                TextField(
                  controller: _controller(duration),
                  style: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.w800,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {
                    _saved = false;
                    _error = null;
                  }),
                  decoration: _tariffInputDecoration(
                    label: duration.toUpperCase(),
                    suffix: '€ HT',
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        if (_error != null) _errorText(_error!),
        const SizedBox(height: 12),
        _saveButton(
          saving: _saving,
          saved: _saved,
          label: 'ENREGISTRER LA GRILLE ANNONCEUR',
          onPressed: _save,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _choiceOverlay?.remove();
    _choiceOverlay = null;
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}

class _PricingChoice<T> {
  const _PricingChoice(this.value, this.label);

  final T value;
  final String label;
}

InputDecoration _tariffInputDecoration({
  required String label,
  required String suffix,
}) {
  const blue = Color(0xFF1E3A8A);
  const red = Color(0xFFDC2626);
  final enabledBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: blue, width: 1.25),
  );
  return InputDecoration(
    labelText: label,
    suffixText: suffix,
    labelStyle: const TextStyle(color: blue, fontWeight: FontWeight.w700),
    floatingLabelStyle: const TextStyle(
      color: blue,
      fontWeight: FontWeight.w800,
    ),
    suffixStyle: const TextStyle(color: blue, fontWeight: FontWeight.w700),
    filled: true,
    fillColor: Colors.white,
    border: enabledBorder,
    enabledBorder: enabledBorder,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: red, width: 1.8),
    ),
  );
}

Widget _pricingCard({
  required String title,
  required String subtitle,
  required Widget child,
}) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF1E3A8A), width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1E3A8A),
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF64748B),
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

Widget _priceRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF1E3A8A),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

Widget _errorText(String value) {
  return Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      value,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFFDC2626),
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

Widget _saveButton({
  required bool saving,
  required bool saved,
  required String label,
  required VoidCallback onPressed,
}) {
  return SizedBox(
    height: 50,
    child: FilledButton.icon(
      onPressed: saving ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: saved
            ? const Color(0xFFDC2626)
            : const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
      ),
      icon: saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : Icon(saved ? Icons.check_circle_outline : Icons.save_outlined),
      label: Text(
        saving
            ? 'ENREGISTREMENT…'
            : saved
            ? 'TARIFS ENREGISTRÉS'
            : label,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
  );
}
