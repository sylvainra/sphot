import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:image_picker/image_picker.dart';

import 'dart:io';

import '../../services/sauveteur_live_publication_service.dart';

class SauveteurRecherchePersonnePage extends StatefulWidget {
  final Color profileColor;
  final String territoireId;
  final String sphotMode;
  final String sauveteurSessionToken;
  final List<String> postesAffectes;
  final String? initialSpotId;

  const SauveteurRecherchePersonnePage({
    super.key,
    required this.profileColor,
    required this.territoireId,
    required this.sphotMode,
    required this.sauveteurSessionToken,
    required this.postesAffectes,
    required this.initialSpotId,
  });

  @override
  State<SauveteurRecherchePersonnePage> createState() =>
      _SauveteurRecherchePersonnePageState();
}

class _SauveteurRecherchePersonnePageState
    extends State<SauveteurRecherchePersonnePage> {
  late stt.SpeechToText _speech;

  bool _isListening = false;
  int? _listeningIndex;
  String? _photoPath;

  final List<SauveteurAssignedSpot> _assignedSpots = [];
  String? _selectedSpotId;
  bool _loadingLive = true;
  bool _publishing = false;
  String? _publishMessage;

  bool get _isSphotOn => widget.sphotMode.toUpperCase() == 'ON';

  final List<String> labels = [
    'Recherché(e) depuis',
    'Lieu de perdition sur la plage',
    'Lieu de station sur la plage',
    'Prénom et NOM de la personne recherchée',
    'Sexe, âge et nationalité',
    'Taille',
    'Corpulence',
    'Chevelure',
    'Chapeau, casquette',
    'Maillot',
    'Brassards, bouée',
    'Jeux de plages',
    'Autre(s) signe(s) distinctif(s)',
    'Prénom(s) et NOM des représentants légaux',
    'Adresse des représentants légaux',
    'Numéro de téléphone',
    'Photo de la personne recherchée',
  ];

  late final List<TextEditingController>
      controllers;

  @override
  void initState() {
    super.initState();

    _speech = stt.SpeechToText();

    controllers = List.generate(
      labels.length,
      (_) => TextEditingController(),
    );

    _loadLiveContext();
  }

  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }

    _speech.stop();

    super.dispose();
  }

  Future<void> _listenToField(
    int index,
  ) async {
    if (_isListening &&
        _listeningIndex == index) {
      setState(() {
        _isListening = false;
        _listeningIndex = null;
      });

      await _speech.stop();

      return;
    }

    final bool available =
        await _speech.initialize();

    if (!available) return;

    setState(() {
      _isListening = true;
      _listeningIndex = index;
    });

    _speech.listen(
      localeId: 'fr_FR',
      onResult: (result) {
        setState(() {
          controllers[index].text =
              result.recognizedWords;

          controllers[index].selection =
              TextSelection.fromPosition(
            TextPosition(
              offset:
                  controllers[index]
                      .text
                      .length,
            ),
          );
        });
      },
    );
  }

