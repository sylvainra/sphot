import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/sauveteur_live_publication_service.dart';
import 'widgets/sauveteur_adaptive_viewport.dart';

enum SauveteurMaterielCategory {
  phonie,
  roulant,
  flottant,
}

class SauveteurMaterielCategoryVerificationPage extends StatefulWidget {
  const SauveteurMaterielCategoryVerificationPage({
    super.key,
    required this.category,
    required this.profileColor,
    required this.territoireId,
    required this.sauveteurSessionToken,
    required this.postesAffectes,
    required this.initialSpotId,
    required this.sphotMode,
  });

  final SauveteurMaterielCategory category;
  final Color profileColor;
  final String territoireId;
  final String sauveteurSessionToken;
  final List<String> postesAffectes;
  final String? initialSpotId;
  final String sphotMode;

  @override
  State<SauveteurMaterielCategoryVerificationPage> createState() =>
      _SauveteurMaterielCategoryVerificationPageState();
}

class _SauveteurMaterielCategoryVerificationPageState
    extends State<SauveteurMaterielCategoryVerificationPage> {
  static const _blue = Color(0xFF1E3A8A);
  static const _green = Color(0xFF15803D);
  static const _orange = Color(0xFFF59E0B);
  static const _red = Color(0xFFDC2626);

  final TextEditingController _remarksController = TextEditingController();
  final Map<String, bool> _checks = <String, bool>{};

  String? _selectedSpotId;
  String? _spotLabel;
  bool _loading = true;
  bool _saving = false;
  String? _message;

  double _vhfBattery = 100;
  double _phoneBattery = 100;
  double _otherCommsBattery = 100;

  bool get _isSphotOn => widget.sphotMode.toUpperCase() == 'ON';

  String get _pageTitle {
    switch (widget.category) {
      case SauveteurMaterielCategory.phonie:
        return 'VÉRIFICATION PHONIE';
      case SauveteurMaterielCategory.roulant:
        return 'MATÉRIEL ROULANT';
      case SauveteurMaterielCategory.flottant:
        return 'MATÉRIEL FLOTTANT';
    }
  }

  String get _categoryLabel {
    switch (widget.category) {
      case SauveteurMaterielCategory.phonie:
        return 'Phonie / communications';
      case SauveteurMaterielCategory.roulant:
        return 'Matériel roulant';
      case SauveteurMaterielCategory.flottant:
        return 'Matériel flottant';
    }
  }

  IconData get _categoryIcon {
    switch (widget.category) {
      case SauveteurMaterielCategory.phonie:
        return Icons.wifi_tethering_rounded;
      case SauveteurMaterielCategory.roulant:
        return Icons.directions_car_filled_rounded;
      case SauveteurMaterielCategory.flottant:
        return Icons.directions_boat_filled_rounded;
    }
  }

  List<_VerificationCriterion> get _criteria {
    switch (widget.category) {
      case SauveteurMaterielCategory.phonie:
        return const [
          _VerificationCriterion(
            keyName: 'vhfWorking',
            title: 'VHF',
            subtitle: 'Émission, réception et commandes fonctionnelles',
            icon: Icons.settings_input_antenna_rounded,
          ),
          _VerificationCriterion(
            keyName: 'phonesWorking',
            title: 'Téléphones',
            subtitle: 'Appels, réseau et fonctionnement conformes',
            icon: Icons.phone_android_rounded,
          ),
          _VerificationCriterion(
            keyName: 'otherCommsWorking',
            title: 'Autres moyens de communication',
            subtitle: 'Matériels concernés disponibles et fonctionnels',
            icon: Icons.cell_tower_rounded,
          ),
        ];

      case SauveteurMaterielCategory.roulant:
        return const [
          _VerificationCriterion(
            keyName: 'rollingWorking',
            title: 'Véhicules / quads / moyens roulants',
            subtitle: 'Démarrage, conduite et équipements fonctionnels',
            icon: Icons.directions_car_filled_rounded,
          ),
          _VerificationCriterion(
            keyName: 'energyFull',
            title: 'Carburant / charge électrique',
            subtitle: 'Plein ou recharge effectué selon le véhicule',
            icon: Icons.local_gas_station_rounded,
          ),
          _VerificationCriterion(
            keyName: 'levelsOk',
            title: 'Niveaux',
            subtitle: 'Huile, refroidissement, frein et autres niveaux corrects',
            icon: Icons.oil_barrel_rounded,
          ),
          _VerificationCriterion(
            keyName: 'dashboardLightsOk',
            title: 'Voyants lumineux',
            subtitle: 'Aucune anomalie signalée au tableau de bord',
            icon: Icons.warning_amber_rounded,
          ),
          _VerificationCriterion(
            keyName: 'sirenOk',
            title: 'Deux-tons',
            subtitle: 'Avertisseur sonore prioritaire fonctionnel',
            icon: Icons.campaign_rounded,
          ),
          _VerificationCriterion(
            keyName: 'beaconsOk',
            title: 'Gyrophares',
            subtitle: 'Signalisation lumineuse prioritaire fonctionnelle',
            icon: Icons.emergency_share_rounded,
          ),
          _VerificationCriterion(
            keyName: 'lightingOk',
            title: 'Éclairage / signalisation',
            subtitle: 'Feux, clignotants et éclairages fonctionnels',
            icon: Icons.lightbulb_outline_rounded,
          ),
          _VerificationCriterion(
            keyName: 'safetyEquipmentOk',
            title: 'Équipements de sécurité',
            subtitle: 'Présents, accessibles et correctement arrimés',
            icon: Icons.health_and_safety_outlined,
          ),
        ];

      case SauveteurMaterielCategory.flottant:
        return const [
          _VerificationCriterion(
            keyName: 'floatingWorking',
            title: 'Embarcations / jets / slides / rescue tubes',
            subtitle: 'Matériels concernés disponibles et fonctionnels',
            icon: Icons.directions_boat_filled_rounded,
          ),
          _VerificationCriterion(
            keyName: 'floatingEnergyFull',
            title: 'Carburant / charge électrique',
            subtitle: 'Plein ou recharge effectué pour les engins concernés',
            icon: Icons.local_gas_station_rounded,
          ),
          _VerificationCriterion(
            keyName: 'helmetsOk',
            title: 'Casques',
            subtitle: 'Présents, adaptés et en bon état',
            icon: Icons.sports_motorsports_rounded,
          ),
          _VerificationCriterion(
            keyName: 'lifeJacketsOk',
            title: 'Gilets de sauvetage',
            subtitle: 'Présents, adaptés et en bon état',
            icon: Icons.health_and_safety_rounded,
          ),
          _VerificationCriterion(
            keyName: 'inflationOk',
            title: 'Gonflage',
            subtitle: 'Embarcations et slides suffisamment gonflés',
            icon: Icons.air_rounded,
          ),
          _VerificationCriterion(
            keyName: 'cutoffOk',
            title: 'Coupe-circuit / sécurité moteur',
            subtitle: 'Dispositifs de sécurité présents et fonctionnels',
            icon: Icons.power_settings_new_rounded,
          ),
          _VerificationCriterion(
            keyName: 'equipmentOk',
            title: 'Armement / remorquage',
            subtitle: 'Matériel embarqué, lignes et accessoires complets',
            icon: Icons.anchor_rounded,
          ),
        ];
    }
  }

  @override
  void initState() {
    super.initState();
    for (final criterion in _criteria) {
      _checks[criterion.keyName] = true;
    }
    _loadSpotContext();
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadSpotContext() async {
    try {
      final spots = await SauveteurLivePublicationService.loadAssignedSpots(
        territoireId: widget.territoireId,
        postesAffectes: widget.postesAffectes,
      );

      final preferredId = widget.initialSpotId?.trim();
      final selected = spots.isEmpty
          ? null
          : spots.firstWhere(
              (spot) => spot.id == preferredId,
              orElse: () => spots.first,
            );

      if (!mounted) return;

      setState(() {
        _selectedSpotId = selected?.id;
        _spotLabel = selected?.label;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Impossible de charger le poste de secours sélectionné.';
      });
    }
  }

  String _status(bool value) => value ? 'OK' : 'À CONTRÔLER';

  List<String> _verificationLines() {
    final lines = <String>[
      'Catégorie : $_categoryLabel',
    ];

    for (final criterion in _criteria) {
      lines.add(
        criterion.title +
            ' : ' +
            _status(_checks[criterion.keyName] ?? false),
      );
    }

    if (widget.category == SauveteurMaterielCategory.phonie) {
      lines.add('Charge VHF : ${_vhfBattery.round()} %');
      lines.add('Charge téléphones : ${_phoneBattery.round()} %');
      lines.add(
        'Charge autres communications : ${_otherCommsBattery.round()} %',
      );
    }

    final remarks = _remarksController.text.trim();
    if (remarks.isNotEmpty) {
      lines.add('Observation : $remarks');
    }

    return lines;
  }

  Future<void> _saveVerification() async {
    final spotId = _selectedSpotId?.trim();

    if (!_isSphotOn) {
      setState(() {
        _message =
            'La vérification réelle peut être enregistrée uniquement '
            'lorsque SPHOT est ON.';
      });
      return;
    }

    if (spotId == null || spotId.isEmpty) {
      setState(() {
        _message = 'Aucun poste de secours n’est sélectionné.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _message = null;
    });

    try {
      final response = await http.post(
        Uri.parse(
          'https://us-central1-sphot-ab80b.cloudfunctions.net/'
          'addSauveteurMainCouranteEntry',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sauveteurSessionToken': widget.sauveteurSessionToken,
          'spotId': spotId,
          'type': 'Vérification matériel',
          'description': _verificationLines().join('\n'),
          'actionTaken': '',
          'visibility': 'operational',
        }),
      );

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() {
          _message = 'Vérification enregistrée dans la MAIN COURANTE.';
        });
      } else {
        setState(() {
          _message =
              'La vérification n’a pas pu être enregistrée actuellement.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Impossible de joindre le service SPHOT.';
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _booleanCheck(_VerificationCriterion criterion) {
    final value = _checks[criterion.keyName] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? _green : _red,
          width: 1.2,
        ),
      ),
      child: SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        secondary: Icon(
          criterion.icon,
          color: value ? _green : _red,
          size: 21,
        ),
        title: Text(
          criterion.title,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 11.5,
          ),
        ),
        subtitle: Text(
          criterion.subtitle,
          style: const TextStyle(fontSize: 9.5),
        ),
        value: value,
        onChanged: (nextValue) {
          setState(() {
            _checks[criterion.keyName] = nextValue;
          });
        },
      ),
    );
  }

  Widget _batteryControl({
    required String title,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final good = value >= 50;

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: good ? _green : _orange,
          width: 1.2,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.battery_charging_full_rounded,
                color: good ? _green : _orange,
                size: 21,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                  ),
                ),
              ),
              Text(
                '${value.round()} %',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: 0,
            max: 100,
            divisions: 20,
            label: '${value.round()} %',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _content() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.50),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _blue, width: 1.4),
          ),
          child: Row(
            children: [
              Icon(
                _categoryIcon,
                color: _blue,
                size: 25,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _categoryLabel.toUpperCase(),
                  style: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        ..._criteria.map(_booleanCheck),
        if (widget.category == SauveteurMaterielCategory.phonie) ...[
          _batteryControl(
            title: 'Charge des VHF',
            value: _vhfBattery,
            onChanged: (value) => setState(() => _vhfBattery = value),
          ),
          _batteryControl(
            title: 'Charge des téléphones',
            value: _phoneBattery,
            onChanged: (value) => setState(() => _phoneBattery = value),
          ),
          _batteryControl(
            title: 'Charge des autres moyens de communication',
            value: _otherCommsBattery,
            onChanged: (value) {
              setState(() => _otherCommsBattery = value);
            },
          ),
        ],
        TextField(
          controller: _remarksController,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Autre / anomalie / précision',
            filled: true,
            fillColor: Colors.white.withOpacity(0.42),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SauveteurAdaptiveViewport(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'data/images/map_background.jpg',
              fit: BoxFit.cover,
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: Column(
                  children: [
                    Image.asset(
                      'data/icons/title.png',
                      height: 54,
                      fit: BoxFit.contain,
                    ),
                    Text(
                      _pageTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFD50000),
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    if (_spotLabel != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.48),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _blue, width: 1.2),
                        ),
                        child: Text(
                          _spotLabel!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _blue,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: _loading
                            ? const Center(
                                child: CircularProgressIndicator(),
                              )
                            : ListView(
                                physics: const BouncingScrollPhysics(),
                                children: [
                                  _content(),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 44,
                                    child: ElevatedButton.icon(
                                      onPressed:
                                          _saving ? null : _saveVerification,
                                      icon: const Icon(
                                        Icons.fact_check_outlined,
                                      ),
                                      label: Text(
                                        _saving
                                            ? 'ENREGISTREMENT...'
                                            : 'ENREGISTRER LA VÉRIFICATION',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _blue,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                  if (_message != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _message!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _message!.startsWith(
                                          'Vérification enregistrée',
                                        )
                                            ? _green
                                            : _red,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 21,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationCriterion {
  const _VerificationCriterion({
    required this.keyName,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String keyName;
  final String title;
  final String subtitle;
  final IconData icon;
}
