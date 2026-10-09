# B1G website — changes needed for app version 1.0.21+

This is the task for whoever maintains the WordPress plugin **"B1G App Platform"**
(REST namespace `b1g/v1`). The TV app already calls everything described here; until the
website has it, the app simply behaves as before (no default server, no update notice).

Nothing that exists today changes: `device/register`, `device/status`, `device/activate`,
`device/playlists` and the `public/*` routes stay exactly as they are.

---

## 1. New REST route: `GET /wp-json/b1g/v1/app/config`

Public, no login, no nonce (the TV app has no cookies). Must answer fast and must not be cached
by a page cache or CDN (send `Cache-Control: no-store`).

The app calls it when it starts, every time it comes back to the front, and every 6 hours:

```
GET /wp-json/b1g/v1/app/config?platform=android-tv&version_code=21&device_id=B1G-XXXX-XXXX
```

| Query parameter | Meaning |
|---|---|
| `platform` | `android-tv` today. Later: `android`, `ios`, `tizen`, `webos`. |
| `version_code` | Build number of the installed app (integer). `0` = unknown. |
| `device_id` | The device ID from `device/register`. May be empty on the very first start. Optional: use it to record "last seen" and "app version" for the device. |

### Response (always HTTP 200, same envelope as the other routes)

```json
{
  "success": true,
  "config": {
    "server_url": "http://example.com:8080",
    "server_name": "B1G TV"
  },
  "update": {
    "version_code": 22,
    "version_name": "1.0.22",
    "apk_url": "https://yoursite.com/downloads/B1G.apk",
    "notes": "Faster channel start.\nSmall fixes.",
    "force": false
  }
}
```

| Field | Type | Rules |
|---|---|---|
| `config.server_url` | string | The provider's Xtream Codes address (DNS), with `http://` or `https://` and the port, no path. **Empty string** = not set. |
| `config.server_name` | string | Short name shown on the sign-in tab (max ~12 characters). May be empty. |
| `update` | object or `null` | `null` (or leave it out) when no version is entered in the settings. |
| `update.version_code` | integer | Build number of the newest APK. The **app** compares it with its own number and offers the update only when this one is higher — the website does not need to compare. |
| `update.version_name` | string | Shown to the customer, e.g. `1.0.22`. |
| `update.apk_url` | string | Direct link to the APK file. Must start with `http://` or `https://`. |
| `update.notes` | string | "What's new", plain text, line breaks as `\n`. May be empty. |
| `update.force` | boolean | `true` = the customer cannot press "Later" (use only for a broken version). |

### What the app does with it

* **`server_url` set** → the sign-in screen opens on a tab that asks for **username and password
  only** and signs in against that server. The tabs "Xtream Codes" (server + username +
  password) and "M3U link" stay available next to it. The address is remembered on the device,
  so signing in also works when the website is down.
* **`server_url` changed later** → customers who signed in with username and password only are
  moved to the new address the next time they open the app (same login, favourites stay).
  This is how a DNS change is rolled out without touching the customers' TVs.
* **`server_url` empty** → the sign-in screen is as before (Xtream Codes / M3U link).
* **`update.version_code` higher than the installed build** → an "Update available" window with
  **Update now / Later**; "Update now" downloads `apk_url` with a percent bar and opens
  Android's installer. The home screen keeps an **Update** button for customers who chose Later.

---

## 2. Settings page in WP admin ("B1G › App settings")

Seven fields, stored as options:

| Label | Option name (suggestion) | Input |
|---|---|---|
| Default IPTV server address | `b1g_app_server_url` | URL text field. Trim spaces, remove a trailing `/`. If someone pastes a full `get.php?...` link keep only scheme + host + port. |
| Server name on the sign-in tab | `b1g_app_server_name` | Text, max 12 characters. |
| Latest app build number | `b1g_app_version_code` | Whole number. Empty or 0 = no update announced. |
| Latest app version name | `b1g_app_version_name` | Text, e.g. `1.0.22`. |
| APK download link | `b1g_app_apk_url` | URL. A "Upload APK" button next to it (media uploader) is welcome. |
| What's new | `b1g_app_update_notes` | Textarea, plain text. |
| Force this update | `b1g_app_update_force` | Checkbox. |

