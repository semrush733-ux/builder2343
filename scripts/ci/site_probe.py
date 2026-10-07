#!/usr/bin/env python3
"""
Diagnostic: how does the public login page of the site work?
Fetches the login page and the scripts it loads (public files only, no login, no form posts)
and prints the parts that matter for running the site inside an app: redirects, other hosts,
new windows, storage, passkeys / OTP / device checks, and the endpoints the login form calls.
"""
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

SITE = 'https://bill.bwpexperts.com'
AGENTS = {
    'app (Android WebView)': 'Mozilla/5.0 (Linux; Android 15; Pixel 6 Build/AP3A; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/126.0.0.0 Mobile Safari/537.36',
    'Chrome on Android': 'Mozilla/5.0 (Linux; Android 15; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
}
out = []


def say(text=''):
    out.append(text)
    print(text)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def fetch(url, agent, follow=True, extra=None):
    headers = {'User-Agent': agent, 'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8'}
    headers.update(extra or {})
    opener = urllib.request.build_opener() if follow else urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(urllib.request.Request(url, headers=headers), timeout=30) as res:
            return res.status, res.geturl(), dict(res.headers), res.read(1500000).decode('utf-8', 'replace')
    except urllib.error.HTTPError as exc:
        return exc.code, url, dict(exc.headers), exc.read(200000).decode('utf-8', 'replace')
    except Exception as exc:  # noqa: BLE001
        return 0, url, {}, repr(exc)


say('# Login flow probe')
pages = {}
for label, agent in AGENTS.items():
    for path in ['/', '/login', '/seller', '/seller/login', '/seller-login', '/sellers', '/admin', '/dashboard', '/app', '/portal', '/wp-login.php', '/wp-admin/']:
        status, final, headers, body = fetch(SITE + path, agent, follow=False)
        loc = headers.get('Location') or headers.get('location') or ''
        title = re.search(r'<title[^>]*>(.*?)</title>', body, re.S | re.I)
        say('%-22s %-16s -> %s %s | title: %s | bytes: %d' % (label, path, status, ('-> ' + loc) if loc else '', (title.group(1).strip() if title else '')[:50], len(body)))
        if path == '/login':
            pages[label] = (status, headers, body)
    say()

status, headers, html = pages['app (Android WebView)']
say('## Response headers of /login (as the app)')
for key in sorted(headers):
    if key.lower() in ('set-cookie', 'content-security-policy', 'permissions-policy', 'x-frame-options', 'cache-control', 'server', 'x-powered-by', 'referrer-policy', 'cross-origin-opener-policy', 'strict-transport-security', 'x-redirect-by', 'link'):
        say('%s: %s' % (key, headers[key][:400]))
a, b = pages['app (Android WebView)'][2], pages['Chrome on Android'][2]
say('same HTML length for app and Chrome: %s (%d vs %d)' % (abs(len(a) - len(b)) < 200, len(a), len(b)))
say()

say('## Login page structure')
for m in re.finditer(r'<form[^>]*>', html, re.I):
    say('form: ' + m.group(0)[:300])
for m in re.finditer(r'<input[^>]*>', html, re.I):
    say('input: ' + re.sub(r'\s+', ' ', m.group(0))[:240])
for m in re.finditer(r'<(?:a|button)[^>]*>(.*?)</(?:a|button)>', html, re.S | re.I):
    text = re.sub(r'<[^>]+>', ' ', m.group(1)).strip()
    say('link/button: %s | %s' % (re.sub(r'\s+', ' ', m.group(0).split('>')[0])[:200], text[:60]))
