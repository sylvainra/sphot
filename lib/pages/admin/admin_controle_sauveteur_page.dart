import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'admin_creation_sauveteur_page.dart';
import 'admin_profile_button.dart';

class AdminControleSauveteurPage extends StatefulWidget {
  final String territoireId;
  final String docId;
  final Map<String, dynamic> data;

  const AdminControleSauveteurPage({
    super.key,
    required this.territoireId,
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
  territoireId: widget.territoireId,
  docId: widget.docId,
  data: data,
),
      ),
    );
  }

  Future<void> _deleteSauveteur() async {
  final sauveteurRef = FirebaseFirestore.instance
      .collection('territoires')
      .doc(widget.territoireId)
      .collection('sauveteurs')
      .doc(widget.docId);

  final sauveteurSnapshot = await sauveteurRef.get();
  final sauveteurData = sauveteurSnapshot.data() ?? {};

  final postesAffectes = sauveteurData['postesAffectes'];

  if (postesAffectes is Iterable) {
    for (final poste in postesAffectes) {
      final posteText = poste.toString();
      final posteId = posteText
          .replaceAll('SPHOT ', '')
          .split(' - ')
          .first
          .trim();

      if (posteId.isEmpty) continue;

      await FirebaseFirestore.instance
          .collection('territoires')
          .doc(widget.territoireId)
          .collection('spots')
          .doc(posteId)
          .collection('sauveteursAffectes')
          .doc(widget.docId)
          .delete();
    }
  }

  await sauveteurRef.delete();

  if (!mounted) return;
  Navigator.of(context).pop();
}

Widget _accessSauveteurBlock() {
  final login = _value('login').isEmpty ? 'NON GÉNÉRÉ' : _value('login');
  final status = _value('accountStatus').isEmpty
      ? 'ACTIVE'
      : _value('accountStatus');

  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: adminColor,
        width: 1.6,
      ),
    ),
    child: Column(
      children: [
        const Text(
          'ACCÈS SAUVETEUR',
          style: TextStyle(
            color: actionColor,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),

        _resumeLine('Identifiant', login),
        _resumeLine('Statut', status),

        const SizedBox(height: 10),

        _accessButton('GÉNÉRER LES ACCÈS', Icons.key_rounded, () {}),
        _accessButton('RÉINITIALISER LE MOT DE PASSE', Icons.password_rounded, () {}),
        _accessButton('ENVOYER PAR EMAIL', Icons.email_rounded, () {}),
        _accessButton('ENVOYER PAR SMS', Icons.sms_rounded, () {}),

        const SizedBox(height: 8),

        _accessButton('SUSPENDRE LE COMPTE', Icons.pause_circle_rounded, () {}),
        _accessButton('SUPPRIMER LE COMPTE', Icons.delete_forever_rounded, () {}),
      ],
    ),
  );
}

Widget _accessButton(String title, IconData icon, VoidCallback onTap) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    child: OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: actionColor),
      label: Text(
        title,
        style: const TextStyle(
          color: actionColor,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(
          color: actionColor,
          width: 1.6,
        ),
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
                            _accessSauveteurBlock(),
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
  foregroundColor: actionColor,
  elevation: 0,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
    side: const BorderSide(
      color: actionColor,
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