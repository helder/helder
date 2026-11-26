package helder.ui.flow;

import haxe.io.Bytes;
import helder.test.Test;

// UAX #14 against Unicode's own cases: a sample of LineBreakTest.txt
// (tests/flow/line-break-test.txt; the whole file too where generate.mjs
// left it in bin/unicode-17.0.0), then CSS's tailorings.
function tests() {
	describe("LineBreaks (UAX #14)", () -> {
		test("LineBreakTest.txt: every boundary", () -> {
			var full = "bin/unicode-17.0.0/LineBreakTest.txt";
			var path = sys.FileSystem.exists(full) ? full : "tests/flow/line-break-test.txt";
			var lines = [for (l in sys.io.File.getContent(path).split("\n")) if (l != "" && l.charAt(0) != "#") l.split("#")[0]];
			assert(lines.length > 1500, "the sample");
			var lb = new LineBreaks(), failed = [];
			for (line in lines) {
				var parts = StringTools.trim(line).split(" ");
				// (÷ and × between code points: the text and what is expected before each unit)
				var buf = new StringBuf(), want = [];
				var k = 1;
				while (k < parts.length) {
					var cp = Std.parseInt("0x" + parts[k]);
					want.push(parts[k - 1] == "÷");
					buf.addChar(cp);
					k += 2;
				}
				// (strict: UAX #14's own CJ, a nonstarter)
				var s = buf.toString(), out = Bytes.alloc(s.length + 1), opts = Bytes.alloc(s.length);
				opts.fill(0, s.length, LineBreaks.STRICT);
				lb.analyze(s, 0, s.length, out, opts);
				var got = [], at = 0, j = 1;
				while (j < parts.length) {
					var cp = Std.parseInt("0x" + parts[j]);
					got.push(at > 0 && out.get(at) & LineBreaks.STATUS != LineBreaks.NONE);
					at += cp >= 0x10000 ? 2 : 1;
					j += 2;
				}
				// (the first boundary is sot's: never a break)
				want[0] = false;
				if (got.join(",") != want.join(",") && failed.length < 8) failed.push(StringTools.trim(line) + "  got " + [for (g in got) g ? "÷" : "×"].join(""));
			}
			equals(failed, [], "the lines that differ");
		});
		test("forced breaks", () -> {
			equals(statuses("a\nb"), "002");
			equals(statuses("a\r\nb"), "0002");
			equals(statuses("a b"), "001");
		});
		test("strict: a small kana does not start a line", () -> {
			// (ぁ is CJ: ID when normal, NS when strict)
			equals(statuses("あぁ"), "01");
			equals(statuses("あぁ", LineBreaks.STRICT), "00");
		});
		test("break-all and keep-all", () -> {
			equals(statuses("ab cd"), "00010");
			equals(statuses("ab cd", LineBreaks.BREAK_ALL), "01011");
			// (between ideographs: a break, none with keep-all; a space still breaks)
			equals(statuses("日本 語"), "0101");
			equals(statuses("日本 語", LineBreaks.KEEP_ALL), "0001");
		});
		test("anywhere: between any two characters, a nonbreaking space too", () -> {
			equals(statuses("a b", LineBreaks.ANYWHERE), "011");
		});
		test("an atomic inline breaks on both sides, a nonbreaking space next to it too", () -> {
			var s = "a ￼b", out = Bytes.alloc(5), opts = Bytes.alloc(4);
			opts.set(2, LineBreaks.ATOMIC);
			new LineBreaks().analyze(s, 0, 4, out, opts);
			equals([for (i in 0...4) out.get(i) & LineBreaks.STATUS], [0, 0, 1, 1]);
		});
		test("a mark is in its base's unit", () -> {
			var s = "é x", out = Bytes.alloc(5);
			new LineBreaks().analyze(s, 0, 4, out);
			equals([for (i in 0...4) out.get(i) & LineBreaks.CLUSTER != 0], [true, false, true, true]);
		});
	});
}

// (each unit's status as digits, one option for all)
private function statuses(s:String, o = 0):String {
	var out = Bytes.alloc(s.length + 1), opts = Bytes.alloc(s.length);
	opts.fill(0, s.length, o);
	new LineBreaks().analyze(s, 0, s.length, out, opts);
	return [for (i in 0...s.length) Std.string(out.get(i) & LineBreaks.STATUS)].join("");
}
