import haxe.DynamicAccess;
import helder.css.CssCascade;
import helder.css.CssMatcher;
import helder.css.CssSelector;
import helder.css.CssStyles;
import helder.dom.Dom;
import helder.dom.Document;
import helder.dom.Element;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// helder.css's cascade against WPT's css-cascade and css-variables tests
// that read statically (fixtures/cascade.json), natively (bun run test
// css): each page parsed by helder.dom and cascaded as WPT's harness shows
// it (a screen of 800 by 600), each case required to pass unless
// cascade-manifest.json's `pending` says why (tagged with the stage that
// clears it); a pending case that passes fails too, until BLESS=1. The
// tests not read are counted by why (cascade.json's statuses).
class CssCascadeCheck {
	static final here = "tests/css";

	static function main() {
		var bless = Sys.getEnv("BLESS") == "1", show = Sys.getEnv("SHOW") == "1";
		var data:Dynamic = haxe.Json.parse(File.getContent('$here/fixtures/cascade.json'));
		var manifestFile = '$here/cascade-manifest.json';
		var manifest:Dynamic = FileSystem.exists(manifestFile) ? haxe.Json.parse(File.getContent(manifestFile)) : {schema: 2, pending: {}};
		var pending = new Map<String, String>();
		var groups:DynamicAccess<Array<String>> = manifest.pending ?? {};
		for (why => keys in groups) for (k in keys) pending.set(k, why);

		pages = data.pages;
		var cases:Array<Dynamic> = data.cases, tests:Array<Array<String>> = data.tests;
		var rows = [], seen = new Map<String, Int>();
		for (c in cases) {
			var key = switch c.kind {
				case "cycles": 'cycles ${(c.declarations : Array<String>).join("; ")}';
				case "crash": 'crash page ${c.page}';
				case _: '${c.kind} page ${c.page}: ${c.a.el} ${c.a.property} ${c.b.value != null ? haxe.Json.stringify(c.b.value) : c.b.el + " " + c.b.property}';
			}
			var n = seen.get(key) ?? 0;
			seen.set(key, n + 1);
			if (n > 0) key += ' #${n + 1}';
			var got = try run(c) catch (e) 'threw ${e.message}';
			// (a case that fails on a page past checkpoint 1 is skipped, with why; one that passes is required)
			rows.push({key: key, ok: got == null, why: got ?? "", skip: got == null ? null : scope(pages[c.page])});
		}
		var failures = [], fixed = [], next = new Map<String, String>(), pass = 0;
		var skipped = new Map<String, Int>();
		for (r in rows) {
			var reason = pending.get(r.key);
			if (r.skip != null) {
				skipped.set(r.skip, (skipped.get(r.skip) ?? 0) + 1);
				continue;
			}
			if (r.ok) {
				pass++;
				if (reason != null) fixed.push(r.key);
			} else {
				next.set(r.key, reason ?? 'cascade: differs');
				if (reason == null) failures.push('${r.key}: ${r.why}');
				if (show) Sys.println('  ${r.key}: ${r.why}');
			}
		}
		var statuses = new Map<String, Int>();
		for (t in tests) {
			var k = ~/: \d+$/.replace(t[2], "");
			statuses.set(k, (statuses.get(k) ?? 0) + 1);
		}
		var skips = Lambda.fold(skipped, (n, a) -> n + a, 0);
		Sys.println('css cascade: ${pass} of ${rows.length - skips} cases pass, ${rows.length - skips - pass} pending, $skips skipped, from ${statuses.get("read") ?? 0} of ${tests.length} tests read; '
			+ '${failures.length} required failing, ${fixed.length} pending passing');
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
			report(pass, rows.length - skips, statuses, skipped);
			return;
		}
		for (f in failures.slice(0, 40)) Sys.println('  required: $f');
		for (f in fixed.slice(0, 40)) Sys.println('  passes, still pending (BLESS=1): $f');
		if (failures.length > 0 || fixed.length > 0) Sys.exit(1);
	}

	static var pages:Array<String>;
	static final styled = new Map<Int, {doc:Document, styles:CssStyles}>();

	// (a page parsed and cascaded; extra: what to change first, then not kept)
	static function page(n:Int, ?extra:Element->Void):{doc:Document, styles:CssStyles} {
		if (extra == null && styled.exists(n)) return styled[n];
		var doc = Dom.parse(pages[n]);
		if (extra != null) extra(doc.documentElement);
		var s = {doc: doc, styles: CssCascade.styles(doc, {media: {type: "screen", width: 800, height: 600}})};
		if (extra == null) styled.set(n, s);
		return s;
	}

	// null when the case passes, else what differs
	static function run(c:Dynamic):Null<String> {
		switch c.kind {
			case "crash":
				var p = page(c.page);
				for (el in all(p.doc.documentElement)) for (prop in ["display", "color", "font-size", "margin-top", "width", "content"]) p.styles.computed(el).text(prop);
				return null;
			case "cycles":
				// (variable-cycles' helper: an element of these declarations in #main)
				var declarations:Array<String> = c.declarations.concat(["--sanity:valid"]);
				var made:Null<Element> = null;
				var p = page(c.page, root -> {
					var main = root.ownerDocument.getElementById("main") ?? root.ownerDocument.body;
					made = root.ownerDocument.createElement("div");
					made.setAttribute("style", declarations.join(";"));
					main.append(made);
				});
				var s = p.styles.computed(made);
				var wrong = [];
				for (v in (c.invalid : Array<String>)) if (s.text(v) != "") wrong.push('$v: ${haxe.Json.stringify(s.text(v))}');
				for (v in (c.valid : Array<String>)) if (s.text(v) == "") wrong.push('$v: ""');
				if (s.text("--sanity") != "valid") wrong.push("--sanity");
				return wrong.length == 0 ? null : wrong.join(", ");
			case kind:
				var p = page(c.page);
				var as = values(p, c.a), bs:Array<String> = c.b.value != null ? [c.b.value] : values(p, c.b);
				if (as.length == 0) return 'no element ${c.a.el}';
				for (k in 0...as.length) {
					var b = bs[bs.length == 1 ? 0 : k];
					if ((as[k] == b) != (kind == "equals")) return '${c.a.el} ${c.a.property}: ${haxe.Json.stringify(as[k])} (want ${kind == "equals" ? "" : "not "}${haxe.Json.stringify(b)})';
				}
				return null;
		}
	}

	static function values(p:{doc:Document, styles:CssStyles}, ref:Dynamic):Array<String> {
		var el:String = ref.el;
		var els = if (el == "@root") [p.doc.documentElement] else if (el == "@body") [p.doc.body] else if (el.startsWith("@all:"))
			CssMatcher.query(CssSelector.parse(el.substr(5)), p.doc) else [p.doc.getElementById(el)];
		return [for (e in els) if (e != null) p.styles.computed(e).text(ref.property)];
	}

	static function all(root:Element):Array<Element> {
		var out = [root];
		for (k in 0...root.children.length) for (e in all(root.children.item(k))) out.push(e);
		return out;
	}

	// (a case out of scope by its page)
	static function scope(html:String):Null<String> {
		if (~/revert-rule/.match(html)) return "out of scope: Cascade 6's revert-rule";
		if (~/@scope\b/.match(html)) return "out of scope: @scope (deferred)";
		if (~/@container\b/.match(html)) return "out of scope: @container (deferred)";
		if (~/@keyframes|animation:/.match(html)) return "out of scope: animation (a page is still)";
		if (~/@property\b/.match(html)) return "out of scope: registered custom properties (@property)";
		if (~/:host|::slotted|shadowroot/.match(html)) return "out of scope: shadow trees";
		if (~/\bident\(/.match(html)) return "out of scope: Values 5's ident()";
		if (~/margin-(block|inline)|padding-(block|inline)|inset-(block|inline)|writing-mode/.match(html)) return "out of scope: logical properties and writing modes (deferred)";
		return null;
	}

	static function report(pass:Int, total:Int, statuses:Map<String, Int>, skipped:Map<String, Int>) {
		var b = new StringBuf();
		b.add('$pass of $total cases pass; skipped (their page is past checkpoint 1):\n\n| Skipped because | Cases |\n| --- | --- |\n');
		var sk = [for (k in skipped.keys()) k];
		sk.sort((x, y) -> skipped[y] - skipped[x] != 0 ? skipped[y] - skipped[x] : Reflect.compare(x, y));
		for (k in sk) b.add('| $k | ${skipped[k]} |\n');
		b.add('\nThe tests, by what became of them:\n\n| Status | Tests |\n| --- | --- |\n');
		var ks = [for (k in statuses.keys()) k];
		ks.sort((x, y) -> statuses[y] - statuses[x] != 0 ? statuses[y] - statuses[x] : Reflect.compare(x, y));
		for (k in ks) b.add('| $k | ${statuses[k]} |\n');
		var readme = File.getContent('$here/README.md');
		var start = readme.indexOf("<!-- cascade -->"), end = readme.indexOf("<!-- /cascade -->");
		if (start < 0 || end < 0) return;
		File.saveContent('$here/README.md', readme.substr(0, start) + "<!-- cascade -->\n" + b.toString() + readme.substr(end));
	}
}
