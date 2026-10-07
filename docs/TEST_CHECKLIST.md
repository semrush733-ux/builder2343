# Test checklist

Status legend:

- **E** = checked automatically on an Android emulator in every cloud build (`scripts/ci/android_smoke.py`)
- **S** = checked automatically on an iPhone simulator in every cloud build (`scripts/ci/ios_smoke.sh`)
- **B** = checked in a desktop browser against a mock site (`tests/shell_and_bridge_test.py`)
- **-** = not tested. Needs a real phone and a real BWP Billing account.

The automatic tests never log in, so everything behind the login is untested. Nothing has been
tested on a real phone.

| # | Flow | Status | What to check |
|---|---|---|---|
| 1 | App launch | E, S | Splash, then "Loading your dashboard...", then the site. No crash, no URL bar |
| 2 | Login | - | Normal website login works |
| 3 | Session persistence | - | Close the app from recents, reopen: still logged in |
| 4 | Logout | - | Returns to the login page, no reload loop |
| 5 | Dashboard | - | Loads, nothing under the status bar / notch / navigation bar |
| 6 | Seller login | - | If available |
| 7 | Admin login | - | If available |
| 8 | Navigation | - | Menus, links, breadcrumbs; no horizontal overflow |
| 9 | Customer search | - | Keyboard does not cover the field or the results |
| 10 | Subscription creation | - | Full form incl. selects and date pickers |
| 11 | Credit fields | - | Numeric keyboard; on iPhone the "Done" bar is shown |
| 12 | Expenses | - | Add / approve |
| 13 | Refund workflow | - | Create / approve |
| 14 | Forms | - | Validation messages, long forms scroll |
| 15 | Modals | - | Fit the screen, scroll inside, pull-to-refresh does not fire inside them |
| 16 | File upload | - | Gallery / Files / PDF |
| 17 | Camera upload | - | Take a photo from the upload field |
| 18 | PDF invoice | E (test file), B | Android: saved + Open/Share dialog. iOS: preview |
| 19 | Download (CSV / Excel / image) | E (test file + page-generated file), B | File appears in `Downloads/BWP Billing` (Android) |
| 20 | Share | E, B | Share sheet opens |
| 21 | Print invoice / receipt | E (dialog opens), B | Native print dialog with a correct preview of a real invoice |
| 22 | External URLs | - | Other websites open in the browser, not in the app |
| 23 | WhatsApp link | - | Opens WhatsApp. Also `tel:` and `mailto:` |
| 24 | Internet disconnected | E, B | Airplane mode: "No Internet Connection" + Retry, never a browser error |
| 25 | Internet restored | E, B | Reconnects by itself and reopens the page that failed |
| 26 | Server unreachable | B (screen only) | "We couldn't connect to BWP Billing." + Retry |
| 27 | Android Back button | E | Goes back page by page; on the first page "Press back again to exit" |
| 28 | App background / resume | E | Same page, no restart. Still logged in: not tested |
| 29 | Session expired | B (download case) | Server redirects to login, no loop |
| 30 | Keyboard / forms | - | Focused input always visible, also inside modals |
| 31 | Portrait mode | E, S (one screen size each) | Small phone and large phone |
| 32 | Pull-to-refresh | E | Refreshes at the top of a page only |
| 33 | Status bar / safe areas | E, S | Content below the status bar and above the navigation bar; icons readable |
| 34 | Release build | - | Signed APK / AAB installs; web view debugging is off |

Known limits to verify on the real site:

- The "couldn't connect" screen is meant only for real connection failures; server error pages (404 / 403 / 500) should appear as in a browser. Not yet checked on a device with a real error page.
- Files returned by a form POST cannot be downloaded by the app (links / GET work).
- "Print" flows that open a blank popup and write into it are not supported by mobile web views.
