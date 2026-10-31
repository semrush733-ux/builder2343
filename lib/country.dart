import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:http/http.dart' as http;

import 'store.dart';

/// A country the app can put first in the channel lists.
class Country {
  const Country(this.code, this.name, this.words);
  final String code;
  final String name;

  /// Short codes (2-3 letters) and names as playlists write them in category titles.
  final List<String> words;

  static const all = <Country>[
    Country('GB', 'United Kingdom', ['uk', 'gb', 'united kingdom', 'britain', 'british', 'england', 'scotland', 'wales']),
    Country('US', 'United States', ['us', 'usa', 'united states', 'america', 'american']),
    Country('CA', 'Canada', ['ca', 'can', 'canada', 'canadian']),
    Country('AU', 'Australia', ['au', 'aus', 'australia', 'australian']),
    Country('NZ', 'New Zealand', ['nz', 'new zealand']),
    Country('IE', 'Ireland', ['ie', 'irl', 'ireland', 'irish']),
    Country('SA', 'Saudi Arabia', ['sa', 'ksa', 'saudi', 'saudi arabia']),
    Country('AE', 'United Arab Emirates', ['ae', 'uae', 'emirates', 'dubai', 'abu dhabi']),
    Country('QA', 'Qatar', ['qa', 'qatar']),
    Country('KW', 'Kuwait', ['kw', 'kuwait']),
    Country('BH', 'Bahrain', ['bh', 'bahrain']),
    Country('OM', 'Oman', ['om', 'oman']),
    Country('EG', 'Egypt', ['eg', 'egypt', 'egyptian']),
    Country('JO', 'Jordan', ['jo', 'jordan']),
    Country('LB', 'Lebanon', ['lb', 'lebanon', 'lebanese']),
    Country('IQ', 'Iraq', ['iq', 'iraq']),
    Country('MA', 'Morocco', ['ma', 'morocco', 'maroc']),
    Country('DZ', 'Algeria', ['dz', 'algeria', 'algerie']),
    Country('TN', 'Tunisia', ['tn', 'tunisia', 'tunisie']),
    Country('TR', 'Turkey', ['tr', 'turkey', 'turkiye', 'turkish']),
    Country('PK', 'Pakistan', ['pk', 'pak', 'pakistan', 'pakistani']),
    Country('IN', 'India', ['in', 'ind', 'india', 'indian', 'hindi']),
    Country('BD', 'Bangladesh', ['bd', 'bangladesh', 'bangla']),
    Country('LK', 'Sri Lanka', ['lk', 'sri lanka']),
    Country('AF', 'Afghanistan', ['af', 'afghanistan', 'afghan']),
    Country('IR', 'Iran', ['ir', 'iran', 'persian']),
    Country('PT', 'Portugal', ['pt', 'prt', 'portugal', 'portuguese']),
    Country('ES', 'Spain', ['es', 'esp', 'spain', 'spanish', 'espana']),
    Country('FR', 'France', ['fr', 'fra', 'france', 'french']),
    Country('DE', 'Germany', ['de', 'ger', 'deu', 'germany', 'german', 'deutschland']),
    Country('IT', 'Italy', ['it', 'ita', 'italy', 'italian', 'italia']),
    Country('NL', 'Netherlands', ['nl', 'netherlands', 'dutch', 'holland']),
    Country('BE', 'Belgium', ['be', 'belgium', 'belgian']),
    Country('CH', 'Switzerland', ['ch', 'switzerland', 'swiss']),
    Country('AT', 'Austria', ['at', 'austria', 'austrian']),
    Country('PL', 'Poland', ['pl', 'poland', 'polish']),
    Country('RO', 'Romania', ['ro', 'romania', 'romanian']),
    Country('GR', 'Greece', ['gr', 'greece', 'greek']),
    Country('SE', 'Sweden', ['se', 'sweden', 'swedish']),
    Country('NO', 'Norway', ['no', 'norway', 'norwegian']),
    Country('DK', 'Denmark', ['dk', 'denmark', 'danish']),
    Country('FI', 'Finland', ['fi', 'finland', 'finnish']),
    Country('RU', 'Russia', ['ru', 'russia', 'russian']),
    Country('UA', 'Ukraine', ['ua', 'ukraine', 'ukrainian']),
    Country('BR', 'Brazil', ['br', 'brazil', 'brasil']),
    Country('MX', 'Mexico', ['mx', 'mexico']),
    Country('AR', 'Argentina', ['ar', 'argentina']),
    Country('NG', 'Nigeria', ['ng', 'nigeria', 'nigerian']),
    Country('ZA', 'South Africa', ['za', 'south africa']),
    Country('KE', 'Kenya', ['ke', 'kenya']),
    Country('ID', 'Indonesia', ['id', 'indonesia']),
    Country('MY', 'Malaysia', ['my', 'malaysia']),
    Country('PH', 'Philippines', ['ph', 'philippines', 'filipino']),
    Country('TH', 'Thailand', ['th', 'thailand', 'thai']),
    Country('VN', 'Vietnam', ['vn', 'vietnam']),
    Country('CN', 'China', ['cn', 'china', 'chinese']),
    Country('JP', 'Japan', ['jp', 'japan', 'japanese']),
    Country('KR', 'South Korea', ['kr', 'korea', 'korean']),
  ];

