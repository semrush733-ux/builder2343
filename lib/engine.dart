import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'config.dart';
import 'store.dart';

/// A message from an engine: [error] true for real errors, false for chatter.
class EngineMessage {
  const EngineMessage(this.text, this.error);
  final String text;
  final bool error;
}

/// What the player screen needs from a playback engine. Two engines exist:
/// [MpvEngine] (libmpv through media_kit) and [ExoEngine] (Google ExoPlayer, Android only).
/// The screen's own controls work the same on both.
abstract class PlaybackEngine {
  String get name;

  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get buffering;
  Stream<bool> get completed;
  Stream<Tracks> get tracks;
  Stream<EngineMessage> get messages;

  Duration get durationNow;
  Tracks get tracksNow;
  int get width;
  int get height;
  bool get playing;
  bool get isBuffering;

  Future<void> open(String url, Duration start);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Future<void> setRate(double rate);
  Future<void> setAudioTrack(AudioTrack track);
  Future<void> setSubtitleTrack(SubtitleTrack track);
  Future<void> setVideoTrack(VideoTrack track);
  Future<List<String>> facts();
  Future<void> dispose();

  /// The picture. [subtitlePad] keeps subtitles above the control bar.
  Widget view({required BoxFit fit, required double subtitlePad});
}

// ------------------------------------------------------------------------------------- mpv

class MpvEngine extends PlaybackEngine {
  MpvEngine({required this.live, required this.direct}) {
    player = Player(
      configuration: PlayerConfiguration(
        title: '2060 Tele Player',
        bufferSize: 48 * 1024 * 1024,
        logLevel: kVerbose ? MPVLogLevel.info : MPVLogLevel.error,
      ),
    );
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        vo: direct ? 'mediacodec_embed' : null,
        hwdec: direct ? 'mediacodec' : null,
      ),
    );
    _logSub = player.stream.log.listen((line) {
      final text = line.text.trim();
      if (text.isNotEmpty) _messages.add(EngineMessage('${line.prefix}: $text', line.level == 'error' || line.level == 'fatal'));
    });
    _errSub = player.stream.error.listen((message) {
      final text = message.trim();
      if (text.isNotEmpty) _messages.add(EngineMessage(text, true));
    });
  }

  final bool live;
  final bool direct;
  late final Player player;
  late final VideoController controller;
  final _messages = StreamController<EngineMessage>.broadcast();
  StreamSubscription<dynamic>? _logSub;
  StreamSubscription<dynamic>? _errSub;

  @override
  String get name => 'mpv';
  @override
  Stream<Duration> get position => player.stream.position;
  @override
  Stream<Duration> get duration => player.stream.duration;
  @override
  Stream<bool> get buffering => player.stream.buffering;
  @override
  Stream<bool> get completed => player.stream.completed;
  @override
  Stream<Tracks> get tracks => player.stream.tracks;
  @override
  Stream<EngineMessage> get messages => _messages.stream;
  @override
  Duration get durationNow => player.state.duration;
  @override
  Tracks get tracksNow => player.state.tracks;
  @override
  int get width => player.state.width ?? 0;
  @override
  int get height => player.state.height ?? 0;
  @override
  bool get playing => player.state.playing;
  @override
  bool get isBuffering => player.state.buffering;

  /// Engine settings chosen for IPTV: reconnect inside the network layer, a
  /// few seconds of buffer, and only a short pause when the buffer runs dry.
  Future<void> _configure() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    // dynamic: setProperty only exists in the Android/desktop NativePlayer, so a
    // static call would break the web compile; the guard above never lets web get here.
    final dynamic mpv = platform;
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
      set('cache-pause-initial', 'no'),
      set('cache-pause-wait', live ? '1' : '2'),
      set('demuxer-readahead-secs', '${((live ? 10 : 60) * _bufMul).round()}'),
      set('demuxer-max-bytes', '${((live ? 64 : 192) * _bufMul).round()}MiB'),
      set('demuxer-max-back-bytes', live ? '16MiB' : '64MiB'),
      if (!live) set('demuxer-seekable-cache', 'yes'),
      set('vd-lavc-dr', 'yes'),
      if (live) set('demuxer-lavf-analyzeduration', '1'),
      if (!live) set('hr-seek', 'no'),
      set('audio-channels', 'stereo'),
      set('sub-auto', 'no'),
      set('hwdec-codecs', 'all'),
      set('vd-lavc-threads', '0'),
      set('vd-lavc-fast', 'yes'),
      set('vd-lavc-skiploopfilter', 'nonkey'),
      set('framedrop', 'decoder+vo'),
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
      if (direct) set('hwdec', 'mediacodec'),
    ]);
  }

  @override
  Future<void> open(String url, Duration start) async {
    await _configure();
    await player.open(
      // Browsers refuse a custom User-Agent, so the web build sends no headers.
      Media(url,
          httpHeaders: kIsWeb ? null : const {'User-Agent': kUserAgent},
          start: start > Duration.zero ? start : null),
      play: true,
    );
  }

  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> seek(Duration to) => player.seek(to);
  @override
  Future<void> setRate(double rate) => player.setRate(rate);
  @override
  Future<void> setAudioTrack(AudioTrack track) => player.setAudioTrack(track);
  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) => player.setSubtitleTrack(track);
  @override
  Future<void> setVideoTrack(VideoTrack track) => player.setVideoTrack(track);

  @override
  Future<List<String>> facts() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return const [];
    final dynamic mpv = platform;
    Future<String> read(String name) async {
      try {
        return ((await mpv.getProperty(name)) as String).trim();
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
    return <String>[
      'Engine: MPV${direct ? ' (direct picture)' : ''}',
      if (values[0].isNotEmpty)
        'Video: ${values[0].toUpperCase()}${fps > 0 ? ', ${fps.toStringAsFixed(fps == fps.roundToDouble() ? 0 : 2)} pictures a second' : ''}',
      hardware ? 'Decoded by the video chip (${values[1]})' : 'Decoded by the processor (slower)',
      if (values[5].isNotEmpty) 'Sound: ${values[5].toUpperCase()}',
      'Pictures skipped so far: $dropped',
    ];
  }

  @override
  Future<void> dispose() async {
    await _logSub?.cancel();
    await _errSub?.cancel();
    await _messages.close();
    await player.dispose();
  }

  @override
  Widget view({required BoxFit fit, required double subtitlePad}) {
    return Video(
      key: ObjectKey(controller),
      controller: controller,
      controls: NoVideoControls,
      fit: fit,
      fill: Colors.black,
      subtitleViewConfiguration: SubtitleViewConfiguration(
        padding: EdgeInsets.fromLTRB(24, 0, 24, subtitlePad),
      ),
    );
  }
}

