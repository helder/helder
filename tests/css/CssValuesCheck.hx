import haxe.DynamicAccess;
import helder.css.CssCascade;
import helder.css.CssGrammars;
import helder.dom.Dom;
import helder.css.CssShorthands;
import helder.css.CssTerm;
import helder.css.CssValues;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// helder.css's values against WPT's cases (fixtures/values.json) and
// css-parsing-tests' colours (fixtures/colors), natively (bun run test css).
// values-manifest.json sorts the cases that don't pass:
//
// - skip: not checkpoint 1's to pass (out of scope: Color 5, drafts; an
//   outdated fixture: css-parsing-tests where it and WPT disagree), each
//   group with why; run, not gated;
// - pending: our gaps, each group tagged with the stage that clears it
//   (values: this layer; cascade; layout); a pending case that passes
//   fails the run too, until BLESS=1 requires it;
// - every other case is required to pass.
//
// BLESS=1 writes the manifest from the results and the counts in
// tests/css/README.md; SHOW=1 prints each case that doesn't pass.
//
// valid: the value parses and serializes to the expected text (any of a
// list; numbers within the row's epsilon); invalid: it doesn't parse;
// computed: it parses and computes to the expected text (no layout, the
// default context: 16px fonts, an 800x600 viewport, black text); inherits:
// the table's inherited flag, the initial value computed; colors: the
// colour computed, or rejected where the expected is null.
class CssValuesCheck {
	// (each property's module, CssData's: the run time's table has none)
	static final MODULES = [for (p in helder.css.CssData.properties) p.name => p.module];
	// (and each one's initial value as webref writes it, prose too)
	static final INITIALS = [for (p in helder.css.CssData.properties) p.name => p.initial];

	static final here = "tests/css";
	static final rows = new Array<{key:String, module:String, ok:Bool, why:String, want:String, skip:Null<String>}>();
	static var want = "";

	static function main() {
		var bless = Sys.getEnv("BLESS") == "1", show = Sys.getEnv("SHOW") == "1";
		var manifestFile = '$here/values-manifest.json';
		var manifest:Dynamic = FileSystem.exists(manifestFile) ? haxe.Json.parse(File.getContent(manifestFile)) : {schema: 2, skip: {}, pending: {}};
		// (the manifest groups its cases by why; a case's own detail is the check's, SHOW=1)
		var pending = new Map<String, String>();
		var groups:DynamicAccess<Array<String>> = manifest.pending ?? {};
		for (why => keys in groups) for (k in keys) pending.set(k, why);

		var values:Dynamic = haxe.Json.parse(File.getContent('$here/fixtures/values.json'));
		documents = (haxe.Json.parse(File.getContent('$here/fixtures/documents.json')) : Dynamic).documents;
		var props:DynamicAccess<DynamicAccess<Array<Array<Dynamic>>>> = values.properties;
		var names = props.keys();
		names.sort(Reflect.compare);
		for (name in names) {
			var module = MODULES.get(name) ?? "css-variables-1";
			var kinds = props.get(name);
			for (r in kinds.get("valid") ?? []) valid(name, module, r);
			for (r in kinds.get("invalid") ?? []) invalid(name, module, r);
			for (r in kinds.get("computed") ?? []) computed(name, module, r);
			for (r in kinds.get("shorthand") ?? []) shorthand(name, module, r);
			for (r in kinds.get("inherits") ?? []) inherits(name, module, r);
		}
		var colorFiles = [for (f in FileSystem.readDirectory('$here/fixtures/colors')) if (f.endsWith(".json")) f];
		colorFiles.sort(Reflect.compare);
		for (f in colorFiles) {
			var pairs:Array<Dynamic> = haxe.Json.parse(File.getContent('$here/fixtures/colors/$f'));
			var k = 0;
			while (k + 1 < pairs.length) {
				color(f, pairs[k], pairs[k + 1]);
				k += 2;
			}
		}

		var failures = [], fixed = [], nextPending = new Map<String, String>(), nextSkip = new Map<String, String>();
		var counts = new Map<String, {pass:Int, pending:Int, skip:Int}>();
		for (r in rows) {
			var c = counts.get(r.module) ?? {pass: 0, pending: 0, skip: 0};
			counts.set(r.module, c);
			var skip = r.skip ?? (r.ok ? null : outdated(r.why));
			if (skip != null) {
				c.skip++;
				nextSkip.set(r.key, skip);
			} else if (r.ok) {
				c.pass++;
				if (pending.exists(r.key)) fixed.push(r.key);
			} else {
				c.pending++;
				nextPending.set(r.key, r.why.split("; ")[0]);
				if (!pending.exists(r.key)) failures.push('${r.key}: ${r.why}');
			}
			if (show && !r.ok) Sys.println('  ${r.key}: ${skip ?? r.why}${r.want != "" ? " (want " + r.want + ")" : ""}');
		}
		var t = totals(counts);
		Sys.println('css values: ${t.pass} required pass of ${t.pass + t.pending} (${t.pending} pending, ${t.skip} skipped); ${failures.length} required failing, ${fixed.length} pending passing');
		if (bless) {
			File.saveContent(manifestFile, '{\n\t"schema": 2,\n\t"skip": ${groupsText(nextSkip)},\n\t"pending": ${groupsText(nextPending)}\n}\n');
			report(counts, nextPending, nextSkip);
			return;
		}
		Sys.println('css values: parity with #321\'s cascade: ${parityChecks} values on ${Lambda.count(parityPages)} pages, ${parity.length} differ');
		for (p in parity.slice(0, Std.parseInt(Sys.getEnv("LIMIT") ?? "40"))) Sys.println('  differs from #321: $p');
		for (f in failures.slice(0, Std.parseInt(Sys.getEnv("LIMIT") ?? "40"))) Sys.println('  required: $f');
		for (f in fixed.slice(0, 40)) Sys.println('  passes, still pending (BLESS=1): $f');
		if (failures.length > 0 || fixed.length > 0 || parity.length > 0) Sys.exit(1);
	}

