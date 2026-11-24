#!/bin/sh
# The browser test's own file (MediaWebTest.hx): VP9 in WebM, 4 s in
# clusters of a second each, a keyframe a second: longer than a player's
# read-ahead, so that its first frame needs a part of it (the Range check);
# 128x96, the least Apple's VP9 decoder takes (Firefox's and WebKit's on macOS).
#   sh tests/media/web/fixtures.sh   (from the repository's root)
set -e
cd "$(dirname "$0")"
ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc=size=128x96:rate=10:duration=4 -c:v libvpx-vp9 -pix_fmt yuv420p -b:v 30k -g 10 \
	-cluster_time_limit 1000 -map_metadata -1 -fflags +bitexact -flags:v +bitexact long.webm
ls -l long.webm
