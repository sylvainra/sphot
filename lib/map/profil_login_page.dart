import 'package:flutter/material.dart';

import '../pages/sauveteur/sauveteur_menu_page.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../pages/admin/admin_espace_page.dart';
import '../pages/admin/admin_registration_page.dart';

import '../services/proconnect_service.dart';

class ProfilLoginPage extends StatefulWidget {
  const ProfilLoginPage({super.key});

  @override
  State<ProfilLoginPage> createState() => _ProfilLoginPageState();
}

class _ProfilLoginPageState extends State<ProfilLoginPage>
    with WidgetsBindingObserver {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _idFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _isEditing = false;
  bool _showPassword = false;

  final Map<String, Map<String, String>> sauveteurAccounts = {
    'chef': {
      'password': '1234',
      'role': 'Chef de poste',
    },
    'adjoint': {
      'password': '1234',
      'role': 'Adjoint chef de poste',
    },
    'sauveteur1': {
      'password': '1234',
      'role': 'Sauveteur',
    },
    'sauveteur2': {
      'password': '1234',
      'role': 'Sauveteur',
    },
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();

    final bottomInset =
        WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom;

    if (bottomInset == 0 && _isEditing) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (!mounted) return;

        FocusScope.of(context).unfocus();

        setState(() {
          _isEditing = false;
        });
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _idController.dispose();
    _passwordController.dispose();
    _idFocusNode.dispose();
    _passwordFocusNode.dispose();

    super.dispose();
  }

  Future<void> _loginSauveteur() async {
  final id = _idController.text.trim().toLowerCase();
  final password = _passwordController.text.trim();

  if (id.isEmpty || password.isEmpty) {
    _showLoginError();
    return;
  }

  try {
    const territoireId = 'longeville_sur_mer';

    final snapshot = await FirebaseFirestore.instance
        .collection('territoires')
        .doc(territoireId)
        .collection('sauveteurs')
        .where('login', isEqualTo: id)
        .where('temporaryPassword', isEqualTo: password)
        .where('accountStatus', isEqualTo: 'ACTIVE')
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      _showLoginError();
      return;
    }

    final data = snapshot.docs.first.data();

    final fonctions = data['fonctions'];
    String userRole = 'Sauveteur';

    if (fonctions is Iterable && fonctions.isNotEmpty) {
      userRole = fonctions.first.toString();
    } else if ((data['role'] ?? '').toString().trim().isNotEmpty) {
      userRole = data['role'].toString();
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SauveteurMenuPage(
          profileColor: const Color(0xFFFF0000),
          userRole: userRole,
        ),
      ),
    );
  } catch (error) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erreur connexion sauveteur : $error'),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

  Future<void> _loginWithProConnect() async {
  if (!mounted) return;

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const AdminEspacePage(),
    ),
  );
}

  void _showLoginError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Identifiant ou mot de passe incorrect'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _activateEditingMode() {
    if (!_isEditing) {
      setState(() => _isEditing = true);
    }
  }

  void _closeKeyboard() {
    FocusScope.of(context).unfocus();
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    const Color sauveteurColor = Color(0xFFEF4444);
    const Color adminColor = Color(0xFF1E3A8A);

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onTap: _closeKeyboard,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'data/images/map_background.jpg',
              fit: BoxFit.cover,
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Column(
                  children: [
                    Image.asset(
                      'data/icons/title.png',
                      height: 64,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),

                    const SizedBox(height: 12),

                    Visibility(
                      visible: !_isEditing,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: const Text(
                        'CONNEXION',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFFF0000),
                          letterSpacing: 1,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      transform: Matrix4.translationValues(
                        0,
                        _isEditing ? -150 : 0,
                        0,
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: sauveteurColor,
                                width: 2.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'ACCÈS SAUVETEUR',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: sauveteurColor,
                                  ),
                                ),

                                const SizedBox(height: 18),

                                TextField(
                                  controller: _idController,
                                  focusNode: _idFocusNode,
                                  textInputAction: TextInputAction.next,
                                  onTap: _activateEditingMode,
                                  onSubmitted: (_) {
                                    FocusScope.of(context)
                                        .requestFocus(_passwordFocusNode);
                                  },
                                  style: const TextStyle(
                                    color: sauveteurColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Identifiant',
                                    hintStyle: const TextStyle(
                                      color: sauveteurColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.08),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 16,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: sauveteurColor,
                                        width: 2,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: sauveteurColor,
                                        width: 2,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: sauveteurColor,
                                        width: 2.4,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 14),

                                TextField(
                                  controller: _passwordController,
                                  focusNode: _passwordFocusNode,
                                  obscureText: !_showPassword,
                                  textInputAction: TextInputAction.done,
                                  onTap: _activateEditingMode,
                                  onSubmitted: (_) => _loginSauveteur(),
                                  style: const TextStyle(
                                    color: sauveteurColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Mot de passe',
                                    hintStyle: const TextStyle(
                                      color: sauveteurColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _showPassword
                                            ? Icons.visibility_off_rounded
                                            : Icons.visibility_rounded,
                                        color: sauveteurColor,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _showPassword = !_showPassword;
                                        });
                                      },
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.08),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 16,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: sauveteurColor,
                                        width: 2,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: sauveteurColor,
                                        width: 2,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: sauveteurColor,
                                        width: 2.4,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 22),

                                SizedBox(
                                  width: double.infinity,
                                  height: 54,
                                  child: ElevatedButton(
                                    onPressed: _loginSauveteur,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: sauveteurColor,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                        side: const BorderSide(
                                          color: sauveteurColor,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    child: const Text(
                                      'SE CONNECTER',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: adminColor,
                                width: 2.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'ADMIN',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: adminColor,
                                  ),
                                ),

                                const SizedBox(height: 14),

                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: OutlinedButton(
                                    onPressed: _loginWithProConnect,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: adminColor,
                                      side: const BorderSide(
                                        color: adminColor,
                                        width: 2,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: const Text(
                                      'SE CONNECTER AVEC PROCONNECT',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    if (!_isEditing)
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),

                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}