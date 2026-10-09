import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'theme.dart' show log;

/// Address of the B1G website backend (WordPress plugin "B1G App Platform").
/// Override at build time with --dart-define=B1G_API_BASE=https://yoursite.com/wp-json/b1g/v1
const String kApiBase = String.fromEnvironment(
  'B1G_API_BASE',
  defaultValue: 'https://iptvuk.my.bestiptvuk-4k.com/wp-json/b1g/v1',
);

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
  });

  final int id;
  final String name;
  final String type; // "m3u" | "xtream"
  final String url;
  final String username;
  final String password;
  final String epgUrl;

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
    );
  }
}

/// Talks to the B1G website: device registration, licence status,
/// activation codes and remote playlists.
class Backend {
  static SharedPreferences? _p;
  static Future<bool>? _registering;

  static String deviceId = '';
  static String pairingCode = '';

  // Cached licence (so the app also works offline).
  static String licStatus = ''; // trial | active | expired | suspended | ''
  static String licType = '';
  static int licDaysLeft = 0;
  static DateTime? licChecked;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    deviceId = _p!.getString('b1g_device_id') ?? '';
    pairingCode = _p!.getString('b1g_pairing') ?? '';
    licStatus = _p!.getString('b1g_lic_status') ?? '';
    licType = _p!.getString('b1g_lic_type') ?? '';
    licDaysLeft = _p!.getInt('b1g_lic_days') ?? 0;
    final ms = _p!.getInt('b1g_lic_checked') ?? 0;
    licChecked = ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  static bool get registered => deviceId.isNotEmpty && pairingCode.isNotEmpty;

  /// The link the QR code encodes: opens the website with this device already
  /// connected, so the playlist can be added from a phone.
  static String get uploadUrl =>
      '$kSiteBase/upload-playlist/?device_id=$deviceId&pairing_code=$pairingCode';

  static String get activationUrl => '$kSiteBase/activation/?device_id=$deviceId';

  /// May the app run? Expired/suspended lock the app; everything else —
  /// including "no answer from the server yet" — keeps it open.
  static bool get allowed => licStatus != 'expired' && licStatus != 'suspended';

  static String get statusLine {
    switch (licStatus) {
      case 'trial':
        return licDaysLeft > 0 ? 'Trial · $licDaysLeft days left' : 'Trial';
      case 'active':
        return licType == 'lifetime'
            ? 'Activated · Lifetime'
            : (licDaysLeft > 0 ? 'Activated · $licDaysLeft days left' : 'Activated');
      case 'expired':
        return 'Licence expired';
      case 'suspended':
        return 'Device suspended';
      default:
        return '';
    }
  }

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
    licStatus = (d['status'] ?? '').toString();
    licType = (d['licence_type'] ?? '').toString();
    licDaysLeft = int.tryParse((d['days_left'] ?? 0).toString()) ?? 0;
    licChecked = DateTime.now();
    await _p?.setString('b1g_lic_status', licStatus);
    await _p?.setString('b1g_lic_type', licType);
    await _p?.setInt('b1g_lic_days', licDaysLeft);
    await _p?.setInt('b1g_lic_checked', licChecked!.millisecondsSinceEpoch);
  }

  // ---- API ----

  /// Registers the device once; later calls return at once.
  static Future<bool> ensureRegistered() {
    if (registered) return Future.value(true);
    return _registering ??= _register().whenComplete(() => _registering = null);
  }

  static Future<bool> _register() async {
    try {
      final data = await _post('/device/register', {
        'platform': Platform.isAndroid ? 'android-tv' : Platform.operatingSystem,
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
