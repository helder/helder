package helder.css;

import helder.css.CssProperty;
import helder.css.CssSheet;
import helder.dom.Dom;
import helder.test.Test;

// Sheets compiled at build time: the same rules, selectors (their
// specificity, Bloom hashes, buckets) and declarations as the text parsed
// when the program runs, and the same styles through the cascade.
private inline final SHEET = '@namespace svg url(http://www.w3.org/2000/svg);
	@layer base, theme;
	@layer base { p { margin: 1px 2px; color: rgb(10 20 30 / 50%) } }
	@layer theme { .a > p:nth-child(2n+1 of .b) { color: color-mix(in srgb, red 40%, blue) } }
	:root { --gap: 4px; --c: oklch(0.7 0.1 none) }
	div.a#main[title^="x" i], :is(ul, ol) li:not(.b):first-child { padding: calc(var(--gap) * 2 + 1em) var(--gap) !important }
	a:link::before { content: "→ " counter(item) attr(title) }
	section:has(> h1) h1 + p ~ span, svg|rect { border: 1px dashed currentcolor; width: min(50%, 300px); transform: rotate(45deg) scale(1.5) }
	@media print and (min-width: 400px) { p { font: italic bold 12px/1.5 serif } }
	@media (orientation: landscape) { p { display: none } }
	@supports (display: grid) { .g { display: grid; grid-template: "a b" 1fr "c d" auto / 1fr 2fr } }
	@supports not (display: grid) { .g { display: table } }
	@page :first { margin: 2cm; @top-center { content: "x" } }
	@font-face { font-family: X; src: url(x.woff2) format("woff2") }
	@counter-style thumbs { system: cyclic; symbols: "👍" }
	li { list-style: square inside; background: url(a.png) no-repeat 0 0 / cover, linear-gradient(to right, red, blue) }
	p { margin-left: -0.333333333333em; opacity: 1e-3; line-height: 1.15 }';

function tests() {
	describe("CssTheme", () -> {
		test("the rules, selectors and declarations the text parses to", () -> {
			var compiled = CssTheme.sheet(SHEET), parsed = CssSheet.parse(SHEET, Author);
			equals(compiled.url, null);
			equals(rules(compiled.rules), rules(parsed.rules));
			equals(CssTheme.sheet(SHEET) == compiled, true);
		});
		test("the same styles", () -> {
			var html = '<!doctype html><div class=a id=main title=Xy><p class=b>a</p><p>b</p></div><ul><li>c</li></ul><section><h1>h</h1><p>p</p><span>s</span></section><a href=x title=t>l</a><div class=g></div>';
			var a = Dom.parse(html), b = Dom.parse(html);
			var compiled = CssCascade.themed(a, [CssTheme.sheet(SHEET)]), parsed = CssCascade.themed(b, [CssSheet.parse(SHEET, Author)]);
			var ea = CssMatcher.query(CssSelector.parse("*") ?? [], a), eb = CssMatcher.query(CssSelector.parse("*") ?? [], b);
			for (k in 0...ea.length)
				for (pseudo in [null, "before"]) {
					var x = compiled.computed(ea[k], pseudo), y = parsed.computed(eb[k], pseudo);
					for (p in 0...CssProperties.COUNT) {
						var n = CssProperties.name(cast p);
						if (x.text(n) != y.text(n)) fail('<${ea[k].localName}>${pseudo ?? ""} $n: ${x.text(n)} compiled, ${y.text(n)} parsed');
					}
				}
			equals(compiled.pages.length, parsed.pages.length);
			equals(compiled.fontFaces.length, 1);
			equals(compiled.counterStyles.length, 1);
		});
		test("the initial values compiled as they parse", () -> {
			var written:Map<String, String> = @:privateAccess CssShorthands.INITIAL;
			for (p in CssData.properties) {
				var text = written.get(p.name) ?? p.initial;
				equals(deep(CssInitial.of(p.name)), deep(text == null ? null : CssValues.parse(p.name, text)), p.name);
				equals(deep(CssInitial.specified(p.name)), deep(p.initial == null ? null : CssValues.parse(p.name, p.initial)), p.name);
			}
		});
		test("a file, its @import beside it, an origin", () -> {
			var s = CssTheme.file("helder/css/CssTheme.test.css", UserAgent);
			equals(s.origin, UserAgent);
			equals(s.rules[0].match(Import(_, _, "x", false)), true);
			var doc = Dom.parse("<p>a</p>");
			var p = CssCascade.themed(doc, [s]).computed(doc.getElementsByTagName("p").item(0));
			equals([p.text("color"), p.text("margin-top")], ["rgb(255, 0, 0)", "3px"]);
		});
	});
}

// (a sheet's rules written out: selectors with what CssTheme compiles, declarations as their parts)
private function rules(list:Array<CssSheetRule>):String
	return [for (r in list) switch r {
		case Style(selectors, declarations):
			'style ${[for (s in selectors) selector(s)].join(", ")} { ${[for (d in declarations) declared(d)].join("; ")} }';
		case Media(media, inner): 'media ${deep(@:privateAccess media.queries)} { ${rules(inner)} }';
		case Layer(name, inner): 'layer $name ${inner == null ? "" : "{ " + rules(inner) + " }"}';
		case Import(sheet, media, layer, anonymous): 'import ${deep(@:privateAccess media.queries)} $layer $anonymous { ${rules(sheet.rules)} }';
		case Page(rule):
			'page ${deep(rule.selectors)} ${[for (d in rule.declarations) declared(d)].join("; ")} ${[for (d in rule.descriptors) d.name + ":" + Css.serialize(d.value)]} ${[for (k => v in rule.margins) k + ":" + [for (d in v) declared(d)].join("; ")]}';
		case FontFace(face): 'font-face ${[for (d in face.descriptors) d.name + ":" + Css.serialize(d.value)]}';
		case CounterStyle(style): 'counter-style ${style.name} ${[for (d in style.descriptors) d.name + ":" + Css.serialize(d.value)]}';
		case FontPaletteValues(p): 'font-palette-values ${p.name} ${[for (d in p.descriptors) d.name + ":" + Css.serialize(d.value)]}';
	}].join("\n");

private function selector(s:CssSelector):String
	return '$s ${s.specificity.toInt()} ${s.hashes} ${s.local} ${deep(s.bucket)}';

private function declared(d:CssDeclared):String
	return '${d.property} ${d.id} ${deep(d.value)} ${d.important} ${d.values == null ? "" : Css.serialize(d.values)} ${d.shorthand}';

// (a value written out to any depth: Std.string stops at a few levels)
private function deep(v:Dynamic):String {
	if (v == null) return "null";
	return switch Type.typeof(v) {
		case TEnum(_):
			var args:Array<Dynamic> = Type.enumParameters(v);
			Type.enumConstructor(v) + (args.length == 0 ? "" : "(" + [for (a in args) deep(a)].join(",") + ")");
		case TObject:
			var fields = Reflect.fields(v);
			fields.sort(Reflect.compare);
			"{" + [for (f in fields) f + ":" + deep(Reflect.field(v, f))].join(",") + "}";
		case TClass(Array): "[" + [for (x in (v : Array<Dynamic>)) deep(x)].join(",") + "]";
		case TClass(CssToken): Std.string((v : CssToken).kind);
		case _: Std.string(v);
	}
}
