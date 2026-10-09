#!/usr/bin/env python3
"""
B1G - emulator test (runs in the cloud build, see .github/workflows/b1g-tv.yml).

Installs the app on an Android emulator with a TV-sized screen, starts the mock
IPTV server (ci/mock_server.py) and drives the app with remote-control keys only:
sign in, open Live TV, play a channel, change channel (with the stream format
fallback), play a movie, jump forward, resume, open a series episode.

The app writes short "B1G ..." lines to the device log; the test reads them to
know what really happened. Output: out/smoke/SMOKE.md, screenshots, logcat.
"""
import os
import re
import subprocess
import sys
import time

PKG = 'com.b1g.b1gtv'
APK = 'out/smoke-apk/b1g-smoke.apk'
OUT = 'out/smoke'
os.makedirs(OUT, exist_ok=True)

OK, BACK, UP, DOWN, LEFT, RIGHT = '23', '4', '19', '20', '21', '22'
results = []
shots = 0


def sh(*args, timeout=60):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout, errors='replace').stdout or ''
    except Exception as exc:  # noqa: BLE001
        return 'ERR %s' % exc


def adb(*args, **kw):
    return sh('adb', *args, **kw)


def shot(name):
    global shots
    shots += 1
    try:
        data = subprocess.run(['adb', 'exec-out', 'screencap', '-p'], capture_output=True, timeout=30).stdout
        with open('%s/%02d-%s.png' % (OUT, shots, name), 'wb') as f:
            f.write(data)
    except Exception:  # noqa: BLE001
        pass


def key(code, pause=1.2):
    adb('shell', 'input', 'keyevent', code)
    time.sleep(pause)


def app_log():
    """All lines the app has written so far."""
    raw = adb('logcat', '-d', '-s', 'flutter:I', timeout=30)
    return [m.group(1) for m in (re.search(r'(B1G .*)$', line) for line in raw.splitlines()) if m]


def mark():
    return len(app_log())


def wait_log(pattern, since, timeout):
    """Waits for an app log line (after position `since`) that matches; returns the match or None."""
    end = time.time() + timeout
    while time.time() < end:
        for line in app_log()[since:]:
            m = re.search(pattern, line)
            if m:
                return m
        time.sleep(1)
    return None


def check(name, ok, detail=''):
    line = '%s  %s' % ('PASS' if ok else 'FAIL', name)
    if detail not in ('', None):
        line += '  [%s]' % str(detail)[:200]
    results.append(line)
    print(line, flush=True)
    return ok


def wait_position(index, at_least, since, timeout):
    """Waits until the player reports a playing position >= at_least seconds."""
    end = time.time() + timeout
    best = -1
    while time.time() < end:
        for line in app_log()[since:]:
            m = re.search(r'playing index=%d pos=(\d+)' % index, line)
            if m:
                best = max(best, int(m.group(1)))
        if best >= at_least:
            return best
        time.sleep(1)
    return best


def main():
    server_log = open('%s/mock-server.log' % OUT, 'w')
    server = subprocess.Popen([sys.executable, 'ci/mock_server.py', '8787'], stdout=server_log, stderr=subprocess.STDOUT)
    time.sleep(2)
    try:
        run()
    finally:
        server.terminate()
        server_log.close()
        with open('%s/logcat.txt' % OUT, 'w') as f:
            f.write(adb('logcat', '-d', timeout=60))
        with open('%s/app-log.txt' % OUT, 'w') as f:
            f.write('\n'.join(app_log()) + '\n')
        failed = [r for r in results if r.startswith('FAIL')]
        with open('%s/SMOKE.md' % OUT, 'w') as f:
            f.write('### Emulator test (remote-control keys, mock IPTV server)\n\n')
            f.write('%d checks, %d failed\n\n```\n%s\n```\n' % (len(results), len(failed), '\n'.join(results)))
        print(open('%s/SMOKE.md' % OUT).read())


