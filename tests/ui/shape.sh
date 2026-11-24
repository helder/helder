#!/bin/sh
# A transparent window on Linux (tests/ui/ShapeWindow.hx): under Xvfb with
# no compositing manager (opaque, as said), with xcompmgr where installed,
# and under a headless weston whose background is green (its screenshot).
#   shape.sh <ShapeWindow>
set -e
exe=$1
export LIBGL_ALWAYS_SOFTWARE=1
export XDG_RUNTIME_DIR=$(mktemp -d)
status=0
d=:$((90 + $$ % 900))
Xvfb $d -screen 0 1024x768x24 -nolisten tcp > /dev/null 2>&1 &
x=$!
i=0
while [ ! -e /tmp/.X11-unix/X${d#:} ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
DISPLAY=$d HELDER_X11=1 timeout 60 "$exe" --transparent no || status=1
if command -v xcompmgr > /dev/null; then
	DISPLAY=$d xcompmgr > /dev/null 2>&1 &
	c=$!
	sleep 0.5
	DISPLAY=$d HELDER_X11=1 timeout 60 "$exe" || status=1
	kill $c 2> /dev/null || true
else
	echo "shape.sh: no xcompmgr here: X11's transparent window not run"
fi
kill $x 2> /dev/null || true
if command -v weston > /dev/null; then
	printf '[shell]\nbackground-color=0xff00ff00\npanel-position=none\nstartup-animation=none\nanimation=none\n' > "$XDG_RUNTIME_DIR/weston.ini"
	weston --config="$XDG_RUNTIME_DIR/weston.ini" --backend=headless --renderer=pixman --socket=shape --width=800 --height=600 --debug > "$XDG_RUNTIME_DIR/weston.log" 2>&1 &
	w=$!
	i=0
	while [ ! -S "$XDG_RUNTIME_DIR/shape" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
	WAYLAND_DISPLAY=shape timeout 60 "$exe" || status=1
	kill $w 2> /dev/null || true
	wait $w 2> /dev/null || true
fi
rm -rf "$XDG_RUNTIME_DIR"
exit $status
