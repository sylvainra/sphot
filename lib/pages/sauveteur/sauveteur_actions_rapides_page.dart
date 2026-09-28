import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../map/flag_marker.dart';
import '../../models/flag_state.dart';
import '../../widgets/adaptive_asset_image.dart';
import '../../widgets/danger_pictogram.dart';
import 'widgets/sauveteur_styled_dropdown.dart';
import 'widgets/sauveteur_adaptive_viewport.dart';

class SauveteurActionsRapidesPage extends StatefulWidget {
  final Color profileColor;
  final String sphotMode;
  final String territoireId;
  final String sauveteurSessionToken;
  final List<String> postesAffectes;
  final String? initialSpotId;

  const SauveteurActionsRapidesPage({
    super.key,
    required this.profileColor,
    required this.sphotMode,
    required this.territoireId,
    required this.sauveteurSessionToken,
    required this.postesAffectes,
    required this.initialSpotId,
  });

  bool get isSphotOn => sphotMode.toUpperCase() == 'ON';

  @override
  State<SauveteurActionsRapidesPage> createState() =>
      _SauveteurActionsRapidesPageState();
}

class _SauveteurActionsRapidesPageState
    extends State<SauveteurActionsRapidesPage> {
  String flagColor = 'Vert';
  String flagPosition = 'Hissé';
  String status = 'Baignade surveillée';
  bool purpleFlagActive = false;
  bool windsockActive = false;

  String nomSecours = 'AUCUN POSTE';
  String nomSphot = '';
  String typeSphot = 'Poste de secours';
  String? selectedSpotId;

  bool isDangerMenuOpen = false;
  bool _loadingSpots = true;
  bool _liveWriteBlocked = false;
  String? _liveStatusMessage;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _liveSubscription;

  final Set<String> selectedDangers = {};
  int baineLevel = 0;
  int caniculeLevel = 0;

  final List<String> dangerChoices = [
    'COURANTS',
    'BAÏNES',
    'SHORE BREAK',
    'VAGUES FORTES',
    'HOULE',
    'CONDITIONS DÉFAVORABLES DE VENT POUR CERTAINS ÉQUIPEMENTS NAUTIQUES',
    'CHÂLEURS',
    'CANICULE',
    'ALTÉRATION DE LA QUALITÉ DES EAUX DE BAIGNADE',
    'PRÉSENCE D’ESPÈCES DANGEREUSES (MÉDUSES...)',
    'EXISTANCE D’UNE ZONE MARINE OU SOUS-MARINE PROTÉGÉE',
    'EAU FROIDE',
    'ROCHERS / RÉCIFS',
    'DÉVERSEMENT',
    'CRUE',
    'FAIBLE PROFONDEUR',
    'ASPIRATION',
    'TRAFFIC MARITIME',
    'TOURBILLONS',
    'REMOUS',
    'VASE / SABLE MOUVANT',
    'LÂCHER DE BARRAGE',
    'CHEVAUX',
    'REQUINS SIGNALÉS',
    'CONDITIONS MÉTÉOROLOGIQUES PROPICES À LA PRÉSENCE DE REQUINS',
    'AUTRE',
   
  ];

  final List<Map<String, String>> postesSecoursCommune = [];

  @override
  void initState() {
    super.initState();
    _loadAssignedSpots();
  }

  @override
  void dispose() {
    _liveSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAssignedSpots() async {
    final ids = widget.postesAffectes
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    final loaded = <Map<String, String>>[];

    for (final spotId in ids) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('territoires')
            .doc(widget.territoireId)
            .collection('spots')
            .doc(spotId)
            .get();

        final data = snapshot.data() ?? <String, dynamic>{};
        loaded.add({
          'spotId': spotId,
          'nomSecours': (data['nomSecours'] ?? spotId).toString(),
          'nomSphot': (data['nomSphot'] ?? '').toString(),
          'typeSphot': (data['typeSphot'] ?? 'Poste de secours').toString(),
        });
      } catch (_) {
        loaded.add({
          'spotId': spotId,
          'nomSecours': spotId,
          'nomSphot': '',
          'typeSphot': 'Poste de secours',
        });
      }
    }

    loaded.sort((a, b) {
      return (a['nomSecours'] ?? '').compareTo(b['nomSecours'] ?? '');
    });

    if (!mounted) return;

    setState(() {
      postesSecoursCommune
        ..clear()
        ..addAll(loaded);
      _loadingSpots = false;
    });

    if (postesSecoursCommune.isNotEmpty) {
      final preferredId = widget.initialSpotId?.trim();
      final initialPoste = postesSecoursCommune.firstWhere(
        (poste) => poste['spotId'] == preferredId,
        orElse: () => postesSecoursCommune.first,
      );
      await _selectSpot(initialPoste);
    }
  }

  Future<void> _selectSpot(Map<String, String> poste) async {
    await _liveSubscription?.cancel();
    _liveSubscription = null;

    if (!mounted) return;

    setState(() {
      selectedSpotId = poste['spotId'];
      nomSecours = poste['nomSecours'] ?? 'POSTE';
      nomSphot = poste['nomSphot'] ?? '';
      typeSphot = poste['typeSphot'] ?? 'Poste de secours';
      _liveWriteBlocked = false;
      _liveStatusMessage = null;

      if (!widget.isSphotOn) {
        flagColor = 'Vert';
        flagPosition = 'Hissé';
        status = 'Baignade surveillée';
        purpleFlagActive = false;
        windsockActive = false;
        selectedDangers.clear();
        baineLevel = 0;
        caniculeLevel = 0;
      }
    });

    if (widget.isSphotOn && selectedSpotId != null) {
      _listenToLiveSpot(selectedSpotId!);
    }
  }

  void _listenToLiveSpot(String spotId) {
    _liveSubscription = FirebaseFirestore.instance
        .collection('spots')
        .doc(spotId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted || !snapshot.exists) return;

      final data = snapshot.data() ?? <String, dynamic>{};
      final liveFlag = data['liveFlag'] is Map
          ? Map<String, dynamic>.from(data['liveFlag'] as Map)
          : <String, dynamic>{};

      final rawColor = (liveFlag['flagColor'] ?? '').toString().toLowerCase();
      final rawPosition =
          (liveFlag['flagPosition'] ?? '').toString().toLowerCase();
      final nextPurpleFlagActive = liveFlag['purpleFlagActive'] == true;
      final nextWindsockActive = liveFlag['windsockActive'] == true;

      String? nextColor;
      if (rawColor == 'green' || rawColor == 'vert') {
        nextColor = 'Vert';
      } else if (rawColor == 'yellow' || rawColor == 'jaune') {
        nextColor = 'Jaune';
      } else if (rawColor == 'red' || rawColor == 'rouge') {
        nextColor = 'Rouge';
      }

      String? nextPosition;
      if (rawPosition == 'affale' || rawPosition == 'affalé') {
        nextPosition = 'Affalé';
      } else if (rawPosition == 'hisse' || rawPosition == 'hissé') {
        nextPosition = 'Hissé';
      }

      final rawDangers = data['dangers'];

      setState(() {
        if (nextColor != null) flagColor = nextColor;
        if (nextPosition != null) flagPosition = nextPosition;
        purpleFlagActive = nextPurpleFlagActive;
        windsockActive = nextWindsockActive;

        status = flagPosition == 'Affalé'
            ? 'Baignade non surveillée temporairement'
            : _statusForFlagColor(flagColor);

        if (rawDangers is Iterable) {
          final values = rawDangers.map((value) => value.toString()).toList();

          var nextBaineLevel = 0;
          var nextCaniculeLevel = 0;

          for (final value in values) {
            final upper = value.toUpperCase();

            if (upper.contains('BAÏNE') || upper.contains('BAINE')) {
              final match = RegExp(
                r'NIVEAU\s*([1-5])',
                caseSensitive: false,
              ).firstMatch(value);
              nextBaineLevel = int.tryParse(match?.group(1) ?? '') ?? 1;
            }

            if (upper.contains('CANICULE')) {
              final match = RegExp(
                r'NIVEAU\s*([1-4])',
                caseSensitive: false,
              ).firstMatch(value);
              nextCaniculeLevel = int.tryParse(match?.group(1) ?? '') ?? 1;
            }
          }

          selectedDangers
            ..clear()
            ..addAll(values);
          baineLevel = nextBaineLevel;
          caniculeLevel = nextCaniculeLevel;
        }
      });
    });
  }

  String _statusForFlagColor(String color) {
    switch (color) {
      case 'Jaune':
        return 'Baignade surveillée mais dangereuse';
      case 'Rouge':
        return 'Baignade interdite';
      default:
        return 'Baignade surveillée et autorisée';
    }
  }

  String _flagColorValue(String color) {
    switch (color) {
      case 'Jaune':
        return 'yellow';
      case 'Rouge':
        return 'red';
      default:
        return 'green';
    }
  }

  String _flagPositionValue(String position) {
    return position == 'Affalé' ? 'affale' : 'hisse';
  }

  Future<bool> _persistLiveChanges(Map<String, dynamic> changes) async {
    if (!widget.isSphotOn || selectedSpotId == null) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(
          'https://us-central1-sphot-ab80b.cloudfunctions.net/'
          'updateSauveteurLiveState',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sauveteurSessionToken': widget.sauveteurSessionToken,
          'spotId': selectedSpotId,
          'changes': changes,
        }),
      );

      if (!mounted) return false;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() {
          _liveWriteBlocked = false;
          _liveStatusMessage = null;
        });
        return true;
      }

      String errorCode = '';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          errorCode = (decoded['error'] ?? '').toString();
        }
      } catch (_) {}

      setState(() {
        _liveWriteBlocked = errorCode == 'sphot_off' ||
            errorCode == 'spot_not_assigned';
        _liveStatusMessage = _liveWriteBlocked
            ? 'Cette action n’est pas enregistrée sur le poste réel.'
            : 'La modification opérationnelle n’a pas pu être enregistrée.';
      });

      return false;
    } catch (_) {
      if (!mounted) return false;

      setState(() {
        _liveStatusMessage =
            'Connexion au SPHOT réel impossible. La modification reste locale.';
      });
      return false;
    }
  }

  Future<void> _persistFlagState() async {
    final currentStatus = flagPosition == 'Affalé'
        ? 'Baignade non surveillée temporairement'
        : _statusForFlagColor(flagColor);

    await _persistLiveChanges({
      'liveFlag': {
        'flagColor': _flagColorValue(flagColor),
        'flagPosition': _flagPositionValue(flagPosition),
        'purpleFlagActive': purpleFlagActive,
        'windsockActive': windsockActive,
      },
      'statutBaignade': currentStatus,
    });
  }

  Future<void> _togglePurpleFlag() async {
    setState(() {
      purpleFlagActive = !purpleFlagActive;
    });

    await _persistFlagState();
  }

  Future<void> _toggleWindsock() async {
    setState(() {
      windsockActive = !windsockActive;
    });

    await _persistFlagState();
  }

  Future<void> _changeFlagColor(String color) async {
    setState(() {
      flagColor = color;
      if (flagPosition != 'Affalé') {
        status = _statusForFlagColor(color);
      }
    });

    await _persistFlagState();
  }

  Future<void> updateFlagPosition(String position) async {
    setState(() {
      flagPosition = position;
      status = position == 'Affalé'
          ? 'Baignade non surveillée temporairement'
          : _statusForFlagColor(flagColor);
    });

    await _persistFlagState();
  }

  void _previewFlagPosition(String position) {
    if (flagPosition == position) return;

    setState(() {
      flagPosition = position;
      status = position == 'Affalé'
          ? 'Baignade non surveillée temporairement'
          : _statusForFlagColor(flagColor);
    });
  }

  SpotFlagState _previewSpotState() {
    return SpotFlagState(
      id: selectedSpotId ?? 'preview',
      idSphot: nomSecours,
      territoireId: widget.territoireId,
      name: nomSecours,
      nomSphot: nomSphot,
      ville: '',
      departement: '',
      logoVille: '',
      siteInternetVille: '',
      villeLat: 0,
      villeLng: 0,
      departementLat: 0,
      departementLng: 0,
      lat: 0,
      lng: 0,
      typeSphot: typeSphot,
      statutBaignade: status,
      periode: '',
      heureDebut: '',
      heureFin: '',
      phone: '',
      activite: '',
      equipement: '',
      labelSphot: '',
      adresseWebcam: '',
      arretesMunicipaux: '',
      liveFlag: {
        'flagColor': _flagColorValue(flagColor),
        'flagPosition': _flagPositionValue(flagPosition),
        'purpleFlagActive': purpleFlagActive,
        'windsockActive': windsockActive,
      },
    );
  }

  String _baineLevelTitle(int level) {
    switch (level) {
      case 1:
      case 2:
        return 'Risque faible à modéré';
      case 3:
        return 'Risque marqué';
      case 4:
        return 'Risque très élevé';
      case 5:
        return 'Risque maximal (Alerte maximale)';
      default:
        return '';
    }
  }

  void _setBaineLevel(int level) {
    setState(() {
      selectedDangers.removeWhere((danger) {
        final upper = danger.toUpperCase();
        return upper.contains('BAÏNE') || upper.contains('BAINE');
      });

      baineLevel = level;

      if (level > 0) {
        selectedDangers.add(
          'BAÏNES - NIVEAU $level : ${_baineLevelTitle(level)}',
        );
      }
    });
  }

  String _caniculeLevelTitle(int level) {
    switch (level) {
      case 1:
        return 'Veille saisonnière';
      case 2:
        return 'Avertissement chaleur';
      case 3:
        return 'Alerte canicule';
      case 4:
        return 'Mobilisation maximale';
      default:
        return '';
    }
  }

  void _setCaniculeLevel(int level) {
    setState(() {
      selectedDangers.removeWhere(
        (danger) => danger.toUpperCase().contains('CANICULE'),
      );

      caniculeLevel = level;

      if (level > 0) {
        selectedDangers.add(
          'CANICULE - NIVEAU $level : ${_caniculeLevelTitle(level)}',
        );
      }
    });
  }

  List<String> _dangerValuesForPublication() {
    final values = <String>[];

    for (final choice in dangerChoices) {
      final upper = choice.toUpperCase();
      final isBaine =
          upper.contains('BAÏNE') || upper.contains('BAINE');
      final isCanicule = upper.contains('CANICULE');

      if (isBaine) {
        if (baineLevel > 0) {
          values.add(
            'BAÏNES - NIVEAU $baineLevel : '
            '${_baineLevelTitle(baineLevel)}',
          );
        }
        continue;
      }

      if (isCanicule) {
        if (caniculeLevel > 0) {
          values.add(
            'CANICULE - NIVEAU $caniculeLevel : '
            '${_caniculeLevelTitle(caniculeLevel)}',
          );
        }
        continue;
      }

      if (selectedDangers.contains(choice)) {
        values.add(choice);
      }
    }

    final known = values.toSet();
    final extras = selectedDangers.where((danger) {
      final upper = danger.toUpperCase();
      final isBaine =
          upper.contains('BAÏNE') || upper.contains('BAINE');
      final isCanicule = upper.contains('CANICULE');
      return !isBaine && !isCanicule && !known.contains(danger);
    });

    values.addAll(extras);
    return values;
  }

  Future<bool> _publishNotification(String message) {
    return _persistLiveChanges({
      'notificationPublique': {
        'message': message.trim(),
        'active': true,
      },
    });
  }

  Widget _buildFlagMastControl() {
    const height = 250.0;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.black.withOpacity(0.25),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final next = details.localPosition.dy <
                      constraints.maxHeight / 2
                  ? 'Hissé'
                  : 'Affalé';
              unawaited(updateFlagPosition(next));
            },
            onVerticalDragUpdate: (details) {
              final next = details.localPosition.dy <
                      constraints.maxHeight / 2
                  ? 'Hissé'
                  : 'Affalé';
              _previewFlagPosition(next);
            },
            onVerticalDragEnd: (_) {
              unawaited(_persistFlagState());
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Positioned(
                  top: 7,
                  left: 0,
                  right: 0,
                  child: Text(
                    'HISSÉ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF15803D),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 18),
                  child: Transform.scale(
                    scale: 1.55,
                    child: FlagMarker(
                      spot: _previewSpotState(),
                    ),
                  ),
                ),
                const Positioned(
                  bottom: 7,
                  left: 0,
                  right: 0,
                  child: Text(
                    'AFFALÉ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Positioned(
                  right: 6,
                  top: 109,
                  child: Icon(
                    Icons.unfold_more_rounded,
                    size: 22,
                    color: Colors.black.withOpacity(0.45),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _openDangersPage() async {
    final result = await Navigator.of(context).push<_DangerSelectionResult>(
      MaterialPageRoute(
        builder: (_) => SauveteurDangersPage(
          profileColor: widget.profileColor,
          dangerChoices: List<String>.from(dangerChoices),
          initialSelectedDangers: Set<String>.from(selectedDangers),
          initialBaineLevel: baineLevel,
          initialCaniculeLevel: caniculeLevel,
        ),
      ),
    );

    if (!mounted || result == null) return;

    setState(() {
      selectedDangers
        ..clear()
        ..addAll(result.selectedDangers);
      baineLevel = result.baineLevel;
      caniculeLevel = result.caniculeLevel;
    });

    await _persistLiveChanges({
      'dangers': _dangerValuesForPublication(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isTemporaryClosed = flagPosition == 'Affalé';

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
  child: Column(
    mainAxisAlignment: MainAxisAlignment.start,
    children: [
                const SizedBox(height: 2),

                Image.asset(
                  'data/icons/title.png',
                  height: 56,
                  fit: BoxFit.contain,
                ),

                Text(
                  'ACTIONS RAPIDES',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: widget.profileColor,
                    letterSpacing: 0.6,
                  ),
                ),

                const SizedBox(height: 2),

                Expanded(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Column(
      children: [
                          if (_loadingSpots)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 6),
                              child: LinearProgressIndicator(),
                            ),

                          if (!_loadingSpots &&
                              postesSecoursCommune.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 6),
                              child: Text(
                                'Aucun poste de secours ne vous est affecté.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFDC2626),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),

                          if (_liveStatusMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                _liveStatusMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFB91C1C),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),

                          if (!isTemporaryClosed)
                            Container(
                              width: double.infinity,
                              height: 64,
                              margin: const EdgeInsets.only(
                                top: 3,
                                bottom: 6,
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 14,
                              ),
                              decoration: BoxDecoration(
                                color: flagColor == 'Vert'
                                    ? const Color(0xFF22C55E)
                                    : flagColor == 'Jaune'
                                        ? const Color(0xFFFDE047)
                                        : const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.black,
                                  width: 3,
                                ),
                              ),
                              child: Text(
                                flagColor == 'Vert'
                                    ? 'BAIGNADE SURVEILLÉE ET AUTORISÉE'
                                    : flagColor == 'Jaune'
                                        ? 'BAIGNADE SURVEILLÉE MAIS DANGEREUSE'
                                        : 'BAIGNADE INTERDITE',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: flagColor == 'Jaune'
                                      ? Colors.black
                                      : Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),

                          if (isTemporaryClosed) _dangerBanner(),

                          _sectionCard(
                            title: 'Actions rapides',
                            icon: Icons.flash_on,
                            showHeader: false,
                            children: [
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 250,
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(
                                      width: 132,
                                      child: _buildFlagMastControl(),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: _FlagColorButton(
                                              label: 'Vert',
                                              color: const Color(0xFF22C55E),
                                              selected: flagColor == 'Vert',
                                              onTap: () {
                                                _changeFlagColor('Vert');
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 9),
                                          Expanded(
                                            child: _FlagColorButton(
                                              label: 'Jaune',
                                              color: const Color(0xFFFDE047),
                                              selected: flagColor == 'Jaune',
                                              onTap: () {
                                                _changeFlagColor('Jaune');
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 9),
                                          Expanded(
                                            child: _FlagColorButton(
                                              label: 'Rouge',
                                              color: const Color(0xFFEF4444),
                                              selected: flagColor == 'Rouge',
                                              onTap: () {
                                                _changeFlagColor('Rouge');
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              _ActionButton(
                                icon: Icons.warning_amber_rounded,
                                label: selectedDangers.isEmpty
                                    ? 'Déclarer un danger'
                                    : '${selectedDangers.length} '
                                        'danger(s) sélectionné(s)',
                                color: const Color(0xFFFDE047),
                                onTap: _openDangersPage,
                              ),
                              const SizedBox(height: 12),
                              _ActionButton(
                                icon: Icons.campaign_rounded,
                                label: 'Ajouter une notification',
                                color: Colors.red,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          SauveteurNotificationPage(
                                        profileColor: widget.profileColor,
                                        onPublish: _publishNotification,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),

                          _sectionCard(
                            title: 'Signaux complémentaires',
                            icon: Icons.flag_rounded,
                            showHeader: false,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _SupplementarySignalButton(
                                      label: 'Drapeau violet',
                                      icon: Icons.flag_rounded,
                                      activeColor: const Color(0xFFD946EF),
                                      selected: purpleFlagActive,
                                      onTap: _togglePurpleFlag,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _SupplementarySignalButton(
                                      label: 'Manche à air',
                                      icon: Icons.air_rounded,
                                      activeColor: const Color(0xFFFF9800),
                                      selected: windsockActive,
                                      onTap: _toggleWindsock,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                  ),
                ),
                const SizedBox(height: 6),
                _bottomNavBar(),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      )),
    );
  }

  Widget _dangerSidePanel() {
  return Material(
    elevation: 24,
    borderRadius: BorderRadius.circular(22),
    child: Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.black,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    const Icon(
      Icons.unfold_more_rounded,
      color: Colors.black45,
      size: 22,
    ),

    const SizedBox(width: 4),

    const Text(
      'DANGERS',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.red,
        fontSize: 20,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.8,
      ),
    ),

    const SizedBox(width: 4),

    const Icon(
      Icons.unfold_more_rounded,
      color: Colors.black45,
      size: 22,
    ),
  ],
),

          const SizedBox(height: 8),

          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: dangerChoices.length,
              itemBuilder: (context, index) {
                final danger = dangerChoices[index];
                final upper = danger.toUpperCase();
                final isBaine =
                    upper.contains('BAÏNE') || upper.contains('BAINE');
                final isCanicule = upper == 'CANICULE';

                if (isBaine) {
                  return _BaineDangerSelector(
                    level: baineLevel,
                    onChanged: _setBaineLevel,
                  );
                }

                if (isCanicule) {
                  return _CaniculeDangerSelector(
                    level: caniculeLevel,
                    onChanged: _setCaniculeLevel,
                  );
                }

                final bool selected = selectedDangers.contains(danger);

                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: selected,
                  activeColor: const Color(0xFFFDE047),
                  checkColor: Colors.black,
                  secondary: DangerPictogram(
                    danger: danger,
                    size: 28,
                  ),
                  title: Text(
                    danger,
                    softWrap: true,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        selectedDangers.add(danger);
                      } else {
                        selectedDangers.remove(danger);
                      }
                    });
                  },
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton(
              onPressed: () async {
                setState(() => isDangerMenuOpen = false);
                await _persistLiveChanges({
                  'dangers': _dangerValuesForPublication(),
                });
              },
              style: ElevatedButton.styleFrom(
  backgroundColor: Colors.red,
  foregroundColor: Colors.white,
  side: const BorderSide(
    color: Colors.black,
    width: 2,
  ),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  ),
),
              child: const Text(
                'VALIDER',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _bottomNavBar() {
  return SafeArea(
    top: false,
    child: Center(
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).pop();
        },
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.black,
              width: 2,
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.black,
              size: 22,
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _dangerBanner() {
    return Container(
      width: double.infinity,
      height: 58,
      margin: const EdgeInsets.only(top: 3, bottom: 6),
      padding: const EdgeInsets.symmetric(
        vertical: 6,
        horizontal: 14,
      ),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.black,
          width: 3,
        ),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.warning_rounded,
            color: Colors.white,
            size: 20,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'BAIGNADE NON SURVEILLÉE TEMPORAIREMENT',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    height: 1,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'BAIGNADE À VOS RISQUES ET PÉRILS',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    IconData? icon,
    Widget? leading,
    bool showHeader = true,
    required List<Widget> children,
  }) {
    assert(icon != null || leading != null);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
  color: Colors.transparent,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(
    color: Colors.black,
    width: 2,
  ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
          if (showHeader)
            Row(
              children: [
                leading ??
                    Icon(
                      icon,
                      color: widget.profileColor,
                    ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ...children,
                ],
      ),
    );
  }
}

class _SphotMenuItem extends StatelessWidget {
  final String title;
  final Color color;
  final bool selected;
  final bool showArrow;
  final bool isOpen;

  const _SphotMenuItem({
    required this.title,
    required this.color,
    required this.selected,
    required this.showArrow,
    required this.isOpen,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      height: 46,
padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected ? Colors.black : Colors.black12,
          width: selected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.place_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          if (showArrow)
            AnimatedRotation(
              turns: isOpen ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: color,
                size: 28,
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomLogoButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _BottomLogoButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 34,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(icon, color: color, size: 30),
      ),
    );
  }
}

class _FlagColorButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _FlagColorButton({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.black : Colors.transparent,
            width: selected ? 3 : 0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Center(
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: label == 'Jaune' ? Colors.black : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _SupplementarySignalButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color activeColor;
  final bool selected;
  final VoidCallback onTap;

  const _SupplementarySignalButton({
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : Colors.black87;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? activeColor
              : Colors.white.withOpacity(0.62),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.black,
            width: selected ? 3 : 2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.20),
                    blurRadius: 7,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : icon,
              size: 21,
              color: foreground,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlagPositionSwitch extends StatelessWidget {
  final bool isAffale;
  final Color color;
  final ValueChanged<bool> onChanged;

  const _FlagPositionSwitch({
    required this.isAffale,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
  color: Colors.transparent,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(
    color: Colors.black,
    width: 2,
  ),
),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: isAffale ? Alignment.centerRight : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: isAffale ? Colors.red : color,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(false),
                    child: Center(
                      child: Text(
                        'HISSÉ',
                        style: TextStyle(
                          color: isAffale ? Colors.black54 : Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(true),
                    child: Center(
                      child: Text(
                        'AFFALÉ',
                        style: TextStyle(
                          color: isAffale ? Colors.white : Colors.black54,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BaineDangerSelector extends StatelessWidget {
  final int level;
  final ValueChanged<int> onChanged;

  const _BaineDangerSelector({
    required this.level,
    required this.onChanged,
  });

  String _titleForLevel(int value) {
    switch (value) {
      case 1:
      case 2:
        return 'Risque faible à modéré';
      case 3:
        return 'Risque marqué';
      case 4:
        return 'Risque très élevé';
      case 5:
        return 'Risque maximal (Alerte maximale)';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = level > 0;
    final displayLevel = enabled ? level : 1;
    final displayColor =
        enabled ? baineLevelColor(displayLevel) : Colors.black38;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withOpacity(0.08),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 34,
                child: Center(
                  child: BaineWaveGlyph(
                    level: displayLevel,
                    color: displayColor,
                    width: 30,
                    height: 24,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'BAÏNES',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Checkbox(
                value: enabled,
                activeColor: const Color(0xFFFDE047),
                checkColor: Colors.black,
                onChanged: (value) {
                  onChanged(value == true ? displayLevel : 0);
                },
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 3),
            Row(
              children: List.generate(5, (index) {
                final currentLevel = index + 1;
                final selected = level == currentLevel;
                final color = baineLevelColor(currentLevel);

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: index == 4 ? 0 : 5,
                    ),
                    child: GestureDetector(
                      onTap: () => onChanged(currentLevel),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: 48,
                        decoration: BoxDecoration(
                          color: selected
                              ? color.withOpacity(0.14)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: selected ? color : Colors.black26,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            BaineWaveGlyph(
                              level: currentLevel,
                              color: color,
                              width: 30,
                              height: 25,
                            ),
                            Text(
                              '$currentLevel',
                              style: TextStyle(
                                color: color,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                level <= 2
                    ? 'Niveaux 1 & 2 : ${_titleForLevel(level)}'
                    : 'Niveau $level : ${_titleForLevel(level)}',
                style: TextStyle(
                  color: baineLevelColor(level),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CaniculeDangerSelector extends StatelessWidget {
  final int level;
  final ValueChanged<int> onChanged;

  const _CaniculeDangerSelector({
    required this.level,
    required this.onChanged,
  });

  String _titleForLevel(int value) {
    switch (value) {
      case 1:
        return 'Veille saisonnière';
      case 2:
        return 'Avertissement chaleur';
      case 3:
        return 'Alerte canicule';
      case 4:
        return 'Mobilisation maximale';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = level > 0;
    final displayLevel = enabled ? level : 1;
    final displayColor =
        enabled ? caniculeLevelColor(displayLevel) : Colors.black38;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withOpacity(0.08),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 34,
                child: Center(
                  child: CaniculeLevelGlyph(
                    level: displayLevel,
                    width: 32,
                    height: 24,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'CANICULE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Checkbox(
                value: enabled,
                activeColor: const Color(0xFFFDE047),
                checkColor: Colors.black,
                onChanged: (value) {
                  onChanged(value == true ? displayLevel : 0);
                },
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 3),
            Row(
              children: List.generate(4, (index) {
                final currentLevel = index + 1;
                final selected = level == currentLevel;
                final color = caniculeLevelColor(currentLevel);

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: index == 3 ? 0 : 5,
                    ),
                    child: GestureDetector(
                      onTap: () => onChanged(currentLevel),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: 50,
                        decoration: BoxDecoration(
                          color: selected
                              ? color.withOpacity(0.14)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: selected ? color : Colors.black26,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CaniculeLevelGlyph(
                              level: currentLevel,
                              width: 48,
                              height: 25,
                            ),
                            Text(
                              'N$currentLevel',
                              style: TextStyle(
                                color: color,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Niveau $level : ${_titleForLevel(level)}',
                style: TextStyle(
                  color: displayColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


class _DangerSelectionResult {
  final Set<String> selectedDangers;
  final int baineLevel;
  final int caniculeLevel;

  const _DangerSelectionResult({
    required this.selectedDangers,
    required this.baineLevel,
    required this.caniculeLevel,
  });
}

class SauveteurDangersPage extends StatefulWidget {
  final Color profileColor;
  final List<String> dangerChoices;
  final Set<String> initialSelectedDangers;
  final int initialBaineLevel;
  final int initialCaniculeLevel;

  const SauveteurDangersPage({
    super.key,
    required this.profileColor,
    required this.dangerChoices,
    required this.initialSelectedDangers,
    required this.initialBaineLevel,
    required this.initialCaniculeLevel,
  });

  @override
  State<SauveteurDangersPage> createState() =>
      _SauveteurDangersPageState();
}

class _SauveteurDangersPageState extends State<SauveteurDangersPage> {
  late final Set<String> _selectedDangers;
  late int _baineLevel;
  late int _caniculeLevel;

  @override
  void initState() {
    super.initState();
    _selectedDangers = Set<String>.from(widget.initialSelectedDangers);
    _baineLevel = widget.initialBaineLevel;
    _caniculeLevel = widget.initialCaniculeLevel;
  }

  String _baineLevelTitle(int level) {
    switch (level) {
      case 1:
      case 2:
        return 'Risque faible à modéré';
      case 3:
        return 'Risque marqué';
      case 4:
        return 'Risque très élevé';
      case 5:
        return 'Risque maximal (Alerte maximale)';
      default:
        return '';
    }
  }

  String _caniculeLevelTitle(int level) {
    switch (level) {
      case 1:
        return 'Veille saisonnière';
      case 2:
        return 'Avertissement chaleur';
      case 3:
        return 'Alerte canicule';
      case 4:
        return 'Mobilisation maximale';
      default:
        return '';
    }
  }

  void _setBaineLevel(int level) {
    setState(() {
      _selectedDangers.removeWhere((danger) {
        final upper = danger.toUpperCase();
        return upper.contains('BAÏNE') || upper.contains('BAINE');
      });

      _baineLevel = level;

      if (level > 0) {
        _selectedDangers.add(
          'BAÏNES - NIVEAU $level : ${_baineLevelTitle(level)}',
        );
      }
    });
  }

  void _setCaniculeLevel(int level) {
    setState(() {
      _selectedDangers.removeWhere(
        (danger) => danger.toUpperCase().contains('CANICULE'),
      );

      _caniculeLevel = level;

      if (level > 0) {
        _selectedDangers.add(
          'CANICULE - NIVEAU $level : ${_caniculeLevelTitle(level)}',
        );
      }
    });
  }

  void _validate() {
    Navigator.of(context).pop(
      _DangerSelectionResult(
        selectedDangers: Set<String>.from(_selectedDangers),
        baineLevel: _baineLevel,
        caniculeLevel: _caniculeLevel,
      ),
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Column(
                  children: [
                    Image.asset(
                      'data/icons/title.png',
                      height: 56,
                      fit: BoxFit.contain,
                    ),
                    Text(
                      'DANGERS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: widget.profileColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.black,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                itemCount: widget.dangerChoices.length,
                                itemBuilder: (context, index) {
                                  final danger = widget.dangerChoices[index];
                                  final upper = danger.toUpperCase();
                                  final isBaine =
                                      upper.contains('BAÏNE') ||
                                      upper.contains('BAINE');
                                  final isCanicule = upper == 'CANICULE';

                                  if (isBaine) {
                                    return _BaineDangerSelector(
                                      level: _baineLevel,
                                      onChanged: _setBaineLevel,
                                    );
                                  }

                                  if (isCanicule) {
                                    return _CaniculeDangerSelector(
                                      level: _caniculeLevel,
                                      onChanged: _setCaniculeLevel,
                                    );
                                  }

                                  final selected =
                                      _selectedDangers.contains(danger);

                                  return CheckboxListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    value: selected,
                                    activeColor: const Color(0xFFFDE047),
                                    checkColor: Colors.black,
                                    secondary: DangerPictogram(
                                      danger: danger,
                                      size: 28,
                                    ),
                                    title: Text(
                                      danger,
                                      softWrap: true,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        height: 1.15,
                                      ),
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedDangers.add(danger);
                                        } else {
                                          _selectedDangers.remove(danger);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: ElevatedButton(
                                onPressed: _validate,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFEF4444),
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                    color: Colors.black,
                                    width: 2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'VALIDER',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.black,
                          width: 2,
                        ),
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.black,
                          size: 20,
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

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isYellow = color == const Color(0xFFFDE047);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 68,
        width: double.infinity,
        decoration: BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(14),
  border: Border.all(
    color: Colors.black,
    width: 2,
  ),
),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: isYellow ? Colors.black : Colors.white,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isYellow ? Colors.black : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SauveteurNotificationPage extends StatefulWidget {
  final Color profileColor;
  final Future<bool> Function(String message) onPublish;

  const SauveteurNotificationPage({
    super.key,
    required this.profileColor,
    required this.onPublish,
  });

  @override
  State<SauveteurNotificationPage> createState() =>
      _SauveteurNotificationPageState();
}

class _SauveteurNotificationPageState
    extends State<SauveteurNotificationPage> {
  late stt.SpeechToText _speech;

  bool _isListening = false;
  bool _saving = false;
  String? _message;

  final TextEditingController controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  }

  @override
  void dispose() {
    controller.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _listen() async {
    if (!_isListening) {
      final available = await _speech.initialize();

      if (!available || !mounted) return;

      setState(() => _isListening = true);

      _speech.listen(
        localeId: 'fr_FR',
        onResult: (result) {
          if (!mounted) return;

          setState(() {
            controller.text = result.recognizedWords;
            controller.selection = TextSelection.fromPosition(
              TextPosition(offset: controller.text.length),
            );
          });
        },
      );
      return;
    }

    setState(() => _isListening = false);
    await _speech.stop();
  }

  Future<void> _submit() async {
    final message = controller.text.trim();

    if (message.isEmpty || _saving) {
      if (message.isEmpty) {
        setState(() {
          _message = 'Saisissez une notification avant de la publier.';
        });
      }
      return;
    }

    FocusScope.of(context).unfocus();
    await _speech.stop();

    if (!mounted) return;

    setState(() {
      _saving = true;
      _isListening = false;
      _message = null;
    });

    final published = await widget.onPublish(message);

    if (!mounted) return;

    if (published) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _saving = false;
      _message =
          'La notification n’a pas pu être publiée sur le SPHOT.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'data/images/map_background.jpg',
            fit: BoxFit.cover,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  Image.asset(
                    'data/icons/title.png',
                    height: 56,
                    fit: BoxFit.contain,
                  ),
                  Text(
                    'NOTIFICATION',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: widget.profileColor,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.black,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.campaign_rounded,
                                color: widget.profileColor,
                                size: 21,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Message public',
                                  style: TextStyle(
                                    color: widget.profileColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: _saving ? null : _listen,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 34,
                                  minHeight: 34,
                                ),
                                icon: Icon(
                                  _isListening
                                      ? Icons.mic_rounded
                                      : Icons.mic_none_rounded,
                                  color: _isListening
                                      ? Colors.red
                                      : widget.profileColor,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                          if (_isListening)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                'Écoute en cours...',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: TextField(
                              controller: controller,
                              enabled: !_saving,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              decoration: InputDecoration(
                                hintText:
                                    'Information utile au public sur ce SPHOT.',
                                filled: true,
                                fillColor: const Color(0xFFF3F7FA),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(
                                    color: Colors.black,
                                    width: 2,
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(
                                    color: Colors.black26,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: widget.profileColor,
                                    width: 3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_message != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _message!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFB91C1C),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: _saving ? null : _submit,
                              icon: _saving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.campaign_rounded),
                              label: Text(
                                _saving
                                    ? 'PUBLICATION...'
                                    : 'PUBLIER LA NOTIFICATION',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: widget.profileColor,
                                foregroundColor: Colors.white,
                                side: const BorderSide(
                                  color: Colors.black,
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.black,
                        width: 2,
                      ),
                    ),
                    child: IconButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.black,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
