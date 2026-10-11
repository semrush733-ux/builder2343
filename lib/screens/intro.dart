import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine.dart';

/// The start animation, drawn entirely in code (no video): three colour layers fly in from the
/// corners, merge into the Cloud Player logo, the play button pops in, a light sweeps across and
/// the name slides in. The startup sound plays with it. Shown once per app start, then [next].
/// Any key or tap skips it.
class IntroGate extends StatefulWidget {
  const IntroGate({super.key, required this.next});
  final Widget next;

  static bool _shown = false;

  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> with SingleTickerProviderStateMixin {
  static const _length = Duration(milliseconds: 4100);

  late final AnimationController _c = AnimationController(vsync: this, duration: _length);
  bool _done = IntroGate._shown;
  ExoEngine? _sound;
  final FocusNode _focus = FocusNode(debugLabel: 'intro');

  @override
  void initState() {
    super.initState();
    IntroGate._shown = true;
    if (_done) return;
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
    _start();
  }

  Future<void> _start() async {
    // The sound starts together with the picture; without sound (web, or a problem) the
    // animation simply runs silently.
    if (ExoEngine.available) {
      try {
        final e = await ExoEngine.create(live: false).timeout(const Duration(milliseconds: 900));
        if (!mounted || _done) {
          e.dispose();
          return;
        }
        _sound = e;
        unawaited(e.open('asset:///flutter_assets/assets/intro_sound.mp3', Duration.zero));
      } catch (_) {}
    }
    if (mounted && !_done) _c.forward();
  }

  void _finish() {
    if (_done) return;
    final e = _sound;
    _sound = null;
    e?.dispose();
    if (mounted) setState(() => _done = true);
  }

  @override
  void dispose() {
    _c.dispose();
    _sound?.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.next;
    return Scaffold(
      backgroundColor: const Color(0xFF0E1118),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent) _finish();
          return KeyEventResult.handled;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _finish,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _IntroPainter(_c.value * _length.inMilliseconds / 1000),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------------- drawing

double _clamp(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);
double _seg(double t, double a, double b) => _clamp((t - a) / (b - a));
double _outCubic(double x) => 1 - math.pow(1 - x, 3).toDouble();
double _inOut(double x) => x < .5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
double _outBack(double x) {
  const c1 = 1.70158, c3 = c1 + 1;
  return 1 + c3 * math.pow(x - 1, 3) + c1 * math.pow(x - 1, 2);
}

/// A polygon with rounded corners (quadratic curves), in the logo's 1000 x 1000 box.
Path _rpoly(List<Offset> pts, List<double> r) {
  final path = Path();
  final n = pts.length;
  for (var i = 0; i < n; i++) {
    final p = pts[i], a = pts[(i - 1 + n) % n], b = pts[(i + 1) % n];
    final da = (a - p).distance, db = (b - p).distance;
    final ri = math.min(r[i], math.min(da / 2, db / 2));
    final p1 = p + (a - p) * (ri / da);
    final p2 = p + (b - p) * (ri / db);
    if (i == 0) {
      path.moveTo(p1.dx, p1.dy);
    } else {
      path.lineTo(p1.dx, p1.dy);
    }
    path.quadraticBezierTo(p.dx, p.dy, p2.dx, p2.dy);
  }
  return path..close();
}

final Path _outer = _rpoly(const [Offset(150, 95), Offset(935, 500), Offset(150, 905)], const [170, 150, 170]);
final Path _play = _rpoly(const [Offset(440, 340), Offset(680, 500), Offset(440, 660)], const [46, 40, 46]);

Shader _lin(Offset a, Offset b, List<Color> colors, List<double> stops) => ui.Gradient.linear(a, b, colors, stops);

class _Layer {
  const _Layer(this.sx, this.rot, this.dx, this.dy, this.from, this.shader, this.shadow);
  final double sx, rot, dx, dy;
  final List<double> from; // start offset x, y and extra turn
  final Shader Function() shader;
  final double shadow;
}

final List<_Layer> _layers = [
  _Layer(0.92, -0.20, 120, -150, const [900, -650, -1.3],
      () => _lin(const Offset(900, 100), const Offset(300, 700), const [Color(0xFFFFE36A), Color(0xFFFFC233), Color(0xFFFF9F1C)], const [0, .5, 1]),
      0.45),
  _Layer(0.74, 0.12, -30, 40, const [-900, -500, 1.5],
      () => _lin(const Offset(800, 300), const Offset(200, 800), const [Color(0xFFFFAA33), Color(0xFFFF7A12), Color(0xFFF25A16)], const [0, .55, 1]),
      0.5),
  _Layer(0.62, 0.42, -160, 230, const [-600, 900, 1.8],
      () => _lin(const Offset(700, 500), const Offset(150, 950), const [Color(0xFFFF7B22), Color(0xFFEE4019), Color(0xFFC9101B)], const [0, .6, 1]),
      0.55),
];

class _IntroPainter extends CustomPainter {
  _IntroPainter(this.t);
  final double t; // seconds

  void _shadowed(Canvas canvas, Path path, Paint fill, Color shadow, double sigma, Offset off) {
    canvas.drawPath(
        path.shift(off),
        Paint()
          ..color = shadow
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma));
    canvas.drawPath(path, fill);
  }

  void _layer(Canvas canvas, _Layer l, double k, double alpha) {
    final dx = l.dx + (1 - k) * l.from[0], dy = l.dy + (1 - k) * l.from[1], rot = l.rot + (1 - k) * l.from[2];
    canvas.save();
    if (alpha < 1) canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    canvas.translate(500 + dx, 500 + dy);
    canvas.rotate(rot);
    canvas.scale(l.sx, l.sx);
    canvas.translate(-500, -500);
    _shadowed(canvas, _outer, Paint()..shader = l.shader(), Color.fromRGBO(110, 15, 0, l.shadow), 35, const Offset(-16, 14));
    if (alpha < 1) canvas.restore();
    canvas.restore();
  }

  void _symbol(Canvas canvas, double a, double b, double c, double merge, double play, double shine) {
    // 1) the layers flying in from three corners
    if (merge < 1) {
      final ks = [a, b, c];
      for (var i = 0; i < 3; i++) {
        if (ks[i] > 0) _layer(canvas, _layers[i], ks[i], (1 - merge) * math.min(1, ks[i] * 3));
      }
    }
    // 2) merged into the logo: base + layers cut to the outline, light sweep
    if (merge > 0) {
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, merge));
      canvas.drawPath(
          _outer,
          Paint()
            ..color = const Color.fromRGBO(255, 120, 20, 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 45));
      canvas.drawPath(
          _outer,
          Paint()
            ..shader = _lin(const Offset(900, 150), const Offset(150, 900),
                const [Color(0xFFFFD84A), Color(0xFFFF9A1F), Color(0xFFF0401E)], const [0, .45, 1]));
      canvas.save();
      canvas.clipPath(_outer);
      for (final l in _layers) {
        _layer(canvas, l, 1, 1);
      }
      if (shine > 0 && shine < 1) {
        final x = -400 + shine * 1800;
        canvas.translate(500, 500);
        canvas.rotate(0.45);
        canvas.translate(-500, -500);
        canvas.drawRect(
            const Rect.fromLTWH(-600, -600, 2200, 2200),
            Paint()
              ..shader = _lin(Offset(x - 170, 0), Offset(x + 170, 0),
                  const [Color(0x00FFFFFF), Color(0x80FFFFFF), Color(0x00FFFFFF)], const [0, .5, 1]));
      }
      canvas.restore();
      canvas.restore();
    }
    // 3) the play button pops in, turning
    if (play > 0) {
      canvas.save();
      canvas.translate(540, 500);
      canvas.rotate((1 - math.min(1, play)) * -1.6);
      canvas.scale(play, play);
      canvas.translate(-540, -500);
      _shadowed(canvas, _play, Paint()..color = Colors.white, const Color.fromRGBO(150, 40, 0, 0.5), 20, const Offset(-6, 10));
      canvas.restore();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0E1118));

