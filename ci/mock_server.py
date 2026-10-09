#!/usr/bin/env python3
"""
Mock IPTV server for the automated test. It answers like an Xtream Codes panel
(player_api.php) and serves the generated test videos from ci/media.

    username / password: demo / demo
    channel 1  .ts works            channel 2  only .m3u8 works (tests the fallback)
    Live .ts is sent like a real panel does it: a short burst, then at real-time speed, and only
    ONE live connection at a time (a second one gets "403 max connections").
    channel 3  never works          movie 10, series 20 (episodes 31, 32)
"""
import base64
import json
import os
import re
import select
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
MEDIA = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'media')
BASE = 'http://10.0.2.2:%d' % PORT  # the host machine as seen from the emulator

LIVE_CATS = [{'category_id': '1', 'category_name': 'UK Entertainment', 'parent_id': 0},
             {'category_id': '2', 'category_name': 'Sports', 'parent_id': 0}]
LIVE = [
    {'num': 1, 'name': 'Test One FHD', 'stream_type': 'live', 'stream_id': 1, 'stream_icon': BASE + '/logo.png', 'epg_channel_id': 'one', 'category_id': '1'},
    {'num': 2, 'name': 'Test Two (HLS only)', 'stream_type': 'live', 'stream_id': 2, 'stream_icon': '', 'epg_channel_id': 'two', 'category_id': '1'},
    {'num': 3, 'name': 'Offline channel', 'stream_type': 'live', 'stream_id': 3, 'stream_icon': '', 'epg_channel_id': None, 'category_id': '1'},
    {'num': 5, 'name': 'Test One HD*', 'stream_type': 'live', 'stream_id': 5, 'stream_icon': BASE + '/logo.png', 'epg_channel_id': 'one', 'category_id': '1'},
    {'num': 4, 'name': 'Sports One', 'stream_type': 'live', 'stream_id': '4', 'stream_icon': BASE + '/logo.png', 'epg_channel_id': '', 'category_id': '2'},
]
VOD_CATS = [{'category_id': '11', 'category_name': 'Action', 'parent_id': 0}]
VOD = [{'num': 1, 'name': 'Test Movie', 'stream_type': 'movie', 'stream_id': 10, 'stream_icon': BASE + '/poster.jpg', 'rating': '7.5', 'category_id': '11', 'container_extension': 'mp4'},
       {'num': 2, 'name': 'Second Movie With A Rather Long Title', 'stream_type': 'movie', 'stream_id': 12, 'stream_icon': '', 'rating': '', 'category_id': '11', 'container_extension': 'mp4'}]
SERIES_CATS = [{'category_id': '21', 'category_name': 'Drama', 'parent_id': 0}]
SERIES = [{'num': 1, 'name': 'Test Series', 'series_id': 20, 'cover': BASE + '/poster.jpg', 'plot': 'A short plot.', 'category_id': '21'}]
SERIES_INFO = {
    'seasons': [],
    'info': {'name': 'Test Series', 'cover': BASE + '/poster.jpg', 'plot': 'Two friends test an app until every screen works.', 'genre': 'Drama'},
    'episodes': {
        '1': [{'id': '31', 'episode_num': 1, 'title': 'Pilot', 'container_extension': 'mp4', 'info': {'duration': '00:05:00'}, 'season': 1},
              {'id': '32', 'episode_num': 2, 'title': 'The Second One', 'container_extension': 'mp4', 'info': {'duration': '00:05:00'}, 'season': 1}],
        '2': [{'id': '33', 'episode_num': 1, 'title': 'New Season', 'container_extension': 'mp4', 'info': [], 'season': 2}],
    },
}