scripts = re.findall(r'<script[^>]+src=["\']([^"\']+)["\']', html, re.I)
say('scripts: ' + ', '.join(s.split('?')[0].replace(SITE, '') for s in scripts))
inline = re.findall(r'<script(?![^>]*src=)[^>]*>(.*?)</script>', html, re.S | re.I)
say('inline scripts: %d' % len(inline))
for chunk in inline:
    chunk = chunk.strip()
    if chunk and ('ajax' in chunk.lower() or 'rest' in chunk.lower() or 'nonce' in chunk.lower() or 'bwp' in chunk.lower()):
        # hide values that look like tokens
        say('inline: ' + re.sub(r'(nonce|token|key)("?\s*[:=]\s*"?)[A-Za-z0-9_\-]{6,}', r'\1\2<hidden>', re.sub(r'\s+', ' ', chunk))[:900])
say()

say('## What the site scripts do (keywords that matter inside an app)')
KEYS = ['window.open', 'target="_blank"', "target='_blank'", 'location.href', 'location.assign', 'location.replace', 'window.top', 'window.parent', 'self !== top', 'top.location',
        'navigator.credentials', 'PublicKeyCredential', 'webauthn', 'passkey', 'otp', 'two_factor', '2fa', 'totp', 'device', 'fingerprint', 'userAgent', 'navigator.platform',
        'localStorage', 'sessionStorage', 'document.cookie', 'serviceWorker', 'Notification', 'recaptcha', 'turnstile', 'hcaptcha', 'seller', 'role', 'redirect', 'wp-json', 'admin-ajax',
        'standalone', 'matchMedia', 'X-Requested-With', 'popup', 'postMessage', 'BroadcastChannel', 'http://']
for src in scripts:
    url = urllib.parse.urljoin(SITE + '/login', src)
    if urllib.parse.urlparse(url).hostname != 'bill.bwpexperts.com':
        say('external script: ' + url.split('?')[0])
        continue
    st, _, _, js = fetch(url, AGENTS['app (Android WebView)'])
    name = url.split('?')[0].replace(SITE, '')
    if '/wp-includes/' in name:
        say('%s (%d bytes) - WordPress core, skipped' % (name, len(js)))
        continue
    say('### %s (HTTP %s, %d bytes)' % (name, st, len(js)))
    for key in KEYS:
        hits = [m.start() for m in re.finditer(re.escape(key), js, re.I)]
        if not hits:
            continue
        say('- %s x%d' % (key, len(hits)))
        for pos in hits[:4]:
            snippet = re.sub(r'\s+', ' ', js[max(0, pos - 140):pos + 220])
            say('    ...%s...' % snippet)
    urls = sorted(set(re.findall(r'["\'](/(?:wp-json|login|seller|admin|dashboard|logout|auth|api|portal|app)[A-Za-z0-9_\-/{}:.?=&]*)["\']', js)))
    if urls:
        say('- paths mentioned: ' + ', '.join(urls[:60]))
    hosts = sorted(set(re.findall(r'https?://([a-z0-9.-]+\.[a-z]{2,})', js, re.I)))
    if hosts:
        say('- hosts mentioned: ' + ', '.join(hosts[:30]))
say()

# ----------------------------------------------------------------------------- the header Android web views add
# Android's in-app web view adds "X-Requested-With: <app package>" to every request, including
# normal page loads (not on all devices - it depends on the WebView version). The site's own
# script uses "X-Requested-With: fetch" for its background calls, so the server may treat any
# request that carries the header as a background call. Compare both.
say('## Does the server answer differently when the request carries X-Requested-With?')
wv = AGENTS['app (Android WebView)']
for path in ['/login', '/dashboard', '/sellers', '/notifications', '/api/notifications/count?after=0', '/']:
    row = []
    for label, extra in [('without header', {}), ('with app header', {'X-Requested-With': 'com.bwpexperts.billing'}), ('with "fetch"', {'X-Requested-With': 'fetch', 'Accept': 'application/json'})]:
        st, final, hd, body = fetch(SITE + path, wv, follow=False, extra=extra)
        ctype = (hd.get('Content-Type') or hd.get('content-type') or '').split(';')[0]
        loc = hd.get('Location') or hd.get('location') or ''
        snippet = re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', body)).strip()[:70]
        row.append('%s: %s %s%s | %s' % (label, st, ctype, (' -> ' + loc.replace(SITE, '')) if loc else '', snippet if st != 200 or 'json' in ctype else '(page)'))
    say('%s' % path)
    for r in row:
        say('    ' + r)
