import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'admin_dashboard_page.dart';
import '../../shared/sphot_access_page.dart';
import '../../../map/map_page.dart';


class AdminChangePasswordPage extends StatefulWidget {
  final String login;
  final String adminUid;
  final String territoireId;
  final String userRole;
  final String civilite;
  final String prenom;
  final String nom;

  const AdminChangePasswordPage({
    super.key,
    required this.login,
    required this.adminUid,
    required this.territoireId,
    required this.userRole,
    required this.civilite,
    required this.prenom,
    required this.nom,
  });

  @override
  State<AdminChangePasswordPage> createState() =>
      _AdminChangePasswordPageState();
}

class _AdminChangePasswordPageState extends State<AdminChangePasswordPage> {
  static const Color _adminColor = Color(0xFF1E3A8A);

  final TextEditingController _newPasswordController =
      TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final FocusNode _newPasswordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();

  bool _showNewPassword = false;
  bool _showConfirmPassword = false;
  bool _isSaving = false;
  String? _errorMessage;

  String get _greeting {
  final rawCivilite = widget.civilite.trim().toLowerCase();
  final nom = widget.nom.trim().toUpperCase();

  String civilite;

  if (rawCivilite == 'madame' ||
      rawCivilite == 'mme' ||
      rawCivilite == 'femme') {
    civilite = 'Madame';
  } else {
    civilite = 'Monsieur';
  }

  final fullName = nom;

  if (fullName.isEmpty) {
    return 'Bonjour';
  }

  return 'Bonjour $civilite $fullName';
}

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _newPasswordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  bool _isPasswordValid(String password) {
    final hasMinimumLength = password.length >= 8;
    final hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
    final hasLowercase = RegExp(r'[a-z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    final hasSpecialCharacter = RegExp(r'[!@#?*\-]').hasMatch(password);

    return hasMinimumLength &&
        hasUppercase &&
        hasLowercase &&
        hasNumber &&
        hasSpecialCharacter;
  }

  Future<void> _changePassword() async {
    if (_isSaving) return;

    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    FocusScope.of(context).unfocus();

    setState(() {
      _errorMessage = null;
    });

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      setState(() {
        _errorMessage = 'Veuillez renseigner et confirmer votre nouveau mot de passe.';
      });
      return;
    }

    if (!_isPasswordValid(newPassword)) {
      setState(() {
        _errorMessage =
            'Le mot de passe doit contenir au moins 8 caractères, une majuscule, une minuscule, un chiffre et un caractère spécial parmi ! @ # ? * -.';
      });
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() {
        _errorMessage = 'Les deux mots de passe ne correspondent pas.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final uri = Uri.parse(
        'https://us-central1-sphot-ab80b.cloudfunctions.net/changeAdminPassword',
      );

      final response = await http.post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'login': widget.login.trim().toLowerCase(),
          'newPassword': newPassword,
        }),
      );

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'La modification du mot de passe a échoué. Veuillez réessayer.';
        });
        return;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'La modification du mot de passe a échoué. Veuillez réessayer.';
        });
        return;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Votre mot de passe a été modifié avec succès.',
              textAlign: TextAlign.center,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );

      Navigator.of(context).pushReplacement(
  MaterialPageRoute(
    builder: (_) => AdminDashboardPage(
      adminUid: widget.adminUid,
      territoireId: widget.territoireId,
    ),
  ),
);
    } catch (error, stackTrace) {
      debugPrint('Erreur changement mot de passe administrateur : $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Connexion impossible. Vérifiez votre connexion internet et réessayez.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData prefixIcon,
    required bool passwordVisible,
    required VoidCallback onVisibilityPressed,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: _adminColor,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(prefixIcon, color: _adminColor),
      suffixIcon: IconButton(
        onPressed: _isSaving ? null : onVisibilityPressed,
        icon: Icon(
          passwordVisible
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          color: _adminColor,
        ),
      ),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.10),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _adminColor, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _adminColor, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _adminColor, width: 2.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SphotAccessPage(
    title: 'CRÉEZ VOTRE MOT DE PASSE',
    onBack: () {
      FocusScope.of(context).unfocus();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/'),
          builder: (_) => const MapPage(),
        ),
        (route) => false,
      );
    },
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _greeting,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _adminColor,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Pour sécuriser votre SPHOT ADMIN, vous devez remplacer le mot de passe provisoire avant d’accéder à votre SPHOT ADMIN.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _adminColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _newPasswordController,
          focusNode: _newPasswordFocusNode,
          enabled: !_isSaving,
          obscureText: !_showNewPassword,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) {
            _confirmPasswordFocusNode.requestFocus();
          },
          onChanged: (_) {
            if (_errorMessage != null) {
              setState(() {
                _errorMessage = null;
              });
            }
          },
          style: const TextStyle(
            color: _adminColor,
            fontWeight: FontWeight.w700,
          ),
          decoration: _inputDecoration(
            hintText: 'Nouveau mot de passe',
            prefixIcon: Icons.lock_outline_rounded,
            passwordVisible: _showNewPassword,
            onVisibilityPressed: () {
              setState(() {
                _showNewPassword = !_showNewPassword;
              });
            },
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confirmPasswordController,
          focusNode: _confirmPasswordFocusNode,
          enabled: !_isSaving,
          obscureText: !_showConfirmPassword,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => _changePassword(),
          onChanged: (_) {
            if (_errorMessage != null) {
              setState(() {
                _errorMessage = null;
              });
            }
          },
          style: const TextStyle(
            color: _adminColor,
            fontWeight: FontWeight.w700,
          ),
          decoration: _inputDecoration(
            hintText: 'Confirmer le mot de passe',
            prefixIcon:
                Icons.verified_user_outlined,
            passwordVisible: _showConfirmPassword,
            onVisibilityPressed: () {
              setState(() {
                _showConfirmPassword =
                    !_showConfirmPassword;
              });
            },
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _adminColor.withValues(
              alpha: 0.06,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Minimum 8 caractères avec une majuscule, une minuscule, un chiffre et un caractère spécial : ! @ # ? * -',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _adminColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        const SizedBox(height: 14),
        SphotAccessButton(
          label: 'VALIDER MON MOT DE PASSE',
          loading: _isSaving,
          onPressed: _changePassword,
        ),
      ],
    ),
  );
}

