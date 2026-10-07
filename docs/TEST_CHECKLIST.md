# Test checklist

Status when this project was handed over:

- **B** = checked in a desktop browser against a mock site (not on a phone, not on the real site)
- **-** = not tested yet. Needs a built app on a device with a real BWP Billing account.

Nothing below has been tested on a real phone or against the real website so far.

| # | Flow | Status | What to check |
|---|---|---|---|
| 1 | App launch | B (launch screen only) | Splash, then "Loading your dashboard...", then the site. No white flash, no URL bar |
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
| 18 | PDF invoice | B (hand-over to native) | Android: saved + Open/Share dialog. iOS: preview |
| 19 | Download (CSV / Excel / image) | B (hand-over to native) | File appears in `Downloads/BWP Billing` (Android) |
| 20 | Share | B (hand-over to native) | Share sheet opens from the download dialog / preview |
| 21 | Print invoice / receipt | B (hand-over to native) | Native print dialog with a correct preview |
| 22 | External URLs | - | Other websites open in the browser, not in the app |
| 23 | WhatsApp link | - | Opens WhatsApp. Also `tel:` and `mailto:` |
| 24 | Internet disconnected | B | Airplane mode: "No Internet Connection" + Retry, never a browser error |
| 25 | Internet restored | B | Reconnects by itself; Retry reopens the page that failed |
| 26 | Server unreachable | B (screen only) | "We couldn't connect to BWP Billing." + Retry |
| 27 | Android Back button | - | Goes back page by page; on the first page "Press back again to exit" |
| 28 | App background / resume | - | Same page, still logged in, no restart |
| 29 | Session expired | B (download case) | Server redirects to login, no loop |
| 30 | Keyboard / forms | - | Focused input always visible, also inside modals |
| 31 | Portrait mode | - | Small phone and large phone |
| 32 | Pull-to-refresh | B (guard logic) | Refreshes at the top of a page only |
| 33 | Status bar colour | B (colour detection) | Matches the page header; icons readable |
| 34 | Release build | - | Signed APK / AAB installs; web view debugging is off |

Known limits to verify on the real site:

- Android shows the "couldn't connect" screen for any HTTP error status on a full page load (404 / 403 / 500).
- Files returned by a form POST cannot be downloaded by the app (links / GET work).
- "Print" flows that open a blank popup and write into it are not supported by mobile web views.
