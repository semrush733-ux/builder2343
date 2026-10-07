#!/bin/bash
# BWP Billing - iOS simulator smoke test (runs in CI, see .github/workflows/ios.yml).
# Installs the simulator build, starts it, waits for the website, takes screenshots and
# checks that the app did not crash and that the native plugin and the bridge script started.
# It never logs in and never submits anything on the website.
set -u
APP="$1"
BUNDLE=com.bwpexperts.billing
OUT=out/smoke
mkdir -p "$OUT"
R="$OUT/SMOKE-ios.md"
LINES=()
check() { if [ "$2" = "1" ]; then LINES+=("PASS  $1"); else LINES+=("FAIL  $1  [${3:-}]"); fi; echo "${LINES[${#LINES[@]}-1]}"; }
note() { LINES+=("      $1"); echo "$1"; }

if [ ! -d "$APP" ]; then
  echo "### Simulator smoke test (iOS)" > "$R"; echo "" >> "$R"; echo "Simulator build not found: $APP" >> "$R"; exit 0
fi

PICK=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
best = None
for runtime in sorted(devices, reverse=True):
    if 'iOS' not in runtime:
        continue
    for d in devices[runtime]:
        if d.get('isAvailable') and d['name'].startswith('iPhone') and 'SE' not in d['name'] and best is None:
            best = (d['udid'], d['name'], runtime.split('.')[-1])
print('|'.join(best) if best else '')")
UDID="${PICK%%|*}"
note "simulator: ${PICK#*|}"
if [ -z "$UDID" ]; then
  echo "### Simulator smoke test (iOS)" > "$R"; echo "" >> "$R"; echo "No iPhone simulator available on the build machine." >> "$R"; exit 0
fi

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"
INSTALLED=$?
check "app installs on the simulator" "$([ $INSTALLED -eq 0 ] && echo 1 || echo 0)" "exit $INSTALLED"

( xcrun simctl launch --console-pty "$UDID" "$BUNDLE" > "$OUT/ios-app.log" 2>&1 ) &
sleep 12
xcrun simctl io "$UDID" screenshot "$OUT/ios-01-starting.png" >/dev/null 2>&1 || true
sleep 40
xcrun simctl io "$UDID" screenshot "$OUT/ios-02-loaded.png" >/dev/null 2>&1 || true

RUNNING=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -c "UIKitApplication:$BUNDLE" || true)
check "app is still running after 50 seconds (no crash)" "$([ "${RUNNING:-0}" -ge 1 ] && echo 1 || echo 0)" "process not found"

CRASHES=$(ls "$HOME/Library/Logs/DiagnosticReports" 2>/dev/null | grep -ciE "^App[-_.]" || true)
check "no crash report written" "$([ "${CRASHES:-0}" -eq 0 ] && echo 1 || echo 0)" "$CRASHES report(s)"

READY=$(grep -c "BwpNative: ready" "$OUT/ios-app.log" 2>/dev/null || true)
check "native plugin started and installed the bridge script" "$([ "${READY:-0}" -ge 1 ] && echo 1 || echo 0)" "log line missing"
MISSING=$(grep -c "bwp-bridge.js not found" "$OUT/ios-app.log" 2>/dev/null || true)
check "bridge script found in the app bundle" "$([ "${MISSING:-0}" -eq 0 ] && echo 1 || echo 0)"
BRIDGE=$(grep -c "\[BWP\] bridge ready" "$OUT/ios-app.log" 2>/dev/null || true)
check "bridge script running on the billing website" "$([ "${BRIDGE:-0}" -ge 1 ] && echo 1 || echo 0)" "no '[BWP] bridge ready' in the app log"

note "app log (filtered):"
while IFS= read -r l; do note "  $l"; done < <(grep -iE "BwpNative|\[BWP\]|Loading app at|WebView loaded|error|fail" "$OUT/ios-app.log" 2>/dev/null | cut -c1-220 | head -25)

xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true

PASSED=$(printf '%s\n' "${LINES[@]}" | grep -c "^PASS" || true)
FAILED=$(printf '%s\n' "${LINES[@]}" | grep -c "^FAIL" || true)
{
  echo "### Simulator smoke test (iOS)"
  echo ""
  echo "$PASSED passed, $FAILED failed"
  echo ""
  echo '```'
  printf '%s\n' "${LINES[@]}"
  echo '```'
} > "$R"
exit 0
