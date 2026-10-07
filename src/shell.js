/*
 * BWP Billing - local shell logic (launch screen + offline / connection-error screen).
 *
 * index.html  (data-mode="launch")  shown at app start, then replaced by the billing website.
 * error.html  (data-mode="error")   loaded by Capacitor (server.errorPath) when a page cannot load.
 *
 * Rules that keep this robust on every phone:
 *  - A page that is still loading is never treated as a failure. Only a real load error reported
 *    by the web view brings up the error screen (error.html). A slow server or a slow connection
 *    just keeps the loading screen, with a "Try again" link after a while.
 *  - The phone's "online" flag (navigator.onLine) is wrong on some devices, so it only chooses
 *    the wording of the error screen. It never stops the app from trying to load.
 *  - Automatic reconnects happen at most once every 30 seconds, so a server that keeps failing
 *    cannot cause an endless reload loop.
 *
 * Written in conservative JavaScript so it also runs on old Android System WebView versions.
 */
(function () {
  'use strict';

  var DEFAULTS = {
    appName: 'BWP Billing',
    company: 'BWP Experts',
    homeUrl: 'https://bill.bwpexperts.com/login',
    allowedHosts: ['bill.bwpexperts.com'],
    brandColor: '#014F4A',
    backgroundColor: '#FFFFFF',
    loadingText: 'Loading your dashboard...'
  };

  var SLOW_HINT_MS = 12000;   // show "still loading"
  var SLOW_RETRY_MS = 30000;  // offer "Try again" while the load keeps going
  var PROBE_MS = 10000;       // error screen: check quietly whether the site is reachable again
  var AUTO_GAP_MS = 30000;    // minimum time between two automatic reconnects

  var body = document.body;
  var mode = body.getAttribute('data-mode') || 'launch';
  var cfg = DEFAULTS;
  var state = '';
  var retryUrl = '';
  var slowTimers = [];
  var probeTimer = null;

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
    if (name !== 'loading') { clearSlow(); }
    var detail = document.getElementById('error-detail');
    if (detail) { detail.hidden = name === 'loading' || !detail.textContent; }
    scheduleProbe();
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

  function clearSlow() {
    while (slowTimers.length) { clearTimeout(slowTimers.pop()); }
    var slowText = document.getElementById('slow-text');
    var slowRetry = document.getElementById('slow-retry');
    if (slowText) { slowText.hidden = true; }
    if (slowRetry) { slowRetry.hidden = true; }
  }

  function go(url) {
    setNote('');
    show('loading');
    clearSlow();
    // The load keeps running; these only tell the user what is happening.
    slowTimers.push(setTimeout(function () {
      var slowText = document.getElementById('slow-text');
      if (slowText) { slowText.hidden = false; }
    }, SLOW_HINT_MS));
    slowTimers.push(setTimeout(function () {
      var slowRetry = document.getElementById('slow-retry');
      if (slowRetry) { slowRetry.hidden = false; }
    }, SLOW_RETRY_MS));
    // replace(): keep this local page out of the back-button history.
    window.location.replace(url);
  }

  // Retry always tries, whatever the phone says about being online.
  function retry() {
    go(target());
  }

  // Automatic reconnects are rate-limited across page loads (sessionStorage survives them).
  function autoAllowed() {
    var now = Date.now();
    try {
      var last = Number(window.sessionStorage.getItem('bwpShellAuto') || 0);
      if (now - last < AUTO_GAP_MS) { return false; }
      window.sessionStorage.setItem('bwpShellAuto', String(now));
    } catch (e) { /* storage not available: allow */ }
    return true;
  }

  function autoGo() {
    if ((state === 'offline' || state === 'unreachable') && autoAllowed()) { go(target()); }
  }

  // While an error screen is showing, quietly check whether the site answers again.
  function scheduleProbe() {
    if (probeTimer) { clearTimeout(probeTimer); probeTimer = null; }
    if (mode !== 'error' || (state !== 'offline' && state !== 'unreachable')) { return; }
    probeTimer = setTimeout(function () {
      probeTimer = null;
      if (document.hidden || typeof window.fetch !== 'function') { scheduleProbe(); return; }
      window.fetch(cfg.homeUrl, { mode: 'no-cors', cache: 'no-store', credentials: 'omit' }).then(function () {
        autoGo();
        scheduleProbe();
      }, function () {
        scheduleProbe();
      });
    }, PROBE_MS);
  }

  function applyConfig() {
    var name = document.getElementById('app-name');
    var company = document.getElementById('app-company');
    var loading = document.getElementById('loading-text');
    if (name) { name.textContent = cfg.appName; }
    if (company) {
      company.textContent = cfg.company ? 'by ' + cfg.company : '';
      company.hidden = !cfg.company;
    }
    var unreachable = document.getElementById('unreachable-title');
    if (unreachable) { unreachable.textContent = "We couldn't connect to " + cfg.appName + '.'; }
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
    // Technical reason of the failed load (from the native side), shown small under the message.
    setErrorDetail: function (text) {
      var detail = document.getElementById('error-detail');
      if (!detail || typeof text !== 'string') { return; }
      detail.textContent = text ? 'Details: ' + text.slice(0, 200) : '';
      detail.hidden = !text || state === 'loading';
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
        go(cfg.homeUrl);
        return;
      }
      el = el.parentNode;
    }
  });

  // Connection came back, or the app was reopened, while an error screen is showing.
  window.addEventListener('online', autoGo);
  window.addEventListener('offline', function () {
    if (state === 'unreachable') { show('offline'); }
  });
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden && state === 'offline' && isOnline()) { autoGo(); }
  });

  loadConfig(function () {
    applyConfig();
    if (retryUrl) { api.setRetryUrl(retryUrl); }
    if (mode === 'launch') {
      // Always try. If the phone really is offline the web view reports it and error.html is shown.
      go(cfg.homeUrl);
    } else {
      askNativeForLastUrl();
      setTimeout(askNativeForLastUrl, 600);
      show(isOnline() ? 'unreachable' : 'offline');
    }
  });
})();
