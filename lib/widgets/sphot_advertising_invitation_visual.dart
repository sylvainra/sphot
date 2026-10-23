import 'package:flutter/material.dart';

/// Visuel SPHOT de candidature publicitaire, indépendant du clic parent.
///
/// Les deux formats sont issus des maquettes déjà validées. Le widget ne
/// définit ni hauteur ni largeur : les emplacements existants les imposent.
class SphotAdvertisingInvitationVisual extends StatelessWidget {
  const SphotAdvertisingInvitationVisual({
    super.key,
    this.compact = false,
    this.mobileMap = false,
    this.fit = BoxFit.contain,
  });

  final bool compact;
  final bool mobileMap;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final assetPath = compact
        ? 'data/images/sphot_advertising_callout_compact.png'
        : mobileMap
            ? 'data/images/sphot_advertising_callout_mobile_centered_v3.png'
            : 'data/images/sphot_advertising_callout_web_centered_v3.png';

    // Le fond habille toute la zone cliquable, même quand le visuel conserve
    // son ratio et laisse quelques pixels de marge sur une taille donnée.
    return ColoredBox(
      color: const Color(0xFF03283D),
      child: Image.asset(
        assetPath,
        width: double.infinity,
        height: double.infinity,
        fit: fit,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );
  }
}
