import 'package:flutter/material.dart';

class AdminSphotsPage extends StatelessWidget {
  const AdminSphotsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Gestion des SPHOTS',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}