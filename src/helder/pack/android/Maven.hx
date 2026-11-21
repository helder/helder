package helder.pack.android;

import haxe.io.Bytes;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// A library's runtime dependencies from Google's Maven repository and
// Maven Central, resolved as Gradle does: the POMs' compile and runtime
// dependencies (versions from their parents' properties and
// dependencyManagement), Gradle module metadata's constraints raising the
// versions already in the graph, the highest version asked for winning,
// Kotlin's standard libraries aligned to one version (its Gradle plugin's
// rule), then only what the chosen versions reach. Every file (POM,
// .module, AAR or JAR) is checked against its .sha1 and kept in the cache
// (<cache>/<group path>/<name>/<version>/, the repository's layout; a
// missing .module remembered), so a resolved tree needs no network again.
// fetch is the caller's (helder.cli.Android: curl): a URL's bytes, null
// when the repository has no such file.
class Maven {
	public static final REPOSITORIES = ["https://dl.google.com/android/maven2/", "https://repo1.maven.org/maven2/"];

	// the versions of the libraries helder's modules declare without one (Play
	// accepts billing 8.0.0 and later)
	public static inline var BILLING = "9.1.0";
	public static final VERSIONS = ["com.android.billingclient:billing" => BILLING];

	// group:name:version, the version from VERSIONS when not given (null: none known)
	public static function versioned(id:String):Null<String> {
		var parts = id.split(":");
		if (parts.length == 3) return id;
		if (parts.length != 2) return null;
		var v = VERSIONS.get(id);
		return v == null ? null : '$id:$v';
	}

	final cache:String;
	final fetch:String->Null<Bytes>;
	final poms = new Map<String, Xml>();

	public function new(cache:String, fetch:String->Null<Bytes>) {
		this.cache = cache;
		this.fetch = fetch;
	}

	static function path(g:String, a:String, v:String, ext:String):String
		return '${g.split(".").join("/")}/$a/$v/$a-$v.$ext';

	// a repository file: the cache's, else fetched (null: no repository has it)
	public function file(p:String):Null<Bytes> {
		var local = '$cache/$p';
		if (FileSystem.exists(local)) return File.getBytes(local);
		if (FileSystem.exists('$local.missing')) return null;
		for (r in REPOSITORIES) {
			var data = fetch(r + p);
			if (data == null) continue;
			var sum = fetch(r + p + ".sha1");
			if (sum == null) throw '${r + p}: no .sha1 to check it against';
			var want = sum.toString().trim().split(" ")[0].toLowerCase();
			var got = haxe.crypto.Sha1.make(data).toHex();
			if (want != got) throw '${r + p}: SHA-1 $got, not the repository\'s $want';
			mkdirs(haxe.io.Path.directory(local));
			var tmp = local + "." + Std.random(1 << 30);
			File.saveBytes(tmp, data);
			try FileSystem.rename(tmp, local) catch (_:Dynamic) try FileSystem.deleteFile(tmp) catch (_:Dynamic) {};
			return data;
		}
		mkdirs(haxe.io.Path.directory(local));
		File.saveContent('$local.missing', "");
		return null;
	}

	static function mkdirs(d:String) {
		if (d == "" || FileSystem.exists(d)) return;
		mkdirs(haxe.io.Path.directory(d));
		FileSystem.createDirectory(d);
	}

	function pom(g:String, a:String, v:String):Xml {
		var key = '$g:$a:$v';
		var x = poms.get(key);
		if (x != null) return x;
		var b = file(path(g, a, v, "pom"));
		if (b == null) throw 'Maven: no POM for $key';
		x = Xml.parse(b.toString()).firstElement();
		poms.set(key, x);
		return x;
	}

	static function child(x:Xml, name:String):Null<Xml> {
		for (e in x.elementsNamed(name))
			return e;
		return null;
	}

