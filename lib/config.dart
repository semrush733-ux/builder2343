/// App-wide settings.
const String kAppName = 'B1G';

/// When the build sets a server address (config/server.txt), the login screen
/// hides the server field and customers only type username and password.
const String kLockedServer = String.fromEnvironment('B1G_SERVER');

/// Only used by the automated emulator test.
const String kPrefillServer = String.fromEnvironment('B1G_PREFILL_SERVER');
const String kPrefillUser = String.fromEnvironment('B1G_PREFILL_USER');
const String kPrefillPass = String.fromEnvironment('B1G_PREFILL_PASS');

/// Sent with every request, so the server can recognise the app.
const String kUserAgent = 'B1G/1.0 (Android TV)';
