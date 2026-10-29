import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'backend.dart';
import 'config.dart';
import 'input_mode.dart';
import 'screens/intro.dart';
import 'start.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  InputMode.init();
  await Store.init();
  await Backend.init();
  // Keep memory low on TV sticks with 1 GB of RAM.
  PaintingBinding.instance.imageCache.maximumSize = 300;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;
  // The remote is the main input: always show which element has focus.
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  runApp(const TeleApp());
}

class TeleApp extends StatelessWidget {
  const TeleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      navigatorKey: navigatorKey,
      // Any touch switches the player to touch controls; any key switches back to remote hints.
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => InputMode.remote = false,
        child: child ?? const SizedBox(),
      ),
      // Short start animation, then the app.
      home: IntroGate(next: startScreen()),
    );
  }
}
