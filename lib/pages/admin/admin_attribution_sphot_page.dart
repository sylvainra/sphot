import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter/material.dart';

import 'admin_profile_button.dart';

class AdminAttributionSphotsPage extends StatefulWidget {
  final String territoireId;

  const AdminAttributionSphotsPage({
    super.key,
    required this.territoireId,
  });

  @override
  State<AdminAttributionSphotsPage> createState() =>
      _AdminAttributionSphotsPageState();
}

class _AdminAttributionSphotsPageState
    extends State<AdminAttributionSphotsPage> {
  static const Color pageColor = Color(0xFF1E3A8A);

  

  final Set<String> selectedDocIds = {};
String selectedSphotLabel = '';
String saveMessage = '';

bool _attributionSaved = false;

OverlayEntry? _dropdownOverlay;

  final ScrollController selectedSphotsScrollController = ScrollController();

  final TextEditingController periodesController = TextEditingController();

List<String> periodesEnregistrees = [];

List<String> periodesSelectionnees = [];

  final List<String> periodeChoices = [];

@override
void initState() {
  super.initState();
  _loadDraft();
}

DocumentReference<Map<String, dynamic>> _draftRef() {
  return FirebaseFirestore.instance
    .collection('territoires')
    .doc(widget.territoireId)
    .collection('adminDrafts')
    .doc('attributionSphots');
}

Future<void> _loadDraft() async {
  final ref = _draftRef();

  final doc = await ref.get();

  if (!doc.exists) {
    return;
  }

  final data = doc.data();

  if (data == null) {
    return;
  }

  if (!mounted) {
    return;
  }

  setState(() {
    selectedDocIds.clear();

    selectedSphotLabel = '';

    periodesSelectionnees = [];

    periodesEnregistrees = [];
  });

  await _refreshSelectedSphotLabel();

}

Future<void> _refreshSelectedSphotLabel() async {
  if (selectedDocIds.isEmpty) {
    setState(() {
      selectedSphotLabel = '';
    });
    return;
  }

  final firestore = FirebaseFirestore.instance;

  final labels = <String>[];

  for (final docId in selectedDocIds) {
    final doc = await firestore
        .collection('territoires')
        .doc(widget.territoireId)
        .collection('spots')
        .doc(docId)
        .get();

    if (!doc.exists) continue;

    final data = doc.data() ?? {};

    final nomSecours = (data['nomSecours'] ?? '').toString();
    final nomSphot = (data['nomSphot'] ?? '').toString();

    final idSphot = (data['idSphot'] ?? doc.id).toString();

final label = [
  'SPHOT $idSphot',
  nomSecours,
  nomSphot,
].where((value) => value.trim().isNotEmpty).join(' - ');

    if (label.trim().isNotEmpty) {
      labels.add(label);
    }
  }

  if (!mounted) return;

  setState(() {
    selectedSphotLabel = labels.join('\n');
  });

  await _saveDraft();
}

Future<void> _saveDraft() async {
  final ref = _draftRef();

  try {
    await ref.set(
  {
    'selectedDocIds': selectedDocIds.toList(),
    'periodesSelectionnees': periodesSelectionnees,
    'periodesEnregistrees': periodesEnregistrees,

    'attributionValidee': true,
    'attributionValideeAt': DateTime.now().toIso8601String(),

    'updatedAt': FieldValue.serverTimestamp(),
  },
  SetOptions(merge: true),
);
  } catch (e) {
    _showMessage('Erreur sauvegarde brouillon : $e');
  }
}

  @override
  void dispose() {
  periodesController.dispose();
  selectedSphotsScrollController.dispose();
  _dropdownOverlay?.remove();
  super.dispose();
}

  List<String> _readValues() {
  return List.from(periodesSelectionnees);
}

  Future<void> _saveAttribution() async {
  if (selectedDocIds.isEmpty) {
    _showMessage('Sélectionnez au moins un SPHOT.');
    return;
  }

  if (periodesSelectionnees.isEmpty) {
    _showMessage('Sélectionnez au moins une période.');
    return;
  }

  final firestore = FirebaseFirestore.instance;

  final batch = firestore.batch();

  for (final spotId in selectedDocIds) {
    final spotRef = firestore
        .collection('territoires')
        .doc(widget.territoireId)
        .collection('spots')
        .doc(spotId);

    batch.set(
      spotRef,
      {
        'periodesSurveillance': periodesSelectionnees,
        'periodesSurveillanceUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  await batch.commit();

  setState(() {
    periodesEnregistrees = List<String>.from(periodesSelectionnees);
    saveMessage = '';
    _attributionSaved = true;
  });
    
}

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _sphotSelector() {
  final fieldKey = GlobalKey();

  void closeMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
  }

  return StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('territoires')
.doc(widget.territoireId)
.collection('spots')
        .where(
          'typeSphot',
          isEqualTo: '🚨 POSTE DE SECOURS 🚨',
        )
        .snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final docs = snapshot.data!.docs;

      docs.sort((a, b) {
        final dataA = a.data() as Map<String, dynamic>;
        final dataB = b.data() as Map<String, dynamic>;

        final secoursA = (dataA['nomSecours'] ?? '').toString();
        final secoursB = (dataB['nomSecours'] ?? '').toString();

        final matchA = RegExp(r'(\d+)').firstMatch(secoursA);
        final matchB = RegExp(r'(\d+)').firstMatch(secoursB);

        final numA = int.tryParse(matchA?.group(1) ?? '9999') ?? 9999;
        final numB = int.tryParse(matchB?.group(1) ?? '9999') ?? 9999;

        return numA.compareTo(numB);
      });

      void openMenu() {
  if (docs.isEmpty) return;

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
                          constraints: BoxConstraints(
                            maxHeight:
                                docs.length <= 6 ? docs.length * 43.0 : 254,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            border: const Border(
                              left: BorderSide(color: pageColor, width: 1.4),
                              right: BorderSide(color: pageColor, width: 1.4),
                              bottom: BorderSide(color: pageColor, width: 1.4),
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
                          child: ScrollbarTheme(
                            data: const ScrollbarThemeData(
                              thumbColor: MaterialStatePropertyAll(pageColor),
                            ),
                            child: Scrollbar(
                              controller: scrollController,
                              thumbVisibility: true,
                              thickness: 10,
                              radius: const Radius.circular(10),
                              child: ListView.builder(
                                controller: scrollController,
                                padding: EdgeInsets.zero,
                                itemCount: docs.length,
                                itemBuilder: (context, index) {
                                  final doc = docs[index];
                                  final data =
                                      doc.data() as Map<String, dynamic>;

                                  final nomSecours =
                                      (data['nomSecours'] ?? '').toString();
                                  final nomSphot =
                                      (data['nomSphot'] ?? '').toString();

                                  final title = [nomSecours, nomSphot]
                                      .where(
                                        (value) => value.trim().isNotEmpty,
                                      )
                                      .join(' - ');

                                  final selected =
                                      selectedDocIds.contains(doc.id);

                                  return InkWell(
                                    onTap: () {
                                      setState(() {
                                        if (selectedDocIds.contains(doc.id)) {
                                          selectedDocIds.remove(doc.id);
                                        } else {
                                          selectedDocIds.add(doc.id);
                                        }

                                        final selectedLabels = docs
                                            .where(
                                              (d) => selectedDocIds.contains(
                                                d.id,
                                              ),
                                            )
                                            .map((d) {
                                          final data = d.data()
                                              as Map<String, dynamic>;

                                          final nomSecours =
                                              (data['nomSecours'] ?? '')
                                                  .toString();
                                          final nomSphot =
                                              (data['nomSphot'] ?? '')
                                                  .toString();

                                          return [nomSecours, nomSphot]
                                              .where(
                                                (value) =>
                                                    value.trim().isNotEmpty,
                                              )
                                              .join(' - ');
                                        }).toList();

                                        selectedSphotLabel = selectedLabels.join('\n');
  saveMessage = '';
});

_saveDraft();

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
                                                ? Color(0xFFEF4444)
                                                : Colors.black54,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              title.isEmpty ? doc.id : title,
                                              maxLines: 10,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w900,
                                                color: pageColor,
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
        child: Container(
          width: double.infinity,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: pageColor,
              width: 1.6,
            ),
          ),
          child: const Row(
            children: [
              Expanded(
                child: Text(
                  'Choisir un/des SPHOT(S)',
                  maxLines: 10,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: pageColor,
                  ),
                ),
              ),
              Icon(
                Icons.checklist_rounded,
                color: Color(0xFFEF4444),
                size: 24,
              ),
              SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFFEF4444),
                size: 26,
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _periodLabelText(String label) {
  final parts = label.split(' — ');

  final titre = parts.isNotEmpty ? parts[0] : '';

  String debut = '';
  String fin = '';
  String horaires = '';

  if (parts.length > 1) {
    final dates = parts[1];

    if (dates.contains(' AU ')) {
      final morceaux = dates.split(' AU ');

      debut = morceaux.first;
      fin = 'AU ${morceaux.last}';
    } else {
      debut = dates;
    }
  }

  if (parts.length > 2) {
    horaires = parts[2];
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        titre,
        style: const TextStyle(
          color: Color(0xFFEF4444),
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),

      if (debut.isNotEmpty)
        Text(
          debut,
          style: const TextStyle(
            color: pageColor,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),

      if (fin.isNotEmpty)
        Text(
          fin,
          style: const TextStyle(
            color: pageColor,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),

      if (horaires.isNotEmpty)
        Text(
          horaires,
          style: const TextStyle(
            color: pageColor,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
    ],
  );
}

  Widget _multiDropdownField() {
  final selectedValues = _readValues();
  final fieldKey = GlobalKey();

  void closeMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
  }

  void updateSelection(String choice) {
  setState(() {
    if (periodesSelectionnees.contains(choice)) {
      periodesSelectionnees.remove(choice);
    } else {
      periodesSelectionnees.add(choice);
    }

    saveMessage = '';
  });

  _saveDraft();
}

  void openMenu() {
    closeMenu();

    final renderBox = fieldKey.currentContext!.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final scrollController = ScrollController();

    _dropdownOverlay = OverlayEntry(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, overlaySetState) {
            final liveSelectedValues = periodesSelectionnees;

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
                      constraints: const BoxConstraints(
  maxHeight: 282,
),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        border: const Border(
                          left: BorderSide(color: pageColor, width: 1.4),
                          right: BorderSide(color: pageColor, width: 1.4),
                          bottom: BorderSide(color: pageColor, width: 1.4),
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
                      child: ScrollbarTheme(
                        data: const ScrollbarThemeData(
                          thumbColor: MaterialStatePropertyAll(pageColor),
                        ),
                        child: Scrollbar(
                          controller: scrollController,
                          thumbVisibility: true,
                          thickness: 10,
                          radius: const Radius.circular(10),
                          child: StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
    .collection('territoires')
    .doc(widget.territoireId)
    .collection('periodesSurveillance')
    .orderBy('startDate')
    .snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final docs = snapshot.data!.docs;

                              if (docs.isEmpty) {
                                return const Center(
                                  child: Text(
                                    'Aucune(s) période(s) créée(s).',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: pageColor,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                );
                              }

                              return SizedBox(
  height: 282,
  child: ListView.builder(
    controller: scrollController,
    padding: EdgeInsets.zero,
    itemCount: docs.length,
                                  itemBuilder: (context, index) {
                                    final data =
                                        docs[index].data() as Map<String, dynamic>;

                                    final label =
                                        (data['label'] ?? data['name'] ?? '')
                                            .toString();

                                    final selected =
                                        liveSelectedValues.contains(label);

                                    return InkWell(
                                      onTap: () {
                                        updateSelection(label);
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
                                                  ? const Color(0xFFEF4444)
                                                  : Colors.black54,
                                              size: 22,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _periodLabelText(label),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
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
        labelText: '',
        filled: true,
        fillColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: pageColor, width: 1.6),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: pageColor, width: 1.6),
        ),
      ),
      child: Row(
        children: [
          Expanded(
  child: const Text(
    'Période(s) à attribuer',
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w900,
      color: pageColor,
    ),
  ),
),
                  
          const Icon(
            Icons.checklist_rounded,
            color: Color(0xFFEF4444),
            size: 24,
          ),
          const SizedBox(width: 2),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFFEF4444),
            size: 26,
          ),
        ],
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final selectedValues = _readValues();

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
                  SizedBox(
  height: 56,
  width: double.infinity,
  child: Stack(
    alignment: Alignment.center,
    children: [
      Image.asset(
        'data/icons/title.png',
        height: 56,
        fit: BoxFit.contain,
      ),
      const Positioned(
        right: 0,
        child: AdminProfileButton(),
      ),
    ],
  ),
),
                  const Text(
                    'ATTRIBUTION AU(X) SPHOT(S)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFEF4444),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: pageColor,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          _sphotSelector(),
                          const SizedBox(height: 14),
                          if (selectedDocIds.isNotEmpty) ...[
                            SizedBox(
  height: 62,
  child: Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: pageColor,
        width: 2,
      ),
    ),
    child: RawScrollbar(
      controller: selectedSphotsScrollController,
      thumbVisibility: true,
      thickness: 10,
      radius: const Radius.circular(10),
      thumbColor: pageColor,
      child: SingleChildScrollView(
        controller: selectedSphotsScrollController,
        child: Text(
          selectedSphotLabel,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFEF4444),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ),
  ),
),
const SizedBox(height: 14),
                               SizedBox(
  height: 52,
  child: _multiDropdownField(),
),
                            const SizedBox(height: 14),
                            Expanded(
  child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: pageColor,
                                    width: 1.4,
                                  ),
                                ),
                                child: selectedValues.isEmpty
                                    ? const Center(
    child: Text(
      'Aucune(s) période(s) attribuée(s).',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: pageColor,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    ),
  )
                                    : ListView.separated(
                                        itemCount: selectedValues.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 8),
                                        itemBuilder: (context, index) {
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
  horizontal: 12,
  vertical: 4,
),
                                            decoration: BoxDecoration(
  color: Colors.transparent,
  borderRadius: BorderRadius.circular(14),
  border: Border.all(
    color: pageColor,
    width: 1.4,
  ),
),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.check_circle_rounded,
                                                  color: Color(0xFFEF4444),
                                                  size: 22,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
  child: _periodLabelText(selectedValues[index]),
),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: _saveAttribution,
                                icon: Icon(
  _attributionSaved
      ? Icons.check_rounded
      : Icons.save_rounded,
),

label: Text(
  _attributionSaved
      ? 'ENREGISTRÉ'
      : 'ENREGISTRER',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
  elevation: 0,
  shadowColor: Colors.transparent,
  backgroundColor: _attributionSaved
      ? const Color(0xFFDC2626)
      : Colors.transparent,
  foregroundColor: _attributionSaved
      ? Colors.white
      : const Color(0xFFDC2626),
  side: const BorderSide(
    color: Color(0xFFDC2626),
    width: 2,
  ),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  ),
),
                              ),
                            ),
                            const SizedBox(height: 14),
Expanded(
  child: Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: pageColor,
        width: 1.4,
      ),
    ),
    child: periodesEnregistrees.isEmpty
        ? const Center(
            child: Text(
              'Aucune(s) période(s) enregistrée(s).',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: pageColor,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        : ListView.separated(
            itemCount: periodesEnregistrees.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return Container(
                padding: const EdgeInsets.symmetric(
  horizontal: 12,
  vertical: 4,
),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: pageColor,
                    width: 1.4,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _periodLabelText(
                        periodesEnregistrees[index],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_rounded,
                        color: Color(0xFFEF4444),
                      ),
                      onPressed: () {
                        setState(() {
                          periodesEnregistrees.removeAt(index);
                        });
                      },
                    ),
                  ],
                ),
              );
            },
          ),
  ),
),
                          ] else
                            const Expanded(
                              child: Center(
                                child: Text(
                                  'Sélectionnez un SPHOT pour lui attribuer ses périodes de surveillance.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: pageColor,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
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
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: pageColor,
                        width: 2,
                      ),
                    ),
                    child: IconButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: pageColor,
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
}