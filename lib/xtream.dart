import 'dart:async';
import 'dart:convert';
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
  // Checked by name so this file also compiles for the web build (no dart:io there).
  final kind = e.runtimeType.toString();
  if (kind == 'SocketException' || kind == 'HandshakeException' || kind == '_ClientSocketException' || e is http.ClientException) {
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
    this.url = '',
  });

  final XKind kind;
  final String id;
  final String name;
  final String icon;
  final String categoryId;
  final String ext;
  final String rating;
  final int num;

  /// Direct stream address. Only set for items that come from an M3U playlist.
  final String url;

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
        if (url.isNotEmpty) 'u': url,
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
      url: str(j['u']),
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

/// Details of one movie, as far as the server has them.
class XMovieInfo {
  const XMovieInfo({
    this.plot = '',
    this.cast = '',
    this.director = '',
    this.genre = '',
    this.year = '',
    this.rating = 0,
    this.duration = '',
    this.backdrop = '',
    this.cover = '',
    this.trailer = '',
    this.country = '',
    this.tmdbId = '',
  });

  /// Id of the film at themoviedb.org, when the server knows it.
  final String tmdbId;

  final String plot;
  final String cast;
  final String director;
  final String genre;
  final String year;

  /// 0 to 10; 0 = unknown.
  final double rating;

  /// Readable length such as "2 h 18 min".
  final String duration;
  final String backdrop;
  final String cover;

  /// YouTube video id of the trailer, when the server has one.
  final String trailer;
  final String country;
}

String _firstText(List<dynamic> values) {
  for (final v in values) {
    if (v is List) {
      final inner = _firstText(v);
      if (inner.isNotEmpty) return inner;
    } else {
      final s = str(v);
      if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
    }
  }
  return '';
}

String _readableLength(Map info) {
  var seconds = toInt(info['duration_secs']);
  if (seconds <= 0) {
    final parts = str(info['duration']).split(':');
    if (parts.length == 3) {
      seconds = toInt(parts[0]) * 3600 + toInt(parts[1]) * 60 + toInt(parts[2]);
    } else if (parts.length == 1 && toInt(parts[0]) > 0) {
      seconds = toInt(parts[0]) * 60; // some servers send minutes
    }
  }
  if (seconds <= 0) return '';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return h > 0 ? '$h h $m min' : '$m min';
}

XMovieInfo parseMovieInfo(dynamic data) {
  if (data is! Map || data['info'] is! Map) return const XMovieInfo();
  final info = data['info'] as Map;
  final date = _firstText([info['releasedate'], info['release_date'], info['releaseDate'], info['year']]);
  final year = RegExp(r'(19|20)\d\d').firstMatch(date)?.group(0) ?? '';
  var trailer = _firstText([info['youtube_trailer'], info['trailer']]);
  final watch = RegExp(r'(?:v=|youtu\.be/|embed/)([A-Za-z0-9_-]{6,})').firstMatch(trailer);
  if (watch != null) trailer = watch.group(1)!;
  if (trailer.contains('/') || trailer.contains(' ')) trailer = '';
  return XMovieInfo(
    plot: _firstText([info['plot'], info['description']]),
    cast: _firstText([info['cast'], info['actors']]),
    director: _firstText([info['director']]),
    genre: _firstText([info['genre']]),
    year: year,
    rating: double.tryParse(_firstText([info['rating'], info['rating_5based']])) ?? 0,
    duration: _readableLength(info),
    backdrop: _firstText([info['backdrop_path'], info['backdrop']]),
    cover: _firstText([info['movie_image'], info['cover_big'], info['cover']]),
    trailer: trailer,
    country: _firstText([info['country']]),
    tmdbId: toInt(info['tmdb_id']) > 0 ? '${toInt(info['tmdb_id'])}' : '',
  );
}

class XEpg {
  const XEpg(this.title, this.start, this.end);
  final String title;
  final DateTime start;
  final DateTime end;
}

