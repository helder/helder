# Source this before using adb to inject input into the selected device.
if [ "${GITHUB_ACTIONS:-}" != true ] && [ "${HELDER_TEST_INPUT:-}" != 1 ]; then
	echo "$0: Android input needs CI or HELDER_TEST_INPUT=1" >&2
	exit 2
fi
