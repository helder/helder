#!/bin/sh
# The viewer (apps/viewer) on the device or emulator adb reaches (CI's
# android job): built for its ABI, installed, started; still running
# after its first frames (no crash in logcat), its phone shell on screen
# (a screenshot in <out dir>/viewer.png).
#   sh tests/pack/viewer-android.sh <helder> [out dir]
set -u
helder=$1
out=${2:-bin/pack/android-viewer}
mkdir -p "$out"
id=org.helder.viewer
failed=0

check() {
	if [ "$2" = 0 ]; then echo "viewer-android.sh: $1: ok"; else
		echo "viewer-android.sh: $1: FAIL"
		failed=1
	fi
}

adb wait-for-device
abi=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')
target=android-arm64
[ "$abi" = x86_64 ] && target=android-x86_64
"$helder" build apps/viewer --target "$target" -o "$out/viewer.apk"
check "helder build apps/viewer --target $target" $?
adb logcat -c
adb install -r "$out/viewer.apk"
check "install viewer.apk" $?
adb shell am start -W -n "$id/android.app.NativeActivity"
check "started" $?
sleep 10
adb exec-out screencap -p > "$out/viewer.png"
check "a screenshot" $?
adb logcat -d > "$out/logcat.txt" 2>/dev/null
# (the app's own: the system's services log their own dlopen failures)
crash="Fatal signal.*($id|viewer)|Process: $id|dlopen failed.*viewer|CANNOT LINK.*viewer"
if grep -q -E "$crash" "$out/logcat.txt"; then
	grep -E -A40 "$crash" "$out/logcat.txt" | head -80
	check "no crash" 1
else
	check "no crash" 0
fi
[ -n "$(adb shell pidof "$id" | tr -d '\r')" ]
check "still running" $?
adb shell am force-stop "$id"
exit $failed
