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
    switch (kind) {
      case TileArtKind.live:
        _live(canvas, s);
      case TileArtKind.movies:
        _movies(canvas, s);
      case TileArtKind.series:
        _series(canvas, s);
    }
  }

  // ---- Live TV: broadcast rings spreading from the corner, equaliser bars, blinking LIVE badge.
  void _live(Canvas canvas, Size s) {
    final o = Offset(s.width * 0.86, s.height * 0.80);
    final maxR = s.shortestSide * 0.95;
    for (var i = 0; i < 4; i++) {
      final p = (t * 1.0 + i / 4) % 1.0;
      final r = maxR * p;
      final a = (1 - p) * (focused ? 0.55 : 0.34);
      canvas.drawCircle(
        o,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = glow.withValues(alpha: a),
      );
    }
    // Equaliser bars.
    final baseY = s.height * 0.90;
    final left = s.width * 0.56;
    final bw = s.width * 0.022;
    for (var i = 0; i < 9; i++) {
      final h = (0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 2 * math.pi * 2 + i * 0.9))) * s.height * 0.16;
      final x = left + i * bw * 1.9;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, baseY - h, bw, h), Radius.circular(bw / 2)),
        Paint()..color = Colors.white.withValues(alpha: 0.22 + (focused ? 0.18 : 0)),
      );
    }
    // LIVE badge, top right.
    final blink = 0.55 + 0.45 * math.sin(t * 2 * math.pi * 3);
    final bx = s.width - 24.0;
    final by = 28.0;
    final tp = TextPainter(
      text: const TextSpan(text: 'LIVE', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width + 40;
    final rect = RRect.fromRectAndRadius(Rect.fromLTWH(bx - w, by - 14, w, 28), const Radius.circular(14));
    canvas.drawRRect(rect, Paint()..color = const Color(0x55000000));
    canvas.drawRRect(rect, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = const Color(0x44FFFFFF));
    canvas.drawCircle(Offset(bx - w + 16, by), 5, Paint()..color = const Color(0xFFFF3B5C).withValues(alpha: blink));
    canvas.drawCircle(
        Offset(bx - w + 16, by), 9 * blink, Paint()..color = const Color(0xFFFF3B5C).withValues(alpha: 0.25 * (1 - blink + 0.3)));
    tp.paint(canvas, Offset(bx - w + 28, by - tp.height / 2));
  }

  // ---- Movies: three poster cards fanned out, floating gently.
  void _movies(Canvas canvas, Size s) {
    final cw = math.min(s.width * 0.30, 96.0);
    final ch = cw * 1.45;
    final cx = s.width * 0.80;
    final cy = s.height * 0.46;
    final cols = [
      [const Color(0xFFFF4FA3), const Color(0xFF7B5CFF)],
      [const Color(0xFF2FE6D0), const Color(0xFF3B6CFF)],
      [const Color(0xFFFFB84F), const Color(0xFFFF4F6E)],
    ];
    for (var i = 0; i < 3; i++) {
      final f = math.sin(t * 2 * math.pi + i * 1.7);
      final ang = (i - 1) * 0.30 + f * 0.04;
      final dx = (i - 1) * cw * 0.62;
      final dy = f * 6 + (i == 1 ? -10 : 4);
      canvas.save();
      canvas.translate(cx + dx, cy + dy);
      canvas.rotate(ang);
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: cw, height: ch), const Radius.circular(10));
      canvas.drawRRect(r.shift(const Offset(0, 6)), Paint()..color = const Color(0x44000000));
      canvas.drawRRect(
        r,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: cols[i])
              .createShader(r.outerRect),
      );
      // play mark on the poster
      final tri = Path()
        ..moveTo(-cw * 0.10, -cw * 0.14)
        ..lineTo(cw * 0.17, 0)
        ..lineTo(-cw * 0.10, cw * 0.14)
        ..close();
      canvas.drawPath(tri, Paint()..color = Colors.white.withValues(alpha: 0.85));
      // two text lines
      final line = Paint()..color = Colors.white.withValues(alpha: 0.35);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-cw * 0.38, ch * 0.30, cw * 0.76, 5), const Radius.circular(3)), line);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-cw * 0.38, ch * 0.38, cw * 0.46, 5), const Radius.circular(3)), line);
      canvas.restore();
    }
  }

  // ---- Series: a stack of episode cards that ripple one after another.
  void _series(Canvas canvas, Size s) {
    final cw = math.min(s.width * 0.34, 110.0);
    final ch = cw * 0.62;
    final cx = s.width * 0.79;
    final cy = s.height * 0.50;
    for (var i = 4; i >= 0; i--) {
      final wave = math.sin(t * 2 * math.pi - i * 0.7);
      final lift = wave * 5;
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + i * 7, cy - i * 14 + lift), width: cw, height: ch),
        const Radius.circular(9),
      );
      final k = 1 - i * 0.16;
      canvas.drawRRect(r.shift(const Offset(0, 4)), Paint()..color = Colors.black.withValues(alpha: 0.25));
      canvas.drawRRect(
        r,
        Paint()
          ..shader = LinearGradient(colors: [
            Color.lerp(const Color(0xFF1E2B55), C.accent, 0.55 * k)!,
            Color.lerp(const Color(0xFF151A3A), C.violet, 0.55 * k)!,
          ]).createShader(r.outerRect),
      );
      if (i == 0) {
        final tp = TextPainter(
          text: const TextSpan(text: 'S1 · E4', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(r.left + 10, r.top + 8));
        // progress bar filling up
        final p = (t * 1.0) % 1.0;
        final bar = Rect.fromLTWH(r.left + 10, r.bottom - 14, cw - 20, 4);
        canvas.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(2)), Paint()..color = Colors.white24);
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(bar.left, bar.top, bar.width * p, 4), const Radius.circular(2)),
            Paint()..color = C.accent);
      }
    }
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