	static function add(key:String, module:String, ok:Bool, why:String, skip:Null<String>) {
		var k = key, n = 2;
		while (seen.exists(k)) k = '$key #${n++}';
		seen.set(k, true);
		rows.push({key: k, module: module, ok: ok, why: why, want: want, skip: skip});
		want = "";
	}

	static final seen = new Map<String, Bool>();
	static var documents:DynamicAccess<Dynamic>;

	// (a computed value as the test's page gives it: the declaration on its
	// #target's style, the page cascaded as WPT's harness shows it, a
	// screen of 800 by 600)
	static function inPage(file:Int, prop:String, value:String):Null<String> {
		var page:Dynamic = documents.get(Std.string(file));
		if (page == null) return null;
		var html:String = Std.isOfType(page, String) ? page : page.html;
		var doc = Dom.parse(html);
		// (what its script sets on elements before the tests run)
		if (!Std.isOfType(page, String)) for (s in (page.styles : Array<Array<String>>)) {
			var el = doc.getElementById(s[0]);
			if (el != null) el.setAttribute("style", (el.getAttribute("style") ?? "") + ";" + s[1] + ": " + s[2]);
		}
		var target = doc.getElementById("target") ?? doc.body;
		if (target == null) return null;
		target.setAttribute("style", (target.getAttribute("style") ?? "") + ";" + prop + ": " + value);
		var media:helder.css.CssMedia.CssMediaContext = {type: "screen", width: 800, height: 600};
		var style = CssCascade.styles(doc, {media: media}).computed(target);
		var got = style.text(prop);
		// (the same through #321's cascade, frozen: the row's property, and every longhand on a page's first row)
		if (!LOGICAL.match(html + " " + prop + " " + value)) {
			var old = reference.RefCascade.styles(doc, {media: media}).computed(target);
			var props = parityPages.exists(file) ? [prop] : LONGHANDS.concat([prop]);
			parityPages.set(file, true);
			for (p in props) {
				parityChecks++;
				var a = style.text(p), b = old.text(p);
				if (a != b) parity.push('$prop: $value, page $file: $p is ${haxe.Json.stringify(a)}, #321 gave ${haxe.Json.stringify(b)}');
			}
		}
		return got;
	}

