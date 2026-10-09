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

/// Extra engine messages in the device log (test builds only).
const bool kVerbose = bool.fromEnvironment('B1G_VERBOSE');

/// Test builds: stay in the standard picture mode even when it cannot draw (the emulator has no
/// graphics chip), so the automated test can exercise every screen.
const bool kNoAutoDirect = bool.fromEnvironment('B1G_NO_AUTO_DIRECT');

/// TMDB (themoviedb.org) adds cast photos, stills and trailers to the movie details page.
/// The key comes from the build (repository secret TMDB_API_KEY); without it the page shows
/// only what the IPTV server itself knows.
const String kTmdbKey = String.fromEnvironment('B1G_TMDB_KEY');
const String kTmdbBase = String.fromEnvironment('B1G_TMDB_BASE', defaultValue: 'https://api.themoviedb.org/3');
const String kTmdbImages = String.fromEnvironment('B1G_TMDB_IMAGES', defaultValue: 'https://image.tmdb.org/t/p');
