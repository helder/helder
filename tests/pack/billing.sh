#!/bin/sh
# Google Play Billing through helder's Maven libraries on the Android
# device or emulator adb reaches (CI's android job): tests/pack/billing/
# BillingCheck.hx (helder.store.Purchases) built for its ABI (billing
# 9.1.0 and its tree fetched once into helder's cache, shrunk and
# translated: the build's "libraries" line, the dex's size), the merged
# manifest's billing permission and queries checked, installed, every class
# verified ahead of time (pm compile -m verify: dex2oat's verifier on all
# of classes2.dex), then started: products() and owned() answered (a list,
# or a short error: BILLING_UNAVAILABLE without the Play Store), available()
# false when billing answered BILLING_UNAVAILABLE, and no VerifyError,
# ClassNotFoundException, NoClassDefFoundError, AbstractMethodError or
# NoSuchMethodError in logcat.
#   sh tests/pack/billing.sh <helder> [out dir]
set -u
helder=$1
out=$(mkdir -p "${2:-bin/pack/android-billing}" && cd "${2:-bin/pack/android-billing}" && pwd)
id=org.helder.billingcheck
failed=0

check() {
	if [ "$2" = 0 ]; then echo "billing.sh: $1: ok"; else
		echo "billing.sh: $1: FAIL"
		failed=1
	fi
}

adb wait-for-device
case $(adb shell getprop ro.product.cpu.abi | tr -d '\r') in
	x86_64) target=android-x86_64 ;;
	*) target=android-arm64 ;;
esac
"$helder" build tests/pack/billing/BillingCheck.hx --target $target -o "$out/BillingCheck.apk" > "$out/build.txt" 2>&1
check "helder build tests/pack/billing/BillingCheck.hx --target $target" $?
cat "$out/build.txt"
unzip -p "$out/BillingCheck.apk" AndroidManifest.xml | LC_ALL=C tr -d '\000' > "$out/manifest.txt"
grep -q "com.android.vending.BILLING" "$out/manifest.txt" && grep -q "com.android.vending.billing.InAppBillingService.BIND" "$out/manifest.txt"
check "the manifest's billing permission and queries" $?

adb uninstall $id > /dev/null 2>&1
adb install -r "$out/BillingCheck.apk"
check "adb install" $?
adb logcat -c
adb shell pm compile -m verify -f $id
adb logcat -d > "$out/verify.txt"
! grep -E "dex2oat.*(failed to verify|Verification error)" "$out/verify.txt"
check "dex2oat verifies every class" $?

adb logcat -c
adb shell am start -W -n $id/android.app.NativeActivity
check "am start" $?
i=0
while [ $i -lt 60 ] && ! adb logcat -d -s hxmc:I | grep -q "billing: done\|billing: no callback"; do
	sleep 1
	i=$((i + 1))
done
adb logcat -d > "$out/logcat.txt"
grep "hxmc" "$out/logcat.txt" | tail -20
grep -qE "billing: products ([0-9]+|failed purchases: [A-Z_]+)" "$out/logcat.txt" && grep -qE "billing: owned ([0-9]+|failed purchases: [A-Z_]+)" "$out/logcat.txt"
check "products and owned answered" $?
! { grep -q "failed purchases: BILLING_UNAVAILABLE" "$out/logcat.txt" && grep "billing: available" "$out/logcat.txt" | tail -1 | grep -q true; }
check "available() false after BILLING_UNAVAILABLE" $?
grep -q "billing: fixtures ok" "$out/logcat.txt"
check "the library's products and purchases read, params built, a signature verified" $?
grep -q "billing: done" "$out/logcat.txt"
check "the check ended" $?
! grep -E "VerifyError|ClassNotFoundException|NoClassDefFoundError|AbstractMethodError|NoSuchMethodError|Fatal signal|FATAL EXCEPTION" "$out/logcat.txt"
check "no missing or unverified class" $?
adb shell am force-stop $id
exit $failed