def run():
    adb('logcat', '-G', '16M')
    size = adb('shell', 'wm', 'size').strip()
    density = adb('shell', 'wm', 'density').strip()
    print(size, density, flush=True)
    out = adb('install', '-r', APK, timeout=300)
    if not check('app installs', 'Success' in out, out.strip()[-200:]):
        return
    adb('logcat', '-c')
    adb('shell', 'am', 'start', '-n', PKG + '/.MainActivity')

    # 1. sign in (server, username and password are pre-filled in the test build)
    ok = wait_log(r'screen=login', 0, 90) is not None
    time.sleep(3)
    shot('login')
    if not check('app starts on the sign-in screen', ok):
        return
    m = mark()
    key(OK)
    ok = wait_log(r'screen=home', m, 60) is not None
    time.sleep(2)
    shot('home')
    if not check('sign in with the remote opens the home screen', ok):
        return

    # 2. live TV
    m = mark()
    key(OK)
    got = wait_log(r'browse live items=(\d+)', m, 60)
    time.sleep(2)
    shot('live-list')
    check('Live TV shows categories and channels', got is not None and int(got.group(1)) == 3, got.group(0) if got else '')
    key(RIGHT)
    shot('live-channel-focused')
    m = mark()
    key(OK)
    ready = wait_log(r'ready index=0 format=(\w+) video=(\d+)x(\d+)', m, 90)
    pos = wait_position(0, 5, m, 60)
    shot('live-playing')
    check('channel 1 plays (.ts stream)', ready is not None and ready.group(1) == 'ts' and pos >= 5,
          '%s, position %ss' % (ready.group(0) if ready else 'not ready', pos))
    check('video picture is decoded', ready is not None and int(ready.group(2)) > 0, ready.group(0) if ready else '')

    # 3. channel up: channel 2 has no .ts on the mock server, the app must fall back to .m3u8
    m = mark()
    key(UP, pause=0.3)
    shot('live-zap-banner')
    ready = wait_log(r'ready index=1 format=(\w+)', m, 120)
    pos = wait_position(1, 5, m, 60)
    shot('live-channel-2')
    check('channel change + fallback to the second stream format', ready is not None and ready.group(1) == 'm3u8' and pos >= 5,
          '%s, position %ss' % (ready.group(0) if ready else 'not ready', pos))
    key(OK)
    shot('live-info-toggled')

    # 4. channel 3 never works: the app must stop retrying with a clear message, not crash
    m = mark()
    key(UP, pause=0.3)
    gave_up = wait_log(r'gave up index=2', m, 150)
    shot('live-offline-channel')
    check('dead channel ends with a message instead of hanging', gave_up is not None)

    key(BACK, pause=2)
    shot('back-to-channel-list')
    key(BACK, pause=2)
    shot('back-to-home')

    # 5. movie: play, jump forward, leave, come back (resume)
    m = mark()
    key(RIGHT)
    key(OK)
    got = wait_log(r'browse vod items=(\d+)', m, 60)
    time.sleep(2)
    shot('movies')
    check('Movies shows categories and titles', got is not None and int(got.group(1)) == 2, got.group(0) if got else '')
    key(RIGHT)
    m = mark()
    key(OK)
    ready = wait_log(r'ready index=0 format=mp4', m, 90)
    pos = wait_position(0, 5, m, 60)
    shot('movie-playing')
    check('movie plays', ready is not None and pos >= 5, 'position %ss' % pos)
    m = mark()
    for _ in range(6):
        key(RIGHT, pause=0.25)
    shot('movie-seeking')
    pos = wait_position(0, 60, m, 25)
    shot('movie-after-jump')
    check('Right x6 jumps about one minute forward', pos >= 60, 'position %ss' % pos)
    key(OK)
    time.sleep(1)
    shot('movie-paused')
    key(BACK, pause=2)
    m = mark()
    key(OK)
    ready = wait_log(r'ready index=0 format=mp4', m, 90)
    pos = wait_position(0, 60, m, 25)
    shot('movie-resumed')
    check('movie resumes where it was left', ready is not None and pos >= 60, 'position %ss' % pos)
    key(BACK, pause=2)
    key(BACK, pause=2)

    # 6. series
    m = mark()
    key(RIGHT)
    key(OK)
    got = wait_log(r'browse series items=(\d+)', m, 60)
    time.sleep(2)
    shot('series-list')
    check('Series shows categories and titles', got is not None and int(got.group(1)) == 1, got.group(0) if got else '')
    key(RIGHT)
    m = mark()
    key(OK)
    got = wait_log(r'series seasons=(\d+)', m, 60)
    time.sleep(2)
    shot('series-episodes')
    check('series page lists seasons and episodes', got is not None and int(got.group(1)) == 2, got.group(0) if got else '')
    m = mark()
    key(OK)
    ready = wait_log(r'ready index=0 format=mp4', m, 90)
    pos = wait_position(0, 5, m, 60)
    shot('episode-playing')
    check('episode plays', ready is not None and pos >= 5, 'position %ss' % pos)
    key(BACK, pause=2)
    key(BACK, pause=2)
    key(BACK, pause=2)
    shot('end-home')

    # 7. the app must still be alive and must not have crashed
    logcat = adb('logcat', '-d', timeout=60)
    crashed = re.findall(r'Process: com\.b1g\.b1gtv.*|Fatal signal.*com\.b1g\.b1gtv.*', logcat)
    check('no crash in the device log', not crashed, crashed[:2])
    alive = adb('shell', 'pidof', PKG).strip()
    check('app is still running at the end', alive != '', alive)


if __name__ == '__main__':
    main()
    sys.exit(0)
