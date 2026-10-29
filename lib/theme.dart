import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 2060 Tele Player colours: deep space background, electric mint as the main accent,
/// violet and pink as the glow colours.
class C {
  static const bg = Color(0xFF06070F);
  static const panel = Color(0xFF0D0F1F);
  static const card = Color(0xFF161934);
  static const accent = Color(0xFF2FE6D0);
  static const violet = Color(0xFF7B5CFF);
  static const pink = Color(0xFFFF4FA3);
  static const text = Color(0xFFF3F5FF);
  static const dim = Color(0xFF8F94B8);
  static const danger = Color(0xFFFF6B8B);

  /// The signature gradient (logo, buttons, highlights).
  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, violet, pink],
  );
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.accent, brightness: Brightness.dark),
  );
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    splashFactory: NoSplash.splashFactory,
    // Soft fade between screens (cheap on weak devices, nicer than an instant cut).
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: _FadeTransitions(),
      TargetPlatform.iOS: _FadeTransitions(),
    }),
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
  );
}

class _FadeTransitions extends PageTransitionsBuilder {
  const _FadeTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }
}

void log(String message) => debugPrint('TELE $message');

/// The round "play in an orbit" mark of 2060 Tele Player.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _MarkPainter()));
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final shader = C.brand.createShader(rect);
    // Outer orbit ring.
    canvas.drawCircle(
      c,
      r * 0.92,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.14,
    );
    // Tilted second orbit.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-math.pi / 5);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 2.0, height: r * 0.78),
      Paint()
        ..color = const Color(0x66FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05,
    );
    canvas.restore();
    // The play triangle.
    final path = Path()
      ..moveTo(c.dx - r * 0.22, c.dy - r * 0.38)
      ..lineTo(c.dx + r * 0.46, c.dy)
      ..lineTo(c.dx - r * 0.22, c.dy + r * 0.38)
      ..close();
    canvas.drawPath(path, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => false;
}

/// "2060" in the brand gradient with "TELE PLAYER" under it.
class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 34});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LogoMark(size: size * 1.25),
        SizedBox(width: size * 0.32),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => C.brand.createShader(Rect.fromLTWH(0, 0, r.width, r.height)),
              child: Text(
                '2060',
                style: TextStyle(
                  fontSize: size,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: size * 0.04,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: size * 0.08),
            Text(
              'TELE PLAYER',
              style: TextStyle(
                fontSize: size * 0.30,
                height: 1.0,
                fontWeight: FontWeight.w700,
                letterSpacing: size * 0.16,
                color: C.dim,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Slow drifting colour clouds behind a screen (aurora). Cheap: three blurred circles,
/// painted once per frame without any shader work.
class Aurora extends StatefulWidget {
  const Aurora({super.key, this.strength = 1.0});
  final double strength;

  @override
  State<Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<Aurora> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 28))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(painter: _AuroraPainter(_c.value, widget.strength), size: Size.infinite),
        ),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t, this.k);
  final double t;
  final double k;

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = C.bg);
    void blob(Color color, double px, double py, double rx, double ry, double phase) {
      final a = (t + phase) * 2 * math.pi;
      final c = Offset(s.width * (px + 0.08 * math.cos(a)), s.height * (py + 0.10 * math.sin(a * 1.3)));
      final r = s.shortestSide * rx;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [color.withValues(alpha: 0.34 * k), color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    blob(C.violet, 0.15, 0.20, 0.85, 0, 0.0);
    blob(C.accent, 0.88, 0.85, 0.75, 0, 0.35);
    blob(C.pink, 0.78, 0.10, 0.55, 0, 0.7);
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}
