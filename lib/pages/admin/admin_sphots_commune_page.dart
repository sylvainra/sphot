import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:latlong2/latlong.dart';

import 'admin_map_picker_page.dart';

import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'admin_validation_sphots_page.dart';

enum AdminSphotMode { none, create, copy, edit }

class AdminSphotsCommunePage extends StatefulWidget {
  final String? initialDocId;
final int? initialStep;

const AdminSphotsCommunePage({
  super.key,
  this.initialDocId,
  this.initialStep,
});

  @override
  State<AdminSphotsCommunePage> createState() => _AdminSphotsCommunePageState();
}

class _AdminSphotsCommunePageState extends State<AdminSphotsCommunePage> {
  static const Color adminColor = Color(0xFF1E3A8A);

  AdminSphotMode mode = AdminSphotMode.none;
  int step = 0;
  String? selectedDocId;

  String? existingSphotMessage;

  String? saveSphotMessage;

  OverlayEntry? _dropdownOverlay;

  final ScrollController _summaryScrollController = ScrollController();
bool _summaryReadToEnd = false;

bool _summaryUserScrolled = false;

bool _sphotJustSaved = false;

  final controllers = <String, TextEditingController>{};

  final List<String> fields = [
    'idSphot',
    'pays',
    'region',
    'departement',
    'ville',
    'villeLat',
    'villeLng',
    'logoVille',
    'siteInternetVille',
    'nomSecours',
    'nomSphot',
    'typeSphot',
    'natureSphot',
    'sphotLat',
    'sphotLng',
    'adresseWebcam',
    'arretesMunicipaux',
    'equipement',
    'labelSphot',
    'accesPmr',
    'moyenPmr',
    'labelPmr',
    'activite',
    'commerce',
  ];

  final List<String> typeSphotChoices = [
  '🚨 POSTE DE SECOURS 🚨',
  '🏖️ ACCÈS PLAGE',
  '🌊 PLAGE',
  '🏞️ LAC',
  '🏞️ ÉTANG',
  '🌊 FLEUVE',
  '🏞️ RIVIÈRE',
  '💧 CASCADE',
  '🧱 BARRAGE',
  '🏝️ LAGON',
  '🏊 PISCINE NATURELLE',
   '🎡 BASE DE LOISIRS',
  '🌳 PARC',
  '💧 PLAN D’EAU',
  'AUTRE',  
];

  final List<String> natureSphotChoices = [
  '🏖️ SABLE',
  '🪨 ROCHERS',
  '🏖️🪨 SABLE / ROCHERS',
  'AUTRE',
  '❔ NON RENSEIGNÉ',
];

  final List<String> equipementChoices = [
    'AUCUN',
    '🟡 ZONE DE BAIN DÉLIMITÉE',
    '🟡 CHENAL EMBARCATION NON MOTORISÉE',
    '🟡 CHENAL EMBARCATION MOTORISÉE',
    '🏁 ZONE D’ACTIVITÉS NAUTIQUES',
    '🎠 JEUX POUR ENFANTS',
    '🏐 TERRAIN DE VOLLEY',
    '🏓 TABLE DE TENNIS DE TABLE',
    '🏋️ FITNESS AREA',
    '🗑️ POUBELLE',
    '🚯 SANS POUBELLE',
    '🚻 TOILETTES',
    '🅿️ PARKING',
    '🚐 PARKING CAMPING-CAR',
    '🚿 DOUCHE',
    '🤿 PLONGEOIR',
    '🛟 PLATE FORME FLOTTANTE',
    '🎠 TOBOGAN AQUATIQUE',
    '⚓ PONTON',
    'AUTRE',
  ];

  final List<String> labelSphotChoices = [
    'AUCUN',
    '🟦 PAVILLON BLEU',
    '♿ HANDIPLAGE',
    '🌿 GREEN COAST AWARD',
    '🌸 VILLES ET VILLAGES FLEURIS',
    '🏄 VILLE DE SURF',
    '🌱 NATURA 2000',
    '🏞️ PARC NATUREL RÉGIONAL DU MARAIS POITEVIN',
    '🌳 STATION VERTE',
    '🏖️ QUALITÉ TOURISME',
    '🌊 FRANCE STATION NAUTIQUE',
    '🐦 RAMSAR',
    '🌍 UNESCO',
    'AUTRE',
  ];

  final List<String> accesPmrChoices = [
    'Oui',
    'Non',
    'Partiel',
    'Non renseigné',
  ];

  final List<String> moyenPmrChoices = [
  'Aucun',

  '🦽 Tiralo',
  '🦽 Hippocampe',
  '♿ Rampe',
  '🟫 Caillebotis',
  '🅿️ Stationnement PMR',
  '🚻 Sanitaires PMR',

  '🚿 Douche adaptée PMR',
  '🛟 Handiplagiste',
  '👕 Vestiaire adapté PMR',
  '⛱️ Abri contre le soleil',
  '🦯 Moyen de guidage spécifique non-voyant pour la baignade',
  '🔊 Bornes sonores d’informations et d’orientation',
  '🟨 Bandes podotactiles de guidage du parking à la plage',

  'Autre',
];