	// (#321 had no logical properties: pages with them are left out)
	static final LOGICAL = ~/(margin|padding|inset|border)-(block|inline)|(min-|max-|\b)(inline|block)-size|border-(start|end)-(start|end)-radius/;
	static final LONGHANDS = [for (p in helder.css.CssData.properties) if (p.longhands.length == 0 && p.alias == null && !LOGICAL.match(p.name) && p.name != "all") p.name];
	static final parityPages = new Map<Int, Bool>();
	static final parity:Array<String> = [];
	static var parityChecks = 0;

	static function valid(name:String, module:String, r:Array<Dynamic>) {
		var custom = name == "--*";
		var prop:String = custom ? r[0] : name, value:String = r[custom ? 1 : 0], expected:Dynamic = r[custom ? 2 : 1], eps:Null<Float> = r[custom ? 4 : 3];
		var key = 'valid $prop: $value';
		var v = CssValues.parse(prop, value);
		want = haxe.Json.stringify(expected ?? value);
		// (setting "" removes the declaration: reading it gives "")
		if (StringTools.trim(value) == "" && expected == "") return add(key, module, v == null, "values: an empty value set; accepted", scope(prop, value));
		if (v == null) return add(key, module, false, reason(prop, value, "rejected"), scope(prop, value));
		var got = CssValues.serialize(prop, v);
		var ok = matches(got, expected ?? value, eps);
		add(key, module, ok, ok ? "" : reason(prop, value, 'serializes as ${haxe.Json.stringify(got)}'), scope(prop, value));
	}

	static function invalid(name:String, module:String, r:Array<Dynamic>) {
		var custom = name == "--*";
		var prop:String = custom ? r[0] : name, value:String = r[custom ? 1 : 0];
		var v = CssValues.parse(prop, value);
		add('invalid $prop: $value', module, v == null, v == null ? "" : reason(prop, value, 'accepted as ${haxe.Json.stringify(CssValues.serialize(prop, v))}'),
			scope(prop, value));
	}

	static function computed(name:String, module:String, r:Array<Dynamic>) {
		var custom = name == "--*";
		var prop:String = custom ? r[0] : name, value:String = r[custom ? 1 : 0], expected:Dynamic = r[custom ? 2 : 1], eps:Null<Float> = r[custom ? 4 : 3];
		var key = 'computed $prop: $value';
		var v = CssValues.parse(prop, value);
		want = haxe.Json.stringify(expected ?? value);
		var file0:Int = r[custom ? 3 : 2];
		if (v == null && !(StringTools.trim(value) == "" && expected == "")) return add(key, module, false, reason(prop, value, "rejected"), scope(prop, value) ?? page(file0, value));
		var file:Int = r[custom ? 3 : 2];
		var skip = scope(prop, value) ?? page(file, value);
		// (setting "" removes the declaration: there is nothing to compute)
		if (StringTools.trim(value) == "" && expected == "") return add(key, module, v == null, "values: an empty value set; accepted", skip);
		var got = inPage(file, prop, value) ?? CssValues.compute(prop, v);
		if (got == null) return add(key, module, false, reason(prop, value, "no computed value", true), skip);
		var ok = matches(got, expected ?? value, eps);
		add(key, module, ok, ok ? "" : reason(prop, value, 'computes to ${haxe.Json.stringify(got)}', true), skip);
	}

	// (the shorthand set: each longhand's specified value as expected)
	static function shorthand(name:String, module:String, r:Array<Dynamic>) {
		var value:String = r[0], expected:DynamicAccess<String> = r[1];
		var key = 'shorthand $name: $value';
		var v = CssValues.parse(name, value);
		want = haxe.Json.stringify(expected);
		if (v == null) return add(key, module, false, reason(name, value, "rejected"), scope(name, value));
		var longhands = switch v {
			case Terms(t): CssShorthands.expand(name, t);
			case _: null;
		}
		var got = new Map<String, String>();
		if (longhands != null) for (l => t in longhands) got.set(l, CssValues.serialize(l, Terms(t)));
		// (an expected longhand that is a shorthand itself, as background's background-position, or a legacy name)
		inline function text(l:String):Null<String> {
			var p = CssGrammars.property(l);
			if (p != null && p.alias != null) l = p.alias;
			return got.exists(l) ? got.get(l) : CssShorthands.isShorthand(l) ? CssShorthands.serialize(l, got, false) : null;
		}
		var wrong = [for (l => e in expected) if (text(l) != e) '$l: ${haxe.Json.stringify(text(l))}'];
		wrong.sort(Reflect.compare);
		add(key, module, wrong.length == 0, wrong.length == 0 ? "" : 'values: a shorthand\'s longhands differ; ${wrong.join(", ")}', scope(name, value));
	}

