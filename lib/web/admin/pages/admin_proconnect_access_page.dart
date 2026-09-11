import 'package:flutter/material.dart';

import '../../shared/sphot_access_page.dart';

class AdminProConnectAccessPage extends StatelessWidget {
  const AdminProConnectAccessPage({super.key});

  void _continueToAdminRequest(BuildContext context) {
    Navigator.of(context).pushReplacementNamed('/admin-request-form');
  }

  @override
  Widget build(BuildContext context) => SphotAccessPage(
    title: 'SPHOT ADMIN',
    onBack: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'L’accès est réservé aux professionnels identifiés par ProConnect.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: sphotAccessBlue,
            fontSize: 16,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 24),
        SphotAccessButton(
          label: 'S’IDENTIFIER AVEC PROCONNECT',
          icon: Icons.verified_user_outlined,
          onPressed: () => _continueToAdminRequest(context),
        ),
      ],
    ),
  );
}
