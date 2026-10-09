import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'xtream.dart';

/// Small on-device storage: login, favourites, resume positions.
class Store {
  static late SharedPreferences _p;
  static final Map<XKind, List<XItem>> _fav = {};
  static Map<String, int>? _resume;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    _fav.clear();
    _resume = null;
  }

  // ---- login ----
  static String get server => _p.getString('server') ?? '';
  static String get username => _p.getString('username') ?? '';
  static String get password => _p.getString('password') ?? '';

  /// Address of the M3U playlist when the app is used with a playlist link.
  static String get m3uUrl => _p.getString('m3u_url') ?? '';

  /// XMLTV guide address for that playlist (set on the website, may be empty).
  static String get m3uEpgUrl => _p.getString('m3u_epg_url') ?? '';

  /// True when the saved login is an M3U playlist link, false for Xtream Codes.
  static bool get isM3u => _p.getString('mode') == 'm3u';

  static bool get loggedIn {
    if (!(_p.getBool('logged_in') ?? false)) return false;
    return isM3u ? m3uUrl.isNotEmpty : (server.isNotEmpty && username.isNotEmpty);
  }

  /// Favourites and resume positions belong to one account: a different
  /// account starts clean.
  static Future<void> _switchAccount(String identity) async {
    if (_p.getString('identity') == identity) return;
    for (final kind in XKind.values) {
      await _p.remove('fav_${kind.name}');
    }
    await _p.remove('resume');
    _fav.clear();
    _resume = null;
    await _p.setString('identity', identity);
  }

  /// True when the saved login used the server address from the B1G website (the customer typed
  /// only username and password). Such a login follows the website when the address changes there.
  static bool get viaSite => _p.getBool('via_site') ?? false;

  static Future<void> saveSession(String server, String username, String password, {bool viaSite = false}) async {
    await _switchAccount('xtream|$server|$username');
    await _p.setString('mode', 'xtream');
    await _p.setString('server', server);
    await _p.setString('username', username);
    await _p.setString('password', password);
    await _p.setBool('via_site', viaSite);
    await _p.setBool('logged_in', true);
  }

  /// The provider moved to a new address: same account, so favourites and resume positions stay.
  static Future<void> moveServer(String server) async {
    await _p.setString('server', server);
    await _p.setString('identity', 'xtream|$server|$username');
  }

  static Future<void> saveM3uSession(String url, {String epgUrl = ''}) async {
    await _switchAccount('m3u|$url');
    await _p.setString('mode', 'm3u');
    await _p.setString('m3u_url', url);
    await _p.setString('m3u_epg_url', epgUrl);
    await _p.setBool('logged_in', true);
  }

  /// Keeps server and username so the next login is quicker.
  static Future<void> logout() async {
    await _p.remove('password');
    await _p.setBool('logged_in', false);
  }

  // ---- favourites ----
  static List<XItem> favourites(XKind kind) {
    final cached = _fav[kind];
    if (cached != null) return cached;
    final list = <XItem>[];
    for (final raw in _p.getStringList('fav_${kind.name}') ?? const <String>[]) {
      try {
        final item = XItem.fromJson(jsonDecode(raw));
        if (item != null) list.add(item);
      } catch (_) {}
    }
    _fav[kind] = list;
    return list;
  }

  static bool isFavourite(XItem item) => favourites(item.kind).any((f) => f.id == item.id);

  /// Returns true when the item is a favourite after the call.
  static bool toggleFavourite(XItem item) {
    final list = favourites(item.kind);
    final index = list.indexWhere((f) => f.id == item.id);
    if (index >= 0) {
      list.removeAt(index);
    } else {
      list.insert(0, item);
    }
    _p.setStringList('fav_${item.kind.name}', list.map((f) => jsonEncode(f.toJson())).toList());
    return index < 0;
  }

  // ---- resume positions (seconds) ----
  static Map<String, int> _loadResume() {
    final cached = _resume;
    if (cached != null) return cached;
    final map = <String, int>{};
    try {
      final data = jsonDecode(_p.getString('resume') ?? '{}');
      if (data is Map) {
        data.forEach((k, v) {
          if (v is int) map[k.toString()] = v;
        });
      }
    } catch (_) {}
    _resume = map;
    return map;
  }

  static int resume(String key) => _loadResume()[key] ?? 0;

  static void setResume(String key, int seconds) {
    final map = _loadResume();
    map.remove(key);
    if (seconds > 0) {
      map[key] = seconds; // newest last
      while (map.length > 300) {
        map.remove(map.keys.first);
      }
    }
    _p.setString('resume', jsonEncode(map));
  }

  // ---- playback ----
  /// Audio language picked last time (ISO code such as "eng"); empty = the stream's default.
  static String get audioLanguage => _p.getString('audio_lang') ?? '';
  static void setAudioLanguage(String code) => _p.setString('audio_lang', code);

  /// How the picture is drawn: "gpu" (standard, works with every video format) or "direct"
  /// (the device's hardware decoder draws straight to the screen: lightest for weak TV sticks,
  /// and the fallback when the standard way cannot start on a device).
  static String get videoMode => _p.getString('video_mode') == 'direct' ? 'direct' : 'gpu';
  static void setVideoMode(String mode) => _p.setString('video_mode', mode);

  /// Subtitle language picked last time; empty = subtitles off.
  static String get subtitleLanguage => _p.getString('sub_lang') ?? '';
  static void setSubtitleLanguage(String code) => _p.setString('sub_lang', code);

  /// Stream format that worked last time for live channels: "ts" or "m3u8".
  static String get liveFormat => _p.getString('live_format') == 'm3u8' ? 'm3u8' : 'ts';

  static void setLiveFormat(String format) {
    if (format != liveFormat) _p.setString('live_format', format);
  }
}
