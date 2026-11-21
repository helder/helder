package helder.pack.android;

import helder.pack.android.ClassFile;
import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

// The fixtures' class files (tests/pack/jvm: lambdas, concatenation,
// exceptions, switches, numbers, arrays, interfaces, nests, locks, the
// stack's words, constants) translated and checked as a file; the
// emulator runs them (tests/pack/jvm.sh)
function tests() {
	final dir = "tests/pack/jvm/classes/fixture";
	final classes = [for (f in FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".class")) ClassFile.read(File.getBytes('$dir/$f'))];
	final byName = [for (c in classes) c.name => c];

	test("class files read: names, members, code, frames", () -> {
		var main = byName.get("fixture/Main");
		equals(main.superName, "java/lang/Object");
		equals(main.version, 55);
		equals(main.method("main", "([Ljava/lang/String;)V") != null, true);
		var lambdas = byName.get("fixture/Lambdas");
		equals(lambdas.bootstraps.length > 10, true);
		equals(byName.get("fixture/Nests$Inner").nestHost, "fixture/Nests");
		equals(byName.get("fixture/Old").version, 52);
		var statics = byName.get("fixture/Statics");
		equals(statics.field("LONG", "J").value, CLong(0x11f, 0x71fb04cb));
		equals(statics.field("TEXT", "Ljava/lang/String;").value, CString("constant \x0100FCn\x0100EF"));
	});

	test("translated: a checked file, no stubs, the lambdas' classes", () -> {
		var jvm = new Jvm(n -> byName.get(n));
		for (c in classes)
			jvm.prepare(c);
		var out = [];
		for (c in classes)
			for (d in jvm.translate(c))
				out.push(d);
		equals(jvm.stubs, []);
		var names = [for (d in out) d.name];
		equals(names.contains("Lfixture/Lambdas$$ExternalSyntheticLambda0;"), true);
		var dex = Dex.write(out);
		var listed = [];
		equals(Dex.check(dex, listed), []);
		equals(dex.getString(0, 8), "dex\n037\x00");
		equals(listed.contains("Lfixture/Nests; bump(Lfixture/Nests;I)I"), true);
	});

	test("strings: escaped, MUTF-8, sorted by UTF-16 units", () -> {
		equals(Dex.units("a\x0100e9"), [0x61, 0xe9]);
		equals(Dex.compare("\x01d83d", "\x01ffff") < 0, true);
		equals(Dex.compare("\x010000", "\x02") < 0, true);
		var dex = Dex.write([
			{
				name: "LS;",
				access: 1,
				superName: "Ljava/lang/Object;",
				interfaces: [],
				fields: [
					{name: "a", type: "Ljava/lang/String;", access: 8, value: VString("\x01d83d\x01de00")},
					{name: "b", type: "J", access: 8, value: VLong(-1, -2)}
				],
				methods: []
			}
		]);
		equals(Dex.check(dex), []);
	});
}
