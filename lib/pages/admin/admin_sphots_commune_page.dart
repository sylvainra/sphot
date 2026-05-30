import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:latlong2/latlong.dart';

import 'admin_map_picker_page.dart';

import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

enum AdminSphotMode { none, create, copy, edit }

class AdminSphotsCommunePage extends StatefulWidget {
  const AdminSphotsCommunePage({super.key});

  @override
  State<AdminSphotsCommunePage> createState() => _AdminSphotsCommunePageState();
}

class _AdminSphotsCommunePageState extends State<AdminSphotsCommunePage> {
  static const Color adminColor = Color(0xFF1E3A8A);

  AdminSphotMode mode = AdminSphotMode.none;
  int step = 0;
  String? selectedDocId;

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
  'AUTRE',  
];

  final List<String> natureSphotChoices = [
  '🏖️ SABLE',
  '🪨 ROCHERS',
  '🏖️🪨 SABLE / ROCHERS',
  'AUTRE',
  '❔ NON RENSEIGNÉ',
];

  final List<String> accesPmrChoices = [
    'Oui',
    'Non',
    'Partiel',
    'Non renseigné',
  ];

  final List<String> moyenPmrChoices = [
    'Aucun',
    'Tiralo',
    'Hippocampe',
    'Rampe',
    'Caillebotis',
    'Stationnement PMR',
    'Sanitaires PMR',
    'Autre',
  ];

  final List<String> labelPmrChoices = [
    'Aucun',
    'Handiplage',
    'Tourisme & Handicap',
    'Autre',
  ];

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
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
      _controller(field).text = (data[field] ?? '').toString();
    }

    setState(() {});
  }

  void _loadForCopy(String docId, Map<String, dynamic> data) {
    selectedDocId = null;
    mode = AdminSphotMode.copy;
    step = 0;

    for (final field in fields) {
      _controller(field).text = (data[field] ?? '').toString();
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
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final docId = mode == AdminSphotMode.edit && selectedDocId != null
        ? selectedDocId!
        : idSphot;

    await FirebaseFirestore.instance.collection('spots').doc(docId).set(data);

    if (!mounted) return;

    _showMessage(
      mode == AdminSphotMode.edit
          ? 'SPHOT modifié'
          : 'SPHOT enregistré',
    );

    selectedDocId = docId;
    mode = AdminSphotMode.edit;
    setState(() {});
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _nextStep() {
    if (step < 6) {
      setState(() => step++);
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
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color, width: selected ? 3 : 2),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
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
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('spots').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;

        return DropdownButtonFormField<String>(
          isExpanded: true,
          value: null,
          hint: Text(label),
          items: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final ville = (data['ville'] ?? '').toString();
            final nomSecours = (data['nomSecours'] ?? '').toString();
            final nomSphot = (data['nomSphot'] ?? '').toString();

            return DropdownMenuItem(
              value: doc.id,
              child: Text(
                '$ville - $nomSecours - $nomSphot',
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (docId) {
            if (docId == null) return;
            final doc = docs.firstWhere((element) => element.id == docId);
            onSelected(doc.id, doc.data() as Map<String, dynamic>);
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withOpacity(0.25),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 1.7),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 1.7),
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

  Widget _dropdownField(String key, String label, List<String> choices) {
  final current = _value(key);
  final safeValue = choices.contains(current) ? current : null;

  return PopupMenuButton<String>(
    offset: Offset.zero,
    position: PopupMenuPosition.under,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
    ),
    color: Colors.white.withOpacity(0.98),
    elevation: 12,
    constraints: BoxConstraints(
      minWidth: MediaQuery.of(context).size.width - 56,
      maxWidth: MediaQuery.of(context).size.width - 56,
    ),
    onSelected: (value) {
      setState(() {
        _controller(key).text = value;
      });
    },
    itemBuilder: (context) {
      return choices.map((choice) {
        final selected = choice == current;

        return PopupMenuItem<String>(
          value: choice,
          padding: EdgeInsets.zero,
          child: _AdminDropdownMenuItem(
            title: choice,
            color: adminColor,
            selected: selected,
          ),
        );
      }).toList();
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        _AdminDropdownMenuItem(
          title: safeValue ?? 'Sélectionner',
          color: adminColor,
          selected: true,
          showArrow: true,
          isOpen: false,
        ),
      ],
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
      'IMPORTER LE LOGO DE LA VILLE',
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
  'Site internet de la ville',
),

const SizedBox(height: 8),

SizedBox(
  width: double.infinity,
  height: 46,
  child: ElevatedButton.icon(
    onPressed: () {
  _openMapPicker(
    title: 'POSITIONNER LA VILLE',
    latKey: 'villeLat',
    lngKey: 'villeLng',
  );
},
    icon: const Icon(Icons.map_outlined),
    label: const Text(
      'POSITIONNER LA VILLE SUR LA CARTE',
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
              'Nommez le SPHOT et choisissez son type.',
            ),
            _textField('nomSecours', 'Repère secours (ex.: LONGE 01),\nSi inexistant, ne rien inscrire.'),
            const SizedBox(height: 6),
            _textField('nomSphot', 'Nom du SPHOT,\n(ex. Plage de..., Lac de...).'),
            const SizedBox(height: 6),
            _dropdownField('typeSphot', 'Type de SPHOT', typeSphotChoices),
            const SizedBox(height: 8),
            _dropdownField('natureSphot', 'Nature du SPHOT', natureSphotChoices),
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
    title: 'POSITIONNER LE SPHOT',
    latKey: 'sphotLat',
    lngKey: 'sphotLng',
  );
},
          icon: const Icon(Icons.map_outlined),
          label: const Text(
  'POSITIONNER LE SPHOT SUR LA CARTE',
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
            _textField('adresseWebcam', 'Adresse URL webcam'),
            const SizedBox(height: 8),
            _textField('arretesMunicipaux', 'Adresse URL arrêté municipal'),
          ],
        );

      case 4:
        return Column(
          children: [
            _stepHeader(
              '5. ÉQUIPEMENTS ET LABELS',
              'Indiquez les services disponibles.',
            ),
            _textField('equipement', 'Équipements', maxLines: 3),
            const SizedBox(height: 8),
            _textField('labelSphot', 'Labels SPHOT', maxLines: 2),
          ],
        );

      case 5:
        return Column(
          children: [
            _stepHeader(
              '6. ACCESSIBILITÉ PMR',
              'Précisez les accès et moyens disponibles.',
            ),
            _dropdownField('accesPmr', 'Accès PMR', accesPmrChoices),
            const SizedBox(height: 8),
            _dropdownField('moyenPmr', 'Moyen PMR', moyenPmrChoices),
            const SizedBox(height: 8),
            _dropdownField('labelPmr', 'Label PMR', labelPmrChoices),
          ],
        );

      default:
        return Column(
          children: [
            _stepHeader(
              '7. ACTIVITÉS ET COMMERCES',
              'Complétez les activités et commerces associés.',
            ),
            _textField('activite', 'Activités', maxLines: 3),
            const SizedBox(height: 8),
            _textField('commerce', 'Commerces', maxLines: 3),
          ],
        );
    }
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
      physics: const BouncingScrollPhysics(),
      child: _currentStep(),
    );
  }

  Widget _stepControls() {
    if (!_hasStarted) return const SizedBox.shrink();

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
          child: ElevatedButton.icon(
            onPressed: step == 6 ? _saveSphot : _nextStep,
            icon: Icon(step == 6 ? Icons.save_rounded : Icons.arrow_forward_rounded),
            label: Text(
              step == 6 ? 'ENREGISTRER' : 'SUIVANT',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: step == 6 ? const Color(0xFF16A34A) : adminColor,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

Widget _existingSphotsPanel() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.10),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: const Color(0xFFF97316),
        width: 2,
      ),
    ),
    child: Column(
      children: [
        const Row(
          children: [
            Icon(
              Icons.folder_copy_rounded,
              color: Color(0xFFF97316),
              size: 28,
            ),
            SizedBox(width: 8),
            Text(
              'SPHOTS EXISTANTS',
              style: TextStyle(
                color: Color(0xFFF97316),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _sphotSelector(
          label: 'Choisir un SPHOT',
          onSelected: (docId, data) {
            selectedDocId = docId;
            setState(() {});
          },
        ),
        const SizedBox(height: 8),
        _modeButton(
  title: 'MODIFIER LE SPHOT',
  subtitle: 'Corriger un SPHOT existant',
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

_modeButton(
  title: 'COPIER LE SPHOT',
  subtitle: 'Créer un nouveau SPHOT à partir de celui-ci',
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

_modeButton(
  title: 'SUPPRIMER LE SPHOT',
  subtitle: 'Supprimer définitivement ce SPHOT',
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
          });

          _showMessage('SPHOT supprimé');
        },
),
      ],
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final bool showSelectorCopy = mode == AdminSphotMode.copy && !_hasStarted;
    final bool showSelectorEdit = mode == AdminSphotMode.edit && selectedDocId == null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('data/images/map_background.jpg', fit: BoxFit.cover),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  Image.asset('data/icons/title.png', height: 56),
                  const Text(
                    'GESTION DES SPHOTS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: adminColor,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: Column(
                        children: [
                          _modeButton(
  title: '+ NOUVEAU SPHOT',
  subtitle: 'Créer un SPHOT étape par étape',
  icon: Icons.add_location_alt_rounded,
  color: adminColor,
  selected: mode == AdminSphotMode.create,
  onTap: _newSphot,
),

if (mode == AdminSphotMode.create)
  Expanded(
    child: _formArea(),
  ),

if (mode == AdminSphotMode.none)
  Expanded(
    child: _existingSphotsPanel(),
  ),

if (mode == AdminSphotMode.copy && _hasStarted)
  Expanded(
    child: _formArea(),
  ),

if (mode == AdminSphotMode.edit && _hasStarted)
  Expanded(
    child: _formArea(),
  ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                  _stepControls(),
                  const SizedBox(height: 8),

                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.black,
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