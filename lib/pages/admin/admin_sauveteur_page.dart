import 'package:flutter/material.dart';

import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:cloud_firestore/cloud_firestore.dart';

class AdminSauveteurPage extends StatefulWidget {
  const AdminSauveteurPage({super.key});

  @override
  State<AdminSauveteurPage> createState() => _AdminSauveteurPageState();
}

class _AdminSauveteurPageState extends State<AdminSauveteurPage> {

final TextEditingController nomController = TextEditingController();
final TextEditingController prenomController = TextEditingController();
final TextEditingController ageController = TextEditingController();
final TextEditingController adresseController = TextEditingController();
final TextEditingController codePostalController = TextEditingController();
final TextEditingController villeController = TextEditingController();
final TextEditingController telephoneController = TextEditingController();
final TextEditingController emailController = TextEditingController();
final TextEditingController experienceController = TextEditingController();
final TextEditingController observationsController = TextEditingController();

final TextEditingController dateNaissanceController = TextEditingController();

final stt.SpeechToText _speech = stt.SpeechToText();

final List<String> fonctionChoices = [
  'CHEF DE POSTE',
  'ADJOINT CHEF DE POSTE',
  'SAUVETEUR',
];

final List<String> fonctionsSelectionnees = [];

final List<String> postesSelectionnes = [];

OverlayEntry? _dropdownOverlay;

Future<void> _startVoice(
  TextEditingController controller, {
  bool uppercase = false,
  bool capitalizeWords = false,
}) async {
  final available = await _speech.initialize();

  if (!available) return;

  await _speech.listen(
    localeId: 'fr_FR',
    onResult: (result) {
      setState(() {
        if (uppercase) {
  controller.text = result.recognizedWords.toUpperCase();
} else if (capitalizeWords) {
  final text = result.recognizedWords;
  controller.text = text.isEmpty
      ? text
      : text[0].toUpperCase() + text.substring(1);
} else {
  controller.text = result.recognizedWords;
}
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
                          color: const Color(0xFF1E3A8A),
                          width: 2,
                        ),
                      ),
                      child: SingleChildScrollView(
  padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          children: [

                            SizedBox(
  height: 56,
  child: _field(
    'NOM',
    controller: nomController,
    uppercase: true,
  ),
),
                            const SizedBox(height: 8),

                            _field('Prénom', controller: prenomController),
                            const SizedBox(height: 8),

                            _dateField('Date de naissance', controller: dateNaissanceController),
                            const SizedBox(height: 8),

                            _field('Âge', controller: ageController),
                            const SizedBox(height: 8),

                            _field('Adresse', controller: adresseController),
                            const SizedBox(height: 8),

                            _field('Code postal', controller: codePostalController),
                            const SizedBox(height: 8),

                            _field(
  'VILLE',
  controller: villeController,
  uppercase: true,
),
                            const SizedBox(height: 8),

                            _field('Téléphone', controller: telephoneController),
                            const SizedBox(height: 8),

                            _field('Email', controller: emailController),
                            const SizedBox(height: 8),

                            _dropdownFonction(),
                            const SizedBox(height: 8),

                            _field('Années d’expérience', controller: experienceController),
                            const SizedBox(height: 8),

                            _multiPostesSecoursField(),
                            const SizedBox(height: 8),

                            _field(
  'Observations',
  controller: observationsController,
  maxLines: 4,
  capitalizeWords: true,
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
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF1E3A8A),
                        width: 2,
                      ),
                    ),
                    child: IconButton(
  onPressed: () {
    Navigator.pop(context);
  },
  padding: EdgeInsets.zero,
  constraints: const BoxConstraints(),
  icon: const Icon(
    Icons.arrow_back_ios_new_rounded,
    color: Color(0xFF1E3A8A),
    size: 22,
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
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.88),
                    border: const Border(
  left: BorderSide(color: Color(0xFF1E3A8A), width: 1.4),
  right: BorderSide(color: Color(0xFF1E3A8A), width: 1.4),
  bottom: BorderSide(color: Color(0xFF1E3A8A), width: 1.4),
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
final selected = fonctionsSelectionnees.contains(choice);

      return InkWell(
        onTap: () {
  setState(() {
    if (selected) {
      fonctionsSelectionnees.remove(choice);
    } else {
      fonctionsSelectionnees.add(choice);
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
      : Icons.check_box_outline_blank_rounded,
  color: selected ? adminColor : const Color(0xFF1E3A8A),
  size: 22,
),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  choice,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E3A8A),
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
  labelText: fonctionsSelectionnees.isEmpty ? null : 'Fonction(s)',
  labelStyle: const TextStyle(
    color: Color(0xFF1E3A8A),
    fontWeight: FontWeight.w700,
  ),
  filled: true,
  fillColor: Colors.transparent,
  contentPadding: const EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 12,
  ),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(
      color: Color(0xFF1E3A8A),
      width: 1.6,
    ),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(
      color: Color(0xFF1E3A8A),
      width: 2,
    ),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(
      color: Color(0xFF1E3A8A),
      width: 1.6,
    ),
  ),
),
      child: Row(
        children: [
          Expanded(
            child: Text(
  fonctionsSelectionnees.isEmpty
      ? 'Fonction(s)'
      : fonctionsSelectionnees.join('\n'),
  style: const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: Color(0xFF1E3A8A),
  ),
)
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
        'SPHOT(S) affecté(s)',
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
      postesSelectionnes.isEmpty ? label : postesSelectionnes.join('\n');

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
  left: BorderSide(color: Color(0xFF1E3A8A), width: 1.4),
  right: BorderSide(color: Color(0xFF1E3A8A), width: 1.4),
  bottom: BorderSide(color: Color(0xFF1E3A8A), width: 1.4),
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
                                          : const Color(0xFF1E3A8A),
                                      size: 22,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        choice,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1E3A8A),
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
        labelText: postesSelectionnes.isEmpty ? null : label,
labelStyle: const TextStyle(
  color: Color(0xFF1E3A8A),
  fontWeight: FontWeight.w700,
),
        filled: true,
        fillColor: Colors.transparent,
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
  style: const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: Color(0xFF1E3A8A),
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

Widget _dateField(
  String label, {
  required TextEditingController controller,
}) {

  return TextField(
    controller: controller,
    readOnly: true,
    style: const TextStyle(
      color: Color(0xFF1E3A8A),
      fontWeight: FontWeight.w700,
    ),
    decoration: InputDecoration(
      labelText: label,
labelStyle: const TextStyle(
  color: Color(0xFF1E3A8A),
  fontWeight: FontWeight.w700,
),
      filled: true,
      fillColor: Colors.transparent,
      suffixIcon: IconButton(
        icon: const Icon(
  Icons.calendar_month_rounded,
  color: Color(0xFFDC2626),
),
        onPressed: () async {
          final pickedDate = await showDatePicker(
  context: context,
  initialDate: DateTime.now(),
  firstDate: DateTime(1900),
  lastDate: DateTime(2100),
  builder: (context, child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF1E3A8A), // bleu ref
          onPrimary: Colors.white,
          onSurface: Color(0xFF1E3A8A),
        ),
      ),
      child: child!,
    );
  },
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
        borderSide: const BorderSide(
          color: Color(0xFF1E3A8A),
          width: 1.6,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color(0xFF1E3A8A),
          width: 1.6,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color(0xFF1E3A8A),
          width: 2,
        ),
      ),
    ),
  );
}

  Widget _field(
  String label, {
  required TextEditingController controller,
  int maxLines = 1,
  bool uppercase = false,
  bool capitalizeWords = false,
}) {
  
  return TextField(
    controller: controller,
    textCapitalization: uppercase
    ? TextCapitalization.characters
    : TextCapitalization.none,
    maxLines: maxLines,
    style: const TextStyle(
      color: Color(0xFF1E3A8A),
      fontWeight: FontWeight.w700,
    ),
    decoration: InputDecoration(
  labelText: label,
  alignLabelWithHint: true,
  labelStyle: const TextStyle(
    color: Color(0xFF1E3A8A),
    fontWeight: FontWeight.w700,
  ),
  floatingLabelStyle: const TextStyle(
    color: Color(0xFF1E3A8A),
    fontWeight: FontWeight.w700,
  ),
  filled: true,
  fillColor: Colors.transparent,
      suffixIcon: IconButton(
        icon: const Icon(
          Icons.mic,
          color: adminColor,
        ),
        onPressed: () => _startVoice(
  controller,
  uppercase: uppercase,
  capitalizeWords: capitalizeWords,
),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color(0xFF1E3A8A),
          width: 1.6,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color(0xFF1E3A8A),
          width: 1.6,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color(0xFF1E3A8A),
          width: 2,
        ),
      ),
    ),
  );
}
}