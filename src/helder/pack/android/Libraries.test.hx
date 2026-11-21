package helder.pack.android;

import haxe.io.Bytes;
import helder.pack.Zip;
import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

// A library as an AAR in memory (tests/pack/jvm's classes in its
// classes.jar, a manifest, keep rules, res/values) made part of an APK:
// shrunk to its keep rules, translated, the dex checked; its manifest's
// entries merged (a permission, <queries>, the component code reaches with
// its configChanges, theme and ${applicationId}, the one nothing reaches
// left out, a meta-data's @integer/ value), classes2.dex after Glue's
function tests() {
	final dir = "tests/pack/jvm/classes/fixture";
	final jar = Zip.stored([for (f in FileSystem.readDirectory(dir)) {name: 'fixture/$f', data: File.getBytes('$dir/$f'), align: 1}]);
	final manifest = '<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="fixture">
	<uses-permission android:name="android.permission.INTERNET" />
	<uses-permission android:name="$${applicationId}.OWN" />
	<queries><intent><action android:name="fixture.BIND" /></intent></queries>
	<application>
		<meta-data android:name="fixture.version" android:value="@integer/fixture_version" />
		<activity android:name=".Lambdas" android:exported="false" android:configChanges="keyboard|orientation" android:theme="@android:style/Theme.Translucent.NoTitleBar" />
		<service android:name="fixture.Old" android:exported="false" />
	</application>
</manifest>';
	final values = '<resources><integer name="fixture_version">42</integer><string name="x">y <b>z</b></string></resources>';
	final aar = Zip.stored([
		{name: "classes.jar", data: jar, align: 1},
		{name: "AndroidManifest.xml", data: Bytes.ofString(manifest), align: 1},
		{name: "proguard.txt", data: Bytes.ofString("-keepclassmembers class fixture.Statics { int counter; }"), align: 1},
		{name: "res/values/values.xml", data: Bytes.ofString(values), align: 1}
	]);
	final r = Libraries.build([{group: "fixture", name: "fixture", version: "1", file: "fixture.aar", aar: true}],
		"-keep class fixture.Lambdas { static void run(); }", "org.example.app", f -> aar);

	test("shrunk and translated: a checked dex, no stubs", () -> {
		equals(r.dex.length, 1);
		var listed = [];
		equals(Dex.check(r.dex[0], listed), []);
		equals(r.stubs, []);
		equals(listed.contains("Lfixture/Lambdas; run()V"), true);
		equals(Lambda.exists(listed, m -> StringTools.startsWith(m, "Lfixture/Numbers;")), false);
		equals(listed.contains("Lfixture/Statics; run()V"), false);
	});

	test("the manifest's entries: permissions, queries, the components code reaches, values", () -> {
		equals([for (e in r.manifest) e.name], ["uses-permission", "uses-permission", "queries"]);
		equals(r.manifest[1].attrs[0].string, "org.example.app.OWN");
		equals([for (e in r.application) e.name], ["meta-data", "activity"]);
		var meta = r.application[0], activity = r.application[1];
		equals(Lambda.find(meta.attrs, a -> a.name == "value").value, 42);
		equals(Lambda.find(activity.attrs, a -> a.name == "name").string, "fixture.Lambdas");
		equals(Lambda.find(activity.attrs, a -> a.name == "configChanges").value, 0x90);
		equals(Lambda.find(activity.attrs, a -> a.name == "theme").value, 0x01030010);
		equals(r.warnings.filter(w -> w.indexOf("<service fixture.Old> left out") >= 0).length, 1);
	});

	test("in the APK: classes2.dex after Glue's classes.dex, the entries in its manifest", () -> {
		final d = Bytes.ofHex("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721");
		final key = Apk.debugSigner({d: d, cert: Apk.certificate(d, Bytes.ofHex("01"), new Date(2026, 0, 1, 0, 0, 0), 30)});
		final app:Apk.ApkOptions = {
			id: "org.example.app",
			label: "App",
			versionCode: 1,
			versionName: "1",
			minSdk: 29,
			targetSdk: 36,
			permissions: ["INTERNET"],
			libraries: r
		};
		var apk = Apk.write(Bytes.ofString("so"), "android-arm64", Glue.dex(false, ["Handler"]), false, app, key);
		var es = Zip.read(apk);
		equals([for (e in es) e.name], ["AndroidManifest.xml", "classes.dex", "classes2.dex", "lib/arm64-v8a/libmain.so"]);
		var text = Axml.dump(Zip.entry(apk, "AndroidManifest.xml"));
		equals(text.split("android.permission.INTERNET").length, 2);
		equals(text.indexOf("fixture.Lambdas") > 0 && text.indexOf("org.example.app.OWN") > 0 && text.indexOf("fixture.BIND") > 0, true);
	});
}
