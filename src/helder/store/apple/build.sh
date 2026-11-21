#!/bin/sh
# HelderStore, StoreShim.swift as a dynamic library, the binary of
# HelderStore.framework (helder.pack.apple.Frameworks writes the bundle
# around it and signs it): ios-arm64, ios-sim-arm64 and macos (arm64 and
# x86_64 in one), iOS 15 and macOS 12 at least, -Osize, local symbols and
# debug info left out, the Swift back-deployment libraries linked in,
# signed ad hoc by the linker. Then StoreShim.sha256, the source's hash,
# which the test lane checks (src/helder/store/Purchases.test.hx).
# Needs Xcode; the same Xcode gives the same bytes.
#   sh src/helder/store/apple/build.sh
set -e
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
build() { # sdk target out
  xcrun --sdk $1 swiftc -parse-as-library -swift-version 5 -Osize -wmo -module-name HelderStore \
    -target $2 -emit-library -o $3 StoreShim.swift -file-prefix-map "$PWD=." \
    -Xlinker -install_name -Xlinker @rpath/HelderStore.framework/HelderStore \
    -Xlinker -dead_strip -Xlinker -exported_symbol -Xlinker "_hsk_*" -Xlinker -x -Xlinker -S -Xlinker -adhoc_codesign
}
mkdir -p ios-arm64 ios-sim-arm64 macos
build iphoneos arm64-apple-ios15.0 ios-arm64/HelderStore
build iphonesimulator arm64-apple-ios15.0-simulator ios-sim-arm64/HelderStore
build macosx arm64-apple-macos12.0 "$tmp/arm64"
build macosx x86_64-apple-macos12.0 "$tmp/x86_64"
lipo -create "$tmp/arm64" "$tmp/x86_64" -output macos/HelderStore
tr -d '\r' < StoreShim.swift | shasum -a 256 | cut -d' ' -f1 > StoreShim.sha256
ls -l ios-arm64/HelderStore ios-sim-arm64/HelderStore macos/HelderStore
