import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.signedOut = false});
  final String message;
  final bool signedOut;
  @override
  String toString() => message;
}

class Change {
  Change(Map<String, dynamic> j)
      : id = '${j['id'] ?? ''}',
        what = '${j['what'] ?? ''}',
        from = '${j['from'] ?? ''}',
        to = '${j['to'] ?? ''}',
        time = DateTime.fromMillisecondsSinceEpoch(((j['time'] as num?) ?? 0).toInt() * 1000, isUtc: true);
  final String id, what, from, to;
  final DateTime time;
}

class AppState {
  AppState(Map<String, dynamic> j)
      : site = '${j['site'] ?? ''}',
        serverUrl = '${j['server_url'] ?? ''}',
        serverName = '${j['server_name'] ?? ''}',
        host = '${j['host'] ?? ''}',
        history = [
          for (final h in (j['history'] is List ? j['history'] as List : const []))
            if (h is Map<String, dynamic>) Change(h)
        ];
  final String site, serverUrl, serverName, host;
  final List<Change> history;
}

class Reply {
  Reply(this.ok, this.message, [this.state]);
  final bool ok;
  final String message;
  final AppState? state;
}

class Api {
  static SharedPreferences? _p;
  static String site = '';
  static String token = '';

  static bool get signedIn => site.isNotEmpty && token.isNotEmpty;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    site = _p!.getString('site') ?? '';
    token = _p!.getString('token') ?? '';
  }

  /// "playercloud.app", "https://playercloud.app/" -> "https://playercloud.app"
  static String cleanSite(String v) {
    var s = v.trim();
    if (s.isEmpty) return '';
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(s)) s = 'https://$s';
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty || u.scheme != 'https') return '';
    final i = u.path.indexOf('/wp-json');
    var path = i >= 0 ? u.path.substring(0, i) : u.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return 'https://${u.host}${u.hasPort && u.port != 443 ? ':${u.port}' : ''}$path';
  }

  static Uri _url(String base, String path) => Uri.parse('$base/wp-json/cloudadmin/v1/$path');

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        if (token.isNotEmpty) 'X-CPA-Token': token,
      };

  static Future<Map<String, dynamic>> _send(String method, String base, String path, [Map<String, dynamic>? body]) async {
    try {
      final uri = _url(base, path);
      final res = method == 'GET'
          ? await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 25))
          : await http.post(uri, headers: _headers(), body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 40));
      Map<String, dynamic> j = {};
      try {
        final d = jsonDecode(res.body);
        if (d is Map<String, dynamic>) j = d;
      } catch (_) {}
      if (res.statusCode == 401) {
        throw ApiException('Please sign in again.', signedOut: true);
      }
      if (res.statusCode == 404 && j.isEmpty) {
        throw ApiException('The Cloud Player Admin plugin was not found on this website.');
      }
      if (j.isEmpty) throw ApiException('The website sent an answer this app does not understand (${res.statusCode}).');
      return j;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('The website did not answer in time. Try again.');
    } catch (_) {
      throw ApiException('Cannot reach the website. Check the address and your internet.');
    }
  }

  static Future<Reply> login(String siteInput, String user, String pass) async {
    final base = cleanSite(siteInput);
    if (base.isEmpty) return Reply(false, 'Enter your website like https://playercloud.app');
    token = '';
    final j = await _send('POST', base, 'login', {'username': user.trim(), 'password': pass});
    if (j['success'] != true) return Reply(false, '${j['message'] ?? 'Sign in failed.'}');
    site = base;
    token = '${j['token'] ?? ''}';
    await _p?.setString('site', site);
    await _p?.setString('token', token);
    return Reply(true, 'Signed in.', AppState(j));
  }

  static Future<void> signOut({bool tellSite = true}) async {
    if (tellSite && signedIn) {
      try {
        await _send('POST', site, 'logout');
      } catch (_) {}
    }
    token = '';
    await _p?.remove('token');
  }

  static Future<AppState> state() async {
    final j = await _send('GET', site, 'state');
    return AppState(j);
  }

  static Future<Reply> check(String newSite) async {
    final j = await _send('POST', site, 'check', {'site': newSite});
    return Reply(j['success'] == true, '${j['message'] ?? ''}');
  }

  static Future<Reply> save({required String newSite, String? serverUrl, String? serverName, bool force = false}) async {
    final j = await _send('POST', site, 'save', {
      'site': newSite,
      if (serverUrl != null) 'server_url': serverUrl,
      if (serverName != null) 'server_name': serverName,
      'force': force,
    });
    return Reply(j['success'] == true, '${j['message'] ?? ''}', j.containsKey('host') ? AppState(j) : null);
  }

  static Future<Reply> restore(String id) async {
    final j = await _send('POST', site, 'restore', {'id': id});
    return Reply(j['success'] == true, '${j['message'] ?? ''}', j.containsKey('host') ? AppState(j) : null);
  }
}
