import 'package:flutter/material.dart';

import 'm3u.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'screens/profiles.dart';
import 'stalker.dart';
import 'store.dart';
import 'xtream.dart';

/// The app's one navigator.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// The screen the app opens on: home with the saved login, or the sign-in screen.
Widget startScreen() {
  if (!Store.loggedIn) return const LoginScreen();
  final Widget home;
  if (Store.isMag) {
    home = HomeScreen(api: StalkerSource(Store.magPortal, Store.magMac));
  } else if (Store.isM3u) {
    home = HomeScreen(api: M3uSource(Store.m3uUrl, epgUrl: Store.m3uEpgUrl));
  } else {
    home = HomeScreen(api: XtreamApi(Store.server, Store.username, Store.password));
  }
  // More than one profile: ask who is watching first.
  if (Store.profiles.length > 1 && !Store.profileChosen) return ProfilePickerScreen(next: (_) => home);
  Store.profileChosen = true;
  return home;
}
