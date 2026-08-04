import 'dart:convert';

import 'package:flutter/material.dart';
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
        _message = 'Les mots de passe sont différents.';
      });
      return false;
    }

    final regex = RegExp(
      r'^(?=.*[A-Z])(?=.*[0-9])(?=.*[!@#?*\-]).{8,}$',
    );

    if (!regex.hasMatch(password)) {
      setState(() {
        _message =
            '8 caractères mini, 1 majuscule, 1 chiffre, 1 caractère : ! @ # ? * -';
      });
      return false;
    }

    setState(() {
      _message = null;
    });

    return true;
  }

  Future<void> _changePassword() async {
    FocusScope.of(context).unfocus();

    if (!_validatePassword()) return;

    final uri = Uri.parse(
      'https://us-central1-sphot-ab80b.cloudfunctions.net/changeSauveteurPassword',
    );

    debugPrint('>>> APPEL changeSauveteurPassword');

    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'login': widget.login,
        'newPassword': _newPasswordController.text.trim(),
      }),
    );

    debugPrint('Status = ${response.statusCode}');
    debugPrint('Body = ${response.body}');
    debugPrint('>>> RETOUR changeSauveteurPassword');

    if (!mounted) return;

    if (response.statusCode < 200 || response.statusCode >= 300) {
      setState(() {
        _message = 'Modification impossible. Réessayez.';
      });
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SauveteurMenuPage(
          profileColor: const Color(0xFFFF0000),
          userRole: widget.userRole,
          territoireId: widget.territoireId,
        ),
      ),
    );
  }

  void _closeKeyboard() {
    FocusScope.of(context).unfocus();
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
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onTap: _closeKeyboard,
        child: SizedBox.expand(
          child: ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'data/images/map_background.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned.fill(
                  bottom: 70 + safeBottom,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final contentWidth = (constraints.maxWidth - 52)
                          .clamp(0.0, 520.0)
                          .toDouble();

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(26, 6, 26, 0),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: contentWidth,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'data/icons/title.png',
                                    height: 56,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      16,
                                      16,
                                      14,
                                    ),
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
                                        const SizedBox(height: 12),
                                        const Text(
                                          'Pour sécuriser votre compte, vous devez choisir un nouveau mot de passe avant d’accéder à SPHOT.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: sauveteurColor,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                        TextField(
                                          controller: _newPasswordController,
                                          obscureText: !_showPassword,
                                          textInputAction: TextInputAction.next,
                                          style: const TextStyle(
                                            color: sauveteurColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          decoration: _inputDecoration(
                                            label: 'Nouveau mot de passe',
                                            showPasswordButton: true,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller:
                                              _confirmPasswordController,
                                          obscureText: !_showPassword,
                                          textInputAction: TextInputAction.done,
                                          onSubmitted: (_) => _changePassword(),
                                          style: const TextStyle(
                                            color: sauveteurColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          decoration: _inputDecoration(
                                            label: 'Confirmer le mot de passe',
                                            showPasswordButton: true,
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                        SizedBox(
                                          width: double.infinity,
                                          height: 50,
                                          child: ElevatedButton(
                                            onPressed: _changePassword,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.transparent,
                                              foregroundColor: sauveteurColor,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(18),
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
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          height: 38,
                                          child: _message == null
                                              ? const SizedBox.shrink()
                                              : Center(
                                                  child: Text(
                                                    _message!,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      color: sauveteurColor,
                                                      fontSize: 13,
                                                      height: 1.15,
                                                      fontWeight:
                                                          FontWeight.w700,
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
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: safeBottom + 8,
                  child: Center(
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      child: IconButton(
                        tooltip: 'Retour',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 28,
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
        vertical: 12,
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