class XAccount {
  const XAccount({
    required this.status,
    this.expires,
    this.maxConnections = 0,
    this.isTrial = false,
    this.formats = const [],
    this.note = '',
  });
  final String status;

  /// Shown on the home screen instead of the expiry date (M3U playlists have none).
  final String note;
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

/// Where channels, movies and series come from: an Xtream Codes login
/// ([XtreamApi]) or an M3U playlist link (M3uSource in m3u.dart).
abstract class Source {
  /// Short name shown on the home screen.
  String get label;

  /// Checks the login / loads the playlist.
  Future<XAccount> login();

  Future<List<XCategory>> categories(XKind kind);

  /// All items of a kind, or only one category when [categoryId] is given.
  Future<List<XItem>> items(XKind kind, {String? categoryId});

  Future<XSeriesInfo> seriesInfo(String seriesId);

  /// Plot, cast, rating... of a movie. Empty when the source has none.
  Future<XMovieInfo> movieInfo(XItem item);

  Future<List<XEpg>> shortEpg(String streamId);

  /// Stream addresses of a live channel, the one to try first at the front.
  List<String> liveUrlsFor(XItem item, String preferredFormat);

  String movieUrlFor(XItem item);

  String episodeUrlFor(XEpisode episode);
}

class XtreamApi implements Source {
  XtreamApi(this.server, this.username, this.password);

  final String server;
  final String username;
  final String password;

  @override
  String get label => username;

  /// Stream formats this account may use ("ts", "m3u8"), known after [login].
  List<String> formats = const [];

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

  @override
  Future<XAccount> login() async {
    final account = parseAccount(await _json(const {}, timeout: const Duration(seconds: 20)));
    formats = account.formats;
    return account;
  }

  @override
  Future<List<XCategory>> categories(XKind kind) async {
    return parseCategories(await _json({'action': _actions[kind]![0]}));
  }

  @override
  Future<List<XItem>> items(XKind kind, {String? categoryId}) async {
    final bytes = await _bytes({
      'action': _actions[kind]![1],
      if (categoryId != null) 'category_id': categoryId,
    }, const Duration(seconds: 60));
    if (bytes.length > 150000) return compute(_parseItems, _ItemsJob(bytes, kind));
    return parseItems(_decodeJson(bytes), kind);
  }

  @override
  Future<XSeriesInfo> seriesInfo(String seriesId) async {
    return parseSeriesInfo(await _json({'action': 'get_series_info', 'series_id': seriesId}));
  }

  @override
  Future<XMovieInfo> movieInfo(XItem item) async {
    return parseMovieInfo(await _json({'action': 'get_vod_info', 'vod_id': item.id}));
  }

  @override
  Future<List<XEpg>> shortEpg(String streamId) async {
    final data = await _json({'action': 'get_short_epg', 'stream_id': streamId, 'limit': '4'},
        timeout: const Duration(seconds: 12));
    return parseEpg(data);
  }

  String get _auth => '${Uri.encodeComponent(username)}/${Uri.encodeComponent(password)}';

  String liveUrl(String id, String ext) => '$server/live/$_auth/$id.$ext';

  String vodUrl(String id, String ext) => '$server/movie/$_auth/$id.${ext.isEmpty ? 'mp4' : ext}';

  String episodeUrl(String id, String ext) => '$server/series/$_auth/$id.${ext.isEmpty ? 'mp4' : ext}';

  @override
  List<String> liveUrlsFor(XItem item, String preferredFormat) {
    final other = preferredFormat == 'ts' ? 'm3u8' : 'ts';
    var order = [preferredFormat, other];
    // Do not try a format the provider has switched off for this account.
    final allowed = order.where(formats.contains).toList();
    if (allowed.isNotEmpty) order = allowed;
    return [for (final format in order) liveUrl(item.id, format)];
  }

  @override
  String movieUrlFor(XItem item) => vodUrl(item.id, item.ext);

  @override
  String episodeUrlFor(XEpisode episode) => episodeUrl(episode.id, episode.ext);
}
