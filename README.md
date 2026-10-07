# BWP Billing - mobile app (Android + iOS)

Native mobile app for **BWP Billing** by **BWP Experts**, built with Ionic Capacitor.

The existing website **https://bill.bwpexperts.com/** stays the backend and the main application.
This project does not contain or change any billing logic, database or API - it is a native shell
around the website that adds what a browser tab cannot do.

| | |
|---|---|
| App name | BWP Billing |
| Android package / iOS bundle ID | `com.bwpexperts.billing` |
| Website | `https://bill.bwpexperts.com/` |
| Start page of the app | `https://bill.bwpexperts.com/login` (the site root is an empty page for logged-out visitors) |
| Capacitor | 8.x |

---

## Build status - read this first

Builds are made in the cloud by GitHub Actions (`.github/workflows/`): Android on Linux, iOS on a
Mac with Xcode. No Mac or Android Studio of your own is needed for a build.

| Part | Status |
|---|---|
| Android: debug APK, release APK, release AAB | **Built in CI.** Release files are unsigned until a keystore is added (section 6) |
| iOS: Xcode project, simulator build, device archive, IPA | **Built in CI.** The IPA is unsigned until Apple signing is added (section 9) |
| Android app on an emulator | Smoke-tested in CI on every build (`scripts/ci/android_smoke.py`), result in the release notes |
| iOS app on a simulator | Smoke-tested in CI on every build (`scripts/ci/ios_smoke.sh`), result in the release notes |
| Launch / offline / error screens and bridge script (`src/`) | Tested in a browser against a mock site (`tests/`, 36 checks) |
| **Real phone** (Android or iPhone) | **Not tested** |
| **Logged-in flows** on the real site (sales, refunds, expenses, uploads, invoices...) | **Not tested** - the tests never log in. Use `docs/TEST_CHECKLIST.md` |

### Where the builds are

Every push to `main` builds both apps and replaces these two releases of the repository:

- `.../releases/tag/android-latest` - `app-debug.apk`, `app-release-unsigned.apk` (or signed `app-release.apk`), `app-release.aab`, `android-studio-project.zip`
- `.../releases/tag/ios-latest` - `BWP-Billing-unsigned.ipa` (or signed `BWP-Billing.ipa`), `ios-xcode-project.zip`

The release notes contain the build report (versions, permissions, bundle contents) and the smoke
test result. Screenshots from the smoke tests are on the branches `ci-smoke-android` and `ci-smoke-ios`.

### Installing the unsigned IPA on your own iPhone

An unsigned IPA cannot be installed directly. Use a sideloading tool on a PC, for example
Sideloadly or AltStore: give it the IPA and your Apple ID and it signs and installs the app.
With a free Apple ID the app runs for 7 days and then has to be installed again; with a paid Apple
Developer account, add the secrets from section 9 and the build produces a signed IPA instead.

---

## 1. Project overview

```
bwp-billing-app/
  capacitor.config.ts        Capacitor configuration (reads src/app-config.json)
  package.json
  src/                       Web assets bundled inside the app
    app-config.json            production URL, allowed hosts, colours  <- single place to edit
    index.html                 launch screen ("Loading your dashboard...")
    error.html                 "No Internet Connection" / "We couldn't connect" screen
    shell.css, shell.js        logic + style of those two screens
    bwp-bridge.js              script injected into the website (downloads, print, share...)
    logo.png
  assets/                    logo + icon / splash source images
  plugins/bwp-native/        ALL custom native code, as a local Capacitor plugin
    android/...                Java  (BwpNativePlugin, BwpChromeClient, ...)
    ios/...                    Swift (BwpNativePlugin)
  scripts/                   setup, native configuration, Gradle helper, brand images
  native-config/             release-signing Gradle file, keystore example, deep-link templates
  docs/                      push notifications, deep links, test checklist
  tests/                     browser test for src/ (optional, needs Python + Playwright)
  .github/workflows/         cloud builds (android.yml, ios.yml)
  android/                   created by the build / "npm run setup"  (Android Studio project, not committed)
  ios/                       created by the build / "npm run setup"  (Xcode project, not committed)
```

How it works:

1. The app starts on a local page (`src/index.html`) - the branded loading screen.
2. If the phone is online it replaces itself with the start page (`homeUrl`, currently `https://bill.bwpexperts.com/login`). Login, cookies,
   localStorage, sessionStorage, AJAX and CSRF tokens work exactly as in a browser, because the
   website runs unchanged in the system web view (Android System WebView / WKWebView).
3. The native plugin injects `bwp-bridge.js` into the website and provides the native features.
   The website talks to the plugin through a channel that the plugin opens only for the hosts in
   `allowedHosts` over https (`window.bwpNative` on Android, `webkit.messageHandlers.bwpNative` on iOS).
4. If a page cannot load, Capacitor shows `src/error.html` instead of the browser error.

Native features:

| Feature | Android | iOS |
|---|---|---|
| Splash screen, app icon | yes | yes |
| Loading screen, offline screen, server-error screen with Retry | yes | yes |
| Auto-reconnect when internet returns | yes | yes |
| Back navigation | Back button: history, then "Press back again to exit" | swipe from left edge |
| Pull-to-refresh | yes (not while a modal / inner list is scrolled) | yes |
| External links (WhatsApp, tel:, mailto:, maps, other sites) open outside the app | yes | yes |
| Downloads (PDF, CSV, Excel, images, blob: files) | saved to `Downloads/BWP Billing`, then Open / Share | Quick Look preview with Share / Save to Files / Print |
| Print (`window.print()`) | native print dialog (also "Save as PDF") | AirPrint dialog |
| Share (`navigator.share`) | native share sheet | native share sheet |
| File upload: camera, gallery, files | one chooser with all three | system menu |
| Safe areas (notch, Dynamic Island, status / navigation bar) | yes | yes |
| Status bar colour follows the page | yes | yes |
| Keyboard never hides the focused field | yes | yes |
| Deep links `https://bill.bwpexperts.com/...` | prepared | prepared |
| Screenshot blocking per screen | prepared, off | hook only |
| Push notifications | documented, not built | documented, not built |

## 2. Requirements

**Android build (Windows, macOS or Linux)**

- Node.js 22 or newer
- JDK 21
- Android Studio (current stable) with Android SDK Platform 36 and Build-Tools
- `ANDROID_HOME` set, or open the project once in Android Studio so it writes `android/local.properties`

**iOS build (macOS only - Apple does not allow building iOS apps on Windows)**

