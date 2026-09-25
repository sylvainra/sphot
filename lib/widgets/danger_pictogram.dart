import 'dart:math' as math;

import 'package:flutter/material.dart';

class DangerPictogram extends StatelessWidget {
  final String danger;
  final double size;

  const DangerPictogram({
    super.key,
    required this.danger,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    final upper = danger.toUpperCase();

    if (_containsBaine(upper)) {
      final level = _extractLevel(upper, max: 5, fallback: 1);
      return BaineWaveGlyph(
        level: level,
        color: baineLevelColor(level),
        width: size * 1.35,
        height: size,
      );
    }

    if (upper.contains('CANICULE')) {
      final level = _extractLevel(upper, max: 4, fallback: 1);
      return CaniculeLevelGlyph(
        level: level,
        width: size * 1.55,
        height: size,
      );
    }

    if (upper.contains('SHORE BREAK') || upper.contains('VAGUES FORTES')) {
      return _paint(
        size,
        _CrestWavePainter(const Color(0xFFDC2626)),
      );
    }

    if (upper.contains('HOULE')) {
      return _paint(
        size,
        _SwellPainter(const Color(0xFFDC2626)),
      );
    }

    if (upper.contains('DÉVERSEMENT') ||
        upper.contains('DEVERSEMENT') ||
        upper.contains('LÂCHER DE BARRAGE') ||
        upper.contains('LACHER DE BARRAGE')) {
      return _paint(
        size,
        _SpillwayPainter(const Color(0xFFDC2626)),
      );
    }

    if (upper.contains('TOURBILLON')) {
      return _paint(
        size,
        _WhirlpoolPainter(const Color(0xFFDC2626)),
      );
    }

    if (upper.contains('CHEVAUX')) {
      return _paint(
        size,
        _HorsePainter(const Color(0xFFDC2626)),
      );
    }

    if (upper.contains('REQUINS SIGNALÉS') ||
        upper.contains('REQUINS SIGNALES')) {
      return _paint(
        size,
        _SharkFinPainter(const Color(0xFFDC2626)),
      );
    }

    if (upper.contains('PROPICES À LA PRÉSENCE DE REQUINS') ||
        upper.contains('PROPICES A LA PRESENCE DE REQUINS')) {
      return _paint(
        size,
        _SharkFinPainter(const Color(0xFFF97316)),
      );
    }

    if (upper.contains('ALTÉRATION DE LA QUALITÉ DES EAUX') ||
        upper.contains('ALTERATION DE LA QUALITE DES EAUX') ||
        upper.contains('ESPÈCES DANGEREUSES') ||
        upper.contains('ESPECES DANGEREUSES') ||
        upper.contains('MÉDUSES') ||
        upper.contains('MEDUSES')) {
      return SizedBox(
        width: size * 1.25,
        height: size,
        child: Center(
          child: Container(
            width: size * 1.05,
            height: size * 0.58,
            decoration: BoxDecoration(
              color: const Color(0xFF8E24AA),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: const Color(0xFF6A1B9A),
                width: 1,
              ),
            ),
          ),
        ),
      );
    }

    if (upper.contains('EAU FROIDE')) {
      return SizedBox(
        width: size * 1.2,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.water_drop_rounded,
              color: const Color(0xFF0B79BF),
              size: size,
            ),
            Icon(
              Icons.ac_unit_rounded,
              color: Colors.white,
              size: size * 0.46,
            ),
          ],
        ),
      );
    }

    if (upper.contains('COURANT')) {
      return _icon(
        Icons.sync_alt_rounded,
        const Color(0xFF0284C7),
        size,
      );
    }

    if (upper.contains('VENT')) {
      return _icon(
        Icons.air_rounded,
        const Color(0xFF64748B),
        size,
      );
    }

    if (upper.contains('CHÂLEUR') || upper.contains('CHALEUR')) {
      return _icon(
        Icons.wb_sunny_rounded,
        const Color(0xFFF97316),
        size,
      );
    }

    if (upper.contains('ROCHER') || upper.contains('RÉCIF')) {
      return _icon(
        Icons.landscape_rounded,
        const Color(0xFF78716C),
        size,
      );
    }

    if (upper.contains('TRAF')) {
      return _icon(
        Icons.directions_boat_rounded,
        const Color(0xFF0F766E),
        size,
      );
    }

    if (upper.contains('CRUE') ||
        upper.contains('PROFONDEUR') ||
        upper.contains('ASPIRATION') ||
        upper.contains('VASE') ||
        upper.contains('AUTRE') ||
        upper.contains('ZONE MARINE')) {
      return _icon(
        Icons.warning_amber_rounded,
        const Color(0xFFF59E0B),
        size,
      );
    }

    return _icon(
      Icons.warning_amber_rounded,
      const Color(0xFFF59E0B),
      size,
    );
  }

  static bool _containsBaine(String value) {
    return value.contains('BAÏNE') || value.contains('BAINE');
  }

  static int _extractLevel(
    String value, {
    required int max,
    required int fallback,
  }) {
    final match = RegExp(r'NIVEAU\s*([1-9])').firstMatch(value);
    final parsed = int.tryParse(match?.group(1) ?? '') ?? fallback;
    return parsed.clamp(1, max);
  }

  static Widget _icon(IconData icon, Color color, double size) {
    return SizedBox(
      width: size * 1.2,
      height: size,
      child: Center(
        child: Icon(
          icon,
          color: color,
          size: size * 0.78,
        ),
      ),
    );
  }

  static Widget _paint(double size, CustomPainter painter) {
    return SizedBox(
      width: size * 1.35,
      height: size,
      child: CustomPaint(painter: painter),
    );
  }
}

