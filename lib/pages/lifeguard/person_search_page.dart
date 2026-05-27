import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:image_picker/image_picker.dart';

import 'dart:io';

class PersonSearchPage extends StatefulWidget {
  final Color profileColor;

  const PersonSearchPage({
    super.key,
    required this.profileColor,
  });

  @override
  State<PersonSearchPage> createState() =>
      _PersonSearchPageState();
}

class _PersonSearchPageState
    extends State<PersonSearchPage> {
  late stt.SpeechToText _speech;

  bool _isListening = false;
  int? _listeningIndex;
  String? _photoPath;

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
            width: 142,

            child: Text(
              '${labels[index]} :',

              style: const TextStyle(
                color: Colors.black,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                height: 1.05,
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
                  horizontal: 8,
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

                      padding:
                          const EdgeInsets.fromLTRB(
                        12,
                        10,
                        12,
                        10,
                      ),

                      decoration: BoxDecoration(
                        color:
                            Colors.transparent,

                        borderRadius:
                            BorderRadius.circular(
                          24,
                        ),

                        border: Border.all(
                          color: Colors.black,
                          width: 2,
                        ),
                      ),

                      child:
                          SingleChildScrollView(
                        physics:
                            const BouncingScrollPhysics(),

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

                                const SizedBox(
                                  height: 120,
                                ),
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