import 'dart:math';

import 'package:flutter/material.dart';

import '../models/flag_state.dart';
import '../widgets/danger_pictogram.dart';

class FlagMarker extends StatefulWidget {
  final SpotFlagState spot;

  // L'aperçu sauveteur dispose d'un mât plus haut que les marqueurs de carte.
  final bool sauveteurPreview;

  // Hauteur personnalisée facultative réservée à l'aperçu Actions rapides.
  // Null conserve toutes les dimensions existantes (carte, Live, autres pages).
  final double? sauveteurPreviewHeight;

  // Le mât de la fiche Live reste compact, contrairement à celui de la carte.
  final bool compactDetail;

  // Configuration propre à la fiche LIVE Web. Cette valeur n'est vraie
  // dans aucun autre constructeur spécialisé (carte, mobile, sauveteur).
  final bool desktopLive;

  // Constructeur historique conservé pour la compatibilité.
  const FlagMarker({
    super.key,
    required this.spot,
    this.sauveteurPreview = false,
    this.sauveteurPreviewHeight,
    this.compactDetail = false,
    this.desktopLive = false,
  });

  // Chaque surface sélectionne explicitement sa configuration.
  // Les quatre réglages peuvent évoluer indépendamment sans modifier
  // accidentellement le mât d'un autre écran.
  const FlagMarker.map({
    super.key,
    required this.spot,
  })  : sauveteurPreview = false,
        sauveteurPreviewHeight = null,
        compactDetail = false,
        desktopLive = false;

  const FlagMarker.publicLiveMobile({
    super.key,
    required this.spot,
  })  : sauveteurPreview = false,
        sauveteurPreviewHeight = null,
        compactDetail = true,
        desktopLive = false;

  const FlagMarker.publicLiveWeb({
    super.key,
    required this.spot,
  })  : sauveteurPreview = false,
        sauveteurPreviewHeight = null,
        compactDetail = true,
        desktopLive = true;

  const FlagMarker.actionsRapides({
    super.key,
    required this.spot,
    required double height,
  })  : sauveteurPreview = true,
        sauveteurPreviewHeight = height,
        compactDetail = false,
        desktopLive = false;

  @override
  State<FlagMarker> createState() => _FlagMarkerState();
}

