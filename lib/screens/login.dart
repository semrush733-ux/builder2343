import 'package:flutter/material.dart';

import '../config.dart';
import '../m3u.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.message});

  /// Shown above the form, for example after an account expired.
  final String? message;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _server;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  late final TextEditingController _m3u;
  final _xtreamTabNode = FocusNode();
  final _m3uTabNode = FocusNode();
  final _serverNode = FocusNode();
  final _userNode = FocusNode();
  final _passNode = FocusNode();
  final _m3uNode = FocusNode();
  final _buttonNode = FocusNode();
  bool _m3uMode = false;
  bool _busy = false;
  String? _error;

  /// A build that is locked to one server only asks for username and password.
  bool get _locked => kLockedServer.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: kPrefillServer.isNotEmpty ? kPrefillServer : Store.server);
    _user = TextEditingController(text: kPrefillUser.isNotEmpty ? kPrefillUser : Store.username);
    _pass = TextEditingController(text: kPrefillPass);
    _m3u = TextEditingController(text: Store.m3uUrl);
    _m3uMode = !_locked && Store.isM3u && Store.m3uUrl.isNotEmpty;
    _error = widget.message;
    log('screen=login');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_m3uMode) {
        (_m3u.text.isEmpty ? _m3uNode : _buttonNode).requestFocus();
      } else if (!_locked && _server.text.isEmpty) {
        _serverNode.requestFocus();
      } else if (_user.text.isEmpty) {
        _userNode.requestFocus();
      } else if (_pass.text.isEmpty) {
        _passNode.requestFocus();
      } else {
        _buttonNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    _m3u.dispose();
    for (final node in [_xtreamTabNode, _m3uTabNode, _serverNode, _userNode, _passNode, _m3uNode, _buttonNode]) {
      node.dispose();
    }
    super.dispose();
  }

  void _setMode(bool m3u) {
    if (_busy || _m3uMode == m3u) return;
    setState(() {
      _m3uMode = m3u;
      _error = null;
    });
    log('login mode=${m3u ? 'm3u' : 'xtream'}');
  }

  void _focusTab() => (_m3uMode ? _m3uTabNode : _xtreamTabNode).requestFocus();

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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => HomeScreen(api: source, account: account)),
    );
  }

  Future<void> _login() => _m3uMode ? _loginM3u() : _loginXtream();

  Future<void> _loginXtream() async {
    if (_busy) return;
    final parsed = parseServerInput(_locked ? kLockedServer : _server.text);
    var user = _user.text.trim();
    var pass = _pass.text.trim();
    // A pasted playlist link carries the username and password itself.
    if (user.isEmpty && pass.isEmpty && parsed.username != null) {
      user = parsed.username!;
      pass = parsed.password ?? '';
    }
    if (parsed.server.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() => _error = _locked ? 'Please enter your username and password.' : 'Please fill in all three fields.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _buttonNode.requestFocus();
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
      log('login ok mode=xtream');
      _enter(api, account);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _loginM3u() async {
    if (_busy) return;
    final typed = _m3u.text.trim();
    if (typed.isEmpty) {
      setState(() => _error = 'Please enter your playlist link.');
      return;
    }
    final url = typed.contains('://') ? typed : 'http://$typed';
    setState(() {
      _busy = true;
      _error = null;
    });
    _buttonNode.requestFocus();
    try {
      // A link from an Xtream Codes panel (".../get.php?username=..&password=..") is used through
      // the panel's API when that works: it adds the TV guide and series pages and loads faster.
      final parsed = parseServerInput(url);
      if (parsed.username != null && parsed.password != null && url.toLowerCase().contains('get.php')) {
        try {
          final api = XtreamApi(parsed.server, parsed.username!, parsed.password!);
          final account = await api.login();
          await Store.saveSession(api.server, api.username, api.password);
          log('login ok mode=xtream (from link)');
          _enter(api, account);
          return;
        } on XtreamAuthException {
          rethrow;
        } catch (_) {
          // Not an Xtream panel after all: read the link as a plain playlist.
        }
      }
      final source = M3uSource(url);
      final account = await source.login();
      await Store.saveM3uSession(url);
      log('login ok mode=m3u ${account.note}');
      _enter(source, account);
    } catch (e) {
      _fail(e);
    }
  }

  Widget _tab(String label, bool m3u, FocusNode node) {
    final selected = _m3uMode == m3u;
    return Expanded(
      child: TvFocus(
        focusNode: node,
        selected: selected,
        radius: 9,
        onTap: () => _setMode(m3u),
        child: SizedBox(
          height: 38,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? C.text : C.dim,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1B1F2A), C.bg],
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 48),
              alignment: Alignment.centerLeft,
              // Scrollable so nothing breaks when the on-screen keyboard takes half the height.
              child: const SingleChildScrollView(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Logo(size: 64),
                    SizedBox(height: 26),
                    Text('Live TV, movies and series\non your big screen.',
                        style: TextStyle(fontSize: 24, height: 1.3, fontWeight: FontWeight.w700)),
                    SizedBox(height: 14),
                    Text('Sign in with the details from your provider.',
                        style: TextStyle(fontSize: 15, color: C.dim)),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Sign in', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 14),
                      if (!_locked) ...[
                        Row(
                          children: [
                            _tab('Xtream Codes', false, _xtreamTabNode),
                            const SizedBox(width: 8),
                            _tab('M3U link', true, _m3uTabNode),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: C.danger.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(_error!, style: const TextStyle(color: C.danger, fontSize: 14)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_m3uMode) ...[
                        TvField(
                          controller: _m3u,
                          focusNode: _m3uNode,
                          label: 'Playlist link (M3U)',
                          icon: Icons.link_rounded,
                          keyboardType: TextInputType.url,
                          action: TextInputAction.done,
                          onSubmitted: (_) => _login(),
                          onUp: _focusTab,
                          onDown: _buttonNode.requestFocus,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _busy
                              ? 'Loading the playlist. A large one can take a minute.'
                              : 'Any M3U / M3U8 playlist address, for example\nhttp://server:port/get.php?username=…&password=…&type=m3u_plus',
                          style: const TextStyle(color: C.dim, fontSize: 12.5, height: 1.35),
                        ),
                      ] else ...[
                        if (!_locked) ...[
                          TvField(
                            controller: _server,
                            focusNode: _serverNode,
                            label: 'Server address',
                            icon: Icons.dns_rounded,
                            keyboardType: TextInputType.url,
                            onSubmitted: (_) => _userNode.requestFocus(),
                            onUp: _focusTab,
                            onDown: _userNode.requestFocus,
                          ),
                          const SizedBox(height: 10),
                        ],
                        TvField(
                          controller: _user,
                          focusNode: _userNode,
                          label: 'Username',
                          icon: Icons.person_rounded,
                          onSubmitted: (_) => _passNode.requestFocus(),
                          onUp: _locked ? () {} : _serverNode.requestFocus,
                          onDown: _passNode.requestFocus,
                        ),
                        const SizedBox(height: 10),
                        TvField(
                          controller: _pass,
                          focusNode: _passNode,
                          label: 'Password',
                          icon: Icons.lock_rounded,
                          obscure: true,
                          action: TextInputAction.done,
                          onSubmitted: (_) => _login(),
                          onUp: _userNode.requestFocus,
                          onDown: _buttonNode.requestFocus,
                        ),
                      ],
                      const SizedBox(height: 16),
                      TvFocus(
                        focusNode: _buttonNode,
                        color: C.accent,
                        focusBorder: Colors.white,
                        onTap: _login,
                        child: SizedBox(
                          height: 46,
                          child: Center(
                            child: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                                  )
                                : const Text('Sign in',
                                    style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
