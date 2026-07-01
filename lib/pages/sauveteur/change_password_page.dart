import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'sauveteur_menu_page.dart';

class ChangePasswordPage extends StatefulWidget {
  final String login;
  final String territoireId;
  final String userRole;

  const ChangePasswordPage({
    super.key,
    required this.login,
    required this.territoireId,
    required this.userRole,
  });

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _showPassword = false;
  String? _message;

  bool _validatePassword() {
  final password = _newPasswordController.text.trim();
  final confirm = _confirmPasswordController.text.trim();

  if (password != confirm) {
    setState(() {
      _message = "Les mots de passe sont différents.";
    });
    return false;
  }

  final regex = RegExp(
    r'^(?=.*[A-Z])(?=.*[0-9])(?=.*[!@#?*\-]).{8,}$',
  );

  if (!regex.hasMatch(password)) {
    setState(() {
      _message =
          "8 caractères mini, 1 majuscule, 1 chiffre, 1 caractère : ! @ # ? * -";
    });
    return false;
  }

  setState(() {
    _message = null;
  });

  return true;
}

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color sauveteurColor = Color(0xFFEF4444);

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
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Column(
                children: [
                  Image.asset(
                    'data/icons/title.png',
                    height: 64,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(height: 18),
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
                          'MODIFIER VOTRE MOT DE PASSE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: sauveteurColor,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Pour sécuriser votre compte, vous devez choisir un nouveau mot de passe avant d’accéder à SPHOT.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: sauveteurColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 22),
                        TextField(
                          controller: _newPasswordController,
                          obscureText: !_showPassword,
                          style: const TextStyle(
                            color: sauveteurColor,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: _inputDecoration(
                            label: 'Nouveau mot de passe',
                            showPasswordButton: true,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _confirmPasswordController,
                          obscureText: !_showPassword,
                          style: const TextStyle(
                            color: sauveteurColor,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: _inputDecoration(
                            label: 'Confirmer le mot de passe',
                            showPasswordButton: true,
                          ),
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: () async {
  if (!_validatePassword()) return;

  final uri = Uri.parse(
    'https://us-central1-sphot-ab80b.cloudfunctions.net/changeSauveteurPassword',
  );

  final response = await http.post(
    uri,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'login': widget.login,
      'newPassword': _newPasswordController.text.trim(),
    }),
  );

debugPrint('Status = ${response.statusCode}');
debugPrint('Body = ${response.body}');

  if (response.statusCode < 200 || response.statusCode >= 300) {
    setState(() {
      _message = 'Modification impossible. Réessayez.';
    });
    return;
  }

await http.post(
  Uri.parse(
    'https://us-central1-sphot-ab80b.cloudfunctions.net/sendSauveteurPasswordChangedEmail',
  ),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'login': widget.login,
    'territoireId': widget.territoireId,
  }),
);

  if (!mounted) return;

  Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) => SauveteurMenuPage(
        profileColor: const Color(0xFFFF0000),
        userRole: widget.userRole,
        territoireId: widget.territoireId,
      ),
    ),
  );
},
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
                              'VALIDER',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        if (_message != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _message!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: sauveteurColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
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

  InputDecoration _inputDecoration({
    required String label,
    required bool showPasswordButton,
  }) {
    const Color sauveteurColor = Color(0xFFEF4444);

    return InputDecoration(
      hintText: label,
      hintStyle: const TextStyle(
        color: sauveteurColor,
        fontWeight: FontWeight.w700,
      ),
      suffixIcon: showPasswordButton
          ? IconButton(
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
            )
          : null,
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
    );
  }
}