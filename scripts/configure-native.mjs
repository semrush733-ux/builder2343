#!/usr/bin/env node
/*
 * BWP Billing - applies the few project-level settings that cannot live in the plugin.
 * Runs after "cap sync" (npm run sync / npm run setup). Every step is idempotent and only
 * edits a file when the expected text is found; otherwise it prints what to do by hand.
 *
 * Android (android/)
 *   - AndroidManifest.xml : allowBackup=false, App Links intent filter for the allowed hosts
 *   - app/build.gradle    : loads app/bwp-signing.gradle (release signing from keystore.properties)
 *   - styles.xml          : splash background colour on Android 12+
 *   - .gitignore          : keystore files are never committed
 *
 * iOS (ios/App/App/Info.plist)
 *   - camera / photo library usage texts (needed for upload fields)
 *   - downloaded files visible in the Files app
 *   - export-compliance flag (the app only uses standard HTTPS)
 */
import { existsSync, readFileSync, writeFileSync, copyFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const app = JSON.parse(readFileSync(join(root, 'src', 'app-config.json'), 'utf8'));
const hosts = Array.isArray(app.allowedHosts) && app.allowedHosts.length ? app.allowedHosts : ['bill.bwpexperts.com'];
const background = /^#[0-9a-f]{6}$/i.test(app.backgroundColor || '') ? app.backgroundColor : '#FFFFFF';

const done = [];
const manual = [];
const read = (file) => readFileSync(file, 'utf8');
const write = (file, text) => writeFileSync(file, text);

function configureAndroid() {
  const android = join(root, 'android');
  if (!existsSync(android)) {
    console.log('android/ not found - skipping Android configuration.');
    return;
  }

  // --- AndroidManifest.xml
  const manifestFile = join(android, 'app', 'src', 'main', 'AndroidManifest.xml');
  if (existsSync(manifestFile)) {
    let manifest = read(manifestFile);
    const before = manifest;

    if (manifest.includes('android:allowBackup="true"')) {
      // Login cookies must not be copied to cloud backups / other devices.
      manifest = manifest.replace('android:allowBackup="true"', 'android:allowBackup="false"');
      done.push('AndroidManifest: allowBackup set to false');
    } else if (!manifest.includes('android:allowBackup="false"')) {
      manual.push('AndroidManifest.xml: add android:allowBackup="false" to <application>.');
    }

    const marker = '<!-- BWP deep links';
    const markerEnd = '<!-- /BWP deep links -->';
    const dataTags = hosts.map((host) => `                <data android:scheme="https" android:host="${host}" />`).join('\n');
    const filter = [
      `            ${marker}: open https links of the billing site inside the app (see docs/DEEP_LINKS.md) -->`,
      '            <intent-filter android:autoVerify="true">',
      '                <action android:name="android.intent.action.VIEW" />',
      '                <category android:name="android.intent.category.DEFAULT" />',
      '                <category android:name="android.intent.category.BROWSABLE" />',
      dataTags,
      '            </intent-filter>',
      `            ${markerEnd}`,
    ].join('\n');
    if (manifest.includes(marker) && manifest.includes(markerEnd)) {
      const start = manifest.lastIndexOf('\n', manifest.indexOf(marker)) + 1;
      const end = manifest.indexOf(markerEnd) + markerEnd.length;
      manifest = manifest.slice(0, start) + filter + manifest.slice(end);
    } else if (/android:name="(\.|com\.bwpexperts\.billing\.)MainActivity"/.test(manifest) && manifest.includes('</activity>')) {
      const at = manifest.indexOf('</activity>');
      const lineStart = manifest.lastIndexOf('\n', at) + 1;
      manifest = manifest.slice(0, lineStart) + filter + '\n' + manifest.slice(lineStart);
      done.push('AndroidManifest: App Links intent filter added');
    } else {
      manual.push('AndroidManifest.xml: MainActivity not found - add the App Links intent filter from docs/DEEP_LINKS.md.');
    }

    if (manifest !== before) write(manifestFile, manifest);
  } else {
    manual.push('android/app/src/main/AndroidManifest.xml not found.');
  }

  // --- release signing
  const signingSource = join(root, 'native-config', 'android', 'bwp-signing.gradle');
  const appDir = join(android, 'app');
  const gradleFile = join(appDir, 'build.gradle');
  if (existsSync(gradleFile)) {
    copyFileSync(signingSource, join(appDir, 'bwp-signing.gradle'));
    let gradle = read(gradleFile);
    if (!gradle.includes('bwp-signing.gradle')) {
      gradle = gradle.replace(/\s*$/, '\n') + "\n// BWP Billing: release signing from android/keystore.properties (never committed)\napply from: 'bwp-signing.gradle'\n";
      write(gradleFile, gradle);
      done.push('app/build.gradle: release signing hook added');
    }
  } else {
    manual.push('android/app/build.gradle not found (Kotlin DSL project?) - add release signing by hand, see README.');
  }
  copyFileSync(join(root, 'native-config', 'android', 'keystore.properties.example'), join(android, 'keystore.properties.example'));

  // --- splash background (Android 12+ system splash)
  const stylesFile = join(appDir, 'src', 'main', 'res', 'values', 'styles.xml');
  if (existsSync(stylesFile)) {
    let styles = read(stylesFile);
    const launch = /(<style name="AppTheme\.NoActionBarLaunch" parent="Theme\.SplashScreen">)([\s\S]*?)(\n\s*<\/style>)/;
    const item = `<item name="windowSplashScreenBackground">${background}</item>`;
    if (styles.includes('windowSplashScreenBackground')) {
      styles = styles.replace(/<item name="windowSplashScreenBackground">[^<]*<\/item>/, item);
      write(stylesFile, styles);
    } else if (launch.test(styles)) {
      styles = styles.replace(launch, (all, open, body, close) => `${open}${body}\n        ${item}${close}`);
      write(stylesFile, styles);
      done.push('styles.xml: splash background colour set');
    }
  }

  // --- never commit signing material
  const ignoreFile = join(android, '.gitignore');
  const ignoreLines = ['keystore.properties', '*.jks', '*.keystore'];
  let ignore = existsSync(ignoreFile) ? read(ignoreFile) : '';
  const missing = ignoreLines.filter((line) => !ignore.split(/\r?\n/).includes(line));
  if (missing.length) {
    ignore = ignore.replace(/\s*$/, '\n') + '\n# BWP Billing: signing keys stay out of source control\n' + missing.join('\n') + '\n';
    write(ignoreFile, ignore);
    done.push('android/.gitignore: keystore files ignored');
  }
}

function configureIos() {
  const plistFile = join(root, 'ios', 'App', 'App', 'Info.plist');
  if (!existsSync(plistFile)) {
    console.log('ios/App/App/Info.plist not found - skipping iOS configuration.');
    return;
  }
  let plist = read(plistFile);
  const entries = [
    ['NSCameraUsageDescription', '<string>Take a photo of a receipt, payment proof or document to attach it in BWP Billing.</string>'],
    ['NSPhotoLibraryUsageDescription', '<string>Choose a photo of a receipt, payment proof or document to attach it in BWP Billing.</string>'],
    ['NSPhotoLibraryAddUsageDescription', '<string>Save invoices and receipts from BWP Billing to your photo library.</string>'],
    ['NSMicrophoneUsageDescription', '<string>Used only if you record a video to attach in BWP Billing.</string>'],
    ['UIFileSharingEnabled', '<true/>'],
    ['LSSupportsOpeningDocumentsInPlace', '<true/>'],
    ['ITSAppUsesNonExemptEncryption', '<false/>'],
  ];
  const additions = entries
    .filter(([key]) => !plist.includes(`<key>${key}</key>`))
    .map(([key, value]) => `\t<key>${key}</key>\n\t${value}`);
  if (!additions.length) return;
  const end = plist.lastIndexOf('</dict>');
  if (end === -1) {
    manual.push('Info.plist: could not find the closing </dict> - add the usage descriptions by hand (README, iOS section).');
    return;
  }
  plist = plist.slice(0, end) + additions.join('\n') + '\n' + plist.slice(end);
  write(plistFile, plist);
  done.push(`Info.plist: ${additions.length} entr${additions.length === 1 ? 'y' : 'ies'} added`);
}

configureAndroid();
configureIos();

console.log(done.length ? `\nNative configuration applied:\n  - ${done.join('\n  - ')}` : '\nNative configuration is already up to date.');
if (manual.length) {
  console.warn(`\nPlease check by hand:\n  - ${manual.join('\n  - ')}`);
}
