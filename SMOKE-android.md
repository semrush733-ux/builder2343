### Emulator smoke test (Android 15)

33 passed, 0 failed

```
      site / -> 200 https://bill.bwpexperts.com/ | title: bill.bwpexperts.com | <input>: 0 | text: bill.bwpexperts.com Skip to content
      site /wp-login.php -> 200 https://bill.bwpexperts.com/login | title: BWP Experts Billing | <input>: 3 | text: BWP Experts Billing BWP Experts Billing Secure Payment Management Portal Sign in Enter your username or email to continue. Username or email
      site security policy: upgrade-insecure-requests
      site /login/ -> 200 https://bill.bwpexperts.com/login/ | title: BWP Experts Billing | <input>: 3 | text: BWP Experts Billing BWP Experts Billing Secure Payment Management Portal Sign in Enter your username or email to continue. Username or email
      site /dashboard/ -> 200 https://bill.bwpexperts.com/login | title: BWP Experts Billing | <input>: 3 | text: BWP Experts Billing BWP Experts Billing Secure Payment Management Portal Sign in Enter your username or email to continue. Username or email
      site /my-account/ -> 200 https://bill.bwpexperts.com/login | title: BWP Experts Billing | <input>: 3 | text: BWP Experts Billing BWP Experts Billing Secure Payment Management Portal Sign in Enter your username or email to continue. Username or email
      install: Performing Streamed Install Success
PASS  app process is running after launch
PASS  billing website loaded inside the app  [https://bill.bwpexperts.com/login]
      page: https://bill.bwpexperts.com/login | title: BWP Experts Billing
      page state: {"bridge":true,"plugin":true,"share":"function","online":true,"w":412,"h":842,"dpr":2.625,"overflowX":false,"viewport":true}
PASS  bridge script injected into the website
PASS  native channel available to the website
PASS  native plugin answers the website  [{"url":"https://bill.bwpexperts.com/login"}]
      page content: {"ready":"complete","text":"BWP Experts Billing Secure Payment Management Portal Sign in Enter your username or email to continue. Username or email Continue Authorised users only. Sign-in activity is recorded.","inputs":1,"forms":1,"links":[],"height":842,"bodyBg":"rgb(0, 0, 0)","generator":""}
PASS  navigator.share available
PASS  page has no horizontal overflow
      screen 1080x2400, web view bounds [0,128][1080,2337]
PASS  content starts below the status bar  [128]
PASS  content ends above the navigation bar  [2337 < 2400]
      keyboard: shown=True before innerHeight=842 after={"tag":"INPUT","bottom":428,"top":378,"view":530,"inner":530}
PASS  keyboard opens for the input field
PASS  page is resized for the keyboard  [842 -> 530]
PASS  focused field stays visible above the keyboard  [{"tag":"INPUT","bottom":428,"top":378,"view":530,"inner":530}]
      saveFile result: {"name":"bwp-smoke-test.txt","savedToDownloads":true} | dialog texts: ['bwp-smoke-test.txt', 'saved to downloads / bwp billing.', 'share', 'close', 'open']
PASS  download: file saved to Downloads  [{"name":"bwp-smoke-test.txt","savedToDownloads":true}]
PASS  download: dialog with Open / Share shown  [['bwp-smoke-test.txt', 'saved to downloads / bwp billing.', 'share', 'close', 'open']]
PASS  download: file exists in Download/BWP Billing  [bwp-smoke-test.txt]
PASS  download: page-generated file (blob) reaches the native dialog  [notice: Preparing file...]
PASS  print: native print dialog opens  [['Select a printer', 'Copies:', '1', 'Paper size:', 'Letter', '1/1']]
PASS  share: native share sheet opens  [ok | ctivityRecord{6feaa01 u0 com.android.intentresolver/.ChooserActivityLauncher t8}]
PASS  pull-to-refresh reloads the page
PASS  Back button returns to the previous page  [https://bill.bwpexperts.com/login -> https://bill.bwpexperts.com/login]
PASS  one Back press on the first page does not close the app  [ActivityRecord{516d294 u0 com.bwpexperts.billing/.MainActivity t8}]
PASS  two quick Back presses leave the app  [cord{dceaf93 u0 com.google.android.apps.nexuslauncher/.NexusLauncherActivity t7}]
PASS  app keeps running in the background
PASS  reopening shows the same page without restarting  [https://bill.bwpexperts.com/login]
      offline screen: https://localhost/error.html | ['BWP Billing', 'BWP Billing', 'by BWP Experts', 'No Internet Connection', 'Please check your internet connection and try again.', 'Retry']
PASS  offline: custom screen instead of the browser error  [https://localhost/error.html]
PASS  offline: "No Internet Connection" + Retry shown  [['BWP Billing', 'BWP Billing', 'by BWP Experts', 'No Internet Connection', 'Please check your internet connection and try again.', 'Retry']]
PASS  offline: technical reason shown on the screen  [['BWP Billing', 'BWP Billing', 'by BWP Experts', 'No Internet Connection', 'Please check your internet connection and try again.', 'Retry', 'Details: net::ERR_INTERNET_DISCONNECTED (-2)']]
      reason shown: ['Details: net::ERR_INTERNET_DISCONNECTED (-2)']
PASS  reconnect: website returns automatically when internet is back  [https://bill.bwpexperts.com/login]
PASS  reconnect: reopens the page that failed  [https://bill.bwpexperts.com/login vs https://bill.bwpexperts.com/login]
PASS  start without internet: "No Internet Connection" screen  [['BWP Billing', 'BWP Billing', 'by BWP Experts', 'No Internet Connection', 'Please check your internet connection and try again.', 'Retry']]
PASS  start without internet: loads the site when internet returns  [https://bill.bwpexperts.com/login]
PASS  the app did not crash (no FATAL EXCEPTION for the app in logcat)  [[]]
PASS  no errors logged by the BWP plugin  [[]]
```
