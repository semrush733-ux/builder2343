import 'package:flutter/material.dart';

import 'api.dart';

const _bg = Color(0xFFF4F5F7);
const _ink = Color(0xFF12161D);
const _muted = Color(0xFF5A6372);
const _line = Color(0xFFDFE3EA);
const _orange = Color(0xFFFF8B06);
const _orangeInk = Color(0xFFA85200);
const _ok = Color(0xFF17764A);
const _okBg = Color(0xFFE5F4EC);
const _bad = Color(0xFFB3261E);
const _badBg = Color(0xFFFCE8E6);

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
    OutlineInputBorder border(Color c, [double w = 1.5]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: w));
    return MaterialApp(
      title: 'Cloud Admin',
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: _orange, brightness: Brightness.light, primary: _orange, surface: Colors.white),
        scaffoldBackgroundColor: _bg,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          border: border(const Color(0xFFCFD5DF)),
          enabledBorder: border(const Color(0xFFCFD5DF)),
          focusedBorder: border(_orange, 2),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _orange,
            foregroundColor: const Color(0xFF1B1000),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _ink,
            backgroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            side: const BorderSide(color: Color(0xFFCFD5DF), width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: _orangeInk)),
      ),
      home: Api.signedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}

void toast(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(text, style: TextStyle(color: error ? _bad : _ok, fontWeight: FontWeight.w600)),
      backgroundColor: error ? _badBg : _okBg,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ));
}

