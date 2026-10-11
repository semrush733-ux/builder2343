import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'theme.dart';
import 'widgets.dart';

/// Internet speed test against Cloudflare's public speed servers (the same ones speed.cloudflare.com
/// uses): ping, download for about 8 seconds, upload for about 6 seconds.
class SpeedTest {
  static const _base = 'https://speed.cloudflare.com';

  /// Median round trip of a few tiny requests, in milliseconds.
  static Future<int> ping() async {
    final times = <int>[];
    final client = http.Client();
    try {
      for (var i = 0; i < 6; i++) {
        final sw = Stopwatch()..start();
        await client.get(Uri.parse('$_base/__down?bytes=0')).timeout(const Duration(seconds: 5));
        sw.stop();
        if (i > 0) times.add(sw.elapsedMilliseconds); // the first one includes setting up the connection
      }
    } finally {
      client.close();
    }
    if (times.isEmpty) return 0;
    times.sort();
    return times[times.length ~/ 2];
  }

  /// Downloads in 3 parallel streams for [seconds]; reports Mbit/s as it goes.
  static Future<double> download(void Function(double mbps) onProgress, {int seconds = 8}) async {
    var bytes = 0;
    final sw = Stopwatch()..start();
    final end = Duration(seconds: seconds);
    Future<void> stream() async {
      final client = http.Client();
      try {
        while (sw.elapsed < end) {
          final res = await client
              .send(http.Request('GET', Uri.parse('$_base/__down?bytes=25000000')))
              .timeout(const Duration(seconds: 10));
          await for (final chunk in res.stream) {
            bytes += chunk.length;
            if (sw.elapsed >= end) break;
          }
        }
      } catch (_) {
      } finally {
        client.close();
      }
    }

    final timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final s = sw.elapsedMilliseconds / 1000;
      if (s > 0.3) onProgress(bytes * 8 / s / 1e6);
    });
    await Future.wait([stream(), stream(), stream()]);
    timer.cancel();
    final s = sw.elapsedMilliseconds / 1000;
    return s > 0 ? bytes * 8 / s / 1e6 : 0;
  }

  /// Uploads 2 MB blocks for [seconds]; reports Mbit/s as it goes.
  static Future<double> upload(void Function(double mbps) onProgress, {int seconds = 6}) async {
    final block = Uint8List(2 * 1024 * 1024);
    var bytes = 0;
    final sw = Stopwatch()..start();
    final client = http.Client();
    try {
      while (sw.elapsed < Duration(seconds: seconds)) {
        await client.post(Uri.parse('$_base/__up'), body: block).timeout(const Duration(seconds: 15));
        bytes += block.length;
        final s = sw.elapsedMilliseconds / 1000;
        if (s > 0) onProgress(bytes * 8 / s / 1e6);
      }
    } catch (_) {
    } finally {
      client.close();
    }
    final s = sw.elapsedMilliseconds / 1000;
    return s > 0 ? bytes * 8 / s / 1e6 : 0;
  }
}

/// Opens the speed test window.
Future<void> showSpeedTest(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _SpeedTestDialog());

class _SpeedTestDialog extends StatefulWidget {
  const _SpeedTestDialog();

  @override
  State<_SpeedTestDialog> createState() => _SpeedTestDialogState();
}

class _SpeedTestDialogState extends State<_SpeedTestDialog> {
  String _phase = '';
  double _live = 0;
  int? _ping;
  double? _down;
  double? _up;
  bool _running = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _ping = null;
      _down = null;
      _up = null;
      _live = 0;
      _error = '';
      _phase = 'Ping';
    });
    try {
      final p = await SpeedTest.ping();
      if (!mounted) return;
      setState(() {
        _ping = p;
        _phase = 'Download';
      });
      final d = await SpeedTest.download((v) {
        if (mounted) setState(() => _live = v);
      });
      if (!mounted) return;
      setState(() {
        _down = d;
        _live = 0;
        _phase = 'Upload';
      });
      final u = await SpeedTest.upload((v) {
        if (mounted) setState(() => _live = v);
      });
      if (!mounted) return;
      setState(() {
        _up = u;
        _live = u;
        _phase = 'Done';
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'The test could not reach the internet.');
    }
    if (mounted) setState(() => _running = false);
  }

  String _verdict(double mbps) {
    if (mbps >= 50) return 'Excellent: 4K streams play smoothly.';
    if (mbps >= 25) return 'Very good: Full HD and most 4K play smoothly.';
    if (mbps >= 10) return 'Good: HD channels play smoothly.';
    if (mbps >= 5) return 'Fair: SD and some HD channels.';
    return 'Slow: streams may buffer. Try a cable or move closer to the router.';
  }

  Widget _stat(String label, String value, String unit, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontSize: 12.5, color: C.dim, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
              Text(unit, style: const TextStyle(fontSize: 11.5, color: C.dim)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final shown = _phase == 'Done' ? (_down ?? 0) : _live;
    final frac = (math.log(1 + shown) / math.log(1 + 300)).clamp(0.0, 1.0);
    return AlertDialog(
      backgroundColor: C.panel,
      // Test again / Close sit next to the title, so small screens never cover them.
      title: Row(
        children: [
          const Icon(Icons.speed_rounded, color: C.accent),
          const SizedBox(width: 10),
          const Expanded(child: Text('Internet speed test', maxLines: 1, overflow: TextOverflow.ellipsis)),
          TvFocus(
            radius: 9,
            color: C.card,
            onTap: _run,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.refresh_rounded, size: 16, color: C.accent),
                  const SizedBox(width: 6),
                  Text(_running ? 'Testing…' : 'Test again',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          TvFocus(
            autofocus: true,
            radius: 9,
            color: C.card,
            onTap: () => Navigator.of(context).pop(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.close_rounded, size: 16, color: C.dim),
                  SizedBox(width: 6),
                  Text('Close', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 200,
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 190,
                    height: 190,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: frac),
                      duration: const Duration(milliseconds: 300),
                      builder: (_, v, __) => CircularProgressIndicator(
                        value: v,
                        strokeWidth: 12,
                        color: C.accent,
                        backgroundColor: const Color(0x22FFFFFF),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(shown.toStringAsFixed(shown >= 100 ? 0 : 1),
                          style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w900)),
                      const Text('Mbit/s', style: TextStyle(fontSize: 14, color: C.dim)),
                      const SizedBox(height: 4),
                      Text(_phase == 'Done' ? 'Download' : _phase,
                          style: const TextStyle(fontSize: 13, color: C.accent, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _stat('PING', _ping == null ? '–' : '$_ping', 'ms', const Color(0xFF35D6C4)),
                const SizedBox(width: 10),
                _stat('DOWNLOAD', _down == null ? '–' : _down!.toStringAsFixed(1), 'Mbit/s', C.accent),
                const SizedBox(width: 10),
                _stat('UPLOAD', _up == null ? '–' : _up!.toStringAsFixed(1), 'Mbit/s', const Color(0xFFB37BFF)),
              ],
            ),
            const SizedBox(height: 14),
            if (_error.isNotEmpty)
              Text(_error, style: const TextStyle(color: C.danger))
            else if (_down != null)
              Text(_verdict(_down!), textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: C.text))
            else
              const Text('Testing… this takes about 15 seconds.', style: TextStyle(color: C.dim)),
          ],
        ),
        ),
      ),
    );
  }
}
