package helder.css;

import helder.test.Test;

// The tables generate.mjs writes as data (CssPacked), read back as CssData has them.
function tests() {
	describe("CssPacked", () -> {
		test("numbers, strings and floats read back", () -> {
			var w = new CssPackedWriter();
			for (n in [0, 1, 62, 63, 64, 4095, 1 << 30, -1, -63, -(1 << 31), 0x7fffffff]) w.int(n);
			for (s in ["a", "", "a", "é“q”", "\x01\x7f"]) w.str(s);
			for (f in [0.5, -3, 1e-7, Math.POSITIVE_INFINITY]) w.float(f);
			var r = new CssPacked(w.toString());
			equals([for (_ in 0...11) r.int()], [0, 1, 62, 63, 64, 4095, 1 << 30, -1, -63, -(1 << 31), 0x7fffffff]);
			equals([for (_ in 0...5) r.str()], ["a", "", "a", "é“q”", "\x01\x7f"]);
			equals([for (_ in 0...4) r.float()], [0.5, -3, 1e-7, Math.POSITIVE_INFINITY]);
		});
		test("CssTable's definitions, as CssData's", () -> {
			var table = [for (p in CssTable.properties) p.name => p];
			for (p in CssData.properties) {
				var t = table.get(p.name);
				equals([t.syntax, t.alias, Std.string(t.inherited), t.longhands.join(" ")], [p.syntax, p.alias, Std.string(p.inherited), p.longhands.join(" ")]);
			}
			equals(CssTable.types.length, CssData.types.length);
			equals([for (t in CssTable.types) t.name + " " + t.syntax], [for (t in CssData.types) t.name + " " + t.syntax]);
		});
		test("CssProperties' columns", () -> {
			for (k in 0...CssProperties.COUNT) {
				var p:CssProperty = cast k;
				equals(CssProperties.of(CssProperties.name(p)), p);
			}
			var color = CssProperties.of("color"), display = CssProperties.of("display"), start = CssProperties.of("margin-inline-start");
			equals([CssProperties.inherits(color), CssProperties.inherits(display), CssProperties.logical(start)], [true, false, true]);
			equals(CssProperties.name(CssProperties.physical(start, true)), "margin-right");
			equals(CssProperties.keywords(CssProperties.of("-helder-scrollbar")), ["system", "overlay", "always"]);
			equals(CssProperties.groups.length, CssProperties.members.length);
		});
		test("CssInitial's values, as their text parses", () -> {
			for (p in CssData.properties) if (p.initial != null && p.longhands.length == 0) {
				var v = CssValues.parse(p.name, p.initial);
				if (v != null) equals(written(CssInitial.specified(p.name)), written(v));
			}
			equals(written(CssInitial.of("-helder-material-tint")), written(CssValues.parse("-helder-material-tint", "transparent")));
		});
	});
}

// (a value as its encoding: anonymous structures' fields in no fixed order otherwise)
private function written(v:Null<CssTerm.CssSpecified>):String
	return CssSheetData.encodeInitials([{name: "", specified: v, of: null}]);