	static function text(x:Null<Xml>, name:String):Null<String> {
		if (x == null) return null;
		var e = child(x, name);
		if (e == null) return null;
		var t = [for (n in e) if (n.nodeType == PCData || n.nodeType == CData) n.nodeValue].join("").trim();
		return t == "" ? null : t;
	}

	// a POM's properties and managed versions, its parents' under them
	function context(g:String, a:String, v:String):{props:Map<String, String>, managed:Map<String, String>} {
		var x = pom(g, a, v), props = new Map<String, String>(), managed = new Map<String, String>();
		var parent = child(x, "parent");
		if (parent != null) {
			var pg = text(parent, "groupId"), pa = text(parent, "artifactId"), pv = text(parent, "version");
			if (pg != null && pa != null && pv != null) {
				var c = try context(pg, pa, pv) catch (_:String) null;
				if (c != null) {
					for (k => val in c.props) props.set(k, val);
					for (k => val in c.managed) managed.set(k, val);
				}
			}
		}
		props.set("project.version", v);
		props.set("pom.version", v);
		props.set("version", v);
		props.set("project.groupId", g);
		var pe = child(x, "properties");
		if (pe != null) for (e in pe.elements())
			props.set(e.nodeName, [for (n in e) if (n.nodeType == PCData || n.nodeType == CData) n.nodeValue].join("").trim());
		var dm = child(x, "dependencyManagement");
		var ds = dm == null ? null : child(dm, "dependencies");
		if (ds != null) for (d in ds.elementsNamed("dependency")) {
			var dg = sub(text(d, "groupId"), props), da = sub(text(d, "artifactId"), props), dv = text(d, "version");
			if (dv != null) managed.set('$dg:$da', sub(dv, props));
		}
		return {props: props, managed: managed};
	}

