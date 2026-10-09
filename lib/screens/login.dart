import 'package:flutter/material.dart';

import '../config.dart';
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
  final _serverNode = FocusNode();
  final _userNode = FocusNode();
  final _passNode = FocusNode();
  final _buttonNode = FocusNode();
  bool _busy = false;
  String? _error;

  bool get _locked => kLockedServer.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: Store.server);
    _user = TextEditingController(text: kPrefillUser.isNotEmpty ? kPrefillUser : Store.username);
    _pass = TextEditingController(text: kPrefillPass);
    _error = widget.message;
    log('screen=login');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_locked && _server.text.isEmpty) {
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
    _serverNode.dispose();
    _userNode.dispose();
    _passNode.dispose();
    _buttonNode.dispose();
    super.dispose();
  }

  Future<void> _login() async {
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
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => HomeScreen(api: api, account: account)),
      );
    } catch (e) {
      log('login failed: ${e.runtimeType}');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyError(e);
      });
    }
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
              padding: const EdgeInsets.all(48),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
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
                      const SizedBox(height: 16),
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
                      if (!_locked) ...[
                        TvField(
                          controller: _server,
                          focusNode: _serverNode,
                          label: 'Server address',
                          icon: Icons.dns_rounded,
                          keyboardType: TextInputType.url,
                          onSubmitted: (_) => _userNode.requestFocus(),
                          onUp: () {},
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
