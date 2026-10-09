import 'package:flutter/material.dart';

import '../backend.dart';
import '../theme.dart';

/// Web version of the update window. A browser cannot install an APK, so this
/// only tells the viewer that a newer app exists and where to get it. The file
/// is swapped in by the conditional import in home.dart / device.dart:
///   import 'update_web.dart' if (dart.library.io) 'update.dart';
Future<void> showUpdateDialog(BuildContext context, BUpdate update) {
  UpdateDialog.showing = true;
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.panel,
      title: Text('Version ${update.versionName} is out'),
      content: Text(
        update.notes.isEmpty
            ? 'A newer B1G app is available for your TV and Android devices. Install it from our website.'
            : update.notes,
        style: const TextStyle(color: C.dim, height: 1.4),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  ).whenComplete(() => UpdateDialog.showing = false);
}

/// Keeps the same name and static flag as the Android implementation.
class UpdateDialog {
  static bool showing = false;
}