Capability: `manage_options`. Sanitize with `esc_url_raw`, `absint`, `sanitize_text_field`,
`sanitize_textarea_field`.

### Reference implementation of the route

```php
add_action('rest_api_init', function () {
    register_rest_route('b1g/v1', '/app/config', [
        'methods'             => 'GET',
        'permission_callback' => '__return_true',
        'callback'            => function (WP_REST_Request $req) {
            $code = absint(get_option('b1g_app_version_code', 0));
            $apk  = esc_url_raw(trim((string) get_option('b1g_app_apk_url', '')));
            $update = null;
            if ($code > 0 && $apk !== '') {
                $update = [
                    'version_code' => $code,
                    'version_name' => (string) get_option('b1g_app_version_name', ''),
                    'apk_url'      => $apk,
                    'notes'        => (string) get_option('b1g_app_update_notes', ''),
                    'force'        => (bool) get_option('b1g_app_update_force', false),
                ];
            }
            // Optional: remember which version each device runs.
            // $device_id = sanitize_text_field((string) $req->get_param('device_id'));
            // $installed = absint($req->get_param('version_code'));

            $res = new WP_REST_Response([
                'success' => true,
                'config'  => [
                    'server_url'  => untrailingslashit(trim((string) get_option('b1g_app_server_url', ''))),
                    'server_name' => (string) get_option('b1g_app_server_name', ''),
                ],
                'update'  => $update,
            ], 200);
            $res->header('Cache-Control', 'no-store, max-age=0');
            return $res;
        },
    ]);
});
```

---

## 3. Hosting the APK

* The link must return the **file itself** with HTTP 200 (redirects are followed). No login,
  no "are you human" page, no download-manager page in between — the app checks that the file
  really is an APK and shows an error otherwise.
* Send a `Content-Length` header (normal for a static file) so the percent bar can count.
* WordPress blocks `.apk` uploads by default. Either allow it:

  ```php
  add_filter('upload_mimes', function ($m) {
      $m['apk'] = 'application/vnd.android.package-archive';
      return $m;
  });
  ```

  or put the file by FTP in e.g. `/wp-content/uploads/b1g/B1G.apk`.
* Exclude the APK path and `/wp-json/b1g/` from page caching / Cloudflare "cache everything".
* Simplest alternative without hosting: use the build's own link
  `https://github.com/semrush733-ux/builder2343/releases/download/b1g-latest/B1G.apk`
  (it always points at the newest build).

---

## 4. Releasing an app update (checklist for the site owner)

1. Build the new APK. Its build number is in the file's release notes and in the app under
   **My device** ("B1G 1.0.22 · build 22").
2. Upload the APK (or use the GitHub link above).
3. In **B1G › App settings** set *Latest app build number* (e.g. `22`), *version name*,
   *APK link*, *What's new*. Save.
4. Customers see "Update available" the next time they open the app.

Updates install **over** the existing app only when every APK is signed with the same key
(the four `ANDROID_*` secrets of the build). An APK signed with a different key is refused by
Android until the old app is uninstalled.

---

## 5. Optional, nice to have

* On the QR page (`/upload-playlist/?device_id=…&pairing_code=…`): when a default server is
  set, offer a short form "Username + Password" that saves an `xtream` playlist with
  `url = default server` for that device. It then appears on the TV under "On your account".
* In the device list in WP admin: show the app version each device last reported
  (`version_code` from this route).

---

## 6. Quick test

```bash
curl -s "https://YOURSITE/wp-json/b1g/v1/app/config?platform=android-tv&version_code=1" | python3 -m json.tool
```

Expected: `"success": true`, a `config` object, and `update` either `null` or the object above.
Then on a TV: sign out → the sign-in screen shows the username/password tab first; raise the
build number in the settings → reopen the app → "Update available".