class _Logo extends StatelessWidget {
  const _Logo(this.size);
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(size * 0.29)),
        child: Icon(Icons.cloud_rounded, color: Colors.white, size: size * 0.58),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
        child: child,
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, [this.lead]);
  final String title;
  final String? lead;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: _ink)),
          if (lead != null) ...[
            const SizedBox(height: 4),
            Text(lead!, style: const TextStyle(fontSize: 15, color: _muted, height: 1.4)),
          ],
        ]),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {required this.ok});
  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: ok ? _okBg : _badBg, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ok ? Icons.check_circle_outline : Icons.error_outline, size: 20, color: ok ? _ok : _bad),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: ok ? _ok : _bad, fontSize: 15, height: 1.35))),
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
  String? _error;

  @override
  void dispose() {
    _site.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await Api.login(_site.text, _user.text, _pass.text);
      if (!mounted) return;
      if (r.ok) {
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => HomeScreen(first: r.state)));
        return;
      }
      setState(() => _error = r.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
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
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const _Logo(56),
                const SizedBox(height: 18),
                const Text('Cloud Player Admin', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: _ink)),
                const SizedBox(height: 6),
                const Text('Sign in to change the app address and see your users.', style: TextStyle(color: _muted, fontSize: 16, height: 1.4)),
                if (_error != null) _Note(_error!, ok: false),
                const SizedBox(height: 18),
                _Panel(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('Your website', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _site,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(hintText: 'https://playercloud.app'),
                    ),
                    const SizedBox(height: 14),
                    const Text('User name', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(controller: _user, autocorrect: false, enableSuggestions: false),
                    const SizedBox(height: 14),
                    const Text('Password', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _pass,
                      obscureText: !_show,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) => _go(),
                      decoration: InputDecoration(
                        suffixIcon: IconButton(
                          tooltip: _show ? 'Hide password' : 'Show password',
                          icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: _muted),
                          onPressed: () => setState(() => _show = !_show),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _go,
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: _ink))
                          : const Text('Sign in'),
                    ),
                  ]),
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
  String? _note;
  bool _noteOk = false;

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
    _navKey.currentState?.pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const LoginScreen()), (_) => false);
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
      if (mounted) setState(() {
        _note = e.message;
        _noteOk = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() => _run(() async {
        final r = await Api.check(_site.text);
        if (!mounted) return;
        setState(() {
          _note = r.message;
          _noteOk = r.ok;
        });
      });

  Future<void> _save() => _run(() async {
        final typed = _site.text.trim();
        final clean = Api.cleanSite(typed);
        // Moving the apps to another website is serious: ask once.
        if (typed.isNotEmpty && clean != (_s?.site ?? '')) {
          final yes = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Move the apps?'),
              content: Text('Every Cloud Player app will connect to\n${clean.isEmpty ? typed : clean}\nthe next time it opens.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Move apps')),
              ],
            ),
          );
          if (yes != true) return;
        }
        final r = await Api.save(newSite: typed, serverUrl: _server.text.trim(), serverName: _name.text.trim(), force: _force);
        if (!mounted) return;
        setState(() {
          if (r.state != null) _apply(r.state!);
          _note = r.message;
          _noteOk = r.ok;
        });
      });

  Future<void> _restore(Change c) => _run(() async {
        final r = await Api.restore(c.id);
        if (!mounted) return;
        setState(() {
          if (r.state != null) _apply(r.state!);
          _note = r.message;
          _noteOk = r.ok;
        });
      });

  Future<void> _addAdmin() async {
    final u = TextEditingController();
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Add an admin'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: u, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'User name')),
              const SizedBox(height: 10),
              TextField(controller: p1, obscureText: true, decoration: const InputDecoration(labelText: 'Password (10 or more characters)')),
              const SizedBox(height: 10),
              TextField(controller: p2, obscureText: true, decoration: const InputDecoration(labelText: 'Password again')),
              if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: _bad))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                if (p1.text != p2.text) {
                  set(() => err = 'The two passwords are not the same.');
                } else {
                  Navigator.pop(c, true);
                }
              },
              child: const Text('Add admin'),
            ),
          ],
        ),
      ),
    );
    final user = u.text.trim(), pass = p1.text;
    u.dispose();
    p1.dispose();
    p2.dispose();
    if (ok != true) return;
    await _run(() async {
      final r = await Api.addAdmin(user, pass);
      if (!mounted) return;
      setState(() {
        if (r.state != null) _apply(r.state!);
        _note = r.message;
        _noteOk = r.ok;
      });
    });
  }

  Future<void> _removeAdmin(Admin a) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove admin?'),
        content: Text('${a.user} will be signed out and cannot sign in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (yes != true) return;
    await _run(() async {
      final r = await Api.removeAdmin(a.user);
      if (!mounted) return;
      setState(() {
        if (r.state != null) _apply(r.state!);
        _note = r.message;
        _noteOk = r.ok;
      });
    });
  }

  Widget _admins(AppState? s) {
    final list = s?.admins ?? const <Admin>[];
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < list.length; i++)
          Container(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 12, bottom: 12),
            decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: _line))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(list[i].user, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(list[i].owner ? 'Main admin' : 'Admin', style: const TextStyle(color: _muted, fontSize: 13)),
                ]),
              ),
              if (!list[i].owner) TextButton(onPressed: _busy ? null : () => _removeAdmin(list[i]), child: const Text('Remove')),
            ]),
          ),
        OutlinedButton.icon(onPressed: _busy ? null : _addAdmin, icon: const Icon(Icons.person_add_alt_1_outlined, size: 20), label: const Text('Add an admin')),
      ]),
    );
  }

  String _when(DateTime t) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.day} ${m[t.month - 1]} ${t.year}, ${two(t.hour)}:${two(t.minute)} UTC';
  }

  String _n(Object? v) {
    if (v == null) return '-';
    final i = int.tryParse('$v');
    if (i == null) return '$v';
    final s = i.toString();
    final b = StringBuffer();
    for (var k = 0; k < s.length; k++) {
      if (k > 0 && (s.length - k) % 3 == 0) b.write(',');
      b.write(s[k]);
    }
    return b.toString();
  }

  Widget _hero(AppState? s) {
    final has = (s?.site ?? '').isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        color: _ink,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 6, color: _orange),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Apps connect to', style: TextStyle(color: Color(0xFFB8C0CD), fontSize: 15)),
                  const SizedBox(height: 8),
                  Text(
                    has ? s!.site.replaceFirst('https://', '') : 'The address built into each app',
                    style: TextStyle(
                      color: has ? Colors.white : const Color(0xFF98A2B3),
                      fontSize: has ? 30 : 22,
                      fontWeight: has ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: -0.8,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Container(width: 9, height: 9, decoration: const BoxDecoration(color: _orange, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        has ? 'Set from this panel. Apps follow within 6 hours.' : 'Nothing set here yet.',
                        style: const TextStyle(color: Color(0xFFFFD7A8), fontSize: 14),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _stat(String big, String label, {bool warm = false}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(big,
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.1, color: warm ? _orangeInk : _ink)),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: _muted, fontSize: 13, height: 1.3)),
          ]),
        ),
      );

  Widget _row(String label, Object? v) => Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: _muted, fontSize: 15))),
          Text(_n(v), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
      );

  Widget _users(AppState? s) {
    final st = s?.stats;
    if (st == null) {
      return const Text('No device list was found on this website.', style: TextStyle(color: _muted));
    }
    const divider = SizedBox(width: 1, height: 84, child: ColoredBox(color: _line));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Row(children: [
            _stat(_n(st['installs']), 'Total installs'),
            divider,
            _stat(_n(st['new_this_month']), 'New in ${st['month_label'] ?? 'this month'}'),
          ]),
          const Divider(height: 1, color: _line),
          Row(children: [
            _stat(_n(st['active_30']), 'Active in the last 30 days'),
            divider,
            _stat(_n(st['inactive_90']), 'Not seen for 3 months', warm: true),
          ]),
        ]),
      ),
      const SizedBox(height: 10),
      _row('New in the last 30 days', st['new_last_30']),
      _row('Active in the last 7 days', st['active_7']),
      _row('Quiet (30 to 90 days)', st['quiet']),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _busy
            ? null
            : () => _run(() async {
                  final x = await Api.state(fresh: true);
                  if (mounted) setState(() => _apply(x));
                }),
        icon: const Icon(Icons.refresh, size: 20),
        label: const Text('Refresh numbers'),
      ),
      const SizedBox(height: 8),
      const Text('Every install is one device. Play Store, LG and Samsung counts are in their own consoles.',
          style: TextStyle(color: _muted, fontSize: 13.5, height: 1.4)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      body: SafeArea(
        child: _loading && s == null
            ? const Center(child: CircularProgressIndicator(color: _orange))
            : RefreshIndicator(
                color: _orange,
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 40), children: [
                  Row(children: [
                    const _Logo(34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          const TextSpan(text: 'Cloud Player ', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: _ink)),
                          TextSpan(text: s != null && s.host.isNotEmpty ? s.host : 'Admin', style: const TextStyle(color: _muted, fontSize: 14)),
                        ]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sign out',
                      icon: const Icon(Icons.logout, color: _ink),
                      onPressed: () async {
                        await Api.signOut();
                        _signedOut();
                      },
                    ),
                  ]),
                  const SizedBox(height: 14),
                  if (_note != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: _Note(_note!, ok: _noteOk)),
                  _hero(s),
                  const _Heading('Change the address', 'Saving first checks that the new address is a Cloud Player website, so apps are never sent to a wrong place.'),
                  _Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('Website address', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _site,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        onChanged: (_) => setState(() => _note = null),
                        decoration: const InputDecoration(hintText: 'https://playercloud.app'),
                      ),
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 8),
                          shape: const Border(),
                          collapsedShape: const Border(),
                          title: const Text('Default IPTV server (optional)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          children: [
                            TextField(
                              controller: _server,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              decoration: const InputDecoration(labelText: 'Server address', hintText: 'http://example.com:8080'),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _name,
                              maxLength: 12,
                              decoration: const InputDecoration(labelText: 'Name on the sign-in tab (up to 12 letters)'),
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _force = !_force),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            Checkbox(value: _force, activeColor: _orange, onChanged: (v) => setState(() => _force = v ?? false)),
                            const Expanded(child: Text('Save without checking', style: TextStyle(color: _muted, fontSize: 14))),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _busy ? null : _save,
                        child: _busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: _ink))
                            : const Text('Save address'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(onPressed: _busy ? null : _check, child: const Text('Check only')),
                      const SizedBox(height: 14),
                      const Text(
                        'Before you move: the new website needs the same plugin and the same devices (a clone). '
                        'Change the address on the site your apps use today, and keep the old site running until every app has moved.',
                        style: TextStyle(color: _muted, fontSize: 13.5, height: 1.4),
                      ),
                    ]),
                  ),
                  const _Heading('Users'),
                  _users(s),
                  const _Heading('Admins', 'Everyone listed here can sign in to the panel and this app. Give each person their own login.'),
                  _admins(s),
                  const _Heading('Recent changes'),
                  _Panel(
                    child: (s == null || s.history.isEmpty)
                        ? const Text('No changes yet. When you change an address it is listed here, with a button to go back.',
                            style: TextStyle(color: _muted, fontSize: 14, height: 1.4))
                        : Column(children: [
                            for (var i = 0; i < s.history.take(8).length; i++) _historyRow(s.history[i], first: i == 0),
                          ]),
                  ),
                ]),
              ),
      ),
    );
  }

  Widget _historyRow(Change c, {required bool first}) => Container(
        padding: EdgeInsets.only(top: first ? 0 : 14, bottom: 14),
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: _line))),
        margin: EdgeInsets.only(top: first ? 0 : 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.what, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(_when(c.time), style: const TextStyle(color: _muted, fontSize: 13)),
          const SizedBox(height: 6),
          Text.rich(TextSpan(children: [
            TextSpan(text: c.from.isEmpty ? 'nothing set' : c.from, style: const TextStyle(color: _muted)),
            const TextSpan(text: '  to  ', style: TextStyle(color: _orangeInk, fontWeight: FontWeight.w700)),
            TextSpan(text: c.to.isEmpty ? 'nothing set' : c.to, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]), style: const TextStyle(fontSize: 14, height: 1.4)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : () => _restore(c),
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Go back to the old one'),
            ),
          ),
        ]),
      );
}
