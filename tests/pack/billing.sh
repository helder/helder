#!/bin/sh
# Google Play Billing through helder's Maven libraries on the Android
# device or emulator adb reaches (CI's android job): tests/pack/billing/
# BillingCheck.hx built for its ABI (billing 9.1.0 and its tree fetched
# once into helder's cache, shrunk and translated: the build's "libraries"
# line, the dex's size), installed, every class verified ahead of time
# (pm compile -m verify: dex2oat's verifier on all of classes2.dex), then
# started: a BillingClient built, startConnection, its listener's callback
# (BILLING_UNAVAILABLE or SERVICE_UNAVAILABLE without the Play Store, OK
# with an account), and no VerifyError, ClassNotFoundException,
# NoClassDefFoundError, AbstractMethodError or NoSuchMethodError in logcat.
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
grep -qE "billing: (onBillingSetupFinished -?[0-9]+|onBillingServiceDisconnected)" "$out/logcat.txt"
check "startConnection's callback" $?
! grep -E "VerifyError|ClassNotFoundException|NoClassDefFoundError|AbstractMethodError|NoSuchMethodError|Fatal signal|FATAL EXCEPTION" "$out/logcat.txt"
check "no missing or unverified class" $?
adb shell am force-stop $id
exit $failed