# A plain M3U playlist (no Xtream login). "M3U Two" has no .ts on this server: the app must try .m3u8.
PLAYLIST = '''#EXTM3U
#EXTINF:-1 tvg-id="one" tvg-logo="{b}/logo.png" group-title="UK",M3U One
{b}/live/demo/demo/1.ts
#EXTINF:-1 tvg-id="two" group-title="UK",M3U Two, HLS only
{b}/live/demo/demo/2.ts
#EXTINF:-1 tvg-logo="{b}/logo.png" group-title="Sports",M3U Sports
{b}/live/demo/demo/4.ts
#EXTINF:-1 tvg-logo="{b}/poster.jpg" group-title="Films",M3U Movie
{b}/movie/demo/demo/10.mp4
#EXTINF:-1 group-title="Shows",M3U Show S01 E01
{b}/series/demo/demo/31.mp4
'''.format(b=BASE)


LIVE_SECONDS = 90.0  # length of ci/media/live.ts
LIVE_LOCK = threading.Lock()
LIVE_ACTIVE = [0]


def b64(text):
    return base64.b64encode(text.encode()).decode()


def epg():
    now = int(time.time())
    start = now - 600
    rows = []
    for i, title in enumerate(['Morning Show', 'News at Ten', 'Late Film']):
        s = start + i * 1800
        rows.append({'id': str(i), 'title': b64(title), 'description': b64('About ' + title),
                     'start_timestamp': str(s), 'stop_timestamp': str(s + 1800)})
    return {'epg_listings': rows}


