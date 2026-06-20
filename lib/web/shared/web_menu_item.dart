import 'package:flutter/material.dart';

class WebMenuItem {
  final String title;
  final IconData icon;
  final Widget page;

  const WebMenuItem({
    required this.title,
    required this.icon,
    required this.page,
  });
}