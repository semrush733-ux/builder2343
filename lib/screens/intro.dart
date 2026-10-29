import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// The start animation, drawn entirely in code: an orbit ring draws itself, the play mark
/// lights up, "2060" rises out of the glow and the name settles under it. About two seconds,
/// once per app start. Any key or tap skips it.
class IntroGate extends StatefulWidget {
  const IntroGate({super.key, required this.next});
  final Widget next;

  static bool _shown = false;

  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2300));
  bool _done = IntroGate._shown;
  final FocusNode _focus = FocusNode(debugLabel: 'intro');

  @override
  void initState() {
    super.initState();
    IntroGate._shown = true;
    if (_done) return;
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
    _c.forward();
  }

  void _finish() {
    if (_done || !mounted) return;
    setState(() => _done = true);
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.next;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent) _finish();
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: Scaffold(
          backgroundColor: C.bg,
          body: Stack(
            fit: StackFit.expand,
            children: [
              const Aurora(strength: 1.2),
              AnimatedBuilder(
                animation: _c,
                builder: (_, __) {
                  final t = _c.value;
                  double seg(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
                  final ring = Curves.easeOutCubic.transform(seg(0.0, 0.55));
                  final mark = Curves.easeOutBack.transform(seg(0.25, 0.70));
                  final word = Curves.easeOutCubic.transform(seg(0.45, 0.85));
                  final tag = Curves.easeOut.transform(seg(0.70, 1.0));
                  final out = 1 - Curves.easeIn.transform(seg(0.92, 1.0));
                  return Opacity(
                    opacity: out,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 150,
                            height: 150,
                            child: CustomPaint(painter: _RingPainter(ring, mark, t)),
                          ),
                          const SizedBox(height: 18),
                          Opacity(
                            opacity: word,
                            child: Transform.translate(
                              offset: Offset(0, 24 * (1 - word)),
                              child: ShaderMask(
                                blendMode: BlendMode.srcIn,
                                shaderCallback: (r) => C.brand.createShader(Rect.fromLTWH(0, 0, r.width, r.height)),
                                child: const Text('2060',
                                    style: TextStyle(
                                        fontSize: 76, fontWeight: FontWeight.w900, letterSpacing: 6, color: Colors.white)),
                              ),
                            ),
                          ),
                          Opacity(
                            opacity: tag,
                            child: Padding(
                              padding: EdgeInsets.only(top: 4 + 10 * (1 - tag)),
                              child: const Text('TELE PLAYER',
                                  style: TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 9, color: C.dim)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.ring, this.mark, this.t);
  final double ring;
  final double mark;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    final rect = Rect.fromCircle(center: c, radius: r);
    final shader = C.brand.createShader(rect);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * ring,
      false,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 9,
    );
    // The tilted orbit turns slowly while the intro runs.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-math.pi / 5 + t * math.pi * 0.6);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 2.1, height: r * 0.8),
      Paint()
        ..color = Color.fromRGBO(255, 255, 255, 0.35 * ring)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.restore();
    // Soft glow behind the mark, then the mark itself.
    canvas.drawCircle(
      c,
      r * 0.8 * mark,
      Paint()
        ..shader = RadialGradient(colors: [C.accent.withValues(alpha: 0.35 * mark), C.accent.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: r * 0.8)),
    );
    final s = mark.clamp(0.0, 1.2);
    final path = Path()
      ..moveTo(c.dx - r * 0.22 * s, c.dy - r * 0.38 * s)
      ..lineTo(c.dx + r * 0.46 * s, c.dy)
      ..lineTo(c.dx - r * 0.22 * s, c.dy + r * 0.38 * s)
      ..close();
    canvas.drawPath(path, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.ring != ring || old.mark != mark || old.t != t;
}
