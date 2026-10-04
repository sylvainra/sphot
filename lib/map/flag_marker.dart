import 'dart:math';

import 'package:flutter/material.dart';

import '../models/flag_state.dart';

const Color sphotViolet = Color(0xFFD946EF);

class FlagMarker extends StatefulWidget {
  final SpotFlagState spot;

  const FlagMarker({
    super.key,
    required this.spot,
  });

  @override
  State<FlagMarker> createState() => _FlagMarkerState();
}

class _FlagMarkerState extends State<FlagMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const double markerWidth = 70;
  static const double markerHeight = 95;

  static const double poleWidth = 4;
  static const double poleHeight = 75;
  static const double poleLeft = (markerWidth - poleWidth) / 2;

  static const double flagLeft = poleLeft + poleWidth - 1;
  static const double flagWidth = 26;
  static const double flagHeight = 30;

  static const double flagTopHisse = 18;
  static const double flagTopAffale = 54;

  // Le drapeau violet possède exactement les mêmes dimensions
  // que le drapeau principal.
  static const double purpleFlagTop = 39;

  // Manche à air fixe.
  static const double windsockWidth = 27;
  static const double windsockHeight = 16;

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

      // Conservé pour compatibilité avec d'éventuelles anciennes données.
      // Le nouveau drapeau violet complémentaire n'utilise PAS flagColor.
      case FlagColor.violet:
        return sphotViolet;

      case FlagColor.none:
        return Colors.transparent;
    }
  }

  Map<String, dynamic> get _liveFlag {
    final value = widget.spot.liveFlag;

    if (value == null) {
      return <String, dynamic>{};
    }

    return value;
  }

  bool get purpleFlagActive {
    return _liveFlag['purpleFlagActive'] == true;
  }

  bool get windsockActive {
    return _liveFlag['windsockActive'] == true;
  }

  bool get flagIsHisse {
    return widget.spot.flagPosition == FlagPosition.hisse;
  }

  double get flagTop {
    return widget.spot.flagPosition == FlagPosition.affale
        ? flagTopAffale
        : flagTopHisse;
  }

  double get windsockTop {
    // Lorsque le violet est hissé, la manche à air descend
    // légèrement pour conserver trois signaux bien distincts.
    if (purpleFlagActive && flagIsHisse) {
      return 65;
    }

    return 46;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: markerWidth,
      height: markerHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // =========================================================
          // MÂT
          // =========================================================
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

          // =========================================================
          // DRAPEAU PRINCIPAL
          // =========================================================
          if (widget.spot.flagColor != FlagColor.none &&
              widget.spot.flagPosition != FlagPosition.none)
            Positioned(
              left: flagLeft,
              top: flagTop,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(
                      flagWidth,
                      flagHeight,
                    ),
                    painter: WavingFlagPainter(
                      color: getFlagColor(),
                      phase: _controller.value * 2 * pi,
                    ),
                  );
                },
              ),
            ),

          // =========================================================
          // DRAPEAU VIOLET COMPLÉMENTAIRE
          //
          // Il n'est pas une quatrième couleur du drapeau principal.
          // Il est physiquement ajouté SOUS le drapeau principal.
          //
          // Même largeur.
          // Même hauteur.
          // Même animation.
          // Même phase de vent.
          // =========================================================
          if (purpleFlagActive && flagIsHisse)
            Positioned(
              left: flagLeft,
              top: purpleFlagTop,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(
                      flagWidth,
                      flagHeight,
                    ),
                    painter: WavingFlagPainter(
                      color: sphotViolet,
                      phase: _controller.value * 2 * pi,
                    ),
                  );
                },
              ),
            ),

          // =========================================================
          // MANCHE À AIR
          //
          // Elle est volontairement fixe.
          // La forme reproduit le principe du cliché :
          // - large ouverture côté mât ;
          // - corps orange ;
          // - rétrécissement progressif ;
          // - anneau gris de fixation.
          // =========================================================
          if (windsockActive)
            Positioned(
              left: flagLeft - 1,
              top: windsockTop,
              child: const CustomPaint(
                size: Size(
                  windsockWidth,
                  windsockHeight,
                ),
                painter: WindsockPainter(),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// DRAPEAU ANIMÉ
// ============================================================================

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

      final wave = sin(
            t * pi * 2.1 - phase,
          ) *
          amplitude;

      topPoints.add(
        Offset(
          x,
          verticalMargin + wave,
        ),
      );

      bottomPoints.add(
        Offset(
          x,
          size.height - verticalMargin + wave,
        ),
      );
    }

    path.moveTo(
      topPoints.first.dx,
      topPoints.first.dy,
    );

    for (final point in topPoints) {
      path.lineTo(
        point.dx,
        point.dy,
      );
    }

    for (final point in bottomPoints.reversed) {
      path.lineTo(
        point.dx,
        point.dy,
      );
    }

    path.close();

    canvas.drawPath(
      path,
      fillPaint,
    );

    canvas.drawPath(
      path,
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant WavingFlagPainter oldDelegate,
  ) {
    return oldDelegate.phase != phase ||
        oldDelegate.color != color;
  }
}

