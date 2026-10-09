import 'dart:async';

import 'package:flutter/material.dart';

import '../backend.dart';
import '../config.dart';
import '../m3u.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'device.dart';
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
  final _accountTabNode = FocusNode();
  final _xtreamTabNode = FocusNode();
  final _m3uTabNode = FocusNode();
  final _serverNode = FocusNode();
  final _userNode = FocusNode();
  final _passNode = FocusNode();
  final _m3uNode = FocusNode();
  final _buttonNode = FocusNode();
  final _userField = GlobalKey<TvFieldState>();
  final _passField = GlobalKey<TvFieldState>();
  // What the form asks for:
  //   account - username and password only; the server address comes from the B1G website
  //   xtream  - server address, username and password
  //   m3u     - a playlist link
  static const _account = 0, _xtream = 1, _m3uLink = 2;
  static const _modeNames = ['account', 'xtream', 'm3u'];
  int _mode = _xtream;
  bool _modeChosen = false;
  bool _busy = false;
  String? _error;
  List<BPlaylist> _serverLists = const [];
  Timer? _poll;

  /// A build that is locked to one server only asks for username and password.
  bool get _locked => kLockedServer.isNotEmpty;

  bool get _m3uMode => _mode == _m3uLink;

  /// The website gave a server address: "username and password only" is offered, and is the default.
  bool get _hasSiteServer => !_locked && Backend.serverUrl.isNotEmpty;

  int _startMode() {
    if (_locked) return _xtream;
    if (Store.isM3u && Store.m3uUrl.isNotEmpty) return _m3uLink;
    if (_hasSiteServer &&
        (Store.viaSite ||
            _server.text.trim().isEmpty ||
            bareServer(_server.text) == bareServer(Backend.serverUrl))) {
      return _account;
    }
    return _xtream;
  }

  /// The website settings arrive a moment after the first start (and can change later).
  void _onBackendChange() {
    if (!mounted) return;
    if (_busy || _modeChosen) {
      setState(() {});
      return;
    }
    var mode = _mode;
    if (_mode == _xtream && _hasSiteServer && _server.text.trim().isEmpty) mode = _account;
    if (_mode == _account && !_hasSiteServer) mode = _xtream;
    final changed = mode != _mode;
    final serverHadFocus = _serverNode.hasFocus;
    setState(() => _mode = mode);
    if (!changed) return;
    log('login mode=${_modeNames[mode]} (website)');
    // The server row appears or disappears: make sure the remote still stands on something.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focus = FocusManager.instance.primaryFocus;
      if (!serverHadFocus && focus != null && focus is! FocusScopeNode) return;
      (_mode == _xtream
              ? _serverNode
              : (_user.text.isEmpty ? _userNode : (_pass.text.isEmpty ? _passNode : _buttonNode)))
          .requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: kPrefillServer.isNotEmpty ? kPrefillServer : Store.server);
    _user = TextEditingController(text: kPrefillUser.isNotEmpty ? kPrefillUser : Store.username);
    _pass = TextEditingController(text: kPrefillPass);
    _m3u = TextEditingController(text: Store.m3uUrl);
    _mode = _startMode();
    _error = widget.message;
    log('screen=login');
    if (_mode == _account) log('login mode=account (website)');
    Backend.changes.addListener(_onBackendChange);
    // Register with the B1G website and watch for playlists added online
    // (by us for the client, or by the client through the QR link).
    Backend.ensureRegistered().then((_) {
      if (mounted) setState(() {});
      _loadServerLists();
    });
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _loadServerLists());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_m3uMode) {
        (_m3u.text.isEmpty ? _m3uNode : _buttonNode).requestFocus();
      } else if (_mode == _xtream && !_locked && _server.text.isEmpty) {
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

  Future<void> _loadServerLists() async {
    if (_busy || !mounted) return;
    try {
      final lists = await Backend.playlists();
      if (!mounted) return;
      final changed = lists.length != _serverLists.length ||
          !List.generate(lists.length, (i) => lists[i].id == _serverLists[i].id && lists[i].url == _serverLists[i].url)
              .every((same) => same);
      if (changed) setState(() => _serverLists = lists);
    } catch (_) {
      // Quietly keep the manual sign-in; the next poll tries again.
    }
  }

  /// Signs in with a playlist that was added on the website.
  /// TV guide address of the server playlist being signed in with.
  String _pendingEpgUrl = '';

  Future<void> _useServerPlaylist(BPlaylist pl) async {
    if (_busy) return;
    log('login server-playlist id=${pl.id} type=${pl.type}');
    if (pl.isXtream) {
      _server.text = pl.url;
      _user.text = pl.username;
      _pass.text = pl.password;
      setState(() {
        _mode = _xtream;
        _modeChosen = true;
      });
      await _loginXtream();
    } else {
      _m3u.text = pl.url;
      _pendingEpgUrl = pl.epgUrl;
      setState(() {
        _mode = _m3uLink;
        _modeChosen = true;
      });
      await _loginM3u();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    Backend.changes.removeListener(_onBackendChange);
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    _m3u.dispose();
    for (final node in [_accountTabNode, _xtreamTabNode, _m3uTabNode, _serverNode, _userNode, _passNode, _m3uNode, _buttonNode]) {
      node.dispose();
    }
    super.dispose();
  }

  void _setMode(int mode) {
    if (_busy || _mode == mode) return;
    setState(() {
      _mode = mode;
      _modeChosen = true;
      _error = null;
    });
    log('login mode=${_modeNames[mode]}');
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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => HomeScreen(api: source, account: account)),
    );
  }

  Future<void> _login() => _m3uMode ? _loginM3u() : _loginXtream();

  Future<void> _loginXtream() async {
    if (_busy) return;
    final fixedServer = _locked || _mode == _account;
    final parsed = parseServerInput(_locked ? kLockedServer : (_mode == _account ? Backend.serverUrl : _server.text));
    var user = _user.text.trim();
    var pass = _pass.text.trim();
    // A pasted playlist link carries the username and password itself.
    if (user.isEmpty && pass.isEmpty && parsed.username != null) {
      user = parsed.username!;
      pass = parsed.password ?? '';
    }
    if (parsed.server.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(
          () => _error = fixedServer ? 'Please enter your username and password.' : 'Please fill in all three fields.');
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
      await Store.saveSession(api.server, user, pass, viaSite: !_locked && _mode == _account);
      log('login ok mode=xtream');
      _enter(api, account);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _loginM3u() async {
    if (_busy) return;
    final epgUrl = _pendingEpgUrl;
    _pendingEpgUrl = '';
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
      final source = M3uSource(url, epgUrl: epgUrl);
      final account = await source.login();
      await Store.saveM3uSession(url, epgUrl: epgUrl);
      log('login ok mode=m3u ${account.note}');
      _enter(source, account);
    } catch (e) {
      _fail(e);
    }
  }

  Widget _tab(String label, int mode, FocusNode node) {
    final selected = _mode == mode;
    return Expanded(
      child: TvFocus(
        focusNode: node,
        selected: selected,
        radius: 9,
        onTap: () => _setMode(mode),
        child: SizedBox(
          height: 38,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _hasSiteServer ? 13 : 14,
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Logo(size: 64),
                    const SizedBox(height: 22),
                    const Text('Live TV, movies and series\non your big screen.',
                        style: TextStyle(fontSize: 24, height: 1.3, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    const Text('Sign in with the details from your provider.',
                        style: TextStyle(fontSize: 15, color: C.dim)),
                    const SizedBox(height: 22),
                    const DeviceCard(compact: true),
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
                      if (_serverLists.isNotEmpty) ...[
                        const Text('ON YOUR ACCOUNT',
                            style: TextStyle(
                                fontSize: 11, letterSpacing: 1.5, color: C.dim, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        for (final pl in _serverLists)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TvFocus(
                              radius: 10,
                              color: C.card,
                              onTap: () => _useServerPlaylist(pl),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                child: Row(
                                  children: [
                                    const Icon(Icons.cloud_done_rounded, size: 18, color: C.accent),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        pl.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    Text(pl.isXtream ? 'Xtream' : 'M3U',
                                        style: const TextStyle(fontSize: 12, color: C.dim)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                        const Text('Or sign in manually:',
                            style: TextStyle(fontSize: 12.5, color: C.dim)),
                        const SizedBox(height: 8),
                      ],
                      if (!_locked) ...[
                        Row(
                          children: [
                            if (_hasSiteServer) ...[
                              _tab(Backend.serverName.isEmpty ? 'Account' : Backend.serverName, _account,
                                  _accountTabNode),
                              const SizedBox(width: 8),
                            ],
                            _tab('Xtream Codes', _xtream, _xtreamTabNode),
                            const SizedBox(width: 8),
                            _tab('M3U link', _m3uLink, _m3uTabNode),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: C.danger.withValues(alpha: 0.12),
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
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _busy
                              ? 'Loading the playlist. A large one can take a minute.'
                              : 'Any M3U / M3U8 playlist address, for example\nhttp://server:port/get.php?username=…&password=…&type=m3u_plus',
                          style: const TextStyle(color: C.dim, fontSize: 12.5, height: 1.35),
                        ),
                      ] else ...[
                        if (!_locked && _mode == _xtream) ...[
                          TvField(
                            controller: _server,
                            focusNode: _serverNode,
                            label: 'Server address',
                            icon: Icons.dns_rounded,
                            keyboardType: TextInputType.url,
                            onSubmitted: (_) => _userField.currentState?.edit(),
                          ),
                          const SizedBox(height: 10),
                        ],
                        TvField(
                          controller: _user,
                          key: _userField,
                          focusNode: _userNode,
                          label: 'Username',
                          icon: Icons.person_rounded,
                          onSubmitted: (_) => _passField.currentState?.edit(),
                        ),
                        const SizedBox(height: 10),
                        TvField(
                          controller: _pass,
                          key: _passField,
                          focusNode: _passNode,
                          label: 'Password',
                          icon: Icons.lock_rounded,
                          obscure: true,
                          action: TextInputAction.done,
                          onSubmitted: (_) => _login(),
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
