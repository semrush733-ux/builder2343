import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:b1gtv/screens/home.dart';
import 'package:b1gtv/screens/intro.dart';
import 'package:b1gtv/screens/login.dart';
import 'package:b1gtv/store.dart';
import 'package:b1gtv/backend.dart';
import 'package:b1gtv/theme.dart';
import 'package:b1gtv/xtream.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSource implements Source {
  @override
  String get label => 'demo.provider.tv';
  @override
  Future<XAccount> login() async => XAccount(status: 'Active', expires: DateTime(2027, 3, 14));
  @override
  Future<List<XCategory>> categories(XKind kind) async => const [];
  @override
  Future<List<XItem>> items(XKind kind, {String? categoryId}) async => const [];
  @override
  Future<XSeriesInfo> seriesInfo(String seriesId) async => const XSeriesInfo(plot: '', cover: '', genre: '', seasons: {});
  @override
  Future<XMovieInfo> movieInfo(XItem item) async => const XMovieInfo();
  @override
  Future<List<XEpg>> shortEpg(String streamId) async => const [];
  @override
  Future<List<XEpg>> fullEpg(String epgId) async => const [];
  @override
  List<String> liveUrlsFor(XItem item, String preferredFormat) => const [];
  @override
  String movieUrlFor(XItem item) => '';
  @override
  String episodeUrlFor(XEpisode episode) => '';
}

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File(f);
      if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
  }

  final fonts = '$root/bin/cache/artifacts/material_fonts';
  await load('Roboto', ['$fonts/Roboto-Regular.ttf', '$fonts/Roboto-Bold.ttf', '$fonts/Roboto-Medium.ttf']);
  await load('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
}

Future<void> _shot(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('shots').createSync(recursive: true);
    File('shots/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Widget _app(GlobalKey key, Widget home) => RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme().copyWith(
            textTheme: buildTheme().textTheme.apply(fontFamily: 'Roboto', bodyColor: C.text, displayColor: C.text)),
        home: home,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    await Backend.init();
  });

  Future<void> size(WidgetTester t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1.5; // 1280 x 720 logical, like a TV
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  testWidgets('shots', skip: Platform.environment['SHOTS'] != '1', (t) async {
    await size(t);
    final key = GlobalKey();

    await t.pumpWidget(_app(key, const IntroGate(next: SizedBox())));
    await t.pump(const Duration(milliseconds: 1500));
    await _shot(t, key, '1-intro');
    await t.pump(const Duration(seconds: 3));

    final k2 = GlobalKey();
    await t.pumpWidget(_app(k2, const LoginScreen()));
    await t.pump(const Duration(milliseconds: 500));
    await _shot(t, k2, '2-login-xtream');
    await t.tap(find.text('M3U / URL'));
    await t.pump(const Duration(milliseconds: 500));
    await _shot(t, k2, '3-login-m3u');
    await t.tap(find.text('MAG'));
    await t.pump(const Duration(milliseconds: 500));
    await _shot(t, k2, '4-login-mag');
    await t.tap(find.text('QR'));
    await t.pump(const Duration(milliseconds: 800));
    await _shot(t, k2, '5-login-qr');

    final k3 = GlobalKey();
    await t.pumpWidget(_app(k3, HomeScreen(api: _FakeSource())));
    await t.pump(const Duration(milliseconds: 1200));
    await _shot(t, k3, '6-home');
    await t.pumpWidget(const SizedBox());
  });
}
