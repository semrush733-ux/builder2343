/*
 * BWP Billing - local shell logic (launch screen + offline / connection-error screen).
 *
 * index.html  (data-mode="launch")  shown at app start, then replaced by the billing website.
 * error.html  (data-mode="error")   loaded by Capacitor (server.errorPath) when a page cannot load.
 *
 * Loop safety:
 *  - The app navigates to the website only when (a) the app starts, (b) the user taps Retry,
 *    or (c) the phone goes from offline to online. It never retries on a timer, so a server
 *    that keeps failing cannot cause an endless reload loop.
 *
 * Written in conservative JavaScript so it also runs on old Android System WebView versions.
 */
(function () {
  'use strict';

  var DEFAULTS = {
    appName: 'BWP Billing',
    company: 'BWP Experts',
    homeUrl: 'https://bill.bwpexperts.com/',
    allowedHosts: ['bill.bwpexperts.com'],
    brandColor: '#014F4A',
    backgroundColor: '#FFFFFF',
    loadingText: 'Loading your dashboard...'
  };

  var LOAD_TIMEOUT_MS = 25000;

  var body = document.body;
  var mode = body.getAttribute('data-mode') || 'launch';
  var cfg = DEFAULTS;
  var state = '';
  var retryUrl = '';
  var loadTimer = null;

  var states = {
    loading: document.getElementById('state-loading'),
    offline: document.getElementById('state-offline'),
    unreachable: document.getElementById('state-unreachable')
  };

  function each(list, fn) {
    for (var i = 0; i < list.length; i++) { fn(list[i], i); }
  }

  function setNote(text) {
    each(document.querySelectorAll('[data-role="note"]'), function (el) { el.textContent = text || ''; });
  }

  function show(name) {
    state = name;
    for (var key in states) {
      if (Object.prototype.hasOwnProperty.call(states, key) && states[key]) {
        if (key === name) { states[key].classList.add('is-active'); } else { states[key].classList.remove('is-active'); }
      }
    }
    if (name !== 'loading' && loadTimer) { clearTimeout(loadTimer); loadTimer = null; }
  }

  function isOnline() {
    return navigator.onLine !== false;
  }

  function isAllowed(url) {
    try {
      var u = new URL(url);
      return u.protocol === 'https:' && cfg.allowedHosts.indexOf(u.hostname) !== -1;
    } catch (e) {
      return false;
    }
  }

  function target() {
    if (mode === 'error' && retryUrl && isAllowed(retryUrl)) { return retryUrl; }
    return cfg.homeUrl;
  }

  function go(url) {
    setNote('');
    show('loading');
    if (loadTimer) { clearTimeout(loadTimer); }
    // If nothing has replaced this page after a while, stop spinning and let the user retry.
    loadTimer = setTimeout(function () {
      loadTimer = null;
      show(isOnline() ? 'unreachable' : 'offline');
    }, LOAD_TIMEOUT_MS);
    // replace(): keep this local page out of the back-button history.
    window.location.replace(url);
  }

  function retry() {
    if (!isOnline()) {
      show('offline');
      setNote('Still offline. Check Wi-Fi or mobile data.');
      return;
    }
    go(target());
  }

  function applyConfig() {
    var name = document.getElementById('app-name');
    var company = document.getElementById('app-company');
    var loading = document.getElementById('loading-text');
    if (name) { name.textContent = cfg.appName; }
    if (company) { company.textContent = 'by ' + cfg.company; }
    if (loading) { loading.textContent = cfg.loadingText; }
    var hex = /^#[0-9a-f]{6}$/i;
    if (cfg.brandColor && hex.test(cfg.brandColor)) {
      document.documentElement.style.setProperty('--brand', cfg.brandColor);
    }
    if (cfg.backgroundColor && hex.test(cfg.backgroundColor)) {
      document.documentElement.style.setProperty('--bg', cfg.backgroundColor);
    }
    document.title = cfg.appName;
  }

  function loadConfig(done) {
    var finished = false;
    function finish(json) {
      if (finished) { return; }
      finished = true;
      var merged = {};
      var key;
      for (key in DEFAULTS) { if (Object.prototype.hasOwnProperty.call(DEFAULTS, key)) { merged[key] = DEFAULTS[key]; } }
      if (json) { for (key in json) { if (Object.prototype.hasOwnProperty.call(json, key)) { merged[key] = json[key]; } } }
      if (!merged.allowedHosts || !merged.allowedHosts.length) { merged.allowedHosts = DEFAULTS.allowedHosts; }
      cfg = merged;
      done();
    }
    try {
      var xhr = new XMLHttpRequest();
      xhr.open('GET', 'app-config.json', true);
      xhr.onload = function () {
        var json = null;
        try { json = JSON.parse(xhr.responseText); } catch (e) { json = null; }
        finish(json);
      };
      xhr.onerror = function () { finish(null); };
      xhr.send();
    } catch (e) {
      finish(null);
    }
    setTimeout(function () { finish(null); }, 1500);
  }

  // iOS: the native plugin is reachable from this page and knows the last page that was open.
  // Android: the native plugin pushes the same value through window.__bwpShell.setRetryUrl().
  function askNativeForLastUrl() {
    try {
      var cap = window.Capacitor;
      var plugin = cap && cap.Plugins && cap.Plugins.BwpNative;
      if (plugin && typeof plugin.getLastUrl === 'function') {
        plugin.getLastUrl().then(function (res) {
          if (res && res.url) { api.setRetryUrl(res.url); }
        }, function () {});
      }
    } catch (e) { /* not available: Retry goes to the home page */ }
  }

  var api = {
    setRetryUrl: function (url) {
      if (typeof url === 'string' && url) {
        retryUrl = url;
        var homeLink = document.getElementById('home-link');
        if (homeLink && isAllowed(url) && url !== cfg.homeUrl) { homeLink.hidden = false; }
      }
    },
    retry: retry
  };
  window.__bwpShell = api;

  document.addEventListener('click', function (event) {
    var el = event.target;
    while (el && el !== document.body) {
      var action = el.getAttribute && el.getAttribute('data-action');
      if (action === 'retry') { retry(); return; }
      if (action === 'home') {
        if (!isOnline()) { show('offline'); return; }
        go(cfg.homeUrl);
        return;
      }
      el = el.parentNode;
    }
  });

  // Connection came back while the offline screen is showing: reconnect once, automatically.
  window.addEventListener('online', function () {
    if (state === 'offline') { go(target()); }
  });
  window.addEventListener('offline', function () {
    if (state === 'unreachable') { show('offline'); }
  });
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden && state === 'offline' && isOnline()) { go(target()); }
  });

  loadConfig(function () {
    applyConfig();
    if (retryUrl) { api.setRetryUrl(retryUrl); }
    if (mode === 'launch') {
      if (isOnline()) { go(cfg.homeUrl); } else { show('offline'); }
    } else {
      askNativeForLastUrl();
      setTimeout(askNativeForLastUrl, 600);
      show(isOnline() ? 'unreachable' : 'offline');
    }
  });
})();
