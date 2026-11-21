package helder.pack.android;

import helder.pack.android.ClassFile;
import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

// Shrink over tests/pack/jvm's classes: what fixture.Main.main reaches
// (calls, fields, lambdas' implementations, a virtual call's overrides in
// the classes instantiated, Object's methods, a framework interface's
// methods), what it does not, and members kept by rules
function tests() {
	final dir = "tests/pack/jvm/classes/fixture";
	final world = [for (f in FileSystem.readDirectory(dir)) {
		var c = ClassFile.read(File.getBytes('$dir/$f'));
		c.name => c;
	}];
	function shrink(rules:String):Shrink {
		var s = new Shrink(world, Keep.parse(Keep.DEFAULTS + rules));
		s.run();
		return s;
	}
	function kept(s:Shrink, cls:String, name:String):Bool {
		var c = world.get(cls);
		return Lambda.exists(c.methods, m -> m.name == name && s.keepsMethod(c, m));
	}

	test("from main: calls, lambdas' bodies, overrides, framework methods", () -> {
		var s = shrink("-keep class fixture.Main { public static void main(java.lang.String[]); }");
		equals(s.keepsClass("fixture/Lambdas"), true);
		equals(kept(s, "fixture/Lambdas", "secret"), true);
		equals(kept(s, "fixture/Lambdas", "lambda$run$0"), true);
		equals(kept(s, "fixture/Interfaces$Circle", "area"), true);
		// (AutoCloseable's close: try-with-resources calls it through the interface)
		equals(kept(s, "fixture/Exceptions$Res", "close"), true);
		equals(kept(s, "fixture/Switches$Color", "values"), true);
		var statics = world.get("fixture/Statics");
		equals(s.keepsField(statics, statics.field("TABLE", "[I")), true);
	});

	test("nothing else: an unreferenced class, an uncalled method", () -> {
		var s = shrink("-keep class fixture.Numbers { static void run(); }");
		equals(s.keepsClass("fixture/Numbers"), true);
		equals(kept(s, "fixture/Numbers", "fact"), true);
		equals(s.keepsClass("fixture/Lambdas"), false);
		equals(kept(s, "fixture/Main", "main"), false);
	});

	test("a kept virtual method keeps its overrides in the instantiated classes", () -> {
		var s = shrink("-keep class fixture.Interfaces$Shape { *; } -keep class fixture.Interfaces$Circle { <init>(); }");
		equals(kept(s, "fixture/Interfaces$Circle", "area"), true);
		equals(kept(s, "fixture/Interfaces$Both", "area"), false);
	});
}
