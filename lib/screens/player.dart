import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../config.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';

/// One thing the player can show. [urls] are tried in order (live channels
/// have a second stream format as a fallback).
class PlayEntry {
  const PlayEntry({
    required this.title,
    required this.urls,
    this.subtitle = '',
    this.resumeKey,
    this.epgId,
    this.logo = '',
    this.item,
  });

  final String title;
  final String subtitle;
  final List<String> urls;
  final String? resumeKey;
  final String? epgId;
  final String logo;
  final XItem? item;
}

String formatTime(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

String formatClock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Full-screen player.
///
/// Live TV:  Up / Down = next / previous channel, OK = info, hold OK = favourite.
/// Movies:   OK = pause, Left / Right = jump back / forward (hold to jump further).
///
/// Playback runs on the device's own media engine (ExoPlayer on Android) with
/// hardware decoding. A stream that drops is reconnected automatically.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.api,
    required this.entries,
    required this.index,
    required this.live,
  });

  final Source api;
  final List<PlayEntry> entries;
  final int index;
  final bool live;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  static const _device = MethodChannel('b1g/device');
  static const _maxFails = 8;

  final FocusNode _focus = FocusNode(debugLabel: 'player');
  VideoPlayerController? _c;
  late int _index;
  int _generation = 0;
  int _urlIndex = 0;
  int _fails = 0;
  String? _status = 'Loading…';
  bool _dead = false;
  bool _suspended = false;
  bool _userPaused = false;
  bool _overlay = true;
  bool _wasBuffering = false;

  Duration _lastPosition = Duration.zero;
  DateTime _lastProgress = DateTime.now();
  DateTime _openedAt = DateTime.now();
  int _lastSavedSecond = -1;
  int _lastLoggedSecond = -1;

  int? _zapTarget;
  Duration? _seekTarget;
  int _seekPresses = 0;
  bool _okDown = false;
  bool _okLong = false;

  List<XEpg> _epg = const [];

  Timer? _hideTimer;
  Timer? _watchdog;
  Timer? _zapTimer;
  Timer? _seekTimer;
  Timer? _retryTimer;
  Timer? _epgTimer;

  PlayEntry get _entry => widget.entries[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.index < 0 || widget.index >= widget.entries.length ? 0 : widget.index;
    WidgetsBinding.instance.addObserver(this);
    _keepScreenOn(true);
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) => _checkStall());
    _open();
    _scheduleEpg();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    for (final t in [_hideTimer, _watchdog, _zapTimer, _seekTimer, _retryTimer, _epgTimer]) {
      t?.cancel();
    }
    _saveResume();
    final c = _c;
    _c = null;
    c?.removeListener(_onTick);
    c?.dispose();
    _keepScreenOn(false);
    _focus.dispose();
    super.dispose();
  }

  Future<void> _keepScreenOn(bool on) async {
    try {
      await _device.invokeMethod<void>('keepScreenOn', on);
    } catch (_) {}
  }

  // An IPTV account usually allows one connection: release the stream as soon
  // as the app goes to the background and reconnect when it comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (_suspended) return;
      _suspended = true;
      _generation++;
      _retryTimer?.cancel();
      _saveResume();
      final c = _c;
      _c = null;
      c?.removeListener(_onTick);
      c?.dispose();
      log('player suspended');
    } else if (state == AppLifecycleState.resumed && _suspended) {
      _suspended = false;
      _fails = 0;
      _open(startAt: widget.live ? null : _lastPosition);
    }
  }

  // ---------------------------------------------------------------- playback

  Future<void> _open({Duration? startAt}) async {
    final generation = ++_generation;
    _retryTimer?.cancel();
    final old = _c;
    _c = null;
    if (mounted) {
      setState(() {
        _dead = false;
        _status = _fails == 0 ? 'Loading…' : 'Reconnecting…';
      });
    }
    if (old != null) {
      old.removeListener(_onTick);
      try {
        await old.dispose();
      } catch (_) {}
    }
    if (generation != _generation || !mounted) return;

    final entry = _entry;
    final url = entry.urls[_urlIndex % entry.urls.length];
    final format = url.substring(url.lastIndexOf('.') + 1);
    log('open index=$_index format=$format try=$_fails');

    final uri = Uri.tryParse(url);
    if (uri == null) {
      _failed();
      return;
    }
    final c = VideoPlayerController.networkUrl(uri, httpHeaders: const {'User-Agent': kUserAgent});
    try {
      await c.initialize().timeout(const Duration(seconds: 25));
    } catch (e) {
      log('open failed: ${e.runtimeType}');
      try {
        await c.dispose();
      } catch (_) {}
      if (generation != _generation || !mounted) return;
      _failed();
      return;
    }
    if (generation != _generation || !mounted) {
      await c.dispose();
      return;
    }

    var start = startAt ?? Duration.zero;
    if (startAt == null && !widget.live && entry.resumeKey != null) {
      final saved = Store.resume(entry.resumeKey!);
      if (saved > 30) start = Duration(seconds: saved);
    }
    try {
      if (!widget.live && start > Duration.zero && c.value.duration > start + const Duration(seconds: 10)) {
        await c.seekTo(start);
      }
      c.addListener(_onTick);
      await c.play();
    } catch (e) {
      log('start failed: ${e.runtimeType}');
      c.removeListener(_onTick);
      try {
        await c.dispose();
      } catch (_) {}
      if (generation != _generation || !mounted) return;
      _failed();
      return;
    }
    if (generation != _generation || !mounted) {
      c.removeListener(_onTick);
      await c.dispose();
      return;
    }
    _lastPosition = c.value.position;
    _lastProgress = DateTime.now();
    _openedAt = DateTime.now();
    _lastLoggedSecond = -1;
    _userPaused = false;
    final size = c.value.size;
    log('ready index=$_index format=$format video=${size.width.round()}x${size.height.round()}');
    setState(() {
      _c = c;
      _status = null;
    });
    _showOverlay();
  }

  void _onTick() {
    final c = _c;
    if (c == null) return;
    final v = c.value;
    if (v.hasError) {
      log('player error: ${v.errorDescription}');
      _failed();
      return;
    }
    final now = DateTime.now();
    if (v.position != _lastPosition) {
      _lastPosition = v.position;
      _lastProgress = now;
      final second = v.position.inSeconds;
      if (second != _lastLoggedSecond && second % 5 == 0) {
        _lastLoggedSecond = second;
        log('playing index=$_index pos=$second');
      }
      // Playing for a while: this stream works, forget earlier failures.
      if (now.difference(_openedAt) > const Duration(seconds: 8)) {
        _fails = 0;
        if (widget.live) {
          final url = _entry.urls[_urlIndex % _entry.urls.length];
          Store.setLiveFormat(url.endsWith('.m3u8') ? 'm3u8' : 'ts');
        }
      }
      if (!widget.live && (second - _lastSavedSecond).abs() >= 10) {
        _lastSavedSecond = second;
        _saveResume();
      }
    }
    if (v.isCompleted && !_userPaused) {
      _ended();
      return;
    }
    if (_overlay || v.isBuffering != _wasBuffering) {
      _wasBuffering = v.isBuffering;
      if (mounted) setState(() {});
    }
  }

  /// A live stream that "ends" has dropped; a movie that ends is finished.
  void _ended() {
    if (widget.live) {
      log('live stream ended, reconnecting');
      _failed(countsAsFailure: DateTime.now().difference(_openedAt) < const Duration(seconds: 8));
      return;
    }
    final key = _entry.resumeKey;
    if (key != null) Store.setResume(key, 0);
    if (_index < widget.entries.length - 1) {
      _index++;
      _urlIndex = 0;
      _fails = 0;
      _lastPosition = Duration.zero;
      _open();
    } else {
      final c = _c;
      _c = null;
      c?.removeListener(_onTick);
      c?.dispose();
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  void _failed({bool countsAsFailure = true}) {
    final c = _c;
    _c = null;
    c?.removeListener(_onTick);
    c?.dispose();
    _generation++;
    if (!mounted || _suspended) return;
    if (countsAsFailure) {
      _fails++;
      if (_entry.urls.length > 1) _urlIndex++; // try the other stream format
    }
    if (_fails > _maxFails) {
      log('gave up index=$_index');
      setState(() {
        _dead = true;
        _status = widget.live
            ? 'This channel is not available right now.'
            : 'This video cannot be played right now.';
      });
      _showOverlay();
      return;
    }
    final wait = !countsAsFailure || _fails <= 2 ? 1 : (_fails <= 5 ? 3 : 6);
    setState(() => _status = 'Reconnecting…');
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: wait), () {
      if (mounted && !_suspended) _open(startAt: widget.live ? null : _lastPosition);
    });
  }

  /// Picture frozen although it should be playing: reconnect.
  void _checkStall() {
    final c = _c;
    if (c == null || _suspended || _dead || !c.value.isInitialized) return;
    if (_userPaused) {
      _lastProgress = DateTime.now();
      return;
    }
    final frozen = DateTime.now().difference(_lastProgress);
    if (frozen > Duration(seconds: widget.live ? 15 : 40)) {
      log('stalled for ${frozen.inSeconds}s, reconnecting');
      _lastProgress = DateTime.now();
      _failed();
    }
  }

  void _saveResume() {
    if (widget.live) return;
    final key = _entry.resumeKey;
    if (key == null) return;
    final c = _c;
    final position = c != null ? c.value.position : _lastPosition;
    final duration = c != null ? c.value.duration : Duration.zero;
    if (duration.inSeconds > 60 && position.inSeconds > duration.inSeconds * 0.95) {
      Store.setResume(key, 0);
    } else if (position.inSeconds > 0) {
      Store.setResume(key, position.inSeconds);
    }
  }

  // ---------------------------------------------------------------- controls

  void _showOverlay() {
    _hideTimer?.cancel();
    if (!_overlay && mounted) setState(() => _overlay = true);
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _dead || _userPaused || _zapTarget != null || _seekTarget != null) return;
      setState(() => _overlay = false);
    });
  }

  void _toggleOverlay() {
    if (_overlay && !_dead) {
      _hideTimer?.cancel();
      setState(() => _overlay = false);
    } else {
      _showOverlay();
    }
  }

  void _zap(int step) {
    final count = widget.entries.length;
    if (count < 2) {
      _showOverlay();
      return;
    }
    final target = ((_zapTarget ?? _index) + step) % count;
    setState(() => _zapTarget = target < 0 ? target + count : target);
    _showOverlay();
    // Open only after the remote has been still for a moment, so skimming
    // through channels does not start a stream for every key press.
    _zapTimer?.cancel();
    _zapTimer = Timer(const Duration(milliseconds: 450), () {
      final next = _zapTarget;
      if (!mounted || next == null) return;
      _saveResume();
      setState(() {
        _index = next;
        _zapTarget = null;
        _urlIndex = 0;
        _fails = 0;
        _epg = const [];
        _lastPosition = Duration.zero;
      });
      _open();
      _scheduleEpg();
      _showOverlay();
    });
  }

  void _togglePause() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      _userPaused = true;
      c.pause();
    } else {
      _userPaused = false;
      _lastProgress = DateTime.now();
      c.play();
    }
    setState(() {});
    _showOverlay();
  }

  void _seek(int direction) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    final duration = c.value.duration;
    if (duration <= Duration.zero) return;
    _seekPresses++;
    final step = _seekPresses > 16 ? 60 : (_seekPresses > 6 ? 30 : 10);
    var target = (_seekTarget ?? c.value.position) + Duration(seconds: step * direction);
    if (target < Duration.zero) target = Duration.zero;
    final end = duration - const Duration(seconds: 3);
    if (target > end) target = end;
    setState(() => _seekTarget = target);
    _showOverlay();
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 400), () async {
      final to = _seekTarget;
      final now = _c;
      if (to == null || now == null || !mounted) return;
      _lastProgress = DateTime.now();
      try {
        await now.seekTo(to);
      } catch (_) {}
      if (!mounted) return;
      setState(() => _seekTarget = null);
      _showOverlay();
    });
  }

  void _toggleFavourite() {
    final item = _entry.item;
    if (item == null) return;
    final added = Store.toggleFavourite(item);
    log('favourite ${added ? 'added' : 'removed'}');
    setState(() {});
    _showOverlay();
  }

  void _retryNow() {
    _fails = 0;
    _urlIndex = 0;
    _open(startAt: widget.live ? null : _lastPosition);
  }

  bool _isOk(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final k = event.logicalKey;

    // OK: short press = info / pause, long press = favourite (live).
    if (_isOk(k)) {
      if (event is KeyDownEvent) {
        _okDown = true;
        _okLong = false;
      } else if (event is KeyRepeatEvent) {
        if (_okDown && !_okLong && widget.live && !_dead) {
          _okLong = true;
          _toggleFavourite();
        }
      } else if (event is KeyUpEvent) {
        final tap = _okDown && !_okLong;
        _okDown = false;
        _okLong = false;
        if (tap) {
          if (_dead) {
            _retryNow();
          } else if (widget.live) {
            _toggleOverlay();
          } else {
            _togglePause();
          }
        }
      }
      return KeyEventResult.handled;
    }

    if (event is KeyUpEvent) {
      if (k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight ||
          k == LogicalKeyboardKey.mediaRewind ||
          k == LogicalKeyboardKey.mediaFastForward) {
        _seekPresses = 0;
      }
      return KeyEventResult.ignored;
    }

    if (k == LogicalKeyboardKey.contextMenu) {
      if (event is KeyDownEvent) _toggleFavourite();
      return KeyEventResult.handled;
    }

    if (widget.live) {
      if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp) {
        _zap(1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown) {
        _zap(-1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) {
        _showOverlay();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.mediaPlayPause) {
        if (event is KeyDownEvent) _toggleOverlay();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      _seek(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      _seek(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      _showOverlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) _togglePause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlay) {
      if (event is KeyDownEvent && _userPaused) _togglePause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPause) {
      if (event is KeyDownEvent && !_userPaused) _togglePause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaTrackNext && widget.entries.length > 1) {
      if (event is KeyDownEvent) _zap(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaTrackPrevious && widget.entries.length > 1) {
      if (event is KeyDownEvent) _zap(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --------------------------------------------------------------------- EPG

  void _scheduleEpg() {
    _epgTimer?.cancel();
    final id = _entry.epgId;
    if (!widget.live || id == null) return;
    final index = _index;
    _epgTimer = Timer(const Duration(milliseconds: 1500), () async {
      try {
        final list = await widget.api.shortEpg(id);
        if (!mounted || index != _index) return;
        setState(() => _epg = list);
      } catch (_) {}
    });
  }

  // ---------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final ready = c != null && c.value.isInitialized;
    final buffering = c != null && c.value.isInitialized && c.value.isBuffering && !_userPaused;
    final shown = widget.entries[_zapTarget ?? _index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_dead) {
              _retryNow();
            } else if (widget.live) {
              _toggleOverlay();
            } else {
              _togglePause();
            }
          },
          onLongPress: widget.live ? _toggleFavourite : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (c != null && ready) _video(c) else const SizedBox.expand(),
              if (_status != null || buffering)
                Center(
                  child: _dead
                      ? _DeadMessage(text: _status ?? '')
                      : Loading(label: _status),
                ),
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _overlay ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: _overlayLayer(shown, c, ready),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _video(VideoPlayerController c) {
    final ratio = c.value.aspectRatio;
    return Center(
      child: AspectRatio(
        aspectRatio: ratio.isFinite && ratio > 0.2 ? ratio : 16 / 9,
        child: VideoPlayer(c),
      ),
    );
  }

  Widget _overlayLayer(PlayEntry shown, VideoPlayerController? c, bool ready) {
    final item = shown.item;
    final favourite = item != null && Store.isFavourite(item);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(34, 22, 34, 46),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xD9000000), Colors.transparent],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.live) ...[
                Container(
                  width: 52,
                  height: 52,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(8)),
                  child: NetImage(shown.logo, cacheWidth: 120),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.live ? '${(_zapTarget ?? _index) + 1}   ${shown.title}' : shown.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (favourite) ...[
                          const SizedBox(width: 10),
                          const Icon(Icons.star_rounded, color: C.accent, size: 20),
                        ],
                      ],
                    ),
                    if (shown.subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(shown.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14.5, color: Color(0xFFD5DAE3))),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(formatClock(DateTime.now()), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.fromLTRB(34, 50, 34, 24),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xE6000000)],
            ),
          ),
          child: widget.live ? _liveBar() : _movieBar(c, ready),
        ),
      ],
    );
  }

  Widget _liveBar() {
    final now = DateTime.now();
    XEpg? current;
    XEpg? next;
    if (_zapTarget == null) {
      for (final e in _epg) {
        if (!e.start.isAfter(now) && e.end.isAfter(now)) {
          current = e;
        } else if (e.start.isAfter(now) && next == null) {
          next = e;
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (current != null) ...[
          Text('${formatClock(current.start)} – ${formatClock(current.end)}   ${current.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: (now.difference(current.start).inSeconds /
                      (current.end.difference(current.start).inSeconds.clamp(1, 1 << 30)))
                  .clamp(0.0, 1.0)
                  .toDouble(),
              color: C.accent,
              backgroundColor: const Color(0x44FFFFFF),
            ),
          ),
          const SizedBox(height: 7),
        ],
        if (next != null)
          Text('Next  ${formatClock(next.start)}   ${next.title}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Color(0xFFD5DAE3))),
        const SizedBox(height: 8),
        const Text('Up / Down  Change channel      OK  Info      Hold OK  Favourite      Back  Channel list',
            style: TextStyle(fontSize: 12.5, color: C.dim)),
      ],
    );
  }

  Widget _movieBar(VideoPlayerController? c, bool ready) {
    final duration = ready ? c!.value.duration : Duration.zero;
    final position = _seekTarget ?? (ready ? c!.value.position : _lastPosition);
    final double value =
        duration.inMilliseconds > 0 ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble() : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(_userPaused ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 26, color: C.accent),
            const SizedBox(width: 10),
            Text(formatTime(position), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: value,
                  color: C.accent,
                  backgroundColor: const Color(0x44FFFFFF),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(formatTime(duration), style: const TextStyle(fontSize: 15, color: Color(0xFFD5DAE3))),
          ],
        ),
        const SizedBox(height: 10),
        const Text('OK  Pause / Play      Left / Right  Jump 10 s (hold to jump further)      Back  Exit',
            style: TextStyle(fontSize: 12.5, color: C.dim)),
      ],
    );
  }
}

class _DeadMessage extends StatelessWidget {
  const _DeadMessage({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
      decoration: BoxDecoration(color: const Color(0xCC11141B), borderRadius: BorderRadius.circular(14)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: C.dim, size: 32),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Press OK to try again', style: TextStyle(fontSize: 13.5, color: C.dim)),
        ],
      ),
    );
  }
}
