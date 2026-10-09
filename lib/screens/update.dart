import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../backend.dart';
import '../config.dart';
import '../theme.dart';
import '../widgets.dart';

/// Offers a newer version of the app: "Update now" downloads the APK from the address set on
/// the website and hands it to Android's installer. The new version installs over this one
/// (same signing key), so the login and favourites stay.
Future<void> showUpdateDialog(BuildContext context, BUpdate update) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !update.force,
    builder: (_) => UpdateDialog(update: update),
  );
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.update});
  final BUpdate update;

  /// True while the window is open.
  static bool showing = false;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _Stage { ask, downloading, installing, failed }

class _UpdateDialogState extends State<UpdateDialog> with WidgetsBindingObserver {
  _Stage _stage = _Stage.ask;
  int _percent = 0;
  String _message = '';
  bool _needsPermission = false;
  http.Client? _client;
  final _mainNode = FocusNode();

  @override
  void initState() {
    super.initState();
    UpdateDialog.showing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    UpdateDialog.showing = false;
    WidgetsBinding.instance.removeObserver(this);
    _client?.close();
    _mainNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Android's "allow this app to install" page: the button works again.
    if (state == AppLifecycleState.resumed && mounted && _stage == _Stage.installing) {
      setState(() {});
      _mainNode.requestFocus();
    }
  }

  Future<void> _start() async {
    if (_stage == _Stage.downloading) return;
    setState(() {
      _stage = _Stage.downloading;
      _percent = 0;
      _message = '';
    });
    _mainNode.requestFocus();
    log('update download start');
    try {
      final dir = await Backend.cacheDir();
      if (dir.isEmpty) throw const FileSystemException('no cache folder');
      final file = File('$dir/updates/B1G-update.apk');
      await file.parent.create(recursive: true);
      if (await file.exists()) await file.delete();

      final client = _client = http.Client();
      final request = http.Request('GET', Uri.parse(widget.update.apkUrl))..headers['User-Agent'] = kUserAgent;
      final response = await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw HttpException('status ${response.statusCode}');
      final total = response.contentLength ?? 0;
      var received = 0;
      var first = <int>[];
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 40))) {
          if (first.length < 2) first = [...first, ...chunk.take(2 - first.length)];
          sink.add(chunk);
          received += chunk.length;
          final percent = total > 0 ? (received * 100 ~/ total).clamp(0, 100).toInt() : 0;
          if (percent != _percent && mounted) setState(() => _percent = percent);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      // An APK is a zip file and starts with "PK"; a web page or an error text does not.
      if (received < 1024 * 1024 || first.length < 2 || first[0] != 0x50 || first[1] != 0x4B) {
        throw const FormatException('not an APK');
      }
      log('update downloaded bytes=$received');
      if (!mounted) return;
      await _install(file.path);
    } catch (e) {
      log('update failed: ${e.runtimeType}');
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _message = e is FormatException
            ? 'The update link on the website does not lead to the app file.'
            : 'The update could not be downloaded. Please check the internet and try again.';
      });
      _mainNode.requestFocus();
    } finally {
      _client?.close();
      _client = null;
    }
  }

  String? _path;

  Future<void> _install(String path) async {
    _path = path;
    final allowed = await Backend.canInstall();
    final started = await Backend.installApk(path);
    log('update installer started=$started allowed=$allowed');
    if (!mounted) return;
    setState(() {
      _stage = started ? _Stage.installing : _Stage.failed;
      _needsPermission = !allowed;
      _message = started ? '' : 'The installer could not be opened on this device.';
    });
    _mainNode.requestFocus();
  }

  void _close() => Navigator.of(context).pop();

  Widget _button(String label, VoidCallback onTap, {bool primary = false, FocusNode? node, bool autofocus = false}) {
    return TvFocus(
      focusNode: node,
      autofocus: autofocus,
      color: primary ? C.accent : C.card,
      focusBorder: primary ? Colors.white : C.accent,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Text(label,
            style: TextStyle(
                color: primary ? Colors.black : C.text, fontSize: 15, fontWeight: FontWeight.w800)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.update;
    final version = u.versionName.isEmpty ? 'build ${u.versionCode}' : u.versionName;
    List<Widget> body = const [];
    List<Widget> buttons = const [];
    switch (_stage) {
      case _Stage.ask:
        body = [
          Text(
            u.force
                ? 'Version $version is needed to keep using B1G.'
                : 'Version $version is ready. Your login and favourites stay as they are.',
            style: const TextStyle(fontSize: 14.5, color: C.dim, height: 1.4),
          ),
          if (u.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(u.notes,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, height: 1.4)),
          ],
        ];
        buttons = [
          _button('Update now', _start, primary: true, node: _mainNode, autofocus: true),
          if (!u.force) _button('Later', _close),
        ];
      case _Stage.downloading:
        body = [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _percent > 0 ? _percent / 100 : null,
                    minHeight: 10,
                    color: C.accent,
                    backgroundColor: C.card,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 52,
                child: Text('$_percent%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('Downloading the update…', style: TextStyle(fontSize: 14, color: C.dim)),
        ];
        buttons = [
          _button('Cancel', () {
            _client?.close();
            _close();
          }, node: _mainNode),
        ];
      case _Stage.installing:
        body = [
          Text(
            _needsPermission
                ? 'Your device asks once for permission: allow B1G to install apps '
                    '(on Fire TV: Settings › My Fire TV › Developer options › Install unknown apps › B1G › ON), '
                    'then press "Install" here.'
                : 'Choose "Update" or "Install" in the window your device shows. The app closes and opens again.',
            style: const TextStyle(fontSize: 14.5, color: C.dim, height: 1.4),
          ),
        ];
        buttons = [
          _button('Install', () {
            final path = _path;
            if (path != null) _install(path);
          }, primary: true, node: _mainNode),
          if (!u.force) _button('Close', _close),
        ];
      case _Stage.failed:
        body = [Text(_message, style: const TextStyle(fontSize: 14.5, color: C.danger, height: 1.4))];
        buttons = [
          _button('Try again', _start, primary: true, node: _mainNode),
          if (!u.force) _button('Close', _close),
        ];
    }
    return PopScope(
      canPop: !u.force && _stage != _Stage.downloading,
      child: Dialog(
        backgroundColor: C.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 22, 26, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.system_update_rounded, color: C.accent, size: 26),
                    const SizedBox(width: 12),
                    Text(u.force ? 'Update needed' : 'Update available',
                        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 14),
                ...body,
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < buttons.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      buttons[i],
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
