import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../backend.dart';
import '../config.dart';
import '../engine.dart';
import '../i18n.dart';
import '../network.dart';
import '../speedtest.dart';
import '../vpn.dart';
import '../parental.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'home.dart' show wallpaperAsset;

enum _Section { network, vpn, vod, live, parental, wallpaper, categories, cache, language, info }

const _titles = {
  _Section.network: 'Network',
  _Section.vpn: 'VPN',
  _Section.vod: 'VOD Player',
  _Section.live: 'Live Player',
  _Section.parental: 'Parental Control',
  _Section.wallpaper: 'Main Wallpaper',
  _Section.categories: 'Manage Categories',
  _Section.cache: 'Clear Cache',
  _Section.language: 'Language',
  _Section.info: 'Application Info',
};

const _icons = {
  _Section.network: Icons.wifi_rounded,
  _Section.vpn: Icons.vpn_lock_rounded,
  _Section.vod: Icons.movie_filter_rounded,
  _Section.live: Icons.live_tv_rounded,
  _Section.parental: Icons.shield_rounded,
  _Section.wallpaper: Icons.wallpaper_rounded,
  _Section.language: Icons.translate_rounded,
  _Section.categories: Icons.checklist_rounded,
  _Section.cache: Icons.cleaning_services_rounded,
  _Section.info: Icons.info_rounded,
};

const _colors = {
  _Section.network: Color(0xFF35A7FF),
  _Section.vpn: Color(0xFF2ECC71),
  _Section.vod: Color(0xFFFF9F1C),
  _Section.live: Color(0xFFFF5A5F),
  _Section.parental: Color(0xFF2ECC71),
  _Section.wallpaper: Color(0xFFFF4FD8),
  _Section.language: Color(0xFF35D6C4),
  _Section.categories: Color(0xFF4AA3FF),
  _Section.cache: Color(0xFFB37BFF),
  _Section.info: Color(0xFFFFC400),
};

