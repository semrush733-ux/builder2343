import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../backend.dart';
import '../theme.dart';
import '../widgets.dart';

/// Wraps the whole app: lets it run while the licence is trial/active and
/// shows the activation screen when it is expired or suspended.
class LicenseGate extends StatefulWidget {
  const LicenseGate({super.key, required this.child});
  final Widget child;

  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
    // Re-check twice a day while the app stays on.
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
    await Backend.ensureRegistered();
    await Backend.refreshStatus();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!Backend.allowed) {
      return ActivationScreen(onUnlocked: () => setState(() {}));
    }
    return widget.child;
  }
}

/// Full-screen activation page: shown when the trial ended or the device was
/// suspended. The customer sees the Device ID, a QR code to the website and a
/// field to type an activation code.
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _code = TextEditingController();
  final _codeNode = FocusNode();
  final _buttonNode = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    log('screen=activation status=${Backend.licStatus}');
  }

  @override
  void dispose() {
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
      log('activation ok');
      widget.onUnlocked();
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
                    DeviceCard(showPairing: false),
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
/// and in the "Device" dialog on the home screen.
class DeviceCard extends StatelessWidget {
  const DeviceCard({super.key, this.showPairing = true, this.compact = false});

  final bool showPairing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!Backend.registered) {
      return const Text('Connecting to the B1G service…',
          style: TextStyle(color: C.dim, fontSize: 13));
    }
    final qrSize = compact ? 120.0 : 148.0;
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
            child: QrImageView(
              data: showPairing ? Backend.uploadUrl : Backend.activationUrl,
              version: QrVersions.auto,
              size: qrSize,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('DEVICE ID',
                    style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: C.dim, fontWeight: FontWeight.w700)),
                Text(Backend.deviceId,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                if (showPairing) ...[
                  const SizedBox(height: 8),
                  const Text('PAIRING CODE',
                      style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: C.dim, fontWeight: FontWeight.w700)),
                  Text(Backend.pairingCode,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                ],
                if (Backend.statusLine.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(Backend.statusLine, style: const TextStyle(fontSize: 13, color: C.dim)),
                ],
                const SizedBox(height: 8),
                Text(
                  showPairing
                      ? 'Scan with your phone to add\nyour playlist to this TV.'
                      : 'Scan with your phone to activate\nthis device on our website.',
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
