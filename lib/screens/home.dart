import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../backend.dart';
import '../i18n.dart';
import '../m3u.dart';
import '../speedtest.dart';
import '../stalker.dart';
import '../autotune.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'browse.dart';
import 'catchup.dart';
import 'login.dart';
import 'playlists.dart';
import 'settings.dart';
import 'tile_art.dart';

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
    Future<void>.delayed(const Duration(milliseconds: 1500), AutoTune.start);
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
      radius: 24,
      color: Colors.transparent,
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
                    art: TileArtKind.live,
                    image: 'assets/tiles/live.webp',
                    order: 0,
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
                          art: TileArtKind.movies,
                          image: 'assets/tiles/movies.webp',
                          order: 1,
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
                          art: TileArtKind.series,
                          image: 'assets/tiles/series.webp',
                          order: 2,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xAA0B0D1C),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: const Color(0x33FFFFFF)),
              boxShadow: const [BoxShadow(color: Color(0x40FFB84F), blurRadius: 30, spreadRadius: -14)],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
          ),
        ],
      ),
    );
  }
}

/// A big home tile: gradient card with its own moving picture (signal rings, floating posters,
/// rippling episode cards). It slides in when the screen opens, and when the remote or finger is on
/// it the tile rises, glows in its colour and a band of light sweeps across.
class _Tile extends StatefulWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.glow,
    required this.onTap,
    required this.art,
    required this.image,
    this.order = 0,
    this.autofocus = false,
    this.hero = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final Color glow;
  final VoidCallback onTap;
  final TileArtKind art;
  final String image;
  final int order;
  final bool autofocus;
  final bool hero;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> with TickerProviderStateMixin {
  bool _focused = false;

  // Loops forever: drives the moving picture.
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 6), value: 0.25);
  // Plays once when the screen opens (staggered by tile order).
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  // Plays each time the tile gets focus: the sweep of light.
  late final AnimationController _shine = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (!Ui.lite) _loop.repeat();
    Future<void>.delayed(Duration(milliseconds: 120 + widget.order * 140), () {
      if (mounted) _enter.forward();
    });
  }

  @override
  void dispose() {
    _loop.dispose();
    _enter.dispose();
    _shine.dispose();
    super.dispose();
  }

  void _onFocus(bool f) {
    setState(() => _focused = f);
    if (f) _shine.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final hero = widget.hero;
    return AnimatedBuilder(
      animation: _enter,
      builder: (context, child) {
        final e = Curves.easeOutCubic.transform(_enter.value);
        return Opacity(
          opacity: e,
          child: Transform.translate(offset: Offset(0, 46 * (1 - e)), child: child),
        );
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: _onFocus,
        child: AnimatedScale(
          scale: _focused ? 1.035 : 1.0,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: widget.glow.withValues(alpha: _focused ? 0.45 : 0.12),
                  blurRadius: _focused ? 46 : 22,
                  spreadRadius: _focused ? -4 : -10,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: TvFocus(
              autofocus: widget.autofocus,
              radius: 24,
              color: widget.colors.last,
              focusBorder: widget.glow,
              onTap: widget.onTap,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: widget.colors),
                ),
                child: Stack(
                  children: [
                    // The picture drifts and breathes slowly (a gentle "Ken Burns" move).
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _loop,
                          builder: (_, child) {
                            final w = math.sin(_loop.value * 2 * math.pi);
                            final zoom = 1.08 + (Ui.lite ? 0 : 0.035 * w) + (_focused ? 0.04 : 0);
                            return Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..translateByDouble(Ui.lite ? 0 : w * 8, Ui.lite ? 0 : w * -4, 0, 1)
                                ..scaleByDouble(zoom, zoom, 1, 1),
                              child: child,
                            );
                          },
                          child: Image.asset(widget.image, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
                        ),
                      ),
                    ),
                    // Colour wash and a shade behind the title so the words stay easy to read.
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              widget.colors.first.withValues(alpha: 0.10),
                              widget.colors.last.withValues(alpha: 0.10),
                              const Color(0xCC050614),
                            ],
                            stops: const [0, 0.5, 1],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _loop,
                          builder: (_, __) => TileArt(kind: widget.art, t: _loop.value, focused: _focused, glow: widget.glow),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _shine,
                          builder: (_, __) => CustomPaint(painter: ShinePainter(_shine.value)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(hero ? 30 : 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedBuilder(
                            animation: _loop,
                            builder: (_, child) {
                              final pulse = 0.5 + 0.5 * math.sin(_loop.value * 2 * math.pi);
                              return Container(
                                width: hero ? 70 : 52,
                                height: hero ? 70 : 52,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0x22FFFFFF),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.10 + 0.12 * pulse)),
                                  boxShadow: [
                                    BoxShadow(
                                        color: widget.glow.withValues(alpha: (_focused ? 0.5 : 0.25) + 0.15 * pulse), blurRadius: 24 + 8 * pulse),
                                  ],
                                ),
                                child: child,
                              );
                            },
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
        ),
      ),
    );
  }
}

/// The picture for a wallpaper number (0 = the standard home background).
String wallpaperAsset(int n) =>
    n <= 0 || n > 20 ? 'assets/home_bg.webp' : 'assets/wallpapers/wp${n.toString().padLeft(2, '0')}.webp';
