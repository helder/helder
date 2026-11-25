#!/bin/sh
# Android's system layers on the device or emulator adb reaches:
# AndroidLayersTest.apk (tests/ui/AndroidLayersTest.hx) run three times:
# with SurfaceControl's layers, with them stalled (debug.helder.layers=
# stall: no transaction reported presented, so that they must fall back
# to the textured compositor while running) and with the textured
# compositor (=0); its lines from logcat (tag hxmc): the compositor's
# frames while the program is blocked (a fling, an animation, this
# script's swipe), the layers moved, not drawn; screencaps of its three
# stills (the last after the header's label changed each frame, drawn
# only where it changed) compared with the textured compositor's
# (android-layers.mjs).
#   sh tests/ui/android-layers.sh <AndroidLayersTest.apk> [out dir]
set -u
. "$(dirname "$0")/../os/android-input.sh"
apk=$1
out=${2:-.}
pkg=org.helder.androidlayerstest
mkdir -p "$out"
failed=0

wait_for() {
	i=0
	while [ $i -lt "$2" ]; do
		adb logcat -d -s hxmc:I > "$log" 2>/dev/null
		grep -q "$1" "$log" && return 0
		# (this app's: another process's crash on the device is not its)
		if adb logcat -d 2>/dev/null | grep -E -A3 "Fatal signal|FATAL EXCEPTION|dlopen failed|CANNOT LINK" | grep -q "$pkg"; then
			echo "android-layers.sh: the app crashed or did not load:"
			adb logcat -d 2>/dev/null | grep -E -A40 "Fatal signal|FATAL EXCEPTION|dlopen failed|CANNOT LINK" | head -80
			return 1
		fi
		sleep 0.25
		i=$((i + 1))
	done
	echo "android-layers.sh: no \"$1\""
	return 1
}

adb wait-for-device
adb install -r -t "$apk" > /dev/null || exit 1
size=$(adb shell wm size | grep -o "[0-9]*x[0-9]*" | tail -1)
W=${size%x*}
H=${size#*x}
for mode in layers stall 0; do
	log="$out/layers-$mode.txt"
	adb shell setprop debug.helder.layers "$([ $mode = layers ] && echo 1 || echo $mode)"
	adb logcat -c
	adb shell am start -W -n $pkg/android.app.NativeActivity > /dev/null
	wait_for "AndroidLayersTest: swipe now" 120 || { failed=1; continue; }
	adb shell input swipe $((W / 2)) $((H * 80 / 100)) $((W / 2)) $((H * 30 / 100)) 120
	wait_for "AndroidLayersTest: still 1" 120 && adb exec-out screencap -p > "$out/still1-$mode.png"
	wait_for "AndroidLayersTest: still 2" 120 && adb exec-out screencap -p > "$out/still2-$mode.png"
	wait_for "AndroidLayersTest: still 3" 120 && adb exec-out screencap -p > "$out/still3-$mode.png"
	wait_for "AndroidLayersTest: done" 120
	adb logcat -d -s hxmc:I > "$log"
	grep "AndroidLayersTest" "$log" | sed 's/^.*AndroidLayersTest/AndroidLayersTest/'
	grep -q "AndroidLayersTest: ok$" "$log" || failed=1
	# (layers: shown on them, else fallen back at run time, as stall must:
	# then the textured compositor's, its pace the device's, a note)
	if [ $mode = layers ] && grep -q "system layers fell back" "$log"; then
		echo "android-layers.sh: note: this device's system layers fell back to the textured compositor"
	elif [ $mode = layers ] && grep -q "frames shown on them 0$" "$log"; then
		echo "android-layers.sh: no frame on the system's layers"
		failed=1
	fi
done
adb shell setprop debug.helder.layers "''"
# (the node's system layer where the layers' run put it; the see-through
# box's colour, in every mode)
slot=$(grep -o "slot at [0-9]* [0-9]*" "$out/layers-layers.txt" | head -1 | awk '{print $3","$4}')
box=$(grep -o "box at [0-9]* [0-9]* [0-9A-F]*" "$out/layers-layers.txt" | head -1 | awk '{print $3","$4","$5}')
node tests/ui/android-layers.mjs "$out/still1-layers.png" "$out/still1-0.png" still1 "$slot,22c060" "$box" || failed=1
node tests/ui/android-layers.mjs "$out/still1-0.png" "$out/still1-layers.png" "still1, textured" "$box" || failed=1
node tests/ui/android-layers.mjs "$out/still2-layers.png" "$out/still2-0.png" still2 || failed=1
# (the header's label changed 120 times, the window's layer drawn only where it changed)
node tests/ui/android-layers.mjs "$out/still3-layers.png" "$out/still3-0.png" still3 || failed=1
# (fallen back: the textured compositor's pixels)
node tests/ui/android-layers.mjs "$out/still1-stall.png" "$out/still1-0.png" "still1, stalled" "$box" || failed=1
exit $failed
