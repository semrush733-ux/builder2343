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
  static bool get loggedIn => (_p.getBool('logged_in') ?? false) && server.isNotEmpty && username.isNotEmpty;

  static Future<void> saveSession(String server, String username, String password) async {
    await _p.setString('server', server);
    await _p.setString('username', username);
    await _p.setString('password', password);
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
  /// Stream format that worked last time for live channels: "ts" or "m3u8".
  static String get liveFormat => _p.getString('live_format') == 'm3u8' ? 'm3u8' : 'ts';

  static void setLiveFormat(String format) {
    if (format != liveFormat) _p.setString('live_format', format);
  }
}
