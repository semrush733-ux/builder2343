import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'player.dart';

/// Seasons and episodes of one series.
class SeriesScreen extends StatefulWidget {
  const SeriesScreen({super.key, required this.api, required this.series});

  final XtreamApi api;
  final XItem series;

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  XSeriesInfo? _info;
  String? _error;
  int _season = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _info = null;
      _error = null;
    });
    try {
      final info = await widget.api.seriesInfo(widget.series.id);
      if (!mounted) return;
      setState(() {
        _info = info;
        if (info.seasons.isNotEmpty) _season = info.seasons.keys.first;
      });
      log('series seasons=${info.seasons.length}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _play(List<XEpisode> episodes, int index) async {
    final api = widget.api;
    final entries = [
      for (final e in episodes)
        PlayEntry(
          title: widget.series.name,
          subtitle: 'S${e.season} E${e.number}  ·  ${e.title}',
          urls: [api.episodeUrl(e.id, e.ext)],
          resumeKey: 'ep:${e.id}',
        ),
    ];
    await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PlayerScreen(api: api, entries: entries, index: index, live: false)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final cover = (info != null && info.cover.isNotEmpty) ? info.cover : widget.series.icon;
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 250,
            color: C.panel,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 150,
                    height: 220,
                    color: C.card,
                    child: NetImage(cover, fit: BoxFit.cover, cacheWidth: 300, fallback: Icons.video_library_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.series.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, height: 1.2, fontWeight: FontWeight.w800),
                ),
                if (info != null && info.genre.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(info.genre,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.accent, fontSize: 12.5)),
                ],
                const SizedBox(height: 8),
                if (info != null)
                  Expanded(
                    child: Text(
                      info.plot,
                      overflow: TextOverflow.fade,
                      style: const TextStyle(color: C.dim, fontSize: 13, height: 1.35),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 0), child: _body())),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) return ErrorBox(message: _error!, onRetry: _load, autofocus: true);
    final info = _info;
    if (info == null) return const Loading();
    if (info.seasons.isEmpty) {
      return const Center(child: Text('No episodes available yet.', style: TextStyle(color: C.dim, fontSize: 15)));
    }
    final seasons = info.seasons.keys.toList();
    final episodes = info.seasons[_season] ?? const <XEpisode>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            itemCount: seasons.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final s = seasons[index];
              return TvFocus(
                selected: s == _season,
                radius: 20,
                onTap: () => setState(() => _season = s),
                onFocus: () {
                  if (s != _season) setState(() => _season = s);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: Text(s == 0 ? 'Specials' : 'Season $s',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            key: ValueKey(_season),
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 24),
            itemCount: episodes.length,
            itemExtent: 54,
            itemBuilder: (context, index) {
              final e = episodes[index];
              final started = Store.resume('ep:${e.id}') > 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TvFocus(
                  autofocus: index == 0,
                  onTap: () => _play(episodes, index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text('${e.number}',
                              style: const TextStyle(color: C.accent, fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                        Expanded(
                          child: Text(e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                        ),
                        if (started)
                          const Padding(
                            padding: EdgeInsets.only(left: 10),
                            child: Text('Continue', style: TextStyle(color: C.accent, fontSize: 12.5)),
                          ),
                        if (e.duration.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Text(e.duration, style: const TextStyle(color: C.dim, fontSize: 12.5)),
                          ),
                        const SizedBox(width: 8),
                        const Icon(Icons.play_arrow_rounded, color: C.dim, size: 20),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
