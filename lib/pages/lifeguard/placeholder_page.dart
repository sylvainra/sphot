import 'package:flutter/material.dart';

class PlaceholderPage extends StatelessWidget {
  final String title;
  final Color profileColor;

  const PlaceholderPage({
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