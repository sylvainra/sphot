import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../web/shared/sphot_access_page.dart';

const _blue = Color(0xFF1E3A8A);
const _red = Color(0xFFDC2626);
const _functionsUrl =
    'https://us-central1-sphot-ab80b.cloudfunctions.net';

class PasswordRecoveryRequestPage extends StatefulWidget {
  const PasswordRecoveryRequestPage({
    super.key,
    required this.login,
    required this.availableAudiences,
    this.initialAudience,
  });

  final String login;
  final List<String> availableAudiences;
  final String? initialAudience;

  @override
  State<PasswordRecoveryRequestPage> createState() =>
      _PasswordRecoveryRequestPageState();
}

class _PasswordRecoveryRequestPageState
    extends State<PasswordRecoveryRequestPage> {
  late final TextEditingController _loginController;
  String? _audience;
  String? _message;
  bool _sending = false;
  bool _submitted = false;

  static const labels = {
    'ADMIN': 'SPHOT ADMIN',
    'ANNONCEUR': 'SPHOT PUBLICITAIRE',
    'SAUVETEUR': 'SPHOT SAUVETEUR',
  };

  @override
  void initState() {
    super.initState();
    _loginController = TextEditingController(text: widget.login);
    final choices = widget.availableAudiences
        .where(labels.containsKey)
        .toSet()
        .toList();
    _audience = widget.initialAudience != null &&
            choices.contains(widget.initialAudience)
        ? widget.initialAudience
        : choices.length == 1
            ? choices.first
            : null;
  }

  @override
  void dispose() {
    _loginController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending || _submitted) return;
    final login = _loginController.text.trim().toLowerCase();
    if (login.isEmpty || _audience == null) {
      setState(() => _message =
          'Renseignez votre identifiant et choisissez votre espace SPHOT.');
      return;
    }
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      final response = await http.post(
        Uri.parse('$_functionsUrl/requestSphotPasswordRecovery'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'login': login, 'audience': _audience}),
      );
      if (response.statusCode != 200) {
        throw StateError('Récupération momentanément indisponible.');
      }
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _message = 'Si un compte actif correspond à ces informations, '
            'un lien de réinitialisation a été envoyé à son adresse email. '
            'Vérifiez également les courriers indésirables.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Service momentanément indisponible. Réessayez plus tard.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = widget.availableAudiences
        .where(labels.containsKey)
        .toSet()
        .toList();
    return SphotAccessPage(
      title: 'MOT DE PASSE OUBLIÉ',
      onBack: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'RÉINITIALISER VOTRE MOT DE PASSE',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _blue, fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          const Text(
            'Indiquez votre identifiant SPHOT. Un lien personnel '
            'sera envoyé à l’adresse email associée à votre compte.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _blue, fontSize: 14),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _loginController,
            enabled: !_sending && !_submitted,
            decoration: const InputDecoration(
              labelText: 'Identifiant SPHOT',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(color: _blue),
          ),
          if (choices.length > 1) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _audience,
              decoration: const InputDecoration(
                labelText: 'Espace SPHOT',
                border: OutlineInputBorder(),
              ),
              items: choices.map((value) => DropdownMenuItem(
                value: value,
                child: Text(labels[value]!),
              )).toList(),
              onChanged: _sending || _submitted ? null :
                  (value) => setState(() => _audience = value),
            ),
          ],
          const SizedBox(height: 18),
          if (_message != null) ...[
            Text(
              _message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _submitted ? _blue : _red,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (!_submitted)
            SphotAccessButton(
              label: 'RECEVOIR LE LIEN',
              loading: _sending,
              onPressed: _submit,
            ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('RETOUR À LA CONNEXION'),
          ),
        ],
      ),
    );
  }
}

class PasswordRecoveryConfirmPage extends StatefulWidget {
  const PasswordRecoveryConfirmPage({super.key, required this.token});

  final String token;

  @override
  State<PasswordRecoveryConfirmPage> createState() =>
      _PasswordRecoveryConfirmPageState();
}

class _PasswordRecoveryConfirmPageState
    extends State<PasswordRecoveryConfirmPage> {
  final _newPassword = TextEditingController();
  final _confirmation = TextEditingController();
  bool _showPassword = false;
  bool _saving = false;
  bool _saved = false;
  String? _message;

  @override
  void dispose() {
    _newPassword.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || _saved) return;
    final password = _newPassword.text.trim();
    if (password != _confirmation.text.trim()) {
      setState(() => _message =
          'Les deux mots de passe ne correspondent pas.');
      return;
    }
    if (password.length < 8 || password.length > 256 ||
        !RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password) ||
        !RegExp(r'[!@#?*\-]').hasMatch(password)) {
      setState(() => _message =
          'Utilisez au moins 8 caractères, une majuscule, une minuscule, '
          'un chiffre et un caractère spécial parmi ! @ # ? * -.');
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final response = await http.post(
        Uri.parse('$_functionsUrl/completeSphotPasswordRecovery'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': widget.token,
          'newPassword': password,
        }),
      );
      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() => _message = response.statusCode == 400
            ? 'Ce lien est invalide, expiré ou déjà utilisé. '
                'Demandez un nouveau lien depuis la connexion SPHOT.'
            : 'Modification impossible pour le moment. Réessayez.');
        return;
      }
      _newPassword.clear();
      _confirmation.clear();
      setState(() {
        _saved = true;
        _message = 'Votre mot de passe a été modifié. '
            'Vous pouvez vous reconnecter à SPHOT.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Connexion impossible. Vérifiez votre accès Internet.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SphotAccessPage(
    title: 'NOUVEAU MOT DE PASSE',
    onBack: () => Navigator.of(context)
        .pushNamedAndRemoveUntil('/login', (_) => false),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'CHOISISSEZ VOTRE MOT DE PASSE',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: _blue, fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 20),
        if (!_saved) ...[
          TextField(
            controller: _newPassword,
            enabled: !_saving,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'Nouveau mot de passe',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () => setState(() =>
                    _showPassword = !_showPassword),
                icon: Icon(_showPassword ? Icons.visibility_off :
                    Icons.visibility),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _confirmation,
            enabled: !_saving,
            obscureText: !_showPassword,
            decoration: const InputDecoration(
              labelText: 'Confirmer le mot de passe',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 16),
          Text(
            _message!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _saved ? _blue : _red,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 18),
        if (!_saved)
          SphotAccessButton(
            label: 'VALIDER MON MOT DE PASSE',
            loading: _saving,
            onPressed: _submit,
          ),
        if (_saved)
          SphotAccessButton(
            label: 'SE CONNECTER',
            loading: false,
            onPressed: () => Navigator.of(context)
                .pushNamedAndRemoveUntil('/login', (_) => false),
          ),
      ],
    ),
  );
}