  static Country? byCode(String code) {
    final c = code.toUpperCase();
    for (final x in all) {
      if (x.code == c) return x;
    }
    return null;
  }

  /// The country in use: the one picked in Settings, else the one found for this device.
  static String get active {
    final pref = Store.countryPref;
    if (pref != 'auto') return pref;
    final d = Store.detectedCountry;
    return d.isNotEmpty ? d : (PlatformDispatcher.instance.locale.countryCode ?? '').toUpperCase();
  }

  static Country? get current => byCode(active);

  /// Looks the device's country up once a day (internet address first, the phone's region
  /// setting as the fallback) and remembers it.
  static Future<void> detect() async {
    final last = Store.detectedAt;
    if (Store.detectedCountry.isNotEmpty && DateTime.now().millisecondsSinceEpoch - last < 86400000) return;
    var code = '';
    for (final url in const ['https://api.country.is/', 'https://ipwho.is/']) {
      try {
        final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
        if (r.statusCode != 200) continue;
        final j = jsonDecode(r.body);
        final c = j is Map ? (j['country'] ?? j['country_code'] ?? '').toString() : '';
        if (c.length == 2) {
          code = c.toUpperCase();
          break;
        }
      } on TimeoutException {
        // try the next one
      } on SocketException {
        // offline
      } catch (_) {}
    }
    if (code.isEmpty) code = (PlatformDispatcher.instance.locale.countryCode ?? '').toUpperCase();
    if (code.isNotEmpty) Store.setDetectedCountry(code);
  }

  /// Does a category / channel title belong to this country? Names are matched as whole words;
  /// short codes only where playlists put them: at the start ("UK | Sports") or in brackets.
  bool matches(String title) {
    final n = title.toLowerCase();
    for (final w in words) {
      if (w.length > 3) {
        if (RegExp('(^|[^a-z])${RegExp.escape(w)}([^a-z]|\$)').hasMatch(n)) return true;
      } else {
        final e = RegExp.escape(w);
        if (RegExp('^[^a-z0-9]*$e([^a-z0-9]|\$)').hasMatch(n) && RegExp('^[^a-z0-9]*$e\\s*[|:\\-\\]\\)/]').hasMatch(n)) return true;
        if (RegExp('[|\\[\\(]\\s*$e\\s*[|\\]\\)]').hasMatch(n)) return true;
        if (RegExp('\\s[-|]\\s*$e\\s*[-|]').hasMatch(n)) return true;
      }
    }
    return false;
  }
}
