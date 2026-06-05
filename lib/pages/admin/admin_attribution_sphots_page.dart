import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminAttributionSphotsPage extends StatefulWidget {
  const AdminAttributionSphotsPage({super.key});

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

  OverlayEntry? _dropdownOverlay;

  final TextEditingController periodesController = TextEditingController();

  final List<String> periodeChoices = [];

  @override
  void dispose() {
    periodesController.dispose();
    _dropdownOverlay?.remove();
    super.dispose();
  }

  List<String> _readValues() {
    return periodesController.text
        .split(RegExp(r'\s*\|\s*|\s*,\s*'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Future<void> _saveAttribution() async {
    if (selectedDocIds.isEmpty) {
  _showMessage('Sélectionnez au moins un SPHOT.');
  return;
}

    final values = _readValues();

    for (final docId in selectedDocIds) {
  await FirebaseFirestore.instance.collection('spots').doc(docId).set(
    {
      'periodesSurveillance': values,
      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );
}

    setState(() {
      saveMessage = 'PÉRIODES ATTRIBUÉES AU SPHOT';
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
                                docs.length <= 6 ? docs.length * 42.0 : 252,
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

                                        selectedSphotLabel =
                                            selectedLabels.join(' | ');
                                        saveMessage = '';
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
                                                ? pageColor
                                                : Colors.black54,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              title.isEmpty ? doc.id : title,
                                              maxLines: 1,
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
                  'Sélectionnez un SPHOT existant',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: pageColor,
                  ),
                ),
              ),
              Icon(
                Icons.checklist_rounded,
                color: pageColor,
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

  Widget _multiDropdownField() {
  final selectedValues = _readValues();
  final fieldKey = GlobalKey();

  void closeMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
  }

  void updateSelection(String choice) {
    setState(() {
      final values = _readValues();

      if (values.contains(choice)) {
        values.remove(choice);
      } else {
        values.add(choice);
      }

      periodesController.text = values.join(' | ');
      saveMessage = '';
    });
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
            final liveSelectedValues = _readValues();

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
                      constraints: const BoxConstraints(maxHeight: 230),
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
                                    'Aucune période créée.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: pageColor,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                );
                              }

                              return ListView.builder(
                                controller: scrollController,
                                padding: EdgeInsets.zero,
                                itemCount: docs.length,
                                itemBuilder: (context, index) {
                                  final data =
                                      docs[index].data()
                                          as Map<String, dynamic>;

                                  final label =
                                      (data['label'] ??
                                              data['name'] ??
                                              '')
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
                                                ? pageColor
                                                : Colors.black54,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              label,
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

  final displayText =
      selectedValues.isEmpty ? 'Périodes à attribuer' : selectedValues.join(' | ');

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
            child: Text(
              displayText,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: pageColor,
              ),
            ),
          ),
          const Icon(
            Icons.checklist_rounded,
            color: pageColor,
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
                  Image.asset(
                    'data/icons/title.png',
                    height: 56,
                    fit: BoxFit.contain,
                  ),
                  const Text(
                    'ATTRIBUTION AUX SPHOTS',
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
                            Container(
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
                              child: Text(
                                selectedSphotLabel,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: pageColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
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
                                          'Aucune période attribuée.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
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
                                              vertical: 10,
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
                                                  color: pageColor,
                                                  size: 22,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    selectedValues[index],
                                                    style: const TextStyle(
                                                      color: pageColor,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: _saveAttribution,
                                icon: const Icon(Icons.save_rounded),
                                label: const Text(
                                  'ENREGISTRER',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF16A34A),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                            if (saveMessage.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: pageColor,
                                    width: 2,
                                  ),
                                ),
                                child: Text(
                                  saveMessage,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
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