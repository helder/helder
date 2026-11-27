package helder.ui.flow;

import helder.test.Gen;
import helder.test.Test;
import helder.ui.flow.InlineContent;
import helder.ui.flow.InlineValues;

// InlineContent: white-space processing (CSS Text 3 §4.1), transforms,
// bidi levels, opportunities and pieces, in Ahem (tests/flow/fixtures:
// every glyph a square of its size, so widths are exact).
function tests() {
	describe("InlineContent", () -> {
		test("collapsible spaces: one between words, none at the start", () -> {
			equals(processed(["  a   b  "]), "a b ");
			equals(processed(["a\t\tb"]), "a b");
		});
		test("spaces collapse across inline boxes, the first kept", () -> {
			var c = content(s -> {
				s.addText("a ", ahem());
				s.openBox(ahem());
				s.addText(" b", ahem());
				s.closeBox();
			});
			equals(c.text, "a b");
			equals(c.end(0), 2);
		});
		test("segment breaks: a space, removed between ideographs", () -> {
			equals(processed(["a \n b"]), "a b");
			equals(processed(["日\n本"]), "日本");
			equals(processed(["한\n국"]), "한 국");
			equals(processed(["\u{1FAE8}\n\u{1FAE8}"]), "\u{1FAE8} \u{1FAE8}");
		});
		test("pre: everything kept, newlines forced breaks", () -> {
			var c = content(s -> s.addText("a  \n b", ahem(s -> s.collapse = Preserve)));
			equals(c.text, "a  \n b");
			equals([for (i in 0...c.items) c.kind(i)], [Text, Break, Text]);
		});
		test("pre-line: spaces collapse, the ones around a break dropped", () -> {
			equals(processed(["a  \n  b"], s -> s.collapse = PreserveBreaks), "a\nb");
		});
		test("after a forced break, a line's spaces dropped", () -> {
			var c = content(s -> {
				s.addText("a", ahem());
				s.addBreak();
				s.addText("  b", ahem());
			});
			equals(c.text, "a\nb");
		});
		test("text-transform", () -> {
			equals(processed(["hello world-wide"], s -> s.transform = Capitalize), "Hello World-Wide");
			equals(processed(["Hello"], s -> s.transform = Uppercase), "HELLO");
			equals(processed(["Ab 1"], s -> s.transform = FullWidth), "Ａｂ １");
		});
		test("source offsets: each unit's place in its box's text", () -> {
			var c = content(s -> s.addText("  a  b", ahem(), null, 10));
			equals(c.text, "a b");
			equals([for (u in 0...3) c.sourceOffset(u)], [12, 13, 15]);
		});
		test("break opportunities: after spaces, none in nowrap", () -> {
			var c = content(s -> s.addText("aa bb", ahem()));
			equals([for (p in 0...c.pieces) c.pieceBreak(p) & LineBreaks.STATUS], [0, 0, 1]);
			var n = content(s -> s.addText("aa bb", ahem(s -> s.wrap = NoWrap)));
			equals([for (p in 0...n.pieces) n.pieceBreak(p) & LineBreaks.STATUS], [0, 0, 0]);
		});
		test("nowrap's boundary with its neighbour: the side before it decides, as Blink's", () -> {
			// (<nobr>aa</nobr> bb: the break before bb is the root's)
			var c = content(s -> {
				s.openBox(ahem(s -> s.wrap = NoWrap));
				s.addText("aa", ahem(s -> s.wrap = NoWrap));
				s.closeBox();
				s.addText(" bb", ahem());
			});
			equals(c.pieceBreak(c.pieces - 1) & LineBreaks.STATUS, LineBreaks.ALLOWED);
			// (pre-wrap's spaces, then nowrap: a break after the spaces; nowrap's, then wrapping text: none)
			var d = content(s -> {
				s.addText("aa ", ahem(s -> s.wrap = NoWrap));
				s.openBox(ahem());
				s.addText("bb", ahem());
				s.closeBox();
			});
			equals([for (p in 0...d.pieces) d.pieceBreak(p) & LineBreaks.STATUS], [0, 0, 0, 0, 0]);
		});
		test("a break before an inline box goes before its start, after a close", () -> {
			var c = content(s -> {
				s.openBox(ahem());
				s.addText("aa ", ahem());
				s.closeBox();
				s.openBox(ahem());
				s.addText("bb", ahem());
				s.closeBox();
			});
			// (Open, aa, space, Close, Open, bb, Close)
			equals([for (p in 0...c.pieces) c.pieceBreak(p) & LineBreaks.STATUS], [0, 0, 0, 0, 1, 0, 0]);
		});
		test("soft hyphens: a break that shows a hyphen, none with hyphens: none", () -> {
			var c = content(s -> s.addText("hy­phen", ahem()));
			equals(c.pieceBreak(1), LineBreaks.ALLOWED | InlineContent.HYPHEN);
			var n = content(s -> s.addText("hy­phen", ahem(s -> s.hyphen = None)));
			equals(n.pieces, 1);
		});
		test("pieces are shaped: Ahem's squares", () -> {
			var c = content(s -> s.addText("ab  cd", ahem()));
			equals([for (p in 0...c.pieces) c.pieceWidth(p)], [32.0, 16.0, 32.0]);
		});
		test("bidi: right-to-left text in its own items, levels from the root", () -> {
			var c = content(s -> s.addText("ab אב cd", ahem()));
			assert(c.bidi);
			equals([for (i in 0...c.items) c.level(i)], [0, 1, 0]);
			var r = new InlineContent(ahem(s -> s.dir = Rtl));
			r.addText("ab", ahem());
			r.finish();
			equals(r.level(0), 2);
		});
		test("an isolate's controls: its content at its own level", () -> {
			var rtl = ahem(s -> {
				s.dir = Rtl;
				s.bidi = Isolate;
			});
			var c = content(s -> {
				s.addText("a ", ahem());
				s.openBox(rtl);
				s.addText("bc", rtl);
				s.closeBox();
			});
			equals(c.level(2), 2);
		});
		test("the items cover the text, in order", () -> property(contents(), c -> {
			var at = 0;
			for (i in 0...c.items) {
				equals(c.start(i), at, "item " + i);
				at = c.end(i);
			}
			equals(at, c.text.length);
			var pt = 0;
			for (p in 0...c.pieces) {
				equals(c.pieceStart(p), pt);
				pt = c.pieceEnd(p);
			}
			equals(pt, c.text.length);
		}));
		test("collapsed: no two spaces in a row, none at a line's start", () -> property(contents(), c -> {
			var t = c.text;
			assert(t.indexOf("  ") < 0, t);
			assert(t.charAt(0) != " " && t.indexOf("\n ") < 0, t);
		}));
	});
}