  final List<String> labelPmrChoices = [
  'Aucun',

  'LABEL HANDIPLAGE 1',
  'LABEL HANDIPLAGE 2',
  'LABEL HANDIPLAGE 3',
  'LABEL HANDIPLAGE 4',

  '🏨 TOURISME & HANDICAP - MOTEUR',
  '🏨 TOURISME & HANDICAP - MENTAL',
  '🏨 TOURISME & HANDICAP - AUDITIF',
  '🏨 TOURISME & HANDICAP - VISUEL',

  'Autre',
];

final List<String> activiteChoices = [
  '🏄 SURF',
  '🏄 BODYBOARD',
  '🏄 BODYSURF',
  'STAND UP PADDLE',
  'LONGE CÔTE',
  '🪁 KITESURF',
  '🪁 SURF FOIL',
  '🪁 WINGFOIL',
  '🪁 PLANCHE À VOILE',
  '⛵ CATAMARAN',
  '⛵ VOILIER',
  'JETSKI / SCOOTER DES MERS',
  '🚤 BATEAU À MOTEUR',
  'BOUÉE TRACTÉE',
  'PARACHUTE ASCENSIONNEL',
  'FLYBOARD',
  'KAYAK SURF',
  'WAVESKI',
  'SKI NAUTIQUE / WAKE BOARD',
  'CHAR À VOILE / SPEED SAIL / KITE BUGGY',
  '🤿 SNORKELING',
  '🤿 PLONGÉE',
  '🤿 CHASSE SOUS-MARINE',
  'CLIFF DIVING',
  '🛶 CANOË',
  '🛶 KAYAK',
  '🛶 PIROGUE',
  '🛶 RAFTING',
  'HYDROSPEED',
  'CANYONING',
  'PÊCHE À PIED',
  'PÊCHE SURFCASTING',
  'NATURISME',
  'AUTRE',
  '❔ NON RENSEIGNÉ',
];

final List<String> commerceChoices = [
  'AUCUN',
  '🛏️ HÔTELLERIE',
  '🏕️ CAMPING',
  '🍴 RESTAURATION',
  '🧺 LAVERIE',
  '🤙 LOCATIONS ÉQUIPEMENTS NAUTIQUES',
  '🏖️ LOCATION / COMMERCE DE PLAGE',
  '🏖️ CLUB DE PLAGE',
  '🏄⛵ COURS ACTIVITÉS NAUTIQUES',
  '🏄⛵ ÉCOLE / CLUB NAUTIQUE',
  'AUTRE',
  '❔ NON RENSEIGNÉ',
];

@override
void initState() {
  super.initState();

  if (widget.initialDocId != null) {
  Future.microtask(() async {
    final doc = await FirebaseFirestore.instance
        .collection('spots')
        .doc(widget.initialDocId!)
        .get();

    if (!doc.exists || !mounted) return;

    _loadForEdit(
      doc.id,
      doc.data() as Map<String, dynamic>,
    );

    setState(() {
      step = widget.initialStep ?? 7;
    });
  });
}

  _summaryScrollController.addListener(() {
    if (step != 7) return;
    if (!_summaryScrollController.hasClients) return;

    final position = _summaryScrollController.position;

    if (position.maxScrollExtent < 50) {
  return;
}

    if (position.pixels > 20) {
      _summaryUserScrolled = true;
    }

    if (_summaryUserScrolled &&
        position.pixels >= position.maxScrollExtent - 20) {
      if (!_summaryReadToEnd) {
        setState(() {
          _summaryReadToEnd = true;
        });
      }
    }
  });
}

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    _dropdownOverlay?.remove();
_summaryScrollController.dispose();
super.dispose();
  }

  TextEditingController _controller(String key) {
    controllers.putIfAbsent(key, () => TextEditingController());
    return controllers[key]!;
  }

  String _value(String key) => _controller(key).text.trim();

  void _clearForm() {
    for (final field in fields) {
      _controller(field).clear();
    }
  }

  void _newSphot() {
    _clearForm();
    selectedDocId = null;
    mode = AdminSphotMode.create;
    step = 0;
    setState(() {});
  }

  void _prepareCopy() {
    _clearForm();
    selectedDocId = null;
    mode = AdminSphotMode.copy;
    step = 0;
    setState(() {});
  }

  void _prepareEdit() {
    _clearForm();
    selectedDocId = null;
    mode = AdminSphotMode.edit;
    step = 0;
    setState(() {});
  }

  void _loadForEdit(String docId, Map<String, dynamic> data) {
    selectedDocId = docId;
    mode = AdminSphotMode.edit;
    step = 0;

    for (final field in fields) {
      final value = data[field];

      if (value is Iterable) {
        _controller(field).text =
            value.map((item) => item.toString()).join(' | ');
      } else {
        _controller(field).text = (value ?? '').toString();
      }
    }

    setState(() {});
  }

  void _loadForCopy(String docId, Map<String, dynamic> data) {
    selectedDocId = null;
    mode = AdminSphotMode.copy;
    step = 0;

    for (final field in fields) {
      final value = data[field];

      if (value is Iterable) {
        _controller(field).text =
            value.map((item) => item.toString()).join(' | ');
      } else {
        _controller(field).text = (value ?? '').toString();
      }
    }

    _controller('idSphot').clear();
    _controller('nomSecours').clear();
    _controller('nomSphot').clear();
    _controller('sphotLat').clear();
    _controller('sphotLng').clear();
    _controller('adresseWebcam').clear();

    setState(() {});
  }

  bool get _hasStarted {
    if (mode == AdminSphotMode.create) return true;
    if (mode == AdminSphotMode.copy && _value('pays').isNotEmpty) return true;
    if (mode == AdminSphotMode.edit && selectedDocId != null) return true;
    return false;
  }

  Future<void> _saveSphot() async {
  setState(() {
    _sphotJustSaved = true;
  });

  Future.delayed(const Duration(seconds: 2), () {
    if (!mounted) return;

    setState(() {
      mode = AdminSphotMode.none;
      selectedDocId = null;
      step = 0;

      existingSphotMessage = null;
      saveSphotMessage = null;

      _summaryReadToEnd = false;
      _summaryUserScrolled = false;
      _sphotJustSaved = false;

      _clearForm();
    });
  });
    final idSphot = _value('idSphot');

    if (idSphot.isEmpty) {
      _showMessage('Renseigne le numéro du SPHOT');
      return;
    }

    final data = {
      'idSphot': idSphot,
      'pays': _value('pays'),
      'region': _value('region'),
      'departement': _value('departement'),
      'ville': _value('ville'),
      'villeLat': double.tryParse(_value('villeLat').replaceAll(',', '.')) ?? 0.0,
      'villeLng': double.tryParse(_value('villeLng').replaceAll(',', '.')) ?? 0.0,
      'logoVille': _value('logoVille'),
      'siteInternetVille': _value('siteInternetVille'),
      'nomSecours': _value('nomSecours'),
      'nomSphot': _value('nomSphot'),
      'typeSphot': _value('typeSphot'),
      'natureSphot': _value('natureSphot'),
      'sphotLat': double.tryParse(_value('sphotLat').replaceAll(',', '.')) ?? 0.0,
      'sphotLng': double.tryParse(_value('sphotLng').replaceAll(',', '.')) ?? 0.0,
      'adresseWebcam': _value('adresseWebcam'),
      'arretesMunicipaux': _value('arretesMunicipaux'),
      'equipement': _value('equipement'),
      'labelSphot': _value('labelSphot'),
      'accesPmr': _value('accesPmr'),
      'moyenPmr': _value('moyenPmr'),
      'labelPmr': _value('labelPmr'),
      'activite': _value('activite'),
      'commerce': _value('commerce'),
      'source': 'admin',
      'sphotValide': true,
'dateValidation': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final docId = mode == AdminSphotMode.edit && selectedDocId != null
        ? selectedDocId!
        : idSphot;

    await FirebaseFirestore.instance.collection('spots').doc(docId).set(data);

    if (!mounted) return;

setState(() {
  _sphotJustSaved = true;
  existingSphotMessage =
      mode == AdminSphotMode.edit
          ? 'SPHOT MODIFIÉ'
          : 'SPHOT ENREGISTRÉ';
});

await Future.delayed(const Duration(seconds: 2));

if (!mounted) return;

setState(() {
  mode = AdminSphotMode.none;
  selectedDocId = null;
  step = 0;

  existingSphotMessage = null;
  saveSphotMessage = null;

  _summaryReadToEnd = false;
  _summaryUserScrolled = false;
  _sphotJustSaved = false;

  _clearForm();
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

  void _nextStep() {
  if (step < 7) {
    setState(() {
      saveSphotMessage = null;
      step++;

      if (step == 7) {
  _sphotJustSaved = false;    
  _summaryReadToEnd = false;
  _summaryUserScrolled = false;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_summaryScrollController.hasClients) {
      _summaryScrollController.jumpTo(0);
    }
  });
}
    });
  }
}

  void _previousStep() {
  if (step > 0) {
    setState(() => step--);
    return;
  }

  setState(() {
    mode = AdminSphotMode.none;
    selectedDocId = null;
    step = 0;
    _clearForm();
  });
}

  Widget _modeButton({
  required String title,
  required String subtitle,
  required IconData icon,
  required Color color,
  required VoidCallback onTap,
  required bool selected,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
  color: selected
      ? adminColor.withOpacity(0.14)
      : Colors.transparent,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(
    color: adminColor,
    width: selected ? 3 : 2,
  ),
),
      child: Row(
        children: [
          Icon(
  icon,
  color: const Color(0xFFFF0000),
  size: 26,
),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
  color: adminColor,
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

  Widget _sphotSelector({
  required String label,
  required void Function(String docId, Map<String, dynamic> data) onSelected,
}) {
  final fieldKey = GlobalKey();

  void closeMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
  }

  return StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance.collection('spots').snapshots(),
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

      String displayLabel = label;

      if (selectedDocId != null) {
        final selectedDocs = docs.where((doc) => doc.id == selectedDocId);
        if (selectedDocs.isNotEmpty) {
          final data = selectedDocs.first.data() as Map<String, dynamic>;
          final nomSecours = (data['nomSecours'] ?? '').toString();
          final nomSphot = (data['nomSphot'] ?? '').toString();

          displayLabel = [nomSecours, nomSphot]
              .where((value) => value.trim().isNotEmpty)
              .join(' - ');
        }
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
                      constraints: const BoxConstraints(maxHeight: 341),
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
                      child: ScrollbarTheme(
                        data: ScrollbarThemeData(
                          thumbColor: MaterialStatePropertyAll(adminColor),
                          trackVisibility:
                              const MaterialStatePropertyAll(false),
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
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final doc = docs[index];
                              final data = doc.data() as Map<String, dynamic>;

                              final nomSecours =
                                  (data['nomSecours'] ?? '').toString();
                              final nomSphot =
                                  (data['nomSphot'] ?? '').toString();

                              final title = [nomSecours, nomSphot]
                                  .where((value) => value.trim().isNotEmpty)
                                  .join(' - ');

                              final selected = doc.id == selectedDocId;

                              return InkWell(
                                onTap: () {
                                  onSelected(doc.id, data);
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
                                        selected
                                            ? Icons.check_circle_rounded
                                            : Icons.place_rounded,
                                        color: adminColor,
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
        child: Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
  color: Colors.transparent,
  borderRadius: BorderRadius.circular(14),
  border: Border.all(
    color: const Color(0xFF1E3A8A),
    width: 1.6,
  ),
),
          child: Row(
            children: [
              Expanded(
                child: Text(
  displayLabel.toUpperCase(),
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w900,
    color: Color(0xFF1E3A8A),
  ),
),
              ),
              const Icon(
  Icons.keyboard_arrow_down_rounded,
  color: Color(0xFFFF0000),
  size: 26,
),
            ],
          ),
        ),
      );
    },
  );
}

    Widget _textField(
  String key,
  String label, {
  int maxLines = 1,
  double labelSize = 14,
}) {
    return TextField(
      controller: _controller(key),
      maxLines: maxLines,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      decoration: InputDecoration(
        label: Text(
  label,
  style: TextStyle(
    fontSize: labelSize,
  ),
),
        filled: true,
        fillColor: Colors.white.withOpacity(0.25),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black, width: 1.4),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black, width: 1.4),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: adminColor, width: 2),
        ),
      ),
    );
  }

