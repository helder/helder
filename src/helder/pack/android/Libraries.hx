package helder.pack.android;

import haxe.io.Bytes;
import helder.pack.Zip;
import helder.pack.android.Axml;
import helder.pack.android.ClassFile;
import helder.pack.android.Dex;
import helder.pack.android.Maven.MavenArtifact;

using StringTools;

// Maven libraries made part of an app: their classes (an AAR's classes.jar
// and libs/*.jar, a JAR's own) shrunk to what the app reaches (Shrink: the
// keep rules given, the libraries' proguard.txt and META-INF rules, Keep's
// defaults; a manifest component the code reaches is the framework's to
// make, so its constructor and overrides are kept, and a class its
// meta-data names), translated (Jvm) and
// written as dex files (more than one past Dex.LIMIT's ids: the APK's
// classes2.dex and on), and their manifests' entries merged into the
// app's: permissions, <queries> and the application's meta-data of each
// library the app uses (a class of it kept), its activities, services,
// receivers and providers that code reaches (the others left out, as
// androidx.startup's provider and profileinstaller's receiver are for
// billing: warnings name them), ${applicationId} replaced, resource values
// (@integer/, @string/, @bool/ of the AAR's res/values) written as the
// values themselves, the framework's styles by their ids. A library's
// resources and Java resources (non-class files of its JARs) are not
// packaged: billing's paths need none.
class Libraries {
	public static function build(artifacts:Array<MavenArtifact>, keep:String, pkg:String, read:String->Bytes):LibraryResult {
		var world = new Map<String, ClassFile>(), origin = new Map<String, String>();
		var rules = new StringBuf(), warnings = [];
		var parts = [];
		rules.add(Keep.DEFAULTS);
		rules.add("\n");
		rules.add(keep);
		for (a in artifacts) {
			var id = '${a.group}:${a.name}:${a.version}';
			var p = unpack(read(a.file), a.aar);
			parts.push({id: id, p: p});
			rules.add("\n");
			rules.add(p.rules);
			for (jar in p.jars)
				for (e in Zip.read(jar)) {
					if (!e.name.endsWith(".class") || e.name.startsWith("META-INF/") || e.name.endsWith("module-info.class")) continue;
					var c = try ClassFile.read(e.data) catch (err:String) {
						warnings.push('$id: ${e.name}: $err');
						continue;
					};
					if (world.exists(c.name)) continue;
					world.set(c.name, c);
					origin.set(c.name, id);
				}
		}
		var shrink = new Shrink(world, Keep.parse(rules.toString()));
		shrink.run();
		// the libraries in use: their components kept, until no other comes in
		var manifests = [for (x in parts) if (x.p.manifest != null) {id: x.id, xml: try Xml.parse(x.p.manifest).firstElement() catch (_:Dynamic) null, values: values(x.p.values)}];
		manifests = manifests.filter(m -> m.xml != null);
		var used = new Map<String, Bool>(), components = new Map<String, Bool>();
		var changed = true;
		while (changed) {
			changed = false;
			for (n in world.keys())
				if (shrink.keepsClass(n) && !used.exists(origin.get(n))) {
					used.set(origin.get(n), true);
					changed = true;
				}
			for (m in manifests) {
				if (!used.exists(m.id)) continue;
				var app = child(m.xml, "application");
				if (app == null) continue;
				for (e in app.elements()) {
					var name = className(e.get("android:name"), m.xml.get("package"));
					if (COMPONENTS.indexOf(e.nodeName) < 0 || name == null || !shrink.keepsClass(name.split(".").join("/"))) continue;
					if (!components.exists(name)) {
						components.set(name, true);
						changed = true;
					}
					shrink.component(name.split(".").join("/"));
					// (a meta-data naming a class, as datatransport's backends: name or value)
					for (md in e.elementsNamed("meta-data"))
						for (v in [md.get("android:name"), md.get("android:value")])
							if (v != null) {
								var cn = v.indexOf(":") >= 0 ? v.substr(v.indexOf(":") + 1) : v;
								if (world.exists(cn.split(".").join("/"))) shrink.component(cn.split(".").join("/"));
							}
				}
			}
		}
		// translated, then split into files
		var jvm = new Jvm(n -> world.get(n));
		var kept = shrink.classes();
		kept.sort((a, b) -> a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
		for (c in kept)
			jvm.prepare(c);
		var classes = [];
		for (c in kept)
			for (d in jvm.translate(c, m -> shrink.keepsMethod(c, m), f -> shrink.keepsField(c, f)))
				classes.push(d);
		var dex = [for (files in Dex.split(classes)) Dex.write(files)];
		// the manifests' entries
		var top:Array<Element> = [], application:Array<Element> = [], queries:Array<Element> = [], seen = new Map<String, Bool>();
		for (m in manifests) {
			if (!used.exists(m.id)) continue;
			var conv = new Converter(pkg, m.values, warnings, m.id);
			for (e in m.xml.elements())
				switch e.nodeName {
					case "uses-permission" | "uses-permission-sdk-23" | "permission":
						var key = e.nodeName + ":" + conv.text(e.get("android:name"));
						if (seen.exists(key)) continue;
						seen.set(key, true);
						top.push(conv.element(e));
					case "queries":
						for (q in e.elements()) {
							var x = conv.element(q), key = "q:" + Std.string(x);
							if (seen.exists(key)) continue;
							seen.set(key, true);
							queries.push(x);
						}
					case "application":
						for (c in e.elements()) {
							var name = className(c.get("android:name"), m.xml.get("package"));
							if (COMPONENTS.indexOf(c.nodeName) >= 0 && (name == null || !shrink.keepsClass(name.split(".").join("/")))) {
								warnings.push('${m.id}: <${c.nodeName} $name> left out: no code reaches it');
								continue;
							}
							if (c.nodeName != "meta-data" && COMPONENTS.indexOf(c.nodeName) < 0) continue;
							var key = c.nodeName + ":" + name;
							if (seen.exists(key)) continue;
							seen.set(key, true);
							if (name != null && c.nodeName != "meta-data") c.set("android:name", name);
							application.push(conv.element(c));
						}
					case _:
				}
		}
		if (queries.length > 0) top.push(Axml.el("queries", [], queries));
		var n = shrink.count();
		return {
			dex: dex,
			manifest: top,
			application: application,
			stubs: jvm.stubs,
			warnings: warnings,
			classes: classes.length,
			methods: n.methods,
			used: [for (k in used.keys()) k]
		};
	}

	static final COMPONENTS = ["activity", "activity-alias", "service", "receiver", "provider"];

	// a component's class name (a library's relative ".Name" from its package)
	static function className(name:Null<String>, pkg:Null<String>):Null<String> {
		if (name == null) return null;
		if (name.startsWith(".") && pkg != null) return pkg + name;
		return name;
	}

	static function child(x:Xml, name:String):Null<Xml> {
		for (e in x.elementsNamed(name))
			return e;
		return null;
	}

	// an AAR's or JAR's parts: its class JARs, manifest, keep rules, res/values
	public static function unpack(b:Bytes, aar:Bool):{jars:Array<Bytes>, manifest:Null<String>, rules:String, values:Null<String>} {
		var entries = Zip.read(b);
		var jars = [], manifest = null, rules = new StringBuf(), values = null;
		function jarRules(jar:Bytes) {
			var r8 = [], pg = [];
			for (e in Zip.read(jar)) {
				if (e.name.startsWith("META-INF/com.android.tools/r8/") || e.name.startsWith("META-INF/com.android.tools/r8-from-")) r8.push(e.data.toString());
				else if (e.name.startsWith("META-INF/proguard/")) pg.push(e.data.toString());
			}
			for (t in (r8.length > 0 ? r8 : pg)) {
				rules.add(t);
				rules.add("\n");
			}
		}
		if (!aar) {
			jars.push(b);
			jarRules(b);
		} else
			for (e in entries) {
				if (e.name == "classes.jar" || (e.name.startsWith("libs/") && e.name.endsWith(".jar"))) {
					jars.push(e.data);
					jarRules(e.data);
				} else if (e.name == "AndroidManifest.xml") manifest = e.data.toString() else if (e.name == "proguard.txt") {
					rules.add(e.data.toString());
					rules.add("\n");
				} else if (e.name == "res/values/values.xml") values = e.data.toString();
			}
		return {jars: jars, manifest: manifest, rules: rules.toString(), values: values};
	}

	// res/values' integers, strings and booleans by "type/name"
	static function values(text:Null<String>):Map<String, String> {
		var out = new Map<String, String>();
		if (text == null) return out;
		var x = try Xml.parse(text).firstElement() catch (_:Dynamic) null;
		if (x == null) return out;
		for (e in x.elements())
			if (["integer", "string", "bool"].indexOf(e.nodeName) >= 0) out.set(e.nodeName + "/" + e.get("name"), [for (n in e) if (n.nodeType == PCData || n.nodeType == CData) n.nodeValue].join("").trim());
		return out;
	}
}

typedef LibraryResult = {
	// classes.dex's followers (classes2.dex, ...)
	dex:Array<Bytes>,
	// the manifest's own entries (uses-permission, permission, queries), the application's
	manifest:Array<Element>,
	application:Array<Element>,
	stubs:Array<String>,
	warnings:Array<String>,
	classes:Int,
	methods:Int,
	used:Array<String>
};

// a library manifest's element as binary XML's
private class Converter {
	final pkg:String;
	final values:Map<String, String>;
	final warnings:Array<String>;
	final id:String;

