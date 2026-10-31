import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

import 'theme.dart' show Ui;
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'xtream.dart';

/// Small on-device storage: login, favourites, resume positions.
class Store {
  static late SharedPreferences _p;
  static final Map<XKind, List<XItem>> _fav = {};
  static Map<String, int>? _resume;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    _fav.clear();
    _recent.clear();
    _resume = null;
    Ui.clock24 = clock24;
    Ui.lite = liteMode;
    Ui.setTheme(theme);
  }

  // ---- profiles ----
  static List<Map<String, dynamic>> get profiles {
    try {
      final d = jsonDecode(_p.getString('profiles') ?? '');
      if (d is List && d.isNotEmpty) return [for (final e in d) Map<String, dynamic>.from(e as Map)];
    } catch (_) {}
    return [
      {'id': 'p1', 'name': 'Main', 'kids': false}
    ];
  }

  static void _saveProfiles(List<Map<String, dynamic>> l) => _p.setString('profiles', jsonEncode(l));

  static String get profileId {
    final id = _p.getString('profile') ?? 'p1';
    return profiles.any((e) => e['id'] == id) ? id : 'p1';
  }

  static String get _pk => profileId == 'p1' ? '' : '|$profileId';
  static Map<String, dynamic> get profile => profiles.firstWhere((e) => e['id'] == profileId, orElse: () => profiles.first);
  static bool get isKids => profile['kids'] == true;

  /// Set once the customer picked a profile in this run of the app.
  static bool profileChosen = false;

  static void setProfile(String id) {
    _p.setString('profile', id);
    _fav.clear();
    _recent.clear();
    _resume = null;
    parentalUnlocked = false;
    profileChosen = true;
  }

  static void addProfile(String name, {bool kids = false}) {
    final l = profiles;
    l.add({'id': 'p${DateTime.now().millisecondsSinceEpoch}', 'name': name, 'kids': kids});
    _saveProfiles(l);
  }

  static void setProfileKids(String id, bool kids) {
    final l = profiles;
    for (final e in l) {
      if (e['id'] == id) e['kids'] = kids;
    }
    _saveProfiles(l);
  }

  static void removeProfile(String id) {
    if (id == 'p1') return;
    final l = profiles..removeWhere((e) => e['id'] == id);
    _saveProfiles(l);
    if (_p.getString('profile') == id) setProfile('p1');
  }

  static final _adult = RegExp(r'(^|[^a-z])(xxx|adult|adults|porn|18\+|sex|erotic|nude|playboy)([^a-z]|$)', caseSensitive: false);
  static bool isAdultName(String name) => _adult.hasMatch(name);

  // ---- channel organiser: hide, rename, pin to top ----
  static Set<String> _set(String key) => (_p.getStringList('$key|$_accountKey$_pk') ?? const <String>[]).toSet();
  static String _ik(XItem i) => '${i.kind.name}|${i.id}';

  static bool isItemHidden(XItem i) => _set('hid_items').contains(_ik(i));
  static void setItemHidden(XItem i, bool v) {
    final s = _set('hid_items');
    v ? s.add(_ik(i)) : s.remove(_ik(i));
    _p.setStringList('hid_items|$_accountKey$_pk', s.toList());
  }

  static bool isPinned(XItem i) => _set('pin_items').contains(_ik(i));
  static void setPinned(XItem i, bool v) {
    final s = _set('pin_items');
    v ? s.add(_ik(i)) : s.remove(_ik(i));
    _p.setStringList('pin_items|$_accountKey$_pk', s.toList());
  }

  static Map<String, String> get _renames {
    try {
      final d = jsonDecode(_p.getString('renames|$_accountKey$_pk') ?? '{}');
      if (d is Map) return {for (final e in d.entries) e.key.toString(): e.value.toString()};
    } catch (_) {}
    return {};
  }

  static void setRename(XItem i, String name) {
    final m = _renames;
    name.trim().isEmpty ? m.remove(_ik(i)) : m[_ik(i)] = name.trim();
    _p.setString('renames|$_accountKey$_pk', jsonEncode(m));
  }

  /// Applies the customer's own hide / rename / pin choices (and the kids filter) to a list.
  static List<XItem> organize(List<XItem> list) {
    final hidden = _set('hid_items');
    final pinned = _set('pin_items');
    final ren = _renames;
    final top = <XItem>[];
    final rest = <XItem>[];
    for (final i in list) {
      if (!allowed(i)) continue;
      final k = _ik(i);
      if (hidden.contains(k)) continue;
      final item = ren.containsKey(k) ? i.copyWith(name: ren[k]) : i;
      (pinned.contains(k) ? top : rest).add(item);
    }
    return [...top, ...rest];
  }

  // ---- reminders for programmes ----
  static List<Map<String, dynamic>> get reminders {
    try {
      final d = jsonDecode(_p.getString('reminders|$_accountKey') ?? '[]');
      if (d is List) return [for (final e in d) Map<String, dynamic>.from(e as Map)];
    } catch (_) {}
    return [];
  }

  static void _saveReminders(List<Map<String, dynamic>> l) => _p.setString('reminders|$_accountKey', jsonEncode(l));

  static bool hasReminder(XItem ch, DateTime start) =>
      reminders.any((r) => r['ch'] is Map && (r['ch'] as Map)['id'] == ch.id && r['at'] == start.millisecondsSinceEpoch);

  /// Returns true when the reminder is set after the call (false when it was removed).
  static bool toggleReminder(XItem ch, String title, DateTime start) {
    final l = reminders;
    final i = l.indexWhere((r) => r['ch'] is Map && (r['ch'] as Map)['id'] == ch.id && r['at'] == start.millisecondsSinceEpoch);
    if (i >= 0) {
      l.removeAt(i);
      _saveReminders(l);
      return false;
    }
    l.add({'ch': ch.toJson(), 'title': title, 'at': start.millisecondsSinceEpoch});
    _saveReminders(l);
    return true;
  }

  /// Reminders whose programme starts within a minute (or just started); they are removed.
  static List<Map<String, dynamic>> takeDueReminders() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final l = reminders;
    final due = l.where((r) => (r['at'] as int) - now < 60000).toList();
    if (due.isEmpty) return const [];
    l.removeWhere((r) => (r['at'] as int) - now < 60000);
    _saveReminders(l);
    // Skip reminders that are more than 30 minutes late (the app was closed).
    return due.where((r) => now - (r['at'] as int) < 1800000).toList();
  }

  // ---- country on top, colour theme, idle screen ----
  static String get countryPref => _p.getString('country_pref') ?? 'auto';
  static void setCountryPref(String v) => _p.setString('country_pref', v);
  static String get detectedCountry => _p.getString('country_detected') ?? '';
  static int get detectedAt => _p.getInt('country_at') ?? 0;
  static void setDetectedCountry(String c) {
    _p.setString('country_detected', c);
    _p.setInt('country_at', DateTime.now().millisecondsSinceEpoch);
  }

  static int get theme => _p.getInt('theme') ?? 0;
  static void setTheme(int i) {
    _p.setInt('theme', i);
    Ui.setTheme(i);
  }

  /// Minutes without a key press before the idle screen shows (0 = never).
  static int get idleMinutes => _p.getInt('idle_min') ?? 5;
  static void setIdleMinutes(int m) => _p.setInt('idle_min', m);

  // ---- backup: playlists and settings as one code ----
  static String exportBackup() {
    final m = <String, dynamic>{};
    for (final k in _p.getKeys()) {
      final v = _p.get(k);
      if (v != null) m[k] = v;
    }
    return base64Url.encode(utf8.encode(jsonEncode(m)));
  }

  static Future<bool> importBackup(String code) async {
    try {
      final d = jsonDecode(utf8.decode(base64Url.decode(code.trim())));
      if (d is! Map) return false;
      for (final e in d.entries) {
        final k = e.key.toString();
        final v = e.value;
        if (v is bool) {
          await _p.setBool(k, v);
        } else if (v is int) {
          await _p.setInt(k, v);
        } else if (v is double) {
          await _p.setDouble(k, v);
        } else if (v is String) {
          await _p.setString(k, v);
        } else if (v is List) {
          await _p.setStringList(k, [for (final x in v) x.toString()]);
        }
      }
      _fav.clear();
      _recent.clear();
      _resume = null;
      Ui.clock24 = clock24;
      Ui.lite = liteMode;
      Ui.setTheme(theme);
      return true;
    } catch (_) {
      return false;
    }
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

  /// True when the saved login is a MAG (Stalker) portal.
  static bool get isMag => _p.getString('mode') == 'mag';
  static String get magPortal => _p.getString('mag_portal') ?? '';
  static String get magMac => _p.getString('mag_mac') ?? '';

  static bool get loggedIn {
    if (!(_p.getBool('logged_in') ?? false)) return false;
    if (isMag) return magPortal.isNotEmpty && magMac.isNotEmpty;
    return isM3u ? m3uUrl.isNotEmpty : (server.isNotEmpty && username.isNotEmpty);
  }

  /// Favourites and resume positions belong to one account: a different
  /// account starts clean.
  static Future<void> _switchAccount(String identity) async {
    if (_p.getString('identity') == identity) return;
    for (final kind in XKind.values) {
      await _p.remove('fav_${kind.name}$_pk');
      await _p.remove('recent_${kind.name}$_pk');
    }
    await _p.remove('resume$_pk');
    _fav.clear();
    _recent.clear();
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

  static Future<void> saveMagSession(String portal, String mac) async {
    await _switchAccount('mag|$portal|$mac');
    await _p.setString('mode', 'mag');
    await _p.setString('mag_portal', portal);
    await _p.setString('mag_mac', mac);
    await _p.setBool('logged_in', true);
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
    for (final raw in _p.getStringList('fav_${kind.name}$_pk') ?? const <String>[]) {
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
    _p.setStringList('fav_${item.kind.name}$_pk', list.map((f) => jsonEncode(f.toJson())).toList());
    return index < 0;
  }

  // ---- recently watched ----
  static final Map<XKind, List<XItem>> _recent = {};

  /// Last opened channels / movies / series of one kind, newest first.
  static List<XItem> recents(XKind kind) {
    final cached = _recent[kind];
    if (cached != null) return cached;
    final list = <XItem>[];
    for (final raw in _p.getStringList('recent_${kind.name}$_pk') ?? const <String>[]) {
      try {
        final item = XItem.fromJson(jsonDecode(raw));
        if (item != null) list.add(item);
      } catch (_) {}
    }
    _recent[kind] = list;
    return list;
  }

  static void addRecent(XItem item) {
    final list = recents(item.kind);
    list.removeWhere((f) => f.id == item.id);
    list.insert(0, item);
    while (list.length > 30) {
      list.removeLast();
    }
    _p.setStringList('recent_${item.kind.name}$_pk', list.map((f) => jsonEncode(f.toJson())).toList());
  }

  // ---- resume positions (seconds) ----
  static Map<String, int> _loadResume() {
    final cached = _resume;
    if (cached != null) return cached;
    final map = <String, int>{};
    try {
      final data = jsonDecode(_p.getString('resume$_pk') ?? '{}');
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
    _p.setString('resume$_pk', jsonEncode(map));
  }

  // ---- playback ----
  /// Audio language picked last time (ISO code such as "eng"); empty = the stream's default.
  static String get audioLanguage => _p.getString('audio_lang') ?? '';
  static void setAudioLanguage(String code) => _p.setString('audio_lang', code);

  /// How the picture is drawn: "gpu" (standard, works with every video format) or "direct"
  /// (the device's hardware decoder draws straight to the screen: lightest for weak TV sticks,
  /// and the fallback when the standard way cannot start on a device).
  static String get videoMode {
    final v = _p.getString('video_mode') ?? '';
    if (v == 'direct' || v == 'gpu') return v;
    // Direct by default: lightest for TV hardware and avoids slow/out-of-sync
    // video on big screens. Emulator test builds keep the standard mode.
    return kNoAutoDirect ? 'gpu' : 'direct';
  }
  static void setVideoMode(String mode) => _p.setString('video_mode', mode);

  /// The device's own best player: Apple's on iPhone / iPad, ExoPlayer on Android.
  static String get _bestEngine => defaultTargetPlatform == TargetPlatform.iOS ? 'native' : 'exo';

  /// Which player engine plays streams: "exo" (Google ExoPlayer, the default on Android) or
  /// "mpv". The app's own controls are the same on both.
  static String get engine {
    final v = _p.getString('player_engine2') ?? '';
    if (v == 'exo' || v == 'mpv' || v == 'native') return v;
    return _bestEngine;
  }
  static void setEngine(String engine) => _p.setString('player_engine2', engine);

  /// Player for Live TV, chosen separately from the one for films and series ([engine]).
  static String get liveEngine {
    final v = _p.getString('live_engine') ?? '';
    if (v == 'exo' || v == 'mpv' || v == 'native') return v;
    return _bestEngine;
  }
  static void setLiveEngine(String engine) => _p.setString('live_engine', engine);

  /// App language: "auto" (the TV's own language when the app has it, else English) or a code.
  static String get uiLanguage => _p.getString('ui_language') ?? 'auto';
  static void setUiLanguage(String code) => _p.setString('ui_language', code);

  /// Home screen wallpaper: 0 = the standard one, 1..20 = the pictures in assets/wallpapers.
  static int get wallpaper => _p.getInt('wallpaper') ?? 0;
  static void setWallpaper(int n) => _p.setInt('wallpaper', n);

  // ---- parental control and category management (per account) ----

  /// The PIN that unlocks locked categories; empty = parental control off.
  static String get parentalPin => _p.getString('parental_pin$_pk') ?? '';
  static void setParentalPin(String pin) => _p.setString('parental_pin$_pk', pin);

  /// The PIN was typed since the app started: locked categories stay open until the app closes.
  static bool parentalUnlocked = false;

  static String _catKey(XKind kind, String id) => '${kind.name}|$id';
  static String get _accountKey => _p.getString('identity') ?? '';

  static Set<String> _catSet(String name) => (_p.getStringList('$name|$_accountKey$_pk') ?? const <String>[]).toSet();

  static void _setCat(String name, XKind kind, String id, bool on) {
    final set = _catSet(name);
    final key = _catKey(kind, id);
    on ? set.add(key) : set.remove(key);
    _p.setStringList('$name|$_accountKey$_pk', set.toList());
  }

  /// Categories the customer switched off in Settings › Manage categories.
  static bool isHidden(XKind kind, String id) => _catSet('hidden_cats').contains(_catKey(kind, id));
  static void setHidden(XKind kind, String id, bool hidden) => _setCat('hidden_cats', kind, id, hidden);

  /// Categories behind the parental PIN.
  static bool isLocked(XKind kind, String id) =>
      parentalPin.isNotEmpty && _catSet('locked_cats').contains(_catKey(kind, id));
  static bool isLockMarked(XKind kind, String id) => _catSet('locked_cats').contains(_catKey(kind, id));
  static void setLocked(XKind kind, String id, bool locked) => _setCat('locked_cats', kind, id, locked);

  /// May this item be listed? Not in a hidden category, and not in a locked one while locked.
  static bool allowed(XItem item) =>
      !isHidden(item.kind, item.categoryId) &&
      (parentalUnlocked || !isLocked(item.kind, item.categoryId)) &&
      !(isKids && isAdultName(item.name));

  /// Subtitle language picked last time; empty = subtitles off.
  static String get subtitleLanguage => _p.getString('sub_lang') ?? '';
  static void setSubtitleLanguage(String code) => _p.setString('sub_lang', code);

  /// Stream format that worked last time for live channels: "ts" or "m3u8".
  static String get liveFormat {
    final v = _p.getString('live_format');
    if (v == 'm3u8' || v == 'ts') return v!;
    // Apple's player only plays HLS (.m3u8) for live channels.
    return defaultTargetPlatform == TargetPlatform.iOS ? 'm3u8' : 'ts';
  }

  static void setLiveFormat(String format) {
    if (format != liveFormat) _p.setString('live_format', format);
  }

  // ---- interface and playback options ----
  /// Open the last watched channel by itself when the app starts.
  static bool get autoStartLast => _p.getBool('auto_start_last') ?? false;
  static void setAutoStartLast(bool v) => _p.setBool('auto_start_last', v);

  /// Lite mode: fewer moving effects (weak TV boxes).
  /// "auto" (the app measures this device), "on" or "off".
  static String get litePref => _p.getString('lite_pref') ?? 'auto';
  static bool get autoLite => _p.getBool('lite_auto') ?? false;
  static bool get liteMode => litePref == 'on' || (litePref == 'auto' && autoLite);
  static void setLitePref(String v) {
    _p.setString('lite_pref', v);
    Ui.lite = liteMode;
  }

  static bool get tuned => _p.getBool('tuned') ?? false;
  static void setAutoLite(bool v) {
    _p.setBool('lite_auto', v);
    _p.setBool('tuned', true);
    Ui.lite = liteMode;
  }

  /// Back to the automatic choices for everything.
  static void resetToAuto() {
    for (final k in ['player_engine2', 'live_engine', 'lite_pref', 'lite_auto', 'tuned', 'buffer_level', 'max_quality', 'smart_net', 'default_fit', 'live_format', 'auto_start_last', 'country_pref', 'theme', 'idle_min']) {
      _p.remove(k);
    }
    Ui.lite = liteMode;
  }

  static bool get clock24 => _p.getBool('clock24') ?? true;
  static void setClock24(bool v) {
    _p.setBool('clock24', v);
    Ui.clock24 = v;
  }

  /// Smart Net: step down by itself when a channel keeps stalling.
  static bool get smartNet => _p.getBool('smart_net') ?? true;
  static void setSmartNet(bool v) => _p.setBool('smart_net', v);

  /// Highest picture height to use when a stream offers several (0 = no limit).
  static int get maxQuality => _p.getInt('max_quality') ?? 0;
  static void setMaxQuality(int h) => _p.setInt('max_quality', h);

  /// How much video is kept ready ahead: 0 small, 1 normal, 2 large (more is smoother on slow nets).
  static int get bufferLevel => (_p.getInt('buffer_level') ?? 1).clamp(0, 2);
  static void setBufferLevel(int n) => _p.setInt('buffer_level', n);

  /// Picture shape when a video opens: 0 fit, 1 fill, 2 stretch.
  static int get defaultFit => (_p.getInt('default_fit') ?? 0).clamp(0, 2);
  static void setDefaultFit(int n) => _p.setInt('default_fit', n);
}