	static function sub(s:Null<String>, props:Map<String, String>):String {
		if (s == null) return null;
		return ~/\$\{([^}]+)\}/g.map(s, r -> props.get(r.matched(1)) ?? r.matched(0));
	}

	// a version range's lowest bound, a version as it is
	static function clean(v:String):String {
		v = v.trim();
		if (v.startsWith("[") || v.startsWith("(")) v = v.substr(1).split(",")[0].replace("]", "").replace(")", "").trim();
		return v;
	}

	// (Gradle's order: a qualifier past the numbers, alpha or rc, before the release)
	public static function compareVersions(a:String, b:String):Int {
		var x = ~/[.\-]/g.split(a), y = ~/[.\-]/g.split(b);
		inline function release(p:String)
			return ~/^[0-9]+$/.match(p) || p == "final" || p == "ga" || p == "release";
		for (k in 0...(x.length > y.length ? x.length : y.length)) {
			var p = x[k], q = y[k];
			if (p == q) continue;
			if (p == null) return release(q) ? -1 : 1;
			if (q == null) return release(p) ? 1 : -1;
			var pn = Std.parseInt(p), qn = Std.parseInt(q);
			var pi = pn != null && ~/^[0-9]+$/.match(p) ? pn : -1, qi = qn != null && ~/^[0-9]+$/.match(q) ? qn : -1;
			if (pi != qi) return pi < qi ? -1 : 1;
			if (pi < 0) return p < q ? -1 : 1;
		}
		return 0;
	}

	// the runtime dependencies (group, name, version) and the module's constraints
	function dependencies(g:String, a:String, v:String):{deps:Array<{g:String, a:String, v:String}>, constraints:Array<{g:String, a:String, v:String}>, packaging:String} {
		var x = pom(g, a, v), c = context(g, a, v), out = [];
		var ds = child(x, "dependencies");
		if (ds != null) for (d in ds.elementsNamed("dependency")) {
			var scope = text(d, "scope") ?? "compile";
			if (scope != "compile" && scope != "runtime") continue;
			if (text(d, "optional") == "true") continue;
			var dg = sub(text(d, "groupId"), c.props), da = sub(text(d, "artifactId"), c.props);
			var dv = text(d, "version");
			var version = dv != null ? clean(sub(dv, c.props)) : c.managed.get('$dg:$da');
			if (version == null) continue;
			out.push({g: dg, a: da, v: version});
		}
		var constraints = [];
		var m = file(path(g, a, v, "module"));
		if (m != null) {
			var j:Dynamic = try haxe.Json.parse(m.toString()) catch (_:Dynamic) null;
			var variants:Array<Dynamic> = j?.variants ?? [];
			for (va in variants) {
				var cs:Array<Dynamic> = va.dependencyConstraints ?? [];
				for (k in cs) {
					var ver:Dynamic = k.version;
					var cv:String = ver?.strictly ?? ver?.requires;
					if (cv != null) constraints.push({g: (k.group : String), a: (k.module : String), v: clean(cv)});
				}
			}
		}
		return {deps: out, constraints: constraints, packaging: text(x, "packaging") ?? "jar"};
	}

	// the tree of group:name:version, each artifact's file fetched (an AAR, else a JAR)
	public function resolve(id:String):Array<MavenArtifact> {
		var parts = id.split(":");
		if (parts.length != 3) throw 'Maven: $id is not group:name:version';
		var want = new Map<String, String>(), edges = new Map<String, {deps:Array<{g:String, a:String, v:String}>, constraints:Array<{g:String, a:String, v:String}>, packaging:String}>();
		var root = parts[0] + ":" + parts[1];
		want.set(root, parts[2]);
		var constraints = [];
		var changed = true;
		while (changed) {
			changed = false;
			for (ga in [for (k in want.keys()) k]) {
				var v = want.get(ga), key = '$ga:$v';
				if (edges.exists(key)) continue;
				var p = ga.split(":");
				var e = dependencies(p[0], p[1], v);
				edges.set(key, e);
				for (k in e.constraints)
					constraints.push(k);
				for (d in e.deps) {
					var cur = want.get('${d.g}:${d.a}');
					if (cur == null || compareVersions(d.v, cur) > 0) {
						want.set('${d.g}:${d.a}', d.v);
						changed = true;
					}
				}
			}
			for (k in constraints) {
				var cur = want.get('${k.g}:${k.a}');
				if (cur != null && compareVersions(k.v, cur) > 0) {
					want.set('${k.g}:${k.a}', k.v);
					changed = true;
				}
			}
			// (Kotlin's standard libraries at one version: since 1.8 stdlib-jdk7 and -jdk8 are empty)
			var kotlin:Null<String> = null;
			for (ga => v in want)
				if (ga.startsWith("org.jetbrains.kotlin:") && (kotlin == null || compareVersions(v, kotlin) > 0)) kotlin = v;
			for (ga => v in want)
				if (ga.startsWith("org.jetbrains.kotlin:") && v != kotlin) {
					want.set(ga, kotlin);
					changed = true;
				}
		}
		var seen = new Map<String, Bool>(), stack = [root], order = [];
		while (stack.length > 0) {
			var ga = stack.pop();
			if (seen.exists(ga)) continue;
			seen.set(ga, true);
			order.push(ga);
			for (d in edges.get('$ga:${want.get(ga)}').deps)
				stack.push('${d.g}:${d.a}');
		}
		order.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		return [for (ga in order) {
			var p = ga.split(":"), v = want.get(ga), e = edges.get('$ga:$v');
			var exts = e.packaging == "jar" ? ["jar", "aar"] : ["aar", "jar"];
			var found:Null<MavenArtifact> = null;
			for (ext in exts) {
				var f = path(p[0], p[1], v, ext);
				if (file(f) != null) {
					found = {group: p[0], name: p[1], version: v, file: '$cache/$f', aar: ext == "aar"};
					break;
				}
			}
			// (a POM alone: a platform or a relocation)
			if (found == null) continue;
			found;
		}];
	}
}

// a resolved artifact: its file in the cache
typedef MavenArtifact = {group:String, name:String, version:String, file:String, aar:Bool};