private var loaded = false;

private function ahem(?change:InlineBasicStyle->Void):InlineBasicStyle {
	if (!loaded) {
		helder.text.SystemFonts.get().add(sys.io.File.getBytes("tests/flow/fixtures/Ahem.ttf"));
		loaded = true;
	}
	var s = new InlineBasicStyle();
	s.families = ["Ahem"];
	if (change != null) change(s);
	return s;
}

private function content(build:InlineContent->Void):InlineContent {
	var c = new InlineContent(ahem());
	build(c);
	c.finish();
	return c;
}

private function processed(texts:Array<String>, ?change:InlineBasicStyle->Void):String {
	var st = ahem(change);
	return content(c -> for (t in texts) c.addText(t, st)).text;
}

// (contents of white space, words, boxes and breaks in collapse mode)
private function contents():Gen<InlineContent> {
	var style = ahem();
	return c -> {
		var n = c.draw(int(0, 12)), out = new InlineContent(style), depth = 0;
		for (_ in 0...n)
			switch c.draw(int(0, 5)) {
				case 0 | 1: out.addText(c.draw(string(pick([" ", "\n", "\t", "a", "b", "א"]), 0, 8)), style);
				case 2:
					out.openBox(style);
					depth++;
				case 3 if (depth > 0):
					out.closeBox();
					depth--;
				case 4: out.addBreak();
				case _: out.addAtomic(10, 10, 8, style);
			}
		out.finish();
		out;
	}
}
