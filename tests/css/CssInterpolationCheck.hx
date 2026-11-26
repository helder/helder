import haxe.DynamicAccess;
import helder.css.CssCascade;
import helder.css.CssInterpolate;
import helder.css.CssProperties;
import helder.css.CssProperty;
import helder.css.CssShorthands;
import helder.css.CssStyle;
import helder.css.CssStyles;
import helder.css.CssTransition;
import helder.css.CssValues;
import helder.dom.Dom;
import helder.dom.Document;
import helder.dom.Element;
import helder.dom.HTMLTemplateElement;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// Interpolation against WPT's test_interpolation calls and their kin
// (fixtures/interpolation.json), as CSS Transitions runs them, natively
// (bun run test css): each case's page built as interpolation-testcommon.js
// builds it (a container, the #target-template's copy, the target and its
// parent), the from and to values computed on targets, every longhand
// interpolated (CssInterpolate, currentcolor resolved as CssTransition
// does), written (a shorthand from its longhands), and required to be the
// expected value computed on its own target, both normalized as the
// harness does (numbers to two places, tokens spaced); a discrete or not
// animatable case required not to interpolate. A case is required unless
// interpolation-manifest.json's `pending` says why.
class CssInterpolationCheck {
	static final here = "tests/css";

	static function main() {
		var bless = Sys.getEnv("BLESS") == "1", show = Sys.getEnv("SHOW") == "1";
		var data:Dynamic = haxe.Json.parse(File.getContent('$here/fixtures/interpolation.json'));
		var manifestFile = '$here/interpolation-manifest.json';
		var manifest:Dynamic = FileSystem.exists(manifestFile) ? haxe.Json.parse(File.getContent(manifestFile)) : {schema: 2, pending: {}};
		var pending = new Map<String, String>();
		var groups:DynamicAccess<Array<String>> = manifest.pending ?? {};
		for (why => keys in groups) for (k in keys) pending.set(k, why);
		pages = data.pages;
		var rows = [], seen = new Map<String, Bool>();
		for (r in (data.rows : Array<Array<Dynamic>>)) for (c in cases(r)) {
			var key = c.key, n = 2;
			while (seen.exists(key)) key = '${c.key} #${n++}';
			seen.set(key, true);
			contexts.set(key, context(r));
			rows.push({key: key, ok: c.why == null, why: c.why ?? ""});
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
		Sys.println('css interpolation: $pass of ${rows.length} cases pass, ${rows.length - pass} pending; ${failures.length} required failing, ${fixed.length} pending passing');
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
			report(pass, rows.length, by);
			return;
		}
		for (f in failures.slice(0, Std.parseInt(Sys.getEnv("LIMIT") ?? "40"))) Sys.println('  required: $f');
		for (f in fixed.slice(0, 40)) Sys.println('  passes, still pending (BLESS=1): $f');
		if (failures.length > 0 || fixed.length > 0) Sys.exit(1);
	}

	static var pages:Array<String>;
	static final contexts = new Map<String, String>();

	// (what a reason may match besides the key: the expected values, and
	// interpolate-size when the page sets it)
	static function context(r:Array<Dynamic>):String {
		var expectations:Null<Array<Array<Dynamic>>> = r[4];
		var page = pages[r[6]];
		return [for (e in expectations ?? []) Std.string(e[1])].join(" ") + (page.indexOf("interpolate-size") >= 0 ? " interpolate-size" : "");
	}

	// (a row's cases: one an expected value, or one for a value that mustn't interpolate)
	static function cases(r:Array<Dynamic>):Array<{key:String, why:Null<String>}> {
		var kind:String = r[0], prop:String = r[1], from:String = r[2], to:String = r[3], expectations:Array<Array<Dynamic>> = r[4];
		var behavior:Null<String> = r[5];
		var head = '$prop from ${from == "@neutral" ? "neutral" : '[$from]'} to [$to]';
		try {
			var points = kind == "interpolation" ? [for (e in expectations) if (Std.isOfType(e[1], String)) e] : [];
			var doc = Dom.parse(pages[r[6]]);
			var a = target(doc, prop, from), b = target(doc, prop, to);
			var expected = [for (e in points) target(doc, prop, e[1])];
			var styles = CssCascade.styles(doc, {media: {type: "screen", width: 800, height: 600}});
			var sa = styles.computed(a), sb = styles.computed(b);
			var names = CssShorthands.isShorthand(prop) ? CssShorthands.longhands(prop) : [prop];
			var ids = [for (n in names) CssProperties.of(n)].filter(p -> p != null);
			if (kind != "interpolation") {
				var moving = [for (p in ids) if (CssInterpolate.values(p, CssTransition.resolved(sa, p), CssTransition.resolved(sb, p), 0.5) != null) CssProperties.name(p)];
				// (allow-discrete or not, a value that interpolates here is wrong)
				return [{key: '$kind $head', why: moving.length == 0 ? null : 'interpolates (${moving.join(", ")})'}];
			}
			return [
				for (k in 0...points.length) {
					var at:Float = points[k][0];
					var se = styles.computed(expected[k]);
					var want = se.text(prop);
					var got = interpolated(styles, sa, sb, se, prop, names, at, behavior);
					var ok = got != null && normalize(got) == normalize(want);
					{key: 'interpolation $head at $at', why: ok ? null : got == null ? 'doesn\'t interpolate (want ${haxe.Json.stringify(want)})' : '${haxe.Json.stringify(got)}, want ${haxe.Json.stringify(want)}'};
				}
			];
		} catch (e) {
			return [{key: '$kind $head', why: 'threw ${e.message}'}];
		}
	}

