import 'dart:math';
import 'package:flutter/material.dart';
import '../models/flag_state.dart';

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
  static const double flagWidth = 34;
  static const double flagHeight = 30;

  static const double flagTopHisse = 18;
  static const double flagTopAffale = 54;

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

  double get flagTop {
    return widget.spot.flagPosition == FlagPosition.affale
        ? flagTopAffale
        : flagTopHisse;
  }

  @override
  Widget build(BuildContext context) {
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
          if (widget.spot.hasValidFlag)
            Positioned(
              left: flagLeft,
              top: flagTop,
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
      final wave = sin(phase + t * pi * 2.1) * amplitude;

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