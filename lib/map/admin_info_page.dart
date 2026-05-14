import 'package:flutter/material.dart';

class AdminInfoPage extends StatelessWidget {
  const AdminInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        title: const Text('Administration'),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
      ),

      body: const Center(
        child: Text(
          'Espace administratif',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}