import 'package:flutter/material.dart';

import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

/// Asks for the parental PIN. True when it was right (locked categories then stay open until
/// the app is closed), or when no PIN is set at all.
Future<bool> askParentalPin(BuildContext context, {String title = 'Enter parental PIN'}) async {
  final pin = Store.parentalPin;
  if (pin.isEmpty || Store.parentalUnlocked) return true;
  final controller = TextEditingController();
  String error = '';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, refresh) {
        void check(String value) {
          if (value.trim() == pin) {
            Navigator.of(ctx).pop(true);
          } else {
            refresh(() => error = 'Wrong PIN, please try again.');
            controller.clear();
          }
        }

        return AlertDialog(
          backgroundColor: C.panel,
          title: Row(
            children: [
              const Icon(Icons.lock_rounded, color: C.accent),
              const SizedBox(width: 10),
              Text(title),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TvField(
                  controller: controller,
                  label: 'PIN',
                  icon: Icons.pin_rounded,
                  obscure: true,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  action: TextInputAction.done,
                  onSubmitted: check,
                ),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(error, style: const TextStyle(color: C.danger, fontSize: 13.5)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => check(controller.text), child: const Text('OK')),
          ],
        );
      },
    ),
  );
  controller.dispose();
  if (ok == true) Store.parentalUnlocked = true;
  return ok == true;
}

/// Asks for a new 4–8 digit PIN twice. Returns it, or null when cancelled.
Future<String?> askNewPin(BuildContext context) async {
  final first = TextEditingController();
  final second = TextEditingController();
  final secondNode = FocusNode();
  String error = '';
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, refresh) {
        void save() {
          final a = first.text.trim();
          final b = second.text.trim();
          if (!RegExp(r'^\d{4,8}$').hasMatch(a)) {
            refresh(() => error = 'Use 4 to 8 digits.');
          } else if (a != b) {
            refresh(() => error = 'The two PINs are not the same.');
          } else {
            Navigator.of(ctx).pop(a);
          }
        }

        return AlertDialog(
          backgroundColor: C.panel,
          title: const Text('New parental PIN'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TvField(
                  controller: first,
                  label: 'PIN (4–8 digits)',
                  icon: Icons.pin_rounded,
                  obscure: true,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => secondNode.requestFocus(),
                ),
                const SizedBox(height: 10),
                TvField(
                  controller: second,
                  focusNode: secondNode,
                  label: 'Same PIN again',
                  icon: Icons.pin_rounded,
                  obscure: true,
                  keyboardType: TextInputType.number,
                  action: TextInputAction.done,
                  onSubmitted: (_) => save(),
                ),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(error, style: const TextStyle(color: C.danger, fontSize: 13.5)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            TextButton(onPressed: save, child: const Text('Save')),
          ],
        );
      },
    ),
  );
  first.dispose();
  second.dispose();
  secondNode.dispose();
  return result;
}
