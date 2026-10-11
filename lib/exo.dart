import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'config.dart';

/// What the ExoPlayer screen hands back when the customer leaves it.
class ExoResult {
  const ExoResult(this.index, this.position, this.duration);
  final int index;
  final Duration position;
  final Duration duration;
}

/// The second player engine: Google's ExoPlayer (Media3), running natively on Android.
/// It is used when the main engine cannot play a stream, or when the customer picks it.
class Exo {
  static const _device = MethodChannel('b1g/device');

  /// Only the Android app has it (not the web or Samsung / LG versions).
  static bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Opens the ExoPlayer screen and waits until the customer comes back.
  /// [urls] holds the addresses of each channel / film (tried in order).
  static Future<ExoResult?> play({
    required List<String> titles,
    required List<List<String>> urls,
    required int index,
    required bool live,
    Duration start = Duration.zero,
  }) async {
    if (!available) return null;
    try {
      final r = await _device.invokeMethod<Map<dynamic, dynamic>>('playExo', {
        'titles': titles,
        'urls': [for (final u in urls) u.join('\n')],
        'index': index,
        'live': live,
        'startMs': start.inMilliseconds,
        'ua': kUserAgent,
      });
      if (r == null) return null;
      int n(Object? v) => v is num ? v.toInt() : 0;
      return ExoResult(
        n(r['index']),
        Duration(milliseconds: n(r['positionMs'])),
        Duration(milliseconds: n(r['durationMs'])),
      );
    } catch (_) {
      return null;
    }
  }
}
