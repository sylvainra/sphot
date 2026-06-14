import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

class AdminProfileButton extends StatefulWidget {
  const AdminProfileButton({super.key});

  @override
  State<AdminProfileButton> createState() => _AdminProfileButtonState();
}

class _AdminProfileButtonState extends State<AdminProfileButton> {
  static const Color adminColor = Color(0xFF1E3A8A);
  static const Color redColor = Color(0xFFDC2626);

  String ville = 'VILLE_NON_RENSEIGNEE';
  String territoireId = '';

  String nomStructure = '';
  String typeStructure = '';
  String nomResponsable = '';
  String prenomResponsable = '';
  String fonctionResponsable = '';
  String telephoneResponsable = '';
  String emailResponsable = '';

  bool identitySaved = false;

  final Map<String, TextEditingController> identityControllers = {};

  TextEditingController _identityController(String key, String value) {
    identityControllers.putIfAbsent(
      key,
      () => TextEditingController(text: value),
    );
    return identityControllers[key]!;
  }

  @override
  void initState() {
    super.initState();
    _loadAdmin();
  }

  @override
  void dispose() {
    for (final controller in identityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final adminDoc = await FirebaseFirestore.instance
        .collection('admins')
        .doc(user.uid)
        .get();

    if (!adminDoc.exists) return;

    final adminData = adminDoc.data() ?? {};
    final loadedTerritoireId =
        (adminData['territoireId'] ?? '').toString();

    String loadedVille = 'VILLE_NON_RENSEIGNEE';

    if (loadedTerritoireId.isNotEmpty) {
      final territoireDoc = await FirebaseFirestore.instance
          .collection('territoires')
          .doc(loadedTerritoireId)
          .get();

      if (territoireDoc.exists) {
        loadedVille =
            (territoireDoc.data()?['ville'] ?? 'VILLE_NON_RENSEIGNEE')
                .toString();
      }
    }

    if (!mounted) return;

    setState(() {
      territoireId = loadedTerritoireId;
      ville = loadedVille;
      nomStructure = (adminData['nomStructure'] ?? '').toString();
      typeStructure = (adminData['typeStructure'] ?? '').toString();
      nomResponsable = (adminData['nomResponsable'] ?? '').toString();
      prenomResponsable = (adminData['prenomResponsable'] ?? '').toString();
      fonctionResponsable =
          (adminData['fonctionResponsable'] ?? '').toString();
      telephoneResponsable =
          (adminData['telephoneResponsable'] ?? '').toString();
      emailResponsable =
          (adminData['emailResponsable'] ?? adminData['email'] ?? '')
              .toString();
    });
  }

  void _openAdminProfile(BuildContext context) {
    bool identityOpen = false;
    bool securityOpen = false;
    bool logoutHover = false;

    _identityController('nomStructure', nomStructure).text = nomStructure;
    _identityController('typeStructure', typeStructure).text = typeStructure;
    _identityController('prenomResponsable', prenomResponsable).text =
        prenomResponsable;
    _identityController('nomResponsable', nomResponsable).text =
        nomResponsable;
    _identityController('fonctionResponsable', fonctionResponsable).text =
        fonctionResponsable;
    _identityController('telephoneResponsable', telephoneResponsable).text =
        telephoneResponsable;
    _identityController('emailResponsable', emailResponsable).text =
        emailResponsable;

    identitySaved = false;

    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, menuSetState) {
            return Align(
              alignment: Alignment.topRight,
              child: Container(
                width: 330,
                margin: const EdgeInsets.only(top: 90, right: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: adminColor, width: 2),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.account_circle_rounded,
                          color: adminColor,
                          size: 52,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'PROFIL ADMIN',
                          style: TextStyle(
                            color: adminColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 12),

                        _profileDropdownHeader(
                          icon: Icons.badge_rounded,
                          title: 'IDENTITÉ',
                          open: identityOpen,
                          onTap: () {
                            menuSetState(() {
                              identityOpen = !identityOpen;
                              securityOpen = false;
                            });
                          },
                        ),

                        if (identityOpen) ...[
                          _identityEditField('nomStructure', 'Structure'),
                          _identityEditField(
                            'typeStructure',
                            'Type structure',
                          ),
                          _identityEditField(
                            'prenomResponsable',
                            'Prénom responsable',
                          ),
                          _identityEditField(
                            'nomResponsable',
                            'Nom responsable',
                          ),
                          _identityEditField(
                            'fonctionResponsable',
                            'Fonction',
                          ),
                          _identityEditField(
                            'telephoneResponsable',
                            'Téléphone',
                          ),
                          _identityEditField(
                            'emailResponsable',
                            'Email',
                          ),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: OutlinedButton(
                              onPressed: () async {
                                await _saveIdentityAdmin();
                                menuSetState(() {
                                  identitySaved = true;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                backgroundColor:
                                    identitySaved ? redColor : Colors.white,
                                side: const BorderSide(
                                  color: redColor,
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                identitySaved
                                    ? 'IDENTITÉ ENREGISTRÉE'
                                    : 'ENREGISTRER IDENTITÉ',
                                style: TextStyle(
                                  color:
                                      identitySaved ? Colors.white : redColor,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        _profileDropdownHeader(
                          icon: Icons.lock_rounded,
                          title: 'SÉCURITÉ',
                          open: securityOpen,
                          onTap: () {
                            menuSetState(() {
                              securityOpen = !securityOpen;
                              identityOpen = false;
                            });
                          },
                        ),

                        if (securityOpen) ...[
                          _profileActionLine(
                            Icons.password_rounded,
                            'Réinitialiser le mot de passe',
                            _sendPasswordResetEmail,
                          ),
                          _profileActionLine(
                            Icons.pause_circle_rounded,
                            'Suspendre le compte',
                            _suspendAdminAccount,
                          ),
                          _profileActionLine(
                            Icons.delete_forever_rounded,
                            'Supprimer le compte',
                            _deleteAdminAccount,
                          ),
                        ],

                        _profileSimpleLine(
                          Icons.settings_rounded,
                          'PARAMÈTRES',
                        ),
                        _profileSimpleLine(
                          Icons.notifications_rounded,
                          'NOTIFICATIONS',
                        ),
                        _profileSimpleLine(
                          Icons.help_rounded,
                          'AIDE',
                        ),

                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          height: 1,
                          color: adminColor,
                        ),
                        const SizedBox(height: 8),

                        MouseRegion(
                          onEnter: (_) {
                            menuSetState(() {
                              logoutHover = true;
                            });
                          },
                          onExit: (_) {
                            menuSetState(() {
                              logoutHover = false;
                            });
                          },
                          child: GestureDetector(
                            onTapDown: (_) {
                              menuSetState(() {
                                logoutHover = true;
                              });
                            },
                            onTapCancel: () {
                              menuSetState(() {
                                logoutHover = false;
                              });
                            },
                            onTap: () async {
                              await FirebaseAuth.instance.signOut();

                              if (!mounted) return;

                              Navigator.of(
                                context,
                                rootNavigator: true,
                              ).pop();
                              Navigator.of(context).pop();
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    logoutHover ? redColor : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: redColor,
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'DÉCONNEXION',
                                  style: TextStyle(
                                    color:
                                        logoutHover ? Colors.white : redColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _profileDropdownHeader({
    required IconData icon,
    required String title,
    required bool open,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: adminColor, width: 1.4),
        ),
        child: Row(
          children: [
            Icon(icon, color: adminColor, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: adminColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Icon(
              open
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: redColor,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileSimpleLine(IconData icon, String title) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: adminColor, width: 1.4),
      ),
      child: Row(
        children: [
          Icon(icon, color: adminColor, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: adminColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileActionLine(
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: redColor, width: 1.4),
        ),
        child: Row(
          children: [
            Icon(icon, color: redColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: redColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _identityEditField(String key, String label) {
  final bool forceUpperCase =
      key == 'nomStructure' ||
      key == 'typeStructure' ||
      key == 'nomResponsable';

  final bool capitalizeFirst =
      key == 'prenomResponsable' ||
      key == 'fonctionResponsable';

  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: identityControllers[key],
      textCapitalization: forceUpperCase
          ? TextCapitalization.characters
          : TextCapitalization.words,
      inputFormatters: [
        TextInputFormatter.withFunction((oldValue, newValue) {
          if (forceUpperCase) {
            return TextEditingValue(
              text: newValue.text.toUpperCase(),
              selection: newValue.selection,
            );
          }

          if (capitalizeFirst) {
            final text = newValue.text;

            if (text.isEmpty) {
              return newValue;
            }

            final formatted =
                text[0].toUpperCase() +
                (text.length > 1 ? text.substring(1).toLowerCase() : '');

            return TextEditingValue(
              text: formatted,
              selection: TextSelection.collapsed(
                offset: formatted.length,
              ),
            );
          }

          return newValue;
        }),
      ],
      style: const TextStyle(
        color: adminColor,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: adminColor,
          fontWeight: FontWeight.w700,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: adminColor,
            width: 1.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: adminColor,
            width: 1.5,
          ),
        ),
      ),
    ),
  );
}

  Future<void> _saveIdentityAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final data = {
      'uid': user.uid,
      'nomStructure':
          identityControllers['nomStructure']?.text.trim() ?? '',
      'typeStructure':
          identityControllers['typeStructure']?.text.trim() ?? '',
      'prenomResponsable':
          identityControllers['prenomResponsable']?.text.trim() ?? '',
      'nomResponsable':
          identityControllers['nomResponsable']?.text.trim() ?? '',
      'fonctionResponsable':
          identityControllers['fonctionResponsable']?.text.trim() ?? '',
      'telephoneResponsable':
          identityControllers['telephoneResponsable']?.text.trim() ?? '',
      'emailResponsable':
          identityControllers['emailResponsable']?.text.trim() ?? '',
      'email': user.email ?? emailResponsable,
      'territoireId': territoireId,
      'role': 'ADMIN',
      'accountStatus': 'ACTIVE',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection('admins')
        .doc(user.uid)
        .set(data, SetOptions(merge: true));

    if (territoireId.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('territoires')
          .doc(territoireId)
          .collection('admins')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));
    }

    if (!mounted) return;

    setState(() {
      nomStructure = data['nomStructure'].toString();
      typeStructure = data['typeStructure'].toString();
      prenomResponsable = data['prenomResponsable'].toString();
      nomResponsable = data['nomResponsable'].toString();
      fonctionResponsable = data['fonctionResponsable'].toString();
      telephoneResponsable = data['telephoneResponsable'].toString();
      emailResponsable = data['emailResponsable'].toString();
      identitySaved = true;
    });
  }

  Future<void> _sendPasswordResetEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;

    if (email == null || email.isEmpty) return;

    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  Future<void> _suspendAdminAccount() async {
    await _updateAdminStatus('SUSPENDED');
  }

  Future<void> _deleteAdminAccount() async {
    await _updateAdminStatus('DELETED');
  }

  Future<void> _updateAdminStatus(String status) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final data = {
      'accountStatus': status,
      'updatedAt': FieldValue.serverTimestamp(),
      if (status == 'SUSPENDED') 'suspendedAt': FieldValue.serverTimestamp(),
      if (status == 'DELETED') 'deletedAt': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection('admins')
        .doc(user.uid)
        .set(data, SetOptions(merge: true));

    if (territoireId.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('territoires')
          .doc(territoireId)
          .collection('admins')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));
    }

    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pop();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: () => _openAdminProfile(context),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: adminColor,
            width: 2,
          ),
        ),
        child: const Icon(
          Icons.person,
          color: adminColor,
          size: 24,
        ),
      ),
    );
  }
}