#!/bin/sh
# AudioOutputCheck (AudioOutputCheck.hx) through each back end's real API, without
# speakers. Linux: ALSA's null device, then its file plugin (the samples
# ALSA was given, checked exactly; paced at the clock by helder). macOS: the "file:" device (CoreAudio's
# generic output unit, rendered at the clock's pace), then the default
# output when the machine has one (exit 3: none). Windows (AudioOutputCheck.exe):
# WASAPI on the default endpoint when the machine has one (exit 3: none);
# on Linux under Wine (WINE, by default /usr/lib/wine/wine64), whose WASAPI
# plays through winealsa to an ALSA default made the file plugin: what
# reaches ALSA is checked (Wine's mixer adds silence before it). The rate
# of the callbacks (--rate) is checked where something paces them: a device,
# CoreAudio's renderer, helder's ALSA file output; not ALSA's null sink,
# which takes samples as fast as they come, nor Wine's mixer over ALSA's.
#   sh tests/os/audio.sh <dir with AudioOutputCheck> [out dir]
set -e
bin=$1
out=$(cd "${2:-$1}" && pwd)
frames=96000
# a device the machine may not have: exit 3 is a skip
maybe() {
	code=0
	"$@" || code=$?
	if [ $code = 3 ]; then
		echo "audio.sh: no output device: skipped"
		return 0
	fi
	return $code
}
if [ -f "$bin/AudioOutputCheck.exe" ]; then
	case "$(uname -s)" in
	MINGW* | MSYS* | CYGWIN*)
		maybe "$bin/AudioOutputCheck.exe" default $frames --rate
		;;
	*)
		# (a prefix and an ALSA configuration of our own)
		home="$out/wine-home"
		mkdir -p "$home"
		cat > "$home/.asoundrc" <<-EOF
			pcm.!default {
				type file
				slave.pcm "null"
				file "$out/wine.raw"
				format "raw"
			}
		EOF
		rm -f "$out/wine.raw"
		wine=${WINE:-/usr/lib/wine/wine64}
		HOME="$home" WINEPREFIX="$home/prefix" WINEDEBUG=-all "$wine" "$bin/AudioOutputCheck.exe" default $frames --expect "Z:$out/wine.raw"
		HOME="$home" WINEPREFIX="$home/prefix" "$(dirname "$wine")/wineserver" -w || true
		rm -rf "$home" "$out/wine.raw"
		;;
	esac
	exit 0
fi
if [ "$(uname -s)" = Darwin ]; then
	"$bin/AudioOutputCheck" "file:$out/coreaudio.raw" $frames --rate --expect "$out/coreaudio.raw"
	rm -f "$out/coreaudio.raw"
	maybe "$bin/AudioOutputCheck" default $frames --rate
	exit 0
fi
"$bin/AudioOutputCheck" null $frames
"$bin/AudioOutputCheck" "file:$out/alsa.raw" $frames --rate --expect "$out/alsa.raw"
rm -f "$out/alsa.raw"
