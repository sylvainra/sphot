import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/advertising_pricing_config.dart';
import '../../shared/web_colors.dart';
import '../models/planning_data.dart';

class PlanningSection extends StatefulWidget {
  const PlanningSection({
    super.key,
    required this.user,
    required this.advertisingPosition,
    required this.radiusKm,
    required this.hasDiffusionSelection,
    required this.developmentBypass,
    required this.costExclTax,
    required this.initialPlanning,
    required this.onPlanningChanged,
  });

  final User? user;
  final LatLng? advertisingPosition;
  final double radiusKm;
  final bool hasDiffusionSelection;
  final bool developmentBypass;
  final int costExclTax;
  final PlanningData initialPlanning;
  final ValueChanged<PlanningData> onPlanningChanged;

  @override
  State<PlanningSection> createState() => _PlanningSectionState();
}

class _PlanningSectionState extends State<PlanningSection> {
  String _durationLabel = '1 semaine';
  late DateTime _startDate;
  late DateTime _endDate;
  late DateTime _displayedMonth;
  List<DateTimeRange> _reservedPeriods = const [];
  bool _loading = true;
  bool _saving = false;
  bool _saved = false;
  bool _reservationsLoaded = false;
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

  @override
  void didUpdateWidget(covariant PlanningSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.advertisingPosition != widget.advertisingPosition ||
        oldWidget.radiusKm != widget.radiusKm) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshReservations();
      });
    }
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

  bool _periodsOverlap(
    DateTime firstStart,
    DateTime firstEnd,
    DateTime secondStart,
    DateTime secondEnd,
  ) {
    return !firstEnd.isBefore(secondStart) && !secondEnd.isBefore(firstStart);
  }

  bool _isSameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  bool _isReserved(DateTime day) => _reservedPeriods.any(
    (period) =>
        !day.isBefore(_dateOnly(period.start)) &&
        !day.isAfter(_dateOnly(period.end)),
  );

  bool _hasConflict(DateTime start, DateTime end) => _reservedPeriods.any(
    (period) => _periodsOverlap(
      start,
      end,
      _dateOnly(period.start),
      _dateOnly(period.end),
    ),
  );

  double _distanceKm(LatLng first, LatLng second) {
    const earthRadiusKm = 6371.0;
    final latitudeDelta = (second.latitude - first.latitude) * math.pi / 180;
    final longitudeDelta = (second.longitude - first.longitude) * math.pi / 180;
    final firstLatitude = first.latitude * math.pi / 180;
    final secondLatitude = second.latitude * math.pi / 180;
    final haversine =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(firstLatitude) *
            math.cos(secondLatitude) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    final bounded = haversine.clamp(0.0, 1.0).toDouble();
    return earthRadiusKm *
        2 *
        math.atan2(math.sqrt(bounded), math.sqrt(1 - bounded));
  }

  Future<List<DateTimeRange>> _fetchReservedPeriods() async {
    final position = widget.advertisingPosition;
    if (position == null) return const [];
    if (widget.developmentBypass && widget.user == null) return const [];

    final snapshot = await FirebaseFirestore.instance
        .collection('adRequests')
        .get();
    final periods = <DateTimeRange>[];
    for (final document in snapshot.docs) {
      final data = document.data();
      final status = (data['status'] ?? '').toString().toLowerCase();
      if (<String>{
        'cancelled',
        'deleted',
        'disabled',
        'finished',
        'rejected',
      }.contains(status)) {
        continue;
      }
      if ((data['broadcastType'] ?? 'local').toString() == 'national') {
        continue;
      }

      final latitude = _toDouble(data['centerLat']);
      final longitude = _toDouble(data['centerLng']);
      final start = _toDate(data['campaignStartDate']);
      final end = _toDate(data['campaignEndDate']);
      if (latitude == null ||
          longitude == null ||
          start == null ||
          end == null) {
        continue;
      }

      final existingRadius = _toDouble(data['radiusKm']) ?? 0;
      final exclusiveDistance = widget.radiusKm + existingRadius;
      final tolerance = exclusiveDistance <= 0 ? 0.025 : 0.0;
      final separation = _distanceKm(position, LatLng(latitude, longitude));
      if (separation <= exclusiveDistance + tolerance) {
        periods.add(DateTimeRange(start: start, end: end));
      }
    }
    return periods;
  }

  Future<void> _load() async {
    final user = widget.user;
    if (user != null) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('advertiserRequests')
            .doc(user.uid)
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
    try {
      _reservedPeriods = await _fetchReservedPeriods();
      _reservationsLoaded = true;
    } catch (error) {
      debugPrint('Chargement réservations publicitaires impossible : $error');
      _error = 'Impossible de charger le calendrier des réservations.';
    }
    if (!mounted) return;
    setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifyPlanning();
    });
  }

  Future<void> _refreshReservations() async {
    setState(() {
      _reservationsLoaded = false;
      _saved = false;
      _error = null;
    });
    try {
      final periods = await _fetchReservedPeriods();
      if (!mounted) return;
      setState(() {
        _reservedPeriods = periods;
        _reservationsLoaded = true;
        if (_hasConflict(_startDate, _endDate)) {
          _error = 'La période sélectionnée contient déjà des dates réservées.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Impossible d’actualiser les réservations.');
    }
    _notifyPlanning();
  }

  bool get _selectionIsAvailable =>
      _reservationsLoaded && !_hasConflict(_startDate, _endDate);

  void _notifyPlanning() {
    widget.onPlanningChanged(
      PlanningData(
        durationLabel: _durationLabel,
        startDate: _startDate,
        endDate: _endDate,
        exclusiveReservation: true,
        availabilityConfirmed: _selectionIsAvailable,
      ),
    );
  }

  void _selectDuration(String value) {
    final newEnd = _calculateEndDate(_startDate, value);
    setState(() {
      _durationLabel = value;
      _endDate = newEnd;
      _saved = false;
      _error = _hasConflict(_startDate, newEnd)
          ? 'Cette durée traverse une période déjà réservée.'
          : null;
    });
    _notifyPlanning();
  }

  void _selectStartDate(DateTime value) {
    final today = _dateOnly(DateTime.now());
    if (value.isBefore(today) || _isReserved(value)) return;
    final newEnd = _calculateEndDate(value, _durationLabel);
    if (_hasConflict(value, newEnd)) {
      setState(() {
        _error =
            'Cette période contient une ou plusieurs dates déjà réservées.';
      });
      return;
    }
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
        _error = 'Définissez d’abord le SPHOT publicitaire à l’étape 3.';
      });
      return;
    }
    if (!widget.hasDiffusionSelection) {
      setState(() {
        _error = 'Sélectionnez d’abord une diffusion à l’étape 4.';
      });
      return;
    }
    setState(() => _saving = true);
    await _refreshReservations();
    if (!mounted) return;
    if (!_selectionIsAvailable) {
      setState(() {
        _saving = false;
        _error =
            'Cette période n’est plus disponible. Choisissez d’autres dates.';
      });
      return;
    }
    try {
      final user = widget.user;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('advertiserRequests')
            .doc(user.uid)
            .set({
              'uid': user.uid,
              'planningCompleted': true,
              'planning': <String, Object?>{
                'durationLabel': _durationLabel,
                'campaignStartDate': Timestamp.fromDate(_startDate),
                'campaignEndDate': Timestamp.fromDate(_endDate),
                'exclusiveReservation': true,
                'availabilityStatus': 'available',
                'radiusKm': widget.radiusKm,
                'confirmedAt': FieldValue.serverTimestamp(),
              },
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }
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
              final reserved = _isReserved(day);
              final selected =
                  !day.isBefore(_startDate) && !day.isAfter(_endDate);
              final disabled = day.isBefore(today) || reserved;
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
                        color: reserved
                            ? WebColors.red.withOpacity(0.18)
                            : selected
                            ? WebColors.blue.withOpacity(0.13)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: _isSameDay(day, _startDate)
                              ? WebColors.blue
                              : reserved
                              ? WebColors.red
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        '$dayNumber',
                        style: TextStyle(
                          color: disabled
                              ? reserved
                                    ? WebColors.red
                                    : const Color(0xFFB0B7C3)
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
            _CalendarLegend(color: WebColors.red, label: 'Déjà réservé'),
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
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, color: WebColors.blue, size: 30),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PLANIFICATION EXCLUSIVE',
                      style: TextStyle(
                        color: WebColors.blue,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 7),
                    Text(
                      'Une seule campagne publicitaire peut être active dans le rayon et pendant la période choisis. Les dates déjà réservées apparaissent directement dans le calendrier.',
                      style: TextStyle(
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
                'Choisissez une durée puis sélectionnez le premier jour disponible dans le calendrier.',
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
                '${widget.costExclTax} € HT',
                style: const TextStyle(
                  color: WebColors.red,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
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