Future<void> _pickPhoto() async {
  final ImagePicker picker = ImagePicker();

  final XFile? image = await picker.pickImage(
    source: ImageSource.camera,
    imageQuality: 85,
  );

  if (image != null) {
    setState(() {
      _photoPath = image.path;
    });
  }
}


  Future<void> _loadLiveContext() async {
    try {
      final spots = await SauveteurLivePublicationService.loadAssignedSpots(
        territoireId: widget.territoireId,
        postesAffectes: widget.postesAffectes,
      );

      if (!mounted) return;

      final initialSpotId = widget.initialSpotId;
      setState(() {
        _assignedSpots
          ..clear()
          ..addAll(spots);
        _selectedSpotId =
            initialSpotId != null &&
                    spots.any((spot) => spot.id == initialSpotId)
                ? initialSpotId
                : (spots.isEmpty ? null : spots.first.id);
        _loadingLive = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingLive = false;
        _publishMessage = 'Impossible de charger le poste affecté.';
      });
    }
  }

  String _fieldValue(int index) => controllers[index].text.trim();

  String _buildPublicNotificationMessage() {
    final parts = <String>['RECHERCHE DE PERSONNE EN COURS'];

    final identity = _fieldValue(3);
    final identityDetails = _fieldValue(4);
    final since = _fieldValue(0);
    final lostPlace = _fieldValue(1);
    final stationPlace = _fieldValue(2);

    if (identity.isNotEmpty) parts.add(identity);
    if (identityDetails.isNotEmpty) parts.add(identityDetails);
    if (since.isNotEmpty) parts.add('Recherché(e) depuis : $since');
    if (lostPlace.isNotEmpty) {
      parts.add('Dernier lieu connu : $lostPlace');
    }
    if (stationPlace.isNotEmpty) {
      parts.add('Lieu de station : $stationPlace');
    }

    final description = <String>[];
    for (final index in const [5, 6, 7, 8, 9, 10, 11, 12]) {
      final value = _fieldValue(index);
      if (value.isNotEmpty) {
        description.add('${labels[index]} : $value');
      }
    }
    if (description.isNotEmpty) {
      parts.add(description.join(', '));
    }

    return parts.join(' • ');
  }

  String _buildMainCouranteDescription() {
    final details = <String>[];

    for (var index = 0; index <= 15; index++) {
      final value = _fieldValue(index);
      if (value.isNotEmpty) {
        details.add('${labels[index]} : $value');
      }
    }

    details.add(
      'Photo prise sur l’appareil : ${_photoPath == null ? 'non' : 'oui'}',
    );

    return details.join('\n');
  }

  Future<void> _publishSearch() async {
    if (_publishing || _loadingLive) return;

    if (!_isSphotOn) {
      setState(() {
        _publishMessage =
            'SPHOT OFF — la publication opérationnelle est désactivée.';
      });
      return;
    }

    if (_selectedSpotId == null) {
      setState(() {
        _publishMessage = 'Aucun poste de secours affecté.';
      });
      return;
    }

    final publicMessage = _buildPublicNotificationMessage();
    if (publicMessage == 'RECHERCHE DE PERSONNE EN COURS') {
      setState(() {
        _publishMessage =
            'Renseignez au moins l’identité, le signalement ou le lieu de disparition.';
      });
      return;
    }

    setState(() {
      _publishing = true;
      _publishMessage = null;
    });

    try {
      await SauveteurLivePublicationService.publish(
        sauveteurSessionToken: widget.sauveteurSessionToken,
        spotId: _selectedSpotId!,
        changes: {
          'notificationPublique': {
            'message': publicMessage,
            'active': true,
            'source': 'recherche_personne',
            'mainCouranteDescription': _buildMainCouranteDescription(),
          },
        },
      );

      if (!mounted) return;
      setState(() {
        _publishMessage =
            'Recherche publiée dans la notification publique et la main courante.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _publishMessage =
            'Publication refusée. Vérifiez votre autorisation et le poste sélectionné.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _publishing = false;
        });
      }
    }
  }

  Widget _publishButton() {
    final enabled =
        _isSphotOn && _selectedSpotId != null && !_loadingLive && !_publishing;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 42,
          child: ElevatedButton.icon(
            onPressed: enabled ? _publishSearch : null,
            icon: const Icon(Icons.cloud_upload_outlined, size: 18),
            label: Text(
              _publishing ? 'PUBLICATION...' : 'PUBLIER',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.profileColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.black12,
            ),
          ),
        ),
        if (_publishMessage != null) ...[
          const SizedBox(height: 5),
          Text(
            _publishMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _publishMessage!.startsWith('Recherche publiée')
                  ? const Color(0xFF15803D)
                  : const Color(0xFFB91C1C),
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }

  Widget _field(
  int index, {
  int minLines = 1,
  int maxLines = 2,
}) {
    final bool listening =
        _isListening &&
        _listeningIndex == index;

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 7,
      ),

      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.center,

        children: [
          SizedBox(
            width: 176,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '${labels[index]} :',
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
            ),
          ),

          Expanded(
            child: TextField(
              controller:
                  controllers[index],

              minLines: minLines,
maxLines: maxLines,

              style: const TextStyle(
                fontSize: 11,
                fontWeight:
                    FontWeight.w700,
              ),

              decoration: InputDecoration(
                isDense: true,

                contentPadding:
                    const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 7,
                ),

                filled: true,

                fillColor:
                    Colors.white.withOpacity(
                  0.45,
                ),

                border:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                    10,
                  ),

                  borderSide:
                      const BorderSide(
                    color: Colors.black,
                    width: 1.2,
                  ),
                ),

                enabledBorder:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                    10,
                  ),

                  borderSide:
                      const BorderSide(
                    color: Colors.black,
                    width: 1.2,
                  ),
                ),

                focusedBorder:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                    10,
                  ),

                  borderSide:
                      BorderSide(
                    color:
                        widget.profileColor,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 5),

          GestureDetector(
            onTap: () =>
                _listenToField(index),

            child: Icon(
              listening
                  ? Icons.mic_rounded
                  : Icons
                      .mic_none_rounded,

              color: listening
                  ? Colors.red
                  : widget.profileColor,

              size: 21,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
  resizeToAvoidBottomInset: true,
      backgroundColor:
          Colors.transparent,

      body: Stack(
        fit: StackFit.expand,

        children: [
          Image.asset(
            'data/images/map_background.jpg',
            fit: BoxFit.cover,
          ),

          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                16,
                8,
                16,
                16,
              ),

              child: Column(
                children: [
                  Image.asset(
                    'data/icons/title.png',
                    height: 56,
                    fit: BoxFit.contain,
                  ),

                  Text(
                    'RECHERCHE DE PERSONNE',

                    textAlign:
                        TextAlign.center,

                    style: TextStyle(
                      fontSize: 22,
                      fontWeight:
                          FontWeight.w900,
                      color:
                          widget.profileColor,
                      letterSpacing: 0.6,
                    ),
                  ),

                  const SizedBox(height: 2),

                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(
                        12,
                        10,
                        12,
                        10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.black,
                          width: 2,
                        ),
                      ),
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: EdgeInsets.zero,
                        child: Stack(
                          children: [

                            // PERSONNAGES EN FOND

                            Positioned(
                              left: -105,
                              top: 0,

                              child: Opacity(
                                opacity: 0.18,

                                child: Icon(
                                  Icons.man_rounded,
                                  color:
                                      Colors.blue,
                                  size: 420,
                                ),
                              ),
                            ),

                            Positioned(
                              right: -120,
                              top: 95,

                              child: Opacity(
                                opacity: 0.18,

                                child: Icon(
                                  Icons.woman_rounded,
                                  color: Colors
                                      .pinkAccent,
                                  size: 420,
                                ),
                              ),
                            ),

                            Column(
                              children: [
                                _field(0),
                                _field(1),
                                _field(2),

                                const SizedBox(
                                  height: 10,
                                ),

                                _field(3),
                                _field(4),
                                _field(5),
                                _field(6),
                                _field(7),
                                _field(8),
                                _field(9),
                                _field(10),
                                _field(11),
                                _field(12),

                                const SizedBox(
                                  height: 14,
                                ),

                                _field(13),
                                _field(
  14,
  minLines: 3,
  maxLines: 4,
),
                                _field(15),
                                Padding(
  padding: const EdgeInsets.only(top: 8),
  child: GestureDetector(
    onTap: _pickPhoto,
    child: Container(
      width: double.infinity,
      height: 180,

      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.25),

        borderRadius: BorderRadius.circular(18),

        border: Border.all(
          color: Colors.black,
          width: 1.5,
        ),
      ),

      child: _photoPath == null
          ? Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: const [
                Icon(
                  Icons.photo_camera_rounded,
                  size: 52,
                  color: Colors.black,
                ),
                SizedBox(height: 10),
                Text(
                  'PHOTO DE LA PERSONNE RECHERCHÉE',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: Colors.black,
                  ),
                ),
              ],
            )
          : ClipRRect(
    borderRadius:
        BorderRadius.circular(16),
    child: Image.file(
      File(_photoPath!),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    ),
  ),
    ),
  ),
),

                                const SizedBox(height: 12),
                                _publishButton(),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Transform.translate(
                    offset: const Offset(
                      0,
                      9,
                    ),

                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(
                          context,
                        ).pop();
                      },

                      child: Container(
                        width: 50,
                        height: 50,

                        decoration:
                            BoxDecoration(
                          color:
                              Colors.transparent,

                          shape:
                              BoxShape.circle,

                          border: Border.all(
                            color:
                                Colors.black,
                            width: 2,
                          ),
                        ),

                        child: const Center(
                          child: Icon(
                            Icons
                                .arrow_back_ios_new_rounded,

                            color:
                                Colors.black,

                            size: 22,
                          ),
                        ),
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