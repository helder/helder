import haxe.DynamicAccess;
import helder.css.CssCascade;
import helder.css.CssCounterDescriptors;
import helder.css.CssCounters;
import helder.css.CssStyles;
import helder.dom.Dom;
import helder.dom.Element;
import helder.dom.Node;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// Counters, counter styles and generated content against WPT's
// css-counter-styles and css-lists reftests that read statically
// (fixtures/counters.json), natively (bun run test css): both pages of a
// reftest cascaded, walked as the box tree will walk them (CssCounters:
// each block a line of its markers, ::before, text and ::after), and their
// lines required the same, unless counters-manifest.json's `pending`
// says why (a pending case that passes fails too, until BLESS=1); and
// @counter-style's descriptors' syntax calls, valid ones written as WPT
// expects.
class CssCountersCheck {
	static final here = "tests/css";

	static function main() {
		var bless = Sys.getEnv("BLESS") == "1", show = Sys.getEnv("SHOW") == "1";
		var data:Dynamic = haxe.Json.parse(File.getContent('$here/fixtures/counters.json'));
		var manifestFile = '$here/counters-manifest.json';
		var manifest:Dynamic = FileSystem.exists(manifestFile) ? haxe.Json.parse(File.getContent(manifestFile)) : {schema: 2, pending: {}};
		var pending = new Map<String, String>();
		var groups:DynamicAccess<Array<String>> = manifest.pending ?? {};
		for (why => keys in groups) for (k in keys) pending.set(k, why);
		sheets = data.sheets;
		var tests:Array<Array<String>> = data.tests;
		var rows = [];
		for (p in (data.pairs : Array<Dynamic>)) {
			var key = 'reftest ${tests[p.file][0]}';
			var why = try compare(p.test, p.ref, tests[p.file][0]) catch (e) 'threw ${e.message}';
			rows.push({key: key, ok: why == null, why: why ?? ""});
		}
		for (r in (data.syntax : Array<Array<Dynamic>>)) {
			var kind:String = r[0];
			if (kind == "name") continue;
			var descriptor:String = r[1], value:String = r[2];
			var got = CssCounterDescriptors.text(descriptor, helder.css.Css.values(value));
			var key = '$kind $descriptor: $value';
			if (kind == "valid") {
				var want:String = r.length == 5 && r[3] != null ? r[3] : value;
				rows.push({key: key, ok: got == want, why: got == want ? "" : 'written ${haxe.Json.stringify(got)}, want ${haxe.Json.stringify(want)}'});
			} else rows.push({key: key, ok: got == null, why: got == null ? "" : 'accepted as ${haxe.Json.stringify(got)}'});
		}
		var failures = [], fixed = [], next = new Map<String, String>(), pass = 0;
		for (r in rows) {
			var reason = pending.get(r.key);
			if (r.ok) {
				pass++;
				if (reason != null) fixed.push(r.key);
			} else {
				next.set(r.key, reason ?? why(r.key));
				if (reason == null) failures.push('${r.key}: ${r.why}');
				if (show) Sys.println('  ${r.key}: ${r.why}');
			}
		}
		var statuses = new Map<String, Int>();
		for (t in tests) {
			var k = ~/: \d+$/.replace(t[2], "");
			statuses.set(k, (statuses.get(k) ?? 0) + 1);
		}
		Sys.println('css counters: $pass of ${rows.length} cases pass, ${rows.length - pass} pending, from ${tests.length} tests; ${failures.length} required failing, ${fixed.length} pending passing');
		if (bless) {
			var by = new Map<String, Array<String>>();
			for (k => w in next) {
				if (!by.exists(w)) by.set(w, []);
				by[w].push(k);
			}
			var b = new StringBuf();
			b.add('{\n\t"schema": 2,\n\t"pending": {\n');
			var ws = [for (w in by.keys()) w];
			ws.sort(Reflect.compare);
			for (i in 0...ws.length) {
				var ks = by[ws[i]];
				ks.sort(Reflect.compare);
				b.add('\t\t${haxe.Json.stringify(ws[i])}: [\n');
				for (j in 0...ks.length) b.add('\t\t\t${haxe.Json.stringify(ks[j])}${j + 1 < ks.length ? "," : ""}\n');
				b.add('\t\t]${i + 1 < ws.length ? "," : ""}\n');
			}
			b.add('\t}\n}\n');
			File.saveContent(manifestFile, b.toString());
			report(pass, rows.length, statuses, by);
			return;
		}
		for (f in failures.slice(0, 40)) Sys.println('  required: $f');
		for (f in fixed.slice(0, 40)) Sys.println('  passes, still pending (BLESS=1): $f');
		if (failures.length > 0 || fixed.length > 0) Sys.exit(1);
	}

	static var sheets:DynamicAccess<String>;

	// (why a case fails, by its test: the stage that clears it, or what WPT expects that we don't follow)
	static function why(key:String):String {
		for (r in REASONS) if (r.re.match(key)) return r.why;
		return "counters: differs";
	}

