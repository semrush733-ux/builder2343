import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'browse.dart';
import 'login.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, this.account});

  final Source api;
  final XAccount? account;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  XAccount? _account;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    log('screen=home');
    if (_account == null) _refreshAccount();
  }

  /// On a normal start the saved login is used straight away and checked in
  /// the background, so the home screen appears without waiting.
  Future<void> _refreshAccount() async {
    try {
      final account = await widget.api.login();
      if (!mounted) return;
      setState(() {
        _account = account;
        _offline = false;
      });
    } on XtreamAuthException catch (e) {
      await Store.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => LoginScreen(message: e.message)),
        (_) => false,
      );
    } catch (_) {
      if (mounted) setState(() => _offline = true);
    }
  }

  void _open(XKind kind) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BrowseScreen(api: widget.api, kind: kind)));
  }

  Future<void> _logout() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: const Text('Sign out?'),
        content: const Text('You will need your login details to sign in again.'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Sign out')),
        ],
      ),
    );
    if (yes != true) return;
    await Store.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  String get _accountLine {
    final a = _account;
    if (a == null) return _offline ? 'No connection to the server' : '';
    if (a.note.isNotEmpty) return a.note;
    final parts = <String>[
      if (a.isTrial) 'Trial',
      a.expires == null ? 'No expiry date' : 'Valid until ${formatDate(a.expires!)}',
    ];
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.fromLTRB(44, 26, 44, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Logo(size: 30),
                const Spacer(),
                const Clock(),
                Container(
                  width: 1,
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  color: const Color(0xFF2A303C),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(widget.api.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    if (_accountLine.isNotEmpty)
                      Text(_accountLine,
                          style: TextStyle(fontSize: 13, color: _offline && _account == null ? C.danger : C.dim)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 22),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _BigTile(
                      autofocus: true,
                      icon: Icons.live_tv_rounded,
                      title: 'Live TV',
                      subtitle: 'Channels and TV guide',
                      colors: const [Color(0xFF3A2C00), Color(0xFF16130A)],
                      onTap: () => _open(XKind.live),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: _BigTile(
                      icon: Icons.movie_rounded,
                      title: 'Movies',
                      subtitle: 'Films on demand',
                      colors: const [Color(0xFF0E2A3A), Color(0xFF0B1319)],
                      onTap: () => _open(XKind.vod),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: _BigTile(
                      icon: Icons.video_library_rounded,
                      title: 'Series',
                      subtitle: 'Seasons and episodes',
                      colors: const [Color(0xFF2A1238), Color(0xFF120B17)],
                      onTap: () => _open(XKind.series),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Hold OK on a channel or title to add it to Favourites.',
                    style: TextStyle(color: C.dim, fontSize: 13)),
                const Spacer(),
                TvFocus(
                  onTap: _logout,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.logout_rounded, size: 17, color: C.dim),
                        SizedBox(width: 8),
                        Text('Sign out', style: TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BigTile extends StatelessWidget {
  const _BigTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      autofocus: autofocus,
      radius: 18,
      color: colors.last,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        ),
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 54, color: C.accent),
            const Spacer(),
            Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 14, color: C.dim)),
          ],
        ),
      ),
    );
  }
}
