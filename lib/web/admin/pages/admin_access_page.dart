import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/sphot_access_page.dart';

class AdminAccessPage extends StatefulWidget {
  const AdminAccessPage({super.key});

  @override
  State<AdminAccessPage> createState() => _AdminAccessPageState();
}

class _AdminAccessPageState extends State<AdminAccessPage> {
  bool _opening = false;
  String? _error;

  Future<void> _startRequest() async {
    if (_opening) return;

    if (kIsWeb) {
      Navigator.of(context).pushReplacementNamed('/admin-request-form');
      return;
    }

    setState(() {
      _opening = true;
      _error = null;
    });

    final opened = await launchUrl(
      Uri.parse('https://sphot.app/#/admin-request-form'),
      mode: LaunchMode.externalApplication,
    );

    if (!mounted) return;

    setState(() {
      _opening = false;
      if (!opened) {
        _error = 'Impossible d’ouvrir le site SPHOT.';
      }
    });
  }

  @override
  Widget build(BuildContext context) => SphotAccessPage(
        title: 'SPHOT ADMIN',
        onBack: () => Navigator.of(context)
            .pushNamedAndRemoveUntil('/map', (route) => false),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Accès réservé aux professionnels.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: sphotAccessBlue,
                fontSize: 16,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              kIsWeb
                  ? "Professionnels, créez votre SPHOT ADMIN en quelques clics, après validation de votre demande préalable auprès de l’équipe SPHOT."
                  : "Pour créer votre SPHOT ADMIN dans de meilleures conditions de confort et de lisibilité, vous allez être redirigé vers le site SPHOT afin de compléter votre demande d’adhésion.",
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: sphotAccessBlue,
                fontSize: 16,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEEEE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Color(0xFFDC2626)),
                ),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SphotAccessButton(
              loading: _opening,
              onPressed: _startRequest,
              label: kIsWeb
                  ? 'COMMENCER MA DEMANDE'
                  : 'CONTINUER SUR LE SITE SPHOT',
            ),
          ],
        ),
      );
}