/// App settings, opened from the gear on the home screen: the menu on the left, the chosen
/// section on the right. The icons spin in once when the page opens.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api});
  final Source api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _Section _section = _Section.network;
  XKind _kind = XKind.live;
  final Map<XKind, List<XCategory>> _cats = {};
  final Map<XKind, String> _catsError = {};
  bool _clearing = false;
  String _cacheNote = '';

  @override
  void initState() {
    super.initState();
    log('screen=settings');
  }

  Future<void> _loadCats(XKind kind) async {
    if (_cats.containsKey(kind)) return;
    try {
      final list = await widget.api.categories(kind);
      if (!mounted) return;
      setState(() => _cats[kind] = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _catsError[kind] = friendlyError(e));
    }
  }

  void _open(_Section s) {
    if (s == _section) return;
    setState(() => _section = s);
    if (s == _Section.parental || s == _Section.categories) _loadCats(_kind);
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: MediaQuery.of(context).size.width < 900 ? 240 : 300,
              color: C.panel,
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 10),
              // A scrolling list, so every option can be reached on small (phone) screens too.
              child: ListView(
                children: [
                  Row(
                    children: [
                      TvFocus(
                        radius: 20,
                        color: C.panel,
                        onTap: () => Navigator.of(context).maybePop(),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.arrow_back_rounded, color: C.text, size: 24),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const _OnceIcon(icon: Icons.settings_rounded, color: C.accent, size: 28, order: 0),
                      const SizedBox(width: 12),
                      Text(t('Settings'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 22),
                  for (final s in _Section.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TvFocus(
                        autofocus: s == _Section.network,
                        selected: s == _section,
                        radius: 11,
                        color: C.panel,
                        onFocus: () => _open(s),
                        onTap: () => _open(s),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          child: Row(
                            children: [
                              _OnceIcon(icon: _icons[s]!, color: _colors[s]!, size: 24, order: s.index + 1),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(t(_titles[s]!),
                                    style: TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: s == _section ? FontWeight.w800 : FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: MediaQuery.of(context).size.width < 900
                    ? const EdgeInsets.fromLTRB(18, 16, 16, 10)
                    : const EdgeInsets.fromLTRB(36, 28, 36, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _OnceIcon(
                            key: ValueKey(_section),
                            icon: _icons[_section]!,
                            color: _colors[_section]!,
                            size: 34,
                            order: 0),
                        const SizedBox(width: 14),
                        Text(t(_titles[_section]!), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Expanded(child: _body()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_section) {
      case _Section.network:
        return const _NetworkPanel();
      case _Section.vpn:
        return const _VpnPanel();
      case _Section.vod:
        return _playerChoice(
          current: ExoEngine.available ? Store.engine : 'mpv',
          onPick: (e) => setState(() => Store.setEngine(e)),
          what: 'Movies and series',
          withMode: true,
        );
      case _Section.live:
        return _playerChoice(
          current: ExoEngine.available ? Store.liveEngine : 'mpv',
          onPick: (e) => setState(() => Store.setLiveEngine(e)),
          what: 'Live TV channels and the channel preview',
          withMode: false,
        );
      case _Section.parental:
        return _parental();
      case _Section.wallpaper:
        return _wallpapers();
      case _Section.categories:
        return _categories();
      case _Section.language:
        return _languages();
      case _Section.cache:
        return _cache();
      case _Section.info:
        return _info();
    }
  }

  // ----------------------------------------------------------------- players

  Widget _playerChoice({
    required String current,
    required ValueChanged<String> onPick,
    required String what,
    required bool withMode,
  }) {
    final exo = ExoEngine.available;
    final mpvChosen = current == 'mpv';
    return ListView(
      children: [
        Text('Plays: $what', style: const TextStyle(fontSize: 14, color: C.dim)),
        const SizedBox(height: 14),
        if (exo)
          _option(
            selected: current == 'exo',
            icon: Icons.smart_display_rounded,
            iconColor: const Color(0xFF4AA3FF),
            title: 'Google ExoPlayer',
            badge: 'RECOMMENDED',
            text: 'Uses the TV\'s own video chip: smooth picture and quick start. Default.',
            onTap: () => onPick('exo'),
          ),
        const SizedBox(height: 10),
        _option(
          selected: mpvChosen,
          icon: Icons.memory_rounded,
          iconColor: const Color(0xFFB37BFF),
          title: 'MPV Player',
          text: 'Plays almost every format. Choose it if something will not play well.',
          onTap: () => onPick('mpv'),
        ),
        const SizedBox(height: 16),
        const Text(
          'When a video will not start on the chosen player, the app tries the other one by itself. '
          'The next video starts on your choice again.',
          style: TextStyle(fontSize: 13.5, color: C.dim, height: 1.5),
        ),
        if (withMode && mpvChosen) ...[
          const SizedBox(height: 24),
          const Text('MPV PICTURE MODE',
              style: TextStyle(fontSize: 13, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          Row(
            children: [
              _chip('Direct (lighter)', Store.videoMode == 'direct', () => setState(() => Store.setVideoMode('direct'))),
              const SizedBox(width: 10),
              _chip('Standard', Store.videoMode == 'gpu', () => setState(() => Store.setVideoMode('gpu'))),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Use Standard if a video plays sound but shows no picture.',
              style: TextStyle(fontSize: 13, color: C.dim)),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- parental

  Future<void> _setPin() async {
    if (Store.parentalPin.isNotEmpty && !await askParentalPin(context, title: 'Current PIN')) return;
    if (!mounted) return;
    final pin = await askNewPin(context);
    if (pin == null || !mounted) return;
    Store.setParentalPin(pin);
    Store.parentalUnlocked = false;
    log('parental pin set');
    setState(() {});
    _toast('Parental PIN saved.');
  }

  Future<void> _removePin() async {
    if (!await askParentalPin(context, title: 'Current PIN')) return;
    Store.setParentalPin('');
    Store.parentalUnlocked = false;
    log('parental pin removed');
    if (mounted) setState(() {});
    _toast('Parental control is off.');
  }

  Future<void> _toggleLock(XCategory c) async {
    if (Store.parentalPin.isEmpty) {
      _toast('Set a PIN first.');
      await _setPin();
      if (Store.parentalPin.isEmpty) return;
    } else if (!await askParentalPin(context)) {
      return;
    }
    Store.setLocked(_kind, c.id, !Store.isLockMarked(_kind, c.id));
    if (mounted) setState(() {});
  }

  Widget _parental() {
    final hasPin = Store.parentalPin.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(hasPin ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: hasPin ? const Color(0xFF2ECC71) : C.dim, size: 20),
            const SizedBox(width: 8),
            Text(hasPin ? 'Parental control is ON' : 'Parental control is OFF  (no PIN set)',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            _chip(hasPin ? 'Change PIN' : 'Set PIN', false, _setPin),
            if (hasPin) ...[const SizedBox(width: 10), _chip('Remove PIN', false, _removePin)],
          ],
        ),
        const SizedBox(height: 8),
        const Text('Locked categories ask for the PIN before they open, and their channels and titles are '
            'left out of "All" and Search.',
            style: TextStyle(fontSize: 13, color: C.dim)),
        const SizedBox(height: 14),
        _kindTabs(),
        const SizedBox(height: 12),
        Expanded(
          child: _catList(
            isOn: (c) => Store.isLockMarked(_kind, c.id),
            onIcon: Icons.lock_rounded,
            offIcon: Icons.lock_open_rounded,
            onColor: const Color(0xFF2ECC71),
            onTap: _toggleLock,
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- categories

  Widget _categories() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Untick a category to hide it everywhere in the app. Tick it again to bring it back.',
            style: TextStyle(fontSize: 13.5, color: C.dim)),
        const SizedBox(height: 14),
        _kindTabs(),
        const SizedBox(height: 12),
        Expanded(
          child: _catList(
            isOn: (c) => !Store.isHidden(_kind, c.id),
            onIcon: Icons.check_box_rounded,
            offIcon: Icons.check_box_outline_blank_rounded,
            onColor: C.accent,
            onTap: (c) async {
              Store.setHidden(_kind, c.id, !Store.isHidden(_kind, c.id));
              setState(() {});
            },
          ),
        ),
      ],
    );
  }

  Widget _kindTabs() {
    const names = {XKind.live: 'Live TV', XKind.vod: 'Movies', XKind.series: 'Series'};
    return Row(
      children: [
        for (final k in XKind.values) ...[
          _chip(names[k]!, _kind == k, () {
            setState(() => _kind = k);
            _loadCats(k);
          }),
          const SizedBox(width: 10),
        ],
      ],
    );
  }

  Widget _catList({
    required bool Function(XCategory) isOn,
    required IconData onIcon,
    required IconData offIcon,
    required Color onColor,
    required Future<void> Function(XCategory) onTap,
  }) {
    final error = _catsError[_kind];
    if (error != null) return Text(error, style: const TextStyle(color: C.danger));
    final cats = _cats[_kind];
    if (cats == null) return const Loading();
    if (cats.isEmpty) return const Text('No categories.', style: TextStyle(color: C.dim));
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisExtent: 46,
        crossAxisSpacing: 10,
        mainAxisSpacing: 8,
      ),
      itemCount: cats.length,
      itemBuilder: (context, i) {
        final c = cats[i];
        final on = isOn(c);
        return TvFocus(
          radius: 9,
          color: C.panel,
          onTap: () => onTap(c),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(on ? onIcon : offIcon, size: 20, color: on ? onColor : C.dim),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: on ? C.text : C.dim, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------- wallpaper

  Widget _wallpapers() {
    final current = Store.wallpaper;
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 16 / 9,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: 21,
      itemBuilder: (context, i) {
        final on = current == i;
        return TvFocus(
          autofocus: on,
          selected: on,
          radius: 12,
          color: Colors.black,
          onTap: () {
            Store.setWallpaper(i);
            log('settings wallpaper=$i');
            setState(() {});
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(wallpaperAsset(i), fit: BoxFit.cover, cacheWidth: 400, filterQuality: FilterQuality.medium),
                if (i == 0)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xCC000000), borderRadius: BorderRadius.circular(5)),
                      child: Text(t('Default'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ),
                if (on)
                  const Positioned(
                    right: 8,
                    top: 8,
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: C.accent,
                      child: Icon(Icons.check_rounded, size: 18, color: Colors.black),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- language

  Widget _languages() {
    final chosen = Store.uiLanguage;
    final entries = <(String, String, String)>[('auto', t('Automatic (TV language)'), ''), ...kLanguages];
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 54,
        crossAxisSpacing: 10,
        mainAxisSpacing: 8,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final (code, english, own) = entries[i];
        final on = chosen == code;
        return TvFocus(
          autofocus: on,
          selected: on,
          radius: 10,
          color: C.panel,
          onTap: () {
            Store.setUiLanguage(code);
            log('settings language=$code');
            setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    size: 18, color: on ? C.accent : C.dim),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(own.isEmpty ? english : own,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      if (own.isNotEmpty && own != english)
                        Text(english, style: const TextStyle(fontSize: 11.5, color: C.dim)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------- cache

  Future<void> _clearCache() async {
    if (_clearing) return;
    setState(() {
      _clearing = true;
      _cacheNote = '';
    });
    try {
      await Backend.clearAppCache();
      _cacheNote = 'Done. Pictures, guide and temporary files were cleared.';
    } catch (_) {
      _cacheNote = 'The cache could not be cleared completely.';
    }
    log('settings cache cleared');
    if (mounted) setState(() => _clearing = false);
  }

  Widget _cache() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Removes saved pictures (logos, posters), guide data and temporary files. Your login, '
          'favourites and settings stay. Use it when pictures look old or the app feels slow.',
          style: TextStyle(fontSize: 14, color: C.dim, height: 1.5),
        ),
        const SizedBox(height: 20),
        TvFocus(
          radius: 12,
          color: const Color(0xFF2A2140),
          onTap: _clearCache,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _clearing
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: C.accent))
                    : const Icon(Icons.cleaning_services_rounded, color: Color(0xFFB37BFF)),
                const SizedBox(width: 12),
                Text(t('Clear cache now'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
        if (_cacheNote.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(_cacheNote, style: const TextStyle(fontSize: 14, color: Color(0xFF2ECC71))),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------- info

  Widget _info() {
    final rows = <List<String>>[
      ['Application', kAppName],
      ['Version', Backend.appVersionName.isEmpty ? '—' : Backend.appVersionName],
      ['Version code', Backend.appVersionCode > 0 ? '${Backend.appVersionCode}' : '—'],
      ['Playlist', widget.api.label],
    ];
    return ListView(
      children: [
        for (final r in rows)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                SizedBox(width: 170, child: Text(r[0], style: const TextStyle(fontSize: 14.5, color: C.dim))),
                Expanded(
                  child: Text(r[1],
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: C.text)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ----------------------------------------------------------------- helpers

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        width: 340,
        content: Text(text, textAlign: TextAlign.center),
      ));
  }

  Widget _option({
    required bool selected,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String text,
    required VoidCallback onTap,
    String badge = '',
  }) {
    return TvFocus(
      selected: selected,
      radius: 12,
      color: C.panel,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      if (badge.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: const Color(0x332ECC71), borderRadius: BorderRadius.circular(5)),
                          child: Text(badge,
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF2ECC71),
                                  letterSpacing: 0.6)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(text, style: const TextStyle(fontSize: 13, color: C.dim)),
                ],
              ),
            ),
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? C.accent : C.dim),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return TvFocus(
      selected: selected,
      radius: 20,
      color: C.panel,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        child: Text(label, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
      ),
    );
  }
}

/// An icon that spins and pops in once when it first appears, then stays still.
class _OnceIcon extends StatefulWidget {
  const _OnceIcon({super.key, required this.icon, required this.color, this.size = 24, this.order = 0});
  final IconData icon;
  final Color color;
  final double size;
  final int order;

  @override
  State<_OnceIcon> createState() => _OnceIconState();
}

class _OnceIconState extends State<_OnceIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: 80 * widget.order), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(_c.value);
        final m = Matrix4.identity()
          ..setEntry(3, 2, 0.002)
          ..rotateY((1 - _c.value) * 2 * math.pi)
          ..scaleByDouble(0.3 + 0.7 * t, 0.3 + 0.7 * t, 1, 1);
        return Opacity(
          opacity: _c.value.clamp(0.0, 1.0),
          child: Transform(alignment: Alignment.center, transform: m, child: child),
        );
      },
      child: Icon(widget.icon, color: widget.color, size: widget.size),
    );
  }
}


/// Settings › Network: the connection in use, the Wi-Fi networks around the TV, and joining one.
class _NetworkPanel extends StatefulWidget {
  const _NetworkPanel();

  @override
  State<_NetworkPanel> createState() => _NetworkPanelState();
}

class _NetworkPanelState extends State<_NetworkPanel> with WidgetsBindingObserver {
  NetInfo _info = const NetInfo();
  List<WifiNet>? _nets = const [];
  bool _scanning = false;
  bool _askedPermission = false;
  String _note = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh(scan: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the permission question or the TV's Wi-Fi page: look again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(scan: true);
  }

  Future<void> _refresh({bool scan = false}) async {
    final info = await Net.info();
    if (!mounted) return;
    setState(() => _info = info);
    if (scan) await _scan();
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    var nets = await Net.scan();
    if (nets != null && nets.isEmpty) {
      // A fresh scan takes a moment on most TVs: ask once more shortly after.
      await Future<void>.delayed(const Duration(seconds: 3));
      nets = await Net.scan();
    }
    if (!mounted) return;
    setState(() {
      _nets = nets;
      _scanning = false;
    });
    if (nets == null && !_askedPermission) {
      _askedPermission = true;
      await Net.askPermission();
    }
  }

  Future<void> _join(WifiNet n) async {
    if (!_info.canJoin) {
      setState(() => _note = 'This TV only lets its own Wi-Fi page join networks. Opening it now…');
      await Net.openSettings();
      return;
    }
    var password = '';
    if (n.secured) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: C.panel,
          title: Text(n.ssid),
          content: SizedBox(
            width: 380,
            child: TvField(
              controller: controller,
              label: 'Wi-Fi password',
              icon: Icons.key_rounded,
              obscure: true,
              autofocus: true,
              action: TextInputAction.done,
              onSubmitted: (_) => Navigator.of(ctx).pop(true),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Connect')),
          ],
        ),
      );
      password = controller.text;
      controller.dispose();
      if (ok != true || !mounted) return;
    }
    setState(() => _note = 'Connecting to ${n.ssid}…');
    final r = await Net.join(n.ssid, password, n.secured);
    if (!mounted) return;
    if (r == 'failed') {
      setState(() => _note = 'Could not connect to ${n.ssid}. Check the password and try again.');
      return;
    }
    if (r == 'settings') return;
    // Give the TV a few seconds to connect, then show the result.
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final info = await Net.info();
      if (!mounted) return;
      setState(() => _info = info);
      if (info.type == 'wifi' && info.ssid == n.ssid) {
        setState(() => _note = 'Connected to ${n.ssid}.');
        return;
      }
    }
    setState(() => _note = 'Still connecting… If it does not connect, check the password.');
  }

  Widget _bars(int level, {double size = 20, Color? color}) {
    const icons = [
      Icons.signal_wifi_0_bar_rounded,
      Icons.network_wifi_1_bar_rounded,
      Icons.network_wifi_2_bar_rounded,
      Icons.network_wifi_3_bar_rounded,
      Icons.signal_wifi_4_bar_rounded,
    ];
    return Icon(icons[level.clamp(0, 4)], size: size, color: color ?? (level >= 3 ? const Color(0xFF2ECC71) : C.accent));
  }

  @override
  Widget build(BuildContext context) {
    final i = _info;
    final connected = i.type != 'none';
    final title = switch (i.type) {
      'wifi' => i.ssid.isEmpty ? 'Wi-Fi' : i.ssid,
      'ethernet' => 'Cable (Ethernet)',
      'mobile' => 'Mobile data',
      'none' => 'Not connected',
      _ => 'Connected',
    };
    final details = <String>[
      if (i.type == 'wifi' && i.linkMbps > 0) '${i.linkMbps} Mbit/s',
      if (i.type == 'wifi' && i.frequency > 0) i.frequency > 4900 ? '5 GHz' : '2.4 GHz',
      if (i.ip.isNotEmpty) 'IP ${i.ip}',
    ];
    final nets = _nets;
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: C.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: connected ? const Color(0x552ECC71) : const Color(0x55FF6B6B)),
          ),
          child: Row(
            children: [
              if (i.type == 'wifi')
                _bars(i.level, size: 40)
              else
                Icon(i.type == 'ethernet' ? Icons.settings_ethernet_rounded : (connected ? Icons.public_rounded : Icons.wifi_off_rounded),
                    size: 40, color: connected ? const Color(0xFF2ECC71) : C.danger),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(connected ? 'CONNECTED' : 'OFFLINE',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                            color: connected ? const Color(0xFF2ECC71) : C.danger)),
                    const SizedBox(height: 2),
                    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    if (details.isNotEmpty)
                      Text(details.join('   ·   '), style: const TextStyle(fontSize: 13.5, color: C.dim)),
                  ],
                ),
              ),
              TvFocus(
                radius: 10,
                color: C.card,
                onTap: () => showSpeedTest(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.speed_rounded, size: 17, color: C.accent),
                      SizedBox(width: 8),
                      Text('Speed test', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TvFocus(
                radius: 10,
                color: C.card,
                onTap: Net.openSettings,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.settings_rounded, size: 17, color: C.dim),
                      SizedBox(width: 8),
                      Text('TV Wi-Fi settings', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Text('NEARBY WI-FI NETWORKS',
                style: TextStyle(fontSize: 13, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const SizedBox(width: 14),
            if (_scanning)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent)),
            const Spacer(),
            TvFocus(
              radius: 18,
              color: C.panel,
              onTap: () => _refresh(scan: true),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 17, color: C.accent),
                    SizedBox(width: 6),
                    Text('Scan again', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_note.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_note, style: const TextStyle(fontSize: 13.5, color: C.accent)),
        ],
        const SizedBox(height: 12),
        if (!Net.available)
          const Text('Network settings are available in the Android app.', style: TextStyle(color: C.dim))
        else if (nets == null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'To list Wi-Fi networks, Android needs the "location" permission for this app '
                '(it is only used for the Wi-Fi list).',
                style: TextStyle(fontSize: 13.5, color: C.dim, height: 1.5),
              ),
              const SizedBox(height: 10),
              TvFocus(
                radius: 10,
                color: C.card,
                onTap: Net.askPermission,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text('Allow', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          )
        else if (nets.isEmpty && !_scanning)
          Text(i.wifiOn ? 'No Wi-Fi networks found yet. Press "Scan again".' : 'Wi-Fi is switched off on this TV.',
              style: const TextStyle(color: C.dim))
        else
          for (final n in nets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TvFocus(
                radius: 10,
                color: C.panel,
                selected: i.type == 'wifi' && i.ssid == n.ssid,
                onTap: () => _join(n),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(
                    children: [
                      _bars(n.level),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(n.ssid,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                      if (i.type == 'wifi' && i.ssid == n.ssid)
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Text('Connected',
                              style: TextStyle(fontSize: 12.5, color: Color(0xFF2ECC71), fontWeight: FontWeight.w800)),
                        ),
                      Text(n.band, style: const TextStyle(fontSize: 12, color: C.dim)),
                      const SizedBox(width: 10),
                      Icon(n.secured ? Icons.lock_rounded : Icons.lock_open_rounded, size: 16, color: C.dim),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}


/// Settings › VPN: the customer's own WireGuard VPN (from their VPN provider), added from the
/// website, a link, or typed in; connect / disconnect for the whole TV.
class _VpnPanel extends StatefulWidget {
  const _VpnPanel();

  @override
  State<_VpnPanel> createState() => _VpnPanelState();
}

class _VpnPanelState extends State<_VpnPanel> {
  List<VpnProfile> _list = const [];
  String _busy = '';
  String _note = '';
  bool _noteBad = false;

  @override
  void initState() {
    super.initState();
    Vpn.state.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    Vpn.state.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await Vpn.refresh();
    final list = await Vpn.profiles();
    if (Vpn.activeName.isEmpty) Vpn.activeName = await Vpn.lastUsed();
    if (mounted) setState(() => _list = list);
  }

  void _say(String text, {bool bad = false}) {
    if (mounted) {
      setState(() {
        _note = text;
        _noteBad = bad;
      });
    }
  }

  Future<void> _addConfig(String name, String config) async {
    final problem = await Vpn.check(config);
    if (problem.isNotEmpty) {
      _say('This is not a valid WireGuard configuration: $problem', bad: true);
      return;
    }
    await Vpn.add(VpnProfile(name.trim().isEmpty ? 'My VPN' : name.trim(), config));
    await _load();
    _say('"${name.trim().isEmpty ? 'My VPN' : name.trim()}" was added. Select it to connect.');
  }

  Future<void> _fromSite() async {
    setState(() => _busy = 'site');
    try {
      final v = await Backend.vpnFromSite();
      if (v == null) {
        _say('No VPN is saved on the website for this TV yet. Add it on the website: Upload Playlist › VPN.',
            bad: true);
      } else {
        await _addConfig(v['name']!, v['config']!);
      }
    } catch (e) {
      _say('The website could not be reached.', bad: true);
    }
    if (mounted) setState(() => _busy = '');
  }

  Future<String?> _ask(String title, String label, IconData icon) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: TvField(
            controller: c,
            label: label,
            icon: icon,
            autofocus: true,
            action: TextInputAction.done,
            onSubmitted: (_) => Navigator.of(ctx).pop(true),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('OK')),
        ],
      ),
    );
    final text = c.text;
    c.dispose();
    return ok == true ? text : null;
  }

  Future<void> _fromLink() async {
    final url = await _ask('VPN configuration link', 'Link to the .conf file', Icons.link_rounded);
    if (url == null || url.trim().isEmpty) return;
    setState(() => _busy = 'link');
    try {
      final text = await Vpn.download(url);
      final parts = Uri.tryParse(url.trim())?.pathSegments.where((x) => x.isNotEmpty).toList() ?? const <String>[];
      final name = parts.isEmpty ? 'My VPN' : parts.last;
      await _addConfig(name.replaceAll(RegExp(r'\.conf$'), ''), text);
    } catch (e) {
      _say(e is FormatException ? e.message : 'The link could not be downloaded.', bad: true);
    }
    if (mounted) setState(() => _busy = '');
  }

  Future<void> _connect(VpnProfile p) async {
    if (Vpn.state.value == 'up' && Vpn.activeName == p.name) {
      setState(() => _busy = p.name);
      final err = await Vpn.disconnect();
      _say(err.isEmpty ? 'VPN switched off.' : err, bad: err.isNotEmpty);
    } else {
      setState(() => _busy = p.name);
      if (Vpn.state.value == 'up') await Vpn.disconnect();
      final err = await Vpn.connect(p);
      _say(err.isEmpty ? 'Connected through "${p.name}". All apps on this TV now use the VPN.' : err,
          bad: err.isNotEmpty);
    }
    if (mounted) setState(() => _busy = '');
  }

  Future<void> _delete(VpnProfile p) async {
    if (Vpn.state.value == 'up' && Vpn.activeName == p.name) await Vpn.disconnect();
    await Vpn.remove(p.name);
    await _load();
    _say('"${p.name}" was removed.');
  }

  Widget _action(IconData icon, String label, VoidCallback onTap, {bool busy = false}) => TvFocus(
        radius: 10,
        color: C.card,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent))
                  : Icon(icon, size: 17, color: C.accent),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final up = Vpn.state.value == 'up';
    if (!Vpn.available) {
      return const Text('The VPN works in the Android app.', style: TextStyle(color: C.dim));
    }
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: C.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: up ? const Color(0x772ECC71) : const Color(0x33FFFFFF)),
          ),
          child: Row(
            children: [
              Icon(up ? Icons.vpn_lock_rounded : Icons.lock_open_rounded,
                  size: 40, color: up ? const Color(0xFF2ECC71) : C.dim),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(up ? 'VPN ON' : 'VPN OFF',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                            color: up ? const Color(0xFF2ECC71) : C.dim)),
                    Text(up ? Vpn.activeName : 'Not protected',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              if (up) _action(Icons.power_settings_new_rounded, 'Switch off', () async {
                    await Vpn.disconnect();
                    _say('VPN switched off.');
                  }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Use the WireGuard VPN from your VPN provider (most providers offer a WireGuard ".conf" file). '
          'Add it once, then select it here to connect. The VPN covers every app on this TV.',
          style: TextStyle(fontSize: 13.5, color: C.dim, height: 1.5),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _action(Icons.link_rounded, 'Add from link', _fromLink, busy: _busy == 'link'),
          ],
        ),
        if (_note.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(_note, style: TextStyle(fontSize: 13.5, color: _noteBad ? C.danger : const Color(0xFF2ECC71))),
        ],
        const SizedBox(height: 18),
        const Text('MY VPNS',
            style: TextStyle(fontSize: 13, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        if (_list.isEmpty)
          const Text('No VPN added yet.', style: TextStyle(color: C.dim))
        else
          for (final p in _list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TvFocus(
                      radius: 10,
                      color: C.panel,
                      selected: up && Vpn.activeName == p.name,
                      onTap: () => _connect(p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            _busy == p.name
                                ? const SizedBox(
                                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent))
                                : Icon(Icons.shield_rounded,
                                    color: up && Vpn.activeName == p.name ? const Color(0xFF2ECC71) : C.dim),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                                  if (p.server.isNotEmpty)
                                    Text(p.server, style: const TextStyle(fontSize: 12.5, color: C.dim)),
                                ],
                              ),
                            ),
                            Text(up && Vpn.activeName == p.name ? 'Connected · OK to switch off' : 'OK to connect',
                                style: const TextStyle(fontSize: 12.5, color: C.dim)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TvFocus(
                    radius: 10,
                    color: C.panel,
                    onTap: () => _delete(p),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.delete_outline_rounded, color: C.dim, size: 20),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
