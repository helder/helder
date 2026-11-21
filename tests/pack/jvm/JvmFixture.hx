import haxe.io.Bytes;
import helder.pack.Zip;
import helder.pack.Zip.ZipEntry;
import helder.pack.android.Libraries;
import helder.pack.android.Maven;
import sys.FileSystem;
import sys.io.File;

// The fixtures as an app's library would be (tests/pack/jvm.sh runs it):
// their class files with kotlin-stdlib (Maven: fetched once into helder's
// cache, offline after), shrunk from fixture.Main.main, translated, written
// as <out>/classes.dex (and classes2.dex... past 65,536 ids); its counts
// and any stub on stdout.
//   JvmFixture <classes dir> <out dir>
class JvmFixture {
	static function main() {
		var args = Sys.args(), dir = args[0], out = args[1];
		var home = Sys.getEnv("HOME") ?? ".";
		var env = Sys.getEnv("HELDER_CACHE");
		var cache = env != null && env != "" ? env : Sys.systemName() == "Mac" ? '$home/Library/Caches/helder' : (Sys.getEnv("XDG_CACHE_HOME") ?? '$home/.cache') + "/helder";
		var maven = new Maven('$cache/maven', curl);
		var deps = maven.resolve("org.jetbrains.kotlin:kotlin-stdlib:1.8.22");
		var entries:Array<ZipEntry> = [];
		function walk(d:String, prefix:String)
			for (f in FileSystem.readDirectory(d)) {
				if (FileSystem.isDirectory('$d/$f')) walk('$d/$f', '$prefix$f/') else if (StringTools.endsWith(f, ".class"))
					entries.push({name: '$prefix$f', data: File.getBytes('$d/$f'), align: 1});
			}
		walk(dir, "");
		var jar = Zip.stored(entries);
		var fixture:MavenArtifact = {group: "fixture", name: "fixture", version: "0", file: "<fixture>", aar: false};
		var t0 = haxe.Timer.stamp();
		var r = Libraries.build([fixture].concat(deps), "-keep class fixture.Main { public static void main(java.lang.String[]); }", "org.helder.jvm",
			f -> f == "<fixture>" ? jar : File.getBytes(f));
		if (!FileSystem.exists(out)) FileSystem.createDirectory(out);
		var size = 0;
		for (k in 0...r.dex.length) {
			File.saveBytes('$out/classes${k == 0 ? "" : Std.string(k + 1)}.dex', r.dex[k]);
			size += r.dex[k].length;
		}
		Sys.println('jvm: ${[for (d in deps) d.name + "-" + d.version].join(", ")}; ${r.classes} classes, ${r.methods} methods, $size bytes in ${r.dex.length} file(s), ${Math.round((haxe.Timer.stamp() - t0) * 1000)} ms');
		for (s in r.stubs)
			Sys.println('jvm: stub $s');
		for (e in r.dex)
			for (err in helder.pack.android.Dex.check(e))
				Sys.println('jvm: check: $err');
	}

	// a URL's bytes (null: 404), by curl
	static function curl(url:String):Null<Bytes> {
		var tmp = Sys.getEnv("TMPDIR") ?? "/tmp";
		var file = '$tmp/jvmfixture.${Std.random(1 << 30)}';
		var p = new sys.io.Process("curl", ["-sSL", "--retry", "3", "-o", file, "-w", "%{http_code}", url]);
		var code = p.stdout.readAll().toString();
		p.exitCode();
		p.close();
		if (code == "404" || code == "403") {
			try FileSystem.deleteFile(file) catch (_:Dynamic) {};
			return null;
		}
		if (code != "200") throw '$url: HTTP $code';
		var b = File.getBytes(file);
		FileSystem.deleteFile(file);
		return b;
	}
}
