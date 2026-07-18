import 'package:flutter/material.dart';

class SuperAdminSphotsPage extends StatelessWidget {
  const SuperAdminSphotsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Gestion globale des SPHOTS',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}