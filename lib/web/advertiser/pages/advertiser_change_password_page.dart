import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../shared/web_colors.dart';
import 'advertiser_dashboard_page.dart';

class AdvertiserChangePasswordPage extends StatefulWidget {
  const AdvertiserChangePasswordPage({
    super.key,
    required this.login,
    required this.advertiserRequestId,
    required this.firstName,
    required this.lastName,
  });

  final String login;
  final String advertiserRequestId;
  final String firstName;
  final String lastName;

  @override
  State<AdvertiserChangePasswordPage> createState() =>
      _AdvertiserChangePasswordPageState();
}

class _AdvertiserChangePasswordPageState
    extends State<AdvertiserChangePasswordPage> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _showPassword = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  bool _passwordIsValid(String value) {
    return value.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(value) &&
        RegExp(r'[a-z]').hasMatch(value) &&
        RegExp(r'[0-9]').hasMatch(value) &&
        RegExp(r'[!@#?*\-]').hasMatch(value);
  }

  Future<void> _save() async {
    if (_saving) return;
    final password = _passwordController.text.trim();
    final confirmation = _confirmationController.text.trim();
    if (!_passwordIsValid(password)) {
      setState(() {
        _error = 'Utilisez au moins 8 caractères avec majuscule, minuscule, chiffre et caractère spécial parmi ! @ # ? * -.';
      });
      return;
    }
    if (password != confirmation) {
      setState(() => _error = 'Les deux mots de passe ne correspondent pas.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await http.post(
        Uri.parse(
          'https://us-central1-sphot-ab80b.cloudfunctions.net/changeAdvertiserPassword',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'login': widget.login.toLowerCase(),
          'newPassword': password,
        }),
      );
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 ||
          decoded is! Map<String, dynamic> ||
          decoded['success'] != true) {
        throw Exception('Réponse de changement de mot de passe invalide.');
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => AdvertiserDashboardPage(
            user: null,
            advertiserRequestId: widget.advertiserRequestId,
            approvedAccess: true,
            onSignOut: () async {},
          ),
        ),
        (route) => false,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'La modification a échoué. Vérifiez votre connexion et réessayez.';
        });
      }
      debugPrint('Changement mot de passe annonceur impossible : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: WebColors.blue,
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: WebColors.blue, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: WebColors.blue, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: WebColors.blue, width: 2.3),
      ),
      suffixIcon: IconButton(
        onPressed: () => setState(() => _showPassword = !_showPassword),
        icon: Icon(
          _showPassword
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          color: WebColors.blue,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = '${widget.firstName} ${widget.lastName}'.trim();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('data/images/map_background.jpg', fit: BoxFit.cover),
          ColoredBox(color: Colors.white.withOpacity(0.78)),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                width: 520,
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.97),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: WebColors.blue, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'PREMIÈRE CONNEXION ANNONCEUR',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: WebColors.blue,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      displayName.isEmpty
                          ? 'Choisissez votre mot de passe personnel.'
                          : 'Bienvenue $displayName. Choisissez votre mot de passe personnel.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF4B5F97),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _passwordController,
                      obscureText: !_showPassword,
                      style: const TextStyle(
                        color: WebColors.blue,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: _decoration('Nouveau mot de passe'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirmationController,
                      obscureText: !_showPassword,
                      style: const TextStyle(
                        color: WebColors.blue,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: _decoration('Confirmer le mot de passe'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: WebColors.red,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: WebColors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.lock_reset_rounded),
                      label: const Text(
                        'VALIDER MON MOT DE PASSE',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
