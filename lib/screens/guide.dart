import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'player.dart';

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');
String _clock(DateTime t) => Ui.hm(t);

String _day(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  if (day == today.add(const Duration(days: 1))) return 'Tomorrow';
  return '${_wd[d.weekday - 1]} ${d.day} ${_mo[d.month - 1]}';
}

DateTime _floor30(DateTime t) => DateTime(t.year, t.month, t.day, t.hour, t.minute < 30 ? 0 : 30);

/// What the customer picked in the guide: a channel to watch live, or a past programme
/// to watch from the server's recording (catch-up).
class GuideResult {
  const GuideResult.channel(int this.channel) : archive = null;
  const GuideResult.archive(PlayEntry this.archive) : channel = null;
  final int? channel;
  final PlayEntry? archive;
}

/// TV Guide: channels down the side, programmes along a time line, the details of the
/// selected programme at the top.
///
/// Remote: Up / Down = channel, Left / Right = programme (earlier / later), OK = watch
/// (now: the channel live; past with a recording: catch-up), Back = close.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key, required this.api, required this.entries, required this.index});

  final Source api;
  final List<PlayEntry> entries;
  final int index;

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  static const double _rowH = 62;
  static const double _sideW = 250;
  static const double _perMin = 7.0; // pixels per minute: 30 minutes = 210 px

  final FocusNode _focus = FocusNode(debugLabel: 'guide');
  final ScrollController _scroll = ScrollController();
  final Map<int, List<XEpg>> _epg = {};
  final Set<int> _loading = {};
  final List<int> _queue = [];
  int _running = 0;
  Timer? _loadTimer;
  Timer? _clockTimer;

  late int _row;
  late DateTime _cursor; // the time the selection follows
  late DateTime _viewStart; // left edge of the time line
  double _gridWidth = 900;

  @override
  void initState() {
    super.initState();
    log('screen=guide channels=${widget.entries.length}');
    _row = widget.index.clamp(0, math.max(0, widget.entries.length - 1));
    final now = DateTime.now();
    _cursor = now;
    _viewStart = _floor30(now).subtract(const Duration(minutes: 30));
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToRow(center: true);
      _focus.requestFocus();
    });
    _scheduleLoad();
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    _clockTimer?.cancel();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ loading

  /// Loads the guide of the rows around the selection, a few at a time.
  void _scheduleLoad() {
    _loadTimer?.cancel();
    _loadTimer = Timer(const Duration(milliseconds: 200), () {
      final from = math.max(0, _row - 6);
      final to = math.min(widget.entries.length - 1, _row + 10);
      _queue
        ..clear()
        ..add(_row);
      for (var i = from; i <= to; i++) {
        if (i != _row) _queue.add(i);
      }
      _pump();
    });
  }

  void _pump() {
    while (_running < 4 && _queue.isNotEmpty) {
      final i = _queue.removeAt(0);
      if (_epg.containsKey(i) || _loading.contains(i)) continue;
      final id = widget.entries[i].epgId;
      if (id == null || id.isEmpty) {
        _epg[i] = const [];
        continue;
      }
      _loading.add(i);
      _running++;
      widget.api.fullEpg(id).then((list) {
        _epg[i] = list;
      }).catchError((Object e) {
        log('guide epg failed: ${e.runtimeType}');
        _epg[i] = const [];
      }).whenComplete(() {
        _loading.remove(i);
        _running--;
        if (mounted) {
          setState(() {});
          _pump();
        }
      });
    }
    if (mounted) setState(() {});
  }

  // --------------------------------------------------------------- selection

  List<XEpg> _list(int row) => _epg[row] ?? const [];

  /// The programme under the cursor in a row, or null (no guide / a gap).
  XEpg? _at(int row, DateTime t) {
    for (final e in _list(row)) {
      if (!e.start.isAfter(t) && e.end.isAfter(t)) return e;
    }
    return null;
  }

  XEpg? get _selected => _at(_row, _cursor);

  int get _visibleMinutes => math.max(60, (_gridWidth / _perMin).floor());

  void _keepCursorVisible() {
    final end = _viewStart.add(Duration(minutes: _visibleMinutes));
    if (_cursor.isBefore(_viewStart.add(const Duration(minutes: 5)))) {
      _viewStart = _floor30(_cursor).subtract(const Duration(minutes: 30));
    } else if (_cursor.isAfter(end.subtract(const Duration(minutes: 20)))) {
      _viewStart = _floor30(_cursor).subtract(const Duration(minutes: 30));
    }
  }

  void _moveRow(int step) {
    final count = widget.entries.length;
    if (count == 0) return;
    setState(() => _row = (_row + step + count) % count);
    _jumpToRow();
    _scheduleLoad();
  }

  /// Left / Right: the programme before / after the selected one. Where the guide has nothing,
  /// the cursor walks in half hours (or jumps to the nearest programme in that direction).
  void _moveTime(int step) {
    final list = _list(_row);
    final sel = _selected;
    XEpg? target;
    if (sel != null) {
      final j = list.indexOf(sel) + step;
      if (j >= 0 && j < list.length) target = list[j];
    } else if (step > 0) {
      for (final e in list) {
        if (e.start.isAfter(_cursor)) {
          target = e;
          break;
        }
      }
    } else {
      for (final e in list.reversed) {
        if (!e.end.isAfter(_cursor)) {
          target = e;
          break;
        }
      }
    }
    final t = target;
    setState(() {
      if (t != null && t.start.difference(_cursor).inHours.abs() < 12) {
        _cursor = t.start.add(const Duration(minutes: 1));
      } else {
        _cursor = _cursor.add(Duration(minutes: 30 * step));
      }
      _keepCursorVisible();
    });
  }

  void _jumpNow() {
    setState(() {
      _cursor = DateTime.now();
      _viewStart = _floor30(_cursor).subtract(const Duration(minutes: 30));
    });
  }

  void _jumpToRow({bool center = false}) {
    if (!_scroll.hasClients) return;
    final view = _scroll.position.viewportDimension;
    final top = _row * _rowH;
    final offset = _scroll.offset;
    double? target;
    if (center) {
      target = top - view / 2 + _rowH / 2;
    } else if (top < offset) {
      target = top;
    } else if (top + _rowH > offset + view) {
      target = top + _rowH - view;
    }
    if (target != null) {
      _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
    }
  }

  // ------------------------------------------------------------------ actions

  bool get _canCatchup => widget.api is XtreamApi;

  void _ok() {
    final entry = widget.entries[_row];
    final sel = _selected;
    final now = DateTime.now();
    if (sel == null || (!sel.start.isAfter(now) && sel.end.isAfter(now))) {
      Navigator.of(context).pop(GuideResult.channel(_row));
      return;
    }
    if (!sel.end.isAfter(now)) {
      final item = entry.item;
      if (_canCatchup && item != null && (sel.archive || item.archive)) {
        final api = widget.api as XtreamApi;
        Navigator.of(context).pop(GuideResult.archive(PlayEntry(
          title: sel.title.isEmpty ? entry.title : sel.title,
          subtitle: '${entry.title}  ·  ${_day(sel.start)} ${_clock(sel.start)}',
          urls: api.timeshiftUrls(item.id, sel.start, sel.end),
          logo: entry.logo,
        )));
        return;
      }
      _toast('This programme has no recording on the server.');
      return;
    }
    _toast('Starts ${_day(sel.start)} at ${_clock(sel.start)}.');
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp) {
      _moveRow(-1);
    } else if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown) {
      _moveRow(1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _moveTime(-1);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _moveTime(1);
    } else if (k == LogicalKeyboardKey.pageUp) {
      _moveRow(-8);
    } else if (k == LogicalKeyboardKey.pageDown) {
      _moveRow(8);
    } else if (k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.home) {
      if (event is KeyDownEvent) _jumpNow();
    } else if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.gameButtonA) {
      if (event is KeyDownEvent) _ok();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ----------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _details(),
                const SizedBox(height: 12),
                Expanded(
                  child: LayoutBuilder(builder: (context, box) {
                    _gridWidth = math.max(200, box.maxWidth - _sideW);
                    return Column(
                      children: [
                        _ruler(),
                        Expanded(child: _grid()),
                      ],
                    );
                  }),
                ),
                const SizedBox(height: 6),
                const Text(
                  '↑ ↓ channel     ← → programme     OK watch (past programmes play from the recording)     ⏯ back to now',
                  style: TextStyle(fontSize: 12, color: C.dim),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _details() {
    if (widget.entries.isEmpty) return const SizedBox.shrink();
    final entry = widget.entries[_row];
    final sel = _selected;
    final now = DateTime.now();
    final loading = _loading.contains(_row) || !_epg.containsKey(_row);
    final live = sel != null && !sel.start.isAfter(now) && sel.end.isAfter(now);
    final past = sel != null && !sel.end.isAfter(now);
    final recorded = sel != null && past && _canCatchup && (sel.archive || (entry.item?.archive ?? false));
    final double progress = sel != null && live
        ? (now.difference(sel.start).inSeconds / math.max(1, sel.end.difference(sel.start).inSeconds)).clamp(0.0, 1.0).toDouble()
        : 0.0;
    return Container(
      height: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 118,
              height: 118,
              color: C.card,
              padding: const EdgeInsets.all(10),
              child: NetImage(entry.logo, fit: BoxFit.contain, cacheWidth: 240),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${_row + 1}', style: const TextStyle(fontSize: 14, color: C.accent, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(entry.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: C.dim)),
                    ),
                    Text('${_day(now)}  ${_clock(now)}', style: const TextStyle(fontSize: 14, color: C.dim)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  sel?.title ?? (loading ? 'Loading the guide…' : 'No programme information'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                if (sel != null)
                  Row(
                    children: [
                      Text(
                        '${_day(sel.start)}  ${_clock(sel.start)} – ${_clock(sel.end)}  ·  ${sel.end.difference(sel.start).inMinutes} min',
                        style: const TextStyle(fontSize: 14, color: Color(0xFFD5DAE3)),
                      ),
                      const SizedBox(width: 10),
                      if (live) _badge('LIVE NOW', C.danger),
                      if (recorded) _badge('CATCH UP', const Color(0xFF2ECC71)),
                      if (!live && !past) _badge('COMING UP', const Color(0xFF4AA3FF)),
                      if (live) ...[
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 160,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 5,
                              color: C.accent,
                              backgroundColor: const Color(0x33FFFFFF),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    sel?.description ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, height: 1.35, color: C.dim),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(5)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.6)),
      );

  Widget _ruler() {
    final slots = (_visibleMinutes / 30).ceil() + 1;
    final now = DateTime.now();
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          SizedBox(
            width: _sideW,
            child: Text(_day(_cursor), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: C.accent)),
          ),
          Expanded(
            child: ClipRect(
              child: Stack(
                children: [
                  for (var i = 0; i < slots; i++)
                    Positioned(
                      left: i * 30 * _perMin,
                      top: 4,
                      child: Text(
                        _clock(_viewStart.add(Duration(minutes: 30 * i))),
                        style: const TextStyle(fontSize: 13, color: C.dim, fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (now.isAfter(_viewStart))
                    Positioned(
                      left: now.difference(_viewStart).inSeconds / 60 * _perMin - 4,
                      bottom: 0,
                      child: const Icon(Icons.arrow_drop_down_rounded, color: C.danger, size: 18),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid() {
    final now = DateTime.now();
    final nowX = now.difference(_viewStart).inSeconds / 60 * _perMin;
    return Stack(
      children: [
        ListView.builder(
          controller: _scroll,
          itemExtent: _rowH,
          itemCount: widget.entries.length,
          itemBuilder: (context, i) => _rowView(i),
        ),
        if (nowX > 0 && nowX < _gridWidth)
          Positioned(
            left: _sideW + nowX - 1,
            top: 0,
            bottom: 0,
            child: IgnorePointer(child: Container(width: 2, color: C.danger.withValues(alpha: 0.8))),
          ),
      ],
    );
  }

  Widget _rowView(int i) {
    final entry = widget.entries[i];
    final on = i == _row;
    final list = _list(i);
    final viewEnd = _viewStart.add(Duration(minutes: _visibleMinutes + 30));
    final now = DateTime.now();
    final sel = on ? _selected : null;
    final loaded = _epg.containsKey(i);

    final cells = <Widget>[];
    for (final e in list) {
      if (!e.end.isAfter(_viewStart) || !e.start.isBefore(viewEnd)) continue;
      final from = e.start.isBefore(_viewStart) ? _viewStart : e.start;
      final left = from.difference(_viewStart).inSeconds / 60 * _perMin;
      final width = e.end.difference(from).inSeconds / 60 * _perMin;
      final picked = identical(e, sel);
      final isNow = !e.start.isAfter(now) && e.end.isAfter(now);
      final isPast = !e.end.isAfter(now);
      cells.add(Positioned(
        left: left,
        top: 3,
        bottom: 3,
        width: math.max(4, width - 3),
        child: GestureDetector(
          onTap: () {
            if (picked) {
              _ok();
            } else {
              setState(() {
                _row = i;
                _cursor = e.start.add(const Duration(minutes: 1));
              });
              _scheduleLoad();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: picked
                  ? C.accent
                  : (isNow ? const Color(0xFF262C3A) : (isPast ? const Color(0xFF151922) : C.card)),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isPast && e.archive && _canCatchup)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.history_rounded, size: 13, color: picked ? Colors.black : const Color(0xFF2ECC71)),
                      ),
                    Expanded(
                      child: Text(
                        e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: picked ? Colors.black : (isPast ? C.dim : C.text),
                        ),
                      ),
                    ),
                  ],
                ),
                if (width > 110)
                  Text(
                    '${_clock(e.start)} – ${_clock(e.end)}',
                    maxLines: 1,
                    style: TextStyle(fontSize: 11.5, color: picked ? Colors.black87 : C.dim),
                  ),
              ],
            ),
          ),
        ),
      ));
    }
    if (cells.isEmpty) {
      cells.add(Positioned.fill(
        top: 3,
        bottom: 3,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: on ? C.accent : C.card,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            loaded ? 'No programme information' : 'Loading…',
            style: TextStyle(fontSize: 13.5, color: on ? Colors.black : C.dim, fontWeight: FontWeight.w600),
          ),
        ),
      ));
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (on) {
          _ok();
        } else {
          setState(() => _row = i);
          _scheduleLoad();
        }
      },
      child: Row(
        children: [
          Container(
            width: _sideW - 8,
            height: _rowH - 6,
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: on ? const Color(0xFF2A2F3C) : C.panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: on ? C.accent : Colors.transparent, width: 2),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text('${i + 1}', style: const TextStyle(fontSize: 12.5, color: C.dim, fontWeight: FontWeight.w700)),
                ),
                SizedBox(width: 44, height: 34, child: NetImage(entry.logo, fit: BoxFit.contain, cacheWidth: 120)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w800 : FontWeight.w600)),
                ),
              ],
            ),
          ),
          Expanded(child: ClipRect(child: Stack(children: cells))),
        ],
      ),
    );
  }
}
