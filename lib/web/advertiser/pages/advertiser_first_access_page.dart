import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../shared/web_colors.dart';
import 'advertiser_change_password_page.dart';

class AdvertiserFirstAccessPage extends StatefulWidget {
  const AdvertiserFirstAccessPage({
    super.key,
    required this.login,
    required this.token,
  });

  final String login;
  final String token;

  @override
  State<AdvertiserFirstAccessPage> createState() =>
      _AdvertiserFirstAccessPageState();
}

class _AdvertiserFirstAccessPageState extends State<AdvertiserFirstAccessPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _session;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.login.isEmpty || widget.token.isEmpty) {
        throw Exception('Ouvrez le lien personnel du mail de validation.');
      }
      final response = await http.post(
        Uri.parse(
          'https://us-central1-sphot-ab80b.cloudfunctions.net/'
          'redeemAdvertiserFirstAccess',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'login': widget.login, 'token': widget.token}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(body['error'] ?? 'Ouverture impossible.');
      }
      await FirebaseAuth.instance.signInWithCustomToken(
        body['firebaseToken'] as String,
      );
      if (!mounted) return;
      setState(() => _session = body);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session != null) {
      return AdvertiserChangePasswordPage(
        login: session['login'] as String,
        advertiserRequestId: session['advertiserRequestId'] as String,
        firstName: '',
        lastName: session['nom']?.toString() ?? '',
        civility: session['civilite']?.toString() ?? '',
      );
    }
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'SPHOT PUBLICITAIRE',
                style: TextStyle(
                  color: WebColors.blue,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 24),
              if (_loading) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Ouverture de votre première connexion…'),
              ] else ...[
                Text(
                  _error ?? 'Ouverture impossible.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _open, child: const Text('RÉESSAYER')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
