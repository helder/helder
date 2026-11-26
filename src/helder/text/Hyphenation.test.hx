package helder.text;

import helder.test.Gen;
import helder.test.Test;
import helder.text.hyphenation.Languages;

// Each language's words hyphenated as the reference hyphenates them
// (tests/text/fixtures/hyphenation: generate.mjs's, Liang's algorithm on
// hyph-utf8's files as they are: the exceptions, a hand list, words of the
// patterns' pieces), BCP 47's matching, and TextLayout breaking at the
// points (hyphens auto) as at soft hyphens.
function tests() {
	Hyphenation.addAll();
	describe("Hyphenation", () -> {
		for (tag in Languages.TAGS)
			test('$tag: as the reference hyphenates', () -> {
				var h = require(Hyphenation.get(tag));
				var bad = [];
				for (line in sys.io.File.getContent('tests/text/fixtures/hyphenation/$tag.txt').split("\n")) {
					if (line == "") continue;
					var word = StringTools.replace(line, "-", "");
					var got = show(word, h.points(word));
					if (got != line) bad.push('$got (the reference: $line)');
				}
				equals(bad, []);
			});
		test("the hand lists", () -> {
			equals(show("hyphenation", Hyphenation.get("en").points("hyphenation")), "hy-phen-ation");
			equals(show("Silbentrennung", Hyphenation.get("de").points("Silbentrennung")), "Sil-ben-tren-nung");
			equals(show("woordenboek", Hyphenation.get("nl-BE").points("woordenboek")), "woor-den-boek");
			// (an exception: as the file has it, not the patterns)
			equals(show("table", Hyphenation.get("en-US").points("table")), "ta-ble");
		});
		test("BCP 47: the nearest language added", () -> {
			equals([for (t in ["en", "en-US", "en_GB", "en-AU", "en-CA", "nl-BE", "de", "de-CH", "de-1996", "pt-BR", "no", "nb-NO", "fr-CA", "sv-FI"]) Hyphenation.get(t).language], [
				"en-us", "en-us", "en-gb", "en-gb", "en-us", "nl", "de-1996", "de-1996", "de-1996", "pt", "nb", "nb", "fr", "sv"
			]);
			for (t in ["ja", "cs", "", "x", "und"])
				equals(Hyphenation.get(t), null, t);
		});
		test("removing the points gives the word back; the points within its limits", () -> property(c -> {
			var tag = c.draw(pick(Languages.TAGS));
			var letters = [for (w in sys.io.File.getContent('tests/text/fixtures/hyphenation/$tag.txt').split("\n")) w];
			var w = c.draw(pick(letters));
			return {tag: tag, word: StringTools.replace(w, "-", "") + c.draw(pick(["", "s", "en", "ing"]))};
		}, x -> {
			var h = Hyphenation.get(x.tag), p = h.points(x.word);
			equals(StringTools.replace(show(x.word, p), "-", ""), x.word);
			var last = 0;
			for (i in p) {
				assert(i > last && i >= h.left && x.word.length - i >= h.right, '${x.word} at $i');
				last = i;
			}
		}));
	});
	describe("TextLayout, hyphens auto", () -> {
		var inter = FontFile.parse(helder.asset.Asset.embed("helder/text/fonts/Inter.ttf"));
		var set = new FontSet(inter, [], 16);
		// (each line's text, "-" where a hyphen is shown at its end)
		function lines(l:TextLayout):Array<String>
			return [
				for (line in l.lines) {
					var last = line.glyphEnd - 1, shown = last >= line.glyphStart && l.glyphChar(last) == 0xAD && !l.glyphHidden(last);
					StringTools.trim(l.text.substring(line.start, line.end)) + (shown ? "-" : "");
				}
			];
		var en = "Typographers argue that automatic hyphenation improves the appearance of justified paragraphs considerably.";
		var nl = "Automatische woordafbreking verbetert de verschijning van uitgevulde alinea's in smalle kolommen aanzienlijk.";
		test("a narrow justified paragraph: English and Dutch broken at their points", () -> {
			var l = new TextLayout(en, set, 1.25, 140, null, 0, 0, 0, -1, Math.NaN, TextLayout.BREAK_WORD, Hyphenation.get("en"));
			l.justify(140);
			equals(lines(l), EN_LINES);
			var d = new TextLayout(nl, set, 1.25, 140, null, 0, 0, 0, -1, Math.NaN, TextLayout.BREAK_WORD, Hyphenation.get("nl"));
			d.justify(140);
			equals(lines(d), NL_LINES);
			for (x in [l, d])
				for (line in x.lines)
					assert(line.width <= 140 + 1e-6, '${line.width}');
			// (manual: at spaces only)
			var m = new TextLayout(en, set, 1.25, 140);
			for (s in lines(m))
				assert(!StringTools.endsWith(s, "-"), s);
		});
		test("each break at one of the word's points, the hyphen's width counted", () -> {
			var h = Hyphenation.get("nl");
			var l = new TextLayout(nl, set, 1.25, 120, null, 0, 0, 0, -1, Math.NaN, TextLayout.BREAK_WORD, h);
			var broken = 0;
			for (line in l.lines) {
				var last = line.glyphEnd - 1;
				if (l.glyphChar(last) != 0xAD) continue;
				broken++;
				// (the word around the break)
				var a = line.end, b = line.end;
				while (a > 0 && l.text.charAt(a - 1) != " ") a--;
				while (b < l.text.length && l.text.charAt(b) != " " && l.text.charAt(b) != ".") b++;
				assert(h.points(l.text.substring(a, b)).indexOf(line.end - a) >= 0, l.text.substring(a, b) + " at " + (line.end - a));
				approx(l.glyphX(last) + l.glyphAdvance(last), line.width);
			}
			assert(broken > 0);
		});
		test("hyphens none: soft hyphens not broken at; manual: they are", () -> {
			var shy = "super\u00ADcali\u00ADfragilistic expiali\u00ADdocious";
			var none = new TextLayout(shy, set, 1.25, 60, null, 0, 0, 0, -1, Math.NaN, TextLayout.NO_HYPHENS);
			equals(lines(none), shy.split(" "));
			var manual = new TextLayout(shy, set, 1.25, 60, null, 0, 0, 0, -1, Math.NaN, 0);
			assert(lines(manual).length > 2);
			// (a word with soft hyphens: theirs, not the patterns')
			var auto = new TextLayout(shy, set, 1.25, 60, null, 0, 0, 0, -1, Math.NaN, 0, Hyphenation.get("en"));
			equals(lines(auto), lines(manual));
		});
		test("not hyphenated: capitals, numbers, URLs, addresses, short words", () -> {
			var h = Hyphenation.get("en");
			for (t in ["HYPHENATION", "hyphenation2", "https://hyphenation.example/typography", "typography@hyphenation.example", "file_hyphenation", "hyphenation.txt", "cat dog"]) {
				var l = new TextLayout(t, set, 1.25, 30, null, 0, 0, 0, -1, Math.NaN, 0, h);
				for (s in lines(l))
					assert(!StringTools.endsWith(s, "-"), t + ": " + s);
			}
			// (a capitalised word is)
			var l = new TextLayout("Hyphenation", set, 1.25, 50, null, 0, 0, 0, -1, Math.NaN, 0, h);
			equals(lines(l), ["Hy-", "phen-", "ation"]);
		});
		test("a run's own language, or none", () -> {
			var text = "hyphenation woordenboek";
			var runs = [new TextRun(12, 23, set, 1.25, 0, 0, Hyphenation.get("nl"))];
			var l = new TextLayout(text, set, 1.25, 50, runs, 0, 0, 0, -1, Math.NaN, 0, Hyphenation.get("en"));
			equals(lines(l), ["hy-", "phen-", "ation", "woor-", "den-", "boek"]);
			var off = [new TextRun(12, 23, set, 1.25, 0, 0, Hyphenator.NONE)];
			var m = new TextLayout(text, set, 1.25, 50, off, 0, 0, 0, -1, Math.NaN, 0, Hyphenation.get("en"));
			equals(lines(m), ["hy-", "phen-", "ation", "woordenboek"]);
		});
		test("wrapped again and reset: as new", () -> {
			var h = Hyphenation.get("en"), l = new TextLayout(en, set, 1.25, 300, null, 0, 0, 0, -1, Math.NaN, 0, h);
			for (w in [300.0, 90, 140, 0, Math.NaN]) {
				l.wrap(w);
				equals(lines(l), lines(new TextLayout(en, set, 1.25, w, null, 0, 0, 0, -1, Math.NaN, 0, h)), '$w');
			}
			// (the min-content width: the widest piece between points, its hyphen)
			var fresh = new TextLayout(en, set, 1.25, 0, null, 0, 0, 0, -1, Math.NaN, 0, h);
			assert(fresh.minWidth < new TextLayout(en, set, 1.25, 0).minWidth);
			approx(fresh.minWidth, fresh.width);
		});
		test("never a line wider than with hyphens manual", () -> property(c -> {
			var tag = c.draw(pick(["en-us", "nl", "de-1996", "fr"]));
			var words = sys.io.File.getContent('tests/text/fixtures/hyphenation/$tag.txt').split("\n").filter(w -> w != "");
			var n = c.draw(int(1, 12));
			return {
				tag: tag,
				text: [for (_ in 0...n) StringTools.replace(c.draw(pick(words)), "-", "")].join(" "),
				width: c.draw(float(0, 300)),
				breaking: c.draw(pick([0, TextLayout.BREAK_WORD]))
			};
		}, x -> {
			var auto = new TextLayout(x.text, set, 1.25, x.width, null, 0, 0, 0, -1, Math.NaN, x.breaking, Hyphenation.get(x.tag));
			var manual = new TextLayout(x.text, set, 1.25, x.width, null, 0, 0, 0, -1, Math.NaN, x.breaking);
			assert(auto.width <= Math.max(manual.width, x.width) + 1e-6, '${auto.width} > ${manual.width}');
			assert(auto.minWidth <= manual.minWidth + 1e-6);
			// (the text's characters all on its lines, once)
			equals(StringTools.replace([for (line in auto.lines) x.text.substring(line.start, line.end)].join(""), " ", ""), StringTools.replace(x.text, " ", ""));
		}));
	});
}

// (Inter at 16 in 140 pixels, justified)
final EN_LINES = [
	"Typographers ar-", "gue that auto-", "matic hyphenation", "improves the ap-", "pearance of justi-", "fied paragraphs", "considerably."
];

final NL_LINES = [
	"Automatische", "woordafbreking", "verbetert de ver-", "schijning van uit-", "gevulde alinea's", "in smalle kolom-", "men aanzienlijk."
];

// (the word with a hyphen at each point)
function show(word:String, points:Array<Int>):String {
	var s = new StringBuf(), k = 0;
	for (i in 0...word.length) {
		if (k < points.length && points[k] == i) {
			s.add("-");
			k++;
		}
		s.addChar(StringTools.fastCodeAt(word, i));
	}
	return s.toString();
}
