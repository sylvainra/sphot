import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/advertiser_territory_service.dart';
import '../services/advertiser_initial_order_service.dart';
import '../services/odoo_local_order_service.dart';
import '../../shared/web_colors.dart';
import '../models/diffusion_preview_data.dart';
import '../models/planning_data.dart';

class QuoteOrderSection extends StatefulWidget {
  const QuoteOrderSection({
    super.key,
    required this.user,
    this.requestId,
    required this.radiusKm,
    required this.diffusionType,
    required this.planning,
    required this.costExclTax,
    required this.durationPrices,
    required this.onRadiusChanged,
    required this.onDiffusionChanged,
    this.selectedTerritory,
    this.pricingReference,
    this.pricingError,
    this.discountPercent = 0,
    this.payableExclTaxCents = 0,
    this.requestData = const <String, dynamic>{},
    this.testOrderEnabled = false,
    this.onRefreshPricing,
    required this.onEditStep,
    this.requestedScope = 'local',
  });

  final User? user;
  final String? requestId;
  final double radiusKm;
  final DiffusionPreviewType? diffusionType;
  final PlanningData planning;
  final int costExclTax;
  final Map<String, int> durationPrices;
  final ValueChanged<double> onRadiusChanged;
  final AdvertiserTerritory? selectedTerritory;
  final String? pricingReference;
  final String? pricingError;
  final int discountPercent;
  final int payableExclTaxCents;
  final Map<String, dynamic> requestData;
  final bool testOrderEnabled;
  final VoidCallback? onRefreshPricing;
  final ValueChanged<DiffusionPreviewType> onDiffusionChanged;
  final ValueChanged<int> onEditStep;
  final String requestedScope;

  @override
  State<QuoteOrderSection> createState() => _QuoteOrderSectionState();
}

class _QuoteOrderSectionState extends State<QuoteOrderSection> {
  String? get _requestId {
    final value = widget.requestId?.trim() ?? '';
    if (value.isNotEmpty) return value;
    return widget.user?.uid;
  }

  bool _loading = true;
  bool _confirming = false;
  String? _orderError;
  Map<String, dynamic>? _receipt;
  final AdvertiserInitialOrderService _orderService =
      const AdvertiserInitialOrderService();
  final OdooLocalOrderService _odooLocalService =
      const OdooLocalOrderService();
  String _professionalIdentity = 'À compléter';
  String _establishment = 'À compléter';

  @override
  void initState() {
    super.initState();
    _loadSummary();
    if (OdooLocalOrderService.enabled) _restoreLocalOrder();
  }

