import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'theme.dart';
import 'xtream.dart';

/// Extra film details from TMDB (themoviedb.org): cast with photos, stills, trailer.
/// Used only to decorate the details page; playing never depends on it.

class TmdbPerson {
  const TmdbPerson(this.name, this.character, this.photo);
  final String name;
  final String character;
  final String photo;
}

class TmdbMovie {
  const TmdbMovie({
    this.plot = '',
    this.year = '',
    this.genre = '',
    this.duration = '',
    this.rating = 0,
    this.backdrop = '',
    this.trailer = '',
    this.cast = const [],
    this.stills = const [],
  });

  final String plot;
  final String year;
  final String genre;
  final String duration;
  final double rating;
  final String backdrop;
  final String trailer;
  final List<TmdbPerson> cast;
  final List<String> stills;
}

class CleanTitle {
  const CleanTitle(this.title, this.year);
  final String title;
  final String year;
}

final _bracket = RegExp(r'[\[\(\{][^\]\)\}]*[\]\)\}]');
final _yearIn = RegExp(r'\b(19|20)\d\d\b');
final _tags = RegExp(r'\b(4k|uhd|fhd|hd|sd|hevc|x265|x264|h265|h264|multi|dual audio|bluray|web-?dl|hdr)\b',
    caseSensitive: false);

/// IPTV lists write titles like "EN | Big Film (2024) [4K]": TMDB needs "Big Film" and 2024.
CleanTitle cleanTitle(String raw) {
  var text = raw;
  var year = '';
  for (final m in _bracket.allMatches(raw)) {
    final y = _yearIn.firstMatch(m.group(0)!);
    if (y != null) year = y.group(0)!;
  }
  text = text.replaceAll(_bracket, ' ');
  // "EN | Title" or "4K-EN - Title": drop a short upper-case prefix in front of a separator.
  for (final separator in const ['|', ' - ', ' : ']) {
    final at = text.indexOf(separator);
    if (at <= 0) continue;
    final prefix = text.substring(0, at).trim();
    final rest = text.substring(at + separator.length).trim();
    if (prefix.length <= 6 && prefix == prefix.toUpperCase() && rest.length >= 2) text = rest;
  }
  text = text.replaceAll(_tags, ' ').replaceAll(RegExp(r'[._]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return CleanTitle(text.isEmpty ? raw.trim() : text, year);
}

String _image(String size, dynamic path) {
  final p = str(path);
  return p.isEmpty ? '' : '$kTmdbImages/$size$p';
}

TmdbMovie parseTmdbMovie(dynamic data) {
  if (data is! Map) return const TmdbMovie();
  final cast = <TmdbPerson>[];
  final credits = data['credits'];
  if (credits is Map && credits['cast'] is List) {
    for (final c in (credits['cast'] as List).whereType<Map>().take(14)) {
      final name = str(c['name']);
      if (name.isNotEmpty) cast.add(TmdbPerson(name, str(c['character']), _image('w185', c['profile_path'])));
    }
  }
  final stills = <String>[];
  final images = data['images'];
  if (images is Map && images['backdrops'] is List) {
    for (final b in (images['backdrops'] as List).whereType<Map>().take(10)) {
      final url = _image('w780', b['file_path']);
      if (url.isNotEmpty) stills.add(url);
    }
  }
  var trailer = '';
  final videos = data['videos'];
  if (videos is Map && videos['results'] is List) {
    final list = (videos['results'] as List).whereType<Map>().where((v) => str(v['site']) == 'YouTube').toList();
    final pick = list.where((v) => str(v['type']) == 'Trailer').toList();
    final chosen = pick.isNotEmpty ? pick.first : (list.isNotEmpty ? list.first : null);
    if (chosen != null) trailer = str(chosen['key']);
  }
  final genres = data['genres'];
  final minutes = toInt(data['runtime']);
  final date = str(data['release_date']);
  return TmdbMovie(
    plot: str(data['overview']),
    year: date.length >= 4 ? date.substring(0, 4) : '',
    genre: genres is List ? genres.whereType<Map>().map((g) => str(g['name'])).where((g) => g.isNotEmpty).join(', ') : '',
    duration: minutes <= 0 ? '' : (minutes >= 60 ? '${minutes ~/ 60} h ${minutes % 60} min' : '$minutes min'),
    rating: (data['vote_average'] is num) ? (data['vote_average'] as num).toDouble() : 0,
    backdrop: _image('w1280', data['backdrop_path']),
    trailer: trailer,
    cast: cast,
    stills: stills,
  );
}

class Tmdb {
  static bool get enabled => kTmdbKey.isNotEmpty;
  static final Map<String, TmdbMovie?> _cache = {};

  static Future<dynamic> _get(String path, Map<String, String> query) async {
    final uri = Uri.parse('$kTmdbBase$path').replace(queryParameters: {'api_key': kTmdbKey, ...query});
    final res = await http.get(uri, headers: const {'Accept': 'application/json'}).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    return jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
  }

  /// Details for a movie, found by its TMDB id when the server gives one, else by title and year.
  /// Returns null when TMDB is not set up, the film is not found or TMDB cannot be reached.
  static Future<TmdbMovie?> movie({required String title, String tmdbId = '', String year = ''}) async {
    if (!enabled) return null;
    final cacheKey = tmdbId.isNotEmpty ? 'id:$tmdbId' : 't:$title|$year';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];
    TmdbMovie? result;
    try {
      var id = tmdbId;
      if (id.isEmpty) {
        final clean = cleanTitle(title);
        final wantYear = year.isNotEmpty ? year : clean.year;
        dynamic found = await _get('/search/movie', {'query': clean.title, if (wantYear.isNotEmpty) 'year': wantYear});
        if (wantYear.isNotEmpty && (found is! Map || found['results'] is! List || (found['results'] as List).isEmpty)) {
          found = await _get('/search/movie', {'query': clean.title});
        }
        if (found is Map && found['results'] is List && (found['results'] as List).isNotEmpty) {
          final first = (found['results'] as List).first;
          if (first is Map) id = str(first['id']);
        }
      }
      if (id.isNotEmpty) {
        final data = await _get('/movie/$id', const {
          'append_to_response': 'credits,videos,images',
          'include_image_language': 'en,null',
        });
        if (data != null) result = parseTmdbMovie(data);
      }
    } catch (e) {
      log('tmdb failed: ${e.runtimeType}');
      return null; // not cached: try again next time
    }
    _cache[cacheKey] = result;
    return result;
  }
}
