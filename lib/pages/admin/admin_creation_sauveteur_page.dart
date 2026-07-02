import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'dart:async';

import 'admin_profile_button.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;



class AdminCreationSauveteurPage extends StatefulWidget {
  final String? docId;
  final Map<String, dynamic>? data;
  final String territoireId;

  const AdminCreationSauveteurPage({
    super.key,
    this.docId,
    this.data,
    required this.territoireId,
  });

  @override
  State<AdminCreationSauveteurPage> createState() =>
    _AdminCreationSauveteurPageState();
}

class _AdminCreationSauveteurPageState extends State<AdminCreationSauveteurPage> {

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

bool sauveteurEnregistre = false;

String generatedLogin = '';
String generatedPassword = '';
bool accesGenere = false;

bool emailEnvoye = false;


String? createdSauveteurDocId;

@override
void initState() {
  super.initState();

  final data = widget.data;
  if (data == null) return;

  nomController.text = (data['nom'] ?? '').toString();
  prenomController.text = (data['prenom'] ?? '').toString();
  dateNaissanceController.text = (data['dateNaissance'] ?? '').toString();
  _updateAgeFromBirthDate();
  adresseController.text = (data['adresse'] ?? '').toString();
  codePostalController.text = (data['codePostal'] ?? '').toString();
  villeController.text = (data['ville'] ?? '').toString();
  telephoneController.text = (data['telephone'] ?? '').toString();
  emailController.text = (data['email'] ?? '').toString();
  experienceController.text = (data['experience'] ?? '').toString();
  observationsController.text = (data['observations'] ?? '').toString();

  final fonctions = data['fonctions'];
  if (fonctions is Iterable) {
    fonctionsSelectionnees
      ..clear()
      ..addAll(fonctions.map((e) => e.toString()));
  }

  final postes = data['postesAffectes'];
  if (postes is Iterable) {
    postesSelectionnes
      ..clear()
      ..addAll(postes.map((e) => e.toString()));
  }
}

Future<void> _startVoice(
  TextEditingController controller, {
  bool uppercase = false,
  bool capitalizeWords = false,
}) async {
  final available = await _speech.initialize();

  if (!available) return;

  await _speech.listen(
    localeId: 'fr_FR',
    listenFor: const Duration(seconds: 10),
    pauseFor: const Duration(seconds: 3),
    onResult: (result) async {
      if (!mounted) return;

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

      if (result.finalResult) {
        await _speech.stop();
      }
    },
  );
}

Future<String> _generateUniqueLogin(String baseLogin) async {
  final sauveteursRef = FirebaseFirestore.instance
      .collection('territoires')
      .doc(widget.territoireId)
      .collection('sauveteurs');

  String candidate = baseLogin;
  int counter = 2;

  while (true) {
    final existing = await sauveteursRef
    .where('login', isEqualTo: candidate)
    .limit(1)
    .get();

if (existing.docs.isEmpty) {
  return candidate;
}

    candidate = '$baseLogin$counter';
    counter++;
  }
}

