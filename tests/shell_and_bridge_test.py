"""
BWP Billing - browser test for the web part of the app (src/).

Checks the launch / offline / error screens and the injected bridge script in headless Chromium
against a local HTTPS mock of the billing site (login cookie, redirects, file downloads). The native
plugin is replaced by a recorder, so this proves what the page asks the native side to do - it does
NOT test the Android / iOS code itself.

Requirements: Python 3, "pip install playwright", "playwright install chromium", openssl.
Run:          python tests/shell_and_bridge_test.py
"""
import subprocess, tempfile, time
import base64, json, mimetypes, os, sys
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'src')
SITE = 'https://bill.bwpexperts.com'
SHOTS = os.path.join(HERE, 'output')
os.makedirs(SHOTS, exist_ok=True)
CERT_DIR = tempfile.mkdtemp()
subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', os.path.join(CERT_DIR, 'key.pem'), '-out', os.path.join(CERT_DIR, 'cert.pem'),
                '-days', '2', '-subj', '/CN=bill.bwpexperts.com', '-addext', 'subjectAltName=DNS:bill.bwpexperts.com'], check=True, capture_output=True)
PDF = b'%PDF-1.4\n% mock invoice\n' + bytes(range(256))
results = []

def check(name, cond, detail=''):
    results.append((name, bool(cond), detail))
    print(('PASS ' if cond else 'FAIL ') + name + (('  -> ' + str(detail)) if detail and not cond else ''))

DASH = '''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Dashboard</title><style>body{margin:0;background:#f4f6f8;font-family:sans-serif}header{background:#014f4a;color:#fff;padding:16px}
#list{height:120px;overflow:auto;border:1px solid #ccc}#list div{height:400px}footer{position:fixed;bottom:0;left:0;right:0;height:40px;background:#222}</style></head>
<body><header id="hdr">BWP Billing</header>
<p><a id="pdf" href="/files/invoice-123.pdf">Invoice PDF</a></p>
<p><a id="dl" href="/export/report" download="report.csv">Report</a></p>
<p><a id="expired" href="/files/expired.pdf">Expired</a></p>
<p><a id="blank" href="/invoices/5" target="_blank">Invoice 5</a></p>
<p><a id="ext" href="https://example.org/">External</a></p>
<p><a id="plain" href="/customers">Customers</a></p>
<p><button id="blobbtn" onclick="var a=document.createElement('a');a.href=window.URL.createObjectURL(new Blob(['a,b\\n1,2\\n'],{type:'text/csv'}));a.download='export.csv';a.click();">Blob</button></p>
<p><a id="datalink" href="data:text/csv;charset=utf-8,name%2Ctotal%0AAli%2C50%0A" download="data-export.csv">Data</a></p>
<p><button id="printbtn" onclick="window.print()">Print</button></p>
<p><button id="openbtn" onclick="window.open('/invoices/9')">Open</button></p>
<div id="list"><div>long</div></div>
<input id="amount" type="number">
<footer></footer></body></html>'''


import ssl, threading, http.server

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *a): pass
    def send(self, status, body=b'', headers=None):
        if isinstance(body, str): body = body.encode()
        self.send_response(status)
        for k, v in (headers or {}).items(): self.send_header(k, v)
        self.send_header('Content-Length', str(len(body))); self.send_header('Cache-Control', 'no-store')
        self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        path = self.path.split('?')[0]
        logged_in = 'bwpsession=abc123' in (self.headers.get('Cookie') or '')
        # Strict policy like a real billing site: page scripts may only connect to the site itself.
        html = {'content-type': 'text/html; charset=utf-8',
                'Content-Security-Policy': "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'"}
        if path == '/pending':
            return self.send(204, b'', {})
        if path == '/login':
            return self.send(200, '<html><title>Login</title><body>login</body></html>', dict(html, **{'Set-Cookie': 'bwpsession=abc123; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=86400'}))
        if path == '/logout':
            return self.send(200, '<html><title>Bye</title></html>', dict(html, **{'Set-Cookie': 'bwpsession=; Path=/; Secure; HttpOnly; Max-Age=0'}))
        if path.startswith('/files/') or path.startswith('/export/'):
            if not logged_in or path == '/files/expired.pdf':
                return self.send(302, b'', {'Location': '/login'})
            if path == '/files/invoice-123.pdf':
                return self.send(200, PDF, {'content-type': 'application/pdf', 'content-disposition': 'attachment; filename="INV-000123.pdf"'})
            if path == '/export/report':
                return self.send(200, b'id,total\n1,50\n', {'content-type': 'text/csv; charset=utf-8'})
            return self.send(404, 'nf', html)
        title = 'Dashboard' if path in ('', '/') else path
        return self.send(200, DASH.replace('<title>Dashboard</title>', '<title>%s</title>' % title), html)

