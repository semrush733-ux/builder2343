import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../backend.dart';
import '../m3u.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'browse.dart';
import 'catchup.dart';
import 'device.dart';
import 'login.dart';
import 'update_web.dart' if (dart.library.io) 'update.dart';

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
    Backend.changes.addListener(_onBackendChange);
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
          'An M3U playlist link does not carry recordings.',
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: C.accent))),
        ],
      ),
    );
  }

  /// "Playlists" above the tiles: shows the lists on this device's account
  /// (added on the website) and switches to the chosen one.
  Future<void> _choosePlaylist() async {
    List<BPlaylist> lists = const [];
    String? error;
    try {
      lists = await Backend.playlists();
    } catch (e) {
      error = e.toString();
    }
    if (!mounted) return;

    final choice = await showDialog<BPlaylist>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: const Text('Playlists'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('Now playing:  ${widget.api.label}',
                    style: const TextStyle(color: C.dim, fontSize: 13.5)),
              ),
              if (error != null)
                Text(error, style: const TextStyle(color: C.danger, fontSize: 13.5))
              else if (lists.isEmpty)
                const Text('No playlists on your account yet.\nAdd one from the website (Upload Playlist / QR).',
                    style: TextStyle(color: C.dim, fontSize: 13.5, height: 1.4))
              else
                for (var i = 0; i < lists.length; i++)
                  TvFocus(
                    autofocus: i == 0,
                    radius: 9,
                    color: C.card,
                    onTap: () => Navigator.of(ctx).pop(lists[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.playlist_play_rounded, size: 18, color: C.accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(lists[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                          ),
                          Text(lists[i].isXtream ? 'Xtream' : 'M3U',
                              style: const TextStyle(fontSize: 12, color: C.dim)),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            autofocus: error != null || lists.isEmpty,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
      if (choice.isXtream) {
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

  void _showDevice() => showDeviceDialog(context);

  void _showUpdate() {
    final update = Backend.update;
    if (update != null) showUpdateDialog(context, update);
  }

  void _onBackendChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Backend.changes.removeListener(_onBackendChange);
    super.dispose();
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Faded entertainment picture far behind everything...
          Opacity(
            opacity: 0.42,
            child: Image.asset(
              'assets/home_bg.webp',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => const SizedBox(),
            ),
          ),
          // ...softened towards the edges so the tiles and text stay easy to read...
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.1),
                radius: 1.05,
                colors: [Color(0x330A0C10), Color(0xE60A0C10)],
              ),
            ),
          ),
          // ...and a large, very faint "Cloud Player" behind the tiles.
          const IgnorePointer(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 30),
                  child: Text(
                    'Cloud Player',
                    style: TextStyle(
                      fontSize: 190,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -6,
                      color: Color(0x14FFFFFF),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _homeContent(),
        ],
      ),
    );
  }

  Widget _homeContent() {
    return Padding(
        padding: const EdgeInsets.fromLTRB(44, 26, 44, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Logo(size: 30),
                const SizedBox(width: 16),
                TvFocus(
                  onTap: _choosePlaylist,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.playlist_play_rounded, size: 18, color: C.dim),
                        SizedBox(width: 8),
                        Text('Playlists', style: TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                ),
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
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 290),
                  child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _BigTile(
                      autofocus: true,
                      order: 0,
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
                      order: 1,
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
                      order: 2,
                      icon: Icons.video_library_rounded,
                      title: 'Series',
                      subtitle: 'Seasons and episodes',
                      colors: const [Color(0xFF2A1238), Color(0xFF120B17)],
                      onTap: () => _open(XKind.series),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: _BigTile(
                      order: 3,
                      icon: Icons.history_rounded,
                      title: 'Catch Up',
                      subtitle: 'Replay past TV',
                      colors: const [Color(0xFF0F2E1C), Color(0xFF0A130D)],
                      onTap: _openCatchup,
                    ),
                  ),
                ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text('Hold OK on a channel or title to add it to Favourites.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: C.dim, fontSize: 13)),
                ),
                const SizedBox(width: 12),
                if (Backend.updateAvailable) ...[
                  TvFocus(
                    color: C.accent,
                    focusBorder: Colors.white,
                    onTap: _showUpdate,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.system_update_rounded, size: 17, color: Colors.black),
                          SizedBox(width: 8),
                          Text('Update',
                              style: TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                TvFocus(
                  onTap: _showDevice,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.qr_code_2_rounded, size: 17, color: C.dim),
                        const SizedBox(width: 8),
                        Text(
                          Backend.statusLine.isEmpty ? 'My device' : 'My device  ·  ${Backend.statusLine}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
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
    this.order = 0,
  });

  final int order;
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
            _FloatIcon(icon: icon, order: order),
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

/// The tile's icon in a rounded badge that floats gently up and down,
/// so the home boxes feel alive without being distracting.
class _FloatIcon extends StatefulWidget {
  const _FloatIcon({required this.icon, this.order = 0});
  final IconData icon;

  /// Position of the tile (0..3): which corner the icon flies in from, and how late.
  final int order;

  @override
  State<_FloatIcon> createState() => _FloatIconState();
}

/// A 3D icon: it flies in from a corner of the screen spinning, then floats, sways in depth
/// and turns a full circle every few seconds. Each tile is a little out of step with the others.
class _FloatIconState extends State<_FloatIcon> with TickerProviderStateMixin {
  static const _corners = [Offset(-150, -130), Offset(150, -130), Offset(-150, 130), Offset(150, 130)];

  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 6000));

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: 150 + widget.order * 220), () {
      if (!mounted) return;
      _enter.forward();
      // Start the loop at a different phase per tile, so the four do not move in step.
      _loop.value = (widget.order * 0.23) % 1.0;
      _loop.repeat();
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _loop.dispose();
    super.dispose();
  }

  Widget _badge() {
    // A few darker copies behind the icon give it thickness when it turns.
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x33FFFFFF), Color(0x0AFFFFFF)],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x22FFFFFF)),
              boxShadow: const [
                BoxShadow(color: Color(0x40FFC400), blurRadius: 28, offset: Offset(0, 14)),
              ],
            ),
          ),
          for (var d = 4; d >= 1; d--)
            Transform.translate(
              offset: Offset(d * 0.9, d * 1.2),
              child: Icon(widget.icon, size: 48, color: Color.lerp(const Color(0xFF7A5A00), const Color(0xFFB88A00), d / 4)),
            ),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFF1B0), C.accent, Color(0xFFFF9F1C)],
            ).createShader(r),
            child: Icon(widget.icon, size: 48),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_enter, _loop]),
        builder: (context, child) {
          // Fly in: from the corner, small, spinning on two axes, settling with a small overshoot.
          final e = Curves.easeOutBack.transform(_enter.value);
          final fade = Curves.easeOut.transform((_enter.value * 1.6).clamp(0.0, 1.0));
          final corner = _corners[widget.order % _corners.length];
          final fly = Offset.lerp(corner, Offset.zero, e)!;
          final enterSpinY = (1 - e) * 2 * math.pi;
          final enterSpinX = (1 - e) * math.pi / 2;
          final scale = 0.3 + 0.7 * e;

          // Then: float up and down, sway in depth, and one full turn near the end of each cycle.
          final t = _loop.value;
          final wave = math.sin(t * 2 * math.pi);
          final float = -8 * (0.5 + 0.5 * wave);
          var turnY = 0.32 * math.sin(t * 4 * math.pi);
          if (t > 0.78) {
            turnY += Curves.easeInOutCubic.transform((t - 0.78) / 0.22) * 2 * math.pi;
          }
          final tiltX = 0.12 * math.cos(t * 2 * math.pi);

          final m = Matrix4.identity()
            ..setEntry(3, 2, 0.0016) // perspective
            ..translateByDouble(fly.dx, fly.dy + float * _enter.value, 0, 1)
            ..rotateY(enterSpinY + turnY * _enter.value)
            ..rotateX(enterSpinX + tiltX * _enter.value)
            ..scaleByDouble(scale, scale, scale, 1);
          return Opacity(
            opacity: fade,
            child: Transform(alignment: Alignment.center, transform: m, child: child),
          );
        },
        child: _badge(),
      ),
    );
  }
}
