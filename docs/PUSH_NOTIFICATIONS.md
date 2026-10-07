# Push notifications - preparation notes

Push notifications are **not implemented**. Nothing in the app pretends to send or receive them.
This page lists what has to be added when you are ready.

Planned notification types: New Sale, Refund Created, Refund Approved, Expense Added,
Expense Approved, Subscription Expiring, Seller Activity.

## What you need to provide

| Item | Where it comes from |
|---|---|
| Firebase project | https://console.firebase.google.com |
| `google-services.json` (Android app `com.bwpexperts.billing`) | Firebase console > Project settings |
| APNs Auth Key (`.p8`), Key ID, Team ID | Apple Developer > Keys (uploaded to Firebase > Cloud Messaging) |
| `GoogleService-Info.plist` (only if Firebase is used on iOS) | Firebase console |
| Firebase service-account key for the server | Firebase console > Service accounts. **Server only - never inside the app** |

## App side

1. `npm install @capacitor/push-notifications` then `npm run sync`.
2. Android: put `google-services.json` in `android/app/` (the Capacitor template applies the Google
   Services Gradle plugin automatically when that file exists).
3. iOS: in Xcode add the **Push Notifications** capability and forward the device token in
   `AppDelegate.swift` as described in the plugin documentation.
4. In `src/bwp-bridge.js` add a small block that, after the user is logged in:
   - calls `Capacitor.Plugins.PushNotifications.requestPermissions()` and `register()`,
   - sends the received token to the server (step below),
   - on `pushNotificationActionPerformed` opens the URL carried in the notification data
     (for example `/refunds/123`) with `window.location.assign(...)`.
   The bridge already runs on every page of the site, so no change to the website is required.

## Server side (bill.bwpexperts.com)

1. An authenticated endpoint that stores `{ user_id, device_token, platform }`.
2. Remove the token on logout and when Firebase reports it as invalid.
3. Send through the Firebase Cloud Messaging HTTP v1 API when a sale, refund, expense etc. happens.
   Put the target page in the data payload, for example `{ "url": "/refunds/123" }`.

## Android 13+

The `POST_NOTIFICATIONS` runtime permission is requested by `requestPermissions()`. Ask for it at a
sensible moment (after login), not at first launch.
