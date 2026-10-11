import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../backend.dart';
import '../config.dart';
import '../engine.dart';
import '../parental.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';

enum _Section { vod, live, parental, categories, cache, info }

const _titles = {
  _Section.vod: 'VOD Player',
  _Section.live: 'Live Player',
  _Section.parental: 'Parental Control',
  _Section.categories: 'Manage Categories',
  _Section.cache: 'Clear Cache',
  _Section.info: 'Application Info',
};

const _icons = {
  _Section.vod: Icons.movie_filter_rounded,
  _Section.live: Icons.live_tv_rounded,
  _Section.parental: Icons.shield_rounded,
  _Section.categories: Icons.checklist_rounded,
  _Section.cache: Icons.cleaning_services_rounded,
  _Section.info: Icons.info_rounded,
};

const _colors = {
  _Section.vod: Color(0xFFFF9F1C),
  _Section.live: Color(0xFFFF5A5F),
  _Section.parental: Color(0xFF2ECC71),
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
  _Section _section = _Section.vod;
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
              width: 300,
              color: C.panel,
              padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      _OnceIcon(icon: Icons.settings_rounded, color: C.accent, size: 28, order: 0),
                      SizedBox(width: 12),
                      Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 22),
                  for (final s in _Section.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TvFocus(
                        autofocus: s == _Section.vod,
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
                                child: Text(_titles[s]!,
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
                padding: const EdgeInsets.fromLTRB(36, 28, 36, 20),
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
                        Text(_titles[_section]!, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
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
      case _Section.categories:
        return _categories();
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
                const Text('Clear cache now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
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
    String expiry;
    switch (Backend.licStatus) {
      case 'active':
        if (Backend.licType == 'lifetime') {
          expiry = 'Lifetime (never expires)';
        } else {
          final d = (Backend.licChecked ?? DateTime.now()).add(Duration(days: math.max(0, Backend.licDaysLeft)));
          expiry = '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}'
              '  (${Backend.licDaysLeft} days left)';
        }
      case 'trial':
        final d = (Backend.licChecked ?? DateTime.now()).add(Duration(days: math.max(0, Backend.licDaysLeft)));
        expiry = 'Free trial until ${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}'
            '  (${Backend.licDaysLeft} days left)';
      case 'expired':
        expiry = 'Expired';
      case 'suspended':
        expiry = 'Suspended';
      default:
        expiry = 'Unknown (no answer from the website yet)';
    }
    final rows = <List<String>>[
      ['Application', kAppName],
      ['Version', Backend.appVersionName.isEmpty ? '—' : Backend.appVersionName],
      ['Version code', Backend.appVersionCode > 0 ? '${Backend.appVersionCode}' : '—'],
      ['Device ID', Backend.deviceId.isEmpty ? '—' : Backend.deviceId],
      ['Licence', Backend.statusLine.isEmpty ? '—' : Backend.statusLine],
      ['Expires', expiry],
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
                          color: r[0] == 'Expires' && Backend.licStatus == 'expired' ? C.danger : C.text)),
                ),
              ],
            ),
          ),
        if (Backend.updateAvailable)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('A newer version is available: use "Update" on the home screen.',
                style: TextStyle(fontSize: 13.5, color: C.accent)),
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
