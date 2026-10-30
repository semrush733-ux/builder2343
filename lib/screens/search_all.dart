import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'browse.dart';
import 'movie.dart';
import 'player.dart';
import 'series.dart';

/// One search box for Live TV, Movies and Series together.
class SearchAllScreen extends StatefulWidget {
  const SearchAllScreen({super.key, required this.api});
  final Source api;

  @override
  State<SearchAllScreen> createState() => _SearchAllScreenState();
}

class _SearchAllScreenState extends State<SearchAllScreen> {
  final _text = TextEditingController();
  final Map<XKind, List<XItem>> _all = {};
  bool _loading = false;
  String _query = '';
  Map<XKind, List<XItem>> _found = {};

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load(XKind kind) async {
    if (_all.containsKey(kind)) return;
    try {
      _all[kind] = await widget.api.items(kind);
    } catch (_) {
      _all[kind] = const [];
    }
  }

  Future<void> _run(String q) async {
    q = q.trim();
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _found = {};
      });
      return;
    }
    setState(() {
      _loading = true;
      _query = q;
    });
    await Future.wait([for (final k in XKind.values) _load(k)]);
    if (!mounted || _query != q) return;
    final words = plainText(q).split(' ').where((w) => w.isNotEmpty).toList();
    final needle = words.join(' ');
    final out = <XKind, List<XItem>>{};
    for (final kind in XKind.values) {
      final starts = <XItem>[];
      final rest = <XItem>[];
      for (final i in _all[kind] ?? const <XItem>[]) {
        if (!Store.allowed(i)) continue;
        final name = plainText(i.name);
        if (name.isEmpty || !words.every(name.contains)) continue;
        (name.startsWith(needle) ? starts : rest).add(i);
        if (starts.length + rest.length >= 60) break;
      }
      out[kind] = [...starts, ...rest];
    }
    setState(() {
      _found = out;
      _loading = false;
    });
  }

  Future<void> _open(XKind kind, List<XItem> list, int index) async {
    final item = list[index];
    Store.addRecent(item);
    final api = widget.api;
    final nav = Navigator.of(context);
    if (kind == XKind.live) {
      await nav.push(MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(api: api, entries: liveEntriesFor(api, list), index: index, live: true)));
    } else if (kind == XKind.series) {
      await nav.push(MaterialPageRoute<void>(builder: (_) => SeriesScreen(api: api, series: item)));
    } else {
      await nav.push(MaterialPageRoute<void>(builder: (_) => MovieScreen(api: api, movie: item)));
    }
  }

  String _title(XKind k) => switch (k) {
        XKind.live => 'Live TV',
        XKind.vod => 'Movies',
        XKind.series => 'Series',
      };

  IconData _icon(XKind k) => switch (k) {
        XKind.live => Icons.live_tv_rounded,
        XKind.vod => Icons.movie_rounded,
        XKind.series => Icons.video_library_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final any = _found.values.any((l) => l.isNotEmpty);
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: Aurora(strength: 0.8)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      TvFocus(
                        radius: 20,
                        color: Colors.transparent,
                        onTap: () => Navigator.of(context).maybePop(),
                        child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.arrow_back_rounded, size: 26)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TvField(
                          controller: _text,
                          label: t('Search'),
                          icon: Icons.search_rounded,
                          autofocus: true,
                          action: TextInputAction.search,
                          onSubmitted: _run,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _loading
                        ? const Loading()
                        : _query.isEmpty
                            ? const Center(
                                child: Text('Type a name and press OK / Search: channels, movies and series are searched together.',
                                    textAlign: TextAlign.center, style: TextStyle(color: C.dim, fontSize: 15)))
                            : !any
                                ? const Center(child: Text('Nothing found.', style: TextStyle(color: C.dim, fontSize: 16)))
                                : ListView(
                                    children: [
                                      for (final kind in XKind.values)
                                        if ((_found[kind] ?? const []).isNotEmpty) ...[
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(4, 14, 0, 8),
                                            child: Text('${_title(kind).toUpperCase()}  ·  ${_found[kind]!.length}',
                                                style: const TextStyle(
                                                    fontSize: 13, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                                          ),
                                          for (var i = 0; i < _found[kind]!.length; i++)
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 6),
                                              child: TvFocus(
                                                radius: 14,
                                                color: const Color(0x80161934),
                                                onTap: () => _open(kind, _found[kind]!, i),
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                  child: Row(
                                                    children: [
                                                      SizedBox(
                                                        width: 40,
                                                        height: 40,
                                                        child: NetImage(_found[kind]![i].icon, fallback: _icon(kind)),
                                                      ),
                                                      const SizedBox(width: 14),
                                                      Expanded(
                                                        child: Text(_found[kind]![i].name,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                                                      ),
                                                      Icon(_icon(kind), size: 18, color: C.dim),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                    ],
                                  ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
