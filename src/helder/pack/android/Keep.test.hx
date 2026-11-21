package helder.pack.android;

import helder.pack.android.ClassFile;
import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

// ProGuard's keep rules as Shrink reads them: the kinds kept, the ones
// that keep only names dropped (nothing is renamed), -if's pair dropped;
// class names' wildcards, a class's access, kind, annotations and
// supertypes, members by name, type and arguments (tests/pack/jvm's classes)
function tests() {
	final dir = "tests/pack/jvm/classes/fixture";
	final classes = [for (f in FileSystem.readDirectory(dir)) ClassFile.read(File.getBytes('$dir/$f'))];
	final byName = [for (c in classes) c.name => c];
	final supers = (c:ClassFile) -> [c.name].concat(c.superName == null ? [] : [c.superName]).concat(c.interfaces);

	test("parsed: keep, members and with rules; names, allowshrinking and -if dropped", () -> {
		var rules = Keep.parse("
			# a comment
			-keep class a.B { *; }
			-keepclassmembers enum * { public static **[] values(); }
			-keepclasseswithmembers class * { native <methods>; }
			-keepnames class c.D
			-keep,allowshrinking class e.F
			-keepclassmembers,allowobfuscation class * extends g.H { <init>(); }
			-if class x.Y
			-keep class x.Z { *; }
			-dontwarn **
		");
		equals([for (r in rules) r.kind], ["keep", "members", "with", "members"]);
	});

	test("class names: ? one character, * within a package, ** across, a lone * any", () -> {
		equals(Keep.matches("a.b.*", "a.b.C"), true);
		equals(Keep.matches("a.b.*", "a.b.c.D"), false);
		equals(Keep.matches("a.**", "a.b.c.D"), true);
		equals(Keep.matches("a.?", "a.B"), true);
		equals(Keep.matches("a.b.C$*", "a.b.C$Inner"), true);
		var all = Keep.parse("-keep class * { *; }")[0];
		equals(all.classMatches(byName.get("fixture/Nests$Inner"), [], n -> null), true);
	});

	test("classes: kind, access, supertypes, negation", () -> {
		var color = byName.get("fixture/Switches$Color"), shape = byName.get("fixture/Interfaces$Shape"), circle = byName.get("fixture/Interfaces$Circle");
		var enums = Keep.parse("-keep enum fixture.** { *; }")[0];
		equals(enums.classMatches(color, supers(color), n -> byName.get(n)), true);
		equals(enums.classMatches(circle, supers(circle), n -> byName.get(n)), false);
		var impl = Keep.parse("-keep !interface * implements fixture.Interfaces$Shape")[0];
		equals(impl.classMatches(circle, supers(circle), n -> byName.get(n)), true);
		equals(impl.classMatches(shape, supers(shape), n -> byName.get(n)), false);
		var not = Keep.parse("-keep class fixture.*, !fixture.Main")[0];
		equals(not.classMatches(byName.get("fixture/Main"), [], n -> null), false);
		equals(not.classMatches(byName.get("fixture/Old"), [], n -> null), true);
	});

	test("members: names, types, arguments, access, <init>", () -> {
		var lambdas = byName.get("fixture/Lambdas");
		var r = Keep.parse("-keepclassmembers class * { private java.lang.String secret(java.lang.String); <init>(...); int base; static void run(); }")[0];
		var matched = [for (m in lambdas.methods) if (Lambda.exists(r.members, s -> r.methodMatches(s, m))) m.name];
		matched.sort(Reflect.compare);
		equals(matched, ["<init>", "run", "secret"]);
		equals([for (f in lambdas.fields) if (Lambda.exists(r.members, s -> r.fieldMatches(s, f))) f.name], ["base"]);
		var color = byName.get("fixture/Switches$Color");
		var defaults = Keep.parse(Keep.DEFAULTS)[0];
		equals([for (m in color.methods) if (Lambda.exists(defaults.members, s -> defaults.methodMatches(s, m))) m.name], ["values", "valueOf"]);
	});
}