    // warm glow behind the logo
    final glow = _outCubic(_seg(t, 0, 0.8)) * (0.85 + 0.15 * math.sin(t * 4));
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.radial(Offset(w / 2, h / 2), h * 0.75,
              [Color.fromRGBO(255, 140, 30, 0.22 * glow), const Color.fromRGBO(255, 140, 30, 0)]));

    final a = _outCubic(_seg(t, 0.05, 0.75));
    final b = _outCubic(_seg(t, 0.18, 0.88));
    final c = _outCubic(_seg(t, 0.31, 1.01));
    final merge = _inOut(_seg(t, 0.98, 1.28));
    final play = _outBack(_seg(t, 1.2, 1.65));
    final shine = _inOut(_seg(t, 1.65, 2.35));
    final word = _outCubic(_seg(t, 1.75, 2.45));
    final out = _inOut(_seg(t, 3.35, 3.95));

    final logo = h * 0.5 * (1 + 0.05 * math.sin(math.pi * _seg(t, 1.0, 1.4))) * (1 + 0.06 * out);

    // the name, measured first so logo + name end up centred together
    final fontSize = h * 0.13;
    final text = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, height: 1, letterSpacing: -fontSize * 0.01),
        children: [
          TextSpan(text: 'Cloud ', style: TextStyle(color: const Color(0xFFF2F4F8).withValues(alpha: word * (1 - out)))),
          TextSpan(
            text: 'Player',
            style: TextStyle(
              foreground: Paint()
                ..shader = ui.Gradient.linear(Offset.zero, Offset(fontSize * 3.6, 0), [
                  const Color(0xFFFFC400).withValues(alpha: word * (1 - out)),
                  const Color(0xFFFF8A1E).withValues(alpha: word * (1 - out)),
                ]),
            ),
          ),
        ],
      ),
    )..layout();
    final gap = logo * 0.12;
    final shift = -((gap + text.width) / 2) * word;

    canvas.saveLayer(Offset.zero & size, Paint()..color = Color.fromRGBO(0, 0, 0, 1 - out));
    canvas.save();
    canvas.translate(w / 2 + shift - logo / 2, h / 2 - logo / 2);
    canvas.scale(logo / 1000, logo / 1000);
    _symbol(canvas, a, b, c, merge, play, shine);
    canvas.restore();
    if (word > 0) {
      final x = w / 2 + shift + logo / 2 + gap + (1 - word) * 80;
      text.paint(canvas, Offset(x, h / 2 - text.height / 2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IntroPainter old) => old.t != t;
}
