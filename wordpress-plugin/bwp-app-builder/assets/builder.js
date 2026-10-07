/* BWP App Builder - form, progress and download buttons. No dependencies. */
(function () {
  'use strict';

  var cfg = window.BWPAB;
  if (!cfg) { return; }
  var STORE_KEY = 'bwpab_build';
  var POLL_MS = 8000;

  function each(list, fn) { for (var i = 0; i < list.length; i++) { fn(list[i]); } }

  function setup(root) {
    var form = root.querySelector('[data-bwpab-form]');
    var errorBox = root.querySelector('[data-bwpab-error]');
    var submit = root.querySelector('[data-bwpab-submit]');
    var progress = root.querySelector('[data-bwpab-progress]');
    var spinner = root.querySelector('[data-bwpab-spinner]');
    var title = root.querySelector('[data-bwpab-title]');
    var status = root.querySelector('[data-bwpab-status]');
    var time = root.querySelector('[data-bwpab-time]');
    var downloads = root.querySelector('[data-bwpab-downloads]');
    var notes = root.querySelector('[data-bwpab-notes]');
    var again = root.querySelector('[data-bwpab-again]');
    if (!form || !progress) { return; }

    var pollTimer = null;
    var clockTimer = null;
    var startedAt = 0;
    var buildId = '';
    var submitLabel = submit.textContent;

    function showError(message) {
      errorBox.textContent = message || '';
      errorBox.hidden = !message;
    }

    function remember(id) {
      try {
        if (id) { window.localStorage.setItem(STORE_KEY, id); } else { window.localStorage.removeItem(STORE_KEY); }
      } catch (e) { /* storage not available */ }
    }

    function recall() {
      try { return window.localStorage.getItem(STORE_KEY) || ''; } catch (e) { return ''; }
    }

    function clock() {
      var seconds = Math.max(0, Math.round((Date.now() - startedAt) / 1000));
      var m = Math.floor(seconds / 60);
      var s = seconds % 60;
      time.textContent = cfg.text.elapsed + ' ' + m + ':' + (s < 10 ? '0' : '') + s;
    }

    function stopTimers() {
      if (pollTimer) { clearTimeout(pollTimer); pollTimer = null; }
      if (clockTimer) { clearInterval(clockTimer); clockTimer = null; }
    }

    function reset() {
      stopTimers();
      remember('');
      buildId = '';
      progress.hidden = true;
      form.hidden = false;
      submit.disabled = false;
      submit.textContent = submitLabel;
      showError('');
    }

    function addNote(text) {
      var li = document.createElement('li');
      li.textContent = text;
      notes.appendChild(li);
    }

    function render(state) {
      form.hidden = true;
      progress.hidden = false;
      title.textContent = state.appName || '';
      downloads.textContent = '';
      notes.textContent = '';
      again.hidden = true;

      var running = state.status === 'queued' || state.status === 'building';
      spinner.hidden = !running;
      time.hidden = !running;
      root.setAttribute('data-state', state.status);

      if (running) {
        status.textContent = state.status === 'queued' ? cfg.text.queued : cfg.text.building;
        if (!clockTimer) {
          startedAt = Date.now() - (state.elapsed || 0) * 1000;
          clock();
          clockTimer = setInterval(clock, 1000);
        }
        return;
      }

      stopTimers();
      remember('');
      again.hidden = false;
      again.textContent = cfg.text.again;

      if (state.status === 'failed') {
        status.textContent = cfg.text.failed + (state.message ? ' ' + state.message : '');
        return;
      }

      status.textContent = cfg.text.done;
      var kinds = ['ios', 'android'];
      for (var i = 0; i < kinds.length; i++) {
        var kind = kinds[i];
        var file = state.downloads ? state.downloads[kind] : null;
        if (!file) { continue; }
        if (file.ok) {
          var link = document.createElement('a');
          link.className = 'bwpab-button bwpab-download';
          link.href = file.url;
          link.textContent = (kind === 'ios' ? cfg.text.ios : cfg.text.android) + (file.size ? ' - ' + file.size : '');
          downloads.appendChild(link);
          addNote(kind === 'ios' ? cfg.text.iosNote : cfg.text.andNote);
        } else {
          addNote(kind === 'ios' ? cfg.text.iosFail : cfg.text.andFail);
        }
      }
      each(state.warnings || [], addNote);
    }

    function poll() {
      pollTimer = null;
      if (!buildId) { return; }
      var url = cfg.ajax + '?action=bwpab_status&id=' + encodeURIComponent(buildId) + '&_=' + Date.now();
      window.fetch(url, { credentials: 'same-origin', cache: 'no-store' })
        .then(function (res) { return res.json().then(function (json) { return { http: res.status, json: json }; }); })
        .then(function (res) {
          if (res.http === 404) { reset(); return; }
          if (res.json && res.json.success && res.json.data) {
            render(res.json.data);
            if (res.json.data.status === 'queued' || res.json.data.status === 'building') {
              pollTimer = setTimeout(poll, POLL_MS);
            }
          } else {
            pollTimer = setTimeout(poll, POLL_MS * 2);
          }
        })
        .catch(function () {
          status.textContent = cfg.text.network;
          pollTimer = setTimeout(poll, POLL_MS * 2);
        });
    }

    form.addEventListener('submit', function (event) {
      event.preventDefault();
      showError('');
      if (typeof form.reportValidity === 'function' && !form.checkValidity()) {
        form.reportValidity();
        return;
      }
      var data = new window.FormData(form);
      data.append('action', 'bwpab_start');
      data.append('nonce', cfg.nonce);
      submit.disabled = true;
      submit.textContent = cfg.text.starting;

      window.fetch(cfg.ajax, { method: 'POST', body: data, credentials: 'same-origin' })
        .then(function (res) { return res.json(); })
        .then(function (json) {
          if (!json || !json.success || !json.data || !json.data.id) {
            throw new Error(json && json.data && json.data.message ? json.data.message : cfg.text.failed);
          }
          buildId = json.data.id;
          remember(buildId);
          render(json.data);
          pollTimer = setTimeout(poll, POLL_MS);
        })
        .catch(function (err) {
          submit.disabled = false;
          submit.textContent = submitLabel;
          showError(err && err.message && err.message !== 'Failed to fetch' ? err.message : cfg.text.network);
        });
    });

    again.addEventListener('click', reset);

    // Came back to the page while a build is running: pick it up again.
    var saved = recall();
    if (/^[a-z0-9]{8,40}$/.test(saved)) {
      buildId = saved;
      form.hidden = true;
      progress.hidden = false;
      status.textContent = cfg.text.queued;
      poll();
    }
  }

  function boot() { each(document.querySelectorAll('[data-bwpab]'), setup); }
  if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', boot); } else { boot(); }
})();
