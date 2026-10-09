#!/usr/bin/env bash
# Small test videos for the emulator test (generated, never real TV content).
set -euo pipefail
M=ci/media
mkdir -p "$M/hls"
V="-c:v libx264 -preset veryfast -profile:v main -pix_fmt yuv420p -g 50"
A="-c:a aac -b:a 96k -ac 2"
SINE="sine=frequency=440:sample_rate=48000"
ffmpeg -loglevel error -y -f lavfi -i "testsrc=size=1280x720:rate=25" -f lavfi -i "$SINE" -t 90 $V -b:v 1200k $A -f mpegts "$M/live.ts"
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=1280x720:rate=25" -f lavfi -i "$SINE" -t 60 $V -b:v 1200k $A \
  -f hls -hls_time 4 -hls_list_size 0 -hls_segment_filename "$M/hls/seg%03d.ts" "$M/hls/index.m3u8"
# The movie has two audio languages and a subtitle track, to test the audio / subtitle menu.
python3 - "$M/subs.srt" <<'PY'
import sys
def t(s): return '%02d:%02d:%02d,000' % (s // 3600, s % 3600 // 60, s % 60)
with open(sys.argv[1], 'w') as f:
    for i in range(0, 300, 4):
        f.write('%d\n%s --> %s\nSubtitle line at %d seconds\n\n' % (i // 4 + 1, t(i), t(i + 3), i))
PY
ffmpeg -loglevel error -y -f lavfi -i "testsrc=size=640x360:rate=25" -f lavfi -i "$SINE" \
  -f lavfi -i "sine=frequency=880:sample_rate=48000" -i "$M/subs.srt" -t 300 \
  -map 0:v -map 1:a -map 2:a -map 3:s $V -b:v 500k $A -c:s mov_text \
  -metadata:s:a:0 language=eng -metadata:s:a:1 language=urd -metadata:s:s:0 language=eng \
  -movflags +faststart "$M/movie.mp4"
ffmpeg -loglevel error -y -f lavfi -i "color=c=0xFFC400:s=160x160" -frames:v 1 "$M/logo.png"
ffmpeg -loglevel error -y -f lavfi -i "testsrc=size=300x450" -frames:v 1 "$M/poster.jpg"
ls -la "$M" "$M/hls" | head -40
