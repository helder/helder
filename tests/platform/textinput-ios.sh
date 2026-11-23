#!/bin/sh
# tests/platform/TextInputCheck.hx on an iPhone simulator (macOS with
# Xcode: CI's ios-simulator job): built for the simulator, launched with
# its output in <out dir>/TextInputCheck.txt under Xcode's Main Thread
# Checker (a UIKit call off the main thread reported on its output), its
# "textinput: N checks, ok" awaited; then no report of the checker, and no
# UIKit assertion in the process's log of a layout or a layer changed off
# the main thread (Core Animation's commits elsewhere: helder.os.OsThread).
# A screenshot of its keyboard in <out dir>. The simulator:
# HELDER_IOS_SIMULATOR's, else one made, booted and deleted here
# (tests/pack/simulator.sh). IOS_BUILD_ONLY=1: the build alone;
# IOS_PREBUILT=1: a build there kept.
#   sh tests/platform/textinput-ios.sh <helder> [out dir]
set -u
helder=$1
out=$(mkdir -p "${2:-bin/pack/ios-textinput}" && cd "${2:-bin/pack/ios-textinput}" && pwd)
app=$out/TextInputCheck.app
id=org.helder.TextInputCheck
failed=0

check() {
	if [ "$2" = 0 ]; then echo "textinput-ios.sh: $1: ok"; else
		echo "textinput-ios.sh: $1: FAIL"
		failed=1
	fi
}

if [ "${IOS_PREBUILT:-}" != 1 ] || [ ! -e "$app" ]; then
	"$helder" build tests/platform/TextInputCheck.hx --target ios-sim -o "$app"
	check "helder build tests/platform/TextInputCheck.hx --target ios-sim" $?
fi
[ -n "${IOS_BUILD_ONLY:-}" ] && exit $failed

. "$(dirname "$0")/../pack/simulator.sh"
simulator helder-ios-textinput

xcrun simctl install "$udid" "$app"
check "simctl install TextInputCheck.app" $?
checker=$(xcode-select -p)/usr/lib/libMainThreadChecker.dylib
[ -f "$checker" ] || checker=
[ -n "$checker" ] || echo "textinput-ios.sh: no Main Thread Checker in $(xcode-select -p)"
since=$(date '+%Y-%m-%d %H:%M:%S')
launch() {
	SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=$checker xcrun simctl launch --console-pty --terminate-running-process "$udid" "$id" > "$out/TextInputCheck.txt" 2>&1 &
	console=$!
}
launch
# (nothing within 30 s, as a first launch on a just booted simulator may: once more)
i=0
while [ $i -lt 30 ] && ! grep -q "textinput:" "$out/TextInputCheck.txt"; do
	sleep 1
	i=$((i + 1))
done
if ! grep -q "textinput:" "$out/TextInputCheck.txt"; then
	echo "textinput-ios.sh: no output; launched again"
	kill $console > /dev/null 2>&1
	launch
fi
i=0
while [ $i -lt 120 ] && ! grep -q -E "textinput: [0-9]+ checks|Uncaught" "$out/TextInputCheck.txt"; do
	sleep 1
	i=$((i + 1))
done
xcrun simctl io "$udid" screenshot "$out/TextInputCheck.png" > /dev/null 2>&1
xcrun simctl terminate "$udid" "$id" > /dev/null 2>&1
kill $console > /dev/null 2>&1
grep -E "textinput:|Uncaught|Called from" "$out/TextInputCheck.txt"
grep -q "textinput: [0-9]* checks, ok" "$out/TextInputCheck.txt"
check "its checks" $?
n=$(grep -c "Main Thread Checker" "$out/TextInputCheck.txt")
[ -z "$checker" ] || grep -A20 "Main Thread Checker" "$out/TextInputCheck.txt" | head -60
[ "$n" = 0 ]
check "no UIKit call off the main thread (Main Thread Checker: $n)" $?
xcrun simctl spawn "$udid" log show --start "$since" --style compact --predicate 'process == "TextInputCheck" AND (eventMessage CONTAINS "off the main thread" OR eventMessage CONTAINS "from a background thread")' > "$out/log.txt" 2>&1
n=$(grep -c "TextInputCheck\[" "$out/log.txt")
grep "TextInputCheck\[" "$out/log.txt" | head -10
[ "$n" = 0 ]
check "no UIKit layout off the main thread (its log: $n)" $?
exit $failed