class _FlagMarkerState extends State<FlagMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const double markerWidth = 70;
  // Mât de carte allongé vers le haut ; le pied reste géoréférencé.
  static const double _normalMarkerHeight = 124;
  static const double _previewMarkerHeight = 115;

  static const double poleWidth = 4;
  static const double poleLeft = (markerWidth - poleWidth) / 2;

  static const double flagLeft = poleLeft + poleWidth - 1;
  static const double flagWidth = 26;
  static const double flagHeight = 30;

  static const double flagTopHisse = 18;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color getFlagColor() {
    switch (widget.spot.flagColor) {
      case FlagColor.green:
        return const Color(0xFF22C55E);
      case FlagColor.yellow:
        return const Color(0xFFFDE047);
      case FlagColor.red:
        return const Color(0xFFEF4444);
      case FlagColor.violet:
        return const Color(0xFFD946EF);
      default:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final purpleFlagActive = widget.spot.liveFlag?['purpleFlagActive'] == true;
    final windsockActive = widget.spot.liveFlag?['windsockActive'] == true;

    final hasMainFlag = widget.spot.flagColor != FlagColor.none &&
        widget.spot.flagPosition != FlagPosition.none;

    final isAffale = widget.spot.flagPosition == FlagPosition.affale;

    // La hauteur du mât reste fixe : activer un signal ne rallonge jamais
    // un marqueur de carte. L'aperçu sauveteur conserve son grand mât.
    final markerHeight = widget.sauveteurPreview
        ? (widget.sauveteurPreviewHeight ?? _previewMarkerHeight)
        : widget.compactDetail
            ? 95.0
            : _normalMarkerHeight;
    // Dans la fiche Live, allonger seulement le trait vers le haut.
    // La taille du widget et les positions validées des signaux ne changent pas.
    final poleHeight =
        widget.compactDetail ? markerHeight - 5 : markerHeight - 20;

    // Le dessin sinusoïdal remplit 18 px sur une zone de 30 px :
    // 6 px de marge en haut et en bas du CustomPaint.
    // L'espace visible demandé entre les deux pavillons vaut un tiers
    // de leur hauteur réellement peinte, soit 6 px.
    const paintedFlagHeight = flagHeight - 12.0;
    const flagGap = paintedFlagHeight / 3;
    const flagStep = paintedFlagHeight + flagGap;

    // Affalé, un seul pavillon se place plus bas sur le mât.
    // Si un signal complémentaire est présent, le pavillon principal
    // remonte pour libérer la place basse, sans modifier le mât.
    // Les signaux affalés restent près du pied du mât, avec assez
    // d'espace pour le pavillon violet ou la manche à air sous le premier.
    final lowerFlagTop = markerHeight - 27.0;
    // La manche à air descend d'un pavillon quand les trois signaux sont
    // simultanément présents : principal, violet et manche à air.
    // Affalé, tout le groupe remonte d'autant : le dernier signal conserve
    // sa place près du pied du mât.
    const tripleSignalWindsockDrop = flagHeight;
    final hasTripleSignal = hasMainFlag && purpleFlagActive && windsockActive;
    final loweredTripleGroupLift =
        isAffale && hasTripleSignal ? tripleSignalWindsockDrop : 0.0;
    // Chaque contexte utilise son profil dédié.
    // Le drapeau de carte commence 4 px sous le sommet du mât :
    // (flagTopHisse = 18) + (marge peinte = 6) - (haut mât = 20).
    // Même écart de 4 px dans la fiche LIVE Web, sans toucher à la carte :
    // (18 - compactHissedLift = 15 + 6) - (haut mât compact = 5) = 4.
    // Les autres profils, combinaisons et drapeaux affalés restent inchangés.
    const compactHissedLift = 15.0;
    const webLiveHissedOffset = 0.0;
    final mainFlagTop = isAffale
        ? lowerFlagTop -
            ((purpleFlagActive || windsockActive) ? flagStep : 0) -
            loweredTripleGroupLift
        : flagTopHisse -
            (widget.compactDetail ? compactHissedLift : 0) +
            (widget.desktopLive ? webLiveHissedOffset : 0);
    final purpleFlagTop = mainFlagTop + flagStep;

    // Même en l'absence du violet, la manche à air se situe à la moitié
    // de l'emplacement où ce pavillon serait placé. Elle est attachée
    // directement au mât (pas à l'extrémité du drapeau principal).
    const windsockHeight = 11.0;
    final windsockTop =
        purpleFlagTop + flagHeight / 2 - windsockHeight / 2 +
            (hasTripleSignal ? tripleSignalWindsockDrop : 0.0);
    const windsockLeft = flagLeft;

    return SizedBox(
      width: markerWidth,
      height: markerHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: poleLeft,
            bottom: 0,
            child: Container(
              width: poleWidth,
              height: poleHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(
                  color: Colors.black,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (hasMainFlag)
            Positioned(
              left: flagLeft,
              top: mainFlagTop,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(flagWidth, flagHeight),
                    painter: WavingFlagPainter(
                      color: getFlagColor(),
                      phase: _controller.value * 2 * pi,
                    ),
                  );
                },
              ),
            ),
          if (hasMainFlag && purpleFlagActive)
            Positioned(
              left: flagLeft,
              top: purpleFlagTop,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(flagWidth, flagHeight),
                    painter: WavingFlagPainter(
                      color: const Color(0xFFD946EF),
                      phase: _controller.value * 2 * pi,
                    ),
                  );
                },
              ),
            ),
          if (hasMainFlag && windsockActive)
            Positioned(
              left: windsockLeft,
              top: windsockTop,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform.rotate(
                    alignment: Alignment.centerLeft,
                    angle: sin(_controller.value * 2 * pi) * 0.04,
                    child: const WindsockGlyph(
                      width: 23,
                      height: 11,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class WavingFlagPainter extends CustomPainter {
  final Color color;
  final double phase;

  WavingFlagPainter({
    required this.color,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    final path = Path();

    const int steps = 40;
    const double verticalMargin = 6;

    final topPoints = <Offset>[];
    final bottomPoints = <Offset>[];

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = size.width * t;

      final amplitude = 0.8 + 3.0 * t;
      final wave = sin(t * pi * 2.1 - phase) * amplitude;

      topPoints.add(Offset(x, verticalMargin + wave));
      bottomPoints.add(Offset(x, size.height - verticalMargin + wave));
    }

    path.moveTo(topPoints.first.dx, topPoints.first.dy);

    for (final point in topPoints) {
      path.lineTo(point.dx, point.dy);
    }

    for (final point in bottomPoints.reversed) {
      path.lineTo(point.dx, point.dy);
    }

    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant WavingFlagPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.color != color;
  }
}