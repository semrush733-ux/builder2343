import 'package:flutter/material.dart';

import '../engine.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

/// App settings, opened from the gear on the home screen.
/// The player choice lives here (not in the player), so customers set it once.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    log('screen=settings');
  }

  @override
  Widget build(BuildContext context) {
    final exo = ExoEngine.available;
    final engine = exo ? Store.engine : 'mpv';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(44, 26, 44, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.settings_rounded, color: C.accent, size: 28),
                  SizedBox(width: 12),
                  Text('Settings', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 26),
              const Text('VIDEO PLAYER',
                  style: TextStyle(fontSize: 13, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 12),
              SizedBox(
                width: 760,
                child: Column(
                  children: [
                    if (exo)
                      _option(
                        autofocus: engine == 'exo',
                        selected: engine == 'exo',
                        icon: Icons.smart_display_rounded,
                        title: 'Google ExoPlayer  (recommended)',
                        text: 'Uses the TV\'s own video chip: smooth picture, quick channel changes. Default.',
                        onTap: () => _set('exo'),
                      ),
                    const SizedBox(height: 10),
                    _option(
                      autofocus: engine == 'mpv',
                      selected: engine == 'mpv',
                      icon: Icons.memory_rounded,
                      title: 'MPV Player',
                      text: 'Plays almost every format. Choose it if a channel or film will not play well.',
                      onTap: () => _set('mpv'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const SizedBox(
                width: 760,
                child: Text(
                  'Whatever you choose, when a video will not start on that player the app tries the other '
                  'one by itself. The next video starts again on your choice.',
                  style: TextStyle(fontSize: 13.5, color: C.dim, height: 1.5),
                ),
              ),
              if (engine == 'mpv') ...[
                const SizedBox(height: 26),
                const Text('MPV PICTURE MODE',
                    style: TextStyle(fontSize: 13, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _chip('Direct (lighter)', Store.videoMode == 'direct', () => _setMode('direct')),
                    const SizedBox(width: 10),
                    _chip('Standard', Store.videoMode == 'gpu', () => _setMode('gpu')),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Use Standard if a video plays sound but shows no picture.',
                    style: TextStyle(fontSize: 13, color: C.dim)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _set(String engine) {
    Store.setEngine(engine);
    log('settings engine=$engine');
    setState(() {});
  }

  void _setMode(String mode) {
    Store.setVideoMode(mode);
    log('settings video mode=$mode');
    setState(() {});
  }

  Widget _option({
    required bool autofocus,
    required bool selected,
    required IconData icon,
    required String title,
    required String text,
    required VoidCallback onTap,
  }) {
    return TvFocus(
      autofocus: autofocus,
      selected: selected,
      radius: 12,
      color: C.panel,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: selected ? C.accent : C.dim, size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(text, style: const TextStyle(fontSize: 13, color: C.dim)),
                ],
              ),
            ),
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? C.accent : C.dim),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return TvFocus(
      selected: selected,
      radius: 20,
      color: C.panel,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        child: Text(label, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
      ),
    );
  }
}
