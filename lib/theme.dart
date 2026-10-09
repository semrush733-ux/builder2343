import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFF0A0C10);
  static const panel = Color(0xFF11141B);
  static const card = Color(0xFF1A1E28);
  static const accent = Color(0xFFFFC400);
  static const text = Color(0xFFF2F4F8);
  static const dim = Color(0xFF8B93A3);
  static const danger = Color(0xFFFF6B6B);
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
    // No page animations: route changes stay instant on slow TV sticks.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: _NoTransitions(),
      TargetPlatform.iOS: _NoTransitions(),
    }),
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
  );
}

class _NoTransitions extends PageTransitionsBuilder {
  const _NoTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return child;
  }
}

void log(String message) => debugPrint('B1G $message');

/// The B1G wordmark.
class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 34});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * 0.32, vertical: size * 0.06),
      decoration: BoxDecoration(color: C.accent, borderRadius: BorderRadius.circular(size * 0.22)),
      child: Text(
        'B1G',
        style: TextStyle(
          color: Colors.black,
          fontSize: size,
          height: 1.15,
          fontWeight: FontWeight.w900,
          letterSpacing: size * 0.02,
        ),
      ),
    );
  }
}
