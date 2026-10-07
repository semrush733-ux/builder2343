import type { CapacitorConfig } from '@capacitor/cli';
import { readFileSync } from 'fs';
import { join } from 'path';

/**
 * Capacitor configuration.
 *
 * App name, app ID, production URL, allowed hosts and brand colours live in ONE place:
 *   src/app-config.json
 * That file is read here (for the native projects), by src/shell.js (launch and
 * error screens) and is handed to the injected bridge script by the native plugin.
 * After changing it run:  npm run sync
 */
function loadAppConfig(): any {
  const candidates = [
    join(process.cwd(), 'src', 'app-config.json'),
    join(__dirname, 'src', 'app-config.json'),
  ];
  for (const file of candidates) {
    try {
      return JSON.parse(readFileSync(file, 'utf8'));
    } catch (e) {
      // try the next location
    }
  }
  throw new Error('src/app-config.json not found or invalid JSON');
}

const app = loadAppConfig();

const config: CapacitorConfig = {
  appId: app.appId || 'com.bwpexperts.billing',
  appName: app.appName,
  webDir: 'src',
  backgroundColor: app.backgroundColor,

  // Capacitor console/native logging only in debug builds.
  loggingBehavior: 'debug',

  server: {
    // The local shell (launch + error screens) is served from https://localhost.
    androidScheme: 'https',
    hostname: 'localhost',
    // HTTPS only. Never enable cleartext for this app.
    cleartext: false,
    // Hosts that are allowed to load INSIDE the app. Everything else is handed
    // to the phone's browser / the matching app (WhatsApp, dialer, mail, maps).
    allowNavigation: app.allowedHosts,
    // Shown instead of the raw WebView error (ERR_INTERNET_DISCONNECTED etc.).
    errorPath: 'error.html',
  },

  android: {
    allowMixedContent: false,
    backgroundColor: app.backgroundColor,
    // webContentsDebuggingEnabled is left at its default on purpose:
    // ON for debug builds (chrome://inspect), OFF for release builds.
  },

  ios: {
    // Keep page content out of the notch / Dynamic Island / home indicator.
    contentInset: 'always',
    backgroundColor: app.backgroundColor,
    allowsLinkPreview: false,
    scrollEnabled: true,
  },

  plugins: {
    SplashScreen: {
      launchShowDuration: 700,
      launchAutoHide: true,
      launchFadeOutDuration: 200,
      backgroundColor: app.backgroundColor,
      androidScaleType: 'CENTER_CROP',
      showSpinner: false,
      splashFullScreen: false,
      splashImmersive: false,
    },
    Keyboard: {
      // iOS: resize the web view so fixed footers/modals stay above the keyboard.
      resize: 'native',
      resizeOnFullScreen: false,
    },
    SystemBars: {
      // Safe areas on Android are handled natively by the BwpNative plugin,
      // because the remote website does not use the CSS inset variables.
      insetsHandling: 'disable',
    },
    // Read by plugins/bwp-native (Android + iOS).
    BwpNative: {
      appName: app.appName,
      homeUrl: app.homeUrl,
      allowedHosts: app.allowedHosts,
      brandColor: app.brandColor,
      backgroundColor: app.backgroundColor,
      pullToRefresh: app.pullToRefresh !== false,
      downloadExtensions: app.downloadExtensions,
      secureScreenPaths: app.secureScreenPaths,
      exitMessage: 'Press back again to exit',
    },
  },
};

export default config;
