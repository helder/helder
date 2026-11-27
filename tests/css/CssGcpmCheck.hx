import haxe.DynamicAccess;
import helder.css.CssCascade;
import helder.css.CssCounters;
import helder.css.CssItems;
import helder.css.CssRunning;
import helder.css.CssStyles;
import helder.dom.Dom;
import helder.dom.Element;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// GCPM's generated content against WPT's css-gcpm tests (fixtures/gcpm.json),
// read through the CSS side's API, natively (bun run test css): each page
// walked as the box tree walks it (CssCounters: each element, its
// ::before, children, ::after), its pages where its forced breaks are
// (break-before, break-after: the tests' pages are short), string-set's
// assignments kept page by page (CssRunning: an element at a page's start
// when nothing shown comes before it there), each page's margin boxes'
// content resolved (string(), counter(page)), and what the test's own
// words say passes checked: each page's running heads, a leader's fill.
// A case is required unless gcpm-manifest.json's `pending` says why
// (stage paged: what needs the paged host's layout).
class CssGcpmCheck {
	static final here = "tests/css";
	static final BOXES = [
		"top-left-corner", "top-left", "top-center", "top-right", "top-right-corner", "bottom-left-corner", "bottom-left", "bottom-center", "bottom-right",
		"bottom-right-corner", "left-top", "left-middle", "left-bottom", "right-top", "right-middle", "right-bottom"
	];

	static function main() {
		var bless = Sys.getEnv("BLESS") == "1";
		var data:Dynamic = haxe.Json.parse(File.getContent('$here/fixtures/gcpm.json'));
		var manifestFile = '$here/gcpm-manifest.json';
		var manifest:Dynamic = FileSystem.exists(manifestFile) ? haxe.Json.parse(File.getContent(manifestFile)) : {schema: 1, pending: {}};
		var pending = new Map<String, String>();
		var groups:DynamicAccess<Array<String>> = manifest.pending ?? {};
		for (why => keys in groups) for (k in keys) pending.set(k, why);
		var pass = 0, failures = [], fixed = [], next = new Map<String, String>();
		var tests:Array<Dynamic> = data.tests;
		for (t in tests) {
			var key:String = t.file;
			var why = check(t.page, t.expect);
			var reason = pending.get(key);
			if (why == null) {
				pass++;
				if (reason != null) fixed.push(key);
			} else {
				next.set(key, reason ?? why);
				if (reason == null) failures.push('$key: $why');
				if (Sys.getEnv("SHOW") == "1") Sys.println('  $key: $why');
			}
		}
		Sys.println('css gcpm: $pass of ${tests.length} tests pass, ${tests.length - pass} pending; ${failures.length} required failing, ${fixed.length} pending passing');
		if (bless) {
			var by = new Map<String, Array<String>>();
			for (k => w in next) {
				if (!by.exists(w)) by.set(w, []);
				by[w].push(k);
			}
			var ws = [for (w in by.keys()) w];
			ws.sort(Reflect.compare);
			var b = new StringBuf();
			b.add('{\n\t"schema": 1,\n\t"pending": {\n');
			for (i in 0...ws.length) {
				var ks = by[ws[i]];
				ks.sort(Reflect.compare);
				b.add('\t\t${haxe.Json.stringify(ws[i])}: [\n');
				for (j in 0...ks.length) b.add('\t\t\t${haxe.Json.stringify(ks[j])}${j + 1 < ks.length ? "," : ""}\n');
				b.add('\t\t]${i + 1 < ws.length ? "," : ""}\n');
			}
			b.add('\t}\n}\n');
			File.saveContent(manifestFile, b.toString());
			return;
		}
		for (f in failures) Sys.println('  required: $f');
		for (f in fixed) Sys.println('  passes, still pending (BLESS=1): $f');
		if (failures.length > 0 || fixed.length > 0) Sys.exit(1);
	}

