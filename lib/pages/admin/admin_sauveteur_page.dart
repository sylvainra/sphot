import 'package:flutter/material.dart';

import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:cloud_firestore/cloud_firestore.dart';

class AdminSauveteurPage extends StatefulWidget {
  const AdminSauveteurPage({super.key});

  @override
  State<AdminSauveteurPage> createState() => _AdminSauveteurPageState();
}

class _AdminSauveteurPageState extends State<AdminSauveteurPage> {

final stt.SpeechToText _speech = stt.SpeechToText();

final List<String> fonctionChoices = [
  'Chef de poste',
  'Adjoint chef de poste',
  'Sauveteur',
];

String? fonctionSelectionnee;

final List<String> postesSelectionnes = [];

OverlayEntry? _dropdownOverlay;

Future<void> _startVoice(TextEditingController controller) async {
  final available = await _speech.initialize();

  if (!available) return;

  await _speech.listen(
    localeId: 'fr_FR',
    onResult: (result) {
      setState(() {
        controller.text = result.recognizedWords;
      });
    },
  );
}

  static const Color adminColor = Color(0xFFDC2626);

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
                  ),

                  const Text(
                    'GESTION DES SAUVETEURS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: adminColor,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.black,
                          width: 2,
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [

                            _field('Nom'),
                            const SizedBox(height: 8),

                            _field('Prénom'),
                            const SizedBox(height: 8),

                            _dateField('Date de naissance'),
                            const SizedBox(height: 8),

                            _field('Âge'),
                            const SizedBox(height: 8),

                            _field('Adresse'),
                            const SizedBox(height: 8),

                            _field('Code postal'),
                            const SizedBox(height: 8),

                            _field('Ville'),
                            const SizedBox(height: 8),

                            _field('Téléphone'),
                            const SizedBox(height: 8),

                            _field('Email'),
                            const SizedBox(height: 8),

                            _dropdownFonction(),
                            const SizedBox(height: 8),

                            _field('Années d’expérience'),
                            const SizedBox(height: 8),

                            _multiPostesSecoursField(),
                            const SizedBox(height: 8),

                            _dateField('Date début affectation'),
                            const SizedBox(height: 8),

                            _dateField('Date fin affectation'),
                            const SizedBox(height: 8),

                            _field(
                              'Observations',
                              maxLines: 4,
                            ),

                            const SizedBox(height: 15),

                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.save),
                                label: const Text(
                                  'ENREGISTRER',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.black,
                        width: 2,
                      ),
                    ),
                    child: IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
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

Widget _dropdownFonction() {
  final fieldKey = GlobalKey();

  void closeMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
  }

  void openMenu() {
    closeMenu();

    final renderBox =
        fieldKey.currentContext!.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _dropdownOverlay = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: closeMenu,
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: position.dx,
              top: position.dy + size.height - 10,
              width: size.width,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.88),
                    border: const Border(
                      left: BorderSide(color: adminColor, width: 1.4),
                      right: BorderSide(color: adminColor, width: 1.4),
                      bottom: BorderSide(color: adminColor, width: 1.4),
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Scrollbar(
  thumbVisibility: true,
  thickness: 10,
  radius: const Radius.circular(10),
  child: ListView.builder(
    padding: EdgeInsets.zero,
    shrinkWrap: true,
    itemCount: fonctionChoices.length,
    itemBuilder: (context, index) {
      final choice = fonctionChoices[index];

      return InkWell(
        onTap: () {
          setState(() {
            fonctionSelectionnee = choice;
          });
          closeMenu();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          child: Row(
            children: [
              Icon(
                fonctionSelectionnee == choice
                    ? Icons.check_circle_rounded
                    : Icons.person_rounded,
                color: adminColor,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  choice,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  ),
),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_dropdownOverlay!);
  }

  return GestureDetector(
    key: fieldKey,
    onTap: openMenu,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: 'Fonction',
        labelStyle: const TextStyle(fontSize: 14),
        filled: true,
        fillColor: Colors.white.withOpacity(0.32),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black, width: 1.6),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black, width: 1.6),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              fonctionSelectionnee ?? 'Fonction',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: fonctionSelectionnee == null
                    ? FontWeight.w400
                    : FontWeight.w700,
                color: fonctionSelectionnee == null
                    ? Colors.black.withOpacity(0.60)
                    : Colors.black,
              ),
            ),
          ),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: adminColor,
            size: 26,
          ),
        ],
      ),
    ),
  );
}

