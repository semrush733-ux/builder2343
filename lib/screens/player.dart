import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../config.dart';
import '../input_mode.dart';
import '../lang.dart';
import '../quality.dart';
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

/// "ts", "m3u8", "mp4"... or "stream" when the address has no file ending.
String formatOfUrl(String url) {
  var path = url;
  final q = path.indexOf('?');
  if (q >= 0) path = path.substring(0, q);
  final slash = path.lastIndexOf('/');
  final dot = path.lastIndexOf('.');
  return dot > slash ? path.substring(dot + 1).toLowerCase() : 'stream';
}

const _fits = [BoxFit.contain, BoxFit.cover, BoxFit.fill];
const _fitNames = ['Fit', 'Fill', 'Stretch'];
const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
const _videoModes = ['gpu', 'direct'];
const _videoModeNames = ['Standard', 'Direct'];

/// Full-screen player.
///
/// Remote:  Live TV - Up / Down = channel, OK = info, Left = channel list, Right / Menu = audio and
///          subtitles, hold OK = favourite.  Movies - OK = pause, Left / Right = jump, Down / Menu =
///          audio, subtitles and speed.
/// Touch:   tap = show controls; back, play / pause, 10 s back / forward, drag the bar, buttons for
///          channels, audio and subtitles, speed and picture size.
///
/// Playback runs on libmpv (the engine behind mpv-style players), which copes with the MPEG-TS and
/// HLS streams IPTV servers send and with every common audio format. A stream that drops is
/// reconnected automatically.
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

  /// The automatic change of picture mode is tried once per app start, never back and forth.
  static bool _autoDirectTried = false;

  // A fresh engine is created for every stream that is opened and the old one is closed first:
  // an IPTV account usually allows a single connection, and a clean start is the most reliable.
  Player? _player;
  VideoController? _video;
  Future<void>? _closing;
  final List<StreamSubscription<dynamic>> _subs = [];
  Duration _wantStart = Duration.zero;
  bool _direct = false; // picture mode of the engine that is open now
  bool _pictureFailed = false;
  final FocusNode _focus = FocusNode(debugLabel: 'player');
  final FocusNode _mainButton = FocusNode(debugLabel: 'player-main-button');
  String _buttonLabel = '';
  String _videoSize = '';

  late int _index;
  int _generation = 0;
  int _urlIndex = 0;
  int _fails = 0;
  String? _status = 'Loading…';
  String _lastError = '';
  bool _dead = false;
  bool _suspended = false;
  bool _accepting = false; // false while switching streams: late events of the old one are ignored
  bool _ready = false;
  bool _playedThisUrl = false;
  bool _userPaused = false;
  bool _buffering = false;
  bool _overlay = true;
  bool _scrubbing = false;
  bool _panelOpen = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _firstPosition;
  Duration _lastPosition = Duration.zero; // last known good position, for resume / reconnect
  DateTime _lastProgress = DateTime.now();
  DateTime _openedAt = DateTime.now();
  DateTime? _errorAt;
  DateTime _errorLoggedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastSavedSecond = -1;
  int _lastLoggedSecond = -1;
  int _shownSecond = -1;

  int? _zapTarget;
  Duration? _seekTarget;
  int _seekPresses = 0;
  bool _okDown = false;
  bool _okLong = false;

  List<AudioTrack> _audioTracks = const [];
  List<SubtitleTrack> _subtitleTracks = const [];
  List<VideoTrack> _videoTracks = const [];
  String _videoId = 'auto';
  int _videoHeight = 0;
  String _audioId = '';
  String _subtitleId = 'no';
  bool _tracksApplied = false;
  int _fit = 0;
  double _speed = 1.0;

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
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) => _checkHealth());
    _open();
    _scheduleEpg();
  }

  Player _createPlayer() {
    final player = Player(
      configuration: PlayerConfiguration(
        title: 'B1G',
        bufferSize: 48 * 1024 * 1024,
        logLevel: kVerbose ? MPVLogLevel.info : MPVLogLevel.error,
      ),
    );
    _player = player;
    _direct = Store.videoMode == 'direct';
    _pictureFailed = false;
    _video = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        vo: _direct ? 'mediacodec_embed' : null,
        hwdec: _direct ? 'mediacodec' : null,
      ),
    );
    _subs.add(player.stream.position.listen(_onPosition));
    _subs.add(player.stream.duration.listen((d) {
      if (_accepting) _duration = d;
    }));
    _subs.add(player.stream.buffering.listen((b) {
      if (b == _buffering) return;
      _buffering = b;
      if (mounted) setState(() {});
    }));
    _subs.add(player.stream.completed.listen((done) {
      if (done) _onCompleted();
    }));
    _subs.add(player.stream.error.listen((message) {
      final text = message.trim();
      if (text.isNotEmpty) _noteError(text, true);
    }));
    _subs.add(player.stream.tracks.listen((tracks) {
      if (_accepting) _readTracks(tracks);
    }));
    _subs.add(player.stream.log.listen((line) {
      final text = line.text.trim();
      if (text.isNotEmpty) _noteError('${line.prefix}: $text', line.level == 'error' || line.level == 'fatal');
    }));
    return player;
  }

  /// Closes the engine (and with it the connection to the server). Waits for a
  /// close that is still running, so two streams are never open at once.
  Future<void> _closePlayer() async {
    final player = _player;
    if (player != null) {
      _player = null;
      _video = null;
      for (final s in _subs) {
        s.cancel();
      }
      _subs.clear();
      final previous = _closing;
      final mine = player.dispose().catchError((Object _) {});
      // Keep waiting for an earlier close too, so two streams are never open at once.
      _closing = previous == null ? mine : Future.wait<void>([previous, mine]).then((_) {});
    }
    final closing = _closing;
    if (closing != null) {
      // Never wait for ever: a stuck engine must not block the next stream.
      await closing.timeout(const Duration(seconds: 4), onTimeout: () {
        log('engine close timed out');
      });
    }
  }

  /// Engine settings chosen for IPTV: reconnect inside the network layer, a
  /// few seconds of buffer, and only a short pause when the buffer runs dry.
  Future<void> _configure(Player player) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    final NativePlayer mpv = platform;
    Future<void> set(String name, String value) async {
      try {
        await mpv.setProperty(name, value);
      } catch (_) {}
    }

    await Future.wait([
      set('user-agent', kUserAgent),
      set('network-timeout', '20'),
      set('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=4'),
      set('cache', 'yes'),
      // Start showing as soon as there is a picture instead of filling a buffer first...
      set('cache-pause-initial', 'no'),
      // ...and after a hiccup wait for only one second of video before carrying on.
      set('cache-pause-wait', widget.live ? '1' : '2'),
      set('demuxer-readahead-secs', widget.live ? '10' : '30'),
      // Live: look at one second of the stream to learn what is in it (the default is up to five).
      if (widget.live) set('demuxer-lavf-analyzeduration', '1'),
      // Movies: jump to the nearest key picture, which is immediate on a network stream.
      if (!widget.live) set('hr-seek', 'no'),
      set('audio-channels', 'stereo'),
      set('sub-auto', 'no'),
      // Let the TV's own video chip decode every format it knows (older films are often MPEG-2,
      // MPEG-4 / DivX or VC-1, which the engine would otherwise decode on the slow processor).
      set('hwdec-codecs', 'all'),
      // When a film still has to be decoded on the processor: use every core, take the quick
      // paths, and drop a frame rather than let the picture fall behind the sound.
      set('vd-lavc-threads', '0'),
      set('vd-lavc-fast', 'yes'),
      set('vd-lavc-skiploopfilter', 'nonkey'),
      set('framedrop', 'decoder+vo'),
      // Light picture processing: TV chips are far weaker than a computer's graphics card.
      set('scale', 'bilinear'),
      set('dscale', 'bilinear'),
      set('cscale', 'bilinear'),
      set('dither', 'no'),
      set('deband', 'no'),
      set('correct-downscaling', 'no'),
      set('linear-downscaling', 'no'),
      set('sigmoid-upscaling', 'no'),
      set('hdr-compute-peak', 'no'),
      set('interpolation', 'no'),
      if (_direct) set('hwdec', 'mediacodec'),
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _accepting = false;
    for (final t in [_hideTimer, _watchdog, _zapTimer, _seekTimer, _retryTimer, _epgTimer]) {
      t?.cancel();
    }
    _saveResume();
    _closePlayer();
    log('player closed');
    _keepScreenOn(false);
    _mainButton.dispose();
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
      _accepting = false;
      _generation++;
      _retryTimer?.cancel();
      _saveResume();
      _closePlayer();
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
    _accepting = false;
    final entry = _entry;
    final url = entry.urls[_urlIndex % entry.urls.length];
    final format = formatOfUrl(url);

    var start = startAt ?? Duration.zero;
    if (startAt == null && !widget.live && entry.resumeKey != null) {
      final saved = Store.resume(entry.resumeKey!);
      if (saved > 30) start = Duration(seconds: saved);
    }
    if (widget.live) start = Duration.zero;

    _ready = false;
    _buffering = false;
    _errorAt = null;
    _firstPosition = null;
    _position = start;
    _duration = Duration.zero;
    _seekTarget = null;
    _tracksApplied = false;
    _audioTracks = const [];
    _subtitleTracks = const [];
    _videoTracks = const [];
    _videoId = 'auto';
    _videoHeight = 0;
    _audioId = '';
    _subtitleId = 'no';
    _lastLoggedSecond = -1;
    if (mounted) {
      setState(() {
        _dead = false;
        _status = _fails == 0 ? 'Loading…' : 'Reconnecting…';
      });
    }
    _wantStart = start;
    log('open index=$_index format=$format try=$_fails');
    try {
      // The old engine is closed completely before the new one starts: most accounts allow a
      // single connection, and one engine at a time is what has proved reliable on TV boxes.
      await _closePlayer();
      if (generation != _generation || !mounted) return;
      final player = _createPlayer();
      setState(() {}); // show the new engine's picture surface
      await _configure(player);
      if (generation != _generation || !mounted) return;
      await player.open(
        Media(url, httpHeaders: const {'User-Agent': kUserAgent}, start: start > Duration.zero ? start : null),
        play: true,
      );
      if (_speed != 1.0) await player.setRate(_speed);
    } catch (e) {
      log('open failed: ${e.runtimeType}');
      if (generation != _generation || !mounted) return;
      _openedAt = DateTime.now();
      _failed();
      return;
    }
    if (generation != _generation || !mounted) return;
    _openedAt = DateTime.now();
    _lastProgress = DateTime.now();
    _userPaused = false;
    _accepting = true;
  }

  void _onPosition(Duration p) {
    if (!_accepting) return;
    final first = _firstPosition ??= p;
    if (p != _position) _lastProgress = DateTime.now();
    _position = p;
    if (!_ready) {
      // "Ready" = the picture is really moving, not just "the address opened".
      if ((p - first).inMilliseconds.abs() < 120) return;
      _markReady();
    }
    _lastPosition = p;
    final now = DateTime.now();
    // Live streams count from an arbitrary clock; log the time since tuning in.
    final second = widget.live ? (p - first).inSeconds : p.inSeconds;
    if (second != _lastLoggedSecond && second % 5 == 0) {
      _lastLoggedSecond = second;
      log('playing index=$_index pos=$second');
    }
    if (now.difference(_openedAt) > const Duration(seconds: 8)) {
      // Playing for a while: this stream works, forget earlier failures.
      _fails = 0;
      if (widget.live) {
        final url = _entry.urls[_urlIndex % _entry.urls.length];
        Store.setLiveFormat(formatOfUrl(url) == 'm3u8' ? 'm3u8' : 'ts');
      }
    }
    if (!widget.live && (second - _lastSavedSecond).abs() >= 10) {
      _lastSavedSecond = second;
      _saveResume();
    }
    if (_overlay && second != _shownSecond && mounted) {
      _shownSecond = second;
      setState(() {});
    }
  }

  void _markReady() {
    _ready = true;
    _playedThisUrl = true;
    final player = _player;
    if (player == null) return;
    if (_duration <= Duration.zero) _duration = player.state.duration;
    _readTracks(player.state.tracks);
    // Resume: if the engine did not start at the saved place, jump there now.
    if (!widget.live && _wantStart > Duration.zero && _position < _wantStart - const Duration(seconds: 5)) {
      log('resume by seeking to ${_wantStart.inSeconds}');
      player.seek(_wantStart);
    }
    final url = _entry.urls[_urlIndex % _entry.urls.length];
    final w = player.state.width ?? 0;
    final h = player.state.height ?? 0;
    _videoSize = w > 0 && h > 0 ? '$w x $h' : '';
    _videoHeight = h;
    log('ready index=$_index format=${formatOfUrl(url)} video=${w}x$h mode=${_direct ? 'direct' : 'gpu'}');
    _applyPreferredTracks();
    if (mounted) setState(() => _status = null);
    _showOverlay();
  }

  static final _address = RegExp(r'[a-z]+://\S+');
  static final _pictureError = RegExp(r'video_out|VO window|suitable GPU context', caseSensitive: false);
  static final _fatal = RegExp(
      r'failed to open|loading failed|failed to recognize|unrecognized file format|http error|server returned|'
      r'connection refused|connection timed out|could not resolve|failed to resolve|no route to host|invalid data found',
      caseSensitive: false);

  /// The engine also reports harmless hiccups (a damaged frame at the start
  /// of a live stream, for example), so a message alone never stops playback.
  /// Only a message that means "cannot open", followed by no picture, counts
  /// as a failure - see [_checkHealth].
  void _noteError(String raw, bool isError) {
    // Stream addresses contain the username and password: never show or log them.
    final text = raw.replaceAll(_address, '[address]');
    final short = text.length > 160 ? text.substring(0, 160) : text;
    if (!isError) {
      if (kVerbose) log('mpv: $short');
      return;
    }
    _lastError = text;
    final now = DateTime.now();
    if (kVerbose || now.difference(_errorLoggedAt) > const Duration(seconds: 1)) {
      _errorLoggedAt = now;
      log('engine: $short');
    }
    if (_pictureError.hasMatch(text)) _pictureFailed = true;
    if (_accepting && !_ready && _fatal.hasMatch(text)) _errorAt ??= DateTime.now();
  }

  /// A live stream that "ends" has dropped; a movie that ends is finished.
  void _onCompleted() {
    if (!_accepting) return;
    if (widget.live || !_ready) {
      log('stream ended, reconnecting');
      _failed(countsAsFailure: !_ready || DateTime.now().difference(_openedAt) < const Duration(seconds: 8));
      return;
    }
    final key = _entry.resumeKey;
    if (key != null) Store.setResume(key, 0);
    _lastPosition = Duration.zero;
    if (_index < widget.entries.length - 1) {
      _index++;
      _urlIndex = 0;
      _fails = 0;
      _playedThisUrl = false;
      _open();
    } else {
      _accepting = false;
      _close();
    }
  }

  void _failed({bool countsAsFailure = true}) {
    _accepting = false;
    _generation++;
    _closePlayer(); // frees the connection before the next attempt
    if (!mounted || _suspended) return;
    if (countsAsFailure) {
      _fails++;
      // A format that never played is swapped for the other one at once; a
      // stream that did play and then dropped gets a second chance first.
      if (_entry.urls.length > 1 && (!_playedThisUrl || _fails % 2 == 0)) {
        _urlIndex++;
        _playedThisUrl = false;
      }
    }
    if (_fails > _maxFails) {
      log('gave up index=$_index');
      if (!_focus.hasPrimaryFocus) _focus.requestFocus();
      setState(() {
        _dead = true;
        _status = widget.live ? 'This channel is not available right now.' : 'This video cannot be played right now.';
      });
      _showOverlay();
      return;
    }
    // Give the server a moment to notice the old connection is gone.
    final wait = !countsAsFailure || _fails <= 2 ? 2 : (_fails <= 5 ? 3 : 6);
    setState(() => _status = 'Reconnecting…');
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: wait), () {
      if (mounted && !_suspended) _open(startAt: widget.live ? null : _lastPosition);
    });
  }

  /// Runs every two seconds: nothing on screen for too long means reconnect.
  void _checkHealth() {
    if (!_accepting || _suspended || _dead) return;
    final now = DateTime.now();
    if (!_ready) {
      final waited = now.difference(_openedAt);
      final errorAt = _errorAt;
      final refused = errorAt != null && now.difference(errorAt) > const Duration(milliseconds: 2500);
      // The engine stopped by itself (nothing loading, not paused by the user).
      final player = _player;
      final idle = player != null &&
          waited > const Duration(seconds: 6) &&
          !player.state.playing &&
          !player.state.buffering;
      if (refused || idle || waited > const Duration(seconds: 25)) {
        log(refused ? 'open failed' : (idle ? 'open stopped' : 'open timed out'));
        if (!refused && !idle && _direct) {
          // The direct picture mode hung on this device: go back to the standard one.
          log('direct mode did not start, back to standard mode');
          Store.setVideoMode('gpu');
        }
        _failed();
      }
      return;
    }
    if (_userPaused || _scrubbing) {
      _lastProgress = now;
      return;
    }
    // Sound but no picture: the standard picture mode could not start on this device.
    // Switch to the direct mode once (remembered for next time) and reopen.
    if (_pictureFailed &&
        !_direct &&
        !kNoAutoDirect &&
        !_autoDirectTried &&
        now.difference(_openedAt) > const Duration(seconds: 3)) {
      _autoDirectTried = true;
      log('picture failed in standard mode, switching to direct mode');
      Store.setVideoMode('direct');
      _reopenHere();
      return;
    }
    final frozen = now.difference(_lastProgress);
    if (frozen > Duration(seconds: widget.live ? 14 : 40)) {
      log('stalled for ${frozen.inSeconds}s, reconnecting');
      _lastProgress = now;
      _failed();
    }
  }

  void _saveResume() {
    if (widget.live) return;
    final key = _entry.resumeKey;
    if (key == null || !_ready) return;
    final position = _lastPosition;
    if (_duration.inSeconds > 60 && position.inSeconds > _duration.inSeconds * 0.95) {
      Store.setResume(key, 0);
    } else if (position.inSeconds > 0) {
      Store.setResume(key, position.inSeconds);
    }
  }

  // ------------------------------------------------------- audio / subtitles

  void _readTracks(Tracks tracks) {
    bool real(String id) => id != 'auto' && id != 'no';
    final audio = tracks.audio.where((t) => real(t.id)).toList();
    final subtitle = tracks.subtitle.where((t) => real(t.id)).toList();
    _videoTracks = tracks.video.where((t) => real(t.id)).toList();
    if (audio.length == _audioTracks.length && subtitle.length == _subtitleTracks.length) return;
    _audioTracks = audio;
    _subtitleTracks = subtitle;
    log('tracks audio=${audio.length} subtitles=${subtitle.length}');
    if (_ready) _applyPreferredTracks();
    if (mounted && _panelOpen) setState(() {});
  }

  /// The language chosen last time is chosen again when the stream has it.
  void _applyPreferredTracks() {
    if (_tracksApplied) return;
    if (_audioTracks.isEmpty && _subtitleTracks.isEmpty) return;
    _tracksApplied = true;
    final wantAudio = Store.audioLanguage;
    if (_audioTracks.isNotEmpty) {
      _audioId = _audioTracks.first.id;
      if (wantAudio.isNotEmpty) {
        for (final t in _audioTracks) {
          if ((t.language ?? '') == wantAudio) {
            if (t.id != _audioId) _player?.setAudioTrack(t);
            _audioId = t.id;
            break;
          }
        }
      }
    }
    final wantSubtitle = Store.subtitleLanguage;
    SubtitleTrack? chosen;
    if (wantSubtitle.isNotEmpty) {
      for (final t in _subtitleTracks) {
        if ((t.language ?? '') == wantSubtitle) {
          chosen = t;
          break;
        }
      }
    }
    _subtitleId = chosen?.id ?? 'no';
    _player?.setSubtitleTrack(chosen ?? SubtitleTrack.no());
  }

  void _chooseAudio(AudioTrack track) {
    _audioId = track.id;
    _player?.setAudioTrack(track);
    Store.setAudioLanguage(track.language ?? '');
    log('audio track=${track.language ?? track.id}');
  }

  void _chooseSubtitle(SubtitleTrack? track) {
    _subtitleId = track?.id ?? 'no';
    _player?.setSubtitleTrack(track ?? SubtitleTrack.no());
    Store.setSubtitleLanguage(track?.language ?? '');
    log('subtitle track=${track == null ? 'off' : (track.language ?? track.id)}');
  }

  void _chooseSpeed(double speed) {
    _speed = speed;
    _player?.setRate(speed);
    log('speed=$speed');
  }

  /// What the engine is doing right now, for the Quality panel (and for support).
  Future<List<String>> _streamFacts() async {
    final platform = _player?.platform;
    if (platform is! NativePlayer) return const [];
    Future<String> read(String name) async {
      try {
        return (await platform.getProperty(name)).trim();
      } catch (_) {
        return '';
      }
    }

    final values = await Future.wait([
      read('video-format'),
      read('hwdec-current'),
      read('container-fps'),
      read('frame-drop-count'),
      read('decoder-frame-drop-count'),
      read('audio-codec-name'),
    ]);
    final fps = double.tryParse(values[2]) ?? 0;
    final hardware = values[1].isNotEmpty && values[1] != 'no';
    final dropped = (int.tryParse(values[3]) ?? 0) + (int.tryParse(values[4]) ?? 0);
    final facts = <String>[
      if (values[0].isNotEmpty) 'Video: ${values[0].toUpperCase()}${fps > 0 ? ', ${fps.toStringAsFixed(fps == fps.roundToDouble() ? 0 : 2)} pictures a second' : ''}',
      hardware ? 'Decoded by the video chip (${values[1]})' : 'Decoded by the processor (slower)',
      if (values[5].isNotEmpty) 'Sound: ${values[5].toUpperCase()}',
      'Pictures skipped so far: $dropped',
    ];
    log('facts video=${values[0]} hwdec=${values[1]} fps=${values[2]} dropped=$dropped mode=${_direct ? 'direct' : 'gpu'}');
    return facts;
  }

  String _variantLabel(VideoTrack track, int number) {
    final height = track.h ?? 0;
    final rate = track.bitrate ?? 0;
    final parts = <String>[
      if (height > 0) qualityOfHeight(height) else 'Version $number',
      if (rate > 0) '${(rate / 1000000).toStringAsFixed(1)} Mbit/s',
    ];
    return parts.join('  ·  ');
  }

  /// "Quality": the versions of this channel that the server lists, and the variants inside the
  /// stream when it has several. A stream that exists in one quality only is shown as such.
  Future<void> _openQuality() async {
    if (_panelOpen) return;
    _panelOpen = true;
    _hideTimer?.cancel();
    final names = [for (final e in widget.entries) e.title];
    final versions = widget.live ? otherVersions(names, _index) : const <int>[];
    final variants = _videoTracks.length > 1 ? _videoTracks : const <VideoTrack>[];
    log('panel=quality versions=${versions.length} variants=${variants.length}');
    final now = _videoHeight > 0 ? '${qualityOfHeight(_videoHeight)}  ($_videoSize)' : 'Unknown';
    final facts = await _streamFacts();
    if (!mounted) {
      _panelOpen = false;
      return;
    }
    final picked = await showDialog<int>(
      context: context,
      barrierColor: const Color(0x66000000),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => _SidePanel(
          alignment: Alignment.centerRight,
          title: 'Quality',
          children: [
            const _PanelHeading('Playing now'),
            _PanelNote(now),
            for (final fact in facts) _PanelNote(fact),
            if (variants.isNotEmpty) ...[
              const _PanelHeading('Quality of this stream'),
              _PanelRow(
                label: 'Automatic (best)',
                selected: _videoId == 'auto',
                autofocus: true,
                onTap: () {
                  _videoId = 'auto';
                  _player?.setVideoTrack(VideoTrack.auto());
                  log('quality=auto');
                  refresh(() {});
                },
              ),
              for (var i = 0; i < variants.length; i++)
                _PanelRow(
                  label: _variantLabel(variants[i], i + 1),
                  selected: _videoId == variants[i].id,
                  onTap: () {
                    _videoId = variants[i].id;
                    _player?.setVideoTrack(variants[i]);
                    log('quality=${variants[i].h ?? variants[i].id}');
                    refresh(() {});
                  },
                ),
            ],
            if (versions.isNotEmpty) ...[
              const _PanelHeading('Other versions of this channel'),
              for (var i = 0; i < versions.length; i++)
                _PanelRow(
                  label: '${qualityInName(names[versions[i]])}   ${names[versions[i]]}',
                  selected: false,
                  autofocus: variants.isEmpty && i == 0,
                  onTap: () => Navigator.of(ctx).pop(versions[i]),
                ),
            ],
            if (variants.isEmpty && versions.isEmpty)
              const _PanelNote('The server sends this in one quality only, so there is nothing to switch to. '
                  'A player cannot shrink a stream: the whole stream is downloaded either way.'),
            if (variants.isEmpty && versions.isEmpty)
              _PanelRow(label: 'OK', selected: false, autofocus: true, onTap: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    );
    _panelOpen = false;
    if (!mounted) return;
    if (picked != null && picked != _index) {
      _tuneTo(picked);
    } else {
      _showOverlay();
    }
  }

  /// Opens the same stream again at the same place (after a picture-mode change).
  void _reopenHere() {
    _saveResume();
    _fails = 0;
    _open(startAt: widget.live ? null : _position);
  }

  void _chooseVideoMode(int index) {
    if (Store.videoMode == _videoModes[index]) return;
    Store.setVideoMode(_videoModes[index]);
    log('video mode=${_videoModes[index]}');
    _reopenHere();
  }

  void _chooseFit(int fit) {
    _fit = fit;
    log('fit=${_fitNames[fit]}');
  }

  Future<void> _openOptions() async {
    if (_panelOpen) return;
    _panelOpen = true;
    _hideTimer?.cancel();
    log('panel=options');
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x66000000),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) {
          void pick(VoidCallback action) {
            action();
            refresh(() {});
            if (mounted) setState(() {});
          }

          return _SidePanel(
            alignment: Alignment.centerRight,
            title: 'Audio and subtitles',
            children: [
              const _PanelHeading('Audio'),
              if (_audioTracks.isEmpty) const _PanelNote('This stream has one audio track.'),
              for (var i = 0; i < _audioTracks.length; i++)
                _PanelRow(
                  label: trackLabel(_audioTracks[i].language, _audioTracks[i].title, i + 1),
                  selected: _audioTracks[i].id == _audioId,
                  autofocus: _audioTracks[i].id == _audioId,
                  onTap: () => pick(() => _chooseAudio(_audioTracks[i])),
                ),
              const _PanelHeading('Subtitles'),
              _PanelRow(
                label: 'Off',
                selected: _subtitleId == 'no',
                autofocus: _audioTracks.isEmpty,
                onTap: () => pick(() => _chooseSubtitle(null)),
              ),
              for (var i = 0; i < _subtitleTracks.length; i++)
                _PanelRow(
                  label: trackLabel(_subtitleTracks[i].language, _subtitleTracks[i].title, i + 1),
                  selected: _subtitleTracks[i].id == _subtitleId,
                  onTap: () => pick(() => _chooseSubtitle(_subtitleTracks[i])),
                ),
              if (!widget.live) ...[
                const _PanelHeading('Speed'),
                _PanelChips(
                  labels: [for (final s in _speeds) '${s}x'],
                  selected: _speeds.indexOf(_speed),
                  onTap: (i) => pick(() => _chooseSpeed(_speeds[i])),
                ),
              ],
              const _PanelHeading('Picture'),
              _PanelChips(
                labels: _fitNames,
                selected: _fit,
                onTap: (i) => pick(() => _chooseFit(i)),
              ),
              const _PanelHeading('Video mode'),
              _PanelChips(
                labels: _videoModeNames,
                selected: _videoModes.indexOf(Store.videoMode),
                onTap: (i) => pick(() => _chooseVideoMode(i)),
              ),
              const _PanelNote('Direct is lighter for TV sticks. Use Standard if a video shows no picture.'),
            ],
          );
        },
      ),
    );
    _panelOpen = false;
    if (mounted) _showOverlay();
  }

  Future<void> _openChannels() async {
    if (_panelOpen || !widget.live || widget.entries.length < 2) return;
    _panelOpen = true;
    _hideTimer?.cancel();
    log('panel=channels');
    const rowHeight = 42.0;
    final scroll = ScrollController(initialScrollOffset: (_index < 4 ? 0 : _index - 4) * rowHeight);
    final picked = await showDialog<int>(
      context: context,
      barrierColor: const Color(0x66000000),
      builder: (ctx) => _SidePanel(
        alignment: Alignment.centerLeft,
        title: 'Channels',
        list: ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          itemExtent: rowHeight,
          itemCount: widget.entries.length,
          itemBuilder: (context, i) => _PanelRow(
            label: '${i + 1}   ${widget.entries[i].title}',
            selected: i == _index,
            autofocus: i == _index,
            onTap: () => Navigator.of(ctx).pop(i),
          ),
        ),
      ),
    );
    scroll.dispose();
    _panelOpen = false;
    if (!mounted) return;
    if (picked != null && picked != _index) {
      _tuneTo(picked);
    } else {
      _showOverlay();
    }
  }

  // ---------------------------------------------------------------- controls

  /// True while the remote is on one of the buttons of the control bar.
  bool get _onControls => _overlay && _focus.hasFocus && !_focus.hasPrimaryFocus;

  /// Shows the control bar. With [focus] the remote lands on its main button.
  void _showOverlay({bool focus = false}) {
    _hideTimer?.cancel();
    if (!_overlay && mounted) setState(() => _overlay = true);
    if (focus && !_dead) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _overlay && !_panelOpen && _focus.hasPrimaryFocus) _mainButton.requestFocus();
      });
    }
    _hideTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted || _dead || _userPaused || _scrubbing || _panelOpen || _zapTarget != null || _seekTarget != null) {
        return;
      }
      _hideOverlay();
    });
  }

  void _hideOverlay() {
    _hideTimer?.cancel();
    if (!_focus.hasPrimaryFocus) _focus.requestFocus();
    if (_overlay && mounted) setState(() => _overlay = false);
  }

  void _toggleOverlay() {
    if (_overlay && !_dead && !_userPaused) {
      _hideOverlay();
    } else {
      _showOverlay();
    }
  }

  void _tuneTo(int index) {
    _zapTimer?.cancel();
    _saveResume();
    setState(() {
      _index = index;
      _zapTarget = null;
      _urlIndex = 0;
      _fails = 0;
      _playedThisUrl = false;
      _epg = const [];
      _lastPosition = Duration.zero;
    });
    _open();
    _scheduleEpg();
    _showOverlay();
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
    _zapTimer = Timer(const Duration(milliseconds: 280), () {
      final next = _zapTarget;
      if (mounted && next != null) _tuneTo(next);
    });
  }

  void _togglePause() {
    if (!_ready || widget.live) {
      _showOverlay();
      return;
    }
    if (_userPaused) {
      _userPaused = false;
      _lastProgress = DateTime.now();
      _player?.play();
    } else {
      _userPaused = true;
      _player?.pause();
    }
    log(_userPaused ? 'paused' : 'resumed');
    setState(() {});
    _showOverlay();
  }

  void _seek(int direction) {
    if (!_ready || widget.live || _duration <= Duration.zero) return;
    _seekPresses++;
    final step = _seekPresses > 16 ? 60 : (_seekPresses > 6 ? 30 : 10);
    _previewSeek((_seekTarget ?? _position) + Duration(seconds: step * direction));
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 400), () {
      _seekPresses = 0;
      final to = _seekTarget;
      if (to != null) _commitSeek(to);
    });
  }

  void _previewSeek(Duration target) {
    var to = target;
    if (to < Duration.zero) to = Duration.zero;
    final end = _duration - const Duration(seconds: 3);
    if (end > Duration.zero && to > end) to = end;
    setState(() => _seekTarget = to);
    _showOverlay();
  }

  Future<void> _commitSeek(Duration to) async {
    if (!mounted || !_ready) return;
    _lastProgress = DateTime.now();
    try {
      await _player?.seek(to);
    } catch (_) {}
    if (!mounted) return;
    _position = to;
    _lastPosition = to;
    setState(() => _seekTarget = null);
    _showOverlay();
  }

  void _toggleFavourite() {
    final item = _entry.item;
    if (item == null) return;
    final added = Store.toggleFavourite(item);
    log('favourite ${added ? 'added' : 'removed'}');
    setState(() => _buttonLabel = added ? 'Added to Favourites' : 'Removed from Favourites');
    _showOverlay();
  }

  void _step(int direction) {
    final next = _index + direction;
    if (next >= 0 && next < widget.entries.length) _tuneTo(next);
  }

  void _cycleFit() {
    _fit = (_fit + 1) % _fits.length;
    log('fit=${_fitNames[_fit]}');
    setState(() => _buttonLabel = 'Picture: ${_fitNames[_fit]}');
    _showOverlay();
  }

  void _retryNow() {
    _fails = 0;
    _urlIndex = 0;
    _playedThisUrl = false;
    _open(startAt: widget.live ? null : _lastPosition);
  }

  void _tap() {
    if (_dead) {
      _retryNow();
    } else {
      _toggleOverlay();
    }
    if (mounted) setState(() {});
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  bool _isOk(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA;

  /// Remote keys.
  ///
  /// Bar hidden:  OK shows the buttons. Movies: Left / Right jump. Live: Up / Down change
  ///              channel, Left = channel list, Right = audio and subtitles, hold OK = favourite.
  /// On the bar:  Left / Right move between the buttons, OK presses one (hold OK on the jump
  ///              buttons to keep jumping), Back hides the bar.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final k = event.logicalKey;
    final down = event is KeyDownEvent;
    final up = event is KeyUpEvent;

    // Keys that mean the same wherever the focus is.
    if (!up) {
      if (k == LogicalKeyboardKey.contextMenu) {
        if (down) _openOptions();
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
      } else {
        if (k == LogicalKeyboardKey.mediaRewind) {
          _seek(-1);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.mediaFastForward) {
          _seek(1);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.space) {
          if (down) _togglePause();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.mediaPlay) {
          if (down && _userPaused) _togglePause();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.mediaPause) {
          if (down && !_userPaused) _togglePause();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.mediaTrackNext) {
          if (down) _step(1);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.mediaTrackPrevious) {
          if (down) _step(-1);
          return KeyEventResult.handled;
        }
      }
    }

    if (_onControls) {
      // The focused button gets OK and Left / Right. Any key keeps the bar on screen.
      if (down) _showOverlay();
      return KeyEventResult.ignored;
    }

    if (_isOk(k)) {
      if (down) {
        _okDown = true;
        _okLong = false;
      } else if (event is KeyRepeatEvent) {
        if (_okDown && !_okLong && widget.live && !_dead) {
          _okLong = true;
          _toggleFavourite();
        }
      } else if (up) {
        final tap = _okDown && !_okLong;
        _okDown = false;
        _okLong = false;
        if (tap) {
          if (_dead) {
            _retryNow();
          } else {
            _showOverlay(focus: true);
          }
        }
      }
      return KeyEventResult.handled;
    }
    if (up) return KeyEventResult.ignored;

    if (widget.live) {
      if (k == LogicalKeyboardKey.arrowLeft) {
        if (down) _openChannels();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        if (down) _openOptions();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _seek(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _seek(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      if (down) _showOverlay(focus: true);
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
    final busy = _status != null || (_buffering && !_userPaused);
    final shown = widget.entries[_zapTarget ?? _index];
    final video = _video;
    return PopScope(
      // Back first puts the control bar away, the next Back leaves the player.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_onControls) {
          _hideOverlay();
        } else {
          _close();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _tap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The picture is hidden until it really plays, so the last frame of the previous
                // channel never shows under the new channel's name.
                if (video != null)
                  Opacity(
                    opacity: _ready ? 1 : 0,
                    child: IgnorePointer(
                      child: ExcludeFocus(
                        child: Video(
                          key: ObjectKey(video),
                          controller: video,
                          controls: NoVideoControls,
                          fit: _fits[_fit],
                          fill: Colors.black,
                          // Subtitles sit above the controls while those are on screen.
                          subtitleViewConfiguration: SubtitleViewConfiguration(
                            padding: EdgeInsets.fromLTRB(24, 0, 24, _overlay ? 150 : 26),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox.expand(),
                if (busy && !_dead) Center(child: Loading(label: _status)),
                if (_dead) Center(child: _DeadMessage(text: _status ?? '', detail: _lastError)),
                IgnorePointer(
                  ignoring: !_overlay,
                  child: AnimatedOpacity(
                    opacity: _overlay ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: ExcludeFocus(excluding: !_overlay || _dead, child: _overlayLayer(shown)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(IconData icon, String label, VoidCallback onTap, {double size = 44, FocusNode? node, bool active = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: TvFocus(
        focusNode: node,
        radius: size / 2,
        color: const Color(0x8C10131A),
        onTap: onTap,
        onFocus: () {
          if (_buttonLabel != label) setState(() => _buttonLabel = label);
        },
        child: SizedBox(
          width: size - 5,
          height: size - 5,
          child: Icon(icon, size: size * 0.5, color: active ? C.accent : Colors.white),
        ),
      ),
    );
  }

  Widget _overlayLayer(PlayEntry shown) {
    final item = shown.item;
    final favourite = item != null && Store.isFavourite(item);
    final many = widget.entries.length > 1;
    final number = (_zapTarget ?? _index) + 1;

    final List<Widget> centre = widget.live
        ? [
            if (many) _button(Icons.list_rounded, 'Channel list', _openChannels, node: _mainButton, size: 52),
            if (many) _button(Icons.skip_previous_rounded, 'Previous channel', () => _zap(-1)),
            if (many) _button(Icons.skip_next_rounded, 'Next channel', () => _zap(1)),
          ]
        : [
            if (many) _button(Icons.skip_previous_rounded, 'Previous episode', () => _step(-1)),
            _button(Icons.fast_rewind_rounded, 'Back 10 seconds (hold for more)', () => _seek(-1)),
            _button(
              _userPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              _userPaused ? 'Play' : 'Pause',
              _togglePause,
              node: _mainButton,
              size: 60,
            ),
            _button(Icons.fast_forward_rounded, 'Forward 10 seconds (hold for more)', () => _seek(1)),
            if (many) _button(Icons.skip_next_rounded, 'Next episode', () => _step(1)),
          ];
    final List<Widget> side = [
      _button(Icons.audiotrack_rounded, 'Audio language', _openOptions, node: widget.live && !many ? _mainButton : null),
      _button(Icons.closed_caption_rounded, 'Subtitles', _openOptions),
      _button(Icons.aspect_ratio_rounded, 'Picture: ${_fitNames[_fit]}', _cycleFit),
      _button(Icons.high_quality_rounded, 'Quality', _openQuality),
      if (!widget.live) _button(Icons.speed_rounded, 'Speed ${_speed}x', _openOptions),
      if (widget.live && item != null)
        _button(favourite ? Icons.star_rounded : Icons.star_border_rounded,
            favourite ? 'Remove from Favourites' : 'Add to Favourites', _toggleFavourite,
            active: favourite),
      _button(Icons.undo_rounded, 'Back', _close),
    ];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(26, 18, 34, 46),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xD9000000), Colors.transparent],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // For touch screens; the remote uses the Back key or the Back button of the bar.
              ExcludeFocus(child: _RoundButton(icon: Icons.arrow_back_rounded, size: 44, onTap: _close)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.live ? '$number.  ${shown.title}' : shown.title,
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
          padding: const EdgeInsets.fromLTRB(28, 44, 28, 16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xF0000000)],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Logo / poster with the picture size under it.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: widget.live ? 76 : 70,
                      height: widget.live ? 76 : 100,
                      color: const Color(0x8C10131A),
                      padding: EdgeInsets.all(widget.live ? 6 : 0),
                      child: NetImage(
                        shown.logo,
                        fit: widget.live ? BoxFit.contain : BoxFit.cover,
                        cacheWidth: 200,
                        fallback: widget.live ? Icons.tv : Icons.movie_rounded,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(_zapTarget == null ? _videoSize : '',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFFD5DAE3), fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.live) _guide() else _timeline(),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 66,
                      child: Row(
                        children: [
                          // Name of the button the remote is on.
                          Expanded(
                            child: Text(_buttonLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, height: 1.2, color: C.dim)),
                          ),
                          ...centre,
                          const SizedBox(width: 22),
                          ...side,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Live TV: what is on now and next.
  Widget _guide() {
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
    final double progress = current == null
        ? 0.0
        : (now.difference(current.start).inSeconds / (current.end.difference(current.start).inSeconds.clamp(1, 1 << 30)))
            .clamp(0.0, 1.0)
            .toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          current == null
              ? 'No TV guide for this channel'
              : '${formatClock(current.start)} – ${formatClock(current.end)}   ${current.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: current == null ? 13.5 : 17,
            fontWeight: current == null ? FontWeight.w500 : FontWeight.w700,
            color: current == null ? C.dim : C.text,
          ),
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            minHeight: 4,
            value: progress,
            color: C.accent,
            backgroundColor: const Color(0x44FFFFFF),
          ),
        ),
        if (next != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Next  ${formatClock(next.start)}   ${next.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Color(0xFFD5DAE3))),
          ),
      ],
    );
  }

  /// Movies and episodes: time, bar that can be dragged by touch, total length.
  Widget _timeline() {
    final duration = _duration;
    final position = _seekTarget ?? _position;
    final known = duration > Duration.zero;
    final double value = known ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble() : 0.0;
    return Row(
      children: [
        Text(formatTime(position), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        Expanded(
          child: ExcludeFocus(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                activeTrackColor: C.accent,
                inactiveTrackColor: const Color(0x44FFFFFF),
                thumbColor: C.accent,
                overlayColor: const Color(0x33FFC400),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              ),
              child: Slider(
                value: value,
                onChangeStart: known
                    ? (_) {
                        _scrubbing = true;
                        _hideTimer?.cancel();
                      }
                    : null,
                onChanged: known ? (v) => _previewSeek(duration * v) : null,
                onChangeEnd: known
                    ? (v) {
                        _scrubbing = false;
                        _commitSeek(duration * v);
                      }
                    : null,
              ),
            ),
          ),
        ),
        Text(formatTime(duration), style: const TextStyle(fontSize: 15, color: Color(0xFFD5DAE3))),
      ],
    );
  }
}

/// Round, tappable control drawn over the picture (touch only).
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, this.size = 48});
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x73000000),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        canRequestFocus: false,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.58, color: Colors.white),
        ),
      ),
    );
  }
}

