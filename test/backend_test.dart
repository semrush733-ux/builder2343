import 'package:b1gtv/backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('identifiers sent with the registration', () {
    test('a real network card address is accepted, placeholders and privacy addresses are not', () {
      expect(isRealMac('A4:5E:60:C1:22:9F'), true);
      expect(isRealMac('a4:5e:60:c1:22:9f'), true);
      expect(isRealMac('02:00:00:00:00:00'), false); // Android's dummy
      expect(isRealMac('00:00:00:00:00:00'), false);
      expect(isRealMac('FF:FF:FF:FF:FF:FF'), false);
      expect(isRealMac('DA:A1:19:3B:7C:01'), false); // made up per Wi-Fi network
      expect(isRealMac(''), false);
      expect(isRealMac('A4-5E-60-C1-22-9F'), false);
    });

    test('device ID always, the first real address only', () {
      expect(
        registrationIds({
          'hwid': '9f8e7d6c5b4a3921',
          'macs': ['02:00:00:00:00:00', 'a4:5e:60:c1:22:9f'],
        }),
        {'hwid': '9f8e7d6c5b4a3921', 'mac': 'A4:5E:60:C1:22:9F'},
      );
    });

    test('no real address: the field is left out', () {
      expect(registrationIds({'hwid': 'abc', 'macs': ['02:00:00:00:00:00']}), {'hwid': 'abc'});
      expect(registrationIds({'hwid': '', 'macs': []}), isEmpty);
      expect(registrationIds(null), isEmpty);
    });
  });

  group('update announced by the website', () {
    test('reads version, link, notes and the force switch', () {
      final u = BUpdate.fromJson({
        'version_code': '21',
        'version_name': '1.0.21',
        'apk_url': ' https://example.com/B1G.apk ',
        'notes': 'Faster start',
        'force': 1,
      })!;
      expect(u.versionCode, 21);
      expect(u.versionName, '1.0.21');
      expect(u.apkUrl, 'https://example.com/B1G.apk');
      expect(u.notes, 'Faster start');
      expect(u.force, true);
    });

    test('nothing announced, no link or no number means no update', () {
      expect(BUpdate.fromJson(null), isNull);
      expect(BUpdate.fromJson({'version_code': 21, 'apk_url': ''}), isNull);
      expect(BUpdate.fromJson({'version_code': 0, 'apk_url': 'https://example.com/B1G.apk'}), isNull);
      expect(BUpdate.fromJson({'version_code': 21, 'apk_url': 'B1G.apk'}), isNull);
    });

    test('an update is only offered for a higher build number than the installed one', () {
      Backend.update = BUpdate(versionCode: 21, versionName: '1.0.21', apkUrl: 'https://example.com/B1G.apk');
      Backend.appVersionCode = 20;
      expect(Backend.updateAvailable, true);
      Backend.appVersionCode = 21;
      expect(Backend.updateAvailable, false);
      Backend.appVersionCode = 0; // version unknown: never offer
      expect(Backend.updateAvailable, false);
      Backend.update = null;
    });
  });
}
