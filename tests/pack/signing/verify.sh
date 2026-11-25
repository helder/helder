#!/bin/sh
# A signed app checked by Apple's own tools, on a Mac (CI's ios-signing job):
# the pack project built for an iPhone and signed by helder
# (helder.pack.apple.CodeSign) with this directory's throwaway identity
# (ca.pem: a test CA; cert.pem and key.pem: its RSA leaf; test.mobileprovision:
# a stand-in App Store profile the CA signed), the CA trusted in the system
# keychain (codesign checks the chain; the runner is thrown away after), then
#   codesign --verify --deep --strict -vvvv   the signature, the sealed files
#   codesign -d --entitlements :-             the entitlements as codesign reads them
#   codesign -d -r-                           the designated requirement
#   xcrun assetutil --info Assets.car         the icon's asset catalog (AssetCatalog)
#   plutil -lint                              Info.plist, PrivacyInfo.xcprivacy
# and tests/store/StoreCheck.hx's app, HelderStore.framework signed inside it.
# Usage: sh tests/pack/signing/verify.sh (from the repository's root, after
# bun install). App Store Connect's own validation is a TestFlight upload
# with the owner's account (src/helder/pack/README.md).
set -eu
out=bin/pack/signing
rm -rf "$out"
mkdir -p "$out"
export PATH="$PWD/node_modules/.bin:$PATH"
node tests/pack/runtime.mjs bin/pack/rt
if [ "$#" -gt 0 ]; then
  helder=$1
else
  node src/helder/cli/run.mjs help > /dev/null
  helder=bin/cli/helder
fi
cp -R tests/pack/project "$out/project"
mkdir -p "$out/project/node_modules/helder"
printf '{"name": "helder", "haxe": {"name": "helder", "classPath": "%s"}}' "$PWD/src" > "$out/project/node_modules/helder"/package.json
HXMC_RT_DIR="$PWD/bin/pack/rt" HELDER_CACHE="$PWD/bin/pack/cache" \
  HELDER_IOS_CERTIFICATE=tests/pack/signing/cert.pem HELDER_IOS_KEY=tests/pack/signing/key.pem \
  HELDER_IOS_PROFILE=tests/pack/signing/test.mobileprovision \
  "$helder" build "$out/project" --target ios --release -o "$out/Packed.ipa"
# (and an app with helder's HelderStore.framework, helder.store's: signed
# by the same identity, nested)
HXMC_RT_DIR="$PWD/bin/pack/rt" HELDER_CACHE="$PWD/bin/pack/cache" \
  HELDER_IOS_CERTIFICATE=tests/pack/signing/cert.pem HELDER_IOS_KEY=tests/pack/signing/key.pem \
  HELDER_IOS_PROFILE=tests/pack/signing/test.mobileprovision \
  "$helder" build tests/store/StoreCheck.hx --target ios --release -o "$out/Store/Store.ipa"
(cd "$out" && unzip -q Packed.ipa && cd Store && unzip -q Store.ipa)
app="$out/Payload/Packed.app"
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain tests/pack/signing/ca.pem
status=0
step() {
  echo "--- $*"
  "$@" || { echo "FAILED: $*"; status=1; }
}
step codesign --verify --deep --strict -vvvv "$app"
step codesign -d --entitlements :- "$app"
step codesign -d -r- "$app"
step codesign -dvvv "$app"
step xcrun assetutil --info "$app/Assets.car"
# (the App Store refuses an icon with alpha: every rendition opaque)
if xcrun assetutil --info "$app/Assets.car" | grep -q '"Opaque" : false'; then echo "FAILED: a rendition not opaque"; status=1; fi
step plutil -lint "$app/Info.plist" "$app/PrivacyInfo.xcprivacy"
store="$out/Store/Payload/Store.app"
step codesign --verify --deep --strict -vvvv "$store"
step sh -c "codesign -dvvv '$store/Frameworks/HelderStore.framework' 2>&1 | grep -q 'TeamIdentifier=HLDRTEST01'"
step plutil -lint "$store/Frameworks/HelderStore.framework/Info.plist"
exit $status
