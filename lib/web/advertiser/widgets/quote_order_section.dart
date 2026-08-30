import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../models/advertising_pricing_config.dart';
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
  String _professionalIdentity = 'À compléter';
  String _establishment = 'À compléter';

  @override
  void initState() {
    super.initState();
    _loadSummary();
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
        return 'FICHE SPHOT PREMIUM';
      case DiffusionPreviewType.pack:
        return 'PACK VISIBILITÉ TOTALE';
      case null:
        return 'À sélectionner';
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

  Widget _radiusChoices() {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: AdvertisingPricingConfig.radiusChoices.map((radius) {
        final selected = widget.radiusKm == radius;
        return ChoiceChip(
          selected: selected,
          onSelected: (_) => widget.onRadiusChanged(radius),
          selectedColor: WebColors.red.withOpacity(0.12),
          side: BorderSide(color: selected ? WebColors.red : WebColors.blue),
          label: Text(
            AdvertisingPricingConfig.radiusLabel(radius),
            style: TextStyle(
              color: selected ? WebColors.red : WebColors.blue,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _diffusionChoices() {
    const values = <DiffusionPreviewType, String>{
      DiffusionPreviewType.map: 'CARTE',
      DiffusionPreviewType.premium: 'PREMIUM',
      DiffusionPreviewType.pack: 'PACK TOTAL',
    };
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: values.entries.map((entry) {
        final selected = widget.diffusionType == entry.key;
        return ChoiceChip(
          selected: selected,
          onSelected: (_) => widget.onDiffusionChanged(entry.key),
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
    final vat = (widget.costExclTax * 0.20).round();
    final total = widget.costExclTax + vat;
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
          title: 'SPHOT PUBLICITAIRE ET RAYON',
          value: widget.requestedScope == 'national'
              ? 'Portée nationale'
              : widget.requestedScope == 'local_and_national'
              ? 'Portée nationale + ${AdvertisingPricingConfig.radiusLabel(widget.radiusKm)} en local'
              : AdvertisingPricingConfig.radiusLabel(widget.radiusKm),
          icon: Icons.location_on_outlined,
          child: widget.requestedScope == 'national' ? null : _radiusChoices(),
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
                '${widget.costExclTax} € HT',
                style: const TextStyle(
                  color: WebColors.red,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'TVA 20 % : $vat € • Total TTC : $total €',
                style: const TextStyle(
                  color: Color(0xFF4B5F97),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _pricingGrid(),
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
      ],
    );
  }
}