Color baineLevelColor(int level) {
  switch (level) {
    case 1:
      return const Color(0xFF22C55E);
    case 2:
      return const Color(0xFF84CC16);
    case 3:
      return const Color(0xFFF59E0B);
    case 4:
      return const Color(0xFFF97316);
    default:
      return const Color(0xFFDC2626);
  }
}

Color caniculeLevelColor(int level) {
  switch (level) {
    case 1:
      return const Color(0xFF4CAF50);
    case 2:
      return const Color(0xFFD4B000);
    case 3:
      return const Color(0xFFF97316);
    default:
      return const Color(0xFFDC2626);
  }
}

class BaineWaveGlyph extends StatelessWidget {
  final int level;
  final Color color;
  final double width;
  final double height;

  const BaineWaveGlyph({
    super.key,
    required this.level,
    required this.color,
    this.width = 34,
    this.height = 26,
  });

  @override
  Widget build(BuildContext context) {
    final safeLevel = level.clamp(1, 5);

    return CustomPaint(
      size: Size(width, height),
      painter: _LevelWavesPainter(
        safeLevel,
        color,
      ),
    );
  }
}

class CaniculeLevelGlyph extends StatelessWidget {
  final int level;
  final double width;
  final double height;

  const CaniculeLevelGlyph({
    super.key,
    required this.level,
    this.width = 44,
    this.height = 28,
  });

