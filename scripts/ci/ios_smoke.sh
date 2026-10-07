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

LOG="$PWD/$OUT/ios-app.log"
: > "$LOG"
xcrun simctl launch --stdout="$LOG" --stderr="$LOG" "$UDID" "$BUNDLE" > "$OUT/ios-launch.txt" 2>&1
note "launch: $(tr '\n' ' ' < "$OUT/ios-launch.txt" | cut -c1-120)"
sleep 12
xcrun simctl io "$UDID" screenshot "$OUT/ios-01-starting.png" >/dev/null 2>&1 || true
sleep 40
xcrun simctl io "$UDID" screenshot "$OUT/ios-02-loaded.png" >/dev/null 2>&1 || true

RUNNING=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -c "UIKitApplication:$BUNDLE" || true)
check "app is still running after 50 seconds (no crash)" "$([ "${RUNNING:-0}" -ge 1 ] && echo 1 || echo 0)" "process not found"

CRASHES=$(ls "$HOME/Library/Logs/DiagnosticReports" 2>/dev/null | grep -ciE "^App[-_.]" || true)
check "no crash report written" "$([ "${CRASHES:-0}" -eq 0 ] && echo 1 || echo 0)" "$CRASHES report(s)"

ls "$HOME/Library/Logs/DiagnosticReports" 2>/dev/null | grep -iE "^App" | head -3 | while IFS= read -r f; do note "crash report: $f"; sed -n '1,40p' "$HOME/Library/Logs/DiagnosticReports/$f" | grep -iE "exception|termination|crashed|reason|^[0-9]+ +(App|Capacitor|BwpNative)" | cut -c1-200 | head -14 | while IFS= read -r l; do note "   $l"; done; done

READY=$(grep -c "BwpNative: ready" "$OUT/ios-app.log" 2>/dev/null || true)
check "native plugin started and installed the bridge script" "$([ "${READY:-0}" -ge 1 ] && echo 1 || echo 0)" "log line missing"
MISSING=$(grep -c "bwp-bridge.js not found" "$OUT/ios-app.log" 2>/dev/null || true)
check "bridge script found in the app bundle" "$([ "${MISSING:-0}" -eq 0 ] && echo 1 || echo 0)"
BRIDGE=$(grep -c "BwpNative: page ready (bill.bwpexperts.com)" "$OUT/ios-app.log" 2>/dev/null || true)
check "website loaded and its bridge script reached the native plugin" "$([ "${BRIDGE:-0}" -ge 1 ] && echo 1 || echo 0)" "no 'page ready' message from the website"

note "app log (filtered):"
while IFS= read -r l; do note "  $l"; done < <(grep -iE "BwpNative|Loading app at|WebView loaded|error|fail|fatal|exception" "$OUT/ios-app.log" 2>/dev/null | cut -c1-220 | head -25)
if [ "${RUNNING:-0}" -lt 1 ]; then
  note "system log for the app (last lines):"
  while IFS= read -r l; do note "  $l"; done < <(xcrun simctl spawn "$UDID" log show --last 3m --style compact --predicate 'process == "App" OR eventMessage CONTAINS "com.bwpexperts.billing"' 2>/dev/null | grep -iE "crash|exception|fatal|terminat|killed|denied|error" | cut -c1-230 | tail -20)
fi

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
