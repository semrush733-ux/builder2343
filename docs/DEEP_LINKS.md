# Deep links (Android App Links / iOS Universal Links)

Goal: a link such as `https://bill.bwpexperts.com/invoices/123` opens inside the BWP Billing app.

The app side is prepared. Links only start opening the app after the two files below are
published on the server - until then they simply open in the browser as before.

## What is already in the project

- Android: `scripts/configure-native.mjs` adds an `autoVerify` intent filter for every host in
  `allowedHosts` to `android/app/src/main/AndroidManifest.xml`.
- Android + iOS: the native plugin loads an incoming link in the web view, but only if it is
  `https` and its host is in `allowedHosts`.

## Android - publish `assetlinks.json`

1. Take `native-config/deep-links/assetlinks.json.template`.
2. Replace the fingerprints with the SHA-256 of
   - your upload / release key: `keytool -list -v -keystore bwp-billing-release.jks -alias bwp-billing`
   - the Play App Signing key (Play Console > Setup > App signing), if you publish through Google Play.
3. Publish it at `https://bill.bwpexperts.com/.well-known/assetlinks.json`
   (content type `application/json`, no redirect, no login).
4. Check on a phone: `adb shell pm get-app-links com.bwpexperts.billing` should show `verified`.

## iOS - publish `apple-app-site-association`

1. Take `native-config/deep-links/apple-app-site-association.template` and replace
   `REPLACE_WITH_TEAM_ID` with your Apple Team ID.
2. Publish it at `https://bill.bwpexperts.com/.well-known/apple-app-site-association`
   (no file extension, content type `application/json`, no redirect, no login).
3. In Xcode: target **App** > **Signing & Capabilities** > **+ Capability** > **Associated Domains**
   and add `applinks:bill.bwpexperts.com`.

## If the intent filter has to be added by hand (Android)

Inside the `<activity ... android:name=".MainActivity">` element:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https" android:host="bill.bwpexperts.com" />
</intent-filter>
```
