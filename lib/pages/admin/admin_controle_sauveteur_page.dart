import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'admin_creation_sauveteur_page.dart';

class AdminControleSauveteurPage extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;

  const AdminControleSauveteurPage({
    super.key,
    required this.docId,
    required this.data,
  });

  @override
  State<AdminControleSauveteurPage> createState() =>
      _AdminControleSauveteurPageState();
}

class _AdminControleSauveteurPageState
    extends State<AdminControleSauveteurPage> {
  static const Color adminColor = Color(0xFF1E3A8A);
  static const Color actionColor = Color(0xFFDC2626);

  late Map<String, dynamic> data;

  @override
  void initState() {
    super.initState();
    data = Map<String, dynamic>.from(widget.data);
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
    final nom = _value('nom');
    final prenom = _value('prenom');
    final title = '$nom $prenom'.trim();
    return title.isEmpty ? widget.docId : title;
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
                color: adminColor,
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

  void _editSauveteur() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AdminCreationSauveteurPage(
          docId: widget.docId,
          data: data,
        ),
      ),
    );
  }

  Future<void> _deleteSauveteur() async {
    await FirebaseFirestore.instance
        .collection('sauveteurs')
        .doc(widget.docId)
        .delete();

    if (!mounted) return;
    Navigator.of(context).pop();
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
                    'CONTRÔLE DU SAUVETEUR',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: actionColor,
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
                            color: adminColor,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Text(
                                _title().toUpperCase(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: actionColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _resumeLine('Nom', _value('nom')),
                            _resumeLine('Prénom', _value('prenom')),
                            _resumeLine('Date de naissance', _value('dateNaissance')),
                            _resumeLine('Âge', _value('age')),
                            _resumeLine('Adresse', _value('adresse')),
                            _resumeLine('Code postal', _value('codePostal')),
                            _resumeLine('Ville', _value('ville')),
                            _resumeLine('Téléphone', _value('telephone')),
                            _resumeLine('Email', _value('email')),
                            _resumeLine('Fonction(s)', _value('fonctions')),
                            _resumeLine('SPHOT(s) affecté(s)', _value('postesAffectes')),
                            _resumeLine('Années d’expérience', _value('experience')),
                            _resumeLine('Observations', _value('observations')),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _editSauveteur,
                                    icon: const Icon(Icons.edit_rounded),
                                    label: const Text(
                                      'MODIFIER LE SAUVETEUR',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: adminColor,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: const BorderSide(
                                          color: adminColor,
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
                                    onPressed: _deleteSauveteur,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: actionColor,
                                      elevation: 0,
                                      padding: EdgeInsets.zero,
                                    ),
                                    child: const Icon(
                                      Icons.delete_rounded,
                                      color: actionColor,
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
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: adminColor,
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
                        color: adminColor,
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