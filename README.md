# Block Merge 2048

Block merge puzzle (drop numbered blocks, same numbers merge and double) with weekly 200-player leagues.
HTML5 + vanilla JS in `www/`, packaged for Android and iOS with Capacitor 7.

## Features

Classic + Time Attack (2 min) modes, bomb and star (wild) blocks, Hammer / Swap / Undo, combos with blast/flower/confetti
effects, synthesized sound effects + music, first-game tutorial, settings, daily reward (7-day streak), lucky spin,
daily challenge, 17 missions, shop (6 block skins, 5 board themes), statistics, score sharing, weekly 200-player League
(simulated players for now), AdMob rewarded + interstitial ads, Android back button, reminder notifications.

## Ads (AdMob)

`ads.json` holds the ad IDs. It ships with Google's **test IDs** (`"testing": true`). Before publishing, create an app
in AdMob, put your real App IDs and ad unit IDs in `ads.json`, set `"testing": false` and push.

## Builds (GitHub Actions)

Every push to the `block-merge-2048` branch runs **Build APK + IPA** (`.github/workflows/build.yml`) and publishes a Release with:

| File | What it is |
|---|---|
| `BlockMerge2048.apk` | Android install file |
| `BlockMerge2048.aab` | Google Play upload (only when the release key secrets are set) |
| `BlockMerge2048-unsigned.ipa` | iOS build, needs signing before it installs on an iPhone |

You can also start a build by hand: **Actions → Build APK + IPA → Run workflow**.

### Release signing (Android)

Without secrets the workflow builds a **debug APK** (fine for testing). For a Play Store build add these repo secrets
(Settings → Secrets and variables → Actions), the same four used by Cargo Truck Driver:

- `KEYSTORE_BASE64` — the `.jks` file as base64
- `KEYSTORE_PASSWORD`
- `KEY_ALIAS`
- `KEY_PASSWORD`

### Installing the IPA on an iPhone

Apple only installs signed apps. Options:

1. **Sideloadly** or **AltStore** on your PC: sign the `.ipa` with a free Apple ID (app works for 7 days, then re-sign).
2. **Apple Developer account** ($99/year): proper signing, TestFlight and App Store.

## Local Android build (Windows)

Needs Node 22, JDK 21 and Android Studio.

```
npm install
npm run android
```

This copies the font, writes the ad config, creates the `android/` project, applies icon/splash/portrait and opens Android Studio.

## Project layout

- `www/index.html` — the whole game (blocks, effects, league)
- `assets/` — app icon (1024) and splash images
- `android-overrides/res/` — Android launcher icons
- `ads.json` — AdMob app + ad unit IDs
- `tools/` — prepare script (font + ad config) and Android/iOS patch scripts
