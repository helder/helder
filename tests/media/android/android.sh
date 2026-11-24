#!/bin/sh
# helder.media on the Android device or emulator adb reaches (CI's android
# job): MediaAndroidTest.apk (MediaCodec's decoding against ffmpeg's, the
# player, A/V sync; its lines from logcat, tag hxmc), then VideoStill.apk
# twice, drawn by helder and on its system layer (setprop
# debug.helder.video layer), each still's screencap checked by still.mjs.
#   sh tests/media/android/android.sh <MediaAndroidTest.apk> <VideoStill.apk> [out dir]
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
wait_for "MediaAndroidTest: passed\|MediaAndroidTest: [0-9]* failed" "$out/decode.txt" 240 || failed=1
grep "MediaAndroidTest" "$out/decode.txt" | sed 's/^.*MediaAndroidTest/MediaAndroidTest/'
grep -q "MediaAndroidTest: passed" "$out/decode.txt" || failed=1
adb shell am force-stop org.helder.mediaandroidtest

adb install -r -t "$2" > /dev/null || exit 1
for mode in drawn layer; do
	adb shell setprop debug.helder.video $mode
	adb logcat -c
	adb shell am start -W -n org.helder.videostill/android.app.NativeActivity > /dev/null
	log="$out/still-$mode.txt"
	wait_for "VideoStill: still" "$log" 120 || { failed=1; continue; }
	adb exec-out screencap -p > "$out/still-$mode.png"
	grep "VideoStill" "$log" | sed 's/^.*VideoStill/VideoStill/'
	box=$(grep -o "box at [0-9]* [0-9]* [0-9]* [0-9]*" "$log" | head -1 | awk '{print $3","$4","$5","$6}')
	node tests/media/android/still.mjs "$out/still-$mode.png" "$box" "$mode" "$([ $mode = layer ] && echo 16 || echo 8)" || failed=1
	# (the layer's run on it, where the system layers run; else drawn, said)
	if [ $mode = layer ] && ! grep -q "on the system layer true" "$log"; then
		echo "android.sh: note: no system layer here (Android before 14, or its layers off): drawn"
	fi
	adb shell am force-stop org.helder.videostill
done
adb shell setprop debug.helder.video "''"
exit $failed
