# Login flow probe
app (Android WebView)  /                -> 200  | title: bill.bwpexperts.com | bytes: 39501
app (Android WebView)  /login           -> 200  | title: BWP Experts Billing | bytes: 15342
app (Android WebView)  /seller          -> 302 -> https://bill.bwpexperts.com/login | title:  | bytes: 0
app (Android WebView)  /seller/login    -> 302 -> https://bill.bwpexperts.com/login | title:  | bytes: 0
app (Android WebView)  /seller-login    -> 302 -> https://bill.bwpexperts.com/login | title:  | bytes: 0
app (Android WebView)  /sellers         -> 302 -> https://bill.bwpexperts.com/login?next=%2Fsellers | title:  | bytes: 0
app (Android WebView)  /admin           -> 302 -> https://bill.bwpexperts.com/login | title:  | bytes: 0
app (Android WebView)  /dashboard       -> 302 -> https://bill.bwpexperts.com/login | title:  | bytes: 0
app (Android WebView)  /app             -> 302 -> https://bill.bwpexperts.com/login | title:  | bytes: 0
app (Android WebView)  /portal          -> 302 -> https://bill.bwpexperts.com/login | title:  | bytes: 0
app (Android WebView)  /wp-login.php    -> 302 -> https://bill.bwpexperts.com/login | title:  | bytes: 0
app (Android WebView)  /wp-admin/       -> 302 -> https://bill.bwpexperts.com/login?next=%2Fwp-admin%2F | title:  | bytes: 0

Chrome on Android      /                -> 200  | title: bill.bwpexperts.com | bytes: 39501
Chrome on Android      /login           -> 200  | title: BWP Experts Billing | bytes: 15342
Chrome on Android      /seller          -> 302 -> https://bill.bwpexperts.com/login | title:  | bytes: 0
Chrome on Android      /seller/login    -> 302 -> https://bill.bwpexperts.com/login | title:  | bytes: 0
Chrome on Android      /seller-login    -> 302 -> https://bill.bwpexperts.com/login | title:  | bytes: 0
Chrome on Android      /sellers         -> 302 -> https://bill.bwpexperts.com/login?next=%2Fsellers | title:  | bytes: 0
Chrome on Android      /admin           -> 302 -> https://bill.bwpexperts.com/login | title:  | bytes: 0
Chrome on Android      /dashboard       -> 302 -> https://bill.bwpexperts.com/login | title:  | bytes: 0
Chrome on Android      /app             -> 302 -> https://bill.bwpexperts.com/login | title:  | bytes: 0
Chrome on Android      /portal          -> 302 -> https://bill.bwpexperts.com/login | title:  | bytes: 0
Chrome on Android      /wp-login.php    -> 302 -> https://bill.bwpexperts.com/login | title:  | bytes: 0
Chrome on Android      /wp-admin/       -> 302 -> https://bill.bwpexperts.com/login?next=%2Fwp-admin%2F | title:  | bytes: 0

## Response headers of /login (as the app)
Cache-Control: no-store, no-cache, must-revalidate, max-age=0, private
Server: hcdn
Set-Cookie: __Host-bwpb_lc=C1MVqthIY6RCB1-i_3msbpRXbPhRLwE66ltr0FTkYwc; path=/; secure; HttpOnly; SameSite=Lax
content-security-policy: upgrade-insecure-requests
cross-origin-opener-policy: same-origin
permissions-policy: camera=(), microphone=(), geolocation=(), payment=(), usb=()
referrer-policy: same-origin
strict-transport-security: max-age=31536000
x-frame-options: DENY
same HTML length for app and Chrome: True (15342 vs 15342)

## Login page structure
form: <form method="post" action="https://bill.bwpexperts.com/login/identify" class="form" novalidate>
input: <input type="hidden" name="_bwpb" value="C1MVqthIY6RCB1-i_3msbpRXbPhRLwE66ltr0FTkYwc">
input: <input type="hidden" name="next" value="">
input: <input class="input input-lg" type="text" id="log" name="log" value="" autocomplete="username" autocapitalize="none" spellcheck="false" required data-focus-fine>
link/button: <button type="submit" class="btn btn-primary btn-block btn-lg" | Continue
scripts: /wp-content/plugins/bwp-experts-billing/assets/js/app.js
inline scripts: 0

## What the site scripts do (keywords that matter inside an app)
### /wp-content/plugins/bwp-experts-billing/assets/js/app.js (HTTP 200, 51146 bytes)
- location.href x3
    ...className = 'toast toast-note'; el.setAttribute('role', 'status'); var safe = ''; try { var u = new URL(item.url || '', window.location.href); if (u.origin === window.location.origin) { safe = u.href; } } catch (err) { safe = ''; } el.href = safe || (BASE + '/notifications'); var strong = document.createElement('strong'); strong....
    ..., input, select, label, form')) { return; } if (window.getSelection && String(window.getSelection()).length > 0) { return; } window.location.href = tr.getAttribute('data-href'); }); }); } /* ---------- Copy buttons ---------- */ function copyText(text) { if (navigator.clipboard && navigator.clipboard.writeText && window.isSecureContext) { ...
    ...bute('data-value') || ''; $$('a[data-carry="' + group + '"]').forEach(function (l) { try { var u = new URL(l.href, window.location.href); if (value && value !== 'daily') { u.searchParams.set(group, value); } else { u.searchParams.delete(group); } l.href = u.toString(); } catch (err) { /* ignore */ } }); if (win...
- device x1
    ...get && e.target.name) { sync(); } }); sync(); } /* ---------- Focus the first field once the welcome animation is done (mouse/keyboard devices) ---------- */ function initFocusFine() { var el = $('[data-focus-fine]'); if (!el || !window.matchMedia || !window.matchMedia('(pointer: fine)').matches) { return; } var reduce = window.matchMedia('(prefe...
- localStorage x2
    ... function (id) { // Several open tabs: only the first one to see a notification plays the sound. try { var seen = parseInt(window.localStorage.getItem('bwpb-sound-seen') || '0', 10) || 0; if (seen >= id) { return false; } window.localStorage.setItem('bwpb-sound-seen', String(id)); } catch (err) { /* storage blocked: just play */ } ret...
    ...{ var seen = parseInt(window.localStorage.getItem('bwpb-sound-seen') || '0', 10) || 0; if (seen >= id) { return false; } window.localStorage.setItem('bwpb-sound-seen', String(id)); } catch (err) { /* storage blocked: just play */ } return true; }; var showCount = function (n) { if (badge) { badge.hidden = n === 0; badge.textContent =...
- Notification x6
    ...parseFloat(el.getAttribute('data-w')); if (!isNaN(w)) { el.style.width = Math.max(0, Math.min(100, w)) + '%'; } }); } /* ---------- Notification sound (Web Audio, no files) ---------- */ var audioCtx = null; function audio() { if (audioCtx) { return audioCtx; } var AC = window.AudioContext || window.webkitAudioContext; if (!AC) { return null;...
    ...ata-sound') || 'coin'); if (kind === 'off') { toast('Sound is off'); return; } playSound(kind); }); }); } /* ---------- New notifications: badge, sound and a pop-up ---------- */ function initUnreadPolling() { var body = document.body; if (!body.hasAttribute('data-last-note')) { return; } var badge = $('[data-unread-badge]'); var dot...
    ...tribute('data-last-note'), 10) || 0; var timer = null; var claim = function (id) { // Several open tabs: only the first one to see a notification plays the sound. try { var seen = parseInt(window.localStorage.getItem('bwpb-sound-seen') || '0', 10) || 0; if (seen >= id) { return false; } window.localStorage.setItem('bwpb-sound-seen', Str...
    ...ation.href); if (u.origin === window.location.origin) { safe = u.href; } } catch (err) { safe = ''; } el.href = safe || (BASE + '/notifications'); var strong = document.createElement('strong'); strong.textContent = item.title; var small = document.createElement('span'); small.textContent = 'New notification'; el.appendChild(small); ...
- seller x1
    ...ready submitted:</p><ul class="dup-list">' + list.map(function (x) { return '<li><strong>' + esc(x.ref) + '</strong> · ' + esc(x.seller) + ' · ' + esc(x.amount || '') + ' · ' + esc(x.date) + ' · ' + esc(x.status_label) + (x.strong ? ' · same amount and account' : '') + '</li>'; }).join('') + '</ul></div></div>'; dupBox.hidden = false; ...
- role x4
    ... if (!box) { return; } var el = document.createElement('div'); el.className = 'toast toast-' + (type || 'success'); el.setAttribute('role', 'status'); el.textContent = message; box.appendChild(el); dismissLater(el); } function dismissLater(el) { setTimeout(function () { el.classList.add('leaving'); setTimeout(function () { el.remove()...
    ...box || !item || !item.title) { return; } var el = document.createElement('a'); el.className = 'toast toast-note'; el.setAttribute('role', 'status'); var safe = ''; try { var u = new URL(item.url || '', window.location.href); if (u.origin === window.location.origin) { safe = u.href; } } catch (err) { safe = ''; } el.href = safe ||...
    ...s = (d && d.clients) || []; if (!items.length) { close(); return; } acList.innerHTML = items.map(function (c, i) { return '<li role="option" id="ac-' + i + '" data-i="' + i + '">' + esc(c.name) + '<span class="ac-sub">' + esc(c.whatsapp) + (c.last ? ' · last payment ' + esc(c.last) : '') + '</span></li>'; }).join(''); acList.hidden = fal...
    ...data-tip]'); if (!marks.length) { return; } var tip = document.createElement('div'); tip.className = 'chart-tip'; tip.setAttribute('role', 'status'); tip.hidden = true; var strong = document.createElement('strong'); var label = document.createElement('span'); tip.appendChild(strong); tip.appendChild(label); document.body.appendChild(tip); ...
- matchMedia x3
    ...nimation is done (mouse/keyboard devices) ---------- */ function initFocusFine() { var el = $('[data-focus-fine]'); if (!el || !window.matchMedia || !window.matchMedia('(pointer: fine)').matches) { return; } var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches; var intro = document.body.classList.contains('auth-intro'); setTi...
    ...e/keyboard devices) ---------- */ function initFocusFine() { var el = $('[data-focus-fine]'); if (!el || !window.matchMedia || !window.matchMedia('(pointer: fine)').matches) { return; } var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches; var intro = document.body.classList.contains('auth-intro'); setTimeout(function () { ...
    ...$('[data-focus-fine]'); if (!el || !window.matchMedia || !window.matchMedia('(pointer: fine)').matches) { return; } var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches; var intro = document.body.classList.contains('auth-intro'); setTimeout(function () { if (!document.activeElement || document.activeElement === document.body)...
- X-Requested-With x1
    ... : ''; }; var BASE = meta('bwpb-base'); function api(path, opts) { opts = opts || {}; var headers = { 'Accept': 'application/json', 'X-Requested-With': 'fetch' }; if (opts.method && opts.method !== 'GET') { headers['X-BWPB-Token'] = meta('bwpb-token'); } return fetch(BASE + path, { method: opts.method || 'GET', headers: headers, credentials: 'same...
- popup x2
    ...ng(n); } if (dot) { dot.hidden = n === 0; } document.title = (n > 0 ? '(' + (n > 99 ? '99+' : n) + ') ' : '') + baseTitle; }; var popup = function (item) { var box = $('#toasts'); if (!box || !item || !item.title) { return; } var el = document.createElement('a'); el.className = 'toast toast-note'; el.setAttribute('role', 'status'); ...
    ...bute('data-sound') || 'coin'); if (navigator.vibrate) { try { navigator.vibrate([40, 60, 40]); } catch (err) { /* ignore */ } } popup(fresh[0]); } } }).catch(function () {}).then(function () { timer = setTimeout(poll, 30000); }); }; timer = setTimeout(poll, 30000); document.addEventListener('visibilitychange', function () { if (...
- paths mentioned: /api/clients?q=, /api/duplicates?txn=, /api/notifications/count?after=

## Does the server answer differently when the request carries X-Requested-With?
/login
    without header: 200 text/html | (page)
    with app header: 200 text/html | (page)
    with "fetch": 200 text/html | (page)
/dashboard
    without header: 302 text/html -> /login | 
    with app header: 302 text/html -> /login | 
    with "fetch": 302 text/html -> /login | 
/sellers
    without header: 302 text/html -> /login?next=%2Fsellers | 
    with app header: 302 text/html -> /login?next=%2Fsellers | 
    with "fetch": 401 application/json | {"ok":false,"error":"Your session has ended. Sign in again."}
/notifications
    without header: 302 text/html -> /login?next=%2Fnotifications | 
    with app header: 302 text/html -> /login?next=%2Fnotifications | 
    with "fetch": 401 application/json | {"ok":false,"error":"Your session has ended. Sign in again."}
/api/notifications/count?after=0
    without header: 401 application/json | {"ok":false,"error":"Your session has ended. Sign in again."}
    with app header: 401 application/json | {"ok":false,"error":"Your session has ended. Sign in again."}
    with "fetch": 401 application/json | {"ok":false,"error":"Your session has ended. Sign in again."}
/
    without header: 200 text/html | (page)
    with app header: 200 text/html | (page)
    with "fetch": 200 text/html | (page)

## Browser check
This machine was not asked to pass the "checking your browser" page (plain requests got HTTP 200), so there was nothing to test.

