#!/bin/sh
# The decoding tests' own files (MediaAppleTest.hx), beside tests/media's:
# what Apple's decoders take that those are not (VP9 in 4:2:0 from 128
# pixels, its hardware's least; 10 bits, BT.2020; full range) and audio of a
# chirp, so that a sample off shows. expect.mjs records ffmpeg's decoding.
#   sh tests/media/apple/fixtures.sh   (from the repository's root)
set -e
cd "$(dirname "$0")"
f() { ffmpeg -hide_banner -loglevel error -y "$@"; }
plain="-map_metadata -1 -fflags +bitexact -flags:v +bitexact -flags:a +bitexact"
chirp="-f lavfi -i aevalsrc=0.5*sin(2*PI*(200+2800*t)*t):s=16000:d=0.5"
# VP9 4:2:0 and Opus
f -f lavfi -i testsrc=size=128x96:rate=10:duration=1 $chirp -c:v libvpx-vp9 -pix_fmt yuv420p -b:v 60k -g 5 -c:a libopus -b:a 24k $plain vp9-yuv.webm
# HEVC Main 10, BT.2020, video range
f -f lavfi -i testsrc=size=64x48:rate=10:duration=0.5 -c:v libx265 -x265-params log-level=none:bframes=2:keyint=5 -preset ultrafast -tag:v hvc1 -pix_fmt yuv420p10le -colorspace bt2020nc -color_primaries bt2020 -color_trc smpte2084 $plain hevc10.mp4
# H.264, full range, BT.709
f -f lavfi -i testsrc=size=64x48:rate=10:duration=0.5 -c:v libx264 -preset veryfast -bf 2 -pix_fmt yuvj420p -colorspace bt709 -color_range pc $plain h264-full.mp4
# the chirp in AAC, MP3, FLAC, ALAC and Opus (MP4), Vorbis (Matroska)
f $chirp $chirp $chirp $chirp $chirp -map 0 -map 1 -map 2 -map 3 -map 4 -c:a:0 aac -b:a:0 64k -c:a:1 libmp3lame -b:a:1 64k -c:a:2 flac -c:a:3 alac -c:a:4 libopus -b:a:4 32k $plain chirp.mp4
f $chirp -c:a vorbis -strict -2 -ac 2 $plain chirp.mkv
node expect.mjs
ls -l *.mp4 *.webm *.mkv
