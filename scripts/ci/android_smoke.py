#!/usr/bin/env python3
"""
BWP Billing - Android smoke test (runs in CI on an emulator, see .github/workflows/android.yml).

Installs the debug APK, starts the app and drives it through adb + the WebView debugging port.
It checks that the app starts, the website loads inside it, the bridge script and the native
plugin work (download dialog, print, share), the Back button, pull-to-refresh, the keyboard and
the offline / reconnect screens. It never logs in and never submits anything on the website.

Output: out/smoke/SMOKE-android.md, screenshots and logcat.
"""
import json
import os
import re
import subprocess
import time
import urllib.request

PKG = 'com.bwpexperts.billing'
SITE = 'https://bill.bwpexperts.com'
APK = 'out/app-debug.apk'
OUT = 'out/smoke'
os.makedirs(OUT, exist_ok=True)
lines = []


def sh(*args, timeout=60):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout).stdout or ''
    except Exception as exc:  # noqa: BLE001
        return 'ERR %s' % exc


def adb(*args, **kw):
    return sh('adb', *args, **kw)


def shot(name):
    try:
        data = subprocess.run(['adb', 'exec-out', 'screencap', '-p'], capture_output=True, timeout=30).stdout
        with open('%s/%s.png' % (OUT, name), 'wb') as f:
            f.write(data)
    except Exception:  # noqa: BLE001
        pass


def ui():
    adb('shell', 'uiautomator', 'dump', '/sdcard/bwp-ui.xml')
    return adb('shell', 'cat', '/sdcard/bwp-ui.xml')


def texts(xml):
    return [t for t in re.findall(r'text="([^"]*)"', xml) if t.strip()]


def check(name, ok, detail=''):
    line = '%s  %s' % ('PASS' if ok else 'FAIL', name)
    if detail not in ('', None):
        line += '  [%s]' % str(detail)[:300]
    lines.append(line)
    print(line, flush=True)


def note(text):
    lines.append('      ' + text)
    print(text, flush=True)


def pid():
    return adb('shell', 'pidof', PKG).strip()


def pages():
    p = pid()
    if not p:
        return []
    adb('forward', 'tcp:9222', 'localabstract:webview_devtools_remote_%s' % p.split()[0])
    try:
        with urllib.request.urlopen('http://127.0.0.1:9222/json', timeout=5) as res:
            return [x for x in json.load(res) if x.get('type') == 'page']
    except Exception:  # noqa: BLE001
        return []


def url():
    ps = pages()
    return ps[0].get('url', '') if ps else ''


def js(expression, await_promise=False):
    import websocket  # pip install websocket-client
    ps = pages()
    if not ps:
        return None
    ws = websocket.create_connection(ps[0]['webSocketDebuggerUrl'], timeout=20, suppress_origin=True)
    try:
        ws.send(json.dumps({'id': 1, 'method': 'Runtime.evaluate', 'params': {
            'expression': expression, 'returnByValue': True, 'awaitPromise': await_promise, 'userGesture': True}}))
        while True:
            msg = json.loads(ws.recv())
            if msg.get('id') == 1:
                break
    finally:
        ws.close()
    result = msg.get('result', {})
    if 'exceptionDetails' in result:
        return 'JS-EXCEPTION: ' + json.dumps(result['exceptionDetails'])[:300]
    return result.get('result', {}).get('value')


def wait_for(predicate, seconds, step=1.0):
    end = time.time() + seconds
    last = None
    while time.time() < end:
        try:
            last = predicate()
            if last:
                return last
        except Exception:  # noqa: BLE001
            pass
        time.sleep(step)
    return last


def resumed():
    out = adb('shell', 'dumpsys', 'activity', 'activities')
    found = re.findall(r'(?:topResumedActivity|mResumedActivity|ResumedActivity)[=:]\s*(.*)', out)
    return found[0].strip() if found else ''


def on_site():
    u = url()
    return u if u.startswith(SITE) else ''


def network(enabled):
    state = 'enable' if enabled else 'disable'
    adb('shell', 'svc', 'wifi', state)
    adb('shell', 'svc', 'data', state)


