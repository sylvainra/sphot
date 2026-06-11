import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_espace_sphot_page.dart';

import 'admin_gestion_sphot_page.dart';

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
  static const Color pageColor = Color(0xFFDC2626);

  late Map<String, dynamic> data;
  bool sphotValide = false;

  @override
void initState() {
  super.initState();

  data = Map<String, dynamic>.from(widget.data);

  sphotValide = data['sphotValide'] == true;
}

  String _value(String key) {
    final value = data[key];
    if (value == null) return '';
    if (value is Iterable) {
      return value.map((e) => e.toString()).join(' | ');
    }
    return value.toString();
  }

  String _title() {
    final id = _value('idSphot');
    final repere = _value('nomSecours');
    final nom = _value('nomSphot');

    final parts = [
      if (id.isNotEmpty) 'SPHOT $id',
      if (repere.isNotEmpty) repere,
      if (nom.isNotEmpty) nom,
    ];

    return parts.isEmpty ? widget.docId : parts.join(' - ');
  }

  Widget _resumeLine(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label : ',
              style: const TextStyle(
                color: Color(0xFF1E3A8A),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSphot() async {
    await FirebaseFirestore.instance
    .collection('territoires')
    .doc(data['territoireId'])
    .collection('spots')
    .doc(widget.docId)
    .delete();

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
  MaterialPageRoute(
    builder: (_) => AdminGestionSphotPage(
  territoireId: data['territoireId']?.toString() ?? '',
),
  ),
);
  }

  Future<void> _validateSphot() async {
  setState(() {
    sphotValide = true;
    data['sphotValide'] = true;
  });

  Future.delayed(const Duration(seconds: 2), () {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AdminGestionSphotPage(
  territoireId: data['territoireId']?.toString() ?? '',
),
      ),
    );
  });

  FirebaseFirestore.instance
    .collection('territoires')
    .doc(data['territoireId'])
    .collection('spots')
    .doc(widget.docId)
    .set(
    {
      'sphotValide': true,
      'dateValidation': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );
}

  void _editSphot() {
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) => AdminEspaceSphotPage(
  initialDocId: widget.docId,
  initialStep: 0,
  territoireId: data['territoireId']?.toString() ?? '',
),
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
                      color: Color(0xFFDC2626),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
  color: Colors.transparent,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(
    color: const Color(0xFF1E3A8A),
    width: 2,
  ),
),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _title().toUpperCase(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: sphotValide ? pageColor : const Color(0xFFDC2626),
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 12),

                            _resumeLine('Commune', _value('ville')),
                            _resumeLine('Pays', _value('pays')),
                            _resumeLine('Région', _value('region')),
                            _resumeLine('Département', _value('departement')),
                            _resumeLine('Repère secours', _value('nomSecours')),
                            _resumeLine('Nom du SPHOT', _value('nomSphot')),
                            _resumeLine('Type', _value('typeSphot')),
                            _resumeLine('Nature', _value('natureSphot')),
                            _resumeLine(
                              'Coordonnées ville',
                              '${_value('villeLat')} / ${_value('villeLng')}',
                            ),
                            _resumeLine(
                              'Coordonnées SPHOT',
                              '${_value('sphotLat')} / ${_value('sphotLng')}',
                            ),
                            _resumeLine('Webcam', _value('adresseWebcam')),
                            _resumeLine(
                              'Arrêtés municipaux',
                              _value('arretesMunicipaux'),
                            ),
                            _resumeLine('Équipements', _value('equipement')),
                            _resumeLine('Labels', _value('labelSphot')),
                            _resumeLine('Accessibilité', _value('accesPmr')),
                            _resumeLine(
                              'Moyens accessibilité',
                              _value('moyenPmr'),
                            ),
                            _resumeLine(
                              'Labels accessibilité',
                              _value('labelPmr'),
                            ),
                            _resumeLine('Activités', _value('activite')),
                            _resumeLine('Commerces', _value('commerce')),

                            const SizedBox(height: 14),

                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _editSphot,
                                    icon: const Icon(Icons.edit_rounded),
                                    label: const Text(
                                      'MODIFIER LE SPHOT',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
  backgroundColor: Colors.transparent,
  foregroundColor: const Color(0xFF1E3A8A),
  elevation: 0,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
    side: const BorderSide(
      color: Color(0xFF1E3A8A),
      width: 2,
    ),
  ),
),
                                  ),
                                ),
                                const SizedBox(width: 8),

SizedBox(
  width: 54,
  height: 48,
  child: ElevatedButton(
    onPressed: _deleteSphot,
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.transparent,
      foregroundColor: const Color(0xFFDC2626),
      elevation: 0,
      padding: EdgeInsets.zero,
    ),
    child: const Icon(
      Icons.delete_rounded,
      color: Color(0xFFDC2626),
      size: 26,
    ),
  ),
),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: sphotValide ? null : _validateSphot,
                      icon: Icon(
                        sphotValide
                            ? Icons.check_circle_rounded
                            : Icons.warning_rounded,
                      ),
                      label: Text(
                        sphotValide
                            ? 'SPHOT VALIDÉ'
                            : 'VALIDER LE SPHOT',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
      backgroundColor: Colors.transparent,
      disabledBackgroundColor: Colors.transparent,
      foregroundColor: const Color(0xFFDC2626),
      disabledForegroundColor: const Color(0xFFDC2626),
      elevation: 0,
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

                  const SizedBox(height: 8),

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
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: const Color(0xFF1E3A8A),
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