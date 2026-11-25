#!/bin/sh
# helder.os.Folders on the Android device or emulator adb reaches (CI's
# android job): /sdcard/Download/helder-folders pushed (a.txt "hello",
# Sub/b.txt "bye"), tests/os/FoldersCheck.hx's APK installed with its data
# cleared and started: its pick shows the system's picker
# (DocumentsUI's ACTION_OPEN_DOCUMENT_TREE), answered here by taps on what
# uiautomator dumps (Download, helder-folders, Use this folder, Allow); its
# lines from logcat end "folders: ok" (the tree listed, a.txt read,
# Sub/b.txt deleted). Started again: the grant kept from the first launch,
# listed without the picker, then forgotten: "folders: kept ok".
#   sh tests/os/folders-android.sh <FoldersCheck.apk> [out dir]
set -u
apk=$1
out=${2:-.}
mkdir -p "$out"
id=org.helder.folderscheck
failed=0

check() {
	if [ "$2" = 0 ]; then echo "folders-android.sh: $1: ok"; else
		echo "folders-android.sh: $1: FAIL"
		failed=1
	fi
}

# wait_for <line> <log> <half-seconds>: logcat's hxmc lines until one says it
wait_for() {
	i=0
	while [ $i -lt "$3" ]; do
		adb logcat -d -s hxmc:I > "$2" 2>/dev/null
		grep -q "$1" "$2" && return 0
		sleep 0.5
		i=$((i + 1))
	done
	return 1
}

# tap <text>: the screen's element of that text (case aside) tapped at its
# middle, its dump retried while it is not there (the picker still opening)
tap() {
	i=0
	while [ $i -lt 30 ]; do
		adb shell uiautomator dump /sdcard/folders-ui.xml > /dev/null 2>&1
		b=$(adb shell cat /sdcard/folders-ui.xml 2>/dev/null | tr '>' '\n' | grep -i "text=\"$1\"" | grep -o 'bounds="[^"]*"' | head -1 | tr -c '0-9\n' ' ')
		if [ -n "$b" ]; then
			set -- $b
			adb shell input tap $((($1 + $3) / 2)) $((($2 + $4) / 2))
			sleep 1
			return 0
		fi
		sleep 1
		i=$((i + 1))
	done
	echo "folders-android.sh: no \"$1\" on the screen"
	return 1
}

adb wait-for-device
adb shell 'rm -rf /sdcard/Download/helder-folders && mkdir -p /sdcard/Download/helder-folders/Sub &&
	printf hello > /sdcard/Download/helder-folders/a.txt && printf bye > /sdcard/Download/helder-folders/Sub/b.txt'
check "the folder pushed" $?
adb install -r -t "$apk" > /dev/null
check "adb install" $?
adb shell pm clear $id > /dev/null
adb logcat -c
adb shell am start -n $id/android.app.NativeActivity > /dev/null
wait_for "folders: picking" "$out/folders.txt" 60
check "the picker asked for" $?
tap Download && tap helder-folders && tap "Use this folder" && tap Allow
check "the picker answered" $?
wait_for "folders: ok\|folders: failed" "$out/folders.txt" 60
grep "folders:" "$out/folders.txt" | sed 's/^.*folders:/folders:/'
grep -q "folders: ok" "$out/folders.txt"
check "the tree granted, listed, read, a file deleted" $?
adb shell ls /sdcard/Download/helder-folders/Sub/b.txt > /dev/null 2>&1
[ $? != 0 ]
check "Sub/b.txt gone from the storage" $?
adb exec-out screencap -p > "$out/folders.png"

adb shell am force-stop $id
# (the second launch's mark: main runs again whenever the activity is made again)
adb shell touch /sdcard/Download/helder-folders/kept
adb logcat -c
adb shell am start -n $id/android.app.NativeActivity > /dev/null
wait_for "folders: kept ok\|folders: failed\|folders: picking" "$out/folders-kept.txt" 60
grep "folders:" "$out/folders-kept.txt" | sed 's/^.*folders:/folders:/'
grep -q "folders: kept ok" "$out/folders-kept.txt"
check "the grant kept from the last launch, listed, forgotten" $?
adb shell am force-stop $id
exit $failed
