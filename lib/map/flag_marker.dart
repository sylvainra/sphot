import 'dart:math';

import 'package:flutter/material.dart';

import '../models/flag_state.dart';
import '../widgets/danger_pictogram.dart';

class FlagMarker extends StatefulWidget {
  final SpotFlagState spot;

  // L'aperçu sauveteur dispose d'un mât plus haut que les marqueurs de carte.
  final bool sauveteurPreview;

  const FlagMarker({
    super.key,
    required this.spot,
    this.sauveteurPreview = false,
  });

  @override
  State<FlagMarker> createState() => _FlagMarkerState();
}

class _FlagMarkerState extends State<FlagMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const double markerWidth = 70;
  static const double _normalMarkerHeight = 95;
  static const double _previewMarkerHeight = 145;

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
    final markerHeight =
        widget.sauveteurPreview ? _previewMarkerHeight : _normalMarkerHeight;
    final poleHeight = markerHeight - 20;

    // Position affalée historique du drapeau principal, en bas du mât.
    final originalLowerTop = markerHeight - 41;
    const halfFlagHeight = flagHeight / 2;

    // Sans violet : position principale inchangée, même si la manche à air
    // est sélectionnée. Avec violet : il prend la place basse historique et
    // le drapeau principal remonte de la moitié d'une hauteur de pavillon.
    final mainFlagTop = isAffale
        ? originalLowerTop - (purpleFlagActive ? halfFlagHeight : 0)
        : flagTopHisse;
    final purpleFlagTop =
        isAffale ? originalLowerTop : flagTopHisse + halfFlagHeight;

    // La manche à air est liée au MÂT, pas à l'extrémité du drapeau.
    // Son point d'attache est à mi-hauteur du pavillon inférieur.
    const windsockHeight = 11.0;
    final lowerFlagTop = purpleFlagActive ? purpleFlagTop : mainFlagTop;
    final windsockTop = lowerFlagTop + halfFlagHeight - windsockHeight / 2;
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