  @override
  Widget build(BuildContext context) {
    final safeLevel = level.clamp(1, 4);
    final color = caniculeLevelColor(safeLevel);
    final iconSize = math.max(10.0, height * 0.58);

    return SizedBox(
      width: width,
      height: height,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            safeLevel,
            (_) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.6),
              child: Icon(
                Icons.wb_sunny_rounded,
                color: color,
                size: iconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelWavesPainter extends CustomPainter {
  final int level;
  final Color color;

  _LevelWavesPainter(this.level, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.8, size.height * 0.09)
      ..strokeCap = StrokeCap.round;

    final spacing = size.height / (level + 1);

    for (var i = 0; i < level; i++) {
      final y = spacing * (i + 1);
      final path = Path()..moveTo(0, y);
      final segment = size.width / 4;

      path
        ..quadraticBezierTo(segment * 0.5, y - spacing * 0.28, segment, y)
        ..quadraticBezierTo(
          segment * 1.5,
          y + spacing * 0.28,
          segment * 2,
          y,
        )
        ..quadraticBezierTo(
          segment * 2.5,
          y - spacing * 0.28,
          segment * 3,
          y,
        )
        ..quadraticBezierTo(
          segment * 3.5,
          y + spacing * 0.28,
          segment * 4,
          y,
        );

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LevelWavesPainter oldDelegate) {
    return oldDelegate.level != level || oldDelegate.color != color;
  }
}

class _CrestWavePainter extends CustomPainter {
  final Color color;

  _CrestWavePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, size.height * 0.09)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final crest = Path()
      ..moveTo(size.width * 0.06, size.height * 0.53)
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.55,
        size.width * 0.28,
        size.height * 0.08,
        size.width * 0.53,
        size.height * 0.10,
      )
      ..cubicTo(
        size.width * 0.78,
        size.height * 0.12,
        size.width * 0.88,
        size.height * 0.34,
        size.width * 0.72,
        size.height * 0.39,
      )
      ..cubicTo(
        size.width * 0.58,
        size.height * 0.43,
        size.width * 0.61,
        size.height * 0.65,
        size.width * 0.94,
        size.height * 0.58,
      );

    canvas.drawPath(crest, paint);

    for (final y in [0.72, 0.88]) {
      final line = Path()..moveTo(size.width * 0.07, size.height * y);
      line
        ..quadraticBezierTo(
          size.width * 0.25,
          size.height * (y - 0.08),
          size.width * 0.45,
          size.height * y,
        )
        ..quadraticBezierTo(
          size.width * 0.65,
          size.height * (y + 0.08),
          size.width * 0.93,
          size.height * y,
        );
      canvas.drawPath(line, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CrestWavePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _SwellPainter extends CustomPainter {
  final Color color;

  _SwellPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, size.height * 0.09)
      ..strokeCap = StrokeCap.round;

    final path = Path()..moveTo(size.width * 0.03, size.height * 0.58);

    final points = <Offset>[
      Offset(size.width * 0.14, size.height * 0.47),
      Offset(size.width * 0.24, size.height * 0.60),
      Offset(size.width * 0.34, size.height * 0.31),
      Offset(size.width * 0.44, size.height * 0.73),
      Offset(size.width * 0.55, size.height * 0.13),
      Offset(size.width * 0.66, size.height * 0.78),
      Offset(size.width * 0.78, size.height * 0.42),
      Offset(size.width * 0.96, size.height * 0.57),
    ];

    for (final point in points) {
      path.quadraticBezierTo(
        (path.getBounds().right + point.dx) / 2,
        point.dy,
        point.dx,
        point.dy,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SwellPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _SpillwayPainter extends CustomPainter {
  final Color color;

  _SpillwayPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, size.height * 0.09)
      ..strokeCap = StrokeCap.round;

    final topY = size.height * 0.18;
    canvas.drawLine(
      Offset(size.width * 0.10, topY),
      Offset(size.width * 0.76, topY),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.86, topY),
      Offset(size.width * 0.96, topY),
      paint,
    );

    for (final x in [0.32, 0.50, 0.68]) {
      final path = Path()
        ..moveTo(size.width * x, topY)
        ..lineTo(size.width * x, size.height * 0.64);
      canvas.drawPath(path, paint);
    }

    final water = Path()..moveTo(size.width * 0.08, size.height * 0.80);
    water
      ..quadraticBezierTo(
        size.width * 0.22,
        size.height * 0.68,
        size.width * 0.34,
        size.height * 0.80,
      )
      ..quadraticBezierTo(
        size.width * 0.46,
        size.height * 0.92,
        size.width * 0.58,
        size.height * 0.80,
      )
      ..quadraticBezierTo(
        size.width * 0.70,
        size.height * 0.68,
        size.width * 0.82,
        size.height * 0.80,
      )
      ..quadraticBezierTo(
        size.width * 0.90,
        size.height * 0.88,
        size.width * 0.98,
        size.height * 0.80,
      );
    canvas.drawPath(water, paint);
  }

  @override
  bool shouldRepaint(covariant _SpillwayPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _WhirlpoolPainter extends CustomPainter {
  final Color color;

  _WhirlpoolPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, size.height * 0.09)
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final path = Path();
    const turns = 2.3;
    const samples = 70;

    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final angle = t * turns * math.pi * 2;
      final radius = size.shortestSide * (0.06 + 0.40 * t);
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );

      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WhirlpoolPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _HorsePainter extends CustomPainter {
  final Color color;

  _HorsePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.8, size.height * 0.075)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final body = Rect.fromLTWH(
      size.width * 0.24,
      size.height * 0.42,
      size.width * 0.48,
      size.height * 0.26,
    );
    canvas.drawOval(body, paint);

    final neck = Path()
      ..moveTo(size.width * 0.64, size.height * 0.47)
      ..lineTo(size.width * 0.76, size.height * 0.25)
      ..lineTo(size.width * 0.89, size.height * 0.31)
      ..lineTo(size.width * 0.80, size.height * 0.42);
    canvas.drawPath(neck, paint);

    for (final x in [0.32, 0.46, 0.61, 0.70]) {
      canvas.drawLine(
        Offset(size.width * x, size.height * 0.64),
        Offset(
          size.width * (x - 0.03),
          size.height * (x == 0.46 ? 0.90 : 0.86),
        ),
        paint,
      );
    }

    final tail = Path()
      ..moveTo(size.width * 0.24, size.height * 0.46)
      ..quadraticBezierTo(
        size.width * 0.10,
        size.height * 0.45,
        size.width * 0.08,
        size.height * 0.70,
      );
    canvas.drawPath(tail, paint);

    canvas.drawCircle(
      Offset(size.width * 0.48, size.height * 0.15),
      size.height * 0.07,
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.48, size.height * 0.22),
      Offset(size.width * 0.48, size.height * 0.44),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.48, size.height * 0.28),
      Offset(size.width * 0.68, size.height * 0.35),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HorsePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _SharkFinPainter extends CustomPainter {
  final Color color;

  _SharkFinPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, size.height * 0.085)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fin = Path()
      ..moveTo(size.width * 0.10, size.height * 0.58)
      ..quadraticBezierTo(
        size.width * 0.36,
        size.height * 0.54,
        size.width * 0.44,
        size.height * 0.18,
      )
      ..quadraticBezierTo(
        size.width * 0.62,
        size.height * 0.32,
        size.width * 0.78,
        size.height * 0.58,
      );
    canvas.drawPath(fin, paint);

    for (final y in [0.62, 0.82]) {
      final wave = Path()..moveTo(size.width * 0.08, size.height * y);
      wave
        ..quadraticBezierTo(
          size.width * 0.30,
          size.height * (y - 0.08),
          size.width * 0.50,
          size.height * y,
        )
        ..quadraticBezierTo(
          size.width * 0.70,
          size.height * (y + 0.08),
          size.width * 0.93,
          size.height * y,
        );
      canvas.drawPath(wave, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SharkFinPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