// ============================================================================
// MANCHE À AIR FIXE
// ============================================================================

class WindsockPainter extends CustomPainter {
  const WindsockPainter();

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    // ------------------------------------------------------------------------
    // Petit bras horizontal fixé au mât
    // ------------------------------------------------------------------------

    final armPaint = Paint()
      ..color = const Color(0xFF616161)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(
        0,
        size.height / 2,
      ),
      Offset(
        3,
        size.height / 2,
      ),
      armPaint,
    );

    // ------------------------------------------------------------------------
    // Anneau métallique, semblable à celui visible sur le cliché
    // ------------------------------------------------------------------------

    final ringFillPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..style = PaintingStyle.fill;

    final ringBorderPaint = Paint()
      ..color = const Color(0xFF9CA3AF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    final ring = Rect.fromCenter(
      center: Offset(
        4,
        size.height / 2,
      ),
      width: 4.5,
      height: 9,
    );

    canvas.drawOval(
      ring,
      ringFillPaint,
    );

    canvas.drawOval(
      ring,
      ringBorderPaint,
    );

    // ------------------------------------------------------------------------
    // Manche orange
    //
    // Large près du mât, plus étroite à son extrémité.
    // ------------------------------------------------------------------------

    final sockPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0xFFFFA000),
          Color(0xFFF59E0B),
          Color(0xFFE58A00),
        ],
      ).createShader(
        Rect.fromLTWH(
          4,
          0,
          size.width - 4,
          size.height,
        ),
      )
      ..style = PaintingStyle.fill;

    final sockBorderPaint = Paint()
      ..color = const Color(0xFFB45309)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;

    final path = Path();

    path.moveTo(
      5,
      2.5,
    );

    path.cubicTo(
      size.width * 0.36,
      2,
      size.width * 0.72,
      4,
      size.width - 1,
      5.5,
    );

    path.lineTo(
      size.width - 1,
      size.height - 5.5,
    );

    path.cubicTo(
      size.width * 0.72,
      size.height - 4,
      size.width * 0.36,
      size.height - 2,
      5,
      size.height - 2.5,
    );

    path.close();

    canvas.drawPath(
      path,
      sockPaint,
    );

    canvas.drawPath(
      path,
      sockBorderPaint,
    );

    // ------------------------------------------------------------------------
    // Renfort clair au niveau de l'ouverture
    // ------------------------------------------------------------------------

    final openingPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawArc(
      Rect.fromLTWH(
        3.5,
        2.5,
        5,
        size.height - 5,
      ),
      -pi / 2,
      pi,
      false,
      openingPaint,
    );

    // ------------------------------------------------------------------------
    // Petits points métalliques visibles sur le bord du cliché
    // ------------------------------------------------------------------------

    final eyeletPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      const Offset(
        5.1,
        4.2,
      ),
      0.65,
      eyeletPaint,
    );

    canvas.drawCircle(
      Offset(
        5.1,
        size.height - 4.2,
      ),
      0.65,
      eyeletPaint,
    );

    // ------------------------------------------------------------------------
    // Quelques plis très discrets du tissu
    // ------------------------------------------------------------------------

    final foldPaint = Paint()
      ..color = const Color(0xFFB45309).withOpacity(0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    canvas.drawLine(
      Offset(
        size.width * 0.35,
        4,
      ),
      Offset(
        size.width * 0.38,
        size.height - 4,
      ),
      foldPaint,
    );

    canvas.drawLine(
      Offset(
        size.width * 0.62,
        4.7,
      ),
      Offset(
        size.width * 0.64,
        size.height - 4.7,
      ),
      foldPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant WindsockPainter oldDelegate,
  ) {
    return false;
  }
}