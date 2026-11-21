package helder.pack.android;

import haxe.io.Bytes;
import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

// Maven's resolution against a repository in memory: POM dependencies
// (compile and runtime, not test or optional), a parent's properties and
// dependencyManagement, the highest version asked for winning, Gradle
// module metadata's constraints, Kotlin's libraries aligned, an AAR found
// before a JAR; each file checked by its .sha1 and cached, so a second
// resolve needs no repository (bin/test/maven)
function tests() {
	final dir = "bin/test/maven";
	final repo = Maven.REPOSITORIES[0];
	final files = new Map<String, Bytes>();
	function pom(g:String, a:String, v:String, deps:String, ?extra:String) {
		var p = '${g.split(".").join("/")}/$a/$v/$a-$v';
		var text = '<project xmlns="http://maven.apache.org/POM/4.0.0"><groupId>$g</groupId><artifactId>$a</artifactId><version>$v</version>${extra ?? ""}<dependencies>$deps</dependencies></project>';
		files.set(repo + p + ".pom", Bytes.ofString(text));
		files.set(repo + p + ".jar", Bytes.ofString('$a $v'));
	}
	function dep(g:String, a:String, v:Null<String>, ?scope:String)
		return '<dependency><groupId>$g</groupId><artifactId>$a</artifactId>${v == null ? "" : "<version>" + v + "</version>"}${scope == null ? "" : "<scope>" + scope + "</scope>"}</dependency>';
	pom("org.app", "root", "1.0", dep("org.lib", "a", "1.0") + dep("org.lib", "b", "1.0") + dep("org.test", "t", "1.0", "test") + dep("org.lib", "m", null),
		'<parent><groupId>org.app</groupId><artifactId>parent</artifactId><version>3</version></parent>');
	files.set(repo + "org/app/parent/3/parent-3.pom", Bytes.ofString('<project><properties><libv>2.0</libv></properties><dependencyManagement><dependencies>${dep("org.lib", "m", "${libv}")}</dependencies></dependencyManagement></project>'));
	pom("org.lib", "a", "1.0", dep("org.lib", "c", "1.0") + dep("org.jetbrains.kotlin", "kotlin-stdlib", "1.8.0"));
	pom("org.lib", "b", "1.0", dep("org.lib", "c", "2.0") + dep("org.jetbrains.kotlin", "kotlin-stdlib-jdk8", "1.6.0"));
	pom("org.lib", "c", "1.0", "");
	pom("org.lib", "c", "2.0", "");
	pom("org.lib", "m", "2.0", "");
	pom("org.jetbrains.kotlin", "kotlin-stdlib", "1.8.0", "");
	pom("org.jetbrains.kotlin", "kotlin-stdlib-jdk8", "1.6.0", dep("org.jetbrains.kotlin", "kotlin-stdlib", "1.6.0"));
	pom("org.jetbrains.kotlin", "kotlin-stdlib-jdk8", "1.8.0", dep("org.jetbrains.kotlin", "kotlin-stdlib", "1.8.0"));
	var fetched = 0;
	function fetch(url:String):Null<Bytes> {
		fetched++;
		if (StringTools.endsWith(url, ".sha1")) {
			var f = files.get(url.substr(0, url.length - 5));
			return f == null ? null : Bytes.ofString(haxe.crypto.Sha1.make(f).toHex());
		}
		return files.get(url);
	}

	test("versions compared as Maven's numbers", () -> {
		equals(Maven.compareVersions("1.10.0", "1.9.2") > 0, true);
		equals(Maven.compareVersions("2.0", "2.0.0") < 0, true);
		equals(Maven.compareVersions("1.0-alpha01", "1.0") < 0, true);
		equals(Maven.compareVersions("1.1.0-rc01", "1.0.2") > 0, true);
		equals(Maven.versioned("com.android.billingclient:billing"), "com.android.billingclient:billing:" + Maven.BILLING);
	});

	test("the tree: highest versions, a parent's managed one, Kotlin aligned, test scope out", () -> {
		Runner.rmrf(dir);
		var m = new Maven(dir, fetch);
		var ids = [for (a in m.resolve("org.app:root:1.0")) a.group + ":" + a.name + ":" + a.version];
		equals(ids, [
			"org.app:root:1.0", "org.jetbrains.kotlin:kotlin-stdlib:1.8.0", "org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.8.0", "org.lib:a:1.0", "org.lib:b:1.0",
			"org.lib:c:2.0", "org.lib:m:2.0"
		]);
	});

	test("cached: offline the second time", () -> {
		var m = new Maven(dir, url -> throw 'fetched $url');
		equals(m.resolve("org.app:root:1.0").length, 7);
		equals(File.getContent('$dir/org/lib/c/2.0/c-2.0.jar'), "c 2.0");
	});

	test("a file whose SHA-1 is not the repository's is refused", () -> {
		Runner.rmrf(dir);
		var m = new Maven(dir, url -> StringTools.endsWith(url, ".sha1") ? Bytes.ofString("0000") : fetch(url));
		var error = try {
			m.resolve("org.lib:c:1.0");
			"";
		} catch (e:String) e;
		equals(error.indexOf("SHA-1") > 0, true);
		equals(FileSystem.exists('$dir/org/lib/c/1.0/c-1.0.pom'), false);
	});
}

private class Runner {
	public static function rmrf(d:String) {
		if (!FileSystem.exists(d)) return;
		if (!FileSystem.isDirectory(d)) {
			FileSystem.deleteFile(d);
			return;
		}
		for (f in FileSystem.readDirectory(d))
			rmrf('$d/$f');
		FileSystem.deleteDirectory(d);
	}
}
