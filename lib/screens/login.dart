import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../backend.dart';
import '../lan_receiver.dart';
import '../m3u.dart';
import '../stalker.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'home.dart';

/// Sign-in: four ways to add a playlist.
///   Xtream Codes  - server, username, password
///   M3U / URL     - paste any playlist link (an Xtream get.php link is recognised too)
///   MAG portal    - portal link + MAC address, like a MAG set-top box
///   QR / Phone    - scan a code, type on the phone, it arrives here
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.message});

  /// Shown above the form, for example after an account expired.
  final String? message;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _xtream = 0, _m3uLink = 1, _mag = 2, _qr = 3;

  final _server = TextEditingController(text: Store.server);
  final _user = TextEditingController(text: Store.username);
  final _pass = TextEditingController();
  final _m3u = TextEditingController(text: Store.m3uUrl);
  final _portal = TextEditingController(text: Store.magPortal);
  late final TextEditingController _macText = TextEditingController(text: Store.magMac);

  final _tabNodes = List.generate(4, (_) => FocusNode());
  final _serverNode = FocusNode();
  final _userNode = FocusNode();
  final _passNode = FocusNode();
  final _m3uNode = FocusNode();
  final _portalNode = FocusNode();
  final _macNode = FocusNode();
  final _buttonNode = FocusNode();

  int _mode = _xtream;
  bool _busy = false;
  String? _error;
  List<BPlaylist> _saved = const [];

  final LanReceiver _lan = LanReceiver();
  StreamSubscription<PhoneEntry>? _lanSub;
  String? _lanUrl;
  bool _lanFailed = false;

  @override
  void initState() {
    super.initState();
    _error = widget.message;
    if (Store.isM3u && Store.m3uUrl.isNotEmpty) _mode = _m3uLink;
    if (Store.isMag && Store.magPortal.isNotEmpty) _mode = _mag;
    log('screen=login');
    _loadSaved();
    _lanSub = _lan.incoming.listen(_fromPhone);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusFirst();
    });
  }

  @override
  void dispose() {
    _lanSub?.cancel();
    _lan.dispose();
    for (final c in [_server, _user, _pass, _m3u, _portal, _macText]) {
      c.dispose();
    }
    for (final n in [..._tabNodes, _serverNode, _userNode, _passNode, _m3uNode, _portalNode, _macNode, _buttonNode]) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final list = await Backend.playlists();
    if (mounted) setState(() => _saved = list);
  }

  void _focusFirst() {
    switch (_mode) {
      case _xtream:
        (_server.text.isEmpty ? _serverNode : (_user.text.isEmpty ? _userNode : _passNode)).requestFocus();
      case _m3uLink:
        _m3uNode.requestFocus();
      case _mag:
        _portalNode.requestFocus();
      default:
        _tabNodes[_qr].requestFocus();
    }
  }

  void _setMode(int mode) {
    if (_busy || _mode == mode) return;
    setState(() {
      _mode = mode;
      _error = null;
    });
    if (mode == _qr) {
      _startLan();
    } else {
      _lan.stop();
      _lanUrl = null;
    }
  }

  Future<void> _startLan() async {
    _lanFailed = false;
    final url = await _lan.start();
    if (!mounted) return;
    setState(() {
      _lanUrl = url;
      _lanFailed = url == null;
    });
  }

  void _fail(Object e) {
    log('login failed: ${e.runtimeType}');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = friendlyError(e);
    });
  }

  void _enter(Source source, XAccount account) {
    if (!mounted) return;
    _lan.stop();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => HomeScreen(api: source, account: account)),
      (_) => false,
    );
  }

  // ---------------------------------------------------------------- sign-in methods

  Future<void> _submit() {
    switch (_mode) {
      case _xtream:
        return _loginXtream(_server.text, _user.text, _pass.text);
      case _m3uLink:
        return _loginM3u(_m3u.text);
      case _mag:
        return _loginMag(_portal.text, _macText.text);
      default:
        return Future<void>.value();
    }
  }

  Future<void> _loginXtream(String serverText, String userText, String passText, {String name = ''}) async {
    if (_busy) return;
    final parsed = parseServerInput(serverText);
    var user = userText.trim();
    var pass = passText.trim();
    // A pasted playlist link carries the username and password itself.
    if (user.isEmpty && pass.isEmpty && parsed.username != null) {
      user = parsed.username!;
      pass = parsed.password ?? '';
    }
    if (parsed.server.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please fill in server, username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var api = XtreamApi(parsed.server, user, pass);
      XAccount account;
      try {
        account = await api.login();
      } on XtreamException {
        rethrow;
      } catch (_) {
        // No "http://" typed and plain http failed: the server may be https only.
        if (parsed.hadScheme || !parsed.server.startsWith('http://')) rethrow;
        api = XtreamApi(parsed.server.replaceFirst('http://', 'https://'), user, pass);
        account = await api.login();
      }
      await Store.saveSession(api.server, user, pass);
      await Backend.savePlaylist(BPlaylist(
          id: 0, name: name.isEmpty ? '$user@${Uri.tryParse(api.server)?.host ?? api.server}' : name, type: 'xtream', url: api.server, username: user, password: pass));
      log('login ok mode=xtream');
      _enter(api, account);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _loginM3u(String typedText, {String epgUrl = ''}) async {
    if (_busy) return;
    final typed = typedText.trim();
    if (typed.isEmpty) {
      setState(() => _error = 'Please paste your playlist link.');
      return;
    }
    final url = typed.contains('://') ? typed : 'http://$typed';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // A link from an Xtream Codes panel (".../get.php?username=..&password=..") is used through
      // the panel's API when that works: it adds the TV guide and series pages and loads faster.
      final parsed = parseServerInput(url);
      if (parsed.username != null && parsed.password != null && url.toLowerCase().contains('get.php')) {
        try {
          final api = XtreamApi(parsed.server, parsed.username!, parsed.password!);
          final account = await api.login();
          await Store.saveSession(api.server, api.username, api.password);
          await Backend.savePlaylist(BPlaylist(
              id: 0,
              name: '${api.username}@${Uri.tryParse(api.server)?.host ?? api.server}',
              type: 'xtream',
              url: api.server,
              username: api.username,
              password: api.password));
          log('login ok mode=xtream (from link)');
          _enter(api, account);
          return;
        } on XtreamAuthException {
          rethrow;
        } catch (_) {
          // Not an Xtream panel after all: read the link as a plain playlist.
        }
      }
      final source = M3uSource(url, epgUrl: epgUrl);
      final account = await source.login();
      await Store.saveM3uSession(url, epgUrl: epgUrl);
      await Backend.savePlaylist(BPlaylist(id: 0, name: source.label, type: 'm3u', url: url, epgUrl: epgUrl));
      log('login ok mode=m3u ${account.note}');
      _enter(source, account);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _loginMag(String portalText, String macTyped) async {
    if (_busy) return;
    final portal = portalText.trim();
    if (portal.isEmpty) {
      setState(() => _error = 'Please enter the portal link.');
      return;
    }
    var mac = cleanMac(macTyped);
    if (macTyped.trim().isNotEmpty && mac.isEmpty) {
      setState(() => _error = 'The MAC address is not valid. Example: 00:1A:79:12:34:56');
      return;
    }
    // No MAC typed: reuse the one from the last time, or make a new one.
    if (mac.isEmpty) {
      mac = Store.magMac.isNotEmpty ? Store.magMac : generateMac();
      _macText.text = mac;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final source = StalkerSource(portal, mac);
      final account = await source.login();
      await Store.saveMagSession(portal, mac);
      await Backend.savePlaylist(BPlaylist(id: 0, name: source.label, type: 'mag', url: portal, mac: mac));
      log('login ok mode=mag');
      _enter(source, account);
    } catch (e) {
      _fail(e);
    }
  }

  void _fromPhone(PhoneEntry e) {
    if (!mounted || _busy) return;
    switch (e.type) {
      case 'xtream':
        _server.text = e['server'];
        _user.text = e['user'];
        _pass.text = e['pass'];
        setState(() => _mode = _xtream);
        _loginXtream(e['server'], e['user'], e['pass']);
      case 'mag':
        _portal.text = e['portal'];
        _macText.text = e['mac'];
        setState(() => _mode = _mag);
        _loginMag(e['portal'], e['mac']);
      default:
        _m3u.text = e['url'];
        setState(() => _mode = _m3uLink);
        _loginM3u(e['url']);
    }
  }

  Future<void> _useSaved(BPlaylist p) async {
    if (_busy) return;
    switch (p.type) {
      case 'xtream':
        _server.text = p.url;
        _user.text = p.username;
        _pass.text = p.password;
        setState(() => _mode = _xtream);
        await _loginXtream(p.url, p.username, p.password, name: p.name);
      case 'mag':
        _portal.text = p.url;
        _macText.text = p.mac;
        setState(() => _mode = _mag);
        await _loginMag(p.url, p.mac);
      default:
        _m3u.text = p.url;
        setState(() => _mode = _m3uLink);
        await _loginM3u(p.url, epgUrl: p.epgUrl);
    }
  }

  // ---------------------------------------------------------------- widgets

  Widget _tab(int mode, IconData icon, String label) {
    final selected = _mode == mode;
    return Expanded(
      child: TvFocus(
        focusNode: _tabNodes[mode],
        selected: selected,
        radius: 12,
        color: selected ? const Color(0xFF1F2350) : C.panel,
        onTap: () => _setMode(mode),
        child: SizedBox(
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: selected ? C.accent : C.dim),
              const SizedBox(height: 3),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: selected ? FontWeight.w800 : FontWeight.w500, color: selected ? C.text : C.dim)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form() {
    switch (_mode) {
      case _xtream:
        return Column(key: const ValueKey('x'), children: [
          TvField(
              controller: _server,
              label: 'Server  (http://host:port)',
              icon: Icons.dns_rounded,
              focusNode: _serverNode,
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _userNode.requestFocus()),
          const SizedBox(height: 10),
          TvField(
              controller: _user,
              label: 'Username',
              icon: Icons.person_rounded,
              focusNode: _userNode,
              onSubmitted: (_) => _passNode.requestFocus()),
          const SizedBox(height: 10),
          TvField(
              controller: _pass,
              label: 'Password',
              icon: Icons.lock_rounded,
              focusNode: _passNode,
              obscure: true,
              action: TextInputAction.done,
              onSubmitted: (_) => _buttonNode.requestFocus()),
        ]);
      case _m3uLink:
        return Column(key: const ValueKey('m'), children: [
          TvField(
              controller: _m3u,
              label: 'Playlist link  (paste any URL)',
              icon: Icons.link_rounded,
              focusNode: _m3uNode,
              keyboardType: TextInputType.url,
              action: TextInputAction.done,
              onSubmitted: (_) => _buttonNode.requestFocus()),
          const SizedBox(height: 10),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Works with .m3u / .m3u8 links and Xtream "get.php" links.',
                style: TextStyle(color: C.dim, fontSize: 12.5)),
          ),
        ]);
      case _mag:
        return Column(key: const ValueKey('g'), children: [
          TvField(
              controller: _portal,
              label: 'Portal link  (http://host/c/)',
              icon: Icons.settings_input_antenna_rounded,
              focusNode: _portalNode,
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _macNode.requestFocus()),
          const SizedBox(height: 10),
          TvField(
              controller: _macText,
              label: 'MAC address  (empty = make one)',
              icon: Icons.memory_rounded,
              focusNode: _macNode,
              action: TextInputAction.done,
              onSubmitted: (_) => _buttonNode.requestFocus()),
          const SizedBox(height: 10),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Give this MAC to your provider if the portal asks for it.',
                style: TextStyle(color: C.dim, fontSize: 12.5)),
          ),
        ]);
      default:
        return Padding(
          key: const ValueKey('q'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 190,
                height: 190,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: _lanUrl == null
                    ? (_lanFailed
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: Text('Connect to Wi-Fi first', textAlign: TextAlign.center, style: TextStyle(color: Colors.black87)))
                        : const SizedBox(width: 30, height: 30, child: Spinner()))
                    : QrImageView(data: _lanUrl!, padding: const EdgeInsets.all(12), backgroundColor: Colors.white),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Scan with your phone', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text('Open the camera, scan the code and type your playlist on the phone. '
                        'It arrives here and signs in by itself. Phone and this screen must be on the same Wi-Fi.',
                        style: TextStyle(color: C.dim, fontSize: 13.5, height: 1.45)),
                    if (_lanUrl != null) ...[
                      const SizedBox(height: 10),
                      Text(_lanUrl!, style: const TextStyle(color: C.accent, fontSize: 12.5)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _savedList() {
    if (_saved.isEmpty) return const SizedBox();
    final shown = _saved.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 26),
        const Text('SAVED PLAYLISTS', style: TextStyle(fontSize: 11.5, letterSpacing: 3, color: C.dim, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        for (final p in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TvFocus(
              radius: 12,
              color: C.panel,
              onTap: () => _useSaved(p),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  children: [
                    Icon(p.isMag ? Icons.settings_input_antenna_rounded : (p.isXtream ? Icons.dns_rounded : Icons.link_rounded),
                        size: 18, color: C.accent),
                    const SizedBox(width: 12),
                    Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
                    const SizedBox(width: 8),
                    Text(p.isMag ? 'MAG' : (p.isXtream ? 'XTREAM' : 'M3U'),
                        style: const TextStyle(fontSize: 10.5, color: C.dim, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Aurora(),
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(52, 24, 20, 24),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 18),
                          const Logo(size: 54),
                          const SizedBox(height: 26),
                          const Text('Your whole TV,\nin one smooth player.',
                              style: TextStyle(fontSize: 27, height: 1.25, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 10),
                          const Text('Xtream  ·  M3U  ·  MAG  ·  QR', style: TextStyle(fontSize: 14.5, color: C.dim, letterSpacing: 1.2)),
                          _savedList(),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 560),
                      margin: const EdgeInsets.fromLTRB(8, 16, 40, 16),
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xCC0D0F1F),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: const Color(0x2AFFFFFF)),
                        boxShadow: const [BoxShadow(color: Color(0x557B5CFF), blurRadius: 60, spreadRadius: -18)],
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                _tab(_xtream, Icons.dns_rounded, 'Xtream'),
                                const SizedBox(width: 8),
                                _tab(_m3uLink, Icons.link_rounded, 'M3U / URL'),
                                const SizedBox(width: 8),
                                _tab(_mag, Icons.settings_input_antenna_rounded, 'MAG'),
                                const SizedBox(width: 8),
                                _tab(_qr, Icons.qr_code_2_rounded, 'QR'),
                              ],
                            ),
                            const SizedBox(height: 18),
                            AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: _form()),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(_error!, style: const TextStyle(color: C.danger, fontSize: 13.5, height: 1.35)),
                              ),
                            if (_mode != _qr) ...[
                              const SizedBox(height: 18),
                              TvFocus(
                                focusNode: _buttonNode,
                                radius: 14,
                                color: C.accent,
                                focusBorder: Colors.white,
                                onTap: () {
                                  if (!_busy) _submit();
                                },
                                child: SizedBox(
                                  height: 52,
                                  child: Center(
                                    child: _busy
                                        ? const SizedBox(width: 22, height: 22, child: Spinner())
                                        : const Text('Continue',
                                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.black)),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