	public function new(pkg:String, values:Map<String, String>, warnings:Array<String>, id:String) {
		this.pkg = pkg;
		this.values = values;
		this.warnings = warnings;
		this.id = id;
	}

	public function text(s:Null<String>):String
		return s == null ? "" : s.replace("${applicationId}", pkg);

	static final BOOLS = [
		"exported", "enabled", "directBootAware", "grantUriPermissions", "multiprocess", "stopWithTask", "isolatedProcess", "excludeFromRecents",
		"noHistory", "required", "syncable", "visibleToInstantApps"
	];
	static final INTS = ["minSdkVersion", "maxSdkVersion", "priority", "initOrder"];
	static final CONFIG = [
		"mcc" => 0x1, "mnc" => 0x2, "locale" => 0x4, "touchscreen" => 0x8, "keyboard" => 0x10, "keyboardHidden" => 0x20, "navigation" => 0x40,
		"orientation" => 0x80, "screenLayout" => 0x100, "uiMode" => 0x200, "screenSize" => 0x400, "smallestScreenSize" => 0x800, "density" => 0x1000,
		"layoutDirection" => 0x2000, "colorMode" => 0x4000, "grammaticalGender" => 0x8000, "fontWeightAdjustment" => 0x10000000,
		"fontScale" => 0x40000000
	];
	static final PROTECTION = [
		"normal" => 0, "dangerous" => 1, "signature" => 2, "signatureOrSystem" => 3, "privileged" => 0x10, "system" => 0x10, "development" => 0x20,
		"appop" => 0x40, "pre23" => 0x80, "installer" => 0x100, "verifier" => 0x200, "preinstalled" => 0x400, "setup" => 0x800
	];
	static final SERVICE_TYPES = [
		"dataSync" => 0x1, "mediaPlayback" => 0x2, "phoneCall" => 0x4, "location" => 0x8, "connectedDevice" => 0x10, "mediaProjection" => 0x20,
		"camera" => 0x40, "microphone" => 0x80, "health" => 0x100, "remoteMessaging" => 0x200, "systemExempted" => 0x400, "shortService" => 0x800,
		"specialUse" => 0x40000000
	];
	static final STYLES = [
		"Theme.Translucent" => 0x0103000f, "Theme.Translucent.NoTitleBar" => 0x01030010, "Theme.Translucent.NoTitleBar.Fullscreen" => 0x01030011,
		"Theme.NoDisplay" => 0x01030055, "Theme.Dialog" => 0x0103000b, "Theme.DeviceDefault.Dialog" => 0x0103012e
	];
	static function flags(table:Map<String, Int>, s:String):Null<Int> {
		var v = 0;
		for (p in s.split("|")) {
			var f = table.get(p.trim());
			if (f == null) return null;
			v |= f;
		}
		return v;
	}