httpd = http.server.ThreadingHTTPServer(('127.0.0.1', 8443), Handler)
sslctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); sslctx.load_cert_chain(os.path.join(CERT_DIR, 'cert.pem'), os.path.join(CERT_DIR, 'key.pem'))
httpd.socket = sslctx.wrap_socket(httpd.socket, server_side=True)
threading.Thread(target=httpd.serve_forever, daemon=True).start()

def local(route, request):
    path = request.url.split('localhost', 1)[1].split('?')[0].lstrip('/') or 'index.html'
    f = os.path.join(SRC, path)
    if not os.path.isfile(f):
        return route.fulfill(status=404, body='nf')
    return route.fulfill(status=200, body=open(f, 'rb').read(), headers={'content-type': mimetypes.guess_type(f)[0] or 'application/octet-stream'})

STUB = '''
window.__calls = [];
(function(){ var methods=['saveFile','printPage','share','setTheme','setRefreshAllowed','pageReady','setScreenSecure','openExternal','getLastUrl'];
 var p={}; methods.forEach(function(m){ p[m]=function(a){ var rec={m:m,a:a}; try{ var all=JSON.parse(sessionStorage.getItem('calls')||'[]'); all.push({m:m,a:(m==='saveFile'?{name:a.name,mime:a.mime,len:a.data.length,data:a.data.slice(0,4000)}:a)}); sessionStorage.setItem('calls',JSON.stringify(all)); }catch(e){} window.__calls.push(rec); return Promise.resolve(m==='getLastUrl'?{url:'https://bill.bwpexperts.com/invoices/77'}:{}); }; });
 window.Capacitor={Plugins:{BwpNative:p}}; })();
'''
CONFIG = json.dumps({'platform': 'android', 'homeUrl': SITE + '/', 'allowedHosts': ['bill.bwpexperts.com'], 'pullToRefresh': True,
                     'downloadExtensions': ['pdf', 'csv', 'xls', 'xlsx', 'doc', 'docx', 'zip'], 'secureScreenPaths': []})
BRIDGE = 'window.__BWP_CONFIG__ = ' + CONFIG + ';\n' + open(os.path.join(SRC, 'bwp-bridge.js')).read()

def calls(page, name=None):
    all_ = json.loads(page.evaluate("sessionStorage.getItem('calls')||'[]'"))
    return [c for c in all_ if name is None or c['m'] == name]

