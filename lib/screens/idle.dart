import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Shown when nobody has touched the app for a while: a big clock on the moving background.
/// Any key or touch brings the app back.
class IdleScreen extends StatefulWidget {
  const IdleScreen({super.key});

  @override
  State<IdleScreen> createState() => _IdleScreenState();
}

class _IdleScreenState extends State<IdleScreen> {
  Timer? _tick;
  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    HardwareKeyboard.instance.addHandler(_key);
  }

  bool _key(KeyEvent e) {
    if (e is KeyDownEvent && mounted) {
      Navigator.of(context).maybePop();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DateTime.now();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: Aurora(strength: 1.3)),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Logo(),
                  const SizedBox(height: 28),
                  ShaderMask(
                    shaderCallback: (r) => LinearGradient(colors: [Ui.c1, Ui.c2, Ui.c3]).createShader(r),
                    child: Text(Ui.hm(t), style: const TextStyle(fontSize: 96, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                  Text('${_days[t.weekday - 1]}, ${t.day} ${_months[t.month - 1]} ${t.year}',
                      style: const TextStyle(fontSize: 20, color: C.dim)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
