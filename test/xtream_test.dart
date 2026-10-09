import 'dart:convert';

import 'package:b1gtv/screens/player.dart';
import 'package:b1gtv/store.dart';
import 'package:b1gtv/xtream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('server address', () {
    test('adds http and removes the trailing slash', () {
      final p = parseServerInput(' example.com:8080/ ');
      expect(p.server, 'http://example.com:8080');
      expect(p.hadScheme, false);
      expect(p.username, isNull);
    });

    test('keeps https', () {
      final p = parseServerInput('https://tv.example.com');
      expect(p.server, 'https://tv.example.com');
      expect(p.hadScheme, true);
    });

    test('reads username and password from a playlist link', () {
      final p = parseServerInput('http://example.com:2095/get.php?username=bob&password=s3cret&type=m3u_plus');
      expect(p.server, 'http://example.com:2095');
      expect(p.username, 'bob');
      expect(p.password, 's3cret');
    });

    test('empty input', () {
      expect(parseServerInput('   ').server, '');
    });
  });

  group('account', () {
    test('active account', () {
      final a = parseAccount({
        'user_info': {'auth': 1, 'status': 'Active', 'exp_date': '1893456000', 'max_connections': '2', 'is_trial': '0'},
      });
      expect(a.maxConnections, 2);
      expect(a.expires, isNotNull);
      expect(a.isTrial, false);
    });

    test('wrong password', () {
      expect(() => parseAccount({'user_info': {'auth': 0}}), throwsA(isA<XtreamAuthException>()));
    });

    test('expired account', () {
      expect(() => parseAccount({'user_info': {'auth': 1, 'status': 'Expired'}}),
          throwsA(isA<XtreamAuthException>()));
    });

    test('not an IPTV server', () {
      expect(() => parseAccount('<html>'), throwsA(isA<XtreamException>()));
    });
  });

  group('lists', () {
    test('items accept numbers or text as ids', () {
      final items = parseItems([
        {'num': 1, 'name': ' BBC One ', 'stream_id': 101, 'stream_icon': 'http://x/logo.png', 'category_id': '5'},
        {'num': '2', 'name': 'ITV', 'stream_id': '102', 'category_id': 5},
        {'name': 'broken'},
      ], XKind.live);
      expect(items.length, 2);
      expect(items[0].name, 'BBC One');
      expect(items[0].id, '101');
      expect(items[1].categoryId, '5');
    });

    test('series use series_id and cover', () {
      final items = parseItems([
        {'series_id': 7, 'name': 'Show', 'cover': 'http://x/c.jpg'}
      ], XKind.series);
      expect(items.single.id, '7');
      expect(items.single.icon, 'http://x/c.jpg');
    });

    test('categories', () {
      final cats = parseCategories([
        {'category_id': '5', 'category_name': 'UK'},
        {'category_id': 6, 'category_name': ''},
      ]);
      expect(cats.length, 2);
      expect(cats[1].name, 'Category 6');
    });

    test('an error object instead of a list gives an empty list', () {
      expect(parseItems(null, XKind.vod), isEmpty);
      expect(parseCategories('nope'), isEmpty);
    });

    test('item survives saving as a favourite', () {
      const item = XItem(kind: XKind.vod, id: '9', name: 'Film', icon: 'http://x/p.jpg', ext: 'mkv');
      final copy = XItem.fromJson(jsonDecode(jsonEncode(item.toJson())))!;
      expect(copy.kind, XKind.vod);
      expect(copy.ext, 'mkv');
      expect(copy.name, 'Film');
    });
  });

  test('TV guide titles are decoded', () {
    final list = parseEpg({
      'epg_listings': [
        {'title': base64.encode(utf8.encode('News at Ten')), 'start_timestamp': '2000', 'stop_timestamp': '3000'},
        {'title': base64.encode(utf8.encode('Breakfast')), 'start_timestamp': 1000, 'stop_timestamp': 2000},
        {'title': 'x', 'start_timestamp': 0, 'stop_timestamp': 0},
      ]
    });
    expect(list.length, 2);
    expect(list.first.title, 'Breakfast');
    expect(list.last.title, 'News at Ten');
  });

  test('series seasons and episodes are sorted', () {
    final info = parseSeriesInfo({
      'info': {'plot': 'A story', 'cover': 'http://x/c.jpg'},
      'episodes': {
        '2': [
          {'id': '21', 'episode_num': 1, 'title': 'S2E1', 'container_extension': 'mkv', 'season': 2}
        ],
        '1': [
          {'id': '12', 'episode_num': '2', 'title': '', 'container_extension': '', 'season': 1},
          {'id': '11', 'episode_num': '1', 'title': 'Pilot', 'container_extension': 'mp4', 'season': 1, 'info': {'duration': '00:45:00'}},
        ],
      },
    });
    expect(info.plot, 'A story');
    expect(info.seasons.keys.toList(), [1, 2]);
    expect(info.seasons[1]!.map((e) => e.id).toList(), ['11', '12']);
    expect(info.seasons[1]![1].title, 'Episode 2');
    expect(info.seasons[1]![1].ext, 'mp4');
    expect(info.seasons[1]![0].duration, '00:45:00');
  });

  test('stream addresses', () {
    final api = XtreamApi('http://example.com:8080', 'bob', 'p@ss word');
    expect(api.liveUrl('5', 'ts'), 'http://example.com:8080/live/bob/p%40ss%20word/5.ts');
    expect(api.vodUrl('6', ''), 'http://example.com:8080/movie/bob/p%40ss%20word/6.mp4');
    expect(api.episodeUrl('7', 'mkv'), 'http://example.com:8080/series/bob/p%40ss%20word/7.mkv');
  });

  test('time format', () {
    expect(formatTime(const Duration(seconds: 65)), '1:05');
    expect(formatTime(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });

  group('storage', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Store.init();
    });

    test('login is remembered and sign out keeps the username', () async {
      expect(Store.loggedIn, false);
      await Store.saveSession('http://s', 'bob', 'pw');
      expect(Store.loggedIn, true);
      await Store.logout();
      expect(Store.loggedIn, false);
      expect(Store.username, 'bob');
      expect(Store.password, '');
    });

    test('favourites toggle', () {
      const item = XItem(kind: XKind.live, id: '1', name: 'One');
      expect(Store.isFavourite(item), false);
      expect(Store.toggleFavourite(item), true);
      expect(Store.favourites(XKind.live).single.name, 'One');
      expect(Store.toggleFavourite(item), false);
      expect(Store.favourites(XKind.live), isEmpty);
    });

    test('resume positions', () {
      Store.setResume('vod:1', 120);
      expect(Store.resume('vod:1'), 120);
      Store.setResume('vod:1', 0);
      expect(Store.resume('vod:1'), 0);
    });
  });
}