say()

# ----------------------------------------------------------------------------- browser check
# If the host answers with its "Checking your browser" page (HTTP 403 + script), find out
# whether a real browser engine gets through, and whether looking like an in-app web view
# (the "; wv" marker and the X-Requested-With header Android adds) makes a difference.
def browser_check():
    try:
        from playwright.sync_api import sync_playwright
    except Exception as exc:  # noqa: BLE001
        say('browser check skipped: %r' % exc)
        return
    challenge = pages['app (Android WebView)'][2]
    say('## The "checking your browser" page')
    say('status as plain request: %s' % pages['app (Android WebView)'][0])
    text = re.sub(r'<(script|style)[^>]*>.*?</\1>', ' ', challenge, flags=re.S | re.I)
    say('visible text: ' + re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', text)).strip()[:400])
    for chunk in re.findall(r'<script(?![^>]*src=)[^>]*>(.*?)</script>', challenge, re.S | re.I):
        say('inline script (%d chars): %s' % (len(chunk), re.sub(r'[A-Za-z0-9+/=_-]{24,}', '<long-value>', re.sub(r'\s+', ' ', chunk))[:700]))
    say()
    variants = [
        ('in-app web view as it is today ("; wv" + X-Requested-With)', AGENTS['app (Android WebView)'], {'X-Requested-With': 'com.bwpexperts.billing'}),
        ('in-app web view without the X-Requested-With header', AGENTS['app (Android WebView)'], {}),
        ('same engine presenting itself as Chrome', AGENTS['Chrome on Android'], {}),
    ]
    say('## Does a real browser engine get through?')
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for label, agent, extra in variants:
            ctx = browser.new_context(user_agent=agent, extra_http_headers=extra, viewport={'width': 412, 'height': 900}, is_mobile=True, has_touch=True)
            page = ctx.new_page()
            statuses = []
            page.on('response', lambda r: statuses.append((r.status, r.url.replace(SITE, '').split('?')[0])) if r.request.is_navigation_request() or 'hcdn-cgi' in r.url else None)
            try:
                page.goto(SITE + '/login', wait_until='domcontentloaded', timeout=45000)
            except Exception as exc:  # noqa: BLE001
                say('%s: navigation error %r' % (label, exc))
            title = ''
            for _ in range(25):
                try:
                    title = page.title()
                except Exception:  # noqa: BLE001
                    title = '(navigating)'
                if title and 'Checking your browser' not in title and title != '(navigating)':
                    break
                page.wait_for_timeout(1000)
            inputs = 0
            post = ''
            try:
                inputs = page.locator('input:not([type=hidden])').count()
                # A background request like the ones the login form makes (GET only, nothing is submitted).
                post = page.evaluate("fetch('/login', {credentials: 'include', cache: 'no-store'}).then(function (r) { return 'HTTP ' + r.status; }, function (e) { return 'failed ' + e; })")
            except Exception as exc:  # noqa: BLE001
                post = repr(exc)[:80]
            cookies = sorted(c['name'] for c in ctx.cookies())
            say('- %s' % label)
            say('    responses: %s' % statuses[:8])
            say('    ends on: "%s" | inputs: %d | background request: %s | cookies: %s' % (title[:60], inputs, post, cookies))
            ctx.close()
        browser.close()
    say()


if pages['app (Android WebView)'][0] == 403 or 'Checking your browser' in pages['app (Android WebView)'][2]:
    try:
        browser_check()
    except Exception as exc:  # noqa: BLE001
        say('browser check failed: %r' % exc)
else:
    say('## Browser check')
    say('This machine was not asked to pass the "checking your browser" page (plain requests got HTTP %s), so there was nothing to test.' % pages['app (Android WebView)'][0])
    say()

with open('probe-output.md', 'w', encoding='utf-8') as f:
    f.write('\n'.join(out) + '\n')
