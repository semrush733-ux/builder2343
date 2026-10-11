import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform, ValueNotifier;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// One saved VPN (a WireGuard configuration from the customer's VPN provider).
class VpnProfile {
  const VpnProfile(this.name, this.config);
  final String name;
  final String config;

  Map<String, String> toJson() => {'n': name, 'c': config};
  static VpnProfile? fromJson(dynamic j) {
    if (j is! Map) return null;
    final c = (j['c'] ?? '').toString();
    if (c.isEmpty) return null;
    return VpnProfile((j['n'] ?? 'VPN').toString(), c);
  }

  /// "Endpoint = host:port" from the configuration, to show which server it is.
  String get server {
    final m = RegExp(r'^\s*Endpoint\s*=\s*(\S+)', multiLine: true, caseSensitive: false).firstMatch(config);
    return m?.group(1) ?? '';
  }
}

/// Settings › VPN: saved WireGuard profiles and the tunnel for the whole TV (Android only).
class Vpn {
  static const _ch = MethodChannel('b1g/device');
  static bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// "up" or "down", kept current for the screens that show it.
  static final ValueNotifier<String> state = ValueNotifier('down');
  static String activeName = '';

  static Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  static Future<List<VpnProfile>> profiles() async {
    final raw = (await _p).getString('vpn_profiles') ?? '[]';
    try {
      final list = jsonDecode(raw);
      if (list is List) return list.map(VpnProfile.fromJson).whereType<VpnProfile>().toList();
    } catch (_) {}
    return [];
  }

  static Future<void> _save(List<VpnProfile> list) async =>
      (await _p).setString('vpn_profiles', jsonEncode([for (final p in list) p.toJson()]));

  static Future<void> add(VpnProfile p) async {
    final list = await profiles();
    list.removeWhere((x) => x.name == p.name);
    list.add(p);
    await _save(list);
  }

  static Future<void> remove(String name) async {
    final list = await profiles();
    list.removeWhere((x) => x.name == name);
    await _save(list);
  }

  /// Empty when the text is a valid WireGuard configuration, else the reason.
  static Future<String> check(String text) async {
    if (!available) return 'VPN works in the Android app.';
    try {
      return await _ch.invokeMethod<String>('vpnCheck', text) ?? '';
    } catch (e) {
      return 'Could not read this configuration.';
    }
  }

  static Future<void> refresh() async {
    if (!available) return;
    try {
      state.value = await _ch.invokeMethod<String>('vpnState') ?? 'down';
    } catch (_) {}
  }

  /// Starts the VPN. Returns an error text, or empty when connected.
  static Future<String> connect(VpnProfile p) async {
    if (!available) return 'VPN works in the Android app.';
    try {
      final r = await _ch.invokeMethod<Map<dynamic, dynamic>>('vpnUp', p.config) ?? const {};
      if (r['ok'] == true) {
        activeName = p.name;
        state.value = 'up';
        (await _p).setString('vpn_active', p.name);
        return '';
      }
      return (r['error'] ?? 'The VPN could not start.').toString();
    } catch (e) {
      return 'The VPN could not start.';
    }
  }

  static Future<String> disconnect() async {
    if (!available) return '';
    try {
      final r = await _ch.invokeMethod<Map<dynamic, dynamic>>('vpnDown') ?? const {};
      state.value = 'down';
      return r['ok'] == true ? '' : (r['error'] ?? '').toString();
    } catch (_) {
      return 'The VPN could not be stopped.';
    }
  }

  static Future<String> lastUsed() async => (await _p).getString('vpn_active') ?? '';

  /// Downloads a configuration from a link (the provider's .conf address).
  static Future<String> download(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw const FormatException('The link must start with http:// or https://');
    }
    final r = await http.get(uri).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw FormatException('The link answered with an error (${r.statusCode}).');
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }
}