SITE = '/wp-json/b1g/v1'
SITE_LISTS = [False]
SITE_CONFIG = [False]
UPDATE_APK = 'out/smoke-apk/b1g-smoke.apk'


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, fmt, *args):
        sys.stdout.write('%s %s\n' % (time.strftime('%H:%M:%S'), fmt % args))
        sys.stdout.flush()

    def send_json(self, data, code=200):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, text, ctype, code=200):
        body = text.encode()
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, name, ctype):
        path = os.path.join(MEDIA, name)
        if not os.path.isfile(path):
            return self.send_text('not found', 'text/plain', 404)
        size = os.path.getsize(path)
        start, end = 0, size - 1
        m = re.match(r'bytes=(\d*)-(\d*)', self.headers.get('Range') or '')
        partial = False
        if m and (m.group(1) or m.group(2)):
            partial = True
            if m.group(1):
                start = int(m.group(1))
                if m.group(2):
                    end = min(int(m.group(2)), size - 1)
            else:
                start = max(0, size - int(m.group(2)))
            if start >= size:
                self.send_response(416)
                self.send_header('Content-Range', 'bytes */%d' % size)
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
        length = end - start + 1
        self.send_response(206 if partial else 200)
        self.send_header('Content-Type', ctype)
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Length', str(length))
        if partial:
            self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, end, size))
        self.end_headers()
        try:
            with open(path, 'rb') as f:
                f.seek(start)
                left = length
                while left > 0:
                    chunk = f.read(min(65536, left))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    left -= len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def client_gone(self):
        try:
            readable, _, _ = select.select([self.connection], [], [], 0)
            return bool(readable) and self.connection.recv(1, socket.MSG_PEEK) == b''
        except OSError:
            return True

    def send_live(self, name):
        path = os.path.join(MEDIA, name)
        with LIVE_LOCK:
            busy = LIVE_ACTIVE[0] >= 1
            if not busy:
                LIVE_ACTIVE[0] += 1
        if busy:
            print('LIVE refused: max connections', flush=True)
            return self.send_text('max connections reached', 'text/plain', 403)
        print('LIVE open', flush=True)
        sent = 0
        try:
            rate = os.path.getsize(path) / LIVE_SECONDS
            burst = rate * 3
            self.send_response(200)
            self.send_header('Content-Type', 'video/mp2t')
            self.send_header('Connection', 'close')
            self.end_headers()
            self.close_connection = True
            start = time.time()
            with open(path, 'rb') as f:
                while not self.client_gone():
                    chunk = f.read(16384)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
                    sent += len(chunk)
                    ahead = (sent - burst) / rate - (time.time() - start)
                    if ahead > 0:
                        time.sleep(min(ahead, 0.2))
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            with LIVE_LOCK:
                LIVE_ACTIVE[0] -= 1
            print('LIVE close after %d bytes' % sent, flush=True)

    def do_HEAD(self):
        self.do_GET()

    # A stand-in for the B1G website (device registration, licence, playlists added online).
    def site(self, path):
        device = {'device_id': 'B1G-TEST01', 'pairing_code': '123456', 'status': 'trial',
                  'licence_type': 'trial', 'days_left': 7}
        if path in ('/device/register', '/device/status'):
            return self.send_json({'success': True, 'device': device})
        if path == '/device/playlists':
            lists = [{'id': 1, 'name': 'My IPTV', 'type': 'xtream', 'url': BASE,
                      'username': 'demo', 'password': 'demo'}] if SITE_LISTS[0] else []
            return self.send_json({'success': True, 'device': device, 'playlists': lists})
        if path == '/app/config':
            # Off: a website that has no default server and announces no update.
            on = SITE_CONFIG[0]
            return self.send_json({
                'success': True,
                'config': {'server_url': BASE if on else '', 'server_name': 'B1G TV' if on else ''},
                'update': {'version_code': 999, 'version_name': '9.9.9', 'apk_url': BASE + '/app/B1G.apk',
                           'notes': 'Faster start.\nSmall fixes.', 'force': False} if on else None,
            })
        return self.send_json({'success': False, 'message': 'Unknown route.'}, 404)

    def do_POST(self):
        length = int(self.headers.get('Content-Length') or 0)
        body = self.rfile.read(length) if length else b''
        try:  # which fields the app sent (names only)
            print('POST %s fields=%s' % (self.path, ','.join(sorted(json.loads(body or b'{}').keys()))), flush=True)
        except Exception:
            pass
        path = urlparse(self.path).path
        if path.startswith(SITE):
            return self.site(path[len(SITE):])
        return self.send_text('not found', 'text/plain', 404)

    def do_GET(self):
        url = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        path = url.path
        if path.startswith(SITE):
            return self.site(path[len(SITE):])
        if path == '/test/config-on':  # the test sets a default server and announces an update
            SITE_CONFIG[0] = True
            return self.send_text('ok', 'text/plain')
        if path == '/app/B1G.apk':  # the "new version": the test app itself
            return self.send_file(os.path.abspath(UPDATE_APK), 'application/vnd.android.package-archive')
        if path == '/test/site-lists-on':  # the test switches on "a playlist was added on the website"
            SITE_LISTS[0] = True
            return self.send_text('ok', 'text/plain')
        if path == '/player_api.php':
            return self.api(q)
        # A stand-in for TMDB (the test build is pointed here instead of themoviedb.org).
        if path == '/3/search/movie':
            hit = 'test movie' in q.get('query', '').lower()
            return self.send_json({'results': [{'id': 555, 'title': 'Test Movie'}] if hit else []})
        if path == '/3/movie/555':
            return self.send_json({
                'id': 555, 'title': 'Test Movie', 'overview': 'From the film database.', 'runtime': 138,
                'release_date': '2026-03-14', 'vote_average': 6.4, 'backdrop_path': '/back.jpg',
                'genres': [{'id': 1, 'name': 'Action'}],
                'credits': {'cast': [
                    {'name': 'Ali Khan', 'character': 'Shivam', 'profile_path': '/p1.jpg'},
                    {'name': 'Sara Ahmed', 'character': 'Zara', 'profile_path': '/p2.jpg'},
                    {'name': 'John Smith', 'character': 'The Tester', 'profile_path': None},
                    {'name': 'Maria Lopez', 'character': 'Engineer', 'profile_path': '/p4.jpg'}]},
                'images': {'backdrops': [{'file_path': '/s1.jpg'}, {'file_path': '/s2.jpg'}, {'file_path': '/s3.jpg'}]},
                'videos': {'results': [{'site': 'YouTube', 'type': 'Trailer', 'key': 'TESTtrailer'}]},
            })
        if path.startswith('/t/p/'):
            return self.send_file('poster.jpg', 'image/jpeg')
        if path == '/playlist.m3u':
            return self.send_text(PLAYLIST, 'audio/x-mpegurl')
        if path in ('/logo.png', '/poster.jpg'):
            return self.send_file(path[1:], 'image/png' if path.endswith('png') else 'image/jpeg')
        m = re.match(r'^/hls/(seg\d+\.ts)$', path)
        if m:
            return self.send_file('hls/' + m.group(1), 'video/mp2t')
        m = re.match(r'^/(live|movie|series)/demo/demo/(\d+)\.(\w+)$', path)
        if not m:
            return self.send_text('not found', 'text/plain', 404)
        kind, sid, ext = m.group(1), m.group(2), m.group(3)
        if kind == 'live':
            if sid in ('1', '4', '5') and ext == 'ts':
                return self.send_live('live.ts')
            if sid in ('1', '2', '4') and ext == 'm3u8':
                with open(os.path.join(MEDIA, 'hls', 'index.m3u8')) as f:
                    text = re.sub(r'^(seg\d+\.ts)$', r'/hls/\1', f.read(), flags=re.M)
                return self.send_text(text, 'application/vnd.apple.mpegurl')
            return self.send_text('not found', 'text/plain', 404)
        return self.send_file('movie.mp4', 'video/mp4')

    def api(self, q):
        ok = q.get('username') == 'demo' and q.get('password') == 'demo'
        action = q.get('action')
        if not ok:
            return self.send_json({'user_info': {'auth': 0}})
        if not action:
            return self.send_json({
                'user_info': {'username': 'demo', 'password': 'demo', 'auth': 1, 'status': 'Active',
                              'exp_date': str(int(time.time()) + 90 * 86400), 'is_trial': '0', 'active_cons': '0',
                              'max_connections': '1', 'allowed_output_formats': ['m3u8', 'ts']},
                'server_info': {'url': '10.0.2.2', 'port': str(PORT), 'server_protocol': 'http'},
            })
        cat = q.get('category_id')

        def by_cat(rows):
            return [r for r in rows if cat is None or str(r['category_id']) == cat]

        table = {
            'get_live_categories': LIVE_CATS, 'get_vod_categories': VOD_CATS, 'get_series_categories': SERIES_CATS,
            'get_live_streams': by_cat(LIVE), 'get_vod_streams': by_cat(VOD), 'get_series': by_cat(SERIES),
        }
        if action in table:
            return self.send_json(table[action])
        if action == 'get_vod_info':
            return self.send_json({
                'info': {'movie_image': BASE + '/poster.jpg', 'backdrop_path': [BASE + '/poster.jpg'],
                         'plot': 'Two engineers test a TV app all night until every screen, every button and every '
                                 'stream works the way it should. A story about patience and test cards.',
                         'cast': 'Ali Khan, Sara Ahmed, John Smith, Maria Lopez', 'director': 'Test Director',
                         'genre': 'Action, Drama', 'releasedate': '2026-03-14', 'rating': '6.4',
                         'duration': '00:05:00', 'duration_secs': 300, 'youtube_trailer': 'TESTtrailer'},
                'movie_data': {'stream_id': 10, 'name': 'Test Movie', 'container_extension': 'mp4'},
            })
        if action == 'get_series_info':
            return self.send_json(SERIES_INFO)
        if action == 'get_short_epg':
            return self.send_json(epg() if q.get('stream_id') in ('1', '2') else {'epg_listings': []})
        return self.send_json([])


if __name__ == '__main__':
    print('mock IPTV server on port %d, media in %s' % (PORT, MEDIA), flush=True)
    ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()
