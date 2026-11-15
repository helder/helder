#!/bin/sh
# The iPhone simulator the iOS device scripts run on (tests/pack/ios.sh,
# tests/gfx/ios.sh, tests/platform/webview-ios.sh; macOS with Xcode).
#
# CI's ios-simulator job makes one at its start and boots it in the
# background while it builds, gives its UDID to all three scripts
# (HELDER_IOS_SIMULATOR) and deletes it at its end: a simulator's first boot
# on a fresh runner is minutes (the runtime's caches made), the scripts'
# own simulators each paid it.
#   sh tests/pack/simulator.sh create [name]   its UDID printed, booting in the background
#   sh tests/pack/simulator.sh delete <udid>   shut down and deleted
#
# Sourced by a script (after its check function), `simulator <name>` sets
# udid: HELDER_IOS_SIMULATOR's, waited for until booted; without it one of
# the newest iOS runtime and iPhone made and booted for the script alone,
# deleted when it exits (each script runs on its own as before).
#   . tests/pack/simulator.sh; simulator helder-ios-hello

# a simulator of the newest iOS runtime and iPhone made: its UDID
simulator_create() {
	runtime=$(xcrun simctl list runtimes available | grep -o 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*' | sort -t- -k2,2n -k3,3n | tail -1)
	type=$(xcrun simctl list devicetypes | grep -o 'com\.apple\.CoreSimulator\.SimDeviceType\.iPhone-[0-9][0-9]*)' | tr -d ')' | sort -t- -k2,2n | tail -1)
	echo "simulator: $type on $runtime" >&2
	xcrun simctl create "$1" "$type" "$runtime"
}

simulator_delete() {
	xcrun simctl shutdown "$1" > /dev/null 2>&1
	xcrun simctl delete "$1" > /dev/null 2>&1
}

simulator() {
	if [ -n "${HELDER_IOS_SIMULATOR:-}" ]; then
		udid=$HELDER_IOS_SIMULATOR
		t0=$(date +%s)
		# (bootstatus -b: boots it if it is not, waits while it boots)
		xcrun simctl bootstatus "$udid" -b > /dev/null 2>&1
		check "the shared simulator $udid booted (waited $(($(date +%s) - t0)) s)" $?
		return
	fi
	udid=$(simulator_create "$1")
	check "a simulator made" $?
	trap 'simulator_delete "$udid"' EXIT
	t0=$(date +%s)
	xcrun simctl boot "$udid"
	xcrun simctl bootstatus "$udid" -b > /dev/null 2>&1
	check "booted ($(($(date +%s) - t0)) s)" $?
}

# (run, not sourced: $0 is this file)
if [ "$(basename "$0")" = simulator.sh ]; then
	set -u
	case "${1:-}" in
	create)
		udid=$(simulator_create "${2:-helder-ios}") || exit 1
		# (the boot left to run while the job builds: CoreSimulator's service
		# boots it, simctl boot only asks; bootstatus -b waits for the end)
		log="${TMPDIR:-/tmp}/helder-simulator-$udid.log"
		nohup sh -c 'xcrun simctl boot "$1"; xcrun simctl bootstatus "$1" -b' sh "$udid" > "$log" 2>&1 &
		echo "$udid"
		;;
	delete)
		simulator_delete "$2"
		;;
	*)
		echo "sh tests/pack/simulator.sh create [name] | delete <udid>" >&2
		exit 2
		;;
	esac
fi