/// Panel over one side of the picture (channel list, audio and subtitles).
class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.alignment, required this.title, this.children, this.list});
  final Alignment alignment;
  final String title;
  final List<Widget>? children;
  final Widget? list;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Material(
        color: const Color(0xF211141B),
        child: SizedBox(
          width: 330,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    ),
                    if (!InputMode.remote)
                      ExcludeFocus(
                        child: IconButton(
                          icon: const Icon(Icons.close_rounded, color: C.dim),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: list ??
                    ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                      children: children ?? const [],
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
      child: Text(text.toUpperCase(),
          style: const TextStyle(fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: C.dim)),
    );
  }
}

class _PanelNote extends StatelessWidget {
  const _PanelNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      child: Text(text, style: const TextStyle(fontSize: 13.5, color: C.dim)),
    );
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({required this.label, required this.selected, required this.onTap, this.autofocus = false});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TvFocus(
        autofocus: autofocus,
        selected: selected,
        radius: 8,
        color: const Color(0xFF171B24),
        onTap: onTap,
        child: SizedBox(
          height: 38,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                ),
                if (selected) const Icon(Icons.check_rounded, color: C.accent, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelChips extends StatelessWidget {
  const _PanelChips({required this.labels, required this.selected, required this.onTap});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < labels.length; i++)
            TvFocus(
              selected: i == selected,
              radius: 18,
              color: const Color(0xFF171B24),
              onTap: () => onTap(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                child: Text(labels[i],
                    style: TextStyle(fontSize: 13.5, fontWeight: i == selected ? FontWeight.w800 : FontWeight.w500)),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeadMessage extends StatelessWidget {
  const _DeadMessage({required this.text, this.detail = ''});
  final String text;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final shortDetail = detail.length > 110 ? '${detail.substring(0, 110)}…' : detail;
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
      decoration: BoxDecoration(color: const Color(0xCC11141B), borderRadius: BorderRadius.circular(14)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: C.dim, size: 32),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(InputMode.remote ? 'Press OK to try again' : 'Tap to try again',
              style: const TextStyle(fontSize: 13.5, color: C.dim)),
          if (shortDetail.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(shortDetail,
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7384))),
          ],
        ],
      ),
    );
  }
}
