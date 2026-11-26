package helder.ui.flow;

import helder.test.Gen;
import helder.test.Test;
import helder.ui.flow.InlineContent;
import helder.ui.flow.InlineLayout;
import helder.ui.flow.InlineValues;

// Lines and fragments in Ahem at 16px (squares of 16, ascent 13 and
// descent 3 as Blink rounds 12.8 and 3.2: line-height normal 16), then the
// properties: lines fit unless a piece cannot break, a layout is the same
// twice, min-content <= max-content, max-content's lines are the forced
// breaks', and the fragments' text in order is the content's.
function tests() {
	describe("InlineLayout", () -> {
		test("words wrap at spaces, the spaces at a line's end removed", () -> {
			var l = lay(c -> c.addText("aa bb cc", ahem()), 80);
			equals(l.lines, 2);
			equals([l.lineWidth(0), l.lineWidth(1)], [80.0, 32.0]);
			equals([l.lineTop(1), l.lineHeight(0), l.lineBaseline(0)], [16.0, 16.0, 13.0]);
			equals(texts(l), ["aa bb", "cc"]);
		});
		test("line-height: half the leading above, half below", () -> {
			var l = lay(c -> c.addText("a", ahem(s -> s.height = 30)), 100, ahem(s -> s.height = 30));
			equals([l.lineHeight(0), l.lineBaseline(0)], [30.0, 20.0]);
			equals([l.y(0), l.fragmentHeight(0)], [7.0, 16.0]);
		});
		test("an inline box's edges take room; its span is its border box", () -> {
			var box = ahem(s -> s.edges(2, 3, 4));
			var l = lay(c -> {
				c.addText("a", ahem());
				c.openBox(box);
				c.addText("bb", ahem());
				c.closeBox();
			}, 200);
			equals(l.lineWidth(0), 16 + 9 + 32 + 9.0);
			var span = find(l, BoxSpan);
			equals([l.x(span), l.fragmentWidth(span)], [18.0, 32 + 14.0]);
			equals([l.y(span), l.fragmentHeight(span)], [-7.0, 30.0]);
			equals(l.x(find(l, TextRun, 1)), 25.0);
		});
		test("a box split across lines: its start edge on the first, its end on the last", () -> {
			var box = ahem(s -> s.edges(0, 0, 10));
			var l = lay(c -> {
				c.openBox(box);
				c.addText("aa bb", ahem());
				c.closeBox();
			}, 50);
			equals(l.lines, 2);
			equals([l.lineWidth(0), l.lineWidth(1)], [42.0, 42.0]);
		});
		test("vertical-align: super, sub, text-top, middle, a length", () -> {
			inline function rise(v:InlineVerticalAlign, ?shift = 0.0):Float {
				var small = ahem(s -> {
					s.size = 10;
					s.vertical = v;
					s.shift = shift;
				});
				var l = lay(c -> {
					c.addText("a", ahem());
					c.openBox(small);
					c.addText("b", small);
					c.closeBox();
				}, 200);
				// (the small text's baseline above the line's)
				var t = find(l, TextRun, 1);
				return l.lineBaseline(0) - (l.y(t) + l.ascent(t));
			}
			equals(rise(Baseline), 0.0);
			// (Blink's LayoutUnit: 1/64 of a pixel, toward zero)
			approx(rise(Super), Std.int((16 / 3 + 1) * 64) / 64);
			approx(rise(Sub), -Std.int((16 / 5 + 1) * 64) / 64);
			equals(rise(Length, 4), 4.0);
			// (text-top: the box's top at its parent's ascent; Ahem 10px: ascent 8, line 10)
			equals(rise(TextTop), 13 - 8.0);
		});
		test("vertical-align: top and bottom align to the line box", () -> {
			var tall = ahem(s -> s.vertical = Top);
			var l = lay(c -> {
				c.addText("a", ahem());
				c.addAtomic(10, 40, 30, tall);
			}, 200);
			equals(l.lineHeight(0), 40.0);
			var at = find(l, Atomic);
			equals(l.y(at), 0.0);
			equals(l.lineBaseline(0), 13.0);
		});
		test("an atomic inline sits on the baseline by its own", () -> {
			var l = lay(c -> {
				c.addText("a", ahem());
				c.addAtomic(20, 30, 25, ahem());
			}, 200);
			// (25 above the baseline, 5 below: the strut's 13 and 3 within)
			equals([l.lineHeight(0), l.lineBaseline(0)], [30.0, 25.0]);
			equals([l.x(find(l, Atomic)), l.y(find(l, Atomic))], [16.0, 0.0]);
		});
		test("a forced break ends a line, its spaces before it removed", () -> {
			var l = lay(c -> {
				c.addText("aa ", ahem());
				c.addBreak();
				c.addText("b", ahem());
			}, 200);
			equals(l.lines, 2);
			equals(l.lineWidth(0), 32.0);
			assert(l.lineForced(0));
		});
		test("an isolate's end after a forced break: on that line, unless something is right to left", () -> {
			function width(dir:InlineDirection) {
				var l = lay(c -> {
					c.openBox(ahem(s -> {
						s.edges(0, 0, 10);
						s.bidi = Isolate;
						s.dir = dir;
					}));
					c.addText("aa", ahem());
					c.addBreak();
					c.closeBox();
				}, 200);
				return [for (k in 0...l.lines) l.lineWidth(k)];
			}
			equals(width(Ltr), [52.0]);
			equals(width(Rtl), [42.0, 10.0]);
		});
		test("pre-wrap's spaces hang at a line's end", () -> {
			var pw = ahem(s -> s.collapse = Preserve);
			var l = lay(c -> c.addText("aa   bb", pw), 60);
			equals(l.lines, 2);
			equals(l.lineWidth(0), 32.0);
			equals(l.fragmentWidth(0), 80.0);
		});
		test("a soft hyphen's break shows a hyphen", () -> {
			var l = lay(c -> c.addText("aaa­bbb", ahem()), 70);
			equals(l.lines, 2);
			var h = find(l, Hyphen);
			equals([l.x(h), l.fragmentWidth(h)], [48.0, 16.0]);
			equals(l.lineWidth(0), 64.0);
		});
		test("overflow-wrap: a word too wide cut where it must", () -> {
			var l = lay(c -> c.addText("aaaaaa", ahem(s -> s.overflow = BreakWord)), 40);
			equals(l.lines, 3);
			equals(texts(l), ["aa", "aa", "aa"]);
			var n = lay(c -> c.addText("aaaaaa", ahem()), 40);
			equals(n.lines, 1);
		});
		test("tabs: to the next stop, in the block's spaces", () -> {
			var l = lay(c -> c.addText("a\tb", ahem(s -> s.collapse = Preserve)), 500, ahem(s -> s.tab = 4));
			equals(l.lineWidth(0), 64 + 16.0);
		});
		test("text-align and text-indent", () -> {
			var root = ahem(s -> {
				s.align = Center;
				s.indent = 10;
			});
			var l = lay(c -> c.addText("aa", ahem()), 100, root);
			equals(l.lineLeft(0), (100 - 42) / 2);
			equals(l.x(0), (100 - 42) / 2 + 10);
		});
		test("justify: the room shared among the spaces, the last line as it is", () -> {
			var root = ahem(s -> s.align = Justify);
			var l = lay(c -> c.addText("aa b cc dd", ahem()), 100, root);
			equals(l.lines, 2);
			// ("aa b cc" is 112 wide: no; "aa b" 64, two spaces' room shared: 36 to the one space)
			equals(texts(l), ["aa b", "cc dd"]);
			equals([l.lineWidth(0), l.lineWidth(1)], [100.0, 80.0]);
			var g = l.glyphs, r = l.glyphRun(0);
			// (b after the widened space: 32 + 16 + 36)
			equals(g.x(g.runStart(r) + 3), 84.0);
		});
		test("justify: an atomic between, its space alone takes the room", () -> {
			var root = ahem(s -> {
				s.align = Justify;
				s.indent = 10;
			});
			var l = lay(c -> {
				c.addText("abc ", ahem());
				c.addAtomic(0, 44, Math.NaN, ahem(s -> s.margins = [3, 2, 0, 0]));
				c.addText("abcdxyz  abcd", ahem());
			}, 220, root);
			equals(l.fragmentWidth(0), 64 + 29.0);
			var same = lay(c -> {
				c.addText("abc ", ahem(s -> s.height = 30));
				c.addAtomic(0, 44, Math.NaN, ahem(s -> {
					s.height = 30;
					s.margins = [2, 3, 0, 0];
					s.vertical = TextTop;
				}));
				c.addText("abcdxyz  abcd-ab\ta  ", ahem(s -> s.height = 30));
			}, 220, ahem(s -> {
				s.align = Justify;
				s.indent = 10;
				s.height = 30;
			}));
			equals(texts(same), ["abc abcdxyz", "abcd-ab a"]);
			equals(same.fragmentWidth(0), 64 + 29.0);
		});
		test("justify: inter-character, after every character but the line's last", () -> {
			var root = ahem(s -> {
				s.align = Justify;
				s.justify = InterCharacter;
			});
			var l = lay(c -> c.addText("ab cd", ahem()), 120, ahem(s -> {
				s.align = Justify;
				s.justify = InterCharacter;
			}));
			equals(l.lines, 1);
			equals(l.lineWidth(0), 80.0);
			var l2 = lay(c -> c.addText("ab cd ef", ahem()), 100, root);
			equals(l2.lineWidth(0), 100.0);
		});
		test("text-overflow: ellipsis: what overflows given up at glyphs, an ellipsis after what is left", () -> {
			var root = ahem(s -> {
				s.textOverflowEnd = Ellipsis;
				s.wrap = NoWrap;
			});
			var l = lay(c -> c.addText("abcdefgh", ahem(s -> s.wrap = NoWrap)), 100, root);
			var e = find(l, Ellipsis);
			assert(e >= 0, "an ellipsis");
			// (100 holds 6 squares; 5 and the ellipsis)
			equals([l.fragmentWidth(0), l.x(e), l.fragmentWidth(e)], [80.0, 80.0, 16.0]);
			equals(l.textEnd(0), 5);
		});
		test("text-overflow: ellipsis in a right-to-left paragraph: on the left", () -> {
			var root = ahem(s -> {
				s.textOverflowEnd = Ellipsis;
				s.wrap = NoWrap;
				s.dir = Rtl;
			});
			var l = lay(c -> c.addText("abcdefgh", ahem(s -> s.wrap = NoWrap)), 100, root);
			var e = find(l, Ellipsis);
			equals([l.x(e), l.x(0), l.x(0) + l.fragmentWidth(0)], [4.0, 20.0, 100.0]);
		});
		test("line-clamp: its last line ends in an ellipsis, none after it", () -> {
			var root = ahem(s -> s.clamp = 2);
			var l = lay(c -> c.addText("aaaa bbbb cccc dddd", ahem()), 100, root);
			equals(l.lines, 2);
			var e = find(l, Ellipsis);
			assert(e >= 0, "an ellipsis");
			equals(l.x(e), 64.0);
			var all = lay(c -> c.addText("aaaa bbbb", ahem()), 100, root);
			equals([all.lines, find(all, Ellipsis)], [2, -1]);
		});
		test("hit testing: a point to its unit, by the glyph's half", () -> {
			var l = lay(c -> c.addText("aa bb", ahem()), 50);
			// (line 0: "aa", line 1: "bb")
			equals(l.hitTest(5, 5).offset, 0);
			equals(l.hitTest(10, 5).offset, 1);
			equals(l.hitTest(40, 5).offset, 2);
			equals(l.hitTest(17, 20).offset, 4);
			equals(l.hitTest(100, 100).offset, 5);
			equals(l.hitTest(-10, 20).offset, 3);
		});
		test("hit testing right to left: the right half is before", () -> {
			var rtl = ahem(s -> {
				s.dir = Rtl;
				s.bidi = BidiOverride;
			});
			var l = lay(c -> {
				c.openBox(rtl);
				c.addText("abc", rtl);
				c.closeBox();
			}, 100);
			// (c b a, from the left: 'a' at 32 to 48)
			equals(l.hitTest(46, 5).offset, 0);
			equals(l.hitTest(34, 5).offset, 1);
			equals(l.hitTest(2, 5).offset, 3);
		});
		test("carets: before each unit, a right-to-left one's right edge", () -> {
			var l = lay(c -> c.addText("ab cd", ahem()), 50);
			equals([l.caret(0).x, l.caret(1).x, l.caret(3).x, l.caret(3).line, l.caret(5).x], [0.0, 16.0, 0.0, 1, 32.0]);
			var rtl = ahem(s -> {
				s.dir = Rtl;
				s.bidi = BidiOverride;
			});
			var r = lay(c -> {
				c.openBox(rtl);
				c.addText("abc", rtl);
				c.closeBox();
			}, 100);
			equals([r.caret(0).x, r.caret(1).x], [48.0, 32.0]);
		});
		test("selection: a rectangle a run of selected glyphs a line, the line's height", () -> {
			var l = lay(c -> {
				c.addText("aa b", ahem());
				c.addAtomic(10, 10, Math.NaN, ahem());
				c.addText(" cc dd", ahem(s -> s.height = 30));
			}, 90);
			var s = l.selection(1, 9);
			equals([for (r in s) [r.x, r.y, r.width, r.height]], [[16.0, 0.0, 58.0, l.lineHeight(0)], [0.0, l.lineTop(1), 48.0, l.lineHeight(1)]]);
			equals(l.selection(2, 2), []);
		});
		test("DOM positions: a unit to its node and offset, and back", () -> {
			var doc = new helder.dom.Document();
			var t = doc.createTextNode("  a  b"), u = doc.createTextNode("c");
			var c = content(c -> {
				c.addText("  a  b", ahem(), t, 0);
				c.addText("c", ahem(), u, 0);
			});
			equals(c.text, "a bc");
			var p = c.domPosition(2);
			equals([p.node == t, p.offset == 5], [true, true]);
			equals(c.domPosition(3).node == u, true);
			equals([c.unitOf(t, 3), c.unitOf(t, 4), c.unitOf(u, 0), c.unitOf(u, 1)], [1, 2, 3, 4]);
		});
		test("hyphens: auto: a word broken at its language's points, a hyphen shown", () -> {
			helder.text.Hyphenation.add(helder.text.hyphenation.EnUs.patterns());
			var auto = ahem(s -> {
				s.hyphen = Auto;
				s.language = "en";
			});
			// (hy-phen-ation: 112 holds "hyphen" and its hyphen)
			var l = lay(c -> c.addText("hyphenation", auto), 112);
			equals(texts(l), ["hyphen", "ation"]);
			assert(find(l, Hyphen) >= 0, "a hyphen");
			// (none without a language, none in capitals, none with hyphens: manual)
			equals(lay(c -> c.addText("hyphenation", ahem(s -> s.hyphen = Auto)), 112).lines, 1);
			equals(lay(c -> c.addText("HYPHENATION", auto), 112).lines, 1);
			equals(lay(c -> c.addText("hyphenation", ahem(s -> s.language = "en")), 112).lines, 1);
		});
		test("floats narrow lines: lineWidth's offset and width", () -> {
			var c = new InlineContent(ahem());
			c.addText("aa bb cc", ahem());
			var l = new InlineLayout().layout(c, new InlineConstraints(100, (y, h) -> y < 16 ? {offset: 40, width: 60} : {offset: 0, width: 100}));
			equals(texts(l), ["aa", "bb cc"]);
			equals(l.x(0), 40.0);
		});
		test("min-content and max-content", () -> {
			var c = content(c -> c.addText("aa bbb c", ahem()));
			equals(InlineLayout.minContent(c), 48.0);
			equals(InlineLayout.maxContent(c), 128.0);
			var a = content(c -> c.addText("aaa", ahem(s -> s.overflow = Anywhere)));
			equals(InlineLayout.minContent(a), 16.0);
		});
		test("glyph runs: a run a text fragment, its glyphs from its left", () -> {
			var l = lay(c -> c.addText("ab", ahem()), 100);
			var r = l.glyphRun(0);
			equals(l.glyphs.runCount(r), 2);
			equals([l.glyphs.x(l.glyphs.runStart(r) + 1), l.glyphs.advance(l.glyphs.runStart(r))], [16.0, 16.0]);
		});
		test("no line is wider than its width unless a piece cannot break", () -> property(cases(), k -> {
			var c = k.content, l = new InlineLayout().layout(c, new InlineConstraints(k.width));
			for (i in 0...l.lines)
				if (l.lineWidth(i) > k.width + 1e-3 && contentRight(l, i) > k.width + 1e-3) assert(unbreakable(l, i), 'line $i: ${l.lineWidth(i)} > ${k.width}');
		}));
		test("laid out twice at a width: the same", () -> property(cases(), k -> {
			var c = k.content;
			var a = snapshot(new InlineLayout().layout(c, new InlineConstraints(k.width)));
			var b = snapshot(new InlineLayout().layout(c, new InlineConstraints(k.width)));
			equals(a, b);
		}));
		test("min-content <= max-content; at max-content, a line a forced break", () -> property(cases(), k -> {
			var c = k.content, min = InlineLayout.minContent(c), max = InlineLayout.maxContent(c);
			assert(min <= max + 1e-6, '$min > $max');
			var l = new InlineLayout().layout(c, new InlineConstraints(max));
			var forced = 0;
			for (i in 0...l.lines)
				if (l.lineForced(i)) forced++;
			equals(l.lines - forced <= 1, true, 'lines ${l.lines}, forced $forced');
		}));
		test("a point just right of a glyph's left edge hits its cluster; a caret there is at it", () -> property(cases(), k -> {
			var c = k.content, l = new InlineLayout().layout(c, new InlineConstraints(k.width)), g = l.glyphs;
			for (f in 0...l.fragments) {
				if (l.kind(f) != TextRun || l.glyphRun(f) < 0) continue;
				var r = l.glyphRun(f);
				for (i in g.runStart(r)...g.runStart(r) + g.runCount(r)) {
					if (g.advance(i) < 1) continue;
					var x = l.x(f) + g.x(i), line = 0;
					while (line < l.lines - 1 && f >= l.lineFragmentEnd(line))
						line++;
					var hit = l.hitTest(x + 0.1, l.lineTop(line) + 0.5);
					equals(hit.offset, g.cluster(i), 'glyph $i at $x');
					approx(l.caret(g.cluster(i)).x, x, 1e-6);
				}
			}
		}));
		test("the fragments' text in order is the content's (but spaces removed at lines' ends)", () -> property(cases(), k -> {
			var c = k.content, l = new InlineLayout().layout(c, new InlineConstraints(k.width)), t = c.text;
			var at = 0;
			for (f in 0...l.fragments) {
				var kind = l.kind(f);
				if (kind != TextRun && kind != Atomic) continue;
				for (u in at...l.textStart(f)) {
					var ch = t.charCodeAt(u);
					assert(ch == 32 || ch == 10, 'unit $u (${t.charAt(u)}) in no fragment');
				}
				assert(l.textStart(f) >= at, "in order");
				at = l.textEnd(f);
			}
			for (u in at...t.length)
				assert(t.charCodeAt(u) == 32 || t.charCodeAt(u) == 10);
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

private function content(build:InlineContent->Void, ?root:InlineStyle):InlineContent {
	var c = new InlineContent(root == null ? ahem() : root);
	build(c);
	c.finish();
	return c;
}

private function lay(build:InlineContent->Void, width:Float, ?root:InlineStyle):InlineLayout
	return new InlineLayout().layout(content(build, root), new InlineConstraints(width));

// (each line's text runs' text, joined)
private function texts(l:InlineLayout):Array<String> {
	var t = l.content.text;
	return [
		for (k in 0...l.lines)
			[
				for (f in l.lineFragmentStart(k)...l.lineFragmentEnd(k))
					if (l.kind(f) == TextRun) t.substring(l.textStart(f), l.textEnd(f))
			].join("")
	];
}

// (the nth fragment of a kind)
private function find(l:InlineLayout, kind:InlineFragment, nth = 0):Int {
	for (f in 0...l.fragments)
		if (l.kind(f) == kind && nth-- == 0) return f;
	return -1;
}

private function snapshot(l:InlineLayout):Array<Array<Float>>
	return [
		for (f in 0...l.fragments)
			[l.kind(f), l.x(f), l.y(f), l.fragmentWidth(f), l.fragmentHeight(f), l.textStart(f), l.textEnd(f)]
	];

// (how far a line's text and atomics reach from its left: boxes' end edges
// after its trailing spaces may overflow, as Blink lets them)
private function contentRight(l:InlineLayout, i:Int):Float {
	var right = 0.0;
	for (f in l.lineFragmentStart(i)...l.lineFragmentEnd(i))
		if (l.kind(f) == TextRun || l.kind(f) == Atomic || l.kind(f) == Hyphen) right = Math.max(right, l.x(f) + l.fragmentWidth(f) - l.lineLeft(i));
	return right;
}

// (whether line i holds a piece it could not break: no opportunity in it but at its start)
private function unbreakable(l:InlineLayout, i:Int):Bool {
	var c = l.content;
	for (u in l.lineStart(i) + 1...l.lineEnd(i))
		// (a soft hyphen's: its fit is its hyphen's too)
		if (c.breakAt(u) & LineBreaks.STATUS == LineBreaks.ALLOWED && c.breakAt(u) & InlineContent.HYPHEN == 0) {
			// (an opportunity inside: the line would have broken there unless what is before it overflows alone)
			// (with nothing before it but edges and spaces removed at the line's start, no break there)
			var before = 0.0, content = false;
			for (f in l.lineFragmentStart(i)...l.lineFragmentEnd(i))
				if (l.textEnd(f) <= u && (l.kind(f) == TextRun || l.kind(f) == Atomic)) {
					before = l.x(f) + l.fragmentWidth(f) - l.lineLeft(i);
					content = true;
				}
			if (content && before <= l.lineAvailable(i) + 1e-3) return false;
		}
	return true;
}

// (a case: what builds its content, as text, and a width)
private class Case {
	public final ops:Array<String>;
	public final width:Float;
	public var content(get, never):InlineContent;

	public function new(ops:Array<String>, width:Float) {
		this.ops = ops;
		this.width = width;
	}

	function get_content():InlineContent {
		var c = new InlineContent(STYLES[0]);
		for (o in ops) {
			var arg = o.substr(2);
			switch o.charAt(0) {
				case "t": c.addText(arg.substr(1), STYLES[Std.parseInt(arg.charAt(0))]);
				case "o": c.openBox(STYLES[Std.parseInt(arg)]);
				case "c": c.closeBox();
				case "b": c.addBreak();
				case _:
					var n = arg.split(",").map(Std.parseFloat);
					c.addAtomic(n[0], n[1], n[2], STYLES[0]);
			}
		}
		c.finish();
		return c;
	}

	public function toString():String
		return '{ops: ${haxe.Json.stringify(ops)}, width: $width}';
}

private final STYLES = [
	ahem(),
	ahem(s -> s.edges(1, 2, 3)),
	ahem(s -> s.collapse = Preserve),
	ahem(s -> s.wrap = NoWrap),
	ahem(s -> s.overflow = BreakWord),
	ahem(s -> {
		s.size = 10;
		s.vertical = Super;
	}),
	ahem(s -> s.collapse = BreakSpaces)
];

// (words, spaces, boxes with edges, atomics, breaks; white-space modes; widths)
private function cases():Gen<Case> {
	return c -> {
		var ops = [], depth = 0;
		for (_ in 0...c.draw(int(1, 14)))
			switch c.draw(int(0, 6)) {
				case 0 | 1 | 2:
					var st = c.draw(int(0, STYLES.length - 1));
					ops.push("t " + st + c.draw(string(pick([" ", "a", "b", "c", "-", "­", "	"]), 0, 12)));
				case 3:
					ops.push("o " + c.draw(int(0, 5)));
					depth++;
				case 4 if (depth > 0):
					ops.push("c ");
					depth--;
				case 5: ops.push("b ");
				case _: ops.push("a " + c.draw(int(0, 40)) + "," + c.draw(int(0, 40)) + "," + c.draw(int(0, 40)));
			}
		new Case(ops, c.draw(int(0, 30)) * 10.0);
	}
}
