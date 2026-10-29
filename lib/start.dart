import 'package:flutter/material.dart';

import 'm3u.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'stalker.dart';
import 'store.dart';
import 'xtream.dart';

/// The app's one navigator.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// The screen the app opens on: home with the saved login, or the sign-in screen.
Widget startScreen() {
  if (!Store.loggedIn) return const LoginScreen();
  if (Store.isMag) return HomeScreen(api: StalkerSource(Store.magPortal, Store.magMac));
  if (Store.isM3u) return HomeScreen(api: M3uSource(Store.m3uUrl, epgUrl: Store.m3uEpgUrl));
  return HomeScreen(api: XtreamApi(Store.server, Store.username, Store.password));
}
