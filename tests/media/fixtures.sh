#!/bin/sh
# The media tests' files (src/helder/media/*.test.hx), made by ffmpeg 9 and
# lace.mjs; the tests hold what ffprobe reads in them (CI has no ffprobe).
#   sh tests/media/fixtures.sh   (from the repository's root)
set -e
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
f() { ffmpeg -hide_banner -loglevel error -y "$@"; }
v="-f lavfi -i testsrc=size=64x48:rate=10:duration=1"
a="-f lavfi -i sine=frequency=440:sample_rate=8000:duration=1"
x264="-c:v libx264 -preset veryfast -bf 2 -pix_fmt yuv420p"
aac="-c:a aac -b:a 16k -ac 1"
plain="-map_metadata -1 -fflags +bitexact -flags:v +bitexact -flags:a +bitexact"

# H.264 with B-frames (ctts) and AAC
f $v $a $x264 -g 10 $aac $plain h264-aac.mp4
# fragmented: moof/traf/trun per keyframe, a sidx, trex defaults
f $v $a $x264 -g 4 $aac -movflags +frag_keyframe+empty_moov+default_base_moof+global_sidx $plain fragmented.mp4
# MOV cut from 0.45 s without re-encoding: an edit list past a keyframe
f -f lavfi -i testsrc=size=64x48:rate=10:duration=2 -f lavfi -i sine=frequency=440:sample_rate=8000:duration=2 $x264 -g 10 $aac "$tmp/two.mp4"
f -ss 0.45 -i "$tmp/two.mp4" -t 1 -c copy $plain editlist.mov
# HEVC (hvcC)
f $v -c:v libx265 -x265-params log-level=none:bframes=2:keyint=10 -preset ultrafast -tag:v hvc1 -pix_fmt yuv420p $plain hevc.mp4
# a rotation matrix (90 degrees)
f -display_rotation:v 90 -i h264-aac.mp4 -map 0:v -c copy $plain rotated.mp4
# audio codecs' configuration in MP4: Opus (dOps), FLAC (dfLa), ALAC, MP3
s="-f lavfi -i sine=frequency=440:sample_rate=48000:duration=0.2"
f $s $s $s $s -map 0 -map 1 -map 2 -map 3 -c:a:0 libopus -b:a:0 12k -c:a:1 flac -c:a:2 alac -c:a:3 libmp3lame -b:a:3 32k $plain audio.mp4
# VP9 and Opus in WebM (CodecDelay, SeekPreRoll, Cues)
f $v -f lavfi -i sine=frequency=440:sample_rate=48000:duration=1 -c:v libvpx-vp9 -b:v 50k -g 5 -c:a libopus -b:a 12k -ac 1 $plain vp9-opus.webm
# AV1 in WebM
f -f lavfi -i testsrc=size=64x64:rate=10:duration=1 -c:v libsvtav1 -preset 12 -g 10 -svtav1-params loglevel=0 $plain av1.webm 2>/dev/null
# VP9 (vpcC) and AV1 (av1C) in MP4, the latter copied from av1.webm
f $v -c:v libvpx-vp9 -b:v 50k -g 5 $plain vp9.mp4
f -i av1.webm -c copy $plain av1.mp4
# Vorbis and PCM in Matroska, their blocks laced by lace.mjs: Xiph and EBML
# lacing (Vorbis), fixed (PCM)
f -f lavfi -i sine=frequency=440:sample_rate=8000:duration=1 -f lavfi -i sine=frequency=220:sample_rate=8000:duration=1 -map 0 -map 1 -c:a:0 vorbis -strict -2 -ac:a:0 2 -c:a:1 pcm_s16le -frame_size:a:1 256 $plain "$tmp/audio.mkv"
node lace.mjs lace "$tmp/audio.mkv" laced.mkv
# live WebM: the segment and clusters of unknown size, no cues
node lace.mjs live vp9-opus.webm live.webm
node expect.mjs
ls -l *.mp4 *.mov *.webm *.mkv
