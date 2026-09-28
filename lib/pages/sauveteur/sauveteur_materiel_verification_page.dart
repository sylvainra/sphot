import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/sauveteur_live_publication_service.dart';
import 'widgets/sauveteur_adaptive_viewport.dart';

class SauveteurMaterielVerificationPage extends StatefulWidget {
  const SauveteurMaterielVerificationPage({
    super.key,
    required this.profileColor,
    required this.territoireId,
    required this.sauveteurSessionToken,
    required this.postesAffectes,
    required this.initialSpotId,
    required this.sphotMode,
  });

  final Color profileColor;
  final String territoireId;
  final String sauveteurSessionToken;
  final List<String> postesAffectes;
  final String? initialSpotId;
  final String sphotMode;

  @override
  State<SauveteurMaterielVerificationPage> createState() =>
      _SauveteurMaterielVerificationPageState();
}

class _SauveteurMaterielVerificationPageState
    extends State<SauveteurMaterielVerificationPage> {
  static const _blue = Color(0xFF1E3A8A);
  static const _green = Color(0xFF15803D);
  static const _orange = Color(0xFFF59E0B);

  final TextEditingController _oxygenMainController =
      TextEditingController(text: '200');
  final TextEditingController _oxygenBackupController =
      TextEditingController(text: '200');
  final TextEditingController _remarksController = TextEditingController();

  String? _selectedSpotId;
  String? _spotLabel;
  bool _loading = true;
  bool _saving = false;
  String? _message;

  bool _aspiratorWorking = true;
  double _aspiratorBattery = 100;
  bool _adultDsaWorking = true;
  bool _adultPadsOk = true;
  bool _pediatricDsaWorking = true;
  bool _pediatricPadsOk = true;
  bool _promptBagComplete = true;
  bool _oxygenMaskAdultOk = true;
  bool _oxygenMaskChildOk = true;
  bool _manualResuscitatorOk = true;

  bool get _isSphotOn => widget.sphotMode.toUpperCase() == 'ON';

  @override
  void initState() {
    super.initState();
    _loadSpotContext();
  }

  @override
  void dispose() {
    _oxygenMainController.dispose();
    _oxygenBackupController.dispose();
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

  int? _parseBar(TextEditingController controller) {
    return int.tryParse(controller.text.trim());
  }

  bool get _oxygenValuesValid {
    final main = _parseBar(_oxygenMainController);
    final backup = _parseBar(_oxygenBackupController);
    return main != null &&
        backup != null &&
        main >= 0 &&
        backup >= 0 &&
        main <= 300 &&
        backup <= 300;
  }

  String _status(bool value) => value ? 'OK' : 'À CONTRÔLER';

  Future<void> _saveVerification() async {
    final spotId = _selectedSpotId?.trim();

    if (!_isSphotOn) {
      setState(() {
        _message =
            'La vérification réelle peut être enregistrée uniquement lorsque SPHOT est ON.';
      });
      return;
    }

    if (spotId == null || spotId.isEmpty) {
      setState(() {
        _message = 'Aucun poste de secours n’est sélectionné.';
      });
      return;
    }

    if (!_oxygenValuesValid) {
      setState(() {
        _message = 'Renseignez les pressions O² entre 0 et 300 bars.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _message = null;
    });

    final mainBar = _parseBar(_oxygenMainController)!;
    final backupBar = _parseBar(_oxygenBackupController)!;

    final lines = <String>[
      'O² bouteille principale : ' + mainBar.toString() + ' bar',
      'O² bouteille secours : ' + backupBar.toString() + ' bar',
      'Aspirateur de mucosités : ' + _status(_aspiratorWorking),
      'Batterie aspirateur : ' + _aspiratorBattery.round().toString() + ' %',
      'DSA adulte : ' + _status(_adultDsaWorking),
      'Électrodes DSA adulte : ' + _status(_adultPadsOk),
      'DSA pédiatrique : ' + _status(_pediatricDsaWorking),
      'Électrodes DSA pédiatrique : ' + _status(_pediatricPadsOk),
      'Sac prompt secours : ' + _status(_promptBagComplete),
      'Masque O² adulte : ' + _status(_oxygenMaskAdultOk),
      'Masque O² pédiatrique : ' + _status(_oxygenMaskChildOk),
      'BAVU / insufflateur : ' + _status(_manualResuscitatorOk),
    ];

    final remarks = _remarksController.text.trim();

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
          'description': lines.join('\n'),
          'actionTaken': remarks.isEmpty
              ? 'Contrôle matériel de début de service.'
              : remarks,
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
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _booleanCheck({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    IconData icon = Icons.check_circle_outline_rounded,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? _green : const Color(0xFFDC2626),
          width: 1.2,
        ),
      ),
      child: SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        secondary: Icon(
          icon,
          color: value ? _green : const Color(0xFFDC2626),
          size: 21,
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 11.5,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 9.5),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _oxygenField({
    required String label,
    required TextEditingController controller,
  }) {
    return Expanded(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'bar',
          isDense: true,
          filled: true,
          fillColor: Colors.white.withOpacity(0.42),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.50),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _blue, width: 1.4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'OXYGÈNE',
                style: TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _oxygenField(
                    label: 'Bouteille principale',
                    controller: _oxygenMainController,
                  ),
                  const SizedBox(width: 8),
                  _oxygenField(
                    label: 'Bouteille secours',
                    controller: _oxygenBackupController,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _booleanCheck(
          title: 'Aspirateur de mucosités',
          subtitle: 'Mise en marche et aspiration fonctionnelles',
          value: _aspiratorWorking,
          icon: Icons.air_rounded,
          onChanged: (value) => setState(() => _aspiratorWorking = value),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.42),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _orange, width: 1.2),
          ),
          child: Row(
            children: [
              const Icon(Icons.battery_charging_full_rounded, color: _orange),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Batterie aspirateur',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                _aspiratorBattery.round().toString() + ' %',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
        Slider(
          value: _aspiratorBattery,
          min: 0,
          max: 100,
          divisions: 20,
          label: _aspiratorBattery.round().toString() + ' %',
          onChanged: (value) {
            setState(() => _aspiratorBattery = value);
          },
        ),
        _booleanCheck(
          title: 'DSA adulte',
          subtitle: 'Autotest / mise en fonction conformes',
          value: _adultDsaWorking,
          icon: Icons.monitor_heart_outlined,
          onChanged: (value) => setState(() => _adultDsaWorking = value),
        ),
        _booleanCheck(
          title: 'Électrodes DSA adulte',
          subtitle: 'Présentes, emballage intact, date valide',
          value: _adultPadsOk,
          icon: Icons.favorite_border_rounded,
          onChanged: (value) => setState(() => _adultPadsOk = value),
        ),
        _booleanCheck(
          title: 'DSA pédiatrique',
          subtitle: 'Autotest / mise en fonction conformes',
          value: _pediatricDsaWorking,
          icon: Icons.monitor_heart_outlined,
          onChanged: (value) =>
              setState(() => _pediatricDsaWorking = value),
        ),
        _booleanCheck(
          title: 'Électrodes DSA pédiatrique',
          subtitle: 'Présentes, emballage intact, date valide',
          value: _pediatricPadsOk,
          icon: Icons.child_care_rounded,
          onChanged: (value) => setState(() => _pediatricPadsOk = value),
        ),
        _booleanCheck(
          title: 'Sac prompt secours',
          subtitle: 'Contenu complet et consommables disponibles',
          value: _promptBagComplete,
          icon: Icons.medical_services_outlined,
          onChanged: (value) => setState(() => _promptBagComplete = value),
        ),
        _booleanCheck(
          title: 'Masque O² adulte',
          subtitle: 'Présent et immédiatement utilisable',
          value: _oxygenMaskAdultOk,
          icon: Icons.masks_outlined,
          onChanged: (value) => setState(() => _oxygenMaskAdultOk = value),
        ),
        _booleanCheck(
          title: 'Masque O² pédiatrique',
          subtitle: 'Présent et immédiatement utilisable',
          value: _oxygenMaskChildOk,
          icon: Icons.masks_outlined,
          onChanged: (value) => setState(() => _oxygenMaskChildOk = value),
        ),
        _booleanCheck(
          title: 'BAVU / insufflateur',
          subtitle: 'Ballon, valve et masques fonctionnels',
          value: _manualResuscitatorOk,
          icon: Icons.emergency_rounded,
          onChanged: (value) =>
              setState(() => _manualResuscitatorOk = value),
        ),
        TextField(
          controller: _remarksController,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Observation / matériel à compléter',
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
                    const Text(
                      'VÉRIFICATION MATÉRIEL',
                      textAlign: TextAlign.center,
                      style: TextStyle(
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
                                            : const Color(0xFFB91C1C),
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
