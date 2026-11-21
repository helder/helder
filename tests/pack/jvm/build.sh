#!/bin/sh
# The fixtures' class files, compiled once and committed (a JDK only here:
# helder and CI never need one): Java 11 (nests, indy concatenation,
# private interface methods), then Old and KotlinUse again for Java 8;
# expected.txt is what a JVM prints. KOTLIN_STDLIB: kotlin-stdlib-1.8.22.jar
# (helder's Maven cache has it after `helder build` of tests/pack/jvm).
#   JAVA_HOME=<jdk 11+> KOTLIN_STDLIB=<jar> sh tests/pack/jvm/build.sh
set -e
cd "$(dirname "$0")"
J=${JAVA_HOME:?JAVA_HOME}/bin
rm -rf classes && mkdir classes
"$J/javac" -encoding UTF-8 --release 11 -cp "$KOTLIN_STDLIB" -d classes src/fixture/*.java
"$J/javac" -encoding UTF-8 --release 8 -cp "classes:$KOTLIN_STDLIB" -d classes src/fixture/Old.java src/fixture/KotlinUse.java
"$J/java" -cp "classes:$KOTLIN_STDLIB" fixture.Main > expected.txt
cat expected.txt