// ------------------------------------------------------------------------------- ExoPlayer

class ExoEngine extends PlaybackEngine {
  ExoEngine._(this.live);

  static const _channel = MethodChannel('b1g/exo');
  static final Map<int, ExoEngine> _live = {};
  static bool _hooked = false;

  /// Only the Android app has it (not the web or the Samsung / LG versions).
  static bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final bool live;
  int _id = 0;
  int _texture = -1;
  bool _disposed = false;

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _tracks = StreamController<Tracks>.broadcast();
  final _messages = StreamController<EngineMessage>.broadcast();
  final ValueNotifier<String> _cues = ValueNotifier('');
  final ValueNotifier<Size> _size = ValueNotifier(Size.zero);

  Duration _dur = Duration.zero;
  Tracks _trackList = Tracks();
  bool _playing = false;
  bool _isBuffering = true;

  /// Creates the native engine (and the picture surface for it).
  static Future<ExoEngine> create({required bool live}) async {
    if (!_hooked) {
      _hooked = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'event') return null;
        final m = call.arguments;
        if (m is! Map) return null;
        final id = (m['id'] as num?)?.toInt() ?? 0;
        _live[id]?._onEvent(m);
        return null;
      });
    }
    final e = ExoEngine._(live);
    final r = await _channel.invokeMethod<Map<dynamic, dynamic>>('create', {'live': live, 'ua': kUserAgent, 'buf': Store.bufferLevel});
    e._id = (r?['id'] as num?)?.toInt() ?? 0;
    e._texture = (r?['texture'] as num?)?.toInt() ?? -1;
    if (e._id == 0 || e._texture < 0) throw StateError('ExoPlayer could not start');
    _live[e._id] = e;
    return e;
  }

  void _onEvent(Map<dynamic, dynamic> m) {
    if (_disposed) return;
    switch (m['type']) {
      case 'state':
        final pos = Duration(milliseconds: (m['pos'] as num?)?.toInt() ?? 0);
        final dur = Duration(milliseconds: (m['dur'] as num?)?.toInt() ?? 0);
        final buf = m['buffering'] == true;
        _playing = m['playing'] == true;
        if (dur != _dur) {
          _dur = dur;
          _duration.add(dur);
        }
        if (buf != _isBuffering) {
          _isBuffering = buf;
          _buffering.add(buf);
        }
        if (_playing) _position.add(pos);
      case 'size':
        final w = (m['w'] as num?)?.toDouble() ?? 0;
        final h = (m['h'] as num?)?.toDouble() ?? 0;
        if (w > 0 && h > 0) _size.value = Size(w, h);
      case 'tracks':
        final list = m['list'];
        if (list is List) {
          final audio = <AudioTrack>[];
          final subs = <SubtitleTrack>[];
          final video = <VideoTrack>[];
          for (final t in list) {
            if (t is! Map) continue;
            final id = (t['id'] ?? '').toString();
            final lang = t['language']?.toString();
            final label = t['label']?.toString();
            switch (t['kind']) {
              case 'a':
                audio.add(AudioTrack(id, label, lang));
              case 's':
                subs.add(SubtitleTrack(id, label, lang));
              case 'v':
                video.add(VideoTrack(id, label, lang,
                    w: (t['w'] as num?)?.toInt(), h: (t['h'] as num?)?.toInt(), bitrate: (t['bitrate'] as num?)?.toInt()));
            }
          }
          _trackList = Tracks(audio: audio, subtitle: subs, video: video);
          _tracks.add(_trackList);
        }
      case 'cues':
        _cues.value = (m['text'] ?? '').toString();
      case 'ended':
        _completed.add(true);
      case 'error':
        _messages.add(EngineMessage('exo: ${m['message'] ?? ''} failed to open', true));
    }
  }

  Future<void> _call(String method, [Map<String, Object?> args = const {}]) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>(method, {'id': _id, ...args});
    } catch (_) {}
  }

  @override
  String get name => 'exo';
  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration> get duration => _duration.stream;
  @override
  Stream<bool> get buffering => _buffering.stream;
  @override
  Stream<bool> get completed => _completed.stream;
  @override
  Stream<Tracks> get tracks => _tracks.stream;
  @override
  Stream<EngineMessage> get messages => _messages.stream;
  @override
  Duration get durationNow => _dur;
  @override
  Tracks get tracksNow => _trackList;
  @override
  int get width => _size.value.width.toInt();
  @override
  int get height => _size.value.height.toInt();
  @override
  bool get playing => _playing;
  @override
  bool get isBuffering => _isBuffering;

  @override
  Future<void> open(String url, Duration start) => _call('open', {'url': url, 'startMs': start.inMilliseconds});
  @override
  Future<void> play() => _call('play');
  @override
  Future<void> pause() => _call('pause');
  @override
  Future<void> seek(Duration to) => _call('seek', {'ms': to.inMilliseconds});
  @override
  Future<void> setRate(double rate) => _call('rate', {'rate': rate});
  @override
  Future<void> setAudioTrack(AudioTrack track) => _call('track', {'kind': 'a', 'track': track.id});
  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) => _call('track', {'kind': 's', 'track': track.id});
  @override
  Future<void> setVideoTrack(VideoTrack track) => _call('track', {'kind': 'v', 'track': track.id});

  @override
  Future<List<String>> facts() async {
    if (_disposed) return const [];
    Map<dynamic, dynamic>? f;
    try {
      f = await _channel.invokeMethod<Map<dynamic, dynamic>>('facts', {'id': _id});
    } catch (_) {}
    if (f == null) return const ['Engine: ExoPlayer'];
    String mime(Object? v) {
      final s = (v ?? '').toString();
      final slash = s.indexOf('/');
      return (slash >= 0 ? s.substring(slash + 1) : s).toUpperCase();
    }

    final fps = (f['fps'] as num?)?.toDouble() ?? 0;
    final decoder = (f['decoder'] ?? '').toString();
    final software = decoder.startsWith('c2.android') || decoder.startsWith('OMX.google') || decoder.contains('ffmpeg');
    return [
      'Engine: ExoPlayer',
      if (mime(f['video']).isNotEmpty)
        'Video: ${mime(f['video'])}${fps > 0 ? ', ${fps.toStringAsFixed(fps == fps.roundToDouble() ? 0 : 2)} pictures a second' : ''}',
      if (decoder.isNotEmpty) software ? 'Decoded by the processor ($decoder)' : 'Decoded by the video chip ($decoder)',
      if (mime(f['audio']).isNotEmpty) 'Sound: ${mime(f['audio'])}',
      'Pictures skipped so far: ${(f['dropped'] as num?)?.toInt() ?? 0}',
    ];
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await _call('dispose');
    _disposed = true;
    _live.remove(_id);
    for (final c in [_position, _duration, _buffering, _completed, _tracks, _messages]) {
      await c.close();
    }
  }

  @override
  Widget view({required BoxFit fit, required double subtitlePad}) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ValueListenableBuilder<Size>(
            valueListenable: _size,
            builder: (context, size, _) {
              final s = size.isEmpty ? const Size(1920, 1080) : size;
              return ClipRect(
                child: FittedBox(
                  fit: fit,
                  child: SizedBox(width: s.width, height: s.height, child: Texture(textureId: _texture)),
                ),
              );
            },
          ),
          ValueListenableBuilder<String>(
            valueListenable: _cues,
            builder: (context, text, _) => text.isEmpty
                ? const SizedBox.shrink()
                : Positioned(
                    left: 24,
                    right: 24,
                    bottom: subtitlePad,
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        height: 1.25,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black), Shadow(blurRadius: 2, color: Colors.black)],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Buffer size chosen in Settings: small 0.5x, normal 1x, large 2x.
double get _bufMul => const [0.5, 1.0, 2.0][Store.bufferLevel];
