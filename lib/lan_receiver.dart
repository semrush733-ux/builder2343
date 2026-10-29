import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// What a phone sent through the QR page.
class PhoneEntry {
  const PhoneEntry(this.fields);
  final Map<String, String> fields;
  String get type => fields['type'] ?? 'm3u';
  String operator [](String k) => (fields[k] ?? '').trim();
}

/// Tiny web page served from the TV (or phone) on the home Wi-Fi. The QR code on the sign-in
/// screen points to it; whoever scans it types the playlist on their phone's keyboard and it
/// arrives here. Nothing leaves the local network and no website is involved.
class LanReceiver {
  HttpServer? _server;
  final _incoming = StreamController<PhoneEntry>.broadcast();
  String _code = '';

  /// The address to put in the QR code (null until [start] worked).
  String? url;

  Stream<PhoneEntry> get incoming => _incoming.stream;

  static bool _isPrivate(InternetAddress a) {
    if (a.type != InternetAddressType.IPv4) return false;
    final p = a.address.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.contains(null)) return false;
    final a0 = p[0]!, a1 = p[1]!;
    return a0 == 10 || (a0 == 172 && a1 >= 16 && a1 <= 31) || (a0 == 192 && a1 == 168) || (a0 == 169 && a1 == 254);
  }

  static Future<String?> lanIp() async {
    try {
      final list = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      String? best;
      for (final nic in list) {
        for (final a in nic.addresses) {
          if (!_isPrivate(a)) continue;
          final n = nic.name.toLowerCase();
          // Wi-Fi and Ethernet first; mobile data and VPN tunnels last.
          if (n.startsWith('wlan') || n.startsWith('eth') || n.startsWith('en')) return a.address;
          best ??= a.address;
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  Future<String?> start() async {
    await stop();
    final ip = await lanIp();
    if (ip == null) return null;
    final rnd = math.Random.secure();
    _code = (100000 + rnd.nextInt(900000)).toString();
    for (final port in const [8767, 8768, 8769, 8770, 0]) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        break;
      } catch (_) {}
    }
    final s = _server;
    if (s == null) return null;
    s.listen(_handle, onError: (Object _) {});
    return url = 'http://$ip:${s.port}/$_code';
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    url = null;
    try {
      await s?.close(force: true);
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    await _incoming.close();
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      // Only devices on the home network, and only with the code from the QR.
      final remote = req.connectionInfo?.remoteAddress;
      if (remote == null || !(remote.isLoopback || _isPrivate(remote))) {
        req.response.statusCode = 403;
        await req.response.close();
        return;
      }
      final path = req.uri.path;
      if (!(path == '/$_code' || path == '/$_code/' || path == '/$_code/add')) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      if (req.method == 'POST' && path.endsWith('/add')) {
        final body = await utf8.decoder.bind(req).join().timeout(const Duration(seconds: 10));
        final fields = Uri.splitQueryString(body.replaceAll('+', '%20'));
        _incoming.add(PhoneEntry(fields));
        _html(req, _donePage);
        return;
      }
      _html(req, _formPage.replaceAll('{{CODE}}', _code));
    } catch (_) {
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  }

  void _html(HttpRequest req, String body) {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..headers.set('Cache-Control', 'no-store')
      ..write(body);
    req.response.close();
  }
}

const _style = '''
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
*{box-sizing:border-box}body{margin:0;font-family:system-ui,Roboto,sans-serif;background:#06070f;color:#f3f5ff;min-height:100vh;
background:radial-gradient(900px 500px at 10% -10%,#3b2a9a55,transparent),radial-gradient(800px 500px at 100% 100%,#2fe6d033,transparent),#06070f}
.w{max-width:480px;margin:0 auto;padding:26px 18px 40px}
h1{margin:0 0 4px;font-size:34px;font-weight:900;letter-spacing:2px;background:linear-gradient(135deg,#2fe6d0,#7b5cff,#ff4fa3);-webkit-background-clip:text;color:transparent}
.s{color:#8f94b8;font-size:12px;letter-spacing:5px;font-weight:700;margin-bottom:22px}
.t{display:flex;gap:6px;margin-bottom:16px}.t button{flex:1;padding:11px 4px;border:1px solid #2a2f55;background:#0d0f1f;color:#8f94b8;border-radius:12px;font-size:14px;font-weight:700}
.t button.on{color:#06070f;background:#2fe6d0;border-color:#2fe6d0}
label{display:block;font-size:12px;color:#8f94b8;margin:12px 0 5px;font-weight:700;letter-spacing:.5px}
input{width:100%;padding:14px;border-radius:12px;border:1px solid #2a2f55;background:#0d0f1f;color:#f3f5ff;font-size:16px;outline:none}
input:focus{border-color:#2fe6d0}
.go{margin-top:22px;width:100%;padding:16px;border:0;border-radius:14px;font-size:17px;font-weight:800;color:#06070f;background:linear-gradient(135deg,#2fe6d0,#8f7bff)}
.p{display:none}.p.on{display:block}
</style>''';

const _formPage = '''<!doctype html><html><head><meta charset="utf-8"><title>2060 Tele Player</title>$_style</head><body><div class="w">
<h1>2060</h1><div class="s">TELE PLAYER</div>
<div class="t"><button type="button" class="on" data-t="m3u">M3U / URL</button><button type="button" data-t="xtream">Xtream</button><button type="button" data-t="mag">MAG</button></div>
<form method="post" action="/{{CODE}}/add" autocomplete="off">
<input type="hidden" name="type" id="type" value="m3u">
<div class="p on" id="p-m3u"><label>PLAYLIST LINK</label><input name="url" inputmode="url" placeholder="http://...  .m3u / get.php?..."></div>
<div class="p" id="p-xtream"><label>SERVER</label><input name="server" inputmode="url" placeholder="http://host:port">
<label>USERNAME</label><input name="user" autocapitalize="off"><label>PASSWORD</label><input name="pass" autocapitalize="off"></div>
<div class="p" id="p-mag"><label>PORTAL LINK</label><input name="portal" inputmode="url" placeholder="http://host/c/">
<label>MAC ADDRESS (optional)</label><input name="mac" autocapitalize="characters" placeholder="00:1A:79:..."></div>
<button class="go" type="submit">Send to my TV</button></form></div>
<script>
document.querySelectorAll('.t button').forEach(function(b){b.onclick=function(){
document.querySelectorAll('.t button').forEach(function(x){x.classList.remove('on')});b.classList.add('on');
document.getElementById('type').value=b.dataset.t;
document.querySelectorAll('.p').forEach(function(p){p.classList.remove('on')});
document.getElementById('p-'+b.dataset.t).classList.add('on');}});
</script></body></html>''';

const _donePage = '''<!doctype html><html><head><meta charset="utf-8"><title>2060 Tele Player</title>$_style</head><body><div class="w">
<h1>Sent</h1><div class="s">CHECK YOUR TV</div>
<p style="color:#cfd3f0;line-height:1.6">Your playlist was sent. The app is signing in now.<br>You can close this page.</p></div></body></html>''';