String _cleanChoice(String value) {
  return value
      .replaceAll('’', "'")
      .replaceAll('É', 'E')
      .replaceAll('È', 'E')
      .replaceAll('Ê', 'E')
      .replaceAll('Ë', 'E')
      .replaceAll('À', 'A')
      .replaceAll('Â', 'A')
      .replaceAll('Ä', 'A')
      .replaceAll('Î', 'I')
      .replaceAll('Ï', 'I')
      .replaceAll('Ô', 'O')
      .replaceAll('Ö', 'O')
      .replaceAll('Ù', 'U')
      .replaceAll('Û', 'U')
      .replaceAll('Ü', 'U')
      .replaceAll('Ç', 'C')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('ë', 'e')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('î', 'i')
      .replaceAll('ï', 'i')
      .replaceAll('ô', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('ù', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^A-Za-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toUpperCase();
}

List<String> _readValues(String key) {
  return _value(key)
      .replaceAll('[', '')
      .replaceAll(']', '')
      .split(RegExp(r'\s*\|\s*|\s*,\s*'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
}

Widget _dropdownField(
  String key,
  String label,
  List<String> choices, {
  double maxMenuHeight = 180,
}) {
  final current = _value(key);
  final fieldKey = GlobalKey();

  void closeMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
  }

  void openMenu() {
    closeMenu();

    final renderBox = fieldKey.currentContext!.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final scrollController = ScrollController();

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
                  constraints: BoxConstraints(maxHeight: maxMenuHeight),
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
                  child: ScrollbarTheme(
                    data: ScrollbarThemeData(
                      thumbColor: MaterialStatePropertyAll(adminColor),
                      trackVisibility: const MaterialStatePropertyAll(false),
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

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _controller(key).text = choice;
                              });
                              closeMenu();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Text(
                                choice,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
              current.isEmpty ? label : current,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: current.isEmpty ? FontWeight.w400 : FontWeight.w700,
                color: current.isEmpty
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

Widget _multiDropdownField(
  String key,
  String label,
  List<String> choices, {
  double maxMenuHeight = 220,
}) {
  final selectedValues = _readValues(key);
  final fieldKey = GlobalKey();

  void closeMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
  }

  void updateSelection(String choice) {
    setState(() {
      final values = _readValues(key);

      if (_cleanChoice(choice) == _cleanChoice('AUCUN')) {
        final hasAucun = values.any(
          (value) => _cleanChoice(value) == _cleanChoice('AUCUN'),
        );

        if (hasAucun) {
          values.clear();
        } else {
          values
            ..clear()
            ..add(choice);
        }
      } else {
        values.removeWhere(
          (value) => _cleanChoice(value) == _cleanChoice('AUCUN'),
        );

        final alreadySelected = values.any(
          (value) => _cleanChoice(value) == _cleanChoice(choice),
        );

        if (alreadySelected) {
          values.removeWhere(
            (value) => _cleanChoice(value) == _cleanChoice(choice),
          );
        } else {
          values.add(choice);
        }
      }

      _controller(key).text = values.join(' | ');
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
            final liveSelectedValues = _readValues(key);

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
                      constraints: BoxConstraints(maxHeight: maxMenuHeight),
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
                      child: ScrollbarTheme(
                        data: ScrollbarThemeData(
                          thumbColor: MaterialStatePropertyAll(adminColor),
                          trackVisibility: const MaterialStatePropertyAll(false),
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

                              final selected = liveSelectedValues.any(
                                (value) =>
                                    _cleanChoice(value) == _cleanChoice(choice),
                              );

                              return InkWell(
                                onTap: () {
                                  updateSelection(choice);
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
  child: key == 'labelPmr' && choice.startsWith('LABEL HANDIPLAGE')
      ? Row(
          children: [
            Image.asset(
              'data/icons/handiplage${choice.replaceAll(RegExp(r'[^0-9]'), '')}.png',
              width: 38,
              height: 38,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            Text(
              choice,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
          ],
        )
      : Text(
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
      selectedValues.isEmpty ? label : selectedValues.join(' | ');

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
                fontWeight:
                    selectedValues.isEmpty ? FontWeight.w400 : FontWeight.w700,
                color: selectedValues.isEmpty
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

  Widget _twoColumns(Widget left, Widget right) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 8),
        Expanded(child: right),
      ],
    );
  }

  String _sphotWorkLabel() {
    final id = _value('idSphot');
    final repere = _value('nomSecours');
    final nom = _value('nomSphot');

    if (step == 1) {
      return id.isEmpty ? 'SPHOT' : 'SPHOT $id';
    }

    final parts = <String>[
      if (id.isNotEmpty) id,
      if (repere.isNotEmpty) repere,
      if (nom.isNotEmpty) nom,
    ];

    return parts.isEmpty ? 'SPHOT' : parts.join(' ');
  }

  Widget _sphotWorkBanner() {
    if (step < 1) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: adminColor.withOpacity(0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: adminColor, width: 2),
      ),
      child: Text(
        _sphotWorkLabel(),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: adminColor,
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _stepHeader(String title, String subtitle) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: adminColor, width: 2),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: adminColor,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

Future<void> _openMapPicker({
  required String title,
  required String latKey,
  required String lngKey,
}) async {
  final currentLat =
      double.tryParse(_value(latKey).replaceAll(',', '.')) ?? 0.0;
  final currentLng =
      double.tryParse(_value(lngKey).replaceAll(',', '.')) ?? 0.0;

  final result = await Navigator.of(context).push<LatLng>(
    MaterialPageRoute(
      builder: (_) => AdminMapPickerPage(
        title: title,
        initialLat: currentLat,
        initialLng: currentLng,
      ),
    ),
  );

  if (result == null) return;

  setState(() {
    _controller(latKey).text = result.latitude.toStringAsFixed(6);
    _controller(lngKey).text = result.longitude.toStringAsFixed(6);
  });
}

Future<void> _importLogoVille() async {
  final picker = ImagePicker();

  final pickedFile = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 90,
  );

  if (pickedFile == null) return;

  final file = File(pickedFile.path);
  final fileName = pickedFile.name;

  final ville = _value('ville').isEmpty
      ? 'ville_non_renseignee'
      : _value('ville')
          .toLowerCase()
          .replaceAll(' ', '_')
          .replaceAll('-', '_')
          .replaceAll("'", '_');

  final ref = FirebaseStorage.instance.ref(
    'logos_villes/$ville/$fileName',
  );

  await ref.putFile(file);

  final url = await ref.getDownloadURL();

  setState(() {
    _controller('logoVille').text = url;
  });

  _showMessage('Logo de la ville importé');
}

  Widget _currentStep() {
    switch (step) {
      case 0:
        return Column(
          children: [
            _stepHeader(
              '1. TERRITOIRE',
              'Renseignez la commune concernée par ce SPHOT.',
            ),
            _textField(
  'idSphot',
  'Numéro du SPHOT (ex.: 01, 02...)',
),
            const SizedBox(height: 8),
            _textField('pays', 'Pays'),
            const SizedBox(height: 8),
            _textField('region', 'Région'),
            const SizedBox(height: 8),
            _textField('departement', 'Département'),
            const SizedBox(height: 8),
            _textField('ville', 'Ville'),
            const SizedBox(height: 8),

SizedBox(
  width: double.infinity,
  height: 46,
  child: ElevatedButton.icon(
    onPressed: _importLogoVille,
    icon: const Icon(Icons.upload_file_rounded),
    label: const Text(
      'IMPORTEZ LE LOGO DE LA VILLE',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: adminColor,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.black, width: 2),
      ),
    ),
  ),
),

const SizedBox(height: 8),

if (_value('logoVille').isNotEmpty)
  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.green.withOpacity(0.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.green),
    ),
    child: const Text(
      '✅ Logo de la ville importé',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontWeight: FontWeight.w900,
      ),
    ),
  ),
const SizedBox(height: 8),

_textField(
  'siteInternetVille',
  'Adresse du site internet de la ville',
),

const SizedBox(height: 8),

SizedBox(
  width: double.infinity,
  height: 46,
  child: ElevatedButton.icon(
    onPressed: () {
  _openMapPicker(
    title: 'POSITIONNEZ LA VILLE',
    latKey: 'villeLat',
    lngKey: 'villeLng',
  );
},
    icon: const Icon(Icons.map_outlined),
    label: const Text(
      'POSITIONNEZ LA VILLE SUR LA CARTE',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: adminColor,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.black, width: 2),
      ),
    ),
  ),
),

const SizedBox(height: 8),

const Center(
  child: Text(
    'OU',
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w900,
    ),
  ),
),

const SizedBox(height: 8),

_twoColumns(
  _textField('villeLat', 'Latitude ville'),
  _textField('villeLng', 'Longitude ville'),
),

const SizedBox(height: 8),

          ],
        );

      case 1:
        return Column(
          children: [
            _stepHeader(
              '2. IDENTIFICATION',
              'Nommez le SPHOT et choisissez son type\net sa nature.',
            ),
            _textField('nomSecours', 'Repère secours (ex.: LONGE 01),\nSi inexistant, ne rien inscrire.'),
            const SizedBox(height: 6),
            _textField('nomSphot', 'Nom du SPHOT,\n(ex. Plage de..., Lac de...).'),
            const SizedBox(height: 6),
            _dropdownField(
  'typeSphot',
  'Type de SPHOT',
  typeSphotChoices,
  maxMenuHeight: 170,
),
            const SizedBox(height: 8),
            _dropdownField(
  'natureSphot',
  'Nature du SPHOT',
  natureSphotChoices,
  maxMenuHeight: 112,
),
          ],
        );

      case 2:
  return Column(
    children: [
      _stepHeader(
        '3. LOCALISATION',
        'Renseignez ou positionnez le SPHOT sur la carte.',
      ),

      SizedBox(
  width: double.infinity,
  height: 46,
  child: ElevatedButton.icon(
          onPressed: () {
  _openMapPicker(
    title: 'POSITIONNEZ LE SPHOT',
    latKey: 'sphotLat',
    lngKey: 'sphotLng',
  );
},
          icon: const Icon(Icons.map_outlined),
          label: const Text(
  'POSITIONNEZ LE SPHOT SUR LA CARTE',
  style: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w900,
  ),
),
          style: ElevatedButton.styleFrom(
            backgroundColor: adminColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Colors.black, width: 2),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),

const Center(
  child: Text(
    'OU',
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w900,
    ),
  ),
),

const SizedBox(height: 8),

_twoColumns(
  _textField(
    'sphotLat',
    'Latitude SPHOT',
    labelSize: 13,
  ),
  _textField(
    'sphotLng',
    'Longitude SPHOT',
    labelSize: 13,
  ),
),
    ],
  );

      case 3:
        return Column(
          children: [
            _stepHeader(
              '4. INFORMATIONS MAIRIE',
              'Ajoutez les liens externes utiles.',
            ),
            _textField('adresseWebcam', 'Adresse internet de la webcam du SPHOT'),
            const SizedBox(height: 8),
            _textField('arretesMunicipaux', 'Adresse internet des arrêtés municipaux du SPHOT'),
          ],
        );

      case 4:
        return Column(
          children: [
            _stepHeader(
              '5. ÉQUIPEMENTS ET LABELS',
              'Indiquez les services disponibles.',
            ),
            _multiDropdownField(
              'equipement',
              'Équipements du SPHOT',
              equipementChoices,
              maxMenuHeight: 275,
            ),
            const SizedBox(height: 8),
            _multiDropdownField(
              'labelSphot',
              'Labels du SPHOT',
              labelSphotChoices,
              maxMenuHeight: 217,
            ),
          ],
        );

      case 5:
  return Column(
    children: [
      _stepHeader(
        '6. ACCESSIBILITÉ',
        'Précisez les labels, accès et moyens disponibles.',
      ),
      _multiDropdownField(
  'labelPmr',
  'Labels Accessibilité',
  labelPmrChoices,
  maxMenuHeight: 275,
),
      const SizedBox(height: 8),
      _dropdownField(
  'accesPmr',
  'Accès Accessibilité',
  accesPmrChoices,
  maxMenuHeight: 155,
),

const SizedBox(height: 8),

_multiDropdownField(
  'moyenPmr',
  'Moyens Accessibilité',
  moyenPmrChoices,
  maxMenuHeight: 159,
),
    ],
  );

      case 6:
  return Column(
    children: [
      _stepHeader(
        '7. ACTIVITÉS ET COMMERCES',
        'Sélectionnez les activités et commerces associés.',
      ),
      _multiDropdownField(
        'activite',
        'Activités du SPHOT',
        activiteChoices,
        maxMenuHeight: 258,
      ),
      const SizedBox(height: 8),
      _multiDropdownField(
        'commerce',
        'Commerces du SPHOT',
        commerceChoices,
        maxMenuHeight: 200,
      ),
    ],
  );

default:
  return Column(
    children: [
      _stepHeader(
        '8. RÉSUMÉ DU SPHOT',
        'Contrôlez les informations renseignées avant enregistrement.',
      ),

      _summaryLine('Numéro du SPHOT', _value('idSphot'), 0),
      _summaryLine('Pays', _value('pays'), 0),
      _summaryLine('Région', _value('region'), 0),
      _summaryLine('Département', _value('departement'), 0),
      _summaryLine('Ville', _value('ville'), 0),
      _summaryLine('Latitude ville', _value('villeLat'), 0),
      _summaryLine('Longitude ville', _value('villeLng'), 0),
      _summaryLine('Site internet ville', _value('siteInternetVille'), 0),

      _summaryLine('Repère secours', _value('nomSecours'), 1),
      _summaryLine('Nom du SPHOT', _value('nomSphot'), 1),
      _summaryLine('Type de SPHOT', _value('typeSphot'), 1),
      _summaryLine('Nature du SPHOT', _value('natureSphot'), 1),

      _summaryLine('Latitude SPHOT', _value('sphotLat'), 2),
      _summaryLine('Longitude SPHOT', _value('sphotLng'), 2),

      _summaryLine('Webcam', _value('adresseWebcam'), 3),
      _summaryLine('Arrêtés municipaux', _value('arretesMunicipaux'), 3),

      _summaryLine('Équipements', _value('equipement'), 4),
      _summaryLine('Labels SPHOT', _value('labelSphot'), 4),

      _summaryLine('Labels Accessibilité', _value('labelPmr'), 5),
      _summaryLine('Accès Accessibilité', _value('accesPmr'), 5),
      _summaryLine('Moyens Accessibilité', _value('moyenPmr'), 5),

      _summaryLine('Activités', _value('activite'), 6),
      _summaryLine('Commerces', _value('commerce'), 6),
          ],
  );
}
}

Widget _summaryLine(
  String label,
  String value,
  int targetStep,
) {
  if (value.trim().isEmpty) {
    return const SizedBox.shrink();
  }

  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.30),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: adminColor,
        width: 1.4,
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: adminColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {
            setState(() {
              step = targetStep;
              saveSphotMessage = null;
            });
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          icon: const Icon(
            Icons.edit_rounded,
            color: adminColor,
            size: 20,
          ),
        ),
      ],
    ),
  );
}

  Widget _formArea() {
  if (!_hasStarted) {
    return const Center(
      child: Text(
        'Choisissez une action pour commencer.',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
      ),
    );
  }

  return SingleChildScrollView(
    controller: step == 7 ? _summaryScrollController : null,
    physics: const BouncingScrollPhysics(),
    child: Column(
      children: [
        _sphotWorkBanner(),
        _currentStep(),
      ],
    ),
  );
}

