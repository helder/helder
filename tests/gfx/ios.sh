#!/bin/sh
# IosTest.app (IosTest.hx) on an iPhone simulator (macOS with Xcode; CI's
# ios-simulator job): on HELDER_IOS_SIMULATOR's simulator, else one of the
# newest iOS runtime and iPhone made and booted (tests/pack/simulator.sh),
# installs the app and launches it with its stdout and stderr in files
# (what the app prints: its lines), then:
#   - the cube rendered headless on the simulator's Metal matches cube.png
#     (GfxTest's rule); the window has a size, and its frame is lit;
#   - 120 frames drawn in the window;
#   - a tap on the Simulator's window (SimTap: a click posted as an HID
#     event, the simulator's touch) comes back as a touch's PointerDown and
#     PointerUp, without mouse events or scrolls; (IOS_SUITE=full, the
#     default: CI's pushes to main and its nightly) a drag held on the cube
#     (SimTap's drag, resting before the lift) turns it with the finger,
#     still while the finger rests, turning again once let go; a fling
#     (SimTap's quick drag) flicks it on at the drag's speed; never a mouse
#     event or a scroll (a touch is its pointer's alone);
#   - a screenshot (simctl io) to <out>/cube-ios.png;
#   - (full) another app (Settings) sends it to the background (Suspend),
#     launching it again brings it back (Resume) and frames go on;
#   - (full, or a failure) the system log of the app's process to
#     <out>/log.txt; a simulator made here is deleted at the end.
# (The bundle's static checks, codesign --verify and plutil -lint, are the
# pack lane's on a Mac, CI's ios-signing job, on bundles built alike.)
#   sh tests/gfx/ios.sh <IosTest.app> [out dir] [SimTap]
set -u
app=$1
out=$(mkdir -p "${2:-.}" && cd "${2:-.}" && pwd)
tap=${3:-}
suite=${IOS_SUITE:-full}
id=org.helder.IosTest
stdout="$out/stdout.txt"
failed=0

check() {
	if [ "$2" = 0 ]; then echo "ios.sh: $1: ok"; else
		echo "ios.sh: $1: FAIL"
		failed=1
	fi
}

# wait_for <pattern> <seconds>: until the app's stdout has a line matching it
wait_for() {
	i=0
	while [ $i -lt "$2" ]; do
		grep -q "$1" "$stdout" 2>/dev/null && return 0
		if grep -q "Uncaught exception\|hxmc: " "$out/stderr.txt" 2>/dev/null; then
			echo "ios.sh: the app failed:"
			cat "$out/stderr.txt"
			return 1
		fi
		sleep 1
		i=$((i + 1))
	done
	echo "ios.sh: no \"$1\" in $2 s"
	return 1
}

. "$(dirname "$0")/../pack/simulator.sh"
simulator hxmc-ios-test
# (the Simulator app's window: what SimTap clicks)
open -a Simulator --args -CurrentDeviceUDID "$udid"
xcrun simctl install "$udid" "$app"
check "install" $?
rm -f "$stdout" "$out/stderr.txt"
xcrun simctl launch --terminate-running-process --stdout="$stdout" --stderr="$out/stderr.txt" "$udid" $id
check "launch" $?
wait_for "IosTest: frames 120" 120
check "120 frames in the window" $?
grep -q "GfxTest: cube, ios headless: ok" "$stdout"
check "the headless cube matches cube.png" $?
grep -q "IosTest: window [1-9][0-9]*x[1-9]" "$stdout"
check "the window has a size" $?
grep -q "IosTest: window frame .*: lit" "$stdout"
check "the window's frame is lit" $?
xcrun simctl io "$udid" screenshot "$out/cube-ios.png"
check "screenshot" $?
if [ -n "$tap" ]; then
	# (the Simulator app frontmost before the first click: a click on an app
	# that is not takes it to the front and goes no further, so the first tap
	# was lost whenever another app had the focus: lsappinfo's front app,
	# which needs no accessibility permission)
	open -a Simulator
	i=0
	while [ $i -lt 100 ] && ! lsappinfo info -only name "$(lsappinfo front)" 2>/dev/null | grep -q '"Simulator"'; do
		sleep 0.2
		i=$((i + 1))
	done
	lsappinfo info -only name "$(lsappinfo front)" 2>/dev/null | grep -q '"Simulator"'
	check "the Simulator app in front (for SimTap's clicks)" $?
	"$tap"
	wait_for "event PointerUp [0-9]* touch" 20
	check "a tap: a touch's PointerDown and PointerUp" $?
	grep -q "event PointerDown [0-9]* touch .* primary" "$stdout"
	check "the tap: its PointerDown, the primary pointer" $?
	! grep -q "event MouseDown\|event MouseUp\|event Scroll" "$stdout"
	check "the tap: no mouse events, no scrolls (a touch is its pointer's alone)" $?
