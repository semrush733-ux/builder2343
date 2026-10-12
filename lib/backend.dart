import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'theme.dart' show log;
import 'tmdb.dart' show Tmdb;

/// Address of the B1G website backend (WordPress plugin "B1G App Platform").
/// Override at build time with --dart-define=B1G_API_BASE=https://yoursite.com/wp-json/b1g/v1
const String kDefaultApiBase = String.fromEnvironment(
  'B1G_API_BASE',
  defaultValue: 'https://playercloud.app/wp-json/b1g/v1',
);

/// The address in use: the built-in one, or a newer one the website told the app to move to.
String get kApiBase => Backend.apiBase;

/// The website address itself (used for the QR / activation links).
String get kSiteBase {
  final i = kApiBase.indexOf('/wp-json/');
  return i > 0 ? kApiBase.substring(0, i) : kApiBase;
}

/// How long the app keeps working on the cached licence when the backend
/// cannot be reached. After that it still fails OPEN (never brick a TV just
/// because a server is down) but asks for a connection on the lock screen.
const Duration kLicenceGrace = Duration(hours: 72);

class BackendException implements Exception {
  BackendException(this.message, [this.statusCode = 0]);
  final String message;
  final int statusCode;
  @override
  String toString() => message;
}

/// A playlist managed on the website (added by us for the client, or by the
/// client through the QR link).
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
  });

  final int id;
  final String name;
  final String type; // "m3u" | "xtream"
  final String url;
  final String username;
  final String password;
  final String epgUrl;

  /// Set when the playlist is locked on the website with a 4-digit PIN (sha256 of "b1g-pin:" + PIN).
  final String pinHash;

  bool get locked => pinHash.isNotEmpty;

  bool get isXtream => type == 'xtream';

  static BPlaylist? fromJson(dynamic j) {
    if (j is! Map) return null;
    final url = (j['url'] ?? '').toString();
    if (url.isEmpty) return null;
    return BPlaylist(
      id: int.tryParse(j['id'].toString()) ?? 0,
      name: (j['name'] ?? 'Playlist').toString(),
      type: (j['type'] ?? 'm3u').toString() == 'xtream' ? 'xtream' : 'm3u',
      url: url,
      username: (j['username'] ?? '').toString(),
      password: (j['password'] ?? '').toString(),
      epgUrl: (j['epg_url'] ?? '').toString(),
      pinHash: (j['pin_hash'] ?? '').toString(),
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
  /// Browser version only: IPTV servers are plain http and send no CORS headers, so a browser
  /// on the https website cannot call them. The website fetches them instead (b1g/v1/relay).
  /// Android / TV builds talk to the server directly and get the address back unchanged.
  static String webUrl(String url) {
    if (!kIsWeb || deviceId.isEmpty) return url;
    if (!(url.startsWith('http://') || url.startsWith('https://'))) return url;
    if (url.startsWith(kApiBase)) return url;
    return '$kApiBase/relay?d=${Uri.encodeQueryComponent(deviceId)}&u=${Uri.encodeQueryComponent(url)}';
  }

  static Uri webUri(Uri uri) => kIsWeb ? Uri.parse(webUrl(uri.toString())) : uri;

  /// Stream addresses as the player should try them. On Android / TV: unchanged.
  /// In a browser an endless MPEG-TS live stream cannot play, so live channels use their HLS
  /// (.m3u8) address instead, and everything goes through the website relay (the IPTV server
  /// is plain http without CORS, which an https page may not load).
  static List<String> playable(List<String> urls) {
    if (!kIsWeb) return urls;
    final out = <String>[];
    void add(String u) {
      if (!out.contains(u)) out.add(u);
    }

    for (final u in urls) {
      final path = (Uri.tryParse(u)?.path ?? '').toLowerCase();
      if (path.endsWith('.m3u8')) add(u);
    }
    for (final u in urls) {
      final uri = Uri.tryParse(u);
      final path = (uri?.path ?? '').toLowerCase();
      if (path.endsWith('.m3u8')) continue;
      if (path.endsWith('.ts') && (path.contains('/live/') || !path.contains('/'))) {
        // Xtream serves every live channel as HLS too: same address, other ending.
        add(u.replaceFirst(RegExp(r'\.ts(?=$|\?)', caseSensitive: false), '.m3u8'));
      } else {
        add(u);
      }
    }
    return [for (final u in out) webUrl(u)];
  }

  static SharedPreferences? _p;

  /// Website API address; starts as the built-in one and follows a website move.
  static String apiBase = kDefaultApiBase;

  static bool _validBase(String v) =>
      v.startsWith('https://') && v.contains('/wp-json/') && Uri.tryParse(v)?.host.isNotEmpty == true;
  static Future<bool>? _registering;
  static const _device = MethodChannel('b1g/device');

  /// Counts up whenever something from the website changed (licence, default server, update),
  /// so screens can listen and redraw.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// The IPTV server set on the website. With it the sign-in screen only asks for
  /// username and password. Kept on the device so it also works without the website.
  static String serverUrl = '';
  static String serverName = '';

  /// The newest app version the website knows about (null: none announced).
  static BUpdate? update;

  /// This installation (from Android): versionCode and versionName.
  static int appVersionCode = 0;
  static String appVersionName = '';

  static bool get updateAvailable =>
      update != null && appVersionCode > 0 && update!.versionCode > appVersionCode;

  static String deviceId = '';
  static String pairingCode = '';

  // Cached licence (so the app also works offline).
  static String licStatus = ''; // trial | active | expired | suspended | ''
  static String licType = '';
  static int licDaysLeft = 0;
  static DateTime? licChecked;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    // A moved website is only followed for a build made for the same default address.
    final moved = _p!.getString('b1g_api_base') ?? '';
    final movedFrom = _p!.getString('b1g_api_base_from') ?? '';
    if (_validBase(moved) && movedFrom == kDefaultApiBase) apiBase = moved;
    deviceId = _p!.getString('b1g_device_id') ?? '';
    pairingCode = _p!.getString('b1g_pairing') ?? '';
    // Device IDs are "CLT-..." now; the website renamed the old "B1G-..." ones too.
    if (deviceId.startsWith('B1G-')) {
      deviceId = 'CLT-${deviceId.substring(4)}';
      await _p!.setString('b1g_device_id', deviceId);
    }
    licStatus = _p!.getString('b1g_lic_status') ?? '';
    licType = _p!.getString('b1g_lic_type') ?? '';
    licDaysLeft = _p!.getInt('b1g_lic_days') ?? 0;
    final ms = _p!.getInt('b1g_lic_checked') ?? 0;
    licChecked = ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    serverUrl = _p!.getString('b1g_server_url') ?? '';
    serverName = _p!.getString('b1g_server_name') ?? '';
    try {
      final v = await _device.invokeMethod<dynamic>('appVersion');
      if (v is Map) {
        appVersionCode = int.tryParse((v['code'] ?? 0).toString()) ?? 0;
        appVersionName = (v['name'] ?? '').toString();
      }
    } catch (_) {
      // Not on Android (tests): no update check.
    }
  }

  /// Folder for the downloaded update (inside the app's own cache).
  static Future<String> cacheDir() async => (await _device.invokeMethod<String>('cacheDir')) ?? '';

  /// May this app start an installation? (Android asks the customer once to allow it.)
  static Future<bool> canInstall() async {
    try {
      return (await _device.invokeMethod<bool>('canInstall')) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Hands the downloaded APK to Android's installer.
  static Future<bool> installApk(String path) async {
    try {
      return (await _device.invokeMethod<bool>('installApk', path)) ?? false;
    } catch (_) {
      return false;
    }
  }

  static bool get registered => deviceId.isNotEmpty && pairingCode.isNotEmpty;

  /// The link the QR code encodes: opens the website with this device already
  /// connected, so the playlist can be added from a phone.
  static String get uploadUrl =>
      '$kSiteBase/upload-playlist/?device_id=$deviceId&pairing_code=$pairingCode';

  static String get activationUrl => '$kSiteBase/activation/?device_id=$deviceId';

  /// Cloud Player is completely free: only a device suspended on the website is locked.
  static bool get allowed => licStatus != 'suspended';

  static String get statusLine => licStatus == 'suspended' ? 'Device suspended' : 'Free';

  // ---- HTTP helpers ----

  static Map<String, String> get _headers =>
      {'Content-Type': 'application/json', 'User-Agent': kUserAgent};

  static dynamic _decode(http.Response r) {
    dynamic data;
    try {
      data = jsonDecode(r.body);
    } catch (_) {
      throw BackendException('Unexpected answer from the server.', r.statusCode);
    }
    if (data is Map && data['success'] == true) return data;
    final message = (data is Map && data['message'] != null)
        ? data['message'].toString()
        : 'Request failed (${r.statusCode}).';
    throw BackendException(message, r.statusCode);
  }

  static Future<dynamic> _get(String path) async {
    final r = await http
        .get(Uri.parse('$kApiBase$path'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    return _decode(r);
  }

  static Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse('$kApiBase$path'), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    return _decode(r);
  }

  static Future<void> _storeStatus(dynamic d) async {
    if (d is! Map) return;
    final before = '$licStatus/$licType/$licDaysLeft';
    licStatus = (d['status'] ?? '').toString();
    licType = (d['licence_type'] ?? '').toString();
    licDaysLeft = int.tryParse((d['days_left'] ?? 0).toString()) ?? 0;
    licChecked = DateTime.now();
    await _p?.setString('b1g_lic_status', licStatus);
    await _p?.setString('b1g_lic_type', licType);
    await _p?.setInt('b1g_lic_days', licDaysLeft);
    await _p?.setInt('b1g_lic_checked', licChecked!.millisecondsSinceEpoch);
    if (before != '$licStatus/$licType/$licDaysLeft') changes.value++;
  }

  /// Reads the app settings from the website: the default IPTV server and the newest app version.
  /// A website without this route (older plugin) or without a connection changes nothing.
  static Future<void> loadConfig() async {
    try {
      final data = await _get('/app/config?platform=android-tv&version_code=$appVersionCode'
          '&device_id=${Uri.encodeQueryComponent(deviceId)}');
      final c = data['config'];
      if (c is Map) {
        final url = (c['server_url'] ?? '').toString().trim();
        final name = (c['server_name'] ?? '').toString().trim();
        if (url != serverUrl || name != serverName) {
          serverUrl = url;
          serverName = name;
          await _p?.setString('b1g_server_url', url);
          await _p?.setString('b1g_server_name', name);
        }
      }
      final moveTo = (c is Map ? c['api_base'] : null)?.toString().trim() ?? '';
      if (_validBase(moveTo) && moveTo != apiBase) {
        log('backend moved to a new website address');
        apiBase = moveTo;
        await _p?.setString('b1g_api_base', moveTo);
        await _p?.setString('b1g_api_base_from', kDefaultApiBase);
      }
      final epoch = int.tryParse((c is Map ? c['cache_epoch'] : null)?.toString() ?? '') ?? 0;
      if (epoch > 0 && epoch != (_p?.getInt('b1g_cache_epoch') ?? 0)) {
        await clearAppCache();
        await _p?.setInt('b1g_cache_epoch', epoch);
      }
      update = BUpdate.fromJson(data['update']);
      log('backend config server=${serverUrl.isEmpty ? 'none' : 'set'} '
          'update=${update?.versionCode ?? 0} app=$appVersionCode');
      changes.value++;
    } on BackendException catch (e) {
      log('backend config: ${e.statusCode}');
    } catch (e) {
      log('backend config failed: ${e.runtimeType}');
    }
  }

  /// "Clear app cache" from the website: pictures, channel logos, film details
  /// and downloaded files go; login, playlists, favourites and licence stay.
  static Future<void> clearAppCache() async {
    final images = PaintingBinding.instance.imageCache;
    images.clear();
    images.clearLiveImages();
    Tmdb.clearCache();
    try {
      await _device.invokeMethod<dynamic>('clearCache');
    } catch (_) {
      // Web / tests: there is no app cache folder.
    }
    log('cache cleared (website)');
  }

  // ---- API ----

  /// Registers the device once; later calls return at once.
  static Future<bool> ensureRegistered() {
    if (registered) return Future.value(true);
    return _registering ??= _register().whenComplete(() => _registering = null);
  }

  static Future<bool> _register() async {
    try {
      var ids = const <String, String>{};
      try {
        ids = registrationIds(await _device.invokeMethod<dynamic>('deviceIds'));
      } catch (_) {
        // Not available: register without them, as before.
      }
      log('backend register hwid=${ids.containsKey('hwid') ? 'yes' : 'no'} mac=${ids.containsKey('mac') ? 'yes' : 'no'}');
      final data = await _post('/device/register', {
        'platform': kIsWeb
            ? 'web'
            : (defaultTargetPlatform == TargetPlatform.android ? 'android-tv' : defaultTargetPlatform.name),
        ...ids,
      });
      final d = data['device'];
      if (d is! Map) return false;
      deviceId = (d['device_id'] ?? '').toString();
      pairingCode = (d['pairing_code'] ?? '').toString();
      if (!registered) return false;
      await _p?.setString('b1g_device_id', deviceId);
      await _p?.setString('b1g_pairing', pairingCode);
      await _storeStatus(d);
      log('backend registered');
      return true;
    } catch (e) {
      log('backend register failed: ${e.runtimeType}');
      return false;
    }
  }

  /// Refreshes the licence; on network trouble the cached status stays.
  static Future<void> refreshStatus() async {
    if (!registered && !await ensureRegistered()) return;
    try {
      final data =
          await _get('/device/status?device_id=$deviceId&pairing_code=$pairingCode');
      await _storeStatus(data['device']);
    } on BackendException catch (e) {
      // A definite server answer (e.g. device deleted) is respected; keep cache otherwise.
      log('backend status: ${e.message}');
    } catch (e) {
      log('backend status failed: ${e.runtimeType}');
    }
  }

  /// Redeems an activation code. Returns null on success, or an error message.
  static Future<String?> activate(String code) async {
    if (!registered && !await ensureRegistered()) {
      return 'No connection to the activation server. Please check the internet and try again.';
    }
    try {
      final data =
          await _post('/device/activate', {'device_id': deviceId, 'code': code.trim()});
      await _storeStatus(data['device']);
      return null;
    } on BackendException catch (e) {
      return e.message;
    } catch (_) {
      return 'No connection. Please check the internet and try again.';
    }
  }

  /// Playlists managed on the website for this device.
  /// Throws [BackendException] with a readable message (403 = licence needed).
  /// The VPN configuration saved for this TV on the website (Upload page › VPN), or null.
  static Future<Map<String, String>?> vpnFromSite() async {
    if (!registered && !await ensureRegistered()) {
      throw BackendException('No connection to the server.');
    }
    final data = await _get('/device/playlists?device_id=$deviceId&pairing_code=$pairingCode');
    final v = data is Map ? data['vpn'] : null;
    if (v is! Map) return null;
    final config = (v['config'] ?? '').toString();
    if (config.trim().isEmpty) return null;
    return {'name': (v['name'] ?? 'My VPN').toString(), 'config': config};
  }

  static Future<List<BPlaylist>> playlists() async {
    if (!registered && !await ensureRegistered()) {
      throw BackendException('No connection to the server.');
    }
    final data =
        await _get('/device/playlists?device_id=$deviceId&pairing_code=$pairingCode');
    await _storeStatus(data['device']);
    final out = <BPlaylist>[];
    final raw = data['playlists'];
    if (raw is List) {
      for (final j in raw) {
        final pl = BPlaylist.fromJson(j);
        if (pl != null) out.add(pl);
      }
    }
    return out;
  }
}