- A Mac with the Xcode version required by Capacitor 8 (https://capacitorjs.com/docs/ios)
- Node.js 22 or newer
- An Apple Developer Program membership (needed for TestFlight / App Store / IPA)

## 3. Installation

```bash
cd bwp-billing-app
npm install
npm run setup
```

`npm run setup` creates `android/` and `ios/` (if missing), generates every icon and splash size,
copies the web assets and applies the BWP settings (`scripts/configure-native.mjs`).
It is safe to run again.

On Windows the `ios/` folder is still created (it is only files); it can be opened and built on a Mac later.
If it could not be created, run `npx cap add ios && npm run sync` on the Mac.

## 4. Development commands

| Command | What it does |
|---|---|
| `npm install` | install dependencies |
| `npm run setup` | first-time setup (see above) |
| `npm run sync` | `npx cap sync` + re-apply BWP native settings. **Run after every change in `src/`, `capacitor.config.ts` or the plugin** |
| `npx cap sync android` / `npx cap sync ios` | sync one platform only |
| `npx cap open android` / `npm run android:open` | open Android Studio |
| `npx cap open ios` / `npm run ios:open` | open Xcode (Mac) |
| `npm run android:debug` | build the debug APK |
| `npm run android:release:apk` | build the release APK |
| `npm run android:release:aab` | build the release AAB |
| `npm run brand` | rebuild icons / splash from `assets/logo.png` |
| `npm run doctor` | check the Capacitor installation |

Debugging the web view: debug builds can be inspected from desktop Chrome at `chrome://inspect`
(Android) or Safari > Develop (iOS). Release builds cannot - web view debugging and Capacitor
logging are off in release builds.

## 5. Android build

```bash
npm run android:debug
```

Output: `android/app/build/outputs/apk/debug/app-debug.apk`

Or in Android Studio: `npm run android:open`, then Run. SDK levels are set in
`android/variables.gradle` by the Capacitor 8 template (target/compile SDK 36, min SDK 24 at the
time of writing) - keep the target SDK at the level Google Play currently requires.

## 6. Android signed release

Create a keystore **once** and keep it forever (you need the same key for every update):

```bash
cd android
keytool -genkeypair -v -keystore bwp-billing-release.jks -alias bwp-billing -keyalg RSA -keysize 2048 -validity 10000
```

Then copy `android/keystore.properties.example` to `android/keystore.properties` and fill it in:

```properties
storeFile=bwp-billing-release.jks
storePassword=your-store-password
keyAlias=bwp-billing
keyPassword=your-key-password
```

- `keystore.properties`, `*.jks` and `*.keystore` are in `.gitignore` - **never commit them**.
- Back up the `.jks` file and both passwords somewhere safe. If they are lost, the app cannot be updated with that key.
- Signing is wired through `android/app/bwp-signing.gradle`; without `keystore.properties` release builds are simply unsigned.

```bash
npm run android:release:apk
```

Output: `android/app/build/outputs/apk/release/app-release.apk`

Before each store upload raise `versionCode` (and `versionName`) in `android/app/build.gradle`.

**Signed builds in the cloud:** add these repository secrets (Settings > Secrets and variables >
Actions) and the Android workflow signs the release APK and AAB:
`ANDROID_KEYSTORE_BASE64` (the `.jks` file as one base64 line), `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

## 7. AAB generation

```bash
npm run android:release:aab
```

Output: `android/app/build/outputs/bundle/release/app-release.aab` - this is the file to upload to
Google Play Console. With Play App Signing your keystore is the *upload key*.

## 8. iOS build (on a Mac)

```bash
npm install
npx cap sync ios
node scripts/configure-native.mjs
npx cap open ios
```

In Xcode choose an iPhone simulator or a connected iPhone and press Run.

`scripts/configure-native.mjs` adds to `ios/App/App/Info.plist`: camera / photo library / microphone
usage texts (required for upload fields), Files-app visibility of downloads, and the
export-compliance flag.

The same steps run in the cloud in `.github/workflows/ios.yml` (Xcode 26), where the project
compiles and archives without errors.

## 9. Xcode signing

In Xcode select the **App** project > target **App** > **Signing & Capabilities**:

| Setting | Where | Value |
|---|---|---|
| Apple Team | *Team* drop-down | your Apple Developer team |
| Bundle ID | *Bundle Identifier* | `com.bwpexperts.billing` (already set) |
| Signing Certificate | handled by *Automatically manage signing* | Apple Development / Apple Distribution |
| Provisioning Profile | handled by *Automatically manage signing* | or pick a manual profile for `com.bwpexperts.billing` |

The App ID `com.bwpexperts.billing` must exist in your Apple Developer account (Xcode creates it
with automatic signing). Display name, version and build number are on the **General** tab.

**Signed IPA in the cloud (no Mac):** add these repository secrets and the iOS workflow archives
with automatic signing and exports `BWP-Billing.ipa` for TestFlight / App Store:
`APPLE_TEAM_ID`, `APPSTORE_API_KEY_ID`, `APPSTORE_API_ISSUER_ID`, `APPSTORE_API_KEY_P8`
(App Store Connect > Users and Access > Integrations > App Store Connect API, role Admin or App Manager).
This signed path has not been exercised yet because no Apple account was available.

## 10. IPA / TestFlight process

1. In Xcode pick the destination **Any iOS Device (arm64)**.
2. **Product > Archive**.
3. In the Organizer: **Distribute App**.
   - **App Store Connect** - upload for TestFlight / App Store.
   - **Release Testing / Ad Hoc / Development** - export an `.ipa` file.
4. In App Store Connect create the app record (bundle ID `com.bwpexperts.billing`) and add testers in TestFlight.

Raise the build number for every upload.

## 11. App icon replacement

1. Replace `assets/logo.png` (transparent PNG, 1024 px or larger, square canvas preferred).
2. `npm run brand`
3. `npm run sync`

`npm run brand` builds `icon-only.png`, `icon-foreground.png`, `icon-background.png` from the logo
(scaled proportionally, never stretched) and then generates every Android / iOS size.

## 12. Splash screen replacement

The splash is built by the same command from the logo, `appName`, `company`, `brandColor` and
`backgroundColor` in `src/app-config.json`. For a fully custom splash, replace
`assets/splash.png` and `assets/splash-dark.png` (2732 x 2732, important content in the middle
third) and run `npx capacitor-assets generate --android --ios` followed by `npm run sync`.

Android 12 and newer always show the app icon on a plain background as the system splash; the
full "BWP Billing / by BWP Experts" artwork appears immediately after on the launch screen.

## 13. Production URL configuration

Everything is in **`src/app-config.json`**:

```json
{
  "homeUrl": "https://bill.bwpexperts.com/login",
  "allowedHosts": ["bill.bwpexperts.com"],
  "brandColor": "#014F4A",
  "backgroundColor": "#FFFFFF",
  "pullToRefresh": true,
  "downloadExtensions": ["pdf", "csv", "xls", "xlsx", "doc", "docx", "zip"],
  "secureScreenPaths": []
}
```

- `homeUrl` - the page the app opens first. It must be a page a logged-out user can use
  (the login page, or a page that redirects to it).
- `allowedHosts` - hosts that load **inside** the app. Everything else opens in the phone's browser
  or the matching app. If login or payment redirects through another domain that must stay in the
  app, add it here.
- `secureScreenPaths` - path prefixes (for example `"/reports"`) where screenshots are blocked on Android. Empty = never.
- Run `npm run sync` after editing.

Only `https://` is accepted. Cleartext `http://`, mixed content and invalid certificates are blocked
and there is no certificate bypass anywhere in the project.

## 14. Troubleshooting

| Problem | Fix |
|---|---|
| `npm install` fails on a `@capacitor/...` version | Run `npm view @capacitor/core version`, put that major version on every `@capacitor/*` package in `package.json`, install again |
| `SDK location not found` | Open `android/` once in Android Studio or set `ANDROID_HOME` |
| Gradle / JDK version errors | Use JDK 21 (Android Studio > Settings > Build Tools > Gradle > Gradle JDK) |
| White screen, or "bwp-bridge.js not found" in Logcat | `npm run sync` |
| Users are logged out every time the app is closed | The server sends a session cookie without an expiry date. Give the login cookie a lifetime (or enable "remember me") on the server; the app keeps any cookie that has an expiry |
| A page shows "We couldn't connect" although the internet works | On Android any HTTP error status on a full page load (404, 403, 500) shows this screen. Check the URL in a browser |
| Download does nothing | Files returned by a form `POST` cannot be re-fetched by the app. Offer them as a normal link (GET) on the server |
| iOS: a file downloaded without a visible link shows no dialog | It is saved by Capacitor into the app's folder in the Files app ("On My iPhone > BWP Billing") |
| Upload field offers no camera | Android: only for inputs that accept images. iOS: needs the Info.plist usage texts (`node scripts/configure-native.mjs`) |
| Content under the status bar / keyboard covers a field | Report the device and Android version; logic is in `BwpNativePlugin.applySafeArea()` |
| Pull-to-refresh fires inside a custom scroll area | Add the attribute `data-no-pull-refresh` to that element on the website, or set `"pullToRefresh": false` |
| Link should stay in the app but opens the browser | Add its host to `allowedHosts` |

## 15. Updating Capacitor / plugins later

```bash
npm outdated
npm install @capacitor/core@latest @capacitor/android@latest @capacitor/ios@latest @capacitor/cli@latest
npm install @capacitor/splash-screen@latest @capacitor/keyboard@latest
npm run sync
```

Keep every `@capacitor/*` package on the same major version. For a new major version follow the
official migration guide (`npx cap migrate`) and re-test with `docs/TEST_CHECKLIST.md`.

Website changes need **no** app update - the content is served by your server. A new store release
is only needed when something in this project changes (native code, icons, `src/`, Capacitor).

The website is not cached for offline use: the app uses the normal browser cache rules sent by
your server, so billing data is always fetched fresh.

---

## What needs your credentials

**Android** - your release keystore and its passwords (section 6); a Google Play Console account to publish.

**Apple** - an Apple Developer Program account, your Team selected in Xcode (section 9), and App
Store Connect access for TestFlight / App Store.

**Push notifications (later)** - Firebase project files and an Apple APNs key, see `docs/PUSH_NOTIFICATIONS.md`.

Nothing secret is stored in this project: no passwords, no API keys, no signing keys.
