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
    required this.initialPlanning,
    required this.onPlanningChanged,
  });

  final User? user;
  final LatLng? advertisingPosition;
  final double radiusKm;
  final bool hasDiffusionSelection;
  final bool developmentBypass;
  final PlanningData initialPlanning;
  final ValueChanged<PlanningData> onPlanningChanged;

  @override
  State<PlanningSection> createState() => _PlanningSectionState();
}

class _PlanningSectionState extends State<PlanningSection> {
  String _durationLabel = AdvertisingPricingConfig.durations.first;
  late DateTime _startDate;
  late DateTime _endDate;
  bool _loading = true;
  bool _checking = false;
  bool _saving = false;
  bool _saved = false;
  bool _availabilityChecked = false;
  bool _available = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    _durationLabel =
        widget.initialPlanning.durationLabel ??
        AdvertisingPricingConfig.durations.first;
    _startDate = widget.initialPlanning.startDate ?? today;
    _endDate = _calculateEndDate(_startDate, _durationLabel);
    _load();
  }

  @override
  void didUpdateWidget(covariant PlanningSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.advertisingPosition != widget.advertisingPosition ||
        oldWidget.radiusKm != widget.radiusKm ||
        oldWidget.hasDiffusionSelection != widget.hasDiffusionSelection) {
      _availabilityChecked = false;
      _available = false;
      _saved = false;
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _notifyPlanning();
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
    final firstTargetMonth = DateTime(start.year, start.month + months, 1);
    final lastTargetDay = DateTime(
      firstTargetMonth.year,
      firstTargetMonth.month + 1,
      0,
    ).day;
    return DateTime(
      firstTargetMonth.year,
      firstTargetMonth.month,
      start.day > lastTargetDay ? lastTargetDay : start.day,
    );
  }

  DateTime _calculateEndDate(DateTime start, String durationLabel) {
    switch (durationLabel) {
      case '15 jours':
        return start.add(const Duration(days: 15));
      case '1 mois':
        return _addMonths(start, 1);
      case '3 mois':
        return _addMonths(start, 3);
      case '6 mois':
        return _addMonths(start, 6);
      case '12 mois':
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

  String get _radiusLabel =>
      AdvertisingPricingConfig.radiusLabel(widget.radiusKm);

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
        _saved = snapshot.data()?['planningCompleted'] == true;
        _availabilityChecked =
            _saved && planning['availabilityStatus'] == 'available';
        _available = _availabilityChecked;
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

  void _notifyPlanning() {
    widget.onPlanningChanged(
      PlanningData(
        durationLabel: _durationLabel,
        startDate: _startDate,
        endDate: _endDate,
        exclusiveReservation: true,
        availabilityConfirmed: _availabilityChecked && _available,
      ),
    );
  }

  void _selectDuration(String value) {
    setState(() {
      _durationLabel = value;
      _endDate = _calculateEndDate(_startDate, value);
      _availabilityChecked = false;
      _available = false;
      _saved = false;
      _error = null;
    });
    _notifyPlanning();
  }

  Future<void> _pickStartDate() async {
    final today = _dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate.isBefore(today) ? today : _startDate,
      firstDate: today,
      lastDate: DateTime(today.year + 3, today.month, today.day),
      helpText: 'DATE DE DÉBUT DE CAMPAGNE',
      cancelText: 'ANNULER',
      confirmText: 'VALIDER',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startDate = _dateOnly(picked);
      _endDate = _calculateEndDate(_startDate, _durationLabel);
      _availabilityChecked = false;
      _available = false;
      _saved = false;
      _error = null;
    });
    _notifyPlanning();
  }

  bool _periodsOverlap(
    DateTime firstStart,
    DateTime firstEnd,
    DateTime secondStart,
    DateTime secondEnd,
  ) {
    return !firstEnd.isBefore(secondStart) && !secondEnd.isBefore(firstStart);
  }

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
    final boundedHaversine = haversine.clamp(0.0, 1.0).toDouble();
    return earthRadiusKm *
        2 *
        math.atan2(
          math.sqrt(boundedHaversine),
          math.sqrt(1 - boundedHaversine),
        );
  }

  Future<bool> _checkAvailability() async {
    final position = widget.advertisingPosition;
    if (position == null) {
      setState(() {
        _error = 'Définissez d’abord le SPHOT publicitaire à l’étape 3.';
      });
      return false;
    }
    if (!widget.hasDiffusionSelection) {
      setState(() {
        _error = 'Sélectionnez d’abord une offre de diffusion à l’étape 4.';
      });
      return false;
    }

    setState(() {
      _checking = true;
      _error = null;
      _availabilityChecked = false;
      _available = false;
    });

    if (widget.developmentBypass && widget.user == null) {
      setState(() {
        _checking = false;
        _availabilityChecked = true;
        _available = true;
        _saved = false;
      });
      _notifyPlanning();
      return true;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('adRequests')
          .get();
      var conflictFound = false;

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

        final existingStart = _toDate(data['campaignStartDate']);
        final existingEnd = _toDate(data['campaignEndDate']);
        if (existingStart == null ||
            existingEnd == null ||
            !_periodsOverlap(
              _startDate,
              _endDate,
              existingStart,
              existingEnd,
            )) {
          continue;
        }

        final latitude = _toDouble(data['centerLat']);
        final longitude = _toDouble(data['centerLng']);
        if (latitude == null || longitude == null) continue;

        final existingRadius = _toDouble(data['radiusKm']) ?? 0;
        final exclusiveDistance = widget.radiusKm + existingRadius;
        final minimumSpotTolerance = exclusiveDistance <= 0 ? 0.025 : 0.0;
        final separationKm = _distanceKm(position, LatLng(latitude, longitude));
        if (separationKm <= exclusiveDistance + minimumSpotTolerance) {
          conflictFound = true;
          break;
        }
      }

      if (!mounted) return false;
      setState(() {
        _availabilityChecked = true;
        _available = !conflictFound;
        _saved = false;
        if (conflictFound) {
          _error = 'Cette zone est déjà réservée par une autre campagne pendant tout ou partie de la période choisie.';
        }
      });
      _notifyPlanning();
      return !conflictFound;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _error = 'La disponibilité ne peut pas être vérifiée pour le moment. Réessayez.';
      });
      debugPrint('Vérification disponibilité publicitaire impossible : $error');
      return false;
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _save() async {
    if (!await _checkAvailability()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

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
                'latitude': widget.advertisingPosition!.latitude,
                'longitude': widget.advertisingPosition!.longitude,
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

  Widget _card({required Widget child}) {
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

  Widget _title(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: WebColors.blue, size: 30),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: WebColors.blue,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dateBox({
    required String label,
    required DateTime value,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: WebColors.blue, width: 1.3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: WebColors.blue, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: WebColors.blue,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _formatDate(value),
                style: const TextStyle(
                  color: WebColors.blue,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
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

    final availabilityColor = !_availabilityChecked
        ? const Color(0xFF6B7280)
        : _available
        ? const Color(0xFF15803D)
        : WebColors.red;
    final availabilityLabel = !_availabilityChecked
        ? 'DISPONIBILITÉ À VÉRIFIER'
        : _available
        ? 'ZONE ET PÉRIODE DISPONIBLES'
        : 'ZONE OU PÉRIODE INDISPONIBLE';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(
                Icons.verified_user_outlined,
                'RÉSERVATION EXCLUSIVE',
                'Une seule campagne publicitaire peut être diffusée dans la zone sélectionnée pendant la période définie.',
              ),
              const SizedBox(height: 14),
              Text(
                'Zone réservée : $_radiusLabel',
                style: const TextStyle(
                  color: WebColors.red,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Toute campagne dont la zone et les dates se chevauchent sera refusée. Il n’y a ni alternance ni rotation entre annonceurs.',
                style: TextStyle(
                  color: Color(0xFF4B5F97),
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(
                Icons.calendar_month_outlined,
                'PÉRIODE DE DIFFUSION',
                'Choisissez une durée puis la date de début de la campagne.',
              ),
              const SizedBox(height: 16),
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
                      backgroundColor: selected
                          ? WebColors.red.withOpacity(0.045)
                          : Colors.white,
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
              Row(
                children: [
                  _dateBox(
                    label: 'DÉBUT',
                    value: _startDate,
                    icon: Icons.edit_calendar_outlined,
                    onTap: _pickStartDate,
                  ),
                  const SizedBox(width: 10),
                  _dateBox(
                    label: 'FIN CALCULÉE',
                    value: _endDate,
                    icon: Icons.event_available_outlined,
                  ),
                ],
              ),
            ],
          ),
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(
                Icons.radar_outlined,
                'DISPONIBILITÉ',
                'La zone et les dates sont comparées aux campagnes déjà réservées.',
              ),
              const SizedBox(height: 8),
              const Text(
                'La disponibilité sera contrôlée une dernière fois lors de la validation de la commande.',
                style: TextStyle(
                  color: Color(0xFF4B5F97),
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                availabilityLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: availabilityColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _checking ? null : _checkAvailability,
                icon: _checking
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.manage_search_outlined),
                label: Text(
                  _checking ? 'VÉRIFICATION…' : 'VÉRIFIER LA DISPONIBILITÉ',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: WebColors.blue,
                  side: const BorderSide(color: WebColors.blue, width: 1.4),
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
            onPressed: _saving || _checking ? null : _save,
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
