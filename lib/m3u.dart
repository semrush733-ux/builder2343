import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'xtream.dart';

/// Everything found in one M3U playlist, sorted into Live TV, Movies and Series.
class M3uData {
  M3uData(this.items, this.categories);

  final Map<XKind, List<XItem>> items;
  final Map<XKind, List<XCategory>> categories;

  int count(XKind kind) => items[kind]?.length ?? 0;
  int get total => count(XKind.live) + count(XKind.vod) + count(XKind.series);
}

const _videoFiles = ['.mp4', '.mkv', '.avi', '.mov', '.m4v', '.flv', '.wmv', '.mpg', '.mpeg', '.webm'];

/// A playlist has no "type" field: the address tells what an entry is.
XKind kindOfUrl(String url) {
  var path = url.toLowerCase();
  final q = path.indexOf('?');
  if (q >= 0) path = path.substring(0, q);
  if (path.contains('/series/')) return XKind.series;
  if (path.contains('/movie/') || path.contains('/movies/') || path.contains('/vod/')) return XKind.vod;
  for (final ext in _videoFiles) {
    if (path.endsWith(ext)) return XKind.vod;
  }
  return XKind.live;
}

/// Reads a playlist line by line, so even very large lists need little memory.
class M3uParser {
  static final _attribute = RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');
  static const _maxItems = 400000;

  final Map<XKind, List<XItem>> _items = {XKind.live: [], XKind.vod: [], XKind.series: []};
  String? _name;
  String _logo = '';
  String _group = '';
  int _total = 0;

  void add(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return;
    if (line.startsWith('#EXTINF')) {
      _logo = '';
      _group = '';
      var nameFrom = 0;
      String tvgName = '';
      for (final m in _attribute.allMatches(line)) {
        final key = m.group(1)!.toLowerCase();
        final value = m.group(2)!.trim();
        if (key == 'tvg-logo') _logo = value;
        if (key == 'group-title') _group = value;
        if (key == 'tvg-name') tvgName = value;
        nameFrom = m.end;
      }
      final comma = line.indexOf(',', nameFrom);
      var name = comma >= 0 ? line.substring(comma + 1).trim() : '';
      if (name.isEmpty) name = tvgName;
      _name = name;
      return;
    }
    if (line.startsWith('#EXTGRP:')) {
      if (_group.isEmpty) _group = line.substring(8).trim();
      return;
    }
    if (line.startsWith('#')) return;

    final name = _name;
    final logo = _logo;
    final group = _group;
    _name = null;
    _logo = '';
    _group = '';
    if (!line.startsWith('http://') && !line.startsWith('https://')) return;
    if (_total >= _maxItems) return;
    final kind = kindOfUrl(line);
    final list = _items[kind]!;
    _total++;
    list.add(XItem(
      kind: kind,
      id: line,
      name: (name == null || name.isEmpty) ? 'No name' : name,
      icon: logo,
      categoryId: group.isEmpty ? 'Other' : group,
      num: list.length + 1,
      url: line,
    ));
  }

  M3uData finish() {
    final categories = <XKind, List<XCategory>>{};
    for (final kind in XKind.values) {
      final seen = <String>{};
      final list = <XCategory>[];
      for (final item in _items[kind]!) {
        if (seen.add(item.categoryId)) list.add(XCategory(item.categoryId, item.categoryId));
      }
      categories[kind] = list;
    }
    return M3uData(_items, categories);
  }
}

M3uData parseM3u(String text) {
  final parser = M3uParser();
  for (final line in const LineSplitter().convert(text)) {
    parser.add(line);
  }
  return parser.finish();
}

/// An M3U playlist link as the source of channels, movies and series.
/// The list is downloaded once per app start and kept in memory.
class M3uSource implements Source {
  M3uSource(this.url);

  final String url;
  Future<M3uData>? _loading;

  @override
  String get label {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? 'M3U playlist' : host;
  }

  Future<M3uData> _load() {
    final running = _loading;
    if (running != null) return running;
    final future = _download();
    _loading = future;
    // A failed download must not be remembered: the next call tries again.
    future.then((_) {}, onError: (Object _) {
      if (identical(_loading, future)) _loading = null;
    });
    return future;
  }

  Future<M3uData> _download() async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw XtreamException('This playlist link is not valid. It must start with http:// or https://');
    }
    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      request.headers['User-Agent'] = kUserAgent;
      final response = await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw XtreamAuthException('The server refused this playlist link (${response.statusCode}).');
      }
      if (response.statusCode != 200) {
        throw XtreamException('The server answered with an error (${response.statusCode}).');
      }
      final parser = M3uParser();
      final lines = response.stream
          .timeout(const Duration(seconds: 45))
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter());
      await for (final line in lines) {
        parser.add(line);
      }
      final data = parser.finish();
      if (data.total == 0) {
        throw XtreamException('This link did not return a playlist with channels.');
      }
      return data;
    } finally {
      client.close();
    }
  }

  @override
  Future<XAccount> login() async {
    final data = await _load();
    String part(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    final parts = <String>[
      if (data.count(XKind.live) > 0) part(data.count(XKind.live), 'channel', 'channels'),
      if (data.count(XKind.vod) > 0) part(data.count(XKind.vod), 'movie', 'movies'),
      if (data.count(XKind.series) > 0) part(data.count(XKind.series), 'episode', 'episodes'),
    ];
    return XAccount(status: 'Active', note: 'M3U playlist  ·  ${parts.join(', ')}');
  }

  @override
  Future<List<XCategory>> categories(XKind kind) async => (await _load()).categories[kind] ?? const [];

  @override
  Future<List<XItem>> items(XKind kind, {String? categoryId}) async {
    final all = (await _load()).items[kind] ?? const <XItem>[];
    if (categoryId == null) return all;
    return all.where((i) => i.categoryId == categoryId).toList();
  }

  /// A playlist lists every episode as its own entry; there are no series pages.
  @override
  Future<XSeriesInfo> seriesInfo(String seriesId) async =>
      const XSeriesInfo(plot: '', cover: '', genre: '', seasons: {});

  /// A playlist carries no TV guide.
  @override
  Future<List<XEpg>> shortEpg(String streamId) async => const [];

  @override
  List<String> liveUrlsFor(XItem item, String preferredFormat) {
    final u = item.url;
    final q = u.indexOf('?');
    final path = q >= 0 ? u.substring(0, q) : u;
    final query = q >= 0 ? u.substring(q) : '';
    // Xtream-style addresses exist in both formats; offer the other one as a fallback.
    if (path.endsWith('.ts')) return [u, '${path.substring(0, path.length - 3)}.m3u8$query'];
    if (path.endsWith('.m3u8') && path.contains('/live/')) {
      return [u, '${path.substring(0, path.length - 5)}.ts$query'];
    }
    return [u];
  }

  @override
  String movieUrlFor(XItem item) => item.url;

  @override
  String episodeUrlFor(XEpisode episode) => episode.id;
}