	static final REASONS = [
		{
			re: ~/chinese|japanese|korean|cjk-ideographic/,
			why: "values: Counter Styles 3 §7.1.2's optional extended CJK forms past 9999 (万, 億...), and values past 32 bits: counters here are 32-bit, as browsers' are"
		},
		{
			re: ~/reversed-00[79]/,
			why: "counters: a reversed() start where a nested reversed list's scope takes the outer list's later items: WPT's numbers are neither Lists 3 §4.4.2's algorithm as written (followed) nor HTML's ordinal values"
		},
		{
			re: ~/inline-list|inline-block-list|list-and-block-in-inline|list-marker-alignment|list-marker-paint-order/,
			why: "layout: lines are layout's (inline list items and their markers, a block inside an inline, where a marker paints)"
		},
		{
			re: ~/list-item-definition|nested-marker/,
			why: "box tree: ::before and ::after that are list items, with markers of their own (CSS Pseudo 4's nested pseudo-elements)"
		},
		{re: ~/disclosure-line-height/, why: "paint: the test is about the room a marker's line gives it; its reference draws the other triangle"},
		{re: ~/persian\/css3-counter-styles-105/, why: "layout: an rtl marker's suffix, placed by the bidi algorithm"}
	];

	// (null: the same lines; else the first that differs)
	static function compare(test:String, ref:String, path:String):Null<String> {
		var a = lines(test, path), b = lines(ref, path);
		// (SHOW_LINES=part of a path: both pages' lines)
		var only = Sys.getEnv("SHOW_LINES");
		if (only != null && path.indexOf(only) >= 0) for (k in 0...Std.int(Math.max(a.length, b.length))) Sys.println('    ${k + 1}: ${a[k]} | ${b[k]}');
		for (k in 0...Std.int(Math.max(a.length, b.length))) if (a[k] != b[k])
			return 'line ${k + 1}: ${haxe.Json.stringify(a[k])}, the reference ${haxe.Json.stringify(b[k])}';
		return null;
	}

	// (the page's text as its boxes would hold it: a line a block)
	static function lines(html:String, path:String):Array<String> {
		var doc = Dom.parse(html);
		var styles = CssCascade.styles(doc, {
			media: {type: "screen", width: 800, height: 600},
			url: 'http://wpt/$path',
			load: url -> url.startsWith("http://wpt/") ? sheets.get(url.substr("http://wpt/".length)) : null
		});
		var counters = new CssCounters(styles);
		var out = [], line = new StringBuf();
		function flush() {
			// (no-break spaces as spaces, a BOM gone)
			var t = ~/\s+/g.replace(line.toString().replace(String.fromCharCode(0xA0), " ").replace(String.fromCharCode(0xFEFF), ""), " ").trim();
			if (t != "") out.push(t);
			line = new StringBuf();
		}
		function generated(el:Element, pseudo:String) {
			if (styles.computed(el, pseudo).generated() == null) return;
			counters.enter(el, pseudo);
			line.add(text(counters.content(el, pseudo)));
			counters.exit(el, pseudo);
		}
		function walk(el:Element) {
			var s = styles.computed(el);
			var d = s.box.display;
			if (d.outer == None) return;
			var block = d.outer != Inline && d.outer != Contents;
			if (block) flush();
			counters.enter(el);
			if (d.listItem) {
				counters.enter(el, "marker");
				line.add(text(counters.marker(el)));
				counters.exit(el, "marker");
			}
			generated(el, "before");
			var n = el.firstChild;
			while (n != null) {
				if (n.nodeType == Node.TEXT_NODE) line.add(n.nodeValue) else if (n.nodeType == Node.ELEMENT_NODE) {
					var e:Element = cast n;
					if (e.localName == "br") flush() else walk(e);
				}
				n = n.nextSibling;
			}
			generated(el, "after");
			counters.exit(el);
			if (block) flush();
		}
		walk(doc.documentElement);
		flush();
		return out;
	}

	static function text(parts:Null<Array<CssGeneratedPart>>):String
		return parts == null ? "" : [for (p in parts) switch p {
			case Text(t): t;
			case Image(_): "[image]";
			case _: "[other]";
		}].join("");

	static function report(pass:Int, total:Int, statuses:Map<String, Int>, pending:Map<String, Array<String>>) {
		var b = new StringBuf();
		b.add('$pass of $total cases pass.\n\n| Pending because | Cases |\n| --- | --- |\n');
		var ws = [for (w in pending.keys()) w];
		ws.sort((x, y) -> pending[y].length - pending[x].length != 0 ? pending[y].length - pending[x].length : Reflect.compare(x, y));
		for (w in ws) b.add('| $w | ${pending[w].length} |\n');
		b.add('\nThe tests, by what became of them:\n\n| Status | Tests |\n| --- | --- |\n');
		var ks = [for (k in statuses.keys()) k];
		ks.sort((x, y) -> statuses[y] - statuses[x] != 0 ? statuses[y] - statuses[x] : Reflect.compare(x, y));
		for (k in ks) b.add('| $k | ${statuses[k]} |\n');
		var readme = File.getContent('$here/README.md');
		var start = readme.indexOf("<!-- counters -->"), end = readme.indexOf("<!-- /counters -->");
		if (start < 0 || end < 0) return;
		File.saveContent('$here/README.md', readme.substr(0, start) + "<!-- counters -->\n" + b.toString() + readme.substr(end));
	}
}
