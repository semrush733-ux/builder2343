import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

/// One Wi-Fi network found by a scan.
class WifiNet {
  const WifiNet(this.ssid, this.level, this.secured, this.band);
  final String ssid;
  final int level; // 0..4 bars
  final bool secured;
  final String band;
}

/// What the TV is connected to right now.
class NetInfo {
  const NetInfo({
    this.type = 'none',
    this.ssid = '',
    this.level = 0,
    this.ip = '',
    this.linkMbps = 0,
    this.frequency = 0,
    this.canJoin = false,
    this.location = false,
    this.wifiOn = false,
  });
  final String type; // wifi | ethernet | mobile | other | none
  final String ssid;
  final int level;
  final String ip;
  final int linkMbps;
  final int frequency;
  final bool canJoin; // Android 9 and older: the app may join a network itself
  final bool location;
  final bool wifiOn;
}

/// Settings › Network, talking to NetHelper on the Android side.
class Net {
  static const _ch = MethodChannel('b1g/device');
  static bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static int _i(Object? v) => v is num ? v.toInt() : 0;

  static Future<NetInfo> info() async {
    if (!available) return const NetInfo();
    try {
      final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('netInfo') ?? const {};
      return NetInfo(
        type: (m['type'] ?? 'none').toString(),
        ssid: (m['ssid'] ?? '').toString(),
        level: _i(m['level']),
        ip: (m['ip'] ?? '').toString(),
        linkMbps: _i(m['linkMbps']),
        frequency: _i(m['frequency']),
        canJoin: m['canJoin'] == true,
        location: m['location'] == true,
        wifiOn: m['wifiOn'] == true,
      );
    } catch (_) {
      return const NetInfo();
    }
  }

  /// Null when the location permission is missing (needed for Wi-Fi scans on Android).
  static Future<List<WifiNet>?> scan() async {
    if (!available) return const [];
    try {
      final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('wifiScan') ?? const {};
      if (m['permission'] == false) return null;
      final list = m['list'];
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map)
            WifiNet((e['ssid'] ?? '').toString(), _i(e['level']), e['secured'] == true, (e['band'] ?? '').toString()),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> askPermission() async {
    try {
      await _ch.invokeMethod<void>('wifiPermission');
    } catch (_) {}
  }

  /// "joining", "settings" (newer Android: the TV's Wi-Fi page was opened) or "failed".
  static Future<String> join(String ssid, String password, bool secured) async {
    try {
      return await _ch.invokeMethod<String>('wifiJoin', {'ssid': ssid, 'password': password, 'secured': secured}) ??
          'failed';
    } catch (_) {
      return 'failed';
    }
  }

  static Future<void> openSettings() async {
    try {
      await _ch.invokeMethod<void>('wifiSettings');
    } catch (_) {}
  }
}
