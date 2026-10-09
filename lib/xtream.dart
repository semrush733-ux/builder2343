import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;

import 'config.dart';

/// Client for IPTV servers that speak the Xtream Codes API (player_api.php).

enum XKind { live, vod, series }

String str(dynamic v) => v == null ? '' : v.toString().trim();

int toInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(str(v)) ?? 0;
}

class XtreamException implements Exception {
  XtreamException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The server answered, but refuses this account (wrong details, expired...).
class XtreamAuthException extends XtreamException {
  XtreamAuthException(super.message);
}

String friendlyError(Object e) {
  if (e is XtreamException) return e.message;
  if (e is TimeoutException) return 'The server did not answer in time. Please try again.';
  if (e is SocketException || e is http.ClientException || e is HandshakeException) {
    return 'Cannot reach the server. Check the address and your internet connection.';
  }
  if (e is FormatException) return 'This address did not answer like an IPTV server.';
  return 'Something went wrong. Please try again.';
}

class ParsedInput {
  const ParsedInput(this.server, this.username, this.password, this.hadScheme);
  final String server;
  final String? username;
  final String? password;
  final bool hadScheme;
}

/// Accepts "host:port", "http://host:port/" or a full playlist link
/// (".../get.php?username=..&password=..") and returns the server base address.
ParsedInput parseServerInput(String input) {
  var s = input.trim();
  if (s.isEmpty) return const ParsedInput('', null, null, false);
  final hadScheme = s.contains('://');
  if (!hadScheme) s = 'http://$s';
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return ParsedInput('', null, null, hadScheme);
  var path = uri.path;
  final lower = path.toLowerCase();
  for (final f in const ['/get.php', '/player_api.php', '/xmltv.php', '/panel_api.php']) {
    if (lower.endsWith(f)) {
      path = path.substring(0, path.length - f.length);
      break;
    }
  }
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  final port = uri.hasPort ? ':${uri.port}' : '';
  final q = uri.queryParameters;
  return ParsedInput('${uri.scheme}://${uri.host}$port$path', q['username'], q['password'], hadScheme);
}

class XCategory {
  const XCategory(this.id, this.name);
  final String id;
  final String name;
}

class XItem {
  const XItem({
    required this.kind,
    required this.id,
    required this.name,
    this.icon = '',
    this.categoryId = '',
    this.ext = '',
    this.rating = '',
    this.num = 0,
  });

  final XKind kind;
  final String id;
  final String name;
  final String icon;
  final String categoryId;
  final String ext;
  final String rating;
  final int num;

  static XItem? fromApi(XKind kind, Map m) {
    final id = str(kind == XKind.series ? m['series_id'] : m['stream_id']);
    if (id.isEmpty) return null;
    final name = str(m['name']);
    return XItem(
      kind: kind,
      id: id,
      name: name.isEmpty ? 'No name' : name,
      icon: str(kind == XKind.series ? m['cover'] : m['stream_icon']),
      categoryId: str(m['category_id']),
      ext: kind == XKind.vod ? str(m['container_extension']) : '',
      rating: str(m['rating']),
      num: toInt(m['num']),
    );
  }

  Map<String, dynamic> toJson() => {
        'k': kind.name,
        'id': id,
        'n': name,
        'i': icon,
        'c': categoryId,
        'e': ext,
        'r': rating,
        'num': num,
      };

  static XItem? fromJson(dynamic j) {
    if (j is! Map) return null;
    final id = str(j['id']);
    if (id.isEmpty) return null;
    final kind = XKind.values.firstWhere((k) => k.name == str(j['k']), orElse: () => XKind.live);
    return XItem(
      kind: kind,
      id: id,
      name: str(j['n']),
      icon: str(j['i']),
      categoryId: str(j['c']),
      ext: str(j['e']),
      rating: str(j['r']),
      num: toInt(j['num']),
    );
  }
}

class XEpisode {
  const XEpisode({
    required this.id,
    required this.title,
    required this.ext,
    required this.season,
    required this.number,
    this.duration = '',
  });

