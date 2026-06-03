import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminControleSphotPage extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;

  const AdminControleSphotPage({
    super.key,
    required this.docId,
    required this.data,
  });

  @override
  State<AdminControleSphotPage> createState() => _AdminControleSphotPageState();
}

class _AdminControleSphotPageState extends State<AdminControleSphotPage> {
  static const Color pageColor = Color(0xFF16A34A);

  late Map<String, dynamic> data;

  @override
  void initState() {
    super.initState();
    data = Map<String, dynamic>.from(widget.data);
  }

  String _title() {
    final nomSecours = (data['nomSecours'] ?? '').toString();
    final nomSphot = (data['nomSphot'] ?? '').toString();

    final title = [nomSecours, nomSphot]
        .where((value) => value.trim().isNotEmpty)
        .join(' - ');

    return title.isEmpty ? widget.docId : title;
  }

  String _displayValue(dynamic value) {
    if (value == null) return '';
    if (value is Iterable) {
      return value.map((item) => item.toString()).join(' | ');
    }
    return value.toString();
  }

  bool _hasValue(String key) {
    final value = data[key];

    if (value == null) return false;
    if (value is String && value.trim().isEmpty) return false;
    if (value is num && value == 0) return false;
    if (value is Iterable && value.isEmpty) return false;

    return true;
  }

  Future<void> _editField(String key, String label) async {
    final controller = TextEditingController(
      text: _displayValue(data[key]),
    );

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Modifier $label',
            style: const TextStyle(
              color: pageColor,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: label,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(controller.text.trim());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: pageColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result == null) return;

    await FirebaseFirestore.instance.collection('spots').doc(widget.docId).set(
      {
        key: result,
        'sphotValide': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    setState(() {
      data[key] = result;
      data['sphotValide'] = false;
    });
  }

  Future<void> _deleteField(String key) async {
    await FirebaseFirestore.instance.collection('spots').doc(widget.docId).set(
      {
        key: FieldValue.delete(),
        'sphotValide': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    setState(() {
      data.remove(key);
      data['sphotValide'] = false;
    });
  }

  Future<void> _validateSphot() async {
    await FirebaseFirestore.instance.collection('spots').doc(widget.docId).set(
      {
        'sphotValide': true,
        'dateValidation': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (!mounted) return;

    Navigator.of(context).pop();
  }

  Widget _fieldRow(String key, String label) {
    if (!_hasValue(key)) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.86),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: pageColor,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label : ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: pageColor,
                    ),
                  ),
                  TextSpan(
                    text: _displayValue(data[key]),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () => _editField(key, label),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 34,
            ),
            icon: const Icon(
              Icons.edit_rounded,
              color: pageColor,
              size: 20,
            ),
          ),
          IconButton(
            onPressed: () => _deleteField(key),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 34,
            ),
            icon: const Icon(
              Icons.delete_rounded,
              color: Colors.red,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _fields() {
    final rows = <Widget>[
      _fieldRow('idSphot', 'Numéro SPHOT'),
      _fieldRow('pays', 'Pays'),
      _fieldRow('region', 'Région'),
      _fieldRow('departement', 'Département'),
      _fieldRow('ville', 'Ville'),
      _fieldRow('villeLat', 'Latitude ville'),
      _fieldRow('villeLng', 'Longitude ville'),
      _fieldRow('logoVille', 'Logo ville'),
      _fieldRow('siteInternetVille', 'Site internet ville'),
      _fieldRow('nomSecours', 'Repère secours'),
      _fieldRow('nomSphot', 'Nom du SPHOT'),
      _fieldRow('typeSphot', 'Type de SPHOT'),
      _fieldRow('natureSphot', 'Nature du SPHOT'),
      _fieldRow('sphotLat', 'Latitude SPHOT'),
      _fieldRow('sphotLng', 'Longitude SPHOT'),
      _fieldRow('adresseWebcam', 'Webcam'),
      _fieldRow('arretesMunicipaux', 'Arrêtés municipaux'),
      _fieldRow('equipement', 'Équipements'),
      _fieldRow('labelSphot', 'Labels SPHOT'),
      _fieldRow('accesPmr', 'Accès PMR'),
      _fieldRow('moyenPmr', 'Moyens PMR'),
      _fieldRow('labelPmr', 'Labels PMR'),
      _fieldRow('activite', 'Activités'),
      _fieldRow('commerce', 'Commerces'),
    ];

    return rows
        .where((widget) => widget is! SizedBox)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final validated = data['sphotValide'] == true;
    final fields = _fields();

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
                    'CONTRÔLE DU SPHOT',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: pageColor,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: validated
                          ? pageColor.withOpacity(0.18)
                          : Colors.red.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: validated ? pageColor : Colors.red,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          validated
                              ? Icons.check_circle_rounded
                              : Icons.circle_rounded,
                          color: validated ? pageColor : Colors.red,
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _title().toUpperCase(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: validated ? pageColor : Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: fields.isEmpty
                        ? const Center(
                            child: Text(
                              'Aucune caractéristique renseignée.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                        : ListView(
                            children: fields,
                          ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _validateSphot,
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text(
                        'VALIDER LE SPHOT',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: pageColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
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
                    child: IconButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
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