	static function inherits(name:String, module:String, r:Array<Dynamic>) {
		var p = CssGrammars.property(name);
		var key = 'inherits $name';
		if (p == null) return add(key, module, false, "values: not in the table; none", null);
		if (p.inherited != r[0]) return add(key, module, false, 'values: the table\'s inherited differs; ${p.inherited}', null);
		var initial:Dynamic = r[1];
		if (initial == null) return add(key, module, true, "", null);
		want = haxe.Json.stringify(initial);
		var got = inPage(r[3], name, "initial") ?? CssValues.compute(name, Wide("initial"));
		var ok = got != null && matches(got, initial, null);
		var initialText = INITIALS.get(name) ?? "";
		add(key, module, ok, ok ? "" : got == null ? 'cascade: an initial value in prose (the used value, the user agent\'s); ${haxe.Json.stringify(initialText)}' : reason(name,
			initialText, 'initial computes to ${haxe.Json.stringify(got)}', true), null);
	}

	static function color(file:String, input:String, expected:Null<String>) {
		var key = 'colors $file: $input';
		var v = CssValues.parse("color", input);
		if (expected == null)
			return add(key, "colors", v == null, v == null ? "" : reason("color", input, 'accepted as ${haxe.Json.stringify(CssValues.serialize("color", v))}'),
				scope("color", input));
		want = expected;
		if (v == null) return add(key, "colors", false, reason("color", input, "rejected"), scope("color", input));
		var got = CssValues.compute("color", v) ?? "";
		var ok = matches(got, expected, 1e-3);
		// (where css-parsing-tests and WPT disagree, WPT is the gate: it clamps lab()'s L, lch()'s C, rounds rgb(), keeps none)
		var why = if (ok) "" else if (~/^(ok)?l(ab|ch)\(/.match(expected) && ~/^(ok)?l(ab|ch)\(/.match(got))
			'outdated fixture: css-parsing-tests leaves lab() and lch() unclamped (WPT and Color 4: L in its range, C at least 0); computes to ${haxe.Json.stringify(got)}'
		else if (StringTools.startsWith(expected, "rgb") && ~/^(hsl|hwb|color\(srgb)/.match(got) && got.indexOf("none") >= 0)
			'outdated fixture: css-parsing-tests resolves none in hsl() and hwb() (WPT: kept); computes to ${haxe.Json.stringify(got)}'
		else if (StringTools.startsWith(expected, "rgb") && near(got, expected, 0.5))
			'outdated fixture: css-parsing-tests keeps rgb()\'s fractions (WPT: rounded); computes to ${haxe.Json.stringify(got)}'
		else reason("color", input, 'computes to ${haxe.Json.stringify(got)}', true);
		add(key, "colors", ok, why, scope("color", input));
	}

	// (a case out of checkpoint 1's scope, by its value, whether it passes or not)
	static function scope(prop:String, value:String):Null<String> {
		var v = value.toLowerCase();
		if (~/color-mix\(|\b(rgba?|hsla?|hwb|lab|lch|oklab|oklch|color)\(\s*from\b|light-dark\(|contrast-color\(|device-cmyk\(|\balpha\(|color-layers\(|color\(--/.match(v))
			return "out of scope: Color 5 and 6 (color-mix(), relative colours, light-dark(), contrast-color()); checkpoint 1 is Color 4";
		if (~/\b(sibling-index|sibling-count|random|random-item|progress|if|calc-size|anchor|anchor-size|inherit|paint|ident)\(|--[a-z][\w-]*\(|-webkit-image-set\(/.match(v)
			|| prop != "content" && ~/\battr\(/.match(v))
			return "out of scope: drafts past checkpoint 1 (Values 5's functions, custom functions, -webkit-image-set())";
		if (~/url\([^)]*\b(param|cross-origin|crossorigin|integrity|referrer-policy|referrerpolicy)\(/.match(v))
			return "out of scope: url()'s request modifiers and param() (Values 5)";
		if (prop == "transform" && ~/3d\(|[xyz]\(|z\(|perspective\(|scale[xyz]?\([^)]*%/i.match(v) && ~/3d\(|scalez\(|translatez\(|rotate[xyz]\(|perspective\(|%/.match(v))
			return "out of scope: Transforms 2 (3D functions, percentages in scale())";
		if (prop == "display" && v.indexOf("grid-lanes") >= 0) return "out of scope: Grid 3's grid-lanes (masonry)";
		if ((prop == "flex-wrap" || prop == "flex-flow") && v.indexOf("balance") >= 0) return "out of scope: Flexbox 2's balance";
		if (prop == "white-space" && v.indexOf("discard-") >= 0) return "out of scope: Text 4's white-space-trim";
		if (prop == "font-synthesis" && v.indexOf("oblique-only") >= 0) return "out of scope: Fonts 5's oblique-only";
		if (v.indexOf("border-area") >= 0) return "out of scope: Backgrounds 4's border-area";
		if (prop == "object-fit" && v.trim().indexOf(" ") > 0) return "out of scope: Images 5's object-fit pairs";
		if (~/\d(cqw|cqh|cqi|cqb|cqmin|cqmax)\b/.match(v)) return "out of scope: container query units (@container is deferred)";
		if (DRAFT.exists(prop) && DRAFT[prop].match(v)) return 'out of scope: a draft\'s value past checkpoint 1\'s modules';
		return null;
	}

	// (values of drafts past checkpoint 1's levels, by property)
	static final DRAFT:Map<String, EReg> = [
		"opacity" => ~/^auto$/, "quotes" => ~/match-parent/, "text-emphasis-position" => ~/^auto$/, "align-items" => ~/(un)?safe normal/,
		"justify-items" => ~/(un)?safe normal/, "place-items" => ~/(un)?safe normal/
	];

	// (a case out of scope by its page: vertical writing modes, a custom property of a relative colour)
	static function page(file:Int, value:String):Null<String> {
		var p:Dynamic = documents.get(Std.string(file));
		if (p == null) return null;
		var html:String = Std.isOfType(p, String) ? p : p.html;
		if (~/writing-mode:\s*vertical|writing-mode:\s*sideways/.match(html)) return "out of scope: writing modes (deferred): the test's page is vertical";
		if (value.indexOf("var(") >= 0 && ~/\b(rgb|hsl|hwb|lab|lch|oklab|oklch|color)\(\s*from\b/.match(html)) return "out of scope: Color 5 (color-mix(), relative colours, light-dark(), contrast-color()); checkpoint 1 is Color 4";
		return null;
	}

	// (a failing colour of an outdated fixture: skipped)
	static function outdated(why:String):Null<String>
		return why.startsWith("outdated fixture:") ? why.split("; ")[0] : null;

	// Why a case fails, tagged with the stage that clears it: cascade (the
	// test's own context, shorthands' longhands, inheritance), layout, or
	// values (this layer: a written reason for each group left).
	static function reason(prop:String, value:String, got:String, computed = false):String {
		var p = CssGrammars.property(prop);
		var v = value.toLowerCase();
		var need = if (~/^(inset-|cursor$)/.match(prop) && WRITTEN.exists(prop)) 'values: ${WRITTEN[prop]}'
		else if (computed && ~/^(width|height|min-|max-|padding|margin|top|right|bottom|left|inset|text-indent|inline-size|block-size)/.match(prop) && v.indexOf("%") >= 0) "layout: percentages of the containing block"
		else if (p != null && p.longhands.length > 0) "cascade: shorthands serialize from their longhands"
		else if (computed && ~/^(inherit|unset|revert|revert-layer)$/.match(v.trim())) "cascade: inherit, the parent's value"
		else if (computed && (prop == "text-shadow" || prop == "box-shadow") && got.indexOf("rgb(0, 0, 0)") >= 0 && !~/rgb|#|[a-z]{3,} \d|\d [a-z]{3,}/.match(v)) "cascade: currentcolor, the element's color"
		else if (computed && prop == "text-emphasis-style") "cascade: the writing mode's default shape"
		else if (computed && (v.indexOf("from-font") >= 0 || ~/\d(lh|rlh|ex|ch|ic|cap)\b/.match(v))) "layout: the font's own metrics"
		else if (computed && prop == "justify-items" || prop == "justify-items" && got.indexOf("legacy") >= 0) "cascade: justify-items' legacy, the parent's"
		else if (computed && ~/^(width|height|inline-size|block-size|min-inline-size|min-block-size)$/.match(prop) && ~/auto|-content/.match(got)) "layout: getComputedStyle's resolved value (the used one)"
		else if (computed && ~/^grid-template|^grid-auto/.match(prop)) "layout: grid tracks' sizes"
		else if (computed && ~/^(line-height|transform-origin|perspective-origin)$/.match(prop)) "layout: getComputedStyle's resolved value (the used one)"
		else if (computed && ~/^(width|height|min-|max-|padding|margin|top|right|bottom|left|inset|text-indent|inline-size|block-size)/.match(prop) && v.indexOf("%") >= 0) "layout: percentages of the containing block"
		else if (computed && v.indexOf("url(") >= 0) "cascade: url() made absolute against the document"
		else if (computed && ~/var\(|env\(/.match(v)) "cascade: var() and env() substituted"
		else if (computed && ~/currentcolor/.match(v)) "cascade: currentcolor, the element's color"
		else if (computed && ~/\d(em|ex|ch|ic|cap|lh|rlh|vw|vh|vmin|vmax|cq[a-z]*|%)(?![a-z])/.match(v)) "cascade: the test's own sizes (font size, container)"
		else if (WRITTEN.exists(prop)) 'values: ${WRITTEN[prop]}'
		else "values: differs";
		return '$need; $got';
	}

	// (what is left in this layer, by property)
	static final WRITTEN:Map<String, String> = [
		"align-content" => "Align 3's `[ first | last ]? && baseline` takes `baseline last`; WPT and browsers don't",
		"align-items" => "Align 3's `[ first | last ]? && baseline` takes `baseline last`; WPT and browsers don't",
		"align-self" => "Align 3's `[ first | last ]? && baseline` takes `baseline last`; WPT and browsers don't",
		"justify-items" => "Align 3's `[ first | last ]? && baseline` takes `baseline last`; WPT and browsers don't",
		"justify-self" => "Align 3's `[ first | last ]? && baseline` takes `baseline last`; WPT and browsers don't",
		"image-orientation" => "Images 3's grammar still has `<angle> || flip`, which browsers dropped and WPT rejects",
		"box-shadow-offset" => "box-shadow's longhands (Borders 4): WPT has a draft's expectations, no browser the longhands",
		"box-shadow-blur" => "box-shadow's longhands (Borders 4): WPT has a draft's expectations, no browser the longhands",
		"box-shadow-spread" => "box-shadow's longhands (Borders 4): WPT has a draft's expectations, no browser the longhands",
		"box-shadow-color" => "box-shadow's longhands (Borders 4): WPT has a draft's expectations, no browser the longhands",
		"transform" => "WPT disagrees with itself: translateX() as written in one file, scalex() lowercase in the others (followed)",
		"color" => "rgb() with none as color(srgb): WPT wants 8 digits here, 6 everywhere else (followed)",
		"text-emphasis-position" => "its initial value: WPT has Text Decoration 4's auto, checkpoint 1's table 3's over right",
		"cursor" => "WPT's computed gradients in cursor: its expected texts drop a parenthesis, and cursor's grammar has image-set() of URLs, not <image>",
		"inset-block" => "WPT's inset-block and inset-inline files want the value as written (0, auto auto), unlike its other logical shorthands' and inset's (followed: the shortest)",
		"inset-inline" => "WPT's inset-block and inset-inline files want the value as written (0, auto auto), unlike its other logical shorthands' and inset's (followed: the shortest)",
		"inset-block-start" => "WPT's logical inset files want 0 as written and calc() unresolved, unlike its top, right, bottom and left files (followed: Values 4's computed value)",
		"inset-block-end" => "WPT's logical inset files want 0 as written and calc() unresolved, unlike its top, right, bottom and left files (followed: Values 4's computed value)",
		"inset-inline-start" => "WPT's logical inset files want 0 as written and calc() unresolved, unlike its top, right, bottom and left files (followed: Values 4's computed value)",
		"inset-inline-end" => "WPT's logical inset files want 0 as written and calc() unresolved, unlike its top, right, bottom and left files (followed: Values 4's computed value)"
	];

	// The text against the expected one (or any of a list): numbers within eps when there is one.
	static function matches(got:String, expected:Dynamic, eps:Null<Float>):Bool {
		var list:Array<String> = Std.isOfType(expected, Array) ? expected : [expected];
		for (e in list) if (got == e || eps != null && near(got, e, eps)) return true;
		return false;
	}

	static function near(a:String, b:String, eps:Float):Bool {
		var num = ~/-?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?/gi;
		var xs = [], ys = [];
		var sa = num.map(a, m -> {
			xs.push(Std.parseFloat(m.matched(0)));
			"#";
		}), sb = num.map(b, m -> {
			ys.push(Std.parseFloat(m.matched(0)));
			"#";
		});
		if (sa != sb || xs.length != ys.length) return false;
		for (k in 0...xs.length) if (Math.abs(xs[k] - ys[k]) > eps) return false;
		return true;
	}

	static function totals(counts:Map<String, {pass:Int, pending:Int, skip:Int}>):{pass:Int, pending:Int, skip:Int} {
		var t = {pass: 0, pending: 0, skip: 0};
		for (c in counts) {
			t.pass += c.pass;
			t.pending += c.pending;
			t.skip += c.skip;
		}
		return t;
	}

	static function groupsText(cases:Map<String, String>):String {
		var by = new Map<String, Array<String>>();
		for (k => why in cases) {
			if (!by.exists(why)) by.set(why, []);
			by[why].push(k);
		}
		var whys = [for (w in by.keys()) w];
		whys.sort(Reflect.compare);
		var b = new StringBuf();
		b.add("{\n");
		for (n in 0...whys.length) {
			var keys = by[whys[n]];
			keys.sort(Reflect.compare);
			b.add('\t\t${haxe.Json.stringify(whys[n])}: [\n');
			for (j in 0...keys.length) b.add('\t\t\t${haxe.Json.stringify(keys[j])}${j + 1 < keys.length ? "," : ""}\n');
			b.add('\t\t]${n + 1 < whys.length ? "," : ""}\n');
		}
		b.add("\t}");
		return b.toString();
	}

	static function tally(cases:Map<String, String>, key:String->String):Array<{name:String, n:Int}> {
		var m = new Map<String, Int>();
		for (why in cases) m.set(key(why), (m.get(key(why)) ?? 0) + 1);
		var out = [for (k => n in m) {name: k, n: n}];
		out.sort((a, b) -> b.n - a.n != 0 ? b.n - a.n : Reflect.compare(a.name, b.name));
		return out;
	}

	static function report(counts:Map<String, {pass:Int, pending:Int, skip:Int}>, pending:Map<String, String>, skip:Map<String, String>) {
		var t = totals(counts);
		var b = new StringBuf();
		b.add('${t.pass} of ${t.pass + t.pending} required (${Math.round(t.pass * 1000 / (t.pass + t.pending)) / 10}%): checkpoint 1\'s progress; ${t.pending} pending, '
			+ 'our gaps; ${t.skip} skipped, not checkpoint 1\'s.\n\n');
		b.add("| Pending, by the stage that clears them | Cases |\n| --- | --- |\n");
		for (s in tally(pending, w -> w.split(":")[0])) b.add('| ${s.name} | ${s.n} |\n');
		b.add("\n| Pending because | Cases |\n| --- | --- |\n");
		for (s in tally(pending, w -> w)) b.add('| ${s.name} | ${s.n} |\n');
		b.add("\n| Skipped because | Cases |\n| --- | --- |\n");
		for (s in tally(skip, w -> w)) b.add('| ${s.name} | ${s.n} |\n');
		var modules = [for (m in counts.keys()) m];
		modules.sort(Reflect.compare);
		b.add("\n| Module | Required | Pending | Skipped |\n| --- | --- | --- | --- |\n");
		for (m in modules) b.add('| $m | ${counts[m].pass} | ${counts[m].pending} | ${counts[m].skip} |\n');
		var readme = File.getContent('$here/README.md');
		var start = readme.indexOf("<!-- values -->"), end = readme.indexOf("<!-- /values -->");
		if (start < 0 || end < 0) return;
		File.saveContent('$here/README.md', readme.substr(0, start) + "<!-- values -->\n" + b.toString() + readme.substr(end));
	}
}
