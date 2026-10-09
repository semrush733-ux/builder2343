import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../backend.dart';
import '../start.dart';
import '../theme.dart';
import '../widgets.dart';
import 'update.dart';

/// Sits above every screen: checks the licence and the website settings at start, whenever the
/// app comes back to the front and a few times a day. Opens the activation screen when the
/// licence ended and offers a newer version of the app when the website announces one.
class AppGate extends StatefulWidget {
  const AppGate({super.key, required this.child});
  final Widget child;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> with WidgetsBindingObserver {
  Timer? _timer;
  bool _checking = false;
  int _promptedFor = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
    _timer = Timer.periodic(const Duration(hours: 6), (_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      await Backend.ensureRegistered();
      await Future.wait([Backend.refreshStatus(), Backend.loadConfig()]);
    } finally {
      _checking = false;
    }
    if (mounted) _act();
  }

  void _act() {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    if (!Backend.allowed) {
      // Closes whatever is open (a running stream too) and shows the activation screen.
      if (!ActivationScreen.showing) {
        nav.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const ActivationScreen()),
          (_) => false,
        );
      }
      return;
    }
    final update = Backend.update;
    if (update == null || !Backend.updateAvailable || UpdateDialog.showing) return;
    if (_promptedFor == update.versionCode && !update.force) return;
    // Never interrupt a film for an ordinary update: it is offered on the home or sign-in screen
    // (the home screen also keeps an "Update" button).
    if (!update.force && nav.canPop()) return;
    final overlay = nav.overlay;
    if (overlay == null) return;
    _promptedFor = update.versionCode;
    log('update prompt version=${update.versionCode}');
    showUpdateDialog(overlay.context, update);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Full-screen activation page: shown when the trial ended or the device was
/// suspended. The customer sees the Device ID, a QR code to the website and a
/// field to type an activation code.
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  /// True while this screen is open.
  static bool showing = false;

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _code = TextEditingController();
  final _codeNode = FocusNode();
  final _buttonNode = FocusNode();
  bool _busy = false;
  String? _error;

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    ActivationScreen.showing = true;
    log('screen=activation status=${Backend.licStatus}');
    // The customer may activate on the website (QR code): notice it without a restart.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (_busy) return;
      await Backend.refreshStatus();
      if (mounted && Backend.allowed) _unlock();
    });
  }

  void _unlock() {
    log('activation ok');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => startScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    ActivationScreen.showing = false;
    _poll?.cancel();
    _code.dispose();
    _codeNode.dispose();
    _buttonNode.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_busy) return;
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Please enter your activation code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _buttonNode.requestFocus();
    final error = await Backend.activate(code);
    if (!mounted) return;
    if (error == null && Backend.allowed) {
      _unlock();
    } else {
      setState(() {
        _busy = false;
        _error = error ?? 'Activation did not complete. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final suspended = Backend.licStatus == 'suspended';
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1B1F2A), C.bg],
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 48),
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Logo(size: 54),
                    const SizedBox(height: 22),
                    Text(
                      suspended ? 'This device is suspended.' : 'Your free trial has ended.',
                      style: const TextStyle(fontSize: 24, height: 1.3, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      suspended
                          ? 'Please contact support to restore access.'
                          : 'Activate once and keep watching — no monthly fees.',
                      style: const TextStyle(fontSize: 15, color: C.dim),
                    ),
                    const SizedBox(height: 24),
                    const DeviceCard(showPairing: false),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Activate this device',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text('Get your code at  ${kSiteBase.replaceFirst('https://', '')}/activation',
                          style: const TextStyle(fontSize: 13.5, color: C.dim)),
                      const SizedBox(height: 14),
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: C.danger.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(_error!, style: const TextStyle(color: C.danger, fontSize: 14)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TvField(
                        controller: _code,
                        focusNode: _codeNode,
                        label: 'Activation code',
                        icon: Icons.vpn_key_rounded,
                        action: TextInputAction.done,
                        onSubmitted: (_) => _activate(),
                      ),
                      const SizedBox(height: 16),
                      TvFocus(
                        focusNode: _buttonNode,
                        color: C.accent,
                        focusBorder: Colors.white,
                        onTap: _activate,
                        child: SizedBox(
                          height: 46,
                          child: Center(
                            child: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                                  )
                                : const Text('Activate',
                                    style: TextStyle(
                                        color: Colors.black, fontSize: 16, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Device ID, pairing code and the QR code that opens the website with this
/// device already connected. Used on the login screen, the activation screen
/// and in the "My device" window on the home screen.
class DeviceCard extends StatelessWidget {
  const DeviceCard({super.key, this.showPairing = true, this.compact = false});

  final bool showPairing;
  final bool compact;

  Widget _value(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(fontSize: 11, letterSpacing: 1.5, color: C.dim, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        // One line, whatever the length: a long ID is drawn smaller instead of being broken up.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Backend.registered) {
      return const Text('Connecting to the B1G service…',
          style: TextStyle(color: C.dim, fontSize: 13));
    }
    final qrSize = compact ? 112.0 : 148.0;
    // On a narrow screen (a phone) the whole card is drawn smaller instead of being cut off.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: _card(qrSize),
    );
  }

  Widget _card(double qrSize) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A303C)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            // The fixed box gives the code its size up front, so the text beside it always
            // gets the rest of the row.
            child: SizedBox(
              width: qrSize,
              height: qrSize,
              child: QrImageView(
                data: showPairing ? Backend.uploadUrl : Backend.activationUrl,
                version: QrVersions.auto,
                size: qrSize,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: compact ? 190 : 230,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _value('DEVICE ID', Backend.deviceId),
                if (showPairing) ...[
                  const SizedBox(height: 10),
                  _value('PAIRING CODE', Backend.pairingCode),
                ],
                if (Backend.statusLine.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(Backend.statusLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: C.accent, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 8),
                Text(
                  showPairing
                      ? 'Scan with your phone to add your playlist to this TV.'
                      : 'Scan with your phone to activate this device on our website.',
                  style: const TextStyle(fontSize: 12, color: C.dim, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The "My device" window of the home screen.
Future<void> showDeviceDialog(BuildContext context) {
  log('screen=device');
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: C.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
        child: IntrinsicWidth(
         child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('My device', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            const DeviceCard(),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    Backend.appVersionName.isEmpty
                        ? 'B1G'
                        : 'B1G ${Backend.appVersionName}  ·  build ${Backend.appVersionCode}',
                    style: const TextStyle(fontSize: 12.5, color: C.dim),
                  ),
                ),
                const SizedBox(width: 16),
                TvFocus(
                  autofocus: true,
                  color: C.accent,
                  focusBorder: Colors.white,
                  onTap: () => Navigator.of(ctx).pop(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 26, vertical: 9),
                    child: Text('Close',
                        style: TextStyle(color: Colors.black, fontSize: 14.5, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ],
         ),
        ),
      ),
    ),
  );
}
