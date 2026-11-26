#!/bin/sh
# The system's Liquid Glass in a key window, captured for GlassPass's
# active look (macOS 26 on): GlassKindsCheck's bands and kinds shown by
# glass-kinds.swift in a window made key, captured, and compared with
# helder's drawing (the mean levels a kind). It takes the focus for about
# two seconds, so a person runs it, not an agent's lane; the terminal may
# ask for Screen Recording the first time.
#   sh tests/ui/glass-key.sh [out]: out/key.png (the capture), out/side.png
#   and out/<kind>.png (side by side), the numbers printed
# Then GlassPass is tuned from out/key.png with no window shown:
#   bin/glass-key/GlassKindsCheck --tune out/key.png 2 regular|clear ... (GlassKindsCheck.hx)
set -e
cd "$(dirname "$0")/../.."
out=${1:-bin/glass-key}
mkdir -p "$out"
target=$(uname -m | sed 's/x86_64/macos-x86_64/;s/arm64/macos-arm64/')
node_modules/.bin/haxe -D hxmc.markup-braces -cp src -cp tests/gfx -cp tests/ui -main GlassKindsCheck \
	-D hxmc.target="$target" -D helder.os=macos --custom-target hxmc="$out/GlassKindsCheck" > "$out/build.log" 2>&1 \
	|| { cat "$out/build.log"; exit 1; }
swiftc -O tests/ui/glass-kinds.swift -o "$out/glass-kinds"
"$out/GlassKindsCheck" --background "$out" 2
"$out/glass-kinds" "$out/bands.png" "$out/kinds.txt" 2 "$out/key.png" key
"$out/GlassKindsCheck" --compare "$out/key.png" "$out" 2
echo "glass-key: $out/key.png captured; send it (or this folder) back for the tuning"
