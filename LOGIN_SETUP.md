# Login setup (Google, Facebook, Apple) + Cloud Save

The game already contains the login screen, cloud save and the build steps.
Login switches on automatically as soon as these GitHub secrets exist
(repo **Settings → Secrets and variables → Actions → New repository secret**).
Until then the app works exactly as before (guest play).

| Secret | What to paste |
|---|---|
| `FIREBASE_ANDROID_JSON` | Full content of `google-services.json` |
| `FIREBASE_IOS_PLIST` | Full content of `GoogleService-Info.plist` |
| `FACEBOOK_APP_ID` | Facebook App ID (numbers) |
| `FACEBOOK_CLIENT_TOKEN` | Facebook Client Token |

## 1. Firebase project (free)

1. Go to https://console.firebase.google.com → **Add project** → name it `Block Merge 2048`.
2. **Add app → Android**
   - Package name: `com.bwpexperts.blockmerge`
   - SHA-1 (debug builds from GitHub): `82:0A:E9:DE:F9:EF:BE:C7:20:5E:D1:CB:3A:F7:88:6E:49:26:08:3D`
   - Also add SHA-256: `05:C8:06:CC:40:EF:DF:7B:51:C9:10:B9:89:BE:B9:2D:75:BA:19:37:B7:87:D6:C4:A0:DB:CF:B3:73:82:B7:86`
   - When you add the release keystore (KEYSTORE_BASE64), add its SHA-1/SHA-256 too
     (`keytool -list -v -keystore your.jks`).
   - Download `google-services.json` → paste into secret `FIREBASE_ANDROID_JSON`.
3. **Add app → iOS**
   - Bundle ID: `com.bwpexperts.blockmerge`
   - Download `GoogleService-Info.plist` → paste into secret `FIREBASE_IOS_PLIST`.
4. **Build → Authentication → Get started → Sign-in method**, enable:
   - **Google**
   - **Facebook** (needs the App ID + App Secret from step 2 below; copy the OAuth redirect URI Firebase shows into Facebook)
   - **Apple** (see step 3 below)
5. **Build → Firestore Database → Create database** (production mode), then **Rules**:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

## 2. Facebook app

1. https://developers.facebook.com → **My Apps → Create App → Authenticate and request data from users with Facebook Login**.
2. **App settings → Basic**: copy **App ID** and **App Secret** (secret goes into Firebase, step 1.4).
3. **App settings → Advanced → Security → Client token**: copy → secret `FACEBOOK_CLIENT_TOKEN`.
4. **Facebook Login → Settings → Valid OAuth Redirect URIs**: paste the URI from Firebase.
5. **Add platform → Android**: package `com.bwpexperts.blockmerge`, class `com.bwpexperts.blockmerge.MainActivity`,
   key hash `ggrp3vnvvscgXtHLOveIbkkmCD0=` (debug builds; add the release key hash later).
6. **Add platform → iOS**: bundle ID `com.bwpexperts.blockmerge`.
7. Switch the app to **Live** mode when you publish.

## 3. Apple login

Sign in with Apple needs a paid **Apple Developer account ($99/year)**:
- Enable the "Sign in with Apple" capability for `com.bwpexperts.blockmerge`.
- In Firebase → Authentication → Apple, fill in the Services ID / Team ID / Key.
- The iOS build then needs real signing (not the unsigned IPA). Send me the signing files when you have the account and I'll add them to the workflow.

Until then the Apple button shows a friendly "not available" message.

## What the player gets

- Log in with Google / Facebook / Apple, or keep playing as guest.
- Progress (coins, skins, levels, stars, League) saves to the cloud automatically.
- On a new phone, after login the game offers to load the cloud progress.
