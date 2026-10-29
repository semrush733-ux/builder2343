import 'package:flutter/material.dart';

import '../backend.dart';
import '../i18n.dart';
import '../m3u.dart';
import '../speedtest.dart';
import '../stalker.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'browse.dart';
import 'catchup.dart';
import 'login.dart';
import 'playlists.dart';
import 'settings.dart';

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

  void _openCatchup() {
    final api = widget.api;
    if (api is XtreamApi) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CatchupScreen(api: api)));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: const Text('Catch Up'),
        content: const Text(
          'Catch Up works with Xtream accounts, where the server keeps recordings of past programmes. '
          'M3U links and MAG portals do not carry recordings.',
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: C.accent))),
        ],
      ),
    );
  }

  /// "Playlists": the lists saved on this device; picking one switches to it.
  Future<void> _choosePlaylist() async {
    final choice = await Navigator.of(context)
        .push<BPlaylist>(MaterialPageRoute(builder: (_) => PlaylistsScreen(current: widget.api.label)));
    if (choice == null || !mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 20),
        behavior: SnackBarBehavior.floating,
        width: 360,
        content: Text('Loading "${choice.name}"…', textAlign: TextAlign.center),
      ));
    try {
      final Source source;
      final XAccount account;
      if (choice.isMag) {
        final src = StalkerSource(choice.url, choice.mac);
        account = await src.login();
        await Store.saveMagSession(choice.url, choice.mac);
        source = src;
      } else if (choice.isXtream) {
        final api = XtreamApi(parseServerInput(choice.url).server, choice.username, choice.password);
        account = await api.login();
        await Store.saveSession(api.server, api.username, api.password);
        source = api;
      } else {
        final src = M3uSource(choice.url, epgUrl: choice.epgUrl);
        account = await src.login();
        await Store.saveM3uSession(choice.url, epgUrl: choice.epgUrl);
        source = src;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      log('playlist switch ok');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => HomeScreen(api: source, account: account)),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          width: 420,
          content: Text(friendlyError(e), textAlign: TextAlign.center),
        ));
    }
  }

  void _addPlaylist() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LoginScreen()));
  }

  Future<void> _logout() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: const Text('Sign out?'),
        content: const Text('Your saved playlists stay on this device.'),
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (Store.wallpaper != 0)
            Opacity(
              opacity: 0.55,
              child: Image.asset(
                wallpaperAsset(Store.wallpaper),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, __, ___) => const SizedBox(),
              ),
            ),
          if (Store.wallpaper == 0) const Aurora() else const Aurora(strength: 0.5),
          SafeArea(child: _content()),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String label, VoidCallback onTap, {bool autofocus = false}) {
    return TvFocus(
      autofocus: autofocus,
      radius: 22,
      color: const Color(0x99161934),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: C.accent),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 20, 44, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Logo(size: 28),
              const Spacer(),
              const Clock(),
              Container(width: 1, height: 34, margin: const EdgeInsets.symmetric(horizontal: 20), color: const Color(0x33FFFFFF)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(widget.api.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  if (_accountLine.isNotEmpty)
                    Text(_accountLine,
                        style: TextStyle(fontSize: 12.5, color: _offline && _account == null ? C.danger : C.dim)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 6,
                  child: _Tile(
                    autofocus: true,
                    hero: true,
                    icon: Icons.live_tv_rounded,
                    title: t('Live TV'),
                    subtitle: t('Channels and TV guide'),
                    colors: const [Color(0xFF14315F), Color(0xFF3A1B7A)],
                    glow: C.accent,
                    onTap: () => _open(XKind.live),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _Tile(
                          icon: Icons.movie_rounded,
                          title: t('Movies'),
                          subtitle: t('Films on demand'),
                          colors: const [Color(0xFF4A1747), Color(0xFF1A1236)],
                          glow: C.pink,
                          onTap: () => _open(XKind.vod),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _Tile(
                          icon: Icons.video_library_rounded,
                          title: t('Series'),
                          subtitle: t('Seasons and episodes'),
                          colors: const [Color(0xFF0C3B3C), Color(0xFF151A3A)],
                          glow: C.accent,
                          onTap: () => _open(XKind.series),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _pill(Icons.history_rounded, t('Catch Up'), _openCatchup),
              _pill(Icons.playlist_play_rounded, t('Playlists'), _choosePlaylist),
              _pill(Icons.add_link_rounded, 'Add playlist', _addPlaylist),
              _pill(Icons.speed_rounded, 'Speed', () => showSpeedTest(context)),
              _pill(Icons.settings_rounded, t('Settings'), () {
                // Language or wallpaper may have changed: redraw when the customer comes back.
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(api: widget.api)))
                    .then((_) {
                  if (mounted) setState(() {});
                });
              }),
              _pill(Icons.logout_rounded, t('Sign out'), _logout),
            ],
          ),
        ],
      ),
    );
  }
}

/// A big home tile: gradient card, a glowing icon, soft scale-up when the remote or finger is on it.
class _Tile extends StatefulWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.glow,
    required this.onTap,
    this.autofocus = false,
    this.hero = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final Color glow;
  final VoidCallback onTap;
  final bool autofocus;
  final bool hero;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final hero = widget.hero;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedScale(
        scale: _focused ? 1.025 : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: TvFocus(
          autofocus: widget.autofocus,
          radius: 24,
          color: widget.colors.last,
          focusBorder: widget.glow,
          onTap: widget.onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: widget.colors),
            ),
            child: Stack(
              children: [
                // A big faint icon bleeding off the corner gives each tile its own shape.
                Positioned(
                  right: hero ? -30 : -18,
                  bottom: hero ? -34 : -22,
                  child: Icon(widget.icon, size: hero ? 230 : 130, color: const Color(0x14FFFFFF)),
                ),
                Padding(
                  padding: EdgeInsets.all(hero ? 30 : 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: hero ? 70 : 52,
                        height: hero ? 70 : 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0x22FFFFFF),
                          boxShadow: [BoxShadow(color: widget.glow.withValues(alpha: _focused ? 0.55 : 0.28), blurRadius: 28)],
                        ),
                        child: Icon(widget.icon, size: hero ? 36 : 26, color: Colors.white),
                      ),
                      const Spacer(),
                      Text(widget.title,
                          style: TextStyle(fontSize: hero ? 40 : 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                      const SizedBox(height: 3),
                      Text(widget.subtitle, style: TextStyle(fontSize: hero ? 15.5 : 13.5, color: const Color(0xCCFFFFFF))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The picture for a wallpaper number (0 = the standard home background).
String wallpaperAsset(int n) =>
    n <= 0 || n > 20 ? 'assets/home_bg.webp' : 'assets/wallpapers/wp${n.toString().padLeft(2, '0')}.webp';
