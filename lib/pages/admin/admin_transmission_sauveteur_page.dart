import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_profile_button.dart';

import 'dart:math';

class AdminTransmissionSauveteurPage extends StatefulWidget {
  final String territoireId;
  final String ville;

  const AdminTransmissionSauveteurPage({
    super.key,
    required this.territoireId,
    required this.ville,
  });

  @override
  State<AdminTransmissionSauveteurPage> createState() =>
      _AdminTransmissionSauveteurPageState();
}

class _AdminTransmissionSauveteurPageState
    extends State<AdminTransmissionSauveteurPage> {
  static const Color bleuRef = Color(0xFF1E3A8A);
  static const Color rougeRef = Color(0xFFDC2626);

  String? selectedSauveteurId;
  Map<String, dynamic>? selectedSauveteurData;

  String _normalizeText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâãäå]'), 'a')
      .replaceAll(RegExp(r'[ç]'), 'c')
      .replaceAll(RegExp(r'[èéêë]'), 'e')
      .replaceAll(RegExp(r'[ìíîï]'), 'i')
      .replaceAll(RegExp(r'[ñ]'), 'n')
      .replaceAll(RegExp(r'[òóôõö]'), 'o')
      .replaceAll(RegExp(r'[ùúûü]'), 'u')
      .replaceAll(RegExp(r'[ýÿ]'), 'y')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
}

String _generateLogin(String prenom, String nom) {
  final cleanPrenom = _normalizeText(prenom);
  final cleanNom = _normalizeText(nom);

  if (cleanPrenom.isEmpty || cleanNom.isEmpty) {
    return '';
  }

  return '${cleanPrenom[0]}$cleanNom';
}

String _generateTemporaryPassword() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  final length = 8 + random.nextInt(3);

  return List.generate(
    length,
    (_) => chars[random.nextInt(chars.length)],
  ).join();
}

Future<void> _generateAccess() async {
  if (selectedSauveteurId == null || selectedSauveteurData == null) return;

  final data = selectedSauveteurData!;
  final nom = (data['nom'] ?? '').toString();
  final prenom = (data['prenom'] ?? '').toString();
  

  final login = _generateLogin(prenom, nom);
  final temporaryPassword = _generateTemporaryPassword();

  if (login.isEmpty) return;

  await FirebaseFirestore.instance
      .collection('territoires')
      .doc(widget.territoireId)
      .collection('sauveteurs')
      .doc(selectedSauveteurId)
      .update({
    'login': login,
    'temporaryPassword': temporaryPassword,
    'passwordUpdatedAt': FieldValue.serverTimestamp(),
    'accessGeneratedAt': FieldValue.serverTimestamp(),
    'accountStatus': 'ACTIF',
  });

  setState(() {
    selectedSauveteurData = {
      ...selectedSauveteurData!,
      'login': login,
      'temporaryPassword': temporaryPassword,
      'accountStatus': 'ACTIF',
    };
  });

  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Accès générés : $login / $temporaryPassword'),
    ),
  );
}

OverlayEntry? _dropdownOverlay;  

