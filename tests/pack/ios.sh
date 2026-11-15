#!/bin/sh
# tests/pack/Hello.hx on an iPhone simulator (macOS with Xcode: CI's
# ios-simulator job; not run elsewhere): the apps built first, then on the
# simulator (tests/pack/simulator.sh: HELDER_IOS_SIMULATOR's, else one of
# the newest iOS runtime and iPhone made, booted and deleted at the end)
# `helder run --target ios -d <it>` (built, installed, launched, its output
# followed from the files simctl writes it to until it ends) prints the
# hello line; then the audio stream. IOS_SUITE=smoke stops there (CI's pull
# requests); the full suite (the default; CI's pushes to main and its
# nightly) goes on: the assets, the screen, the planets example,
# UIAccessibility. IOS_BUILD_ONLY=1: the builds alone (CI's build step,
# while the simulator boots), IOS_PREBUILT=1: a build there already kept.
# (The bundles' static checks, codesign --verify and plutil -lint, are the
# pack lane's on a Mac: CI's ios-signing job.)
#   sh tests/pack/ios.sh <helder> [out dir]
set -u
helder=$1
out=$(mkdir -p "${2:-bin/pack/ios}" && cd "${2:-bin/pack/ios}" && pwd)
line="hello from helder on .*: 998001 6 boom"
suite=${IOS_SUITE:-full}
failed=0

check() {
	if [ "$2" = 0 ]; then echo "ios.sh: $1: ok"; else
		echo "ios.sh: $1: FAIL"
		failed=1
	fi
}

# build <entry> <app>: for the simulator, unless built already (IOS_PREBUILT=1)
build() {
	if [ "${IOS_PREBUILT:-}" = 1 ] && [ -d "$2" ]; then return 0; fi
	"$helder" build "$1" --target ios-sim -o "$2"
	check "helder build $1 --target ios-sim" $?
}

# (Hello's, Checksum's and AudioCheck's: helder run builds them again, warm)
build tests/pack/Hello.hx "$out/Hello.app"
build tests/pack/AudioCheck.hx "$out/AudioCheck.app"
if [ "$suite" = full ]; then
	build tests/asset/Checksum.hx "$out/Checksum.app"
	build tests/pack/Screen.hx "$out/Screen.app"
	build examples/planets/Planets.hx "$out/Planets.app"
	build tests/ui/IosAccessCheck.hx "$out/IosAccessCheck.app"
fi
[ -n "${IOS_BUILD_ONLY:-}" ] && exit $failed

. "$(dirname "$0")/simulator.sh"
simulator helder-ios-hello
"$helder" run tests/pack/Hello.hx --target ios -d "$udid" > "$out/run.txt" 2>&1
code=$?
cat "$out/run.txt"
# (the app prints its line and returns: simctl may report the launch as
# failed when it has ended before simctl was done; the line decides)
if [ $code != 0 ] && grep -q "$line" "$out/run.txt"; then
	echo "ios.sh: helder run: exit code $code, but the app ran and printed its line"
	code=0
fi
check "helder run --target ios -d <simulator>" $code
grep -q "$line" "$out/run.txt"
check "its line, from helder run" $?

# Audio (tests/pack/AudioCheck.hx): a RemoteIO output opened (the
# session's category ambient), a tone for two seconds, its line: "audio:
# started" when the device pulled half a second's worth or more.
"$helder" run tests/pack/AudioCheck.hx --target ios -d "$udid" > "$out/audio.txt" 2>&1
code=$?
cat "$out/audio.txt"
if [ $code != 0 ] && grep -q "audio:" "$out/audio.txt"; then code=0; fi
check "helder run tests/pack/AudioCheck.hx --target ios" $code
grep -q "audio: started" "$out/audio.txt"
check "audio: the stream started (RemoteIO's render callbacks)" $?

[ "$suite" = full ] || exit $failed