  final String id;
  final String title;
  final String ext;
  final int season;
  final int number;
  final String duration;
}

class XSeriesInfo {
  const XSeriesInfo({required this.plot, required this.cover, required this.genre, required this.seasons});
  final String plot;
  final String cover;
  final String genre;

  /// Season number -> episodes, in season order.
  final Map<int, List<XEpisode>> seasons;
}

class XEpg {
  const XEpg(this.title, this.start, this.end);
  final String title;
  final DateTime start;
  final DateTime end;
}

class XAccount {
  const XAccount({required this.status, this.expires, this.maxConnections = 0, this.isTrial = false, this.formats = const []});
  final String status;
  final DateTime? expires;
  final int maxConnections;
  final bool isTrial;
  final List<String> formats;
}

dynamic _decodeJson(Uint8List bytes) {
  final text = utf8.decode(bytes, allowMalformed: true).trim();
  if (text.isEmpty) return null;
  return jsonDecode(text);
}

List<Map> _asList(dynamic data) {
  if (data is List) return data.whereType<Map>().toList();
  if (data is Map) return data.values.whereType<Map>().toList();
  return const [];
}

class _ItemsJob {
  const _ItemsJob(this.bytes, this.kind);
  final Uint8List bytes;
  final XKind kind;
}

List<XItem> _parseItems(_ItemsJob job) => parseItems(_decodeJson(job.bytes), job.kind);

List<XItem> parseItems(dynamic data, XKind kind) {
  final out = <XItem>[];
  for (final m in _asList(data)) {
    final item = XItem.fromApi(kind, m);
    if (item != null) out.add(item);
  }
  return out;
}

List<XCategory> parseCategories(dynamic data) {
  final out = <XCategory>[];
  for (final m in _asList(data)) {
    final id = str(m['category_id']);
    if (id.isEmpty) continue;
    final name = str(m['category_name']);
    out.add(XCategory(id, name.isEmpty ? 'Category $id' : name));
  }
  return out;
}

XAccount parseAccount(dynamic data) {
  if (data is! Map || data['user_info'] is! Map) {
    throw XtreamException('This address did not answer like an IPTV server.');
  }
  final u = data['user_info'] as Map;
  if (toInt(u['auth']) != 1) throw XtreamAuthException('Wrong username or password.');
  final status = str(u['status']);
  if (status.isNotEmpty && status.toLowerCase() != 'active') {
    throw XtreamAuthException('This account is ${status.toLowerCase()}. Please contact your provider.');
  }
  final exp = toInt(u['exp_date']);
  final formats = u['allowed_output_formats'];
  return XAccount(
    status: status.isEmpty ? 'Active' : status,
    expires: exp > 0 ? DateTime.fromMillisecondsSinceEpoch(exp * 1000) : null,
    maxConnections: toInt(u['max_connections']),
    isTrial: toInt(u['is_trial']) == 1,
    formats: formats is List ? formats.map(str).toList() : const [],
  );
}

String _b64(dynamic v) {
  final s = str(v);
  if (s.isEmpty) return '';
  try {
    return utf8.decode(base64.decode(base64.normalize(s)), allowMalformed: true).trim();
  } catch (_) {
    return s;
  }
}

List<XEpg> parseEpg(dynamic data) {
  final out = <XEpg>[];
  if (data is! Map) return out;
  for (final m in _asList(data['epg_listings'])) {
    final start = toInt(m['start_timestamp']);
    final stop = toInt(m['stop_timestamp']);
    if (start <= 0 || stop <= start) continue;
    out.add(XEpg(
      _b64(m['title']),
      DateTime.fromMillisecondsSinceEpoch(start * 1000),
      DateTime.fromMillisecondsSinceEpoch(stop * 1000),
    ));
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

XSeriesInfo parseSeriesInfo(dynamic data) {
  final seasons = <int, List<XEpisode>>{};
  var plot = '';
  var cover = '';
  var genre = '';
  if (data is Map) {
    final info = data['info'];
    if (info is Map) {
      plot = str(info['plot']);
      cover = str(info['cover']);
      genre = str(info['genre']);
    }
    final eps = data['episodes'];
    final groups = <List>[];
    if (eps is Map) {
      for (final v in eps.values) {
        if (v is List) groups.add(v);
      }
    } else if (eps is List) {
      for (final v in eps) {
        if (v is List) groups.add(v);
      }
      if (groups.isEmpty) groups.add(eps);
    }
    for (final group in groups) {
      for (final e in group.whereType<Map>()) {
        final id = str(e['id']);
        if (id.isEmpty) continue;
        final season = toInt(e['season']);
        final number = toInt(e['episode_num']);
        final info = e['info'];
        final title = str(e['title']);
        final ext = str(e['container_extension']);
        seasons.putIfAbsent(season, () => <XEpisode>[]).add(XEpisode(
              id: id,
              title: title.isEmpty ? 'Episode $number' : title,
              ext: ext.isEmpty ? 'mp4' : ext,
              season: season,
              number: number,
              duration: info is Map ? str(info['duration']) : '',
            ));
      }
    }
  }
  final sorted = <int, List<XEpisode>>{};
  for (final k in seasons.keys.toList()..sort()) {
    sorted[k] = seasons[k]!..sort((a, b) => a.number.compareTo(b.number));
  }
  return XSeriesInfo(plot: plot, cover: cover, genre: genre, seasons: sorted);
}

class XtreamApi {
  XtreamApi(this.server, this.username, this.password);

  final String server;
  final String username;
  final String password;

  static const _actions = {
    XKind.live: ['get_live_categories', 'get_live_streams'],
    XKind.vod: ['get_vod_categories', 'get_vod_streams'],
    XKind.series: ['get_series_categories', 'get_series'],
  };

  Uri _uri(Map<String, String> extra) {
    return Uri.parse('$server/player_api.php').replace(queryParameters: {
      'username': username,
      'password': password,
      ...extra,
    });
  }

  Future<Uint8List> _bytes(Map<String, String> extra, Duration timeout) async {
    final res = await http
        .get(_uri(extra), headers: const {'User-Agent': kUserAgent, 'Accept': 'application/json'}).timeout(timeout);
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw XtreamException('Wrong username or password.');
    }
    if (res.statusCode != 200) {
      throw XtreamException('The server answered with an error (${res.statusCode}).');
    }
    return res.bodyBytes;
  }

  Future<dynamic> _json(Map<String, String> extra, {Duration timeout = const Duration(seconds: 30)}) async {
    final bytes = await _bytes(extra, timeout);
    if (bytes.length > 150000) return compute(_decodeJson, bytes);
    return _decodeJson(bytes);
  }

  Future<XAccount> login() async {
    return parseAccount(await _json(const {}, timeout: const Duration(seconds: 20)));
  }

  Future<List<XCategory>> categories(XKind kind) async {
    return parseCategories(await _json({'action': _actions[kind]![0]}));
  }

  /// All items of a kind, or only one category when [categoryId] is given.
  Future<List<XItem>> items(XKind kind, {String? categoryId}) async {
    final bytes = await _bytes({
      'action': _actions[kind]![1],
      if (categoryId != null) 'category_id': categoryId,
    }, const Duration(seconds: 60));
    if (bytes.length > 150000) return compute(_parseItems, _ItemsJob(bytes, kind));
    return parseItems(_decodeJson(bytes), kind);
  }

  Future<XSeriesInfo> seriesInfo(String seriesId) async {
    return parseSeriesInfo(await _json({'action': 'get_series_info', 'series_id': seriesId}));
  }

  Future<List<XEpg>> shortEpg(String streamId) async {
    final data = await _json({'action': 'get_short_epg', 'stream_id': streamId, 'limit': '4'},
        timeout: const Duration(seconds: 12));
    return parseEpg(data);
  }

  String get _auth => '${Uri.encodeComponent(username)}/${Uri.encodeComponent(password)}';

  String liveUrl(String id, String ext) => '$server/live/$_auth/$id.$ext';

  String vodUrl(String id, String ext) => '$server/movie/$_auth/$id.${ext.isEmpty ? 'mp4' : ext}';

  String episodeUrl(String id, String ext) => '$server/series/$_auth/$id.${ext.isEmpty ? 'mp4' : ext}';
}
