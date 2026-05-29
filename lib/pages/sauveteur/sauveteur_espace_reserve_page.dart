import 'package:flutter/material.dart';

class SauveteurEspaceReservePage extends StatelessWidget {
  final String title;
  final Color profileColor;

  const SauveteurEspaceReservePage({
    super.key,
    required this.title,
    required this.profileColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(title),
      ),
    );
  }
}