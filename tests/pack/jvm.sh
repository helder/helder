#!/bin/sh
# The JVM fixtures (tests/pack/jvm: Java 11 and Java 8 classes calling
# kotlin-stdlib's) on the Android device or emulator adb reaches (CI's
# android job): translated to dex by tests/pack/jvm/JvmFixture.hx on Haxe's
# interpreter (haxe --run: no host program to build, nor the host's
# runtime objects; kotlin-stdlib from Maven, fetched once into helder's
# cache; shrunk from fixture.Main.main), run by dalvikvm, its output against
# tests/pack/jvm/expected.txt (a JVM's); then every class verified
# (dex2oat's verify filter): no stub, no check failure, no verifier error.
#   sh tests/pack/jvm.sh [out dir]
# (HAXE: the compiler, else node_modules/.bin's, bun install's)
set -u
haxe=${HAXE:-node_modules/.bin/haxe}
out=$(mkdir -p "${1:-bin/pack/android-jvm}" && cd "${1:-bin/pack/android-jvm}" && pwd)
failed=0

check() {
	if [ "$2" = 0 ]; then echo "jvm.sh: $1: ok"; else
		echo "jvm.sh: $1: FAIL"
		failed=1
	fi
}

rm -rf "$out/dex"
"$haxe" -cp src -cp tests/pack/jvm --run JvmFixture tests/pack/jvm/classes "$out/dex" > "$out/jvm.txt" 2>&1
check "the fixtures translated (haxe --run JvmFixture)" $?
cat "$out/jvm.txt"
grep -q "^jvm: .* classes" "$out/jvm.txt" && ! grep -q "jvm: stub\|jvm: check" "$out/jvm.txt"
check "no stubs, the files checked" $?

adb wait-for-device
cp=""
for f in "$out"/dex/classes*.dex; do
	n=$(basename "$f")
	adb push "$f" "/data/local/tmp/jvm-$n" > /dev/null
	cp="$cp${cp:+:}/data/local/tmp/jvm-$n"
done
adb logcat -c
adb shell dalvikvm -cp "$cp" fixture.Main > "$out/fixture.txt" 2>&1
tr -d '\r' < "$out/fixture.txt" > "$out/fixture.out"
diff tests/pack/jvm/expected.txt "$out/fixture.out"
check "dalvikvm's output is the JVM's" $?
# (every class, not only those the run loads: dex2oat's verify filter)
case $(adb shell getprop ro.product.cpu.abi | tr -d '\r') in
	x86_64) isa=x86_64 ;;
	*) isa=arm64 ;;
esac
for f in $(echo "$cp" | tr ':' ' '); do
	adb shell "/apex/com.android.art/bin/dex2oat64 --dex-file=$f --oat-file=/data/local/tmp/jvm-fixture.oat --compiler-filter=verify --instruction-set=$isa" >> "$out/dex2oat.txt" 2>&1
done
adb logcat -d > "$out/logcat.txt"
! grep -iE "VerifyError|Verification failed|Verification error|failed to verify|Rejecting class" "$out/logcat.txt" "$out/dex2oat.txt"
check "no verifier error" $?
exit $failed
