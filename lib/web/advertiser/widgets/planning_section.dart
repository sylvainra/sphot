

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/advertising_pricing_config.dart';
import '../../shared/web_colors.dart';
import '../models/planning_data.dart';
import '../services/advertiser_phase_two_write_service.dart';

class PlanningSection extends StatefulWidget {
  const PlanningSection({
    super.key,
    required this.user,
    this.requestId,
    required this.advertisingPosition,
    required this.radiusKm,
    required this.hasDiffusionSelection,
    required this.developmentBypass,
    required this.costExclTax,
    this.pricingReference,
    this.pricingError,
    this.pricingLoading = false,
    this.onRefreshPricing,
    this.durationPrices = const {},
    this.discountPercent = 0,
    this.payableExclTaxCents = 0,
    required this.initialPlanning,
    required this.onPlanningChanged,
    this.requestedScope = 'local',
    this.activityType = '',
  });

  final User? user;
  final String? requestId;
  final LatLng? advertisingPosition;
  final double radiusKm;
  final bool hasDiffusionSelection;
  final bool developmentBypass;
  final int costExclTax;
  final String? pricingReference;
  final String? pricingError;
  final bool pricingLoading;
  final VoidCallback? onRefreshPricing;
  final Map<String, int> durationPrices;
  final int discountPercent;
  final int payableExclTaxCents;
  final PlanningData initialPlanning;
  final ValueChanged<PlanningData> onPlanningChanged;
  final String requestedScope;
  final String activityType;

  @override
  State<PlanningSection> createState() => _PlanningSectionState();
}

class _PlanningSectionState extends State<PlanningSection> {
  String? get _requestId {
    final value = widget.requestId?.trim() ?? '';
    if (value.isNotEmpty) return value;
    return widget.user?.uid;
  }

  String _durationLabel = '1 semaine';
  late DateTime _startDate;
  late DateTime _endDate;
  late DateTime _displayedMonth;

