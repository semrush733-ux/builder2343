import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'player.dart';

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return '${_wd[d.weekday - 1]} ${d.day} ${_mo[d.month - 1]}';
}

/// Catch Up: channels whose server keeps a recording, and the past
/// programmes of the selected channel. Picking a programme plays it
/// like a movie (seekable), through the server's timeshift address.
class CatchupScreen extends StatefulWidget {
  const CatchupScreen({super.key, required this.api});
  final XtreamApi api;

  @override
  State<CatchupScreen> createState() => _CatchupScreenState();
}

class _CatchupScreenState extends State<CatchupScreen> {
  List<XItem> _channels = const [];
  XItem? _channel;
  List<XEpg> _programs = const [];
  bool _loadingChannels = true;
  bool _loadingPrograms = false;
  String _error = '';
  int _epgGeneration = 0;

  @override
  void initState() {
    super.initState();
    log('screen=catchup');
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    try {
      final items = await widget.api.items(XKind.live);
      if (!mounted) return;
      setState(() {
        _channels = items.where((i) => i.archive).toList();
        _loadingChannels = false;
      });
      if (_channels.isNotEmpty) _select(_channels.first);
    } catch (e) {
      log('catchup channels failed: ${e.runtimeType}');
      if (!mounted) return;
      setState(() {
        _loadingChannels = false;
        _error = 'The channel list could not be loaded. Please check the internet and try again.';
      });
    }
  }

  Timer? _debounce;

  /// Selecting with the remote fires on every row the focus passes over,
  /// so the programme list is fetched only once the focus settles.
  void _select(XItem channel) {
    if (_channel?.id == channel.id) return;
    final generation = ++_epgGeneration;
    setState(() {
      _channel = channel;
      _programs = const [];
      _loadingPrograms = true;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _fetch(channel, generation));
  }

  Future<void> _fetch(XItem channel, int generation) async {
    try {
      final programs = await widget.api.catchup(channel.id);
      if (!mounted || generation != _epgGeneration) return;
      setState(() {
        _programs = programs;
        _loadingPrograms = false;
      });
    } catch (e) {
      log('catchup epg failed: ${e.runtimeType}');
      if (!mounted || generation != _epgGeneration) return;
      setState(() => _loadingPrograms = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _play(XEpg p) {
    final channel = _channel;
    if (channel == null) return;
    final urls = widget.api.timeshiftUrls(channel.id, p.start, p.end);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        api: widget.api,
        entries: [
          PlayEntry(
            title: p.title.isEmpty ? channel.name : p.title,
            subtitle: '${channel.name}  ·  ${_dayLabel(p.start)} ${_two(p.start.hour)}:${_two(p.start.minute)}',
            urls: urls,
            logo: channel.icon,
          ),
        ],
        index: 0,
        live: false,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.history_rounded, color: C.accent, size: 26),
                  const SizedBox(width: 10),
                  const Text('Catch Up', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('${_channels.length} channels', style: const TextStyle(fontSize: 13, color: C.dim)),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loadingChannels) {
      return const Center(child: CircularProgressIndicator(color: C.accent));
    }
    if (_error.isNotEmpty) {
      return Center(child: Text(_error, style: const TextStyle(color: C.dim, fontSize: 15)));
    }
    if (_channels.isEmpty) {
      return const Center(
        child: Text(
          'This account has no catch-up channels.\nThe provider decides which channels keep a recording.',
          textAlign: TextAlign.center,
          style: TextStyle(color: C.dim, fontSize: 15, height: 1.5),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 340,
          child: ListView.builder(
            itemCount: _channels.length,
            itemBuilder: (context, i) {
              final c = _channels[i];
              final on = c.id == _channel?.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6, right: 14),
                child: TvFocus(
                  autofocus: i == 0,
                  color: on ? C.card : C.panel,
                  onFocus: () => _select(c),
                  onTap: () => _select(c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(
                      children: [
                        const Icon(Icons.live_tv_rounded, size: 17, color: C.dim),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                              color: on ? C.accent : C.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _programList()),
      ],
    );
  }

  Widget _programList() {
    if (_loadingPrograms) {
      return const Center(child: CircularProgressIndicator(color: C.accent));
    }
    if (_programs.isEmpty) {
      return const Center(
        child: Text('No recorded programmes for this channel yet.',
            style: TextStyle(color: C.dim, fontSize: 14.5)),
      );
    }
    final rows = <Widget>[];
    String lastDay = '';
    for (final p in _programs) {
      final day = _dayLabel(p.start);
      if (day != lastDay) {
        lastDay = day;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 0, 8),
          child: Text(day.toUpperCase(),
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: C.dim)),
        ));
      }
      final mins = p.end.difference(p.start).inMinutes;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: TvFocus(
          color: C.panel,
          onTap: () => _play(p),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text('${_two(p.start.hour)}:${_two(p.start.minute)}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: C.accent)),
                ),
                Expanded(
                  child: Text(
                    p.title.isEmpty ? 'Programme' : p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$mins min', style: const TextStyle(fontSize: 12.5, color: C.dim)),
                const SizedBox(width: 8),
                const Icon(Icons.play_arrow_rounded, size: 18, color: C.dim),
              ],
            ),
          ),
        ),
      ));
    }
    return ListView(padding: const EdgeInsets.only(right: 4), children: rows);
  }
}
