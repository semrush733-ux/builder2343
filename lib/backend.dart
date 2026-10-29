import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart' show log;
import 'tmdb.dart' show Tmdb;

/// 2060 Tele Player has no website or licence: everything stays on the device.
const String kSiteBase = '';

class BackendException implements Exception {
  BackendException(this.message, [this.statusCode = 0]);
  final String message;
  final int statusCode;
  @override
  String toString() => message;
}

/// A playlist saved on this device: an M3U link, an Xtream Codes login or a MAG (Stalker) portal.
class BPlaylist {
  BPlaylist({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    this.username = '',
    this.password = '',
    this.epgUrl = '',
    this.pinHash = '',
    this.mac = '',
  });

  final int id;
  final String name;
  final String type; // "m3u" | "xtream" | "mag"
  final String url;
  final String username;
  final String password;
  final String epgUrl;
  final String pinHash;

  /// MAG portals: the box address (MAC) the portal knows this device by.
  final String mac;

  bool get locked => pinHash.isNotEmpty;
  bool get isXtream => type == 'xtream';
  bool get isMag => type == 'mag';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'url': url,
        'username': username,
        'password': password,
        'epg_url': epgUrl,
        'pin_hash': pinHash,
        'mac': mac,
      };

  static BPlaylist? fromJson(dynamic j) {
    if (j is! Map) return null;
    final url = (j['url'] ?? '').toString();
    if (url.isEmpty) return null;
    final type = (j['type'] ?? 'm3u').toString();
    return BPlaylist(
      id: int.tryParse(j['id'].toString()) ?? 0,
      name: (j['name'] ?? 'Playlist').toString(),
      type: type == 'xtream' ? 'xtream' : (type == 'mag' ? 'mag' : 'm3u'),
      url: url,
      username: (j['username'] ?? '').toString(),
      password: (j['password'] ?? '').toString(),
      epgUrl: (j['epg_url'] ?? '').toString(),
      pinHash: (j['pin_hash'] ?? '').toString(),
      mac: (j['mac'] ?? '').toString(),
    );
  }
}

/// A server address without "http://" and trailing slash, for comparing two spellings of one address.
String bareServer(String url) =>
    url.trim().toLowerCase().replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/+$'), '');

/// True for a network card's own address. False for the "02:00:00:00:00:00" placeholder newer
/// Android versions hand out, for empty or broadcast addresses, and for the made-up privacy
/// addresses (locally administered) that differ from one Wi-Fi network to the next.
bool isRealMac(String mac) {
  final m = mac.trim().toUpperCase();
  if (!RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(m)) return false;
  if (m == '02:00:00:00:00:00' || m == '00:00:00:00:00:00' || m == 'FF:FF:FF:FF:FF:FF') return false;
  return (int.parse(m.substring(0, 2), radix: 16) & 0x02) == 0;
}

/// The identifiers sent once with the registration, so the website recognises the same TV after
/// the app was removed and installed again (same device ID, pairing code and licence).
Map<String, String> registrationIds(dynamic fromDevice) {
  final out = <String, String>{};
  if (fromDevice is! Map) return out;
  final hwid = (fromDevice['hwid'] ?? '').toString().trim();
  if (hwid.isNotEmpty) out['hwid'] = hwid;
  final macs = fromDevice['macs'];
  if (macs is List) {
    for (final raw in macs) {
      final mac = raw.toString().trim().toUpperCase();
      if (isRealMac(mac)) {
        out['mac'] = mac;
        break;
      }
    }
  }
  return out;
}

/// A newer version of the app, announced by the website.
class BUpdate {
  BUpdate({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    this.notes = '',
    this.force = false,
  });

  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String notes;

  /// The app cannot be used until it is updated.
  final bool force;

  static BUpdate? fromJson(dynamic j) {
    if (j is! Map) return null;
    final code = int.tryParse((j['version_code'] ?? '').toString()) ?? 0;
    final url = (j['apk_url'] ?? '').toString().trim();
    if (code <= 0 || !url.startsWith('http')) return null;
    final force = j['force'];
    return BUpdate(
      versionCode: code,
      versionName: (j['version_name'] ?? '').toString().trim(),
      apkUrl: url,
      notes: (j['notes'] ?? '').toString().trim(),
      force: force == true || force == 1 || force == '1' || force == 'true',
    );
  }
}

/// Talks to the B1G website: device registration, licence status,
/// activation codes, remote playlists, the default server and app updates.
class Backend {
  static Uri webUri(Uri uri) => uri;
  static String webUrl(String url) => url;
  static List<String> playable(List<String> urls) => urls;

  static SharedPreferences? _p;
  static const _device = MethodChannel('b1g/device');

  /// Kept so screens that listen for changes still compile; nothing changes it any more.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static String serverUrl = '';
  static String serverName = '';
  static BUpdate? update;
  static int appVersionCode = 0;
  static String appVersionName = '';
  static bool get updateAvailable => false;

  static String deviceId = '';
  static String pairingCode = '';
  static String licStatus = 'active';
  static String licType = '';
  static int licDaysLeft = 0;
  static DateTime? licChecked;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    try {
      final v = await _device.invokeMethod<dynamic>('appVersion');
      if (v is Map) {
        appVersionCode = int.tryParse((v['code'] ?? 0).toString()) ?? 0;
        appVersionName = (v['name'] ?? '').toString();
      }
    } catch (_) {}
  }

  static Future<String> cacheDir() async => (await _device.invokeMethod<String>('cacheDir')) ?? '';
  static Future<bool> canInstall() async => false;
  static Future<bool> installApk(String path) async => false;

  static bool get registered => true;
  static String get uploadUrl => '';
  static String get activationUrl => '';
  static bool get allowed => true;
  static String get statusLine => '';

  static Future<void> loadConfig() async {}
  static Future<bool> ensureRegistered() async => true;
  static Future<void> refreshStatus() async {}
  static Future<String?> activate(String code) async => null;
  static Future<Map<String, String>?> vpnFromSite() async => null;

  static Future<void> clearAppCache() async {
    final images = PaintingBinding.instance.imageCache;
    images.clear();
    images.clearLiveImages();
    Tmdb.clearCache();
    try {
      await _device.invokeMethod<dynamic>('clearCache');
    } catch (_) {}
    log('cache cleared');
  }

  // ---- playlists saved on this device ----

  static Future<List<BPlaylist>> playlists() async {
    final p = _p ?? await SharedPreferences.getInstance();
    final out = <BPlaylist>[];
    for (final raw in p.getStringList('tp_playlists') ?? const <String>[]) {
      try {
        final pl = BPlaylist.fromJson(jsonDecode(raw));
        if (pl != null) out.add(pl);
      } catch (_) {}
    }
    return out;
  }

  static Future<void> _write(List<BPlaylist> list) async {
    final p = _p ?? await SharedPreferences.getInstance();
    await p.setStringList('tp_playlists', [for (final e in list) jsonEncode(e.toJson())]);
  }

  /// Saves (or replaces, same type + address + user) a playlist.
  static Future<void> savePlaylist(BPlaylist pl) async {
    final all = await playlists();
    all.removeWhere((e) => e.type == pl.type && e.url == pl.url && e.username == pl.username);
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    all.insert(
        0,
        BPlaylist(
            id: id,
            name: pl.name,
            type: pl.type,
            url: pl.url,
            username: pl.username,
            password: pl.password,
            epgUrl: pl.epgUrl,
            mac: pl.mac));
    await _write(all);
  }

  static Future<void> removePlaylist(BPlaylist pl) async {
    final all = await playlists();
    all.removeWhere((e) => e.id == pl.id);
    await _write(all);
  }
}
