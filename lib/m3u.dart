import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;

import 'package:archive/archive.dart' show GZipDecoder;
import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;

import 'config.dart';
import 'theme.dart' show log;
import 'xtream.dart';

/// Everything found in one M3U playlist, sorted into Live TV, Movies and Series.
class M3uData {
  M3uData(this.items, this.categories, {this.epgUrl = ''});

  final Map<XKind, List<XItem>> items;
  final Map<XKind, List<XCategory>> categories;

  /// TV guide address named by the playlist itself (#EXTM3U url-tvg="...").
  final String epgUrl;

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
  String _tvgId = '';
  String _epgUrl = '';
  int _total = 0;

  void add(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return;
    if (line.startsWith('#EXTM3U')) {
      // The playlist header may name its own TV guide: url-tvg / x-tvg-url.
      for (final m in _attribute.allMatches(line)) {
        final key = m.group(1)!.toLowerCase();
        if ((key == 'url-tvg' || key == 'x-tvg-url') && _epgUrl.isEmpty) {
          _epgUrl = m.group(2)!.trim().split(',').first.trim();
        }
      }
      return;
    }
    if (line.startsWith('#EXTINF')) {
      _logo = '';
      _group = '';
      _tvgId = '';
      var nameFrom = 0;
      String tvgName = '';
      for (final m in _attribute.allMatches(line)) {
        final key = m.group(1)!.toLowerCase();
        final value = m.group(2)!.trim();
        if (key == 'tvg-logo') _logo = value;
        if (key == 'group-title') _group = value;
        if (key == 'tvg-name') tvgName = value;
        if (key == 'tvg-id') _tvgId = value;
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
    final tvgId = _tvgId;
    _name = null;
    _logo = '';
    _group = '';
    _tvgId = '';
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
      epgId: kind == XKind.live ? tvgId : '',
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
    return M3uData(_items, categories, epgUrl: _epgUrl);
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
  M3uSource(this.url, {this.epgUrl = ''});

  final String url;

  /// XMLTV guide address from the website (playlist settings). When empty,
  /// the address named inside the playlist itself (url-tvg) is used.
  final String epgUrl;

  Future<M3uData>? _loading;
  Future<Map<String, List<XEpg>>>? _guideLoading;

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

  /// A playlist only knows the name and the picture of a movie.
  @override
  Future<XMovieInfo> movieInfo(XItem item) async => XMovieInfo(cover: item.icon);

  /// Now/next from the XMLTV guide; [streamId] is the channel's tvg-id.
  @override
  Future<List<XEpg>> shortEpg(String streamId) async {
    if (streamId.isEmpty) return const [];
    final guide = await _guide();
    final list = guide[streamId] ?? guide[streamId.toLowerCase()] ?? const <XEpg>[];
    final now = DateTime.now();
    return list.where((e) => e.end.isAfter(now)).take(4).toList();
  }

  /// Downloads and parses the XMLTV guide once per app start. Best effort:
  /// any problem simply means "no guide", never an error on screen.
  Future<Map<String, List<XEpg>>> _guide() {
    final running = _guideLoading;
    if (running != null) return running;
    final future = _downloadGuide();
    _guideLoading = future;
    future.then((_) {}, onError: (Object _) {
      if (identical(_guideLoading, future)) _guideLoading = null;
    });
    return future;
  }

  Future<Map<String, List<XEpg>>> _downloadGuide() async {
    try {
      var address = epgUrl.trim();
      if (address.isEmpty) address = (await _load()).epgUrl;
      if (address.isEmpty) return const {};
      final uri = Uri.tryParse(address);
      if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return const {};

      final client = http.Client();
      List<int> bytes;
      try {
        final request = http.Request('GET', uri);
        request.headers['User-Agent'] = kUserAgent;
        final response = await client.send(request).timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) return const {};
        // TV sticks have little memory: stop after 24 MB and use what arrived
        // (the regex parser only reads complete <programme> blocks anyway).
        const cap = 24 * 1024 * 1024;
        final buffer = BytesBuilder(copy: false);
        await for (final chunk in response.stream.timeout(const Duration(seconds: 60))) {
          buffer.add(chunk);
          if (buffer.length >= cap) break;
        }
        bytes = buffer.takeBytes();
      } finally {
        client.close();
      }

      // .gz guides are common; gzip starts with 1f 8b.
      if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        try {
          bytes = GZipDecoder().decodeBytes(bytes);
        } catch (_) {
          return const {};
        }
        if (bytes.length > 160 * 1024 * 1024) return const {};
      }

      final xml = utf8.decode(bytes, allowMalformed: true);
      final guide = xml.length > 200000
          ? await compute(parseXmltv, xml)
          : parseXmltv(xml);
      log('epg guide channels=${guide.length}');
      return guide;
    } catch (e) {
      log('epg guide failed: ${e.runtimeType}');
      return const {};
    }
  }

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

/// Parses an XMLTV guide into channel-id -> programmes (today and tomorrow).
/// Top level so it can run in a background isolate via [compute].
Map<String, List<XEpg>> parseXmltv(String xml) {
  final programme = RegExp(
      r'<programme[^>]*?start="([^"]+)"[^>]*?(?:stop="([^"]+)")?[^>]*?channel="([^"]+)"[^>]*>(.*?)</programme>',
      dotAll: true);
  final titleTag = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true);

  final now = DateTime.now();
  final from = now.subtract(const Duration(hours: 3));
  final to = now.add(const Duration(hours: 36));
  final out = <String, List<XEpg>>{};

  for (final m in programme.allMatches(xml)) {
    final start = xmltvTime(m.group(1) ?? '');
    if (start == null || start.isAfter(to)) continue;
    final end = xmltvTime(m.group(2) ?? '') ?? start.add(const Duration(hours: 1));
    if (end.isBefore(from)) continue;
    final channel = (m.group(3) ?? '').trim();
    if (channel.isEmpty) continue;
    final body = m.group(4) ?? '';
    final title = _xmlText(titleTag.firstMatch(body)?.group(1) ?? '');
    if (title.isEmpty) continue;
    final list = out.putIfAbsent(channel, () => <XEpg>[]);
    if (list.length >= 60) continue;
    list.add(XEpg(title, start, end));
  }
  for (final list in out.values) {
    list.sort((a, b) => a.start.compareTo(b.start));
  }
  return out;
}

/// XMLTV time: "20261010020000 +0500" style -> local DateTime.
DateTime? xmltvTime(String s) {
  s = s.trim();
  if (s.length < 12) return null;
  int? part(int a, int b) => int.tryParse(s.substring(a, b));
  final y = part(0, 4), mo = part(4, 6), d = part(6, 8), h = part(8, 10), mi = part(10, 12);
  if (y == null || mo == null || d == null || h == null || mi == null) return null;
  final se = s.length >= 14 ? (part(12, 14) ?? 0) : 0;
  var utc = DateTime.utc(y, mo, d, h, mi, se);
  final offset = RegExp(r'([+-])(\d{2})(\d{2})').firstMatch(s.length > 14 ? s.substring(14) : '');
  if (offset != null) {
    final shift = Duration(hours: int.parse(offset.group(2)!), minutes: int.parse(offset.group(3)!));
    utc = offset.group(1) == '-' ? utc.add(shift) : utc.subtract(shift);
  }
  return utc.toLocal();
}

String _xmlText(String s) => s
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
