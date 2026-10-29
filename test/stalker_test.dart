import 'package:b1gtv/stalker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MAG helpers', () {
    test('cleanMac accepts common spellings and rejects the rest', () {
      expect(cleanMac('00:1a:79:12:34:56'), '00:1A:79:12:34:56');
      expect(cleanMac('00-1A-79-12-34-56'), '00:1A:79:12:34:56');
      expect(cleanMac('001A79123456'), '00:1A:79:12:34:56');
      expect(cleanMac('00:1A:79:12:34'), '');
      expect(cleanMac(''), '');
      expect(cleanMac('zz:1A:79:12:34:56'), '');
    });

    test('generateMac makes a MAG-range address', () {
      for (var i = 0; i < 20; i++) {
        final m = generateMac();
        expect(m.startsWith('00:1A:79:'), true);
        expect(cleanMac(m), m);
      }
    });

    test('stalkerAddress finds the stream address inside a portal command', () {
      expect(stalkerAddress('ffmpeg http://host:80/live/abc/123.ts'), 'http://host:80/live/abc/123.ts');
      expect(stalkerAddress('ffrt http://localhost/ch/12'), 'http://localhost/ch/12');
      expect(stalkerAddress('/media/55.mpg'), '');
    });
  });
}