  bool _loading = true;
  bool _saving = false;
  bool _saved = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    final initialDuration = widget.initialPlanning.durationLabel;
    if (initialDuration != null &&
        AdvertisingPricingConfig.durations.contains(initialDuration)) {
      _durationLabel = initialDuration;
    }
    _startDate = widget.initialPlanning.startDate ?? today;
    _endDate = _calculateEndDate(_startDate, _durationLabel);
    _displayedMonth = DateTime(_startDate.year, _startDate.month);
    _load();
  }



  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
  }

  String _normaliseActivity(Object? value) {
    return (value ?? '').toString().trim().toLowerCase();
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return _dateOnly(value.toDate());
    if (value is DateTime) return _dateOnly(value);
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return _dateOnly(parsed);
    }
    return null;
  }

  DateTime _addMonths(DateTime start, int months) {
    final target = DateTime(start.year, start.month + months, 1);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(
      target.year,
      target.month,
      start.day > lastDay ? lastDay : start.day,
    );
  }

  DateTime _calculateEndDate(DateTime start, String durationLabel) {
    switch (durationLabel) {
      case '1 semaine':
        return start.add(const Duration(days: 7));
      case '2 semaines':
        return start.add(const Duration(days: 14));
      case '1 mois':
        return _addMonths(start, 1);
      case '2 mois':
        return _addMonths(start, 2);
      case '6 mois':
        return _addMonths(start, 6);
      case '1 an':
        return _addMonths(start, 12);
      default:
        return start;
    }
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String _monthLabel(DateTime value) {
    const months = <String>[
      'JANVIER',
      'FÉVRIER',
      'MARS',
      'AVRIL',
      'MAI',
      'JUIN',
      'JUILLET',
      'AOÛT',
      'SEPTEMBRE',
      'OCTOBRE',
      'NOVEMBRE',
      'DÉCEMBRE',
    ];
    return '${months[value.month - 1]} ${value.year}';
  }

  bool _isSameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;


  Future<void> _load() async {
    final requestId = _requestId;
    if (requestId != null) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('advertiserRequests')
            .doc(requestId)
            .get();
        final planning = _map(snapshot.data()?['planning']);
        final savedDuration = planning['durationLabel']?.toString();
        final savedStart = _toDate(planning['campaignStartDate']);
        if (savedDuration != null &&
            AdvertisingPricingConfig.durations.contains(savedDuration)) {
          _durationLabel = savedDuration;
        }
        if (savedStart != null) _startDate = savedStart;
        _endDate = _calculateEndDate(_startDate, _durationLabel);
        _displayedMonth = DateTime(_startDate.year, _startDate.month);
        _saved = snapshot.data()?['planningCompleted'] == true;
      } catch (error) {
        debugPrint('Chargement planification annonceur impossible : $error');
        _error = 'Impossible de charger la planification enregistrée.';
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifyPlanning();
    });
  }

  bool get _datesAreValid =>
      !_startDate.isBefore(_dateOnly(DateTime.now())) &&
      _endDate.isAfter(_startDate);


  void _notifyPlanning() {
    widget.onPlanningChanged(
      PlanningData(
        durationLabel: _durationLabel,
        startDate: _startDate,
        endDate: _endDate,
        exclusiveReservation: false,
        availabilityConfirmed: _datesAreValid,
      ),
    );
  }

  void _selectDuration(String value) {
    final newEnd = _calculateEndDate(_startDate, value);
    setState(() {
      _durationLabel = value;
      _endDate = newEnd;
      _saved = false;
      _error = null;
    });
    _notifyPlanning();
  }

  void _selectStartDate(DateTime value) {
    final today = _dateOnly(DateTime.now());
    if (value.isBefore(today)) return;
    final newEnd = _calculateEndDate(value, _durationLabel);
    setState(() {
      _startDate = value;
      _endDate = newEnd;
      _saved = false;
      _error = null;
    });
    _notifyPlanning();
  }

  Future<void> _save() async {
    if (widget.advertisingPosition == null) {
      setState(() {
        _error = 'Définissez d’abord le SPHOT PUBLICITAIRE à l’étape 3.';
      });
      return;
    }
    if (!widget.hasDiffusionSelection) {
      setState(() {
        _error = 'Sélectionnez d’abord une diffusion à l’étape 4.';
      });
      return;
    }
    if (!_datesAreValid) {
      setState(() => _error =
          'Choisissez une date de début actuelle ou future.');
      return;
    }
    setState(() => _saving = true);
    try {
      final requestId = _requestId;
      if (requestId == null || requestId.isEmpty) {
        throw StateError('Dossier annonceur introuvable.');
      }
      final date = '${_startDate.year.toString().padLeft(4, '0')}-'
          '${_startDate.month.toString().padLeft(2, '0')}-'
          '${_startDate.day.toString().padLeft(2, '0')}';
      await AdvertiserPhaseTwoWriteService.save(
        requestId: requestId,
        action: 'savePlanning',
        payload: <String, Object?>{
          'durationLabel': _durationLabel,
          'startDate': date,
        },
      );
      if (!mounted) return;
      setState(() => _saved = true);
      _notifyPlanning();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'L’enregistrement a échoué. Réessayez.');
      debugPrint('Enregistrement planification annonceur impossible : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _card(Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: child,
    );
  }

  Widget _calendar() {
    final firstDay = DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    final daysInMonth = DateTime(
      _displayedMonth.year,
      _displayedMonth.month + 1,
      0,
    ).day;
    final leadingDays = firstDay.weekday - 1;
    final cellCount = leadingDays + daysInMonth;
    final rowCount = (cellCount / 7).ceil();
    final today = _dateOnly(DateTime.now());

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() {
                _displayedMonth = DateTime(
                  _displayedMonth.year,
                  _displayedMonth.month - 1,
                );
              }),
              icon: const Icon(Icons.chevron_left, color: WebColors.blue),
            ),
            Expanded(
              child: Text(
                _monthLabel(_displayedMonth),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: WebColors.blue,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              onPressed: () => setState(() {
                _displayedMonth = DateTime(
                  _displayedMonth.year,
                  _displayedMonth.month + 1,
                );
              }),
              icon: const Icon(Icons.chevron_right, color: WebColors.blue),
            ),
          ],
        ),
        Row(
          children: [
            for (final label in const ['L', 'M', 'M', 'J', 'V', 'S', 'D'])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (var row = 0; row < rowCount; row++)
          Row(
            children: List.generate(7, (column) {
              final dayNumber = row * 7 + column - leadingDays + 1;
              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return const Expanded(child: SizedBox(height: 42));
              }
              final day = DateTime(
                _displayedMonth.year,
                _displayedMonth.month,
                dayNumber,
              );

              final selected =
                  !day.isBefore(_startDate) && !day.isAfter(_endDate);
              final disabled = day.isBefore(today);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: InkWell(
                    onTap: disabled ? null : () => _selectStartDate(day),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? WebColors.blue.withOpacity(0.13)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: _isSameDay(day, _startDate)
                              ? WebColors.blue
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        '$dayNumber',
                        style: TextStyle(
                          color: disabled
                              ? const Color(0xFFB0B7C3)
                              : WebColors.blue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        const SizedBox(height: 10),
        const Wrap(
          spacing: 14,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [

            _CalendarLegend(color: WebColors.blue, label: 'Votre période'),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(color: WebColors.red)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.shield_outlined,
                color: WebColors.blue,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PLANIFICATION DE LA CAMPAGNE',
                      style: TextStyle(
                        color: WebColors.blue,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'La diffusion respecte les dates et la zone géographique choisie. '
                          'Plusieurs annonceurs peuvent diffuser simultanément. '
                          'Les SPHOTS PUBLICITAIRES alternent équitablement, sans exclusivité.',
                      style: const TextStyle(
                        color: Color(0xFF4B5F97),
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    color: WebColors.blue,
                    size: 30,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'PÉRIODE DE DIFFUSION',
                      style: TextStyle(
                        color: WebColors.blue,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Choisissez une durée puis sélectionnez la date de début souhaitée dans le calendrier.',
                style: TextStyle(
                  color: Color(0xFF4B5F97),
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AdvertisingPricingConfig.durations.map((duration) {
                  final selected = duration == _durationLabel;
                  return OutlinedButton(
                    onPressed: () => _selectDuration(duration),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: selected
                          ? WebColors.red
                          : WebColors.blue,
                      side: BorderSide(
                        color: selected ? WebColors.red : WebColors.blue,
                        width: selected ? 2 : 1.3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    child: Text(
                      duration.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              _calendar(),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: _DateSummary(
                      label: 'DÉBUT',
                      value: _formatDate(_startDate),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateSummary(
                      label: 'FIN CALCULÉE',
                      value: _formatDate(_endDate),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _card(
          Column(
            children: [
              const Text(
                'COÛT',
                style: TextStyle(
                  color: WebColors.blue,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.pricingLoading
                    ? 'CHARGEMENT DES TARIFS…'
                    : widget.costExclTax > 0
                        ? '${widget.costExclTax} € HT'
                        : 'TARIF PUBLIÉ NON DISPONIBLE',
                style: const TextStyle(
                  color: WebColors.red,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (widget.costExclTax > 0 &&
                  widget.discountPercent > 0) ...[
                const SizedBox(height: 5),
                Text(
                  'Remise client : -${widget.discountPercent} %',
                  style: const TextStyle(
                    color: WebColors.blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'NET HT : ${(widget.payableExclTaxCents / 100).toStringAsFixed(2)} €',
                  style: const TextStyle(
                    color: WebColors.red,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                widget.pricingReference == null
                    ? 'Référence tarifaire : en attente de publication'
                    : 'Référence : ${widget.pricingReference}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: WebColors.blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (widget.pricingError != null)
                Text(
                  widget.pricingError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: WebColors.red),
                ),
              if (widget.onRefreshPricing != null)
                TextButton.icon(
                  onPressed: widget.pricingLoading
                      ? null
                      : widget.onRefreshPricing,
                  icon: const Icon(Icons.refresh),
                  label: const Text('ACTUALISER LES TARIFS PUBLIÉS'),
                ),
              if (widget.durationPrices.isNotEmpty)
                ExpansionTile(
                  title: const Text(
                    'CONSULTER LES TARIFS PUBLIÉS',
                    style: TextStyle(
                      color: WebColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  children: [
                    for (final entry in widget.durationPrices.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(child: Text(entry.key)),
                            Text('${entry.value} € HT'),
                          ],
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 4),
              Text(
                'Du ${_formatDate(_startDate)} au ${_formatDate(_endDate)}',
                style: const TextStyle(
                  color: Color(0xFF4B5F97),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WebColors.red,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _saved ? WebColors.red : WebColors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(
                    _saved
                        ? Icons.check_circle_outline_rounded
                        : Icons.save_outlined,
                  ),
            label: Text(
              _saving
                  ? 'ENREGISTREMENT…'
                  : _saved
                  ? 'PLANIFICATION ENREGISTRÉE'
                  : 'ENREGISTRER LA PLANIFICATION',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color.withOpacity(0.18),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF4B5F97),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _DateSummary extends StatelessWidget {
  const _DateSummary({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebColors.blue, width: 1.3),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: WebColors.blue,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
