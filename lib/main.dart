import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'config.dart';
import 'input_mode.dart';
import 'm3u.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'store.dart';
import 'theme.dart';
import 'xtream.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  InputMode.init();
  await Store.init();
  // Keep memory low on TV sticks with 1 GB of RAM.
  PaintingBinding.instance.imageCache.maximumSize = 300;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;
  // The remote is the main input: always show which element has focus.
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  runApp(const B1GApp());
}

class B1GApp extends StatelessWidget {
  const B1GApp({super.key});

  @override
  Widget build(BuildContext context) {
    final Source source =
        Store.isM3u ? M3uSource(Store.m3uUrl) : XtreamApi(Store.server, Store.username, Store.password);
    final Widget home = Store.loggedIn ? HomeScreen(api: source) : const LoginScreen();
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Any touch switches the player to touch controls; any key switches back to remote hints.
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => InputMode.remote = false,
        child: child,
      ),
      home: home,
    );
  }
}
