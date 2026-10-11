import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine.dart';
import '../theme.dart';

/// The start animation with its sound (assets/intro.mp4, 5 seconds), shown once when the app
/// opens, then [next]. Any key or tap skips it. Where ExoPlayer is not available (web), or if the
/// video cannot play, the app goes straight on.
class IntroGate extends StatefulWidget {
  const IntroGate({super.key, required this.next});
  final Widget next;

  static bool _shown = false;

  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> {
  ExoEngine? _engine;
  bool _done = IntroGate._shown || !ExoEngine.available;
  bool _playing = false;
  Timer? _safety;
  StreamSubscription<bool>? _end;
  StreamSubscription<Duration>? _pos;
  final FocusNode _focus = FocusNode(debugLabel: 'intro');

  @override
  void initState() {
    super.initState();
    IntroGate._shown = true;
    if (!_done) _start();
  }

  Future<void> _start() async {
    // Never keep the customer waiting: the app opens after 7 s whatever happens.
    _safety = Timer(const Duration(seconds: 7), _finish);
    try {
      final e = await ExoEngine.create(live: false);
      if (!mounted || _done) {
        e.dispose();
        return;
      }
      _engine = e;
      _end = e.completed.listen((ended) {
        if (ended) _finish();
      });
      _pos = e.position.listen((p) {
        if (!_playing && p > Duration.zero && mounted) setState(() => _playing = true);
      });
      await e.open('asset:///flutter_assets/assets/intro.mp4', Duration.zero);
      if (mounted) setState(() {});
    } catch (_) {
      _finish();
    }
  }

  void _finish() {
    if (_done) return;
    _safety?.cancel();
    _end?.cancel();
    _pos?.cancel();
    final e = _engine;
    _engine = null;
    e?.dispose();
    if (mounted) setState(() => _done = true);
  }

  @override
  void dispose() {
    _safety?.cancel();
    _end?.cancel();
    _pos?.cancel();
    _engine?.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.next;
    final e = _engine;
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The logo in the middle until the first video frame is up (no black flash).
              Center(
                child: SizedBox(
                  width: 180,
                  height: 180,
                  child: Image.asset('assets/symbol.png', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox()),
                ),
              ),
              if (e != null)
                AnimatedOpacity(
                  opacity: _playing ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: e.view(fit: BoxFit.cover, subtitlePad: 0),
                ),
              const Positioned(
                right: 28,
                bottom: 22,
                child: Text('OK to skip', style: TextStyle(fontSize: 12.5, color: C.dim)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

