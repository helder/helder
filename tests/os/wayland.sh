#!/bin/sh
# The wayland lane's runs under a headless weston (pixman, its own runtime
# directory), at scale 1 and 2: tests/os/WaylandTest.hx, then the viewer
# on Wayland (a photo shown, --exit-after) with a screenshot of the
# compositor's output (weston-screenshooter: the viewer's drawn menu bar,
# helder's decorations).
# Then, given, the compositor's scrolling in a window (AsyncScrollWindow),
# and a layer's animation while the program blocks (its --anim); a window
# drawn on the CPU (SoftWaylandTest: wl_shm frames, the screenshot's pixels).
#   wayland.sh <WaylandTest> <viewer> <out dir> [AsyncScrollWindow] [SoftWaylandTest]
set -e
test=$1; viewer=$2; out=$3; async=$4; soft=$5
mkdir -p "$out"
export XDG_RUNTIME_DIR=$(mktemp -d)
export LIBGL_ALWAYS_SOFTWARE=1
status=0
for scale in 1 2; do
	sock=helder-wl-$scale
	weston --backend=headless --renderer=pixman --socket=$sock --width=1280 --height=860 --scale=$scale --debug > "$out/weston-$scale.log" 2>&1 &
	w=$!
	i=0
	while [ ! -S "$XDG_RUNTIME_DIR/$sock" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
	WAYLAND_DISPLAY=$sock "$test" $scale || status=1
	if [ -n "$soft" ]; then
		WAYLAND_DISPLAY=$sock "$soft" || status=1
	fi
	if [ -n "$async" ] && [ $scale = 1 ]; then
		WAYLAND_DISPLAY=$sock "$async" || status=1
		WAYLAND_DISPLAY=$sock "$async" --anim || status=1
	fi
	if [ $scale = 1 ]; then
		HOME=$(mktemp -d) WAYLAND_DISPLAY=$sock "$viewer" --new --exit-after 5 "apps/viewer/tests/fixtures/folder/photo 2.jpg" > "$out/wayland-viewer.txt" 2>&1 &
		v=$!
		sleep 3
		(cd "$out" && rm -f wayland-screenshot-*.png && WAYLAND_DISPLAY=$sock timeout 10 weston-screenshooter > /dev/null 2>&1 && mv wayland-screenshot-*.png wayland-viewer.png) || echo "wayland.sh: no screenshot"
		wait $v || status=1
		cat "$out/wayland-viewer.txt"
		grep -q "viewer: photo 2.jpg · 5 / 6 · 1242×1048 (shown" "$out/wayland-viewer.txt" || { echo "wayland.sh: the viewer did not show the photo on Wayland"; status=1; }
	fi
	kill $w 2> /dev/null || true
	wait $w 2> /dev/null || true
done
rm -rf "$XDG_RUNTIME_DIR"
exit $status
