#!/bin/sh
# The viewer (apps/viewer) on an iPhone simulator (macOS with Xcode: CI's
# ios-simulator job): built for the simulator, installed, the sample
# folder's photos put in its Documents (its place on a phone), launched
# with --exit-after; its phone shell on screen (a screenshot in <out
# dir>/viewer.png), then its line, "viewer: Documents (browsing, N items",
# awaited. The simulator: HELDER_IOS_SIMULATOR's, else one made, booted and
# deleted here (tests/pack/simulator.sh). IOS_BUILD_ONLY=1: the build alone;
# IOS_PREBUILT=1: a build there kept.
#   sh tests/pack/viewer-ios.sh <helder> [out dir]
set -u
helder=$1
out=$(mkdir -p "${2:-bin/pack/ios-viewer}" && cd "${2:-bin/pack/ios-viewer}" && pwd)
app=$out/viewer.app
id=org.helder.viewer
failed=0

check() {
	if [ "$2" = 0 ]; then echo "viewer-ios.sh: $1: ok"; else
		echo "viewer-ios.sh: $1: FAIL"
		failed=1
	fi
}

if [ "${IOS_PREBUILT:-}" != 1 ] || [ ! -e "$app" ]; then
	"$helder" build apps/viewer --target ios-sim -o "$app"
	check "helder build apps/viewer --target ios-sim" $?
fi
[ -n "${IOS_BUILD_ONLY:-}" ] && exit $failed

. "$(dirname "$0")/simulator.sh"
simulator helder-ios-viewer

xcrun simctl install "$udid" "$app"
check "simctl install viewer.app" $?
data=$(xcrun simctl get_app_container "$udid" "$id" data)
mkdir -p "$data/Documents"
cp apps/viewer/samples/*.jpg "$data/Documents/"
xcrun simctl launch --console-pty --terminate-running-process "$udid" "$id" --exit-after 25 > "$out/viewer.txt" 2>&1 &
console=$!
# (its first frames: the phone's shell at the Documents folder, its thumbnails made; a just booted simulator's first launch is slow)
sleep 15
xcrun simctl io "$udid" screenshot "$out/viewer.png" > /dev/null 2>&1
check "a screenshot" $?
i=0
while [ $i -lt 60 ] && ! grep -q -E "^viewer: |Uncaught" "$out/viewer.txt"; do
	sleep 1
	i=$((i + 1))
done
xcrun simctl terminate "$udid" "$id" > /dev/null 2>&1
kill $console > /dev/null 2>&1
grep -E "viewer:|Uncaught|Called from" "$out/viewer.txt"
grep -q "viewer: Documents (browsing, 5 items" "$out/viewer.txt"
check "its Documents browsed" $?
exit $failed
