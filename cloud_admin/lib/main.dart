import 'package:flutter/material.dart';

import 'api.dart';

const _orange = Color(0xFFFF8B06);
const _bg = Color(0xFF0F1115);
const _card = Color(0xFF171A21);
const _line = Color(0xFF2D3340);
const _muted = Color(0xFF98A1B3);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.init();
  runApp(const AdminApp());
}

final _navKey = GlobalKey<NavigatorState>();

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: _orange, brightness: Brightness.dark, primary: _orange, surface: _card);
    OutlineInputBorder border(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
    return MaterialApp(
      title: 'Cloud Admin',
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: _bg,
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0F1218),
          border: border(_line),
          enabledBorder: border(_line),
          focusedBorder: border(_orange, 2),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _orange,
            foregroundColor: const Color(0xFF1B1000),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            side: const BorderSide(color: _line),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      home: Api.signedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}

void toast(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? const Color(0xFF7A1A1F) : const Color(0xFF1F5130),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ));
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(),
              style: const TextStyle(color: Color(0xFFFFB066), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

// ------------------------------------------------------------------------------------ sign in

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _site = TextEditingController(text: Api.site);
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _show = false;

  @override
  void dispose() {
    _site.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await Api.login(_site.text, _user.text, _pass.text);
      if (!mounted) return;
      if (r.ok) {
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => HomeScreen(first: r.state)));
        return;
      }
      toast(context, r.message, error: true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.cloud_circle_rounded, size: 72, color: _orange),
                const SizedBox(height: 10),
                const Text('Cloud Admin', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Change the Cloud Player app address from your phone.',
                    textAlign: TextAlign.center, style: TextStyle(color: _muted)),
                const SizedBox(height: 26),
                TextField(
                  controller: _site,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Your website', hintText: 'https://playercloud.app'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _user,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'User name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: !_show,
                  autocorrect: false,
                  enableSuggestions: false,
                  onSubmitted: (_) => _go(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                        icon: Icon(_show ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _show = !_show)),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _go,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Sign in'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------- home

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.first});
  final AppState? first;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _site = TextEditingController();
  final _server = TextEditingController();
  final _name = TextEditingController();
  AppState? _s;
  bool _busy = false;
  bool _force = false;
  bool _loading = true;
  String? _checkMsg;
  bool _checkOk = false;

  @override
  void initState() {
    super.initState();
    if (widget.first != null) {
      _apply(widget.first!);
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _site.dispose();
    _server.dispose();
    _name.dispose();
    super.dispose();
  }

  void _apply(AppState s) {
    _s = s;
    _site.text = s.site;
    _server.text = s.serverUrl;
    _name.text = s.serverName;
  }

  void _signedOut() {
    Api.signOut(tellSite: false);
    final nav = _navKey.currentState;
    nav?.pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const LoginScreen()), (_) => false);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await Api.state();
      if (mounted) setState(() => _apply(s));
    } on ApiException catch (e) {
      if (e.signedOut) {
        _signedOut();
        return;
      }
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } on ApiException catch (e) {
      if (e.signedOut) {
        _signedOut();
        return;
      }
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() => _run(() async {
        final r = await Api.check(_site.text);
        if (!mounted) return;
        setState(() {
          _checkMsg = r.message;
          _checkOk = r.ok;
        });
      });

  Future<void> _save() => _run(() async {
        final typed = _site.text.trim();
        // Moving the apps to another website is serious: ask once.
        if (typed.isNotEmpty && Api.cleanSite(typed) != (_s?.site ?? '')) {
          final yes = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Move the apps?'),
              content: Text('All Cloud Player apps will use\n${Api.cleanSite(typed).isEmpty ? typed : Api.cleanSite(typed)}\nthe next time they open.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Move')),
              ],
            ),
          );
          if (yes != true) return;
        }
        final r = await Api.save(newSite: typed, serverUrl: _server.text.trim(), serverName: _name.text.trim(), force: _force);
        if (!mounted) return;
        if (r.state != null) setState(() => _apply(r.state!));
        setState(() => _checkMsg = null);
        toast(context, r.message, error: !r.ok);
      });

  Future<void> _restore(Change c) => _run(() async {
        final r = await Api.restore(c.id);
        if (!mounted) return;
        if (r.state != null) setState(() => _apply(r.state!));
        toast(context, r.message, error: !r.ok);
      });

  String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)} UTC';
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _bg,
        title: Text(s != null && s.host.isNotEmpty ? s.host : 'Cloud Admin', style: const TextStyle(fontSize: 18)),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Api.signOut();
              _signedOut();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _loading && s == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                _Card(
                  title: 'App main address',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(
                      (s?.site ?? '').isEmpty ? 'Now: not set (apps keep the address built into them)' : 'Now: ${s!.site}',
                      style: const TextStyle(color: _muted),
                    ),
                    const SizedBox(height: 4),
                    const Text('Apps pick up a change the next time they open, or within 6 hours.', style: TextStyle(color: _muted, fontSize: 13)),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _site,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      onChanged: (_) => setState(() => _checkMsg = null),
                      decoration: const InputDecoration(labelText: 'Website address', hintText: 'https://playercloud.app'),
                    ),
                    if (_checkMsg != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: _checkOk ? const Color(0xFF12301F) : const Color(0xFF3A1D22), borderRadius: BorderRadius.circular(12)),
                        child: Text(_checkMsg!, style: TextStyle(color: _checkOk ? const Color(0xFF9BE8B6) : const Color(0xFFFFB3BB))),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Default IPTV server (optional)', hintText: 'http://example.com:8080'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _name,
                      maxLength: 12,
                      decoration: const InputDecoration(labelText: 'Name on the sign-in tab (optional)'),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _force,
                      onChanged: (v) => setState(() => _force = v ?? false),
                      title: const Text('Save without checking', style: TextStyle(color: _muted, fontSize: 14)),
                    ),
                    const SizedBox(height: 6),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : const Text('Save'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(onPressed: _busy ? null : _check, child: const Text('Check address')),
                    const SizedBox(height: 12),
                    const Text(
                      'Saving checks that the new address really is a Cloud Player website first. '
                      'The new website must have the same plugin and devices (a clone) before you move.',
                      style: TextStyle(color: _muted, fontSize: 13),
                    ),
                  ]),
                ),
                _Card(
                  title: 'Recent changes',
                  child: (s == null || s.history.isEmpty)
                      ? const Text('Nothing changed yet.', style: TextStyle(color: _muted))
                      : Column(children: [
                          for (final c in s.history.take(8))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(c.what, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text(_when(c.time), style: const TextStyle(color: _muted, fontSize: 12)),
                                    const SizedBox(height: 2),
                                    Text('${c.from.isEmpty ? '(nothing)' : c.from}\n-> ${c.to.isEmpty ? '(nothing)' : c.to}',
                                        style: const TextStyle(color: _muted, fontSize: 13)),
                                  ]),
                                ),
                                TextButton(onPressed: _busy ? null : () => _restore(c), child: const Text('Go back')),
                              ]),
                            ),
                        ]),
                ),
              ]),
      ),
    );
  }
}
