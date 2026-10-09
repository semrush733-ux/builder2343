import 'package:b1gtv/backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