Widget _multiPostesSecoursField() {
  return StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('spots')
        .snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      }

      final docs = snapshot.data!.docs.where((doc) {
  final data = doc.data() as Map<String, dynamic>;
  final typeSphot = (data['typeSphot'] ?? '').toString();

  return typeSphot.contains('POSTE DE SECOURS');
}).toList();

      final postes = docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final nomSpot =
    (data['nomSpot'] ?? data['nomSphot'] ?? '').toString();

return nomSpot;
      }).where((value) => value.isNotEmpty).toList();

      return _multiDropdownPostes(
        'Poste de secours affecté',
        postes,
      );
    },
  );
}

Widget _multiDropdownPostes(
  String label,
  List<String> choices,
) {
  final fieldKey = GlobalKey();

  final displayText =
      postesSelectionnes.isEmpty ? label : postesSelectionnes.join(' | ');

  void closeMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
  }

  void openMenu() {
    closeMenu();

    final renderBox =
        fieldKey.currentContext!.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final scrollController = ScrollController();

    _dropdownOverlay = OverlayEntry(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, overlaySetState) {
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: closeMenu,
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  left: position.dx,
                  top: position.dy + size.height - 10,
                  width: size.width,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        border: const Border(
                          left: BorderSide(color: adminColor, width: 1.4),
                          right: BorderSide(color: adminColor, width: 1.4),
                          bottom: BorderSide(color: adminColor, width: 1.4),
                        ),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(10),
                          bottomRight: Radius.circular(10),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Scrollbar(
                        controller: scrollController,
                        thumbVisibility: true,
                        thickness: 10,
                        radius: const Radius.circular(10),
                        child: ListView.builder(
                          controller: scrollController,
                          primary: false,
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: choices.length,
                          itemBuilder: (context, index) {
                            final choice = choices[index];
                            final selected =
                                postesSelectionnes.contains(choice);

                            return InkWell(
                              onTap: () {
                                setState(() {
                                  if (selected) {
                                    postesSelectionnes.remove(choice);
                                  } else {
                                    postesSelectionnes.add(choice);
                                  }
                                });
                                overlaySetState(() {});
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      selected
                                          ? Icons.check_box_rounded
                                          : Icons
                                              .check_box_outline_blank_rounded,
                                      color: selected
                                          ? adminColor
                                          : Colors.black54,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        choice,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    Overlay.of(context).insert(_dropdownOverlay!);
  }

  return GestureDetector(
    key: fieldKey,
    onTap: openMenu,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 14),
        filled: true,
        fillColor: Colors.white.withOpacity(0.32),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black, width: 1.6),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black, width: 1.6),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              displayText,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: TextStyle(
                fontSize: 13,
                fontWeight: postesSelectionnes.isEmpty
                    ? FontWeight.w400
                    : FontWeight.w700,
                color: postesSelectionnes.isEmpty
                    ? Colors.black.withOpacity(0.60)
                    : Colors.black,
              ),
            ),
          ),
          const Icon(
            Icons.checklist_rounded,
            color: adminColor,
            size: 24,
          ),
          const SizedBox(width: 2),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: adminColor,
            size: 26,
          ),
        ],
      ),
    ),
  );
}

Widget _dateField(String label) {
  final controller = TextEditingController();

  return TextField(
    controller: controller,
    readOnly: true,
    decoration: InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white.withOpacity(0.25),
      suffixIcon: IconButton(
        icon: const Icon(
          Icons.calendar_month_rounded,
          color: adminColor,
        ),
        onPressed: () async {
          final pickedDate = await showDatePicker(
            context: context,
            initialDate: DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
           
          );

          if (pickedDate == null) return;

          controller.text =
              '${pickedDate.day.toString().padLeft(2, '0')}/'
              '${pickedDate.month.toString().padLeft(2, '0')}/'
              '${pickedDate.year}';
        },
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
  );
}

  Widget _field(
  String label, {
  int maxLines = 1,
}) {
  final controller = TextEditingController();

  return TextField(
    controller: controller,
    maxLines: maxLines,
    decoration: InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white.withOpacity(0.25),

      suffixIcon: IconButton(
        icon: const Icon(
          Icons.mic,
          color: Colors.red,
        ),
        onPressed: () => _startVoice(controller),
      ),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
  );
}
}