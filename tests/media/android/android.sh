#!/bin/sh
# helder.media on the Android device or emulator adb reaches (CI's android
# job): MediaAndroidCheck.apk (MediaCodec's decoding against ffmpeg's, the
# player, A/V sync; its lines from logcat, tag hxmc), then VideoStillCheck.apk
# three times, drawn by helder, on its system layer (setprop
# debug.helder.video layer) and with that layer asked for once paused
# (late), each still's screencap checked by still.mjs as it was shown.
#   sh tests/media/android/android.sh <MediaAndroidCheck.apk> <VideoStillCheck.apk> [out dir]
set -u
out=${3:-.}
mkdir -p "$out"
failed=0

wait_for() {
	i=0
	while [ $i -lt "$3" ]; do
		adb logcat -d -s hxmc:I > "$2" 2>/dev/null
		grep -q "$1" "$2" && return 0
		if adb logcat -d 2>/dev/null | grep -E -A3 "Fatal signal|FATAL EXCEPTION|dlopen failed|CANNOT LINK" | grep -q "org.helder"; then
			echo "android.sh: the app crashed or did not load:"
			adb logcat -d 2>/dev/null | grep -E -A40 "Fatal signal|FATAL EXCEPTION|dlopen failed|CANNOT LINK" | head -60
			return 1
		fi
		sleep 0.5
		i=$((i + 1))
	done
	echo "android.sh: no \"$1\""
	return 1
}

adb wait-for-device
adb install -r -t "$1" > /dev/null || exit 1
adb logcat -c
adb shell am start -W -n org.helder.mediaandroidtest/android.app.NativeActivity > /dev/null
wait_for "MediaAndroidCheck: passed\|MediaAndroidCheck: [0-9]* failed" "$out/decode.txt" 240 || failed=1
grep "MediaAndroidCheck" "$out/decode.txt" | sed 's/^.*MediaAndroidCheck/MediaAndroidCheck/'
grep -q "MediaAndroidCheck: passed" "$out/decode.txt" || failed=1
adb shell am force-stop org.helder.mediaandroidtest

adb install -r -t "$2" > /dev/null || exit 1
for mode in drawn layer late; do
	adb shell setprop debug.helder.video $mode
	adb logcat -c
	adb shell am start -W -n org.helder.videostill/android.app.NativeActivity > /dev/null
	log="$out/still-$mode.txt"
	wait_for "VideoStillCheck: still" "$log" 120 || { failed=1; continue; }
	adb exec-out screencap -p > "$out/still-$mode.png"
	grep "VideoStillCheck" "$log" | sed 's/^.*VideoStillCheck/VideoStillCheck/'
	box=$(grep -o "box at [0-9]* [0-9]* [0-9]* [0-9]*" "$log" | head -1 | awk '{print $3","$4","$5","$6}')
	# (which way the still was shown, said at it: the layer's check where
	# the system layer showed it, else helder's drawing, the fallback's)
	if grep "box at" "$log" | grep -q "on the system layer true"; then
		node tests/media/android/still.mjs "$out/still-$mode.png" "$box" "$mode, on the system layer" 16 || failed=1
	else
		[ $mode != drawn ] && echo "android.sh: note: no system layer showed it here (Android before 14, its layers off or not split): drawn, checked so"
		node tests/media/android/still.mjs "$out/still-$mode.png" "$box" "$mode, drawn" 8 || failed=1
	fi
	adb shell am force-stop org.helder.videostill
done
# (quoted for the device's shell: an empty value)
adb shell "setprop debug.helder.video ''"
exit $failed