  static const Color adminColor = Color(0xFFDC2626);

String _normalizeLogin(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâäãå]'), 'a')
      .replaceAll(RegExp(r'[ç]'), 'c')
      .replaceAll(RegExp(r'[èéêë]'), 'e')
      .replaceAll(RegExp(r'[ìíîï]'), 'i')
      .replaceAll(RegExp(r'[ñ]'), 'n')
      .replaceAll(RegExp(r'[òóôöõ]'), 'o')
      .replaceAll(RegExp(r'[ùúûü]'), 'u')
      .replaceAll(RegExp(r'[ýÿ]'), 'y')
      .replaceAll('æ', 'ae')
      .replaceAll('œ', 'oe')
      .replaceAll(RegExp(r"[' -]"), '');
}

 Future<void> _generateAccess() async {
  final nom = nomController.text.trim();
  final prenom = prenomController.text.trim();

  if (nom.isEmpty || prenom.isEmpty) return;

  if (!_validateContactBeforeAccess()) return;

  final baseLogin = _normalizeLogin('${prenom[0]}$nom');

final login =
    await _generateUniqueLogin(baseLogin);

  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final now = DateTime.now().millisecondsSinceEpoch;

  String password = '';

  for (int i = 0; i < 8; i++) {
    password += chars[(now + i * 17) % chars.length];
  }

  final sauveteursRef = FirebaseFirestore.instance
      .collection('territoires')
      .doc(widget.territoireId)
      .collection('sauveteurs');

  final docRef = widget.docId == null
    ? sauveteursRef.doc(createdSauveteurDocId)
    : sauveteursRef.doc(widget.docId);

createdSauveteurDocId ??= docRef.id;

  await docRef.set({
    'login': login,
    'temporaryPassword': password,
    'mustChangePassword': true,
    'accountStatus': 'ACTIVE',
    'accessGeneratedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  await _upsertSauveteurAccount(
  login: login,
  temporaryPassword: password,
  accountStatus: 'ACTIVE',
  sauveteurId: docRef.id,
  nom: nom.toUpperCase(),
  prenom: prenom,
  email: emailController.text.trim(),
);

  setState(() {
  generatedLogin = login;
  generatedPassword = password;
  accesGenere = true;

  emailEnvoye = false;
});
}

Future<void> _upsertSauveteurAccount({
  required String login,
  required String temporaryPassword,
  required String accountStatus,
  required String sauveteurId,
  required String nom,
  required String prenom,
  required String email,
}) async {
  final uri = Uri.parse(
    'https://us-central1-sphot-ab80b.cloudfunctions.net/upsertSauveteurAccount',
  );

  await http.post(
    uri,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'login': login,
      'temporaryPassword': temporaryPassword,
      'mustChangePassword': true,
      'accountStatus': accountStatus,
      'territoireId': widget.territoireId,
      'sauveteurId': sauveteurId,
      'nom': nom,
      'prenom': prenom,
      'email': email,
      'role': 'SAUVETEUR',
    }),
  );
}

Future<void> _sendCredentialsEmail() async {
  final email = emailController.text.trim();
  final prenom = prenomController.text.trim();

  if (email.isEmpty || generatedLogin.isEmpty || generatedPassword.isEmpty) {
    return;
  }

  if (!mounted) return;

  setState(() {
  emailEnvoye = true;
});

debugPrint(">>> emailEnvoye = $emailEnvoye");

  final uri = Uri.https(
    'us-central1-sphot-ab80b.cloudfunctions.net',
    '/sendSauveteurCredentialsEmail',
    {
      'email': email,
      'prenom': prenom,
      'identifiant': generatedLogin,
      'motdepasse': generatedPassword,
    },
  );

  try {
    debugPrint(">>> Avant appel HTTP");
    final response = await http.get(uri);
    debugPrint(">>> Après appel HTTP");

    debugPrint("STATUS EMAIL = ${response.statusCode}");
    debugPrint("BODY EMAIL = ${response.body}");

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('Erreur email SPHOT : ${response.statusCode} - ${response.body}');
    }
  } catch (e) {
    debugPrint('Email probablement envoyé, mais réponse non lisible : $e');
  }
}

bool _validateSauveteurBeforeSave() {
  if (nomController.text.trim().isEmpty) {
    _showError('Le nom du sauveteur est obligatoire.');
    return false;
  }

  if (prenomController.text.trim().isEmpty) {
    _showError('Le prénom du sauveteur est obligatoire.');
    return false;
  }

  if (telephoneController.text.trim().isEmpty) {
    _showError('Le téléphone du sauveteur est obligatoire.');
    return false;
  }

  if (emailController.text.trim().isEmpty) {
    _showError('L’adresse email du sauveteur est obligatoire.');
    return false;
  }

  if (!emailController.text.trim().contains('@')) {
    _showError('L’adresse email du sauveteur n’est pas valide.');
    return false;
  }

  if (fonctionsSelectionnees.isEmpty) {
    _showError('Sélectionne au moins une fonction.');
    return false;
  }

  if (postesSelectionnes.isEmpty) {
    _showError('Affecte au moins un SPHOT au sauveteur.');
    return false;
  }

  if (widget.docId == null && generatedLogin.isEmpty) {
    _showError('Génère l’accès avant d’enregistrer.');
    return false;
  }

  if (widget.docId == null && generatedPassword.isEmpty) {
    _showError(
      'Le mot de passe temporaire doit être généré avant enregistrement.',
    );
    return false;
  }

  return true;
}