with sync_playwright() as p:
    browser = p.chromium.launch(env={k: v for k, v in os.environ.items() if 'proxy' not in k.lower()}, args=['--host-resolver-rules=MAP bill.bwpexperts.com 127.0.0.1:8443', '--ignore-certificate-errors', '--no-proxy-server', '--disable-features=LocalNetworkAccessChecks'])
    errors = []

    def new_ctx(bridge=True):
        ctx = browser.new_context(ignore_https_errors=True, viewport={'width': 390, 'height': 800}, device_scale_factor=2, has_touch=True, is_mobile=True)
        ctx.route('https://localhost/**', local)
        ctx.route('https://example.org/**', lambda r, q: r.fulfill(status=200, body='<title>ext</title>ext', headers={'content-type': 'text/html'}))
        if bridge:
            # mimic the native side: bridge script first (document start), Capacitor bridge after it
            ctx.add_init_script(BRIDGE)
            ctx.add_init_script(STUB)
        return ctx

    # ---------------- shell: launch online
    ctx = new_ctx(bridge=False); page = ctx.new_page()
    page.on('pageerror', lambda e: errors.append('shell: ' + str(e)))
    page.goto('https://localhost/index.html', wait_until='commit')
    page.wait_for_url(SITE + '/login', timeout=8000)
    check('launch: goes to the billing site login page', page.url == SITE + '/login')
    page.go_back(); page.wait_for_timeout(300)
    check('launch: local page not kept in history (Back does not return to it)', not page.url.startswith('https://localhost'), page.url)
    ctx.close()

    OFFLINE_FLAG = "Object.defineProperty(navigator,'onLine',{configurable:true,get:function(){return window.__online===true;}});"

    # ---------------- shell: the phone wrongly reports "offline" (seen on some devices) - the app must still load
    ctx = new_ctx(bridge=False); page = ctx.new_page()
    page.on('pageerror', lambda e: errors.append('shell: ' + str(e)))
    page.add_init_script(OFFLINE_FLAG)
    page.goto('https://localhost/index.html', wait_until='commit')
    page.wait_for_url(SITE + '/login', timeout=8000)
    check('launch: loads the site even when the phone reports "offline"', page.url == SITE + '/login')
    ctx.close()

    # ---------------- shell: slow server - keep loading, never show the error screen on a timer
    # The mock answers "204 No Content", so the browser stays on the launch page exactly as it
    # does while a slow server has not answered yet.
    ctx = new_ctx(bridge=False); page = ctx.new_page()
    page.on('pageerror', lambda e: errors.append('shell: ' + str(e)))
    slow_cfg = json.loads(open(os.path.join(SRC, 'app-config.json')).read()); slow_cfg['homeUrl'] = SITE + '/pending'
    ctx.route('https://localhost/app-config.json', lambda r, q: r.fulfill(status=200, body=json.dumps(slow_cfg), headers={'content-type': 'application/json'}))
    page.goto('https://localhost/index.html')
    page.wait_for_timeout(1500)
    check('launch screen: shows app name / company / loading text',
          page.inner_text('#app-name') == 'BWP Billing' and page.inner_text('#app-company') == 'by BWP Experts' and page.inner_text('#loading-text') == 'Loading your dashboard...')
    check('launch screen: logo loaded', page.evaluate("document.querySelector('.brand img').naturalWidth") > 0)
    page.screenshot(path=SHOTS + '/shell-loading.png')
    check('slow server: no "still loading" hint in the first seconds', page.is_visible('#state-loading') and page.is_hidden('#slow-text'))
    page.wait_for_timeout(12000)
    check('slow server: after 13 s still on the loading screen, with a "still loading" hint', page.is_visible('#state-loading') and page.is_visible('#slow-text') and page.is_hidden('#state-unreachable') and page.is_hidden('#state-offline'))
    page.screenshot(path=SHOTS + '/shell-slow.png')
    page.wait_for_timeout(19000)
    check('slow server: after 32 s still loading (no error screen), "Try again" offered', page.is_visible('#state-loading') and page.is_visible('#slow-retry') and page.is_hidden('#state-unreachable') and page.is_hidden('#state-offline'))
    ctx.close()

    # ---------------- shell: error screen while offline; Retry always tries; reconnect
    ctx = new_ctx(bridge=False); page = ctx.new_page()
    page.on('pageerror', lambda e: errors.append('shell: ' + str(e)))
    page.add_init_script(OFFLINE_FLAG)
    page.goto('https://localhost/error.html')
    page.wait_for_selector('#state-offline.is-active', timeout=5000)
    check('offline: "No Internet Connection" screen', 'No Internet Connection' in page.inner_text('#state-offline'))
    check('offline: message text', 'Please check your internet connection and try again.' in page.inner_text('#state-offline'))
    page.evaluate("window.__bwpShell.setErrorDetail('net::ERR_NAME_NOT_RESOLVED (-2)')")
    check('offline: technical reason shown small under the message', page.is_visible('#error-detail') and page.inner_text('#error-detail') == 'Details: net::ERR_NAME_NOT_RESOLVED (-2)', page.inner_text('#error-detail'))
    page.screenshot(path=SHOTS + '/shell-offline.png')
    page.click('#state-offline button[data-action=retry]')
    page.wait_for_url(SITE + '/login', timeout=8000)
    check('offline: Retry tries to load even when the phone still reports "offline"', page.url == SITE + '/login')
    page.goto('https://localhost/error.html'); page.wait_for_selector('#state-offline.is-active', timeout=5000)
    page.evaluate("window.__online=true; window.dispatchEvent(new Event('online'));")
    page.wait_for_url(SITE + '/login', timeout=8000)
    check('reconnect: loads the site automatically when internet returns', page.url == SITE + '/login')
    page.goto('https://localhost/error.html'); page.wait_for_selector('.state.is-active', timeout=5000)
    page.evaluate("window.__online=true; window.dispatchEvent(new Event('online'));"); page.wait_for_timeout(1500)
    check('reconnect: a second automatic reconnect within 30 s is not made (no reload loop)', page.url == 'https://localhost/error.html', page.url)
    ctx.close()

    # ---------------- shell: error screen notices by itself that the site is reachable again
    ctx = new_ctx(bridge=False); page = ctx.new_page()
    page.goto('https://localhost/error.html'); page.wait_for_selector('#state-unreachable.is-active', timeout=5000)
    page.wait_for_url(SITE + '/login', timeout=16000)
    check('reconnect: error screen reopens the site by itself once it answers', page.url == SITE + '/login')
    ctx.close()

    # ---------------- shell: error page
    ctx = new_ctx(bridge=False); page = ctx.new_page()
    page.on('pageerror', lambda e: errors.append('shell: ' + str(e)))
    page.goto('https://localhost/error.html')
    page.wait_for_selector('#state-unreachable.is-active')
    check('error page: "We couldn\'t connect to BWP Billing."', "We couldn't connect to BWP Billing." in page.inner_text('#state-unreachable'))
    page.screenshot(path=SHOTS + '/shell-error.png')
    page.evaluate("window.__bwpShell.setRetryUrl('https://bill.bwpexperts.com/invoices/42')")
    check('error page: "Go to dashboard" appears when retry target is another page', page.is_visible('#home-link'))
    page.evaluate("window.__bwpShell.setRetryUrl('https://evil.example/x')")
    page.click('#state-unreachable button[data-action=retry]')
    page.wait_for_url(SITE + '/**', timeout=8000)
    check('error page: retry URL outside the allowed host is ignored (goes home)', page.url == SITE + '/login', page.url)
    page.goto('https://localhost/error.html'); page.wait_for_selector('#state-unreachable.is-active')
    page.evaluate("window.__bwpShell.setRetryUrl('https://bill.bwpexperts.com/invoices/42')")
    page.click('#state-unreachable button[data-action=retry]')
    page.wait_for_url(SITE + '/invoices/42', timeout=8000)
    check('error page: Retry reopens the page that failed', page.url == SITE + '/invoices/42')
    ctx.close()

    # ---------------- bridge on the website
    ctx = new_ctx(); page = ctx.new_page()
    page.on('pageerror', lambda e: errors.append('bridge: ' + str(e)))
    popups = []; ctx.on('page', lambda pg: popups.append(pg))
    page.goto(SITE + '/login'); page.goto(SITE + '/'); page.wait_for_timeout(1300)
    check('bridge: loaded once', page.evaluate("!!window.__bwp && window.__bwp.version") == '1.0.0')
    check('bridge: pageReady sent', len(calls(page, 'pageReady')) >= 1)
    th = calls(page, 'setTheme')
    check('bridge: status bar colour = header colour, bottom = footer colour', th and th[-1]['a'] == {'top': '#014f4a', 'bottom': '#222222'}, th)

    page.click('#pdf'); page.wait_for_timeout(700)
    sv = calls(page, 'saveFile')
    ok = len(sv) == 1 and sv[0]['a']['name'] == 'INV-000123.pdf' and sv[0]['a']['mime'] == 'application/pdf' and base64.b64decode(sv[0]['a']['data'] + '=' * (-len(sv[0]['a']['data']) % 4))[:len(PDF)] == PDF
    check('download: PDF link -> saveFile with header file name and exact bytes', ok, sv)
    check('download: page did not navigate away', page.url == SITE + '/')

    page.click('#dl'); page.wait_for_timeout(600)
    sv = calls(page, 'saveFile')
    check('download: <a download> link -> saveFile(report.csv, text/csv)', len(sv) == 2 and sv[1]['a']['name'] == 'report.csv' and sv[1]['a']['mime'] == 'text/csv', sv[1:] )

    page.click('#blobbtn'); page.wait_for_timeout(600)
    sv = calls(page, 'saveFile')
    check('download: script-generated blob -> saveFile(export.csv), despite the site CSP', len(sv) == 3 and sv[2]['a']['name'] == 'export.csv' and base64.b64decode(sv[2]['a']['data']) == b'a,b\n1,2\n', sv[2:])

    page.evaluate("window.__bwp.download('https://bill.bwpexperts.com/files/invoice-123.pdf','guess.bin','application/pdf')"); page.wait_for_timeout(600)
    check('download: native DownloadListener hand-over works', len(calls(page, 'saveFile')) == 4)
    page.click('#datalink'); page.wait_for_timeout(600)
    sv = calls(page, 'saveFile')
    check('download: data: link -> saveFile(data-export.csv)', len(sv) == 5 and sv[4]['a']['name'] == 'data-export.csv' and sv[4]['a']['mime'] == 'text/csv' and base64.b64decode(sv[4]['a']['data']) == b'name,total\nAli,50\n', sv[4:])

    page.click('#printbtn'); page.wait_for_timeout(200)
    check('print: window.print -> native print dialog', len(calls(page, 'printPage')) == 1)

    r = page.evaluate("typeof navigator.share === 'function' ? navigator.share({title:'Invoice',text:'INV-1',url:'https://bill.bwpexperts.com/i/1'}).then(function(){return 'ok'}) : 'missing'")
    sh = calls(page, 'share')
    check('share: navigator.share -> native share sheet', r == 'ok' and sh and sh[0]['a'] == {'title': 'Invoice', 'text': 'INV-1', 'url': 'https://bill.bwpexperts.com/i/1'}, (r, sh))

    # pull-to-refresh guard
    page.evaluate("document.getElementById('list').scrollTop = 0")
    page.touchscreen.tap(100, 30); page.wait_for_timeout(150)
    ra = calls(page, 'setRefreshAllowed')
    check('refresh guard: allowed at top of page', ra and ra[-1]['a'] == {'allowed': True}, ra)
    page.evaluate("document.getElementById('list').scrollTop = 60")
    box = page.locator('#list').bounding_box()
    page.touchscreen.tap(box['x'] + 20, box['y'] + 20); page.wait_for_timeout(150)
    ra = calls(page, 'setRefreshAllowed')
    check('refresh guard: blocked inside a scrolled list', ra and ra[-1]['a'] == {'allowed': False}, ra)
    page.evaluate("window.scrollTo(0,0); document.body.style.overflowY='hidden'")
    page.touchscreen.tap(100, 30); page.wait_for_timeout(150)
    page.evaluate("document.body.style.overflowY=''")

    # offline banner
    banner = "(function(){var e=document.querySelector('[data-bwp-notice]');return !!e && e.style.display==='block' && e.textContent==='No internet connection'})()"
    page.evaluate("window.dispatchEvent(new Event('offline'))"); page.wait_for_timeout(700)
    check('offline banner: a false "offline" signal (site still answers) shows nothing', not page.evaluate(banner))
    ctx.route(SITE + '/favicon.ico*', lambda r, q: r.abort())
    page.evaluate("Object.defineProperty(navigator,'onLine',{configurable:true,get:function(){return false;}}); window.dispatchEvent(new Event('offline'))"); page.wait_for_timeout(700)
    check('offline banner: shown when the site really cannot be reached', page.evaluate(banner))
    page.screenshot(path=SHOTS + '/site-offline-banner.png')
    ctx.unroute(SITE + '/favicon.ico*')
    page.evaluate("Object.defineProperty(navigator,'onLine',{configurable:true,get:function(){return true;}}); window.dispatchEvent(new Event('online'))"); page.wait_for_timeout(2200)
    check('offline banner: hidden after reconnect', page.evaluate("document.querySelector('[data-bwp-notice]').style.display") == 'none')

    # links
    page.click('#blank'); page.wait_for_url(SITE + '/invoices/5', timeout=5000)
    check('links: internal target=_blank stays in the app (no new window)', page.url == SITE + '/invoices/5' and len(popups) == 0, (page.url, len(popups)))
    page.go_back(); page.wait_for_url(SITE + '/')
    page.click('#openbtn'); page.wait_for_url(SITE + '/invoices/9', timeout=5000)
    check('links: window.open(internal) stays in the app', page.url == SITE + '/invoices/9' and len(popups) == 0)
    page.go_back(); page.wait_for_url(SITE + '/')
    page.click('#expired'); page.wait_for_url(SITE + '/login', timeout=5000)
    check('session expired: file link that returns the login page shows the login page', page.url == SITE + '/login')
    check('session expired: nothing saved', len(calls(page, 'saveFile')) == 5)
    page.goto(SITE + '/logout'); page.goto(SITE + '/'); page.wait_for_timeout(400)
    page.click('#pdf'); page.wait_for_url(SITE + '/login', timeout=5000)
    check('logged out: protected file is not saved, login page is shown', page.url == SITE + '/login' and len(calls(page, 'saveFile')) == 5)
    page.goto(SITE + '/'); page.wait_for_timeout(300)
    page.click('#plain'); page.wait_for_url(SITE + '/customers', timeout=5000)
    check('links: normal internal link untouched', page.url == SITE + '/customers')
    ctx.close()

    # ---------------- native channel transports (Android WebMessageListener / iOS message handler)
    ANDROID_CHANNEL = """
    window.__sent = [];
    window.bwpNative = { postMessage: function (raw) { var m = JSON.parse(raw); window.__sent.push(m); var self = this;
      setTimeout(function () { self.onmessage && self.onmessage({ data: JSON.stringify(m.method === 'fail' ? { id: m.id, ok: false, error: 'nope' } : { id: m.id, ok: true, result: { echo: m.method, args: m.args } }) }); }, 5); } };
    """
    ctx = browser.new_context(ignore_https_errors=True, viewport={'width': 390, 'height': 800})
    ctx.add_init_script(ANDROID_CHANNEL); ctx.add_init_script(BRIDGE)
    page = ctx.new_page(); page.goto(SITE + '/login'); page.goto(SITE + '/'); page.wait_for_timeout(600)
    r = page.evaluate("window.__bwp.call('getLastUrl', {a: 1})")
    check('android channel: request / reply round trip', r == {'echo': 'getLastUrl', 'args': {'a': 1}}, r)
    r = page.evaluate("window.__bwp.call('fail', {}).then(function(){return 'resolved'}, function(e){return 'rejected: ' + e.message})")
    check('android channel: native error rejects the promise', r == 'rejected: nope', r)
    sent = page.evaluate("window.__sent.map(function(m){return m.method})")
    check('android channel: page start calls go through it (pageReady, setTheme)', 'pageReady' in sent and 'setTheme' in sent, sent)
    page.click('#pdf'); page.wait_for_timeout(700)
    sent = page.evaluate("window.__sent.filter(function(m){return m.method === 'saveFile'}).map(function(m){return m.args.name})")
    check('android channel: PDF download delivered as saveFile', sent == ['INV-000123.pdf'], sent)
    ctx.close()

    IOS_CHANNEL = """
    window.__sent = [];
    window.webkit = { messageHandlers: { bwpNative: { postMessage: function (m) { window.__sent.push(m); return Promise.resolve({ echo: m.method }); } } } };
    """
    ctx = browser.new_context(ignore_https_errors=True, viewport={'width': 390, 'height': 800})
    ctx.add_init_script(IOS_CHANNEL); ctx.add_init_script(BRIDGE.replace('"platform": "android"', '"platform": "ios"'))
    page = ctx.new_page(); page.goto(SITE + '/login'); page.goto(SITE + '/'); page.wait_for_timeout(600)
    r = page.evaluate("window.__bwp.call('getLastUrl', {})")
    sent = page.evaluate("window.__sent.map(function(m){return m.method})")
    check('ios channel: request / reply round trip', r == {'echo': 'getLastUrl'} and 'pageReady' in sent, (r, sent))
    ctx.close()

    # ---------------- bridge must stay out of other websites
    ctx = new_ctx(); page = ctx.new_page()
    page.goto('https://example.org/'); page.wait_for_timeout(300)
    check('bridge: inactive on other hosts', page.evaluate("typeof window.__bwp") == 'undefined')
    ctx.close()

    check('no JavaScript errors in shell or bridge', not errors, errors)
    browser.close()

bad = [r for r in results if not r[1]]
print('\n%d passed, %d failed' % (len(results) - len(bad), len(bad)))
sys.exit(1 if bad else 0)