def back():
    adb('shell', 'input', 'keyevent', '4')


def start_app():
    return adb('shell', 'am', 'start', '-W', '-n', '%s/.MainActivity' % PKG)


def run(name, fn):
    try:
        fn()
    except Exception as exc:  # noqa: BLE001
        check(name + ' (test crashed)', False, repr(exc))


# ----------------------------------------------------------------------------- tests

def t_launch():
    note('install: ' + adb('install', '-r', APK, timeout=180).strip().replace('\n', ' ')[-120:])
    adb('logcat', '-c')
    start_app()
    u = wait_for(on_site, 75, 2)
    shot('01-launch')
    check('app process is running after launch', bool(pid()))
    check('billing website loaded inside the app', bool(u), url() or 'no page')
    ps = pages()
    if ps:
        note('page: %s | title: %s' % (ps[0].get('url'), ps[0].get('title')))
    time.sleep(3)
    state = js("JSON.stringify({bridge: !!window.__bwp, plugin: !!(window.bwpNative && typeof window.bwpNative.postMessage === 'function'),"
               "share: typeof navigator.share, online: navigator.onLine, w: innerWidth, h: innerHeight, dpr: devicePixelRatio,"
               "overflowX: document.documentElement.scrollWidth > innerWidth + 1, viewport: !!document.querySelector('meta[name=viewport]')})")
    note('page state: %s' % state)
    st = json.loads(state) if isinstance(state, str) and state.startswith('{') else {}
    check('bridge script injected into the website', st.get('bridge') is True)
    check('native channel available to the website', st.get('plugin') is True)
    pong = js("window.__bwp.call('getLastUrl', {}).then(function(r){return JSON.stringify(r)}, function(e){return 'REJECTED ' + (e && e.message)})", True)
    check('native plugin answers the website', isinstance(pong, str) and SITE in pong, pong)
    info = js("JSON.stringify({ready: document.readyState, text: (document.body.innerText || '').replace(/\\s+/g, ' ').slice(0, 400), inputs: document.querySelectorAll('input:not([type=hidden])').length,"
              "forms: document.forms.length, links: Array.prototype.slice.call(document.querySelectorAll('a[href]'), 0, 12).map(function(a){return a.getAttribute('href')}),"
              "height: document.documentElement.scrollHeight, bodyBg: getComputedStyle(document.body).backgroundColor, generator: (document.querySelector('meta[name=generator]') || {}).content || ''})")
    note('page content: %s' % info)
    check('navigator.share available', st.get('share') == 'function')
    check('page has no horizontal overflow', st.get('overflowX') is False)
    xml = ui()
    size = re.search(r'(\d+)x(\d+)', adb('shell', 'wm', 'size'))
    m = re.search(r'class="android\.webkit\.WebView"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml)
    if m and size:
        x1, y1, x2, y2 = map(int, m.groups())
        w, h = int(size.group(1)), int(size.group(2))
        note('screen %dx%d, web view bounds [%d,%d][%d,%d]' % (w, h, x1, y1, x2, y2))
        check('content starts below the status bar', y1 > 0, y1)
        check('content ends above the navigation bar', y2 < h, '%d < %d' % (y2, h))
    else:
        check('web view found in the layout', False)


def t_keyboard():
    rect = js("(function(){var e=document.querySelector('input[type=email],input[type=text],input[type=password],input:not([type=hidden])');"
              "if(!e)return '';var r=e.getBoundingClientRect();return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2,dpr:devicePixelRatio,h:innerHeight});})()")
    if not rect:
        note('keyboard test skipped: no input field on this page')
        return
    r = json.loads(rect)
    m = re.search(r'class="android\.webkit\.WebView"[^>]*bounds="\[(\d+),(\d+)\]', ui())
    ox, oy = (int(m.group(1)), int(m.group(2))) if m else (0, 0)
    adb('shell', 'input', 'tap', str(int(ox + r['x'] * r['dpr'])), str(int(oy + r['y'] * r['dpr'])))
    shown = wait_for(lambda: 'mInputShown=true' in adb('shell', 'dumpsys', 'input_method'), 8)
    time.sleep(2)
    shot('02-keyboard')
    state = js("(function(){var e=document.activeElement;var r=e.getBoundingClientRect();var vv=window.visualViewport;"
               "return JSON.stringify({tag:e.tagName,bottom:Math.round(r.bottom),top:Math.round(r.top),view:Math.round(vv?vv.height:innerHeight),inner:innerHeight});})()")
    note('keyboard: shown=%s before innerHeight=%s after=%s' % (bool(shown), r['h'], state))
    st = json.loads(state) if isinstance(state, str) and state.startswith('{') else {}
    check('keyboard opens for the input field', bool(shown))
    check('page is resized for the keyboard', st.get('inner', 10 ** 6) < r['h'], '%s -> %s' % (r['h'], st.get('inner')))
    check('focused field stays visible above the keyboard', st.get('tag') == 'INPUT' and 0 <= st.get('top', -1) and st.get('bottom', 10 ** 6) <= st.get('view', 0), state)
    back()
    time.sleep(1.5)
    js("document.activeElement && document.activeElement.blur()")


def t_download():
    res = js("window.__bwp.call('saveFile', {name:'bwp-smoke-test.txt', mime:'text/plain', data:'QldQIEJpbGxpbmcgc21va2UgdGVzdAo='})"
             ".then(function(r){return JSON.stringify(r)}, function(e){return 'REJECTED ' + (e && e.message)})", True)
    time.sleep(2)
    xml = ui()
    shot('03-download-dialog')
    tx = [t.lower() for t in texts(xml)]
    note('saveFile result: %s | dialog texts: %s' % (res, tx[:8]))
    check('download: file saved to Downloads', isinstance(res, str) and '"savedToDownloads":true' in res, res)
    check('download: dialog with Open / Share shown', 'bwp-smoke-test.txt' in tx and 'open' in tx and 'share' in tx, tx[:8])
    listing = adb('shell', 'ls', '/sdcard/Download/BWP Billing/').strip()
    check('download: file exists in Download/BWP Billing', 'bwp-smoke-test' in listing, listing)
    back()
    time.sleep(1)
    # A file generated by the page itself (blob), through the same path a real invoice takes.
    js("(function(){var a=document.createElement('a');a.href=window.URL.createObjectURL(new Blob(['id,total\\n1,50\\n'],{type:'text/csv'}));a.download='bwp-smoke-export.csv';a.click();})()")
    seen = wait_for(lambda: 'bwp-smoke-export.csv' in [t.lower() for t in texts(ui())], 12, 1.5)
    shot('03b-blob-download-dialog')
    check('download: page-generated file (blob) reaches the native dialog', bool(seen), [t for t in texts(ui())][:6])
    back()
    time.sleep(1)


def t_print():
    js("window.print()")
    time.sleep(5)
    xml = ui()
    shot('04-print')
    ok = 'com.android.printspooler' in xml or 'printer' in xml.lower() or 'save as pdf' in xml.lower()
    check('print: native print dialog opens', ok, texts(xml)[:6])
    for _ in range(3):
        if PKG in resumed():
            break
        back()
        time.sleep(1.5)


def t_share():
    res = js("navigator.share({title:'BWP Billing', text:'smoke test', url: location.href}).then(function(){return 'ok'}, function(e){return 'REJECTED ' + (e && e.message)})", True)
    time.sleep(2.5)
    top = resumed()
    shot('05-share')
    check('share: native share sheet opens', res == 'ok' and PKG not in top, '%s | %s' % (res, top[-80:]))
    for _ in range(3):
        if PKG in resumed():
            break
        back()
        time.sleep(1.5)


def t_refresh():
    js("window.__bwpMarker = 1; window.scrollTo(0, 0)")
    size = re.search(r'(\d+)x(\d+)', adb('shell', 'wm', 'size'))
    w, h = int(size.group(1)), int(size.group(2))
    adb('shell', 'input', 'swipe', str(w // 2), str(int(h * 0.30)), str(w // 2), str(int(h * 0.80)), '600')
    reloaded = wait_for(lambda: js("typeof window.__bwpMarker") == 'undefined', 20, 1.5)
    shot('06-after-refresh')
    check('pull-to-refresh reloads the page', bool(reloaded))
    wait_for(on_site, 20)
    time.sleep(2)


def t_back():
    first = url()
    js("location.assign(location.pathname + (location.search ? location.search + '&' : '?') + 'bwp_smoke=1')")
    moved = wait_for(lambda: 'bwp_smoke=1' in url(), 25)
    time.sleep(2)
    back()
    returned = wait_for(lambda: bool(url()) and 'bwp_smoke=1' not in url(), 20)
    check('Back button returns to the previous page', bool(moved) and bool(returned), '%s -> %s' % (first, url()))
    time.sleep(3)
    back()
    time.sleep(1)
    shot('07-back-once')
    check('one Back press on the first page does not close the app', PKG in resumed(), resumed()[-80:])
    time.sleep(3)
    back()
    time.sleep(0.4)
    back()
    time.sleep(2)
    check('two quick Back presses leave the app', PKG not in resumed(), resumed()[-80:])
    check('app keeps running in the background', bool(pid()))
    start_app()
    time.sleep(3)
    check('reopening shows the same page without restarting', url().startswith(SITE), url())


def t_offline_session():
    before = url()
    network(False)
    time.sleep(4)
    js("location.reload()")
    wait_for(lambda: url().startswith('https://localhost/error.html'), 25)
    time.sleep(2)
    xml = ui()
    shot('08-offline')
    tx = texts(xml)
    note('offline screen: %s | %s' % (url(), tx[:6]))
    check('offline: custom screen instead of the browser error', url().startswith('https://localhost/error.html'), url())
    check('offline: "No Internet Connection" + Retry shown', 'No Internet Connection' in tx and 'Retry' in tx, tx[:6])
    network(True)
    back_online = wait_for(on_site, 75, 2)
    time.sleep(2)
    shot('09-reconnected')
    check('reconnect: website returns automatically when internet is back', bool(back_online), url())
    check('reconnect: reopens the page that failed', bool(back_online) and url().split('?')[0] == before.split('?')[0], '%s vs %s' % (url(), before))


def t_offline_start():
    network(False)
    time.sleep(3)
    adb('shell', 'am', 'force-stop', PKG)
    start_app()
    tx = wait_for(lambda: [t for t in texts(ui()) if 'No Internet' in t] and texts(ui()), 20, 2) or []
    shot('10-offline-start')
    check('start without internet: "No Internet Connection" screen', 'No Internet Connection' in tx, tx[:6])
    network(True)
    check('start without internet: loads the site when internet returns', bool(wait_for(on_site, 75, 2)), url())
    shot('11-online-again')


def t_logs():
    log = adb('logcat', '-d', timeout=60)
    with open(OUT + '/logcat.txt', 'w') as f:
        f.write(log)
    crashes = [ln for ln in log.splitlines() if 'FATAL EXCEPTION' in ln]
    ours = [ln for ln in log.splitlines() if re.search(r' [EW] BwpNative', ln)]
    check('no crash (FATAL EXCEPTION) in logcat', not crashes, crashes[:2])
    check('no errors logged by the BWP plugin', not ours, [x[-160:] for x in ours[:4]])


for label, test in [('launch', t_launch), ('keyboard', t_keyboard), ('download', t_download), ('print', t_print),
                    ('share', t_share), ('refresh', t_refresh), ('back', t_back), ('offline session', t_offline_session),
                    ('offline start', t_offline_start), ('logs', t_logs)]:
    run(label, test)

network(True)
failed = [x for x in lines if x.startswith('FAIL')]
passed = [x for x in lines if x.startswith('PASS')]
with open(OUT + '/SMOKE-android.md', 'w') as f:
    f.write('### Emulator smoke test (Android %s)\n\n' % adb('shell', 'getprop', 'ro.build.version.release').strip())
    f.write('%d passed, %d failed\n\n```\n%s\n```\n' % (len(passed), len(failed), '\n'.join(lines)))
print('\n%d passed, %d failed' % (len(passed), len(failed)))
