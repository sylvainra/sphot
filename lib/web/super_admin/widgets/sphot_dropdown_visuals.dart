import 'package:flutter/material.dart';

/// Référentiel visuel unique pour les menus déroulants SPHOT.
class SphotDropdownVisuals {
  const SphotDropdownVisuals._();

  static const Color blue = Color(0xFF1E3A8A);
  static const Color red = Color(0xFFDC2626);

  static final BoxDecoration popupDecoration = BoxDecoration(
    color: Colors.white,
    border: const Border(
      left: BorderSide(color: blue, width: 1.8),
      right: BorderSide(color: blue, width: 1.8),
      bottom: BorderSide(color: blue, width: 1.8),
    ),
    borderRadius: const BorderRadius.only(
      bottomLeft: Radius.circular(14),
      bottomRight: Radius.circular(14),
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.12),
        blurRadius: 9,
        offset: const Offset(0, 4),
      ),
    ],
  );

  static const ScrollbarThemeData scrollbarTheme = ScrollbarThemeData(
    thumbColor: WidgetStatePropertyAll(blue),
    trackVisibility: WidgetStatePropertyAll(false),
  );

  static OutlineInputBorder inputBorder({double width = 1.8}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: blue, width: width),
      );
}
