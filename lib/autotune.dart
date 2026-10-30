import 'package:flutter/scheduler.dart';

import 'store.dart';

/// Looks at how smoothly this device draws the animated home screen, once, and switches the
/// app to Lite mode by itself when it struggles (old TV boxes). The customer can still pick
/// Smooth or Lite by hand in Settings.
class AutoTune {
  static bool _running = false;

  static void start() {
    if (_running || Store.tuned || Store.litePref != 'auto') return;
    _running = true;
    var seen = 0;
    var slow = 0;
    late TimingsCallback cb;
    cb = (List<FrameTiming> timings) {
      for (final t in timings) {
        seen++;
        if (seen <= 40) continue; // start-up frames are always slower
        if (t.totalSpan.inMilliseconds > 24) slow++;
      }
      if (seen >= 260) {
        SchedulerBinding.instance.removeTimingsCallback(cb);
        _running = false;
        Store.setAutoLite(slow / (seen - 40) > 0.3);
      }
    };
    SchedulerBinding.instance.addTimingsCallback(cb);
  }
}