fi
if [ -n "$tap" ] && [ "$suite" = full ]; then
	# a drag held on the cube (SimTap's drag sideways, a quarter of the
	# screen, resting 4 s before the lift): the cube turned by the finger's
	# pointer, held still while it rests, turning again once let go; then a
	# fling (a quick drag sideways): flicked on at the drag's speed after
	# the lift. No scrolls, no mouse events: the pointers alone.
	angle() {
		grep -o "IosTest: spin $1 angle -*[0-9]*" "$stdout" | tail -1 | grep -o -- "-*[0-9]*$"
	}
	ups=$(grep -c "event PointerUp" "$stdout")
	before=$(angle free)
	"$tap" 0.3 0.55 0.55 0.55 4 &
	sleep 2
	held1=$(angle held)
	sleep 1
	held2=$(angle held)
	wait
	echo "ios.sh: before $before, held: angle $held1, then $held2"
	grep -q "event PointerMove [0-9]* touch" "$stdout"
	check "a drag: the finger's PointerMoves" $?
	[ -n "$held1" ] && [ "$held1" = "$held2" ]
	check "the cube held still under the resting finger" $?
	[ -n "$before" ] && [ -n "$held1" ] && [ $((held1 - before)) -ge 400 ]
	check "the cube turned with the finger (a quarter of the screen: about 785 mrad)" $?
	sleep 1
	[ "$(grep -c "event PointerUp" "$stdout")" -gt "$ups" ]
	check "let go: its PointerUp" $?
	free1=$(angle free)
	sleep 2
	free2=$(angle free)
	echo "ios.sh: let go: angle $free1, then $free2"
	[ -n "$free1" ] && [ "$free1" != "$free2" ]
	check "the cube turning again once let go" $?
	# (the fling: the speed the cube was let go at, logged at the lift, not
	# sampled from a later spin line (a frame pacing's 20 frames of decay
	# after it); against the drag's speed as the app received it: the
	# simulator delivers SimTap's moves at its own pace, a drag posted over
	# 0.1 s arriving over 0.3 to 0.7 s, so its speed is the drag's, not a
	# number fixed here. Let go at half the drag's speed or more (Spin's
	# smoothing), and at twice the cube's own 600 or more: a flick, not its
	# own turn nor a release from rest)
	lines=$(wc -l < "$stdout")
	"$tap" 0.3 0.55 0.7 0.55
	i=0
	while [ $i -lt 20 ] && ! tail -n +$((lines + 1)) "$stdout" | grep -q "IosTest: released speed"; do
		sleep 0.5
		i=$((i + 1))
	done
	released=$(tail -n +$((lines + 1)) "$stdout" | grep -o "IosTest: released speed .*" | tail -1)
	echo "ios.sh: the fling: ${released:-no release logged}"
	flick=$(echo "$released" | sed -n 's/^IosTest: released speed \(-*[0-9]*\) drag \(-*[0-9]*\) .*/\1/p')
	drag=$(echo "$released" | sed -n 's/^IosTest: released speed \(-*[0-9]*\) drag \(-*[0-9]*\) .*/\2/p')
	[ -n "$flick" ] && [ -n "$drag" ] && [ "$flick" -ge 1200 ] && [ $((flick * 2)) -ge "$drag" ]
	check "a fling carries the cube on at the drag's speed (let go at $flick mrad/s, the drag $drag)" $?
	! grep -q "event MouseDown\|event MouseUp\|event Scroll" "$stdout"
	check "the drags: no mouse events, no scrolls" $?
fi
if [ "$suite" = full ]; then
	xcrun simctl launch "$udid" com.apple.Preferences > /dev/null
	wait_for "event Suspend" 30
	check "another app: Suspend" $?
	xcrun simctl launch "$udid" $id > /dev/null
	wait_for "event Resume" 30
	check "back again: Resume" $?
	frames=$(grep -o "frames [0-9]*" "$stdout" | tail -1 | cut -d' ' -f2)
	wait_for "IosTest: frames $((frames + 60))" 60
	check "frames after Resume" $?
fi
# (the system log: a minute and more on a runner, so on a failure and in the full suite)
if [ $failed != 0 ] || [ "$suite" = full ]; then
	xcrun simctl spawn "$udid" log show --last 10m --style compact --predicate 'process == "IosTest"' > "$out/log.txt" 2>&1
fi
xcrun simctl terminate "$udid" $id
cat "$stdout"
exit $failed