	public function element(x:Xml):Element {
		var attrs:Array<Attr> = [];
		for (a in x.attributes()) {
			if (!a.startsWith("android:")) continue;
			var name = a.substr(8), raw = text(x.get(a));
			if (!Axml.IDS.exists(name)) {
				warnings.push('$id: android:$name of <${x.nodeName}> dropped');
				continue;
			}
			if (raw.startsWith("@")) {
				var ref = raw.substr(1);
				if (ref.startsWith("android:style/") && STYLES.exists(ref.substr(14))) {
					attrs.push({android: true, name: name, type: Axml.REFERENCE, value: STYLES.get(ref.substr(14))});
					continue;
				}
				var v = values.get(ref);
				if (v == null) {
					warnings.push('$id: android:$name="$raw" of <${x.nodeName}> dropped (no such value)');
					continue;
				}
				if (ref.startsWith("integer/")) attrs.push({android: true, name: name, type: Axml.INT_DEC, value: Std.parseInt(v)}) else if (ref.startsWith("bool/"))
					attrs.push({android: true, name: name, type: Axml.BOOLEAN, value: v == "true" ? -1 : 0}) else
					attrs.push({android: true, name: name, type: Axml.STRING, string: v});
				continue;
			}
			var typed:Null<Attr> = if (BOOLS.indexOf(name) >= 0) {android: true, name: name, type: Axml.BOOLEAN, value: raw == "true" ? -1 : 0} else
				if (INTS.indexOf(name) >= 0) {android: true, name: name, type: Axml.INT_DEC, value: Std.parseInt(raw)} else switch name {
				case "configChanges": var f = flags(CONFIG, raw); f == null ? null : {android: true, name: name, type: Axml.INT_HEX, value: f};
				case "protectionLevel": var f = flags(PROTECTION, raw); f == null ? null : {android: true, name: name, type: Axml.INT_HEX, value: f};
				case "foregroundServiceType": var f = flags(SERVICE_TYPES, raw); f == null ? null : {android: true, name: name, type: Axml.INT_HEX, value: f};
				case _: {android: true, name: name, type: Axml.STRING, string: raw};
			};
			if (typed == null) warnings.push('$id: android:$name="$raw" of <${x.nodeName}> dropped') else attrs.push(typed);
		}
		return Axml.el(x.nodeName, attrs, [for (c in x.elements()) element(c)]);
	}
}
