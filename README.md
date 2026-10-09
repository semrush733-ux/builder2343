# B1G - IPTV player for Fire TV / Android TV

Flutter app, package `com.b1g.b1gtv`. It is a player only: it contains no channels and no server
address. The customer signs in with the details of their IPTV account (Xtream Codes API).

| | |
|---|---|
| Sign in | Server address, username, password - or paste a playlist link (`.../get.php?username=..&password=..`) |
| Live TV | Categories, channel list, search, favourites, TV guide (now / next) |
| Movies / Series | Poster grid, seasons and episodes, resume where you stopped, next episode starts by itself |
| Player | ExoPlayer with hardware decoding, automatic reconnect, `.ts` with fallback to `.m3u8` |
| Remote | Everything works with the D-pad. Hold OK = favourite. In the player: Up / Down = channel, Left / Right = jump |

## Where the build is

Every push to the branch `b1g-tv` builds the app in the cloud (`.github/workflows/b1g-tv.yml`) and
replaces the file in this release:

`https://github.com/semrush733-ux/builder2343/releases/tag/b1g-latest` -> `B1G.apk`

The release notes hold the build report and the result of the emulator test. Screenshots of that
test are on the branch `ci-smoke-b1g`.

## Lock the app to one server

Put the server address into `config/server.txt` (one line, for example `http://example.com:8080`)
and push. The sign-in screen then only asks for username and password.

## Signing

Without signing secrets every build is signed with a new throw-away key: the APK installs, but a
newer build cannot be installed over an older one (uninstall first). Before the APK goes to
customers, add a keystore as repository secrets (`ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) and keep that keystore
safe - updates must always be signed with the same key.

## Project layout

```
lib/                    the app (Dart)
  xtream.dart           server API
  store.dart            saved login, favourites, resume positions
  screens/              login, home, browse, series, player
android_overlay/        TV manifest, activity, icons and banner (copied over Flutter's Android template)
config/server.txt       optional fixed server address
ci/                     mock IPTV server and emulator test
test/                   unit tests
```

## Not in this version

Plain M3U playlists without an Xtream login, a full-week TV guide grid, subtitles / audio-track
menu, catch-up, parental PIN, iPhone / Samsung / LG builds.
