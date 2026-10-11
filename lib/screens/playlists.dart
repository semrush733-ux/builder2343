import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';

import '../backend.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';

enum _State { checking, active, expired, unknown }

/// The playlists on the customer's account, each with its address and a status dot:
/// green = account active, red = expired / blocked, grey = could not be checked.
/// The checks run one after the other in the background (a light login call each), so the TV
/// is never busy with several at once. OK on a playlist switches to it.
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key, required this.current});

  /// Name of the playlist in use now (shown with a "Now playing" tag).
  final String current;

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  // Kept for the whole app session, so opening the page again does not check again.
  static final Map<String, _State> _known = {};
  static final Map<String, DateTime?> _expires = {};

  List<BPlaylist>? _lists;
  String? _error;

  @override
  void initState() {
    super.initState();
    log('screen=playlists');
    _load();
  }

  String _key(BPlaylist p) => '${p.url}|${p.username}';

  Future<void> _load() async {
    try {
      final lists = await Backend.playlists();
      if (!mounted) return;
      setState(() => _lists = lists);
      _checkAll(lists);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// Xtream login data of a playlist: its own fields, or the ones inside an Xtream-style M3U link.
  (String, String, String)? _xtream(BPlaylist p) {
    if (p.isXtream) return (parseServerInput(p.url).server, p.username, p.password);
    final parsed = parseServerInput(p.url);
    final user = parsed.username;
    final pass = parsed.password;
    if (user != null && pass != null && user.isNotEmpty && parsed.server.isNotEmpty) {
      return (parsed.server, user, pass);
    }
    return null;
  }

  Future<void> _checkAll(List<BPlaylist> lists) async {
    for (final p in lists) {
      if (!mounted) return;
      final key = _key(p);
      if (_known.containsKey(key) && _known[key] != _State.checking) continue;
      final login = _xtream(p);
      if (login == null) {
        _known[key] = _State.unknown;
        setState(() {});
        continue;
      }
      setState(() => _known[key] = _State.checking);
      try {
        final account = await XtreamApi(login.$1, login.$2, login.$3).login();
        final exp = account.expires;
        _expires[key] = exp;
        _known[key] = exp != null && exp.isBefore(DateTime.now()) ? _State.expired : _State.active;
      } on XtreamAuthException {
        _known[key] = _State.expired;
      } catch (_) {
        _known[key] = _State.unknown;
      }
      if (mounted) setState(() {});
    }
  }

  // Locked playlists (4-digit PIN set on the website) are hidden until their PIN is typed;
  // they then stay visible until the app is closed.
  static final Set<int> _revealed = {};

  static String _hash(String pin) => sha256.convert(utf8.encode('b1g-pin:${pin.trim()}')).toString();

  bool _visible(BPlaylist p) => !p.locked || _revealed.contains(p.id);

  void _pick(BPlaylist p) => Navigator.of(context).pop(p);

  /// "Show locked playlists": the PIN shows every playlist locked with it.
  Future<void> _reveal() async {
    final lists = _lists ?? const <BPlaylist>[];
    final hashes = {for (final p in lists) if (p.locked) p.pinHash};
    final ok = await _askPin('Locked playlists', (hash) => hashes.contains(hash), (hash) {
      for (final p in lists) {
        if (p.locked && p.pinHash == hash) _revealed.add(p.id);
      }
    });
    if (ok && mounted) setState(() {});
  }

  Future<bool> _askPin(String title, bool Function(String hash) accepts, void Function(String hash) onOk) async {
    final controller = TextEditingController();
    var error = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) {
          void check(String value) {
            final hash = _hash(value);
            if (accepts(hash)) {
              onOk(hash);
              Navigator.of(ctx).pop(true);
            } else {
              controller.clear();
              refresh(() => error = 'Wrong PIN, please try again.');
            }
          }

          return AlertDialog(
            backgroundColor: C.panel,
            title: Row(
              children: [
                const Icon(Icons.lock_rounded, color: C.accent),
                const SizedBox(width: 10),
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TvField(
                    controller: controller,
                    label: 'Playlist PIN (4 digits)',
                    icon: Icons.pin_rounded,
                    obscure: true,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    action: TextInputAction.done,
                    onSubmitted: check,
                  ),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(error, style: const TextStyle(color: C.danger, fontSize: 13.5)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
              TextButton(onPressed: () => check(controller.text), child: const Text('OK')),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final lists = _lists;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(44, 26, 44, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.playlist_play_rounded, color: C.accent, size: 30),
                  SizedBox(width: 12),
                  Text('Playlists', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  Spacer(),
                  _Legend(color: Color(0xFF2ECC71), text: 'Active'),
                  SizedBox(width: 18),
                  _Legend(color: C.danger, text: 'Expired'),
                  SizedBox(width: 18),
                  _Legend(color: C.dim, text: 'Not checked'),
                ],
              ),
              const SizedBox(height: 22),
              Expanded(
                child: _error != null
                    ? Text(_error!, style: const TextStyle(color: C.danger))
                    : lists == null
                        ? const Loading()
                        : lists.isEmpty
                            ? const Center(
                                child: Text('No playlists on your account yet.\nAdd one from the website (Upload Playlist / QR).',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: C.dim, fontSize: 15, height: 1.5)),
                              )
                            : Builder(builder: (context) {
                                final shown = lists.where(_visible).toList();
                                final hidden = lists.length - shown.length;
                                return ListView(
                                  children: [
                                    for (var i = 0; i < shown.length; i++)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 10),
                                        child: _row(shown[i], i == 0),
                                      ),
                                    if (hidden > 0)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: TvFocus(
                                          autofocus: shown.isEmpty,
                                          radius: 10,
                                          color: C.panel,
                                          onTap: _reveal,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.lock_rounded, size: 18, color: C.accent),
                                                const SizedBox(width: 10),
                                                Text(
                                                    hidden == 1
                                                        ? 'Show locked playlist (PIN)'
                                                        : 'Show $hidden locked playlists (PIN)',
                                                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BPlaylist p, bool first) {
    final key = _key(p);
    final state = _known[key] ?? _State.checking;
    final exp = _expires[key];
    final color = switch (state) {
      _State.active => const Color(0xFF2ECC71),
      _State.expired => C.danger,
      _ => C.dim,
    };
    final label = switch (state) {
      _State.checking => 'Checking…',
      _State.active => exp == null
          ? 'Active'
          : 'Active until ${exp.day.toString().padLeft(2, '0')}-${exp.month.toString().padLeft(2, '0')}-${exp.year}',
      _State.expired => 'Expired',
      _State.unknown => 'Not checked',
    };
    final now = p.name == widget.current || p.username == widget.current;
    return TvFocus(
      autofocus: first,
      radius: 12,
      color: C.panel,
      selected: now,
      onTap: () => _pick(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            _Dot(color: color, pulsing: state == _State.checking),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (p.locked)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.lock_rounded, size: 18, color: C.accent),
                        ),
                      Flexible(
                        child: Text(p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(5)),
                        child: Text(p.isXtream ? 'XTREAM' : 'M3U',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: C.dim)),
                      ),
                      if (now) ...[
                        const SizedBox(width: 8),
                        const Text('Now playing',
                            style: TextStyle(fontSize: 12, color: C.accent, fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(fontSize: 13.5, color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          _Dot(color: color),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 13, color: C.dim)),
        ],
      );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.pulsing = false});
  final Color color;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
      ),
    );
    if (!pulsing) return dot;
    return const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: C.dim));
  }
}
