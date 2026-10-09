import 'package:flutter/services.dart';

/// Remembers whether the app is being used with a remote / keyboard or by touch,
/// so the player can show the right controls for each.
class InputMode {
  static bool remote = false;
  static bool _started = false;

  static void init() {
    if (_started) return;
    _started = true;
    HardwareKeyboard.instance.addHandler((KeyEvent event) {
      remote = true;
      return false; // never swallow the key
    });
  }
}