# The assets (tests/asset/Checksum.hx: helder.asset's files in the app's
# assets/, sealed by CodeResources: the pack lane's codesign on a Mac
# verifies the bundle), `helder run` prints each file's size and CRC-32,
# an image's decoded pixels', the bundle's list: the lines of
# tests/asset/checksum.txt.
"$helder" run tests/asset/Checksum.hx --target ios -d "$udid" > "$out/checksum.txt" 2>&1
code=$?
cat "$out/checksum.txt"
if [ $code != 0 ] && grep -q "pixels crc" "$out/checksum.txt"; then code=0; fi
check "helder run tests/asset/Checksum.hx --target ios" $code
while IFS= read -r l; do
	grep -qF "$l" "$out/checksum.txt"
	check "assets: $l" $?
done < tests/asset/checksum.txt

# The screen (tests/pack/Screen.hx) on the same simulator: launched with
# its output here (--console-pty, in the background: <out dir>/screen.txt),
# its window, safe area and the display's frames, the bars hidden; then the
# Settings app launched over it (the background) and it again (back); its
# lines checked by tests/pack/screen.mjs.
sid=org.helder.Screen
wait_for() {
	i=0
	while [ $i -lt "$2" ] && ! grep -q "$1" "$out/screen.txt"; do
		sleep 1
		i=$((i + 1))
	done
	grep -q "$1" "$out/screen.txt"
	check "screen: $1" $?
}
xcrun simctl install "$udid" "$out/Screen.app"
check "simctl install Screen.app" $?
: > "$out/screen.txt"
xcrun simctl launch --console-pty --terminate-running-process "$udid" $sid > "$out/screen.txt" 2>&1 &
console=$!
wait_for "screen: immersive" 60
sleep 2
xcrun simctl launch "$udid" com.apple.Preferences > /dev/null 2>&1
wait_for "screen: suspend" 20
sleep 2
xcrun simctl launch "$udid" $sid > /dev/null 2>&1
wait_for "first frame after resume" 30
sleep 1
xcrun simctl terminate "$udid" $sid > /dev/null 2>&1
kill $console > /dev/null 2>&1
node tests/pack/screen.mjs "$out/screen.txt" ios
check "the screen's lines (tests/pack/screen.mjs)" $?

# The planets example (examples/planets: ui's markup with a <Scene> in it):
# built for the simulator, launched, its first frames drawn (its line), a
# screenshot kept in <out dir>/planets.png. (helder/little-skies, the game,
# has its own CI.)
gid=org.helder.Planets
xcrun simctl install "$udid" "$out/Planets.app"
check "simctl install Planets.app" $?
: > "$out/planets.txt"
xcrun simctl launch --console-pty --terminate-running-process "$udid" $gid > "$out/planets.txt" 2>&1 &
console=$!
i=0
while [ $i -lt 60 ] && ! grep -q "planets: drawing" "$out/planets.txt"; do
	sleep 1
	i=$((i + 1))
done
tail -20 "$out/planets.txt"
grep -q "planets: drawing" "$out/planets.txt"
check "planets: its first frames" $?
sleep 3
! grep -q "Uncaught exception" "$out/planets.txt"
check "planets: nothing uncaught" $?
xcrun simctl io "$udid" screenshot "$out/planets.png" > /dev/null 2>&1
xcrun simctl terminate "$udid" $gid > /dev/null 2>&1
kill $console > /dev/null 2>&1

# helder.ui's UIAccessibility (tests/ui/IosAccessCheck.hx): the fixture's
# window read as VoiceOver reads it, a button activated, a slider
# incremented; its lines end with "access: N checks, ok".
aid=org.helder.IosAccessCheck
xcrun simctl install "$udid" "$out/IosAccessCheck.app"
check "simctl install IosAccessCheck.app" $?
: > "$out/access.txt"
xcrun simctl launch --console-pty --terminate-running-process "$udid" $aid > "$out/access.txt" 2>&1 &
console=$!
i=0
while [ $i -lt 60 ] && ! grep -q "access: .* checks" "$out/access.txt"; do
	sleep 1
	i=$((i + 1))
done
tail -40 "$out/access.txt"
grep -q "access: .* checks, ok" "$out/access.txt"
check "access: UIAccessibility's elements" $?
xcrun simctl terminate "$udid" $aid > /dev/null 2>&1
kill $console > /dev/null 2>&1
exit $failed
