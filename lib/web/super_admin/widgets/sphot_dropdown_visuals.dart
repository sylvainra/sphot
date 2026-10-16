import 'package:flutter/material.dart';

/// Référentiel visuel unique pour les menus déroulants SPHOT.
class SphotDropdownVisuals {
  const SphotDropdownVisuals._();

  static const Color blue = Color(0xFF1E3A8A);
  static const Color red = Color(0xFFDC2626);

  // Jonction au champ : identique au menu ÉQUIPEMENTS validé.
  static const double popupOverlap = 12;
  static const double popupContentInset = 12;

  /// Relie visuellement le contour des filtres à leur liste ouverte.
  /// Le cadre du champ ne doit pas créer une ligne horizontale qui
  /// sépare visuellement le popup. Dessiné au-dessus des deux widgets.
  static List<Widget> joinedFieldEdges(Offset origin, Size size) => [
    Positioned(
      left: origin.dx + 2,
      top: origin.dy + size.height - 4,
      width: size.width - 4,
      height: 7,
      child: const IgnorePointer(
        child: ColoredBox(color: Colors.white),
      ),
    ),
    Positioned(
      left: origin.dx,
      top: origin.dy + size.height - 26,
      width: size.width,
      height: 29,
      child: const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: blue, width: 1.8),
              right: BorderSide(color: blue, width: 1.8),
            ),
          ),
        ),
      ),
    ),
  ];


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
        color: Colors.black.withOpacity(0.045),
        blurRadius: 4,
        offset: const Offset(0, 2),
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
