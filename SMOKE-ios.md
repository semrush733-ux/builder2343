### Simulator smoke test (iOS)

6 passed, 0 failed

```
      simulator: iPhone 17 Pro|iOS-26-5
      simulator boot was slow or did not finish
PASS  app installs on the simulator
      launch: com.bwpexperts.billing: 18684 
      website ready after about 18s
PASS  app is still running at the end of the test (no crash)
PASS  no crash report written
PASS  native plugin started and installed the bridge script
PASS  bridge script found in the app bundle
PASS  website loaded and its bridge script reached the native plugin
      app log (filtered):
        2026-10-07 16:41:24.328 App[18684:56179] BwpNative: ready (bridge script installed)
        2026-10-07 16:42:14.474 App[18684:56179] BwpNative: page ready (bill.bwpexperts.com)
```