void _checkSummaryScroll() {
  if (!_summaryScrollController.hasClients) return;

  final position = _summaryScrollController.position;

  if (position.pixels >= position.maxScrollExtent - 20) {
    if (!_summaryReadToEnd) {
      setState(() {
        _summaryReadToEnd = true;
      });
    }
  }
}

  Widget _stepControls() {
  if (!_hasStarted) return const SizedBox.shrink();

  final bool isSummaryStep = step == 7;

  return Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _previousStep,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text(
            'PRÉCÉDENT',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: ElevatedButton(
          onPressed: isSummaryStep
              ? (_summaryReadToEnd ? _saveSphot : null)
              : _nextStep,
          style: ElevatedButton.styleFrom(
            backgroundColor: isSummaryStep
    ? (_sphotJustSaved
        ? const Color(0xFF16A34A)
        : (_summaryReadToEnd ? Colors.red : Colors.grey))
    : adminColor,
            disabledBackgroundColor: Colors.grey,
            disabledForegroundColor: Colors.white,
            foregroundColor: Colors.white,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isSummaryStep
    ? (_sphotJustSaved ? 'ENREGISTRÉ' : 'ENREGISTRER')
    : 'SUIVANT',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                isSummaryStep
                    ? (_summaryReadToEnd
                        ? Icons.save_rounded
                        : Icons.keyboard_double_arrow_down_rounded)
                    : Icons.arrow_forward_rounded,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

Widget _existingSphotsPanel({
  required double bandeauHeight,
  required double gap,
}) {
  return Container(
    width: double.infinity,
    height: double.infinity,
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.10),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: const Color(0xFF1E3A8A),
        width: 2,
      ),
    ),
    child: Column(
      children: [
        const Row(
          children: [
            Icon(
              Icons.folder_copy_rounded,
              color: Color(0xFFFF0000),
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              'SPHOTS EXISTANTS',
              style: TextStyle(
                color: Color(0xFF1E3A8A),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),

        SizedBox(height: gap),

        Expanded(
          child: Column(
            children: [
              Expanded(
                child: _sphotSelector(
                  label: 'Sélectionnez un SPHOT existant',
                  onSelected: (docId, data) {
                    selectedDocId = docId;
                    existingSphotMessage = null;
                    setState(() {});
                  },
                ),
              ),

              SizedBox(height: gap),

              Expanded(
                child: _modeButton(
                  title: 'MODIFIER LE SPHOT',
                  subtitle: '',
                  icon: Icons.edit_location_alt_rounded,
                  color: const Color(0xFF16A34A),
                  selected: false,
                  onTap: selectedDocId == null
                      ? () {}
                      : () async {
                          final doc = await FirebaseFirestore.instance
                              .collection('spots')
                              .doc(selectedDocId)
                              .get();

                          _loadForEdit(
                            doc.id,
                            doc.data() as Map<String, dynamic>,
                          );
                        },
                ),
              ),

              SizedBox(height: gap),

              Expanded(
                child: _modeButton(
                  title: 'COPIER LE SPHOT',
                  subtitle: '',
                  icon: Icons.copy_rounded,
                  color: const Color(0xFF7C3AED),
                  selected: false,
                  onTap: selectedDocId == null
                      ? () {}
                      : () async {
                          final doc = await FirebaseFirestore.instance
                              .collection('spots')
                              .doc(selectedDocId)
                              .get();

                          _loadForCopy(
                            doc.id,
                            doc.data() as Map<String, dynamic>,
                          );
                        },
                ),
              ),

              SizedBox(height: gap),

              Expanded(
                child: _modeButton(
                  title: 'SUPPRIMER LE SPHOT',
                  subtitle: '',
                  icon: Icons.delete_forever_rounded,
                  color: Colors.red,
                  selected: false,
                  onTap: selectedDocId == null
                      ? () {}
                      : () async {
                          await FirebaseFirestore.instance
                              .collection('spots')
                              .doc(selectedDocId)
                              .delete();

                          setState(() {
                            selectedDocId = null;
                            mode = AdminSphotMode.none;
                            step = 0;
                            _clearForm();
                            existingSphotMessage = 'SPHOT SUPPRIMÉ';
                          });
                        },
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.transparent,
    body: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('data/images/map_background.jpg', fit: BoxFit.cover),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Column(
              children: [
                Image.asset('data/icons/title.png', height: 42),
                const Text(
                  'GESTION DES SPHOTS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFFF0000),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
  color: Colors.transparent,
  borderRadius: BorderRadius.circular(22),
  border: Border.all(
    color: const Color(0xFF1E3A8A),
    width: 2,
  ),
),
                    child: mode == AdminSphotMode.none
                        ? LayoutBuilder(
                            builder: (context, constraints) {
                              const double gap = 8;

final double bandeauHeight =
    (constraints.maxHeight - (gap * 5)) / 6;

                              return Column(
                                children: [
                                  SizedBox(
                                    height: bandeauHeight,
                                    child: _modeButton(
                                      title: '+ CRÉER UN NOUVEAU SPHOT',
                                      subtitle: '',
                                      icon: Icons.add_location_alt_rounded,
                                      color: adminColor,
                                      selected: false,
                                      onTap: _newSphot,
                                    ),
                                  ),
                                  const SizedBox(height: gap),
                                  SizedBox(
  height: (bandeauHeight * 4) + (gap * 3),
  child: _existingSphotsPanel(
    bandeauHeight: bandeauHeight,
    gap: gap,
  ),
),
                                  
                                  
                                  const SizedBox(height: gap),
                                  SizedBox(
                                    height: bandeauHeight,
                                    child: _modeButton(
                                      title: 'CONTRÔLER/VALIDER LES SPHOTS',
                                      subtitle: '',
                                      icon: Icons.fact_check_rounded,
                                      color: const Color(0xFF16A34A),
                                      selected: false,
                                      onTap: () {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const AdminValidationSphotsPage(),
    ),
  );
},
                                    ),
                                  ),
                                ],
                              );
                            },
                          )
                        : Column(
                            children: [
                              if (mode == AdminSphotMode.create)
                                Expanded(child: _formArea()),
                              if (mode == AdminSphotMode.copy && _hasStarted)
                                Expanded(child: _formArea()),
                              if (mode == AdminSphotMode.edit && _hasStarted)
                                Expanded(child: _formArea()),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                _stepControls(),
                const SizedBox(height: 4),
                Container(
  width: 40,
  height: 40,
  decoration: BoxDecoration(
    color: Colors.transparent,
    shape: BoxShape.circle,
    border: Border.all(
      color: const Color(0xFF1E3A8A),
      width: 2,
    ),
  ),
  child: IconButton(
    onPressed: () => Navigator.of(context).pop(),
    padding: EdgeInsets.zero,
    icon: const Icon(
      Icons.arrow_back_ios_new_rounded,
      color: Color(0xFF1E3A8A),
      size: 18,
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

class _AdminDropdownMenuItem extends StatelessWidget {
  final String title;
  final Color color;
  final bool selected;
  final bool showArrow;
  final bool isOpen;

  const _AdminDropdownMenuItem({
    required this.title,
    required this.color,
    required this.selected,
    this.showArrow = false,
    this.isOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? Colors.black : Colors.black12,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.place_rounded,
            color: Color(0xFF1E3A8A),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
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
                size: 24,
              ),
            ),
        ],
      ),
    );
  }
}