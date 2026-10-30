import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Moving pictures for the big home tiles. Each one is a single CustomPaint driven by the tile's
/// animation value (0..1, looping), so it costs almost nothing on weak TV boxes.
enum TileArtKind { live, movies, series }

class TileArt extends StatelessWidget {
  const TileArt({super.key, required this.kind, required this.t, required this.focused, required this.glow});

  final TileArtKind kind;
  final double t;
  final bool focused;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ArtPainter(kind, t, focused, glow), size: Size.infinite);
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.kind, this.t, this.focused, this.glow);
  final TileArtKind kind;
  final double t;
  final bool focused;
  final Color glow;

  @override
  void paint(Canvas canvas, Size s) {
    if (!Ui.lite) _particles(canvas, s);
    if (kind == TileArtKind.live) _liveBadge(canvas, s);
  }

  /// Soft specks of light drifting upwards (dust in a projector beam).
  void _particles(Canvas canvas, Size s) {
    for (var i = 0; i < 16; i++) {
      final seed = i * 0.6180339;
      final phase = (t * (0.6 + (i % 4) * 0.18) + seed) % 1.0;
      final x = s.width * ((seed * 7.3) % 1.0) + math.sin(phase * 2 * math.pi + i) * 9;
      final y = s.height * (1.05 - phase * 1.15);
      final a = math.sin(phase * math.pi) * (focused ? 0.55 : 0.34);
      final r = 1.2 + (i % 3) * 0.9;
      canvas.drawCircle(Offset(x, y), r * 2.4, Paint()..color = glow.withValues(alpha: a * 0.25));
      canvas.drawCircle(Offset(x, y), r, Paint()..color = Colors.white.withValues(alpha: a));
    }
  }

  void _liveBadge(Canvas canvas, Size s) {
    final blink = 0.55 + 0.45 * math.sin(t * 2 * math.pi * 3);
    final bx = s.width - 24.0;
    final by = 28.0;
    final tp = TextPainter(
      text: const TextSpan(text: 'LIVE', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width + 40;
    final rect = RRect.fromRectAndRadius(Rect.fromLTWH(bx - w, by - 14, w, 28), const Radius.circular(14));
    canvas.drawRRect(rect, Paint()..color = const Color(0x66000000));
    canvas.drawRRect(rect, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = const Color(0x44FFFFFF));
    canvas.drawCircle(Offset(bx - w + 16, by), 9 * blink, Paint()..color = const Color(0xFFFF3B5C).withValues(alpha: 0.25));
    canvas.drawCircle(Offset(bx - w + 16, by), 5, Paint()..color = const Color(0xFFFF3B5C).withValues(alpha: blink));
    tp.paint(canvas, Offset(bx - w + 28, by - tp.height / 2));
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.t != t || old.focused != focused;
}

/// A diagonal band of light that sweeps across the tile while it is focused.
class ShinePainter extends CustomPainter {
  ShinePainter(this.progress);
  final double progress; // 0..1

  @override
  void paint(Canvas canvas, Size s) {
    if (progress <= 0 || progress >= 1) return;
    final x = -s.width * 0.4 + (s.width * 1.8) * progress;
    final path = Path()
      ..moveTo(x, 0)
      ..lineTo(x + s.width * 0.18, 0)
      ..lineTo(x + s.width * 0.18 - s.height * 0.35, s.height)
      ..lineTo(x - s.height * 0.35, s.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.14),
          Colors.white.withValues(alpha: 0),
        ]).createShader(Rect.fromLTWH(x - s.height * 0.35, 0, s.width * 0.18 + s.height * 0.35, s.height)),
    );
  }

  @override
  bool shouldRepaint(ShinePainter old) => old.progress != progress;
}
