#!/bin/sh
# Android's system layers on the device or emulator adb reaches:
# AndroidLayersTest.apk (tests/ui/AndroidLayersTest.hx) run twice, with
# SurfaceControl's layers and with the textured compositor
# (debug.helder.layers=0), its lines from logcat (tag hxmc): the
# compositor's frames while the program is blocked (a fling, an animation,
# this script's swipe), the layers moved, not drawn; screencaps of its two
# stills compared (android-layers.mjs).
#   sh tests/ui/android-layers.sh <AndroidLayersTest.apk> [out dir]
set -u
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
		if adb logcat -d 2>/dev/null | grep -q "Fatal signal\|FATAL EXCEPTION\|dlopen failed\|CANNOT LINK"; then
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
for mode in layers 0; do
	log="$out/layers-$mode.txt"
	adb shell setprop debug.helder.layers "$([ $mode = layers ] && echo 1 || echo 0)"
	adb logcat -c
	adb shell am start -W -n $pkg/android.app.NativeActivity > /dev/null
	wait_for "AndroidLayersTest: swipe now" 120 || { failed=1; continue; }
	adb shell input swipe $((W / 2)) $((H * 80 / 100)) $((W / 2)) $((H * 30 / 100)) 120
	wait_for "AndroidLayersTest: still 1" 120 && adb exec-out screencap -p > "$out/still1-$mode.png"
	wait_for "AndroidLayersTest: still 2" 120 && adb exec-out screencap -p > "$out/still2-$mode.png"
	wait_for "AndroidLayersTest: done" 120
	adb logcat -d -s hxmc:I > "$log"
	grep "AndroidLayersTest" "$log" | sed 's/^.*AndroidLayersTest/AndroidLayersTest/'
	grep -q "AndroidLayersTest: ok$" "$log" || failed=1
	if [ $mode = layers ] && grep -q "frames shown on them 0$" "$log"; then
		echo "android-layers.sh: no frame on the system's layers"
		failed=1
	fi
done
adb shell setprop debug.helder.layers "''"
# (the node's system layer where the layers' run put it)
slot=$(grep -o "slot at [0-9]* [0-9]*" "$out/layers-layers.txt" | head -1 | awk '{print $3","$4}')
node tests/ui/android-layers.mjs "$out/still1-layers.png" "$out/still1-0.png" still1 "$slot,22c060" || failed=1
node tests/ui/android-layers.mjs "$out/still2-layers.png" "$out/still2-0.png" still2 || failed=1
exit $failed
