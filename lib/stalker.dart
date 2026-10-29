import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show md5, sha256;
import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;

import 'theme.dart' show log;
import 'xtream.dart';

/// MAG / Stalker (Ministra) portal client: the app introduces itself to the portal as a MAG box
/// with a MAC address, exactly like a set-top box does, and then shows the portal's channels,
/// movies and series.

const _ua = 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) '
    'MAG200 stbapp ver: 2 rev: 250 Safari/533.3';

final _macRe = RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$');

/// Upper-case "00:1A:79:AA:BB:CC" from whatever the customer typed, or '' when it is not a MAC.
String cleanMac(String input) {
  final hex = input.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
  if (hex.length != 12) return '';
  final mac = [for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2)].join(':');
  return _macRe.hasMatch(mac) ? mac : '';
}

/// A new MAC in the range portals expect from MAG boxes (00:1A:79:..).
String generateMac() {
  final r = math.Random.secure();
  String b() => r.nextInt(256).toRadixString(16).padLeft(2, '0').toUpperCase();
  return '00:1A:79:${b()}:${b()}:${b()}';
}

dynamic _decodeBytes(Uint8List bytes) {
  final text = utf8.decode(bytes, allowMalformed: true).trim();
  if (text.isEmpty) return null;
  return jsonDecode(text);
}

/// The first http(s) address inside a portal command such as "ffmpeg http://host/x" or
/// "ffrt http://localhost/ch/12".
String stalkerAddress(String cmd) {
  final m = RegExp(r'https?://\S+').firstMatch(cmd);
  return m == null ? '' : m.group(0)!;
}

class StalkerSource implements Source {
  StalkerSource(this.portal, this.mac);

  /// The portal address as typed (".../c/", ".../stalker_portal/c/" or just the host).
  final String portal;

  /// The MAC address this device uses at the portal.
  final String mac;

  String _endpoint = '';
  String _token = '';
  Future<void>? _ready;
  XAccount? _account;
  final Map<String, Map> _raw = {};
  List<XItem>? _channels;
  final Map<XKind, List<XCategory>> _cats = {};

  @override
  String get label {
    final host = Uri.tryParse(_normalised())?.host ?? '';
    return host.isEmpty ? 'MAG portal' : host;
  }

  // ---------------------------------------------------------------- addresses

  String _normalised() {
    var s = portal.trim();
    if (s.isEmpty) return '';
    if (!s.contains('://')) s = 'http://$s';
    return s;
  }