	// (null when the test's words hold on its pages; else why not)
	static function check(page:String, expect:String):Null<String> {
		var doc = Dom.parse(page);
		var styles = CssCascade.styles(doc, {media: {type: "print", width: 794, height: 1123}});
		var leaders = [];
		// (twice: the first walk counts the pages, for counter(pages))
		var count = 0, heads:Array<Array<String>> = [];
		for (pass in 0...2) {
			var counters = new CssCounters(styles);
			var strings = new CssRunning<String>();
			var index = 0, fresh = true, breakNext = false;
			heads = [];
			function next() {
				if (index > 0) heads.push(margins(styles, index, strings));
				index++;
				strings.page();
				fresh = true;
				breakNext = false;
			}
			next();
			function walk(el:Element) {
				var s = styles.computed(el);
				if ((breakNext || forced(s.text("break-before"))) && !fresh) next();
				counters.enter(el);
				for (v in counters.strings(el, index, count)) strings.assign(v.name, v.value, fresh);
				var shown = s.box.display.outer != None;
				for (p in ["before", "after"]) if (shown && styles.computed(el, p).generated() != null) {
					counters.enter(el, p);
					for (part in counters.content(el, p) ?? []) switch part {
						case Leader(fill): if (pass == 0) leaders.push(fill);
						case Text(t) if (t != ""): fresh = false;
						case _:
					}
					counters.exit(el, p);
				}
				var c = el.firstChild;
				while (c != null) {
					switch Std.downcast(c, Element) {
						case null: if (shown && StringTools.trim(c.nodeValue ?? "") != "") fresh = false;
						case e: walk(e);
					}
					c = c.nextSibling;
				}
				counters.exit(el);
				if (forced(s.text("break-after"))) breakNext = true;
			}
			walk(doc.documentElement);
			heads.push(margins(styles, index, strings));
			count = heads.length;
		}
		if (~/leader|underscores|~ characters/i.match(expect)) {
			var want = ~/dotted/.match(expect) ? ". " : ~/underscores/.match(expect) ? "_" : ~/~/.match(expect) ? "~" : null;
			return want != null && Lambda.exists(leaders, l -> l.indexOf(want) >= 0) ? null : 'leaders ${haxe.Json.stringify(leaders)}, want ${haxe.Json.stringify(want)}';
		}
		// (each clause: its page, one, two, three, all other pages, else the first; a quoted text, or empty)
		var wants = clauses(expect);
		if (Sys.getEnv("SHOW") == "1") Sys.println('    pages ${haxe.Json.stringify(heads)}; want ${haxe.Json.stringify(wants)}');
		if (wants.length == 0) return 'no running head text in its words: ${expect}';
		for (w in wants) {
			var pages = w.page == 0 ? [for (k in 2...heads.length + 1) k] : [w.page];
			for (p in pages) {
				var texts = p <= heads.length ? heads[p - 1].filter(t -> t != "") : [];
				var ok = w.text == null ? texts.length == 0 : texts.contains(w.text);
				if (!ok) return 'page $p\'s running heads ${haxe.Json.stringify(texts)}, want ${w.text == null ? "none" : haxe.Json.stringify(w.text)}';
			}
		}
		return null;
	}

	static function forced(v:String):Bool
		return switch v {
			case "page" | "always" | "left" | "right" | "recto" | "verso": true;
			case _: false;
		}

	// (what the words want: a page (0: all but the first) and its running head's text, null for none)
	static function clauses(expect:String):Array<{page:Int, text:Null<String>}> {
		var out = [];
		for (clause in ~/[.]\s+|,\s*and\s+|[”"]\s+(?=On |Running |“)/g.split(expect)) {
			var page = ~/all other pages/.match(clause) ? 0 : ~/page two/.match(clause) ? 2 : ~/page three/.match(clause) ? 3 : 1;
			var quoted = ~/[“"]([^”"]+)/;
			if (quoted.match(clause)) out.push({page: page, text: quoted.matched(1)});
			else if (~/\b(empty|omitted)\b/.match(clause)) out.push({page: page, text: null});
		}
		return out;
	}

	// (a page's margin boxes' contents)
	static function margins(styles:CssStyles, index:Int, strings:CssRunning<String>):Array<String>
		return [for (box in BOXES) margin(styles, index, box, strings)].filter(t -> t != null);

	// (a margin box's content on a page, numbered from 1 (its index from 0, :first's 0; page 2 a left one):
	// strings, string() as the page has it, the page counter)
	static function margin(styles:CssStyles, index:Int, box:String, strings:CssRunning<String>):Null<String> {
		var s = styles.marginBoxStyle(index - 1, null, index % 2 == 0, false, box);
		var items = s == null ? null : CssItems.content(s.terms(Content));
		if (items == null) return null;
		var b = new StringBuf();
		for (i in items) switch i {
			case Text(t): b.add(t);
			case StringValue(name, which): b.add(strings.value(name, which) ?? "");
			case Counter("page", _): b.add(Std.string(index));
			case _:
		}
		return b.toString();
	}
}