Future<void> _saveSauveteur() async {
  final nom = nomController.text.trim();
  final prenom = prenomController.text.trim();

  if (!_validateSauveteurBeforeSave()) return;

  final sauveteursRef = FirebaseFirestore.instance
      .collection('territoires')
      .doc(widget.territoireId)
      .collection('sauveteurs');

  final docRef = widget.docId == null
    ? sauveteursRef.doc(createdSauveteurDocId)
    : sauveteursRef.doc(widget.docId);

createdSauveteurDocId ??= docRef.id;

  final baseLogin = _normalizeLogin(
  '${prenom.trim().isNotEmpty ? prenom.trim()[0] : ''}$nom',
);

final loginToSave = widget.docId == null
    ? (generatedLogin.isNotEmpty
        ? generatedLogin
        : await _generateUniqueLogin(baseLogin))
    : (widget.data?['login'] ?? '').toString();

final sauveteurData = {
  'nom': nom.toUpperCase(),
  'prenom': prenom,
  'role': 'SAUVETEUR',
  'accountStatus': 'ACTIVE',
  'accessInheritedStatus': 'ACTIVE',
  'authUid': '',
  'login': loginToSave,
  'temporaryPassword': widget.docId == null
    ? generatedPassword
    : (widget.data?['temporaryPassword'] ?? '').toString(),
  'mustChangePassword': true,
  'createdByAdmin': true,
    'dateNaissance': dateNaissanceController.text.trim(),
    'age': ageController.text.trim(),
    'adresse': adresseController.text.trim(),
    'codePostal': codePostalController.text.trim(),
    'ville': villeController.text.trim().toUpperCase(),
    'telephone': telephoneController.text.trim(),
    'email': emailController.text.trim(),
    'fonctions': fonctionsSelectionnees,
    'postesAffectes': postesSelectionnes,
    'experience': experienceController.text.trim(),
    'observations': observationsController.text.trim(),
    'territoireId': widget.territoireId,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  if (widget.docId == null) {
    sauveteurData['createdAt'] = FieldValue.serverTimestamp();
  }

  await docRef.set(sauveteurData, SetOptions(merge: true));

  if (loginToSave.isNotEmpty) {
  await _upsertSauveteurAccount(
    login: loginToSave,
    temporaryPassword:
        sauveteurData['temporaryPassword'].toString(),
    accountStatus: 'ACTIVE',
    sauveteurId: docRef.id,
    nom: nom.toUpperCase(),
    prenom: prenom,
    email: emailController.text.trim(),
  );
}

 final anciensPostesAffectes =
    (widget.data?['postesAffectes'] as List?)
            ?.map((e) => e.toString())
            .toSet() ??
        <String>{};

final nouveauxPostesAffectes = postesSelectionnes.toSet();

final postesARetirer =
    anciensPostesAffectes.difference(nouveauxPostesAffectes);

for (final posteId in postesARetirer) {
  await FirebaseFirestore.instance
      .collection('territoires')
      .doc(widget.territoireId)
      .collection('spots')
      .doc(posteId)
      .collection('sauveteursAffectes')
      .doc(docRef.id)
      .delete();
}

for (final posteId in nouveauxPostesAffectes) {
  await FirebaseFirestore.instance
      .collection('territoires')
      .doc(widget.territoireId)
      .collection('spots')
      .doc(posteId)
      .collection('sauveteursAffectes')
      .doc(docRef.id)
      .set({
    'sauveteurId': docRef.id,
    'nom': nom.toUpperCase(),
    'prenom': prenom,
    'fonctions': fonctionsSelectionnees,
    'postesAffectes': postesSelectionnes,
    'territoireId': widget.territoireId,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

  if (!mounted) return;

setState(() {
  sauveteurEnregistre = true;
});

await Future.delayed(const Duration(seconds: 1));

if (!mounted) return;

Navigator.of(context).pop();
}

void _showError(String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
      backgroundColor: const Color(0xFFDC2626),
    ),
  );
}

bool _validateContactBeforeAccess() {
  if (telephoneController.text.trim().isEmpty) {
    _showError('Le téléphone du sauveteur est obligatoire avant de générer l’accès.');
    return false;
  }

  if (emailController.text.trim().isEmpty) {
    _showError('L’adresse email du sauveteur est obligatoire avant de générer l’accès.');
    return false;
  }

  if (!emailController.text.trim().contains('@')) {
    _showError('L’adresse email du sauveteur n’est pas valide.');
    return false;
  }

  return true;
}

@override
Widget build(BuildContext context) {

  final contactOk = telephoneController.text.trim().isNotEmpty &&
    emailController.text.trim().isNotEmpty &&
    emailController.text.trim().contains('@');

    final canSaveSauveteur =
    widget.docId != null || (accesGenere && emailEnvoye);

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
                Text(
                  widget.docId != null
                      ? 'MODIFICATION D’UN SAUVETEUR'
                      : 'CRÉATION D’UN SAUVETEUR',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
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
                          _field(
                            'Prénom',
                            controller: prenomController,
                            capitalizeWords: true,
                          ),
                          const SizedBox(height: 8),
                          _dateField(
                            'Date de naissance',
                            controller: dateNaissanceController,
                          ),
                          const SizedBox(height: 8),
                          TextField(
  controller: ageController,
  readOnly: true,
  enableInteractiveSelection: false,
  style: const TextStyle(
    color: Color(0xFF1E3A8A),
    fontWeight: FontWeight.w700,
  ),
  decoration: InputDecoration(
    labelText: 'Âge',
    labelStyle: const TextStyle(
      color: Color(0xFF1E3A8A),
      fontWeight: FontWeight.w700,
    ),
    filled: true,
    fillColor: Colors.transparent,
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
),
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
                          _field(
  'Téléphone',
  controller: telephoneController,
  keyboardType: TextInputType.phone,
  inputFormatters: [
    FilteringTextInputFormatter.digitsOnly,
    PhoneNumberFormatter(),
  ],
),
                          const SizedBox(height: 8),
                          _field('Email', controller: emailController),
                          const SizedBox(height: 8),
                          _dropdownFonction(),
                          const SizedBox(height: 8),
                          _field(
                            'Années d’expérience',
                            controller: experienceController,
                          ),
                          const SizedBox(height: 8),
                          _multiPostesSecoursField(),
                          const SizedBox(height: 8),

                          _field(
  'Observations',
  controller: observationsController,
  maxLines: 4,
  capitalizeWords: true,
),

const SizedBox(height: 8),

if (widget.docId != null)
  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(
        color: const Color(0xFF1E3A8A),
        width: 1.6,
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Identifiant : ${(widget.data?['login'] ?? '').toString().isEmpty ? 'non généré' : (widget.data?['login'] ?? '').toString()}',
          style: const TextStyle(
            color: Color(0xFF1E3A8A),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Mot de passe : ${(widget.data?['temporaryPassword'] ?? '').toString().isEmpty ? 'non généré' : (widget.data?['temporaryPassword'] ?? '').toString()}',
          style: const TextStyle(
            color: Color(0xFF1E3A8A),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  ),

const SizedBox(height: 8),

if (widget.docId == null) ...[

                          

                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _generateAccess,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accesGenere
                                    ? const Color(0xFFDC2626)
                                    : Colors.transparent,
                                elevation: 0,
                                side: const BorderSide(
                                  color: Color(0xFFDC2626),
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                accesGenere
                                    ? 'ACCÈS GÉNÉRÉ'
                                    : 'GÉNÉRER L\'ACCÈS',
                                style: TextStyle(
                                  color: accesGenere
                                      ? const Color(0xFFFFFFFF)
                                      : const Color(0xFFDC2626),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFF1E3A8A),
                                width: 1.6,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Identifiant : ${generatedLogin.isEmpty ? 'non généré' : generatedLogin}',
                                  style: const TextStyle(
                                    color: Color(0xFF1E3A8A),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Mot de passe : ${generatedPassword.isEmpty ? 'non généré' : generatedPassword}',
                                  style: const TextStyle(
                                    color: Color(0xFF1E3A8A),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),
                          SizedBox(
  width: double.infinity,
  height: 42,
  child: ElevatedButton(
    onPressed: accesGenere && contactOk
        ? () async {
            if (emailEnvoye) return;
            await _sendCredentialsEmail();
          }
        : null,
    style: ElevatedButton.styleFrom(
      backgroundColor: emailEnvoye
          ? const Color(0xFFDC2626)
          : Colors.transparent,
      foregroundColor: emailEnvoye
          ? Colors.white
          : const Color(0xFFDC2626),
      disabledBackgroundColor: Colors.transparent,
      disabledForegroundColor: const Color(0xFFDC2626),
      elevation: 0,
      side: const BorderSide(
        color: Color(0xFFDC2626),
        width: 2,
      ),
    ),
    child: Text(
      emailEnvoye ? 'EMAIL ENVOYÉ' : 'ENVOYER PAR EMAIL',
      style: const TextStyle(
        fontWeight: FontWeight.w900,
      ),
    ),
  ),
),


],

                    


                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: canSaveSauveteur ? _saveSauveteur : null,
                              icon: Icon(
                                Icons.save,
                                color: sauveteurEnregistre
                                    ? const Color(0xFFFFFFFF)
                                    : const Color(0xFFDC2626),
                              ),
                              label: Text(
                                sauveteurEnregistre
                                    ? 'ENREGISTRÉ'
                                    : 'ENREGISTRER',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: sauveteurEnregistre
                                      ? const Color(0xFFFFFFFF)
                                      : const Color(0xFFDC2626),
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: sauveteurEnregistre
                                    ? const Color(0xFFDC2626)
                                    : Colors.transparent,
                                foregroundColor: sauveteurEnregistre
                                    ? const Color(0xFFFFFFFF)
                                    : const Color(0xFFDC2626),
                                elevation: 0,
                                side: const BorderSide(
                                  color: Color(0xFFDC2626),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

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

Widget _dropdownPostes(List<Map<String, String>> choices) {
  final fieldKey = GlobalKey();

  void closeMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
  }

  void openMenu() {
    closeMenu();

    final renderBox =
        fieldKey.currentContext!.findRenderObject()
            as RenderBox;

    final position =
        renderBox.localToGlobal(Offset.zero);

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
                    child: Container(
                      color: Colors.transparent,
                    ),
                  ),
                ),
                Positioned(
                  left: position.dx,
                  top: position.dy + size.height - 10,
                  width: size.width,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints:
                          const BoxConstraints(
                        maxHeight: 180,
                      ),
                      decoration: BoxDecoration(
                        color:
                            Colors.white.withOpacity(0.88),
                        border: const Border(
                          left: BorderSide(
                            color: Color(0xFF1E3A8A),
                            width: 1.4,
                          ),
                          right: BorderSide(
                            color: Color(0xFF1E3A8A),
                            width: 1.4,
                          ),
                          bottom: BorderSide(
                            color: Color(0xFF1E3A8A),
                            width: 1.4,
                          ),
                        ),
                        borderRadius:
                            const BorderRadius.only(
                          bottomLeft:
                              Radius.circular(10),
                          bottomRight:
                              Radius.circular(10),
                        ),
                      ),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: choices.length,
                        itemBuilder:
                            (context, index) {
                          final choice = choices[index];

final id = choice['id'] ?? '';
final label = choice['label'] ?? '';

final selected =
    postesSelectionnes.contains(id);

                          return InkWell(
                            onTap: () {
                              setState(() {
                                if (selected) {
                                  postesSelectionnes.remove(id);
                                } else {
                                  postesSelectionnes.add(id);
                                }
                              });

                              overlaySetState(() {});
                            },
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons
                                            .check_box_rounded
                                        : Icons
                                            .check_box_outline_blank_rounded,
                                    color: selected
                                        ? adminColor
                                        : const Color(
                                            0xFF1E3A8A),
                                    size: 22,
                                  ),
                                  const SizedBox(
                                      width: 8),
                                  Expanded(
                                    child: Text(
                                      label,
                                      style:
                                          const TextStyle(
                                        fontSize: 13,
                                        fontWeight:
                                            FontWeight.w800,
                                        color: Color(
                                            0xFF1E3A8A),
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
        labelText:
            postesSelectionnes.isEmpty
                ? null
                : 'SPHOT(S) affecté(s)',
        labelStyle: const TextStyle(
          color: Color(0xFF1E3A8A),
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: Colors.transparent,
        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: Color(0xFF1E3A8A),
            width: 1.6,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: Color(0xFF1E3A8A),
            width: 2,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(14),
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
    postesSelectionnes.isEmpty
        ? 'SPHOT(S) affecté(s)'
        : choices
            .where((choice) =>
                postesSelectionnes.contains(choice['id']))
            .map((choice) => choice['label'] ?? '')
            .where((label) => label.trim().isNotEmpty)
            .join('\n'),
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: Color(0xFF1E3A8A),
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
        return const SizedBox();
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

      final postes = docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;

        final idSphot = (data['idSphot'] ?? doc.id).toString();
        final nomSecours = (data['nomSecours'] ?? '').toString();
        final nomSphot = (data['nomSphot'] ?? '').toString();

        final label = [
          'SPHOT $idSphot',
          nomSecours,
          nomSphot,
        ].where((value) => value.trim().isNotEmpty).join(' - ');

        return {
          'id': doc.id,
          'label': label.isEmpty ? doc.id : label,
        };
      }).toList();

      return _dropdownPostes(postes);
    },
  );
}

void _updateAgeFromBirthDate() {
  final text = dateNaissanceController.text.trim();

  final parts = text.split('/');

  if (parts.length != 3) {
    ageController.clear();
    return;
  }

  final day = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final year = int.tryParse(parts[2]);

  if (day == null || month == null || year == null) {
    ageController.clear();
    return;
  }

  final birthDate = DateTime(year, month, day);
  final today = DateTime.now();

  int age = today.year - birthDate.year;

  if (today.month < birthDate.month ||
      (today.month == birthDate.month &&
       today.day < birthDate.day)) {
    age--;
  }

  ageController.text = age.toString();
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
              _updateAgeFromBirthDate();
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
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
}) {
  
  return TextField(
  controller: controller,
  keyboardType: keyboardType,
  inputFormatters: inputFormatters,

  onChanged: (value) {
    if (uppercase) {
      final newValue = value.toUpperCase();

      if (newValue != value) {
        controller.value = TextEditingValue(
          text: newValue,
          selection: TextSelection.collapsed(
            offset: newValue.length,
          ),
        );
      }
    }

    if (capitalizeWords && value.isNotEmpty) {
      final newValue =
          value[0].toUpperCase() + value.substring(1);

      if (newValue != value) {
        controller.value = TextEditingValue(
          text: newValue,
          selection: TextSelection.collapsed(
            offset: newValue.length,
          ),
        );
      }
    }
   setState(() {}); 
  },

  textCapitalization: uppercase
      ? TextCapitalization.characters
      : TextCapitalization.sentences,

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

class PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digits.length > 10) {
      digits = digits.substring(0, 10);
    }

    final buffer = StringBuffer();

    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && i % 2 == 0) {
        buffer.write(' ');
      }

      buffer.write(digits[i]);
    }

    final formatted = buffer.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}