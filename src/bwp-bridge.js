/*
 * BWP Billing - bridge script.
 *
 * The native plugin (plugins/bwp-native) injects this file into every page of the
 * billing website at document start. It connects the website to native features:
 *
 *   - a message channel to the native plugin (window.bwpNative / webkit.messageHandlers.bwpNative)
 *   - file downloads (PDF invoices, receipts, CSV/Excel reports, blob: and data: files)
 *   - Print  (window.print -> native print dialog, which can also save as PDF)
 *   - Share  (navigator.share -> native share sheet, on Android)
 *   - status bar / safe-area colour that follows the page
 *   - pull-to-refresh guard (no refresh while a modal or inner list is being scrolled)
 *   - keeping the focused input visible above the keyboard
 *   - offline banner
 *   - internal links that ask for a new window stay inside the app
 *
 * It does NOT touch billing logic, forms, requests, cookies or storage of the website.
 * It is written in conservative JavaScript so it also runs on old Android WebView versions.
 */
(function () {
  'use strict';

  if (window.__bwp) { return; }

  var cfg = window.__BWP_CONFIG__ || {};
  var allowedHosts = cfg.allowedHosts || [];

  // Main frame of the billing website only.
  try { if (window.top !== window.self) { return; } } catch (e) { return; }
  if (allowedHosts.indexOf(window.location.hostname) === -1) { return; }

  var isIOS = cfg.platform === 'ios' || (!cfg.platform && /iPhone|iPad|iPod/.test(navigator.userAgent));
  var isAndroid = !isIOS;
  var DOC_EXT = cfg.downloadExtensions || ['pdf', 'csv', 'xls', 'xlsx', 'doc', 'docx', 'zip'];
  var SECURE_PATHS = cfg.secureScreenPaths || [];

  /* ------------------------------------------------------------------ native calls */

  // Capacitor does not inject its own bridge into remote websites, so the native plugin exposes
  // a channel of its own, restricted to the allowed origins:
  //   Android : window.bwpNative            (WebMessageListener; old WebViews: window.bwpNativeLegacy)
  //   iOS     : webkit.messageHandlers.bwpNative (answers with a Promise)
  var pending = {};
  var sequence = 0;
  var channelHooked = false;

  function nativePlugin(name) {
    var cap = window.Capacitor;
    return cap && cap.Plugins && cap.Plugins[name] ? cap.Plugins[name] : null;
  }

  function iosChannel() {
    var w = window.webkit;
    return w && w.messageHandlers && w.messageHandlers.bwpNative ? w.messageHandlers.bwpNative : null;
  }

  function androidChannel() {
    var c = window.bwpNative;
    if (c && typeof c.postMessage === 'function') { return c; }
    c = window.bwpNativeLegacy;
    return c && typeof c.postMessage === 'function' ? c : null;
  }

  function onNativeReply(raw) {
    var message;
    try { message = typeof raw === 'string' ? JSON.parse(raw) : raw; } catch (e) { return; }
    if (!message || !pending[message.id]) { return; }
    var entry = pending[message.id];
    delete pending[message.id];
    clearTimeout(entry.timer);
    if (message.ok) { entry.resolve(message.result || {}); } else { entry.reject(new Error(message.error || 'Native call failed')); }
  }

  function sendToAndroid(channel, method, args) {
    return new Promise(function (resolve, reject) {
      sequence += 1;
      var id = 'c' + sequence;
      var timer = setTimeout(function () {
        if (pending[id]) { delete pending[id]; reject(new Error('Native call timed out')); }
      }, 60000);
      pending[id] = { resolve: resolve, reject: reject, timer: timer };
      if (!channelHooked && channel === window.bwpNative) {
        channelHooked = true;
        channel.onmessage = function (event) { onNativeReply(event && event.data); };
      }
      try {
        channel.postMessage(JSON.stringify({ id: id, method: method, args: args || {} }));
      } catch (e) {
        clearTimeout(timer);
        delete pending[id];
        reject(e);
      }
    });
  }

  function nativeAvailable() {
    return !!(iosChannel() || androidChannel() || nativePlugin('BwpNative'));
  }

  function callNative(method, args) {
    try {
      var ios = iosChannel();
      if (ios) { return Promise.resolve(ios.postMessage({ method: method, args: args || {} })); }
      var android = androidChannel();
      if (android) { return sendToAndroid(android, method, args); }
      var plugin = nativePlugin('BwpNative');
      if (plugin && typeof plugin[method] === 'function') { return Promise.resolve(plugin[method](args || {})); }
    } catch (e) {
      return Promise.reject(e);
    }
    return Promise.reject(new Error('BwpNative.' + method + ' is not available'));
  }

  function callNativeQuiet(method, args) {
    return callNative(method, args).then(null, function () {});
  }

  // The channel exists from document start; the short wait only covers unusual load orders.
  function whenNativeReady(fn) {
    var tries = 0;
    (function check() {
      if (nativeAvailable()) { fn(); return; }
      tries += 1;
      if (tries < 50) { setTimeout(check, 100); }
    })();
  }

  function onReady(fn) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', fn);
    } else {
      fn();
    }
  }

  /* ------------------------------------------------------------------ small in-page notice */

  var noticeEl = null;
  var noticeTimer = null;
  var stickyText = '';

  function ensureNotice() {
    if (noticeEl || !document.documentElement) { return noticeEl; }
    var host = document.createElement('div');
    host.setAttribute('data-bwp-notice', '');
    host.setAttribute('role', 'status');
    host.setAttribute('aria-live', 'polite');
    var style = host.style;
    style.cssText = [
      'position:fixed', 'left:12px', 'right:12px', 'bottom:16px', 'z-index:2147483647',
      'margin:0 auto', 'max-width:420px', 'padding:12px 16px', 'border-radius:12px',
      'background:rgba(17,24,39,0.94)', 'color:#fff',
      'font:500 14px/1.35 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif',
      'text-align:center', 'box-shadow:0 8px 24px rgba(0,0,0,0.28)', 'pointer-events:none',
      'display:none'
    ].join(';');
    (document.body || document.documentElement).appendChild(host);
    noticeEl = host;
    return host;
  }

  function renderNotice(text) {
    var el = ensureNotice();
    if (!el) { return; }
    if (text) {
      el.textContent = text;
      el.style.display = 'block';
    } else {
      el.style.display = 'none';
    }
  }

  // Temporary message. A sticky message (offline) comes back when it expires.
  function notice(text, ms) {
    if (noticeTimer) { clearTimeout(noticeTimer); noticeTimer = null; }
    renderNotice(text);
    if (ms) {
      noticeTimer = setTimeout(function () { noticeTimer = null; renderNotice(stickyText); }, ms);
    }
  }

  function setSticky(text) {
    stickyText = text || '';
    if (!noticeTimer) { renderNotice(stickyText); }
  }

  /* ------------------------------------------------------------------ downloads */

  var busy = {};

  function toAbsolute(url) {
    try { return new URL(url, window.location.href); } catch (e) { return null; }
  }

  function isAllowedUrl(abs) {
    return !!abs && abs.protocol === 'https:' && allowedHosts.indexOf(abs.hostname) !== -1;
  }

  function extensionOf(abs) {
    var match = /\.([a-z0-9]{1,6})$/i.exec(abs.pathname || '');
    return match ? match[1].toLowerCase() : '';
  }

  function isDocumentUrl(abs) {
    return DOC_EXT.indexOf(extensionOf(abs)) !== -1;
  }

  function nameFromDisposition(header) {
    if (!header) { return ''; }
    var match = /filename\*\s*=\s*(?:[\w-]+'[^']*')?([^;]+)/i.exec(header);
    if (match) {
      try { return decodeURIComponent(match[1].trim().replace(/^"|"$/g, '')); } catch (e) { /* fall through */ }
    }
    match = /filename\s*=\s*(?:"([^"]*)"|([^;]+))/i.exec(header);
    if (match) { return (match[1] !== undefined ? match[1] : match[2]).trim(); }
    return '';
  }

  function nameFromUrl(abs) {
    if (!abs || abs.protocol === 'blob:' || abs.protocol === 'data:') { return ''; }
    var parts = (abs.pathname || '').split('/');
    var last = parts[parts.length - 1] || '';
    try { last = decodeURIComponent(last); } catch (e) { /* keep as is */ }
    return last;
  }

  var MIME_EXT = {
    'application/pdf': 'pdf',
    'text/csv': 'csv',
    'application/csv': 'csv',
    'application/vnd.ms-excel': 'xls',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
    'application/msword': 'doc',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
    'application/zip': 'zip',
    'application/json': 'json',
    'text/plain': 'txt',
    'image/png': 'png',
    'image/jpeg': 'jpg',
    'image/webp': 'webp',
    'image/gif': 'gif'
  };

  function cleanName(name, mime) {
    var safe = String(name || '').replace(/[\\/:*?"<>|\u0000-\u001f]+/g, '_').replace(/^\.+/, '').trim();
    if (!safe) { safe = 'download'; }
    if (safe.length > 120) { safe = safe.slice(safe.length - 120); }
    if (!/\.[a-z0-9]{1,6}$/i.test(safe) && MIME_EXT[mime]) { safe += '.' + MIME_EXT[mime]; }
    return safe;
  }

  function blobToBase64(blob) {
    return new Promise(function (resolve, reject) {
      var reader = new FileReader();
      reader.onload = function () {
        var result = String(reader.result || '');
        var comma = result.indexOf(',');
        resolve(comma === -1 ? '' : result.slice(comma + 1));
      };
      reader.onerror = function () { reject(reader.error || new Error('read failed')); };
      reader.readAsDataURL(blob);
    });
  }

  // Files the page builds itself (blob: URLs) are remembered here, so a download can read them
  // directly. Fetching a blob: URL would be blocked by a strict Content-Security-Policy
  // (connect-src 'self'), which billing sites commonly send.
  var blobStore = {};
  var blobOrder = [];
  var BLOB_LIMIT = 24;

  function forgetBlob(url) {
    if (blobStore[url]) {
      delete blobStore[url];
      var at = blobOrder.indexOf(url);
      if (at !== -1) { blobOrder.splice(at, 1); }
    }
  }

  try {
    var nativeCreateObjectURL = window.URL.createObjectURL;
    var nativeRevokeObjectURL = window.URL.revokeObjectURL;
    window.URL.createObjectURL = function (object) {
      var url = nativeCreateObjectURL.apply(window.URL, arguments);
      try {
        if (typeof Blob !== 'undefined' && object instanceof Blob) {
          blobStore[url] = object;
          blobOrder.push(url);
          while (blobOrder.length > BLOB_LIMIT) { delete blobStore[blobOrder.shift()]; }
        }
      } catch (e) { /* keep the normal behaviour */ }
      return url;
    };
    window.URL.revokeObjectURL = function (url) {
      // Pages usually revoke the URL right after starting the download: keep it a little longer.
      setTimeout(function () { forgetBlob(url); }, 60000);
      return nativeRevokeObjectURL.apply(window.URL, arguments);
    };
  } catch (e) { /* leave the default behaviour */ }

  // data: URL -> { mime, data (base64) } without any network request.
  function parseDataUrl(href) {
    var comma = href.indexOf(',');
    if (comma === -1) { return null; }
    var meta = href.slice(5, comma);
    var payload = href.slice(comma + 1);
    var isBase64 = /;base64$/i.test(meta);
    var mime = (meta.replace(/;base64$/i, '').split(';')[0] || 'text/plain').toLowerCase();
    try {
      if (isBase64) {
        return { mime: mime, data: decodeURIComponent(payload).replace(/\s+/g, '') };
      }
      // unescape() turns %XX into single bytes, which is exactly what btoa() expects.
      return { mime: mime, data: window.btoa(unescape(payload)) };
    } catch (e) {
      return null;
    }
  }

  function saveBase64(data, name, mime) {
    return callNative('saveFile', { name: cleanName(name, mime), mime: mime || 'application/octet-stream', data: data });
  }

  function finishDownload(promise, href) {
    promise.then(function () {
      notice('', 0);
    }, function () {
      notice(navigator.onLine === false ? 'No internet connection' : 'Download failed. Please try again.', 3500);
    }).then(function () {
      delete busy[href];
    });
  }

  /**
   * Hand a file to the native side, which saves it and shows Open / Share (Android) or a
   * preview with Share (iOS).
   *   blob: / data:  read directly from memory
   *   https          fetched with the user's existing session (same site only)
   */
  function download(url, suggestedName, mimeHint) {
    var abs = toAbsolute(url);
    if (!abs) { return; }
    var href = abs.href;
    var isHttp = abs.protocol === 'https:' || abs.protocol === 'http:';
    if (isHttp && !isAllowedUrl(abs)) {
      // Another website: let the phone's browser handle it.
      callNativeQuiet('openExternal', { url: href });
      return;
    }
    if (busy[href]) { return; }
    busy[href] = true;
    notice('Preparing file...', 0);

    if (abs.protocol === 'data:') {
      var parsed = parseDataUrl(href);
      finishDownload(parsed
        ? saveBase64(parsed.data, suggestedName || 'download', parsed.mime)
        : Promise.reject(new Error('Unreadable data URL')), href);
      return;
    }

    if (abs.protocol === 'blob:' && blobStore[href]) {
      var stored = blobStore[href];
      var storedMime = String(stored.type || mimeHint || 'application/octet-stream').split(';')[0].trim().toLowerCase();
      finishDownload(blobToBase64(stored).then(function (data) {
        return saveBase64(data, suggestedName || 'download', storedMime);
      }), href);
      return;
    }

    var options = { credentials: 'include', cache: 'no-store' };
    finishDownload(window.fetch(href, isHttp ? options : undefined).then(function (res) {
      if (!res.ok) { throw new Error('HTTP ' + res.status); }
      var type = String(res.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
      if (isHttp && type === 'text/html') {
        // Not a file (for example the login page after the session expired): show it normally.
        window.location.assign(res.url || href);
        return null;
      }
      var headerName = nameFromDisposition(res.headers.get('content-disposition'));
      return res.blob().then(function (blob) {
        var mime = type || blob.type || mimeHint || 'application/octet-stream';
        return blobToBase64(blob).then(function (data) {
          return saveBase64(data, headerName || suggestedName || nameFromUrl(abs), mime);
        });
      });
    }), href);
  }

  function closestAnchor(node) {
    while (node && node !== document) {
      if (node.nodeType === 1 && node.tagName === 'A' && node.hasAttribute('href')) { return node; }
      node = node.parentNode;
    }
    return null;
  }

  // Returns true when the click was taken over as a download.
  function handleAnchor(anchor) {
    var raw = anchor.getAttribute('href');
    if (!raw || raw.charAt(0) === '#') { return false; }
    var abs = toAbsolute(raw);
    if (!abs) { return false; }
    var wantsDownload = anchor.hasAttribute('download');
    if (abs.protocol === 'blob:' || abs.protocol === 'data:') {
      download(abs.href, anchor.getAttribute('download') || '', '');
      return true;
    }
    if (isAllowedUrl(abs) && (wantsDownload || isDocumentUrl(abs))) {
      download(abs.href, anchor.getAttribute('download') || '', '');
      return true;
    }
    return false;
  }

  // Bubble phase on window: the website's own click handlers run first and are respected.
  window.addEventListener('click', function (event) {
    if (event.defaultPrevented || event.button) { return; }
    var anchor = closestAnchor(event.target);
    if (!anchor) { return; }
    if (handleAnchor(anchor)) {
      event.preventDefault();
      return;
    }
    // Internal link that asks for a new tab: keep it inside the app.
    var abs = toAbsolute(anchor.getAttribute('href'));
    var targetName = (anchor.getAttribute('target') || '').toLowerCase();
    if (targetName === '_blank' && isAllowedUrl(abs)) {
      anchor.setAttribute('target', '_self');
    }
  }, false);

  // Files started from script: link.click() on a temporary <a download>.
  try {
    var originalAnchorClick = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function () {
      try {
        if (this.hasAttribute('href') && !this.isConnected && handleAnchor(this)) { return; }
      } catch (e) { /* fall back to the normal click */ }
      return originalAnchorClick.apply(this, arguments);
    };
  } catch (e) { /* leave the default behaviour */ }

  // window.open(): internal pages stay in the app, files go to the native download flow.
  try {
    var originalOpen = window.open;
    window.open = function (url) {
      try {
        if (typeof url === 'string' && url && url !== 'about:blank') {
          var abs = toAbsolute(url);
          if (abs && (abs.protocol === 'blob:' || abs.protocol === 'data:')) {
            download(abs.href, '', '');
            return null;
          }
          if (isAllowedUrl(abs)) {
            if (isDocumentUrl(abs)) { download(abs.href, '', ''); return null; }
            window.location.assign(abs.href);
            return window;
          }
        }
      } catch (e) { /* fall back */ }
      return originalOpen.apply(window, arguments);
    };
  } catch (e) { /* leave the default behaviour */ }

  /* ------------------------------------------------------------------ print + share */

  try {
    var originalPrint = window.print;
    window.print = function () {
      callNative('printPage', { title: document.title || cfg.appName || 'Document' }).then(null, function () {
        try { originalPrint.call(window); } catch (e) { /* nothing else to try */ }
      });
    };
  } catch (e) { /* leave the default behaviour */ }

  // Android WebView has no Web Share API. iOS already provides it natively.
  if (isAndroid && typeof navigator.share !== 'function') {
    try {
      navigator.share = function (data) {
        data = data || {};
        if (data.files && data.files.length) {
          return Promise.reject(new TypeError('Sharing files from the page is not supported in this app.'));
        }
        return callNative('share', {
          title: String(data.title || ''),
          text: String(data.text || ''),
          url: String(data.url || '')
        }).then(function () {});
      };
      navigator.canShare = function (data) {
        return !(data && data.files && data.files.length);
      };
    } catch (e) { /* leave it unsupported */ }
  }

  /* ------------------------------------------------------------------ status bar colour */

  var lastTheme = '';
  var probe = null;

  function parseColor(value) {
    if (!value) { return null; }
    var match = /rgba?\(([^)]+)\)/i.exec(value);
    if (!match) { return null; }
    var parts = match[1].split(/[\s,\/]+/).filter(function (p) { return p !== ''; });
    if (parts.length < 3) { return null; }
    var r = parseFloat(parts[0]);
    var g = parseFloat(parts[1]);
    var b = parseFloat(parts[2]);
    var a = parts.length > 3 ? parseFloat(parts[3]) : 1;
    if (parts.length > 3 && /%$/.test(parts[3])) { a = a / 100; }
    if (isNaN(r) || isNaN(g) || isNaN(b) || isNaN(a)) { return null; }
    return { r: Math.round(r), g: Math.round(g), b: Math.round(b), a: a };
  }

  function toHex(c) {
    function h(n) {
      var s = Math.max(0, Math.min(255, n)).toString(16);
      return s.length === 1 ? '0' + s : s;
    }
    return '#' + h(c.r) + h(c.g) + h(c.b);
  }

  function solidBackground(el) {
    while (el && el.nodeType === 1) {
      var c = parseColor(window.getComputedStyle(el).backgroundColor);
      if (c && c.a >= 0.9) { return toHex(c); }
      el = el.parentElement;
    }
    return '';
  }

  function resolveCssColor(value) {
    if (!value || !document.body) { return ''; }
    if (!probe) {
      probe = document.createElement('span');
      probe.style.display = 'none';
    }
    probe.style.color = '';
    probe.style.color = value;
    if (!probe.style.color) { return ''; }
    document.body.appendChild(probe);
    var c = parseColor(window.getComputedStyle(probe).color);
    document.body.removeChild(probe);
    return c ? toHex(c) : '';
  }

  function reportTheme() {
    if (!document.body) { return; }
    var top = '';
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) { top = resolveCssColor(meta.getAttribute('content')); }
    var w = window.innerWidth || document.documentElement.clientWidth || 0;
    var h = window.innerHeight || document.documentElement.clientHeight || 0;
    if (!top && w && h) { top = solidBackground(document.elementFromPoint(w / 2, 2)); }
    var bottom = w && h ? solidBackground(document.elementFromPoint(w / 2, h - 3)) : '';
    var page = solidBackground(document.body) || solidBackground(document.documentElement) || '#ffffff';
    top = top || page;
    bottom = bottom || page;
    var key = top + '|' + bottom;
    if (key === lastTheme) { return; }
    callNative('setTheme', { top: top, bottom: bottom }).then(function () { lastTheme = key; }, function () {});
  }

  /* ------------------------------------------------------------------ pull-to-refresh guard */

  var lastAllowed = null;

  function refreshAllowedFrom(node) {
    if (cfg.pullToRefresh === false) { return false; }
    var docEl = document.documentElement;
    var bodyEl = document.body;
    if (!bodyEl) { return false; }
    if ((window.pageYOffset || docEl.scrollTop || bodyEl.scrollTop || 0) > 0) { return false; }
    var rootStyle = window.getComputedStyle(docEl);
    var bodyStyle = window.getComputedStyle(bodyEl);
    var blocked = { contain: 1, none: 1 };
    if (blocked[rootStyle.overscrollBehaviorY] || blocked[bodyStyle.overscrollBehaviorY]) { return false; }
    // A modal / drawer is open (Bootstrap and most frameworks lock body scrolling).
    if (bodyStyle.overflowY === 'hidden' || rootStyle.overflowY === 'hidden') { return false; }
    var el = node && node.nodeType === 1 ? node : (node ? node.parentElement : null);
    while (el && el !== bodyEl && el !== docEl) {
      if (el.scrollTop > 0) { return false; }
      var tag = el.tagName;
      if (tag === 'CANVAS' || tag === 'IFRAME' || tag === 'VIDEO') { return false; }
      if (tag === 'INPUT' && el.type === 'range') { return false; }
      if (el.hasAttribute('data-no-pull-refresh')) { return false; }
      if (window.getComputedStyle(el).position === 'fixed') { return false; }
      el = el.parentElement;
    }
    return true;
  }

  function onTouchStart(event) {
    var allowed = refreshAllowedFrom(event.target);
    if (allowed === lastAllowed) { return; }
    lastAllowed = allowed;
    callNativeQuiet('setRefreshAllowed', { allowed: allowed });
  }

  /* ------------------------------------------------------------------ keyboard */

  function isEditable(el) {
    if (!el || el.nodeType !== 1) { return false; }
    var tag = el.tagName;
    if (tag === 'TEXTAREA' || tag === 'SELECT') { return true; }
    if (tag === 'INPUT') {
      var type = (el.getAttribute('type') || 'text').toLowerCase();
      return ['button', 'submit', 'reset', 'checkbox', 'radio', 'file', 'hidden', 'image', 'range', 'color'].indexOf(type) === -1;
    }
    return el.isContentEditable === true;
  }

  function keepVisible(el) {
    if (!isEditable(el) || document.activeElement !== el) { return; }
    var vv = window.visualViewport;
    var viewTop = vv ? vv.offsetTop : 0;
    var viewHeight = vv ? vv.height : window.innerHeight;
    var rect = el.getBoundingClientRect();
    if (rect.bottom > viewTop + viewHeight - 12 || rect.top < viewTop + 4) {
      try { el.scrollIntoView({ block: 'center', inline: 'nearest' }); } catch (e) { el.scrollIntoView(false); }
    }
  }

  /* ------------------------------------------------------------------ screenshot protection (off by default) */

  function applyScreenSecurity() {
    if (!SECURE_PATHS.length) { return; }
    var path = window.location.pathname;
    var secure = false;
    for (var i = 0; i < SECURE_PATHS.length; i++) {
      if (SECURE_PATHS[i] && path.indexOf(SECURE_PATHS[i]) === 0) { secure = true; break; }
    }
    callNativeQuiet('setScreenSecure', { enabled: secure });
  }

  /* ------------------------------------------------------------------ wiring */

  document.addEventListener('touchstart', onTouchStart, { capture: true, passive: true });

  document.addEventListener('focusin', function (event) {
    var el = event.target;
    if (isEditable(el)) { setTimeout(function () { keepVisible(el); }, 350); }
  }, true);

  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', function () {
      var el = document.activeElement;
      if (isEditable(el)) { setTimeout(function () { keepVisible(el); }, 60); }
    });
  }

  window.addEventListener('offline', function () { setSticky('No internet connection'); });
  window.addEventListener('online', function () {
    setSticky('');
    notice('Back online', 1800);
  });

  onReady(function () {
    if (navigator.onLine === false) { setSticky('No internet connection'); }
    whenNativeReady(function () {
      callNativeQuiet('pageReady', { host: window.location.hostname });
      reportTheme();
      applyScreenSecurity();
      if (isIOS) {
        // Show the bar with "Done" above the keyboard - numeric keypads have no return key.
        var keyboard = nativePlugin('Keyboard');
        if (keyboard && typeof keyboard.setAccessoryBarVisible === 'function') {
          try { Promise.resolve(keyboard.setAccessoryBarVisible({ isVisible: true })).then(null, function () {}); } catch (e) { /* optional */ }
        }
      }
    });
  });

  window.addEventListener('load', function () {
    reportTheme();
    setTimeout(reportTheme, 800);
  });
  window.addEventListener('pageshow', function () {
    lastTheme = '';
    setTimeout(reportTheme, 50);
    applyScreenSecurity();
  });

  // Used by the old-WebView fallback channel to deliver answers.
  window.__bwpNativeReply = onNativeReply;

  window.__bwp = {
    version: '1.0.0',
    call: callNative,
    download: download,
    reportTheme: function () { lastTheme = ''; reportTheme(); }
  };
})();