  String get _origin {
    final u = Uri.tryParse(_normalised());
    if (u == null || u.host.isEmpty) return '';
    return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}';
  }

  /// Addresses of the portal's API to try, most likely first.
  List<String> _candidates() {
    final u = Uri.tryParse(_normalised());
    if (u == null || u.host.isEmpty) return const [];
    final o = _origin;
    var path = u.path;
    // ".../c/" or ".../c" is the portal's web page; the API lives next to it.
    path = path.replaceFirst(RegExp(r'/c/?$'), '').replaceFirst(RegExp(r'/+$'), '');
    final out = <String>[];
    void add(String a) {
      if (!out.contains(a)) out.add(a);
    }

    if (path.contains('stalker_portal')) {
      add('$o$path/server/load.php');
    }
    if (path.isNotEmpty && !path.contains('stalker_portal')) {
      add('$o$path/portal.php');
      add('$o$path/server/load.php');
    }
    add('$o/portal.php');
    add('$o/stalker_portal/server/load.php');
    add('$o/server/load.php');
    add('$o/c/portal.php');
    return out;
  }

  // ---------------------------------------------------------------- transport

  Map<String, String> get _headers => {
        'User-Agent': _ua,
        'X-User-Agent': 'Model: MAG250; Link: WiFi',
        'Accept': '*/*',
        'Cookie': 'mac=$mac; stb_lang=en; timezone=Europe%2FLondon',
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  Uri _uri(String endpoint, Map<String, String> q) => Uri.parse(endpoint).replace(queryParameters: {
        ...q,
        'JsHttpRequest': '1-xml',
      });

  Future<dynamic> _fetch(String endpoint, Map<String, String> q, {Duration timeout = const Duration(seconds: 25)}) async {
    final res = await http.get(_uri(endpoint, q), headers: _headers).timeout(timeout);
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw XtreamAuthException('The portal refused this device (MAC $mac). Ask your provider to add this MAC.');
    }
    if (res.statusCode != 200) {
      throw XtreamException('The portal answered with an error (${res.statusCode}).');
    }
    final bytes = res.bodyBytes;
    try {
      return bytes.length > 150000 ? await compute(_decodeBytes, bytes) : _decodeBytes(bytes);
    } on FormatException {
      return null;
    }
  }

  Future<void> _handshake() async {
    if (_endpoint.isEmpty) {
      Object? last;
      for (final candidate in _candidates()) {
        try {
          final data = await _fetch(candidate, {'type': 'stb', 'action': 'handshake', 'token': '', 'prehash': '0'},
              timeout: const Duration(seconds: 12));
          final js = data is Map ? data['js'] : null;
          if (js is Map && str(js['token']).isNotEmpty) {
            _endpoint = candidate;
            _token = str(js['token']);
            break;
          }
        } on XtreamAuthException {
          rethrow;
        } catch (e) {
          last = e;
        }
      }
      if (_endpoint.isEmpty) {
        if (last != null && _candidates().length == 1) throw last;
        throw XtreamException('This address did not answer like a MAG / Stalker portal. Check the portal link.');
      }
    } else {
      final data = await _fetch(_endpoint, {'type': 'stb', 'action': 'handshake', 'token': _token, 'prehash': '0'});
      final js = data is Map ? data['js'] : null;
      if (js is Map && str(js['token']).isNotEmpty) _token = str(js['token']);
    }
    await _profile();
  }

  Future<void> _profile() async {
    final sn = md5.convert(utf8.encode(mac)).toString().toUpperCase().substring(0, 13);
    final did = sha256.convert(utf8.encode(mac)).toString().toUpperCase();
    try {
      final data = await _fetch(_endpoint, {
        'type': 'stb',
        'action': 'get_profile',
        'hd': '1',
        'ver': 'ImageDescription: 0.2.18-r14-pub-250; ImageDate: Fri Jan 15 15:20:44 EET 2016; '
            'PORTAL version: 5.6.1; API Version: JS API version: 328; STB API version: 134; Player Engine version: 0x566',
        'num_banks': '2',
        'sn': sn,
        'stb_type': 'MAG250',
        'client_type': 'STB',
        'image_version': '218',
        'video_out': 'hdmi',
        'device_id': did,
        'device_id2': did,
        'signature': '',
        'auth_second_step': '1',
        'hw_version': '1.7-BD-00',
        'not_valid_token': '0',
        'metrics': '',
        'hw_version_2': sha256.convert(utf8.encode(sn)).toString(),
        'timestamp': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
        'api_signature': '262',
        'prehash': '',
      });
      final js = data is Map ? data['js'] : null;
      if (js is Map && str(js['token']).isNotEmpty) _token = str(js['token']);
    } on XtreamAuthException {
      rethrow;
    } catch (_) {
      // Some portals skip this step; the handshake token is then enough.
    }
  }

  Future<void> _ensure() => _ready ??= _handshake().catchError((Object e) {
        _ready = null;
        throw e;
      });

  /// One API call with the signed-in session; signs in again once when the portal forgot us.
  Future<Map> _call(Map<String, String> q, {Duration timeout = const Duration(seconds: 25)}) async {
    await _ensure();
    var data = await _fetch(_endpoint, q, timeout: timeout);
    if (data is! Map || data['js'] == null) {
      _ready = null;
      await _ensure();
      data = await _fetch(_endpoint, q, timeout: timeout);
    }
    if (data is! Map || data['js'] == null) {
      throw XtreamException('The portal did not answer. Please try again.');
    }
    return data;
  }

  // ---------------------------------------------------------------- Source

  @override
  Future<XAccount> login() async {
    if (cleanMac(mac).isEmpty) throw XtreamException('The MAC address is not valid (example 00:1A:79:12:34:56).');
    await _ensure();
    var expires = '';
    try {
      final data = await _call({'type': 'account_info', 'action': 'get_main_info'}, timeout: const Duration(seconds: 15));
      final js = data['js'];
      if (js is Map) {
        expires = str(js['end_date']).isNotEmpty ? str(js['end_date']) : str(js['phone']);
      }
    } catch (_) {}
    // Make sure the portal really gives channels to this MAC.
    try {
      await _call({'type': 'itv', 'action': 'get_genres'}, timeout: const Duration(seconds: 15));
    } on XtreamAuthException {
      rethrow;
    } catch (_) {}
    DateTime? when;
    final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(expires);
    if (m != null) when = DateTime.tryParse('${m.group(1)}-${m.group(2)}-${m.group(3)}');
    _account = XAccount(
      status: 'Active',
      expires: when,
      note: when == null ? (expires.isNotEmpty ? expires : 'MAG portal  ·  $mac') : '',
    );
    return _account!;
  }

  List<Map> _list(dynamic js) {
    if (js is List) return js.whereType<Map>().toList();
    if (js is Map && js['data'] is List) return (js['data'] as List).whereType<Map>().toList();
    return const [];
  }

  String _icon(String logo) {
    final l = logo.trim();
    if (l.isEmpty) return '';
    if (l.startsWith('http')) return l;
    if (l.startsWith('/')) return '$_origin$l';
    return '$_origin/stalker_portal/misc/logos/320/$l';
  }

  static const _types = {XKind.live: 'itv', XKind.vod: 'vod', XKind.series: 'series'};

  @override
  Future<List<XCategory>> categories(XKind kind) async {
    final cached = _cats[kind];
    if (cached != null) return cached;
    final action = kind == XKind.live ? 'get_genres' : 'get_categories';
    final data = await _call({'type': _types[kind]!, 'action': action});
    final out = <XCategory>[];
    for (final m in _list(data['js'])) {
      final id = str(m['id']);
      final title = str(m['title']).isNotEmpty ? str(m['title']) : str(m['name']);
      if (id.isEmpty || id == '*' || title.isEmpty) continue;
      out.add(XCategory(id, title));
    }
    return _cats[kind] = out;
  }

  XItem? _item(XKind kind, Map m) {
    final id = str(m['id']);
    if (id.isEmpty) return null;
    final cmd = str(m['cmd']);
    _raw['${kind.name}:$id'] = m;
    final icon = kind == XKind.live ? _icon(str(m['logo'])) : _icon(str(m['screenshot_uri']));
    return XItem(
      kind: kind,
      id: id,
      name: str(m['name']).isEmpty ? 'No name' : str(m['name']),
      icon: icon,
      categoryId: kind == XKind.live ? str(m['tv_genre_id']) : str(m['category_id']),
      rating: str(m['rating_imdb']).isNotEmpty ? str(m['rating_imdb']) : str(m['rating_kinopoisk']),
      num: toInt(m['number']),
      url: cmd,
      epgId: str(m['xmltv_id']),
      archive: toInt(m['tv_archive']) == 1,
    );
  }

  @override
  Future<List<XItem>> items(XKind kind, {String? categoryId}) async {
    if (kind == XKind.live) {
      var all = _channels;
      if (all == null) {
        final data = await _call({'type': 'itv', 'action': 'get_all_channels'}, timeout: const Duration(seconds: 90));
        final built = <XItem>[];
        for (final m in _list(data['js'])) {
          final it = _item(XKind.live, m);
          if (it != null) built.add(it);
        }
        all = built;
        _channels = built;
      }
      if (categoryId == null || categoryId.isEmpty) return all;
      return all.where((i) => i.categoryId == categoryId).toList();
    }
    final out = <XItem>[];
    var page = 1;
    var total = 0;
    while (page <= 60) {
      final data = await _call({
        'type': _types[kind]!,
        'action': 'get_ordered_list',
        'category': (categoryId == null || categoryId.isEmpty) ? '*' : categoryId,
        'p': '$page',
        'sortby': 'added',
      }, timeout: const Duration(seconds: 40));
      final js = data['js'];
      final rows = _list(js);
      if (rows.isEmpty) break;
      for (final m in rows) {
        final it = _item(kind, m);
        if (it != null) out.add(it);
      }
      if (js is Map) total = toInt(js['total_items']);
      if (total > 0 && out.length >= total) break;
      page++;
    }
    return out;
  }

  @override
  Future<XSeriesInfo> seriesInfo(String seriesId) async {
    final m = _raw['series:$seriesId'] ?? const {};
    final seasons = <int, List<XEpisode>>{};
    final eps = m['series'];
    if (eps is List && eps.isNotEmpty) {
      seasons[1] = [
        for (final e in eps)
          XEpisode(
            id: '$seriesId|${str(m['cmd'])}|${str(e)}',
            title: 'Episode ${str(e)}',
            ext: '',
            season: 1,
            number: toInt(e),
          ),
      ];
    } else {
      // Portals that list seasons as folders: ask for the content of the series item.
      try {
        final data = await _call({
          'type': 'series',
          'action': 'get_ordered_list',
          'movie_id': seriesId,
          'season_id': '0',
          'episode_id': '0',
          'p': '1',
        });
        for (final s in _list(data['js'])) {
          final season = toInt(RegExp(r'\d+').firstMatch(str(s['name']))?.group(0));
          final sub = s['series'];
          if (sub is List) {
            seasons[season <= 0 ? seasons.length + 1 : season] = [
              for (final e in sub)
                XEpisode(
                  id: '$seriesId|${str(s['cmd'])}|${str(e)}',
                  title: 'Episode ${str(e)}',
                  ext: '',
                  season: season <= 0 ? seasons.length + 1 : season,
                  number: toInt(e),
                ),
            ];
          }
        }
      } catch (_) {}
    }
    return XSeriesInfo(
      plot: str(m['description']),
      cover: _icon(str(m['screenshot_uri'])),
      genre: str(m['genres_str']),
      seasons: seasons,
    );
  }

  @override
  Future<XMovieInfo> movieInfo(XItem item) async {
    final m = _raw['${item.kind.name}:${item.id}'] ?? const {};
    final minutes = toInt(m['time']);
    return XMovieInfo(
      plot: str(m['description']),
      cast: str(m['actors']),
      director: str(m['director']),
      genre: str(m['genres_str']),
      year: str(m['year']),
      rating: double.tryParse(str(m['rating_imdb'])) ?? double.tryParse(str(m['rating_kinopoisk'])) ?? 0,
      duration: minutes > 0 ? (minutes >= 60 ? '${minutes ~/ 60} h ${minutes % 60} min' : '$minutes min') : '',
      cover: item.icon,
      backdrop: item.icon,
      country: str(m['country']),
    );
  }

  @override
  Future<List<XEpg>> shortEpg(String streamId) async {
    try {
      final data = await _call({'type': 'itv', 'action': 'get_short_epg', 'ch_id': streamId, 'size': '4'},
          timeout: const Duration(seconds: 10));
      final out = <XEpg>[];
      for (final m in _list(data['js'])) {
        final a = toInt(m['start_timestamp']);
        final b = toInt(m['stop_timestamp']);
        if (a <= 0 || b <= a) continue;
        out.add(XEpg(str(m['name']), DateTime.fromMillisecondsSinceEpoch(a * 1000),
            DateTime.fromMillisecondsSinceEpoch(b * 1000),
            description: str(m['descr'])));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<XEpg>> fullEpg(String epgId) async => const [];

  // Stream addresses are made by the portal at play time (they carry a short-lived token):
  // use [StalkerSource.resolveLive] and friends. These plain versions give the address inside
  // the stored command, which works on portals that hand out fixed addresses.
  @override
  List<String> liveUrlsFor(XItem item, String preferredFormat) {
    final a = stalkerAddress(item.url);
    return a.isEmpty ? const [] : [a];
  }

  @override
  String movieUrlFor(XItem item) => stalkerAddress(item.url);

  @override
  String episodeUrlFor(XEpisode episode) => '';

  Future<String> _createLink(String type, String cmd, {String series = ''}) async {
    final data = await _call({
      'type': type,
      'action': 'create_link',
      'cmd': cmd,
      'series': series,
      'forced_storage': 'undefined',
      'disable_ad': '0',
      'download': '0',
    }, timeout: const Duration(seconds: 20));
    final js = data['js'];
    final got = js is Map ? stalkerAddress(str(js['cmd'])) : '';
    if (got.isEmpty) throw XtreamException('The portal did not give a stream address for this item.');
    return got;
  }

  Future<List<String>> resolveLive(XItem item) async {
    try {
      return [await _createLink('itv', item.url)];
    } catch (e) {
      final fixed = stalkerAddress(item.url);
      if (fixed.isNotEmpty && !fixed.contains('localhost')) return [fixed];
      rethrow;
    }
  }

  Future<String> resolveMovie(XItem item) async {
    var cmd = item.url;
    if (cmd.isEmpty) cmd = '/media/${item.id}.mpg';
    return _createLink('vod', cmd);
  }

  Future<String> resolveEpisode(XEpisode e) async {
    final parts = e.id.split('|');
    final cmd = parts.length > 1 ? parts[1] : '';
    final n = parts.length > 2 ? parts[2] : '${e.number}';
    return _createLink('vod', cmd, series: n);
  }
}

/// Live stream addresses, asking the portal first when this is a MAG source.
Future<List<String>> resolveLiveUrls(Source s, XItem item, String format) async {
  if (s is StalkerSource) return s.resolveLive(item);
  return s.liveUrlsFor(item, format);
}

Future<String> resolveMovieUrl(Source s, XItem item) async {
  if (s is StalkerSource) return s.resolveMovie(item);
  return s.movieUrlFor(item);
}

Future<String> resolveEpisodeUrl(Source s, XEpisode e) async {
  if (s is StalkerSource) return s.resolveEpisode(e);
  return s.episodeUrlFor(e);
}

void stalkerLog(String m) => log('stalker $m');
