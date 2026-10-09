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


def picture_share(name):
    """Share of clearly non-black pixels in the middle of the newest screenshot called `name` (0..1)."""
    try:
        from PIL import Image
        path = sorted(p for p in os.listdir(OUT) if p.endswith('-%s.png' % name))[-1]
        im = Image.open(os.path.join(OUT, path)).convert('RGB')
        w, h = im.size
        box = im.crop((w // 4, h // 4, w * 3 // 4, h * 3 // 4)).resize((96, 54))
        px = list(box.getdata())
        return sum(1 for r, g, b in px if max(r, g, b) > 60) / float(len(px))
    except Exception as exc:  # noqa: BLE001
        print('picture_share failed: %s' % exc, flush=True)
        return -1.0


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
    # The emulator uses a phone system image, which starts in "touch mode": Android swallows the
    # first remote key to leave that mode. A real TV is never in touch mode. Down does nothing here.
    key(DOWN)
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
    # The mock sends live TV like a real panel: short burst, then real-time speed, one connection only.
    # (The emulator has no graphics chip, so in the standard picture mode it plays without a visible
    # picture; the picture itself is checked at the very end, in the direct mode.)
    pos = wait_position(0, 25, m, 60)
    opens = len([line for line in app_log()[m:] if 'open index=0' in line])
    shot('live-after-25s')
    check('live keeps playing for 25 s on a real-time stream without reconnecting', pos >= 25 and opens == 1,
          'position %ss, opened %d time(s)' % (pos, opens))

    # 2b. panels inside the player: channel list (Left) and audio / subtitles (Right)
    m = mark()
    key(LEFT, pause=2)
    got = wait_log(r'panel=channels', m, 10)
    shot('live-channel-list')
    key(BACK, pause=1.5)
    m2 = mark()
    key(RIGHT, pause=2)
    got2 = wait_log(r'panel=options', m2, 10)
    shot('live-options')
    key(BACK, pause=1.5)
    check('channel list and options open inside the live player', got is not None and got2 is not None)

    # 3. channel up: channel 2 has no .ts on the mock server, the app must fall back to .m3u8
    m = mark()
    key(UP, pause=0.3)
    shot('live-zap-banner')
    ready = wait_log(r'ready index=1 format=(\w+)', m, 120)
    pos = wait_position(1, 5, m, 60)
    shot('live-channel-2')
    check('channel change + fallback to the second stream format', ready is not None and ready.group(1) == 'm3u8' and pos >= 5,
          '%s, position %ss' % (ready.group(0) if ready else 'not ready', pos))
    key(OK)  # OK shows the button bar; the remote lands on "Channel list"
    time.sleep(1)
    shot('live-button-bar')

    # 3b. pick a channel from the list inside the player
    key(OK, pause=2)
    shot('live-channel-list-from-button')
    key(UP)
    m = mark()
    key(OK)
    ready = wait_log(r'ready index=0 format=(\w+)', m, 90)
    pos = wait_position(0, 5, m, 60)
    shot('live-picked-from-list')
    check('a channel can be picked from the list in the player', ready is not None and pos >= 5,
          '%s, position %ss' % (ready.group(0) if ready else 'not ready', pos))

    # 4. channel 3 never works: the app must stop retrying with a clear message, not crash
    m = mark()
    key(UP, pause=0.3)
    key(UP, pause=0.3)
    gave_up = wait_log(r'gave up index=2', m, 320)
    shot('live-offline-channel')
    check('dead channel ends with a message instead of hanging', gave_up is not None)

    key(BACK, pause=2)
    shot('back-to-channel-list')

    # 4b. favourites (hold OK) and search (text typed with a keyboard)
    m = mark()
    adb('shell', 'input', 'keyevent', '--longpress', OK)
    got = wait_log(r'favourite added', m, 20)
    time.sleep(0.5)
    shot('favourite-added')
    check('holding OK adds a favourite', got is not None)
    key(LEFT)
    for _ in range(4):
        key(UP, pause=0.4)
    shot('search-row-focused')
    key(OK, pause=2)
    m = mark()
    adb('shell', 'input', 'text', 'Two')
    time.sleep(1)
    shot('search-typed')
    key('66', pause=1)  # Enter
    got = wait_log(r'browse live search=(\d+)', m, 40)
    time.sleep(1)
    shot('search-result')
    check('search finds the channel', got is not None and int(got.group(1)) == 1, got.group(0) if got else '')
    m = mark()
    key(DOWN)
    key(OK)
    got = wait_log(r'browse live favourites=(\d+)', m, 20)
    time.sleep(1)
    shot('favourites-list')
    check('Favourites lists the saved channel', got is not None and int(got.group(1)) == 1, got.group(0) if got else '')

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
    key(OK)  # a movie opens on its details page
    info = wait_log(r'screen=movie details=(\w+) cast=(\w+) trailer=(\w+)', m, 30)
    time.sleep(2)
    shot('movie-details')
    check('the movie details page shows plot, cast and trailer from the server',
          info is not None and info.groups() == ('true', 'true', 'true'), info.group(0) if info else '')
    extra = wait_log(r'tmdb cast=(\d+) stills=(\d+)', m, 20)
    time.sleep(2)
    shot('movie-details-with-cast-photos')
    check('cast photos and stills are added from the film database',
          extra is not None and extra.group(1) == '4' and extra.group(2) == '3', extra.group(0) if extra else '')
    key(DOWN)
    time.sleep(1)
    shot('movie-details-cast-row')
    key(DOWN)
    time.sleep(1)
    shot('movie-details-media-row')
    key(UP)
    key(UP)
    m = mark()
    key(OK)  # "Watch now"
    ready = wait_log(r'ready index=0 format=mp4', m, 90)
    pos = wait_position(0, 5, m, 60)
    shot('movie-playing')
    check('movie plays', ready is not None and pos >= 5, 'position %ss' % pos)

    # 5b. audio language and subtitles (the test movie has English + Urdu audio and English subtitles)
    tracks = wait_log(r'tracks audio=(\d+) subtitles=(\d+)', m, 10)
    check('the movie reports its audio and subtitle tracks', tracks is not None and tracks.group(1) == '2' and tracks.group(2) == '1',
          tracks.group(0) if tracks else '')
    m2 = mark()
    key(OK)  # shows the button bar, the remote lands on Play / Pause
    time.sleep(1)
    shot('movie-button-bar')
    key(RIGHT)  # Forward 10 s
    key(RIGHT)  # Audio language
    shot('movie-audio-button')
    key(OK, pause=2)
    panel = wait_log(r'panel=options', m2, 10)
    shot('movie-options')
    check('the player buttons can be reached and pressed with the remote', panel is not None)
    key(DOWN)
    key(OK)
    audio = wait_log(r'audio track=urd', m2, 10)
    key(DOWN)
    key(DOWN)
    key(OK)
    subs = wait_log(r'subtitle track=eng', m2, 10)
    time.sleep(1)
    shot('movie-options-chosen')
    key(BACK, pause=4)
    shot('movie-with-subtitles')
    before = wait_position(0, 0, m2, 1)
    time.sleep(6)
    after = wait_position(0, 0, m2, 1)
    check('audio language and subtitles can be changed with the remote', audio is not None and subs is not None)
    check('the movie keeps playing after the change', after > before, '%ss -> %ss' % (before, after))

    # (the button bar has hidden itself again by now, so Left / Right jump directly)
    m = mark()
    for _ in range(6):
        key(RIGHT, pause=0.25)
    shot('movie-seeking')
    pos = wait_position(0, 60, m, 25)
    shot('movie-after-jump')
    check('Right x6 jumps about one minute forward', pos >= 60, 'position %ss' % pos)
    m = mark()
    key(OK)  # button bar, on Play / Pause
    key(OK)  # pause
    paused = wait_log(r'paused', m, 10)
    time.sleep(1)
    shot('movie-paused')
    check('OK on the Pause button pauses the movie', paused is not None)

    # 5c. touch: a tap shows the touch controls, the back button closes the player
    adb('shell', 'input', 'tap', '960', '330')
    time.sleep(1.5)
    shot('movie-touch-controls')
    m = mark()
    adb('shell', 'input', 'tap', '96', '80')
    closed = wait_log(r'player closed', m, 10)
    time.sleep(1.5)
    shot('movie-touch-back')
    check('touch: the back button closes the player', closed is not None)
    if closed is None:
        key(BACK, pause=2)
    m = mark()
    key(OK)
    ready = wait_log(r'ready index=0 format=mp4', m, 90)
    pos = wait_position(0, 60, m, 25)
    shot('movie-resumed')
    check('movie resumes where it was left', ready is not None and pos >= 60, 'position %ss' % pos)
    key(BACK, pause=2)  # player -> details
    key(BACK, pause=2)  # details -> list
    key(BACK, pause=2)  # list -> home

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

    # 6b. sign out, wrong password, then type the right one with the remote + keyboard
    key(DOWN)
    shot('sign-out-focused')
    key(OK, pause=2)
    shot('sign-out-dialog')
    m = mark()
    key(RIGHT)
    key(OK)
    ok = wait_log(r'screen=login', m, 30) is not None
    time.sleep(2)
    shot('signed-out')
    check('sign out returns to the sign-in screen', ok)

    def retype_password(text):
        key(UP)  # the password row
        key(OK, pause=1.5)  # OK opens the keyboard on it
        for _ in range(8):
            key('67', pause=0.2)  # Delete
        adb('shell', 'input', 'text', text)
        time.sleep(1)

    retype_password('nope')
    shot('password-typed')
    m = mark()
    key('66')  # the keyboard's Done key signs in
    got = wait_log(r'login failed: XtreamAuthException', m, 30)
    time.sleep(1)
    shot('wrong-password')
    check('wrong password is refused with a message', got is not None)
    retype_password('demo')
    m = mark()
    key('66')
    ok = wait_log(r'screen=home', m, 30) is not None
    time.sleep(2)
    shot('signed-in-again')
    check('typing the password and signing in again works', ok)

    # 6c. the same app with a plain M3U playlist link instead of an Xtream login
    key(DOWN)
    key(OK, pause=2)
    m = mark()
    key(RIGHT)
    key(OK)
    ok = wait_log(r'screen=login', m, 30) is not None
    time.sleep(2)
    for _ in range(4):
        key(UP, pause=0.5)  # password, username, server, then the "Xtream Codes" tab
    m = mark()
    key(RIGHT)
    key(OK)
    got = wait_log(r'login mode=m3u', m, 15)
    shot('m3u-tab')
    check('the M3U link option can be chosen with the remote', ok and got is not None)
    key(DOWN)  # the playlist link row
    shot('m3u-row-focused')
    key(OK, pause=1.5)
    adb('shell', 'input', 'text', 'http://10.0.2.2:8787/playlist.m3u')
    time.sleep(1)
    shot('m3u-link-typed')
    m = mark()
    key('66')
    got = wait_log(r'login ok mode=m3u (.*)$', m, 40)
    ok = wait_log(r'screen=home', m, 20) is not None
    time.sleep(2)
    shot('m3u-home')
    check('playlist link loads', got is not None and ok and '3 channels' in got.group(1), got.group(0) if got else '')
    m = mark()
    key(OK)
    got = wait_log(r'browse live items=(\d+)', m, 40)
    time.sleep(2)
    shot('m3u-live-list')
    check('playlist channels are grouped', got is not None and int(got.group(1)) == 2, got.group(0) if got else '')
    key(RIGHT)
    m = mark()
    key(OK)
    ready = wait_log(r'ready index=0 format=(\w+)', m, 90)
    pos = wait_position(0, 5, m, 60)
    shot('m3u-channel-playing')
    check('playlist channel plays', ready is not None and pos >= 5, 'position %ss' % pos)
    m = mark()
    key(UP, pause=0.3)
    ready = wait_log(r'ready index=1 format=(\w+)', m, 120)
    pos = wait_position(1, 5, m, 60)
    shot('m3u-channel-2')
    check('playlist channel falls back to the other stream format', ready is not None and ready.group(1) == 'm3u8' and pos >= 5,
          '%s, position %ss' % (ready.group(0) if ready else 'not ready', pos))
    key(BACK, pause=2)
    key(BACK, pause=2)
    m = mark()
    key(RIGHT)
    key(OK)
    got = wait_log(r'browse vod items=(\d+)', m, 40)
    time.sleep(2)
    key(RIGHT)
    key(OK, pause=3)  # details page (a playlist only has name and picture)
    m2 = mark()
    key(OK)  # "Watch now"
    ready = wait_log(r'ready index=0 format=mp4', m2, 90)
    pos = wait_position(0, 5, m2, 60)
    shot('m3u-movie-playing')
    check('playlist movie plays', got is not None and ready is not None and pos >= 5, 'position %ss' % pos)

    # 7. the picture itself: switch this movie to the direct picture mode (which the emulator can draw)
    key(OK)  # button bar
    key(RIGHT)
    key(RIGHT)  # Audio language
    key(OK, pause=2)  # options panel
    for _ in range(10):
        key(DOWN, pause=0.4)  # down to the last row: Video mode
    shot('video-mode-row')
    m3 = mark()
    key(LEFT)  # "Standard"
    key(RIGHT)  # "Direct"
    key(OK)
    chosen = wait_log(r'video mode=direct', m3, 10)
    ready = wait_log(r'ready index=0 format=mp4 video=\d+x\d+ mode=direct', m3, 60)
    key(BACK, pause=2)  # close the panel
    key(BACK, pause=4)  # put the button bar away
    shot('direct-mode-picture')
    share = picture_share('direct-mode-picture')
    check('the picture mode can be changed in the player', chosen is not None and ready is not None)
    check('the movie picture is really visible on the screen (direct mode)', share > 0.5, 'non-black share %.2f' % share)
    key(BACK, pause=2)
    key(BACK, pause=2)
    key(BACK, pause=2)
    shot('m3u-end-home')

    # 7. the app must still be alive and must not have crashed
    logcat = adb('logcat', '-d', timeout=60)
    crashed = re.findall(r'Process: com\.b1g\.b1gtv.*|Fatal signal.*com\.b1g\.b1gtv.*', logcat)
    check('no crash in the device log', not crashed, crashed[:2])
    alive = adb('shell', 'pidof', PKG).strip()
    check('app is still running at the end', alive != '', alive)


if __name__ == '__main__':
    main()
    sys.exit(0)