	// (each longhand's interpolated value written, a shorthand from them; a
	// discrete one as a transition leaves it: its end, or flipped halfway with allow-discrete)
	static function interpolated(styles:CssStyles, sa:CssStyle, sb:CssStyle, se:CssStyle, prop:String, names:Array<String>, at:Float,
			behavior:Null<String>):Null<String> {
		var texts = new Map<String, String>();
		for (n in names) {
			var p = CssProperties.of(n);
			if (p == null) {
				texts.set(n, se.text(n));
				continue;
			}
			var x = CssTransition.resolved(sa, p), y = CssTransition.resolved(sb, p);
			var v = CssInterpolate.values(p, x, y, at);
			if (v == null) {
				if (CssValues.written(n, x, @:privateAccess se.context()) == CssValues.written(n, y, @:privateAccess se.context())) v = y;
				else if (behavior == "allow-discrete") v = CssInterpolate.discrete(p, x, y, at)
				else return null;
			}
			texts.set(n, CssValues.written(n, v, @:privateAccess se.context()));
		}
		if (!CssShorthands.isShorthand(prop)) return texts[prop];
		var initials = [for (n in names) n => @:privateAccess styles.initialText(n, se)];
		return CssShorthands.serialize(prop, texts, true, initials);
	}

	// (a target as the harness makes it: a container, the template's copy,
	// the .target in it (else the container), its parent a .parent; the
	// value on its style, none for neutral)
	static function target(doc:Document, prop:String, value:String):Element {
		var container = doc.createElement("div");
		container.setAttribute("class", "container");
		doc.body.append(container);
		var template = doc.getElementById("target-template");
		if (template != null && Std.isOfType(template, HTMLTemplateElement)) container.append((cast template : HTMLTemplateElement).content.cloneNode(true));
		var t = first(container, "target") ?? container;
		t.setAttribute("class", ((t.getAttribute("class") ?? "") + " target").trim());
		if (t.parentElement != null) t.parentElement.setAttribute("class", ((t.parentElement.getAttribute("class") ?? "") + " parent").trim());
		if (value != "@neutral") t.setAttribute("style", '$prop: $value');
		return t;
	}

	static function first(el:Element, cls:String):Null<Element> {
		var c = el.firstElementChild;
		while (c != null) {
			if ((" " + (c.getAttribute("class") ?? "") + " ").indexOf(' $cls ') >= 0) return c;
			var d = first(c, cls);
			if (d != null) return d;
			c = c.nextElementSibling;
		}
		return null;
	}

	// (the harness's normalizeValue: numbers to two places, a space after each token)
	static function normalize(v:String):String {
		var rounded = ~/-?\d*\.\d+(e-?\d+)?/g.map(v, m -> {
			var n = Std.parseFloat(m.matched(0));
			var s = Std.string(Math.round(n * 100) / 100);
			if (s == "-0") s = "0";
			s;
		});
		var spaced = ~/([\w\d.]+|[^\s])/g.map(rounded, m -> m.matched(1) + " ");
		return ~/\s+/g.replace(spaced, " ");
	}

	static function why(key:String):String {
		var text = key + " " + (contexts.get(key) ?? "");
		for (r in REASONS) if (r.re.match(text)) return r.why;
		return "values: differs";
	}

	static final REASONS:Array<{re:EReg, why:String}> = [
		{re: ~/calc-size|interpolate-size/, why: "sizes: calc-size() and interpolate-size not yet (Values 5)"},
		{re: ~/\b(sign|progress|random)\(/, why: "math functions: sign(), progress() and random() not resolved in computed values yet"},
		{
			re: ~/3d|perspective|rotate[xyz]\(|translatez|scalez|^interpolation rotate .*(\[|\s)(-?[\d.]+ ){3}|^interpolation rotate .*\[[xyz] /i,
			why: "transforms: 3D functions, axes and perspective not yet (2D only)"
		},
		{re: ~/^\S+ grid-template-/, why: "grid: track lists not interpolated yet (Grid 1 §7.2.5)"},
		{re: ~/^interpolation (width|left|transform-origin) /, why: "resolved values: getComputedStyle's px are layout's, and this check has none"},
		{re: ~/^interpolation list-style-image /, why: "images: list-style-image is discrete (Lists 3); the test wants it to transition, flipping halfway as Chrome's cross-fade does"},
		{re: ~/^interpolation clip /, why: "clip: rect() without commas, CSS 2's form the expected values use, not parsed"},
		{re: ~/^interpolation display from \[none\] to \[flex\]/, why: "display: expects an animation's flip (none until p > 0); without allow-discrete no transition starts"},
		{re: ~/^discrete height from neutral to \[100px\]/, why: "page: its script sets height: auto before this case, so neutral isn't the page's 10px"},
		{re: ~/^interpolation background-color from \[currentcolor\]/, why: "colours: one channel off by one, a browser's 8-bit premultiplied rounding"}
	];

	static function report(pass:Int, total:Int, pending:Map<String, Array<String>>) {
		var b = new StringBuf();
		b.add('$pass of $total cases pass.\n\n| Pending because | Cases |\n| --- | --- |\n');
		var ws = [for (w in pending.keys()) w];
		ws.sort((x, y) -> pending[y].length - pending[x].length != 0 ? pending[y].length - pending[x].length : Reflect.compare(x, y));
		for (w in ws) b.add('| $w | ${pending[w].length} |\n');
		var readme = File.getContent('$here/README.md');
		var start = readme.indexOf("<!-- interpolation -->"), end = readme.indexOf("<!-- /interpolation -->");
		if (start < 0 || end < 0) return;
		File.saveContent('$here/README.md', readme.substr(0, start) + "<!-- interpolation -->\n" + b.toString() + readme.substr(end));
	}
}
