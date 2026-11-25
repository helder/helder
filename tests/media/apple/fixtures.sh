#!/bin/sh
# The decoding tests' own files (MediaAppleCheck.hx), beside tests/media's:
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
# flat quadrants (red, green, blue, grey) and a square moving: VideoWindowCheck's
# colours, away from edges (at crf 18 or less Apple's decoding of it is not
# ffmpeg's: the right half's Cr 255, not the source's 34 and 128, on an M4
# and CI's virtual Mac; AVAssetReader's the same byte for byte, so the
# system's decoder's, not helder's feeding of it)
sq="between(X,N*5,N*5+5)*between(Y,20,27)"
f -f lavfi -i "nullsrc=s=64x48:r=10:d=1,format=rgb24,geq=r='if($sq,255,if(lt(Y,24),if(lt(X,32),255,0),if(lt(X,32),0,128)))':g='if($sq,255,if(lt(Y,24),if(lt(X,32),0,255),if(lt(X,32),0,128)))':b='if($sq,255,if(lt(Y,24),0,if(lt(X,32),255,128)))'" -c:v libx264 -preset veryslow -crf 23 -g 10 -pix_fmt yuv420p $plain quads.mp4
# the chirp in AAC, MP3, FLAC, ALAC and Opus (MP4), Vorbis (Matroska)
f $chirp $chirp $chirp $chirp $chirp -map 0 -map 1 -map 2 -map 3 -map 4 -c:a:0 aac -b:a:0 64k -c:a:1 libmp3lame -b:a:1 64k -c:a:2 flac -c:a:3 alac -c:a:4 libopus -b:a:4 32k $plain chirp.mp4
f $chirp -c:a vorbis -strict -2 -ac 2 $plain chirp.mkv
node expect.mjs
ls -l *.mp4 *.webm *.mkv