  Future<void> _restoreLocalOrder() async {
    final requestId = _requestId;
    if (requestId == null) return;
    try {
      final existing = await _odooLocalService.lookup(requestId);
      if (mounted && existing != null) {
        setState(() {
          _receipt = existing;
          _orderError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _orderError =
            'Lecture Odoo locale indisponible : $error');
      }
    }
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  String _firstText(
    Iterable<dynamic> values, {
    String fallback = 'À compléter',
  }) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  Future<void> _loadSummary() async {
    final requestId = _requestId;
    if (requestId != null) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('advertiserRequests')
            .doc(requestId)
            .get();
        final data = snapshot.data() ?? <String, dynamic>{};
        final identity = _map(data['professionalIdentity']);
        final profile = _map(data['professionalProfile']);
        final establishment = _map(data['establishment']);
        final name = _firstText([
          profile['displayName'],
          '${profile['displayFirstName'] ?? ''} ${profile['displayLastName'] ?? ''}',
          data['contactName'],
        ]);
        final email = _firstText([
          profile['professionalEmail'],
          identity['email'],
          data['email'],
        ], fallback: '');
        _professionalIdentity = email.isEmpty ? name : '$name • $email';
        final businessName = _firstText([
          establishment['businessName'],
          data['advertiserName'],
        ]);
        final city = _firstText([
          establishment['city'],
          data['centerCity'],
        ], fallback: '');
        _establishment = city.isEmpty ? businessName : '$businessName • $city';
      } catch (error) {
        debugPrint('Chargement récapitulatif devis impossible : $error');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'À définir';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String get _diffusionLabel {
    switch (widget.diffusionType) {
      case DiffusionPreviewType.map:
        return 'CARTE SPHOT';
      case DiffusionPreviewType.premium:
        return 'FICHES SPHOT';
      case DiffusionPreviewType.pack:
        return 'PACK VISIBILITÉ TOTALE';
      case null:
        return 'À sélectionner';
    }
  }

  String? get _selectedOffer => switch (widget.diffusionType) {
    DiffusionPreviewType.map => 'map',
    DiffusionPreviewType.premium => 'premium',
    DiffusionPreviewType.pack => 'pack',
    null => null,
  };

  String? _utcDay(dynamic value) {
    DateTime? date;
    if (value is Timestamp) date = value.toDate();
    if (value is DateTime) date = value;
    if (date == null) return null;
    return date.toUtc().toIso8601String().substring(0, 10);
  }

  bool get _savedChoicesMatch {
    final data = widget.requestData;
    final territory = _map(data['advertisingTerritory']);
    final diffusion = _map(data['diffusion']);
    final planning = _map(data['planning']);
    final selectedStart = widget.planning.startDate;
    final date = selectedStart == null
        ? null
        : '${selectedStart.year.toString().padLeft(4, '0')}-'
            '${selectedStart.month.toString().padLeft(2, '0')}-'
            '${selectedStart.day.toString().padLeft(2, '0')}';
    return territory['level'] == widget.selectedTerritory?.level.storageKey &&
        diffusion['visibilityType'] == _selectedOffer &&
        planning['durationLabel'] == widget.planning.durationLabel &&
        _utcDay(planning['campaignStartDate']) == date &&
        widget.planning.isComplete;
  }

  bool get _canConfirmTestOrder {
    final data = widget.requestData;
    return widget.testOrderEnabled && widget.user != null &&
        data['status'] == 'approved' &&
        data['advertisingSpotCompleted'] == true &&
        data['diffusionCompleted'] == true &&
        data['planningCompleted'] == true &&
        _savedChoicesMatch &&
        widget.pricingReference != null &&
        widget.pricingError == null &&
        widget.payableExclTaxCents > 0 &&
        _existingOrder == null && _pendingOtherOrder == null &&
        _receipt == null && !_confirming;
  }

  Map<String, dynamic>? get _existingOrder {
    if (widget.requestData['quoteOrderCompleted'] != true) return null;
    final order = _map(widget.requestData['order']);
    return order['origin'] == 'sphot_advertiser_initial_v1' ? order : null;
  }

  Map<String, dynamic>? get _confirmedOrder => _receipt ?? _existingOrder;

  int get _displayBaseCents =>
      (_confirmedOrder?['baseAmountExclTaxCents'] as num?)?.toInt() ??
      widget.costExclTax * 100;

  int get _displayPayableCents =>
      (_confirmedOrder?['odooUntaxedCents'] as num?)?.toInt() ??
      (_confirmedOrder?['payableExclTaxCents'] as num?)?.toInt() ??
      widget.payableExclTaxCents;

  int get _displayDiscount =>
      (_confirmedOrder?['discountPercent'] as num?)?.toInt() ??
      widget.discountPercent;

  String? get _pendingOtherOrder {
    if (widget.requestData['quoteOrderCompleted'] != true &&
        widget.requestData['order'] == null) return null;
    if (_existingOrder != null) return null;
    return 'Une commande existe déjà pour ce dossier : nouvelle '
        'confirmation indisponible.';
  }

  Future<void> _confirmTestOrder() async {
    if (!_canConfirmTestOrder) return;
    final requestId = _requestId;
    final territory = widget.selectedTerritory?.level.storageKey;
    final offer = _selectedOffer;
    final duration = widget.planning.durationLabel;
    final startDate = widget.planning.startDate;
    final reference = widget.pricingReference;
    if (requestId == null || territory == null || offer == null ||
        duration == null || startDate == null || reference == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(OdooLocalOrderService.enabled
            ? 'CONFIRMER LA COMMANDE DANS ODOO LOCAL'
            : 'CONFIRMER LA COMMANDE SPHOT TEST'),
        content: Text(
          'Commande de test : ${(widget.payableExclTaxCents / 100).toStringAsFixed(2)} € HT '
          '(TVA déterminée ultérieurement par Odoo).\n\n' +
          (OdooLocalOrderService.enabled
              ? 'Une véritable commande de TEST sera créée dans Odoo '
                  'sur cet ordinateur. Aucune facture, transaction bancaire '
                  'ou campagne active ne sera créée.'
              : 'La sélection enregistrée sera figée pour ce dossier. '
                  'Aucune facture, transaction bancaire ou campagne active '
                  'ne sera créée.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ANNULER'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CONFIRMER LE TEST'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _confirming = true;
      _orderError = null;
    });
    try {
      final day = '${startDate.year.toString().padLeft(4, '0')}-'
          '${startDate.month.toString().padLeft(2, '0')}-'
          '${startDate.day.toString().padLeft(2, '0')}';
      final result = OdooLocalOrderService.enabled
          ? await _odooLocalService.confirm(
              requestId: requestId,
              territory: territory,
              offer: offer,
              duration: duration,
              startDate: day,
              pricingReference: reference,
              payableExclTaxCents: widget.payableExclTaxCents,
            )
          : await _orderService.prepare(
              requestId: requestId,
              territory: territory,
              offer: offer,
              duration: duration,
              startDate: day,
              pricingReference: reference,
              payableExclTaxCents: widget.payableExclTaxCents,
            );
      if (!mounted) return;
      setState(() => _receipt = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _orderError = error.toString().replaceFirst(
          'Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Widget _summaryCard({
    required int step,
    required String title,
    required String value,
    required IconData icon,
    Widget? child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: WebColors.blue, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: WebColors.blue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Color(0xFF4B5F97),
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (step > 1)
                TextButton(
                  onPressed: () => widget.onEditStep(step),
                  child: const Text(
                    'MODIFIER',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
            ],
          ),
          if (child != null) ...[const SizedBox(height: 12), child],
        ],
      ),
    );
  }

  Widget _diffusionChoices() {
    const values = <DiffusionPreviewType, String>{
      DiffusionPreviewType.map: 'CARTE',
      DiffusionPreviewType.premium: 'FICHES SPHOT',
      DiffusionPreviewType.pack: 'PACK TOTAL',
    };
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: values.entries.map((entry) {
        final selected = widget.diffusionType == entry.key;
        return ChoiceChip(
          selected: selected,
          onSelected: _confirmedOrder == null
              ? (_) => widget.onDiffusionChanged(entry.key)
              : null,
          selectedColor: WebColors.red.withOpacity(0.12),
          side: BorderSide(color: selected ? WebColors.red : WebColors.blue),
          label: Text(
            entry.value,
            style: TextStyle(
              color: selected ? WebColors.red : WebColors.blue,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _pricingGrid() {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 4),
      title: const Text(
        'CONSULTER LA GRILLE TARIFAIRE',
        style: TextStyle(color: WebColors.blue, fontWeight: FontWeight.w900),
      ),
      children: widget.durationPrices.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  entry.key.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF4B5F97),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${entry.value} € HT',
                style: const TextStyle(
                  color: WebColors.blue,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: WebColors.red),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summaryCard(
          step: 0,
          title: 'IDENTITÉ PROFESSIONNELLE',
          value: _professionalIdentity,
          icon: Icons.verified_user_outlined,
        ),
        _summaryCard(
          step: 1,
          title: 'ÉTABLISSEMENT',
          value: _establishment,
          icon: Icons.storefront_outlined,
        ),
        _summaryCard(
          step: 2,
          title: 'ZONE DE DIFFUSION',
          value: widget.selectedTerritory == null
              ? 'À choisir à l’étape SPHOT PUBLICITAIRE'
              : widget.selectedTerritory!.level.label,
          icon: Icons.location_on_outlined,
        ),
        _summaryCard(
          step: 3,
          title: 'DIFFUSION',
          value: _diffusionLabel,
          icon: Icons.campaign_outlined,
          child: _diffusionChoices(),
        ),
        _summaryCard(
          step: 4,
          title: 'PLANIFICATION',
          value:
              '${widget.planning.durationLabel ?? 'À définir'} • ${_formatDate(widget.planning.startDate)} → ${_formatDate(widget.planning.endDate)}',
          icon: Icons.calendar_month_outlined,
        ),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: WebColors.red, width: 1.8),
          ),
          child: Column(
            children: [
              const Text(
                'COÛT',
                style: TextStyle(
                  color: WebColors.blue,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _displayBaseCents > 0
                    ? '${(_displayBaseCents / 100).toStringAsFixed(2)} € HT'
                    : 'TARIF PUBLIÉ INDISPONIBLE',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: WebColors.red,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (_displayBaseCents > 0) ...[
                if (_displayDiscount > 0) ...[
                  Text(
                    'REMISE CLIENT : -$_displayDiscount %',
                    style: const TextStyle(
                      color: WebColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'NET HT : ${(_displayPayableCents / 100).toStringAsFixed(2)} €',
                    style: const TextStyle(
                      color: WebColors.red,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
                const Text(
                  'TVA et montant TTC déterminés par Odoo suivant '
                  'le pays et la situation fiscale du client.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF4B5F97),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (_confirmedOrder?['pricingReference'] != null ||
                  widget.pricingReference != null)
                Text(
                  (_confirmedOrder?['pricingReference'] ??
                      widget.pricingReference).toString(),
                  style: const TextStyle(
                    color: WebColors.blue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (widget.pricingError != null)
                Text(
                  widget.pricingError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: WebColors.red),
                ),
              const SizedBox(height: 8),
              if (widget.durationPrices.isNotEmpty) _pricingGrid(),
            ],
          ),
        ),
        if (!widget.planning.isComplete)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'La planification doit être enregistrée ou revalidée avant la création du devis.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WebColors.red,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        if (widget.testOrderEnabled) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              border: Border.all(color: const Color(0xFFD97706)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'COMMANDE SPHOT — ENVIRONNEMENT DE TEST',
                  style: TextStyle(color: WebColors.blue,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(OdooLocalOrderService.enabled
                    ? 'Connexion directe à Odoo Community LOCAL. '
                        'La commande est enregistrée dans Odoo uniquement '
                        'après confirmation. Aucun paiement bancaire ni publicité '
                        'active ne sera déclenché.'
                    : 'La confirmation enregistre uniquement un dossier de '
                        'commande SPHOT TEST. Elle ne passe aucune commande '
                        'dans Odoo et ne déclenche ni paiement ni publicité.'),
                if (_existingOrder != null || _receipt != null) ...[
                  const SizedBox(height: 10),
                  Text('RÉFÉRENCE : ${(_receipt ?? _existingOrder)!['reference']}',
                      style: const TextStyle(fontWeight: FontWeight.w900,
                          color: WebColors.blue)),
                  if (_confirmedOrder?['odooOrderName'] != null) ...[
                    Text('COMMANDE ODOO : '
                        '${_confirmedOrder!['odooOrderName']}',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text('STATUT ODOO : '
                        '${_confirmedOrder!['odooState']}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('TOTAL ODOO : '
                        '${((_confirmedOrder!['odooTotalCents'] as num) / 100).toStringAsFixed(2)} € TTC',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (_confirmedOrder?['odooInvoiceName'] != null)
                      Text('FACTURE ODOO : '
                          '${_confirmedOrder!['odooInvoiceName']}'),
                    Text('RÈGLEMENT ODOO : '
                        '${_confirmedOrder!['paymentStatus'] ?? 'not_started'}'),
                  ] else
                    const Text('COMMANDE TEST ENREGISTRÉE — '
                        'EN ATTENTE DE RACCORDEMENT ODOO',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  const Text('Aucun paiement bancaire ; '
                      'campagne non activée (test local).'),
                ] else ...[
                  if (!_savedChoicesMatch)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Enregistrez puis réouvrez la diffusion et '
                          'la planification : les choix à l’écran doivent '
                          'correspondre aux choix sauvegardés.',
                          style: TextStyle(color: WebColors.red,
                              fontWeight: FontWeight.w800)),
                    ),
                  if (_pendingOtherOrder != null)
                    Text(_pendingOtherOrder!, style: const TextStyle(
                        color: WebColors.red, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _confirming ? null : widget.onRefreshPricing,
                    icon: const Icon(Icons.refresh),
                    label: const Text('ACTUALISER LE DEVIS'),
                  ),
                  FilledButton.icon(
                    onPressed: _canConfirmTestOrder ? _confirmTestOrder : null,
                    icon: _confirming
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.assignment_turned_in_outlined),
                    label: Text(_confirming
                        ? 'CONFIRMATION EN COURS…'
                        : 'CONFIRMER LA COMMANDE TEST'),
                  ),
                ],
                if (_orderError != null) ...[
                  const SizedBox(height: 8),
                  Text(_orderError!, style: const TextStyle(
                      color: WebColors.red, fontWeight: FontWeight.w800)),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
