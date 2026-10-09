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
ffmpeg -loglevel error -y -f lavfi -i "testsrc=size=640x360:rate=25" -f lavfi -i "$SINE" -t 300 $V -b:v 500k $A -movflags +faststart "$M/movie.mp4"
ffmpeg -loglevel error -y -f lavfi -i "color=c=0xFFC400:s=160x160" -frames:v 1 "$M/logo.png"
ffmpeg -loglevel error -y -f lavfi -i "testsrc=size=300x450" -frames:v 1 "$M/poster.jpg"
ls -la "$M" "$M/hls" | head -40