@override
void dispose() {
  _dropdownOverlay?.remove();
  super.dispose();
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
                    'TRANSMISSION DES ACCÈS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: rougeRef,
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
                          color: bleuRef,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          SizedBox(
  height: 52,
  child: _sauveteurSelector(),
),
                          const SizedBox(height: 10),

                          if (selectedSauveteurData != null)
                            _selectedSauveteurCard(),

                          const SizedBox(height: 10),

                          _actionButton(
  'GÉNÉRER LES ACCÈS',
  Icons.key_rounded,
  onPressed: _generateAccess,
),
                          const SizedBox(height: 10),
                          _actionButton(
                            'RÉINITIALISER LE MOT DE PASSE',
                            Icons.password_rounded,
                          ),
                          const SizedBox(height: 10),
                          _actionButton(
                            'ENVOYER PAR EMAIL',
                            Icons.email_rounded,
                          ),
                          const SizedBox(height: 10),
                          _actionButton(
                            'ENVOYER PAR SMS',
                            Icons.sms_rounded,
                          ),

                          const SizedBox(height: 10),

                          _actionButton(
                            'SUSPENDRE LE COMPTE',
                            Icons.pause_circle_rounded,
                          ),
                          const SizedBox(height: 10),
                          _actionButton(
                            'SUPPRIMER LE COMPTE',
                            Icons.delete_forever_rounded,
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
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: bleuRef,
                        width: 2,
                      ),
                    ),
                    child: IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: bleuRef,
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

  Widget _sauveteurSelector() {
  final fieldKey = GlobalKey();

  void closeMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
  }

  return StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('territoires')
        .doc(widget.territoireId)
        .collection('sauveteurs')
        .snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const SizedBox(
          height: 56,
          child: Center(child: CircularProgressIndicator()),
        );
      }

      final docs = snapshot.data!.docs;

      docs.sort((a, b) {
        final dataA = a.data() as Map<String, dynamic>;
        final dataB = b.data() as Map<String, dynamic>;

        final nomA = (dataA['nom'] ?? '').toString().toUpperCase();
        final nomB = (dataB['nom'] ?? '').toString().toUpperCase();
        final prenomA = (dataA['prenom'] ?? '').toString().toUpperCase();
        final prenomB = (dataB['prenom'] ?? '').toString().toUpperCase();

        final compareNom = nomA.compareTo(nomB);
        if (compareNom != 0) return compareNom;

        return prenomA.compareTo(prenomB);
      });

      String displayLabel = 'CHOISIR UN SAUVETEUR';

      if (selectedSauveteurId != null) {
        final selectedDocs =
            docs.where((doc) => doc.id == selectedSauveteurId);

        if (selectedDocs.isNotEmpty) {
          final data = selectedDocs.first.data() as Map<String, dynamic>;
          final nom = (data['nom'] ?? '').toString();
          final prenom = (data['prenom'] ?? '').toString();
          
          
          displayLabel = '$nom $prenom'.trim().toUpperCase();
        }
      }

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
                      constraints: const BoxConstraints(maxHeight: 332),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
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
                          thumbColor:
                              MaterialStatePropertyAll(Color(0xFF1E3A8A)),
                          trackVisibility: MaterialStatePropertyAll(false),
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
                              final data =
                                  doc.data() as Map<String, dynamic>;

                              final nom = (data['nom'] ?? '').toString();
final prenom =
    (data['prenom'] ?? '').toString();

final login =
    (data['login'] ?? 'non généré').toString();

final password =
    (data['temporaryPassword'] ?? 'non généré').toString();

final status =
    (data['accountStatus'] ?? 'ACTIF').toString();

final title =
    '$nom $prenom'.trim().toUpperCase();

                              final selected =
                                  doc.id == selectedSauveteurId;

                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    selectedSauveteurId = doc.id;
                                    selectedSauveteurData = data;
                                  });
                                  closeMenu();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        selected
                                            ? Icons.check_circle_rounded
                                            : Icons.person_rounded,
                                        color: const Color(0xFFDC2626),
                                        size: 22,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title.isEmpty ? doc.id : title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: Color(0xFF1E3A8A),
        ),
      ),
      const SizedBox(height: 2),
      Text(
        'ID : $login',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1E3A8A),
        ),
      ),
      Text(
        'MDP : $password',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1E3A8A),
        ),
      ),
      Text(
        'STATUT : $status',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1E3A8A),
        ),
      ),
    ],
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
                  displayLabel,
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
                color: Color(0xFFDC2626),
                size: 26,
              ),
            ],
          ),
        ),
      );
    },
  );
}

  Widget _selectedSauveteurCard() {
  final data = selectedSauveteurData ?? {};

  final nom = (data['nom'] ?? '').toString();
  final prenom = (data['prenom'] ?? '').toString();

  final login = (data['login'] ?? '').toString();
  final temporaryPassword =
      (data['temporaryPassword'] ?? '').toString();
  final status =
      (data['accountStatus'] ?? 'ACTIF').toString();

  return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: bleuRef,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            '$nom $prenom'.trim().toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: rougeRef,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            login.isEmpty ? 'Identifiant : non généré' : 'Identifiant : $login',
            style: const TextStyle(
              color: bleuRef,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
Text(
  temporaryPassword.isEmpty
      ? 'Mot de passe : non généré'
      : 'Mot de passe : $temporaryPassword',
  style: const TextStyle(
    color: bleuRef,
    fontSize: 12,
    fontWeight: FontWeight.w800,
  ),
),
          const SizedBox(height: 2),
          Text(
            'Statut : $status',
            style: const TextStyle(
              color: bleuRef,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBox(String text) {
    return Container(
      width: double.infinity,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: bleuRef,
          width: 2,
        ),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: bleuRef,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _actionButton(
  String title,
  IconData icon, {
  VoidCallback? onPressed,
}) {
    final bool enabled = selectedSauveteurId != null;

    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(
          icon,
          color: enabled ? rougeRef : Colors.grey,
        ),
        label: Text(
          title,
          style: TextStyle(
            color: enabled ? bleuRef : Colors.grey,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: enabled ? bleuRef : Colors.grey,
            width: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}