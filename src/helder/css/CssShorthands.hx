package helder.css;

import helder.css.CssTerm;

using Lambda;
using StringTools;

// Shorthands to their longhands and back (CSSOM's "serialize a CSS value"
// from them): each shorthand as its spec says, the matcher's Parts telling
// what of the value each longhand is. A longhand left out is its initial
// value; a shorthand's reset-only longhands (font's font-kerning, border's
// border-image) are set to theirs too.
class CssShorthands {
	static final SIDES = ["top", "right", "bottom", "left"];
	static final CORNERS = ["top-left", "top-right", "bottom-right", "bottom-left"];
	static final TRANSITION = ["transition-property", "transition-duration", "transition-timing-function", "transition-delay", "transition-behavior"];

	// (a logical border shorthand's sides: the longhands' prefixes)
	static function borders(shorthand:String):Array<String>
		return switch shorthand {
			case "border-block": ["border-block-start", "border-block-end"];
			case "border-inline": ["border-inline-start", "border-inline-end"];
			case _: [shorthand];
		}

	static final LINE_STYLES = ["none", "hidden", "dotted", "dashed", "solid", "double", "groove", "ridge", "inset", "outset"];

	// Every longhand a shorthand sets, reset-only ones included.
	public static function longhands(shorthand:String):Array<String> {
		return switch shorthand {
			case "all": [for (p in CssTable.properties) if (p.longhands.length == 0 && p.alias == null && p.name != "all" && p.name != "direction" && p.name != "unicode-bidi") p.name];
			case "border": [for (s in SIDES) for (k in ["width", "style", "color"]) 'border-$s-$k'].concat(CssGrammars.property("border-image").longhands);
			case "border-width" | "border-style" | "border-color": [for (s in SIDES) 'border-$s-${shorthand.substr(7)}'];
			case "font":
				["font-style", "font-variant-caps", "font-weight", "font-width", "font-size", "line-height", "font-family", "font-variant-ligatures", "font-variant-alternates",
					"font-variant-numeric", "font-variant-east-asian", "font-variant-position", "font-variant-emoji", "font-feature-settings", "font-kerning",
					"font-language-override", "font-optical-sizing", "font-size-adjust", "font-variation-settings"];
			case "background-position": ["background-position-x", "background-position-y"];
			case "text-decoration": ["text-decoration-line", "text-decoration-thickness", "text-decoration-style", "text-decoration-color"];
			// (webref's list leaves out Fonts 4's font-synthesis-position)
			case "font-synthesis": ["font-synthesis-weight", "font-synthesis-style", "font-synthesis-small-caps", "font-synthesis-position"];
			case _:
				var p = CssGrammars.property(shorthand);
				p == null ? [] : [for (l in p.longhands) for (x in expanded(l)) x];
		}
	}

	// (a longhand that is a shorthand itself, as background-position is background's, as its own)
	static function expanded(l:String):Array<String> {
		var p = CssGrammars.property(l);
		return p != null && p.longhands.length > 0 ? longhands(l) : [l];
	}

	// (box-shadow's longhands are a draft's no browser has: it stays one property)
	public static function isShorthand(property:String):Bool {
		var p = CssGrammars.property(property);
		return property == "all" || p != null && p.longhands.length > 0 && property != "box-shadow";
	}

	// The longhands' terms of a shorthand's matched terms, null where the value is not one (a shorthand's prose rules).
	public static function expand(shorthand:String, terms:Array<CssTerm>):Null<Map<String, Array<CssTerm>>> {
		var out = new Map<String, Array<CssTerm>>();
		inline function set(l:String, t:Array<CssTerm>)
			out.set(l, plain(t));
		var parts = top(terms);
		switch shorthand {
			case "margin" | "padding" | "inset" | "border-width" | "border-style" | "border-color":
				var names = shorthand == "inset" ? SIDES : [for (s in SIDES) shorthand.startsWith("border-") ? 'border-$s-${shorthand.substr(7)}' : '$shorthand-$s'];
				var items = values(terms);
				for (k in 0...4) set(names[k], items[side(items.length, k)]);
			case "border-radius":
				var flat = plain(terms), slash = -1;
				for (k in 0...flat.length) if (flat[k].match(Delim("/"))) slash = k;
				var h = slash < 0 ? flat : flat.slice(0, slash), v = slash < 0 ? h : flat.slice(slash + 1);
				for (k in 0...4) {
					var a = h[side(h.length, k)], b = v[side(v.length, k)];
					set('border-${CORNERS[k]}-radius', CssText.term(a) == CssText.term(b) ? [a] : [a, b]);
				}
			case "border" | "border-top" | "border-right" | "border-bottom" | "border-left":
				var width = null, style = null, color = null;
				for (t in plain(terms)) switch t {
					case Keyword(k) if (LINE_STYLES.contains(k)): style = t;
					case Color(_): color = t;
					case _: width = t;
				}
				var sides = shorthand == "border" ? SIDES : [shorthand.substr(7)];
				for (s in sides) {
					if (width != null) set('border-$s-width', [width]);
					if (style != null) set('border-$s-style', [style]);
					if (color != null) set('border-$s-color', [color]);
				}
			case "background":
				var layers = CssText.layers(terms);
				var keys = ["background-image", "background-position-x", "background-position-y", "background-size", "background-repeat", "background-attachment", "background-origin",
					"background-clip"];
				var lists = [for (k in keys) k => new Array<Array<CssTerm>>()];
				for (n in 0...layers.length) {
					var l = layers[n];
					var image:Array<CssTerm> = [Keyword("none")], pos = null, size = null, repeat = null, attach = null, boxes = [], color = null;
					for (t in l) switch t {
						case Part("<bg-image>", ts): image = ts;
						case Part("<bg-position>", ts): pos = ts;
						case Part("<bg-size>", ts): size = ts;
						case Part("<repeat-style>", ts): repeat = ts;
						case Part("<attachment>", ts): attach = ts;
						case Part("<visual-box>" | "<bg-clip>", ts): boxes.push(ts);
						case Part("'background-color'", ts) | Part("background-color", ts): color = ts;
						case Part(_, ts):
							// (final-bg-layer's own parts: the same, a level down)
							for (x in ts) switch x {
								case Part("<bg-image>", y): image = y;
								case Part("<bg-position>", y): pos = y;
								case Part("<bg-size>", y): size = y;
								case Part("<repeat-style>", y): repeat = y;
								case Part("<attachment>", y): attach = y;
								case Part("<visual-box>" | "<bg-clip>", y): boxes.push(y);
								case Part("background-color", y): color = y;
								case _:
							}
						case Color(_): color = [t];
						case _:
					}
					var xy = pos == null ? null : axes(plain(pos));
					lists["background-image"].push(plain(image));
					lists["background-position-x"].push(xy == null ? [Percentage(0)] : xy.x);
					lists["background-position-y"].push(xy == null ? [Percentage(0)] : xy.y);
					lists["background-size"].push(size == null ? [Keyword("auto")] : plain(size));
					lists["background-repeat"].push(repeat == null ? [Keyword("repeat")] : plain(repeat));
					lists["background-attachment"].push(attach == null ? [Keyword("scroll")] : plain(attach));
					lists["background-origin"].push(boxes.length > 0 ? plain(boxes[0]) : [Keyword("padding-box")]);
					lists["background-clip"].push(boxes.length > 1 ? plain(boxes[1]) : boxes.length == 1 ? plain(boxes[0]) : [Keyword("border-box")]);
					if (n == layers.length - 1) set("background-color", color == null ? [Color(CssColors.keyword("transparent"))] : plain(color));
				}
				for (k in keys) set(k, CssText.unlayers(lists[k]));
			case "background-position":
				var xs = [], ys = [];
				for (l in CssText.layers(plain(terms))) {
					var xy = axes(l);
					if (xy == null) return null;
					xs.push(xy.x);
					ys.push(xy.y);
				}
				set("background-position-x", CssText.unlayers(xs));
				set("background-position-y", CssText.unlayers(ys));
			case "flex":
				var f = plain(terms);
				if (f.length == 1 && f[0].match(Keyword("none"))) {
					set("flex-grow", [Number(0, false)]);
					set("flex-shrink", [Number(0, false)]);
					set("flex-basis", [Keyword("auto")]);
				} else {
					var grow = parts.get("flex-grow"), shrink = parts.get("flex-shrink"), basis = parts.get("flex-basis");
					// (a lone auto is 1 1 auto; a lone basis 1 1 basis; numbers without a basis 0%)
					set("flex-grow", grow ?? [Number(1, false)]);
					set("flex-shrink", shrink ?? [Number(1, false)]);
					set("flex-basis", basis ?? (grow != null ? [Percentage(0)] : [Keyword("auto")]));
				}
			case "gap" | "grid-gap" | "place-content" | "place-items" | "place-self" | "overflow":
				var names = CssGrammars.property(shorthand).longhands;
				var items = [for (t in terms) switch t {
					case Part(_, ts): ts;
					case _: [t];
				}];
				set(names[0], items[0]);
				// (place-content's baseline alone: justify-content start, Align 3 §10.1)
				var baseline = plain(items[0]).exists(t -> t.match(Keyword("baseline")));
				set(names[1], items.length > 1 ? items[1] : shorthand == "place-content" && baseline ? [Keyword("start")] : items[0]);
			case "grid-template":
				var t = template(plain(terms));
				if (t == null) return null;
				for (k => v in t) out.set(k, v);
			case "grid":
				var t = plain(terms);
				var halves = slashed(t);
				var flow = t.exists(x -> x.match(Keyword("auto-flow")));
				if (!flow) {
					var g = template(t);
					if (g == null) return null;
					for (k => v in g) out.set(k, v);
				} else {
					var dense = t.exists(x -> x.match(Keyword("dense")));
					var rowsFlow = halves[0].exists(x -> x.match(Keyword("auto-flow")));
					inline function tracks(h:Array<CssTerm>):Array<CssTerm>
						return h.filter(x -> !x.match(Keyword("auto-flow" | "dense")));
					set("grid-auto-flow", rowsFlow ? (dense ? [Keyword("row"), Keyword("dense")] : [Keyword("row")]) : (dense ? [Keyword("column"), Keyword("dense")] : [Keyword("column")]));
					if (rowsFlow) {
						var a = tracks(halves[0]);
						if (a.length > 0) set("grid-auto-rows", a);
						set("grid-template-columns", halves[1]);
						set("grid-template-rows", [Keyword("none")]);
					} else {
						var a = tracks(halves[1]);
						if (a.length > 0) set("grid-auto-columns", a);
						set("grid-template-rows", halves[0]);
						set("grid-template-columns", [Keyword("none")]);
					}
					set("grid-template-areas", [Keyword("none")]);
				}
			case "grid-row" | "grid-column":
				var lines = slashed(plain(terms));
				set('$shorthand-start', lines[0]);
				set('$shorthand-end', lines.length > 1 ? lines[1] : ident(lines[0]) ? lines[0] : [Keyword("auto")]);
			case "grid-area":
				var lines = slashed(plain(terms));
				inline function line(k:Int, from:Int):Array<CssTerm>
					return k < lines.length ? lines[k] : ident(lines[from]) ? lines[from] : [Keyword("auto")];
				set("grid-row-start", lines[0]);
				set("grid-column-start", line(1, 0));
				set("grid-row-end", line(2, 0));
				set("grid-column-end", line(3, lines.length > 1 ? 1 : 0));
			case "text-align":
				var t = plain(terms);
				switch t {
					case [Keyword("justify-all")]:
						set("text-align-all", [Keyword("justify")]);
						set("text-align-last", [Keyword("justify")]);
					case _:
						set("text-align-all", t);
						set("text-align-last", [Keyword("auto")]);
				}
			case "white-space":
				var t = plain(terms);
				var pair = switch t {
					case [Keyword("normal")]: ["collapse", "wrap"];
					case [Keyword("pre")]: ["preserve", "nowrap"];
					case [Keyword("pre-wrap")]: ["preserve", "wrap"];
					case [Keyword("pre-line")]: ["preserve-breaks", "wrap"];
					case _: null;
				}
				if (pair != null) {
					set("white-space-collapse", [Keyword(pair[0])]);
					set("text-wrap-mode", [Keyword(pair[1])]);
				} else {
					if (parts.exists("white-space-collapse")) set("white-space-collapse", parts["white-space-collapse"]);
					if (parts.exists("text-wrap-mode")) set("text-wrap-mode", parts["text-wrap-mode"]);
				}
			case "vertical-align":
				for (t in plain(terms)) switch t {
					case Keyword("first" | "last"): set("baseline-source", [t]);
					case _:
				}
				if (parts.exists("alignment-baseline")) set("alignment-baseline", parts["alignment-baseline"]);
				if (parts.exists("baseline-shift")) set("baseline-shift", parts["baseline-shift"]);
			case "font-synthesis":
				var t = plain(terms);
				var none = t.length == 1 && t[0].match(Keyword("none"));
				for (k in ["weight", "style", "small-caps", "position"]) {
					var on = !none && t.exists(x -> switch x {
						case Keyword(w): w == k;
						case _: false;
					});
					set('font-synthesis-$k', [Keyword(on ? "auto" : "none")]);
				}
			case "list-style":
				for (k => v in parts) set(k, v);
				// (none sets whichever of the image and the type is not given, Lists 3)
				if (plain(terms).exists(x -> x.match(Keyword("none")))) {
					var image = parts.get("list-style-image"), type = parts.get("list-style-type");
					if (image == null || plain(image).exists(x -> x.match(Keyword("none")))) set("list-style-image", [Keyword("none")]);
					if (type == null || plain(type).exists(x -> x.match(Keyword("none")))) set("list-style-type", [Keyword("none")]);
				}
			case "font":
				var t = plain(terms);
				for (k => v in parts) if (k != "font-variant" && k != "font-stretch") set(k, v);
				for (x in terms) switch x {
					case Part("<font-variant-css2>", v): set("font-variant-caps", v);
					case Part("<font-width-css3>", v): set("font-width", v);
					case Part(_, inner): for (y in inner) switch y {
							case Part("<font-variant-css2>", v): set("font-variant-caps", v);
							case Part("<font-width-css3>", v): set("font-width", v);
							case Part(n, v) if (n == "font-style" || n == "font-weight" || n == "font-size" || n == "line-height" || n == "font-family"): set(n, v);
							case _:
						}
					case _:
				}
				// (font's normal in front is any of style, variant, weight, width's: theirs anyway)
				for (l in ["font-variant-caps", "font-width"]) if (out.exists(l) && out[l].length == 1 && out[l][0].match(Keyword("normal"))) out.remove(l);
				// (a system font: its longhands are the system's, which a page has not; the initial values, system-ui's family)
				if (t.length == 1 && t[0].match(Keyword(_))) set("font-family", [Keyword("system-ui")]);
			case "font-variant":
				var t = plain(terms);
				if (t.length == 1 && t[0].match(Keyword("normal" | "none"))) {
					set("font-variant-ligatures", t);
				} else {
					var groups = [
						"font-variant-ligatures" => [], "font-variant-caps" => [], "font-variant-alternates" => [], "font-variant-numeric" => [],
						"font-variant-east-asian" => [], "font-variant-position" => [], "font-variant-emoji" => []
					];
					for (x in t) groups[variant(x)].push(x);
					for (k => v in groups) if (v.length > 0) set(k, v);
				}
			// (a start and an end: one value is both, Logical 1 §4)
			case "margin-block" | "margin-inline" | "padding-block" | "padding-inline" | "inset-block" | "inset-inline" | "border-block-width" | "border-block-style"
				| "border-block-color" | "border-inline-width" | "border-inline-style" | "border-inline-color":
				var names = CssGrammars.property(shorthand).longhands;
				var items = values(terms);
				set(names[0], items[0]);
				set(names[1], items.length > 1 ? items[1] : items[0]);
			case "border-block" | "border-inline" | "border-block-start" | "border-block-end" | "border-inline-start" | "border-inline-end":
				var width = null, style = null, color = null;
				for (t in plain(terms)) switch t {
					case Keyword(k) if (LINE_STYLES.contains(k)): style = t;
					case Color(_): color = t;
					case _: width = t;
				}
				for (b in borders(shorthand)) {
					if (width != null) set('$b-width', [width]);
					if (style != null) set('$b-style', [style]);
					if (color != null) set('$b-color', [color]);
				}
			case "transition":
				var layers = [for (_ in TRANSITION) []];
				for (layer in CssText.layers(terms)) {
					var property = null, duration = null, easing = null, delay = null, behavior = null;
					for (t in layer) switch t {
						case Part("<single-transition>", inner): for (x in inner) switch x {
								case Part("<single-transition-property>", p): property = plain(p);
								case Part("<easing-function>", e): easing = plain(e);
								case Part("<transition-behavior-value>", b): behavior = plain(b);
								case Keyword("none"): property = [x];
								case _ if (duration == null): duration = plain([x]);
								case _: delay = plain([x]);
							}
						case _:
					}
					var parts = [property ?? [Keyword("all")], duration ?? [Dimension(0, "s")], easing ?? [Keyword("ease")], delay ?? [Dimension(0, "s")], behavior ?? [Keyword("normal")]];
					for (k in 0...TRANSITION.length) layers[k].push(parts[k]);
				}
				for (k in 0...TRANSITION.length) set(TRANSITION[k], CssText.unlayers(layers[k]));
			// (Overflow 4 §4.1: none, or the lines and ellipsis, continue collapse, -webkit-legacy's)
			case "line-clamp":
				var lines:Array<CssTerm> = [], ellipsis = null, legacy = false, none = false;
				for (t in terms) switch t {
					case Part("block-ellipsis", e): ellipsis = plain(e);
					case Keyword("none"): none = true;
					case Keyword("-webkit-legacy"): legacy = true;
					case Number(_, _) | Calc(_, _, _): lines.unshift(t);
					case Keyword("auto"): lines.push(t);
					case _:
				}
				if (!none) {
					set("max-lines", lines.length == 0 ? [Keyword("auto")] : lines);
					set("block-ellipsis", ellipsis ?? [Keyword("ellipsis")]);
					set("continue", [Keyword(legacy ? "-webkit-legacy" : "collapse")]);
				}
			default:
				// (`a || b || c` of the longhands themselves: each its part)
				for (k => v in parts) if (CssGrammars.property(shorthand).longhands.contains(k)) set(k, v);
		}
		// the rest at their initial values
		for (l in longhands(shorthand)) if (!out.exists(l)) {
			var initial = initialTerms(l);
			if (initial == null) return null;
			out.set(l, initial);
		}
		return out;
	}

	// ---- serialization

	// The shorthand's text from its longhands' texts (specified or
	// computed, each as CssValues writes it); "" where they can't be one
	// (a longhand a CSS-wide keyword the others are not, a value the
	// shorthand can't say).
	// (initials: the longhands' initial values as computed where the texts were, when not the default context)
	public static function serialize(shorthand:String, texts:Map<String, String>, computed:Bool, ?initials:Map<String, String>):String {
		var ls = longhands(shorthand);
		for (l in ls) if (!texts.exists(l)) return "";
		var wide = ls.map(l -> texts[l]).filter(v -> ["initial", "inherit", "unset", "revert", "revert-layer"].contains(v));
		if (wide.length > 0) return wide.length == ls.length && wide.foreach(w -> w == wide[0]) ? wide[0] : "";
		inline function v(l:String):String
			return texts[l];
		inline function isInitial(l:String):Bool
			return texts[l] == (initials != null && initials.exists(l) ? initials[l] : initialText(l, computed));
		inline function omitting(names:Array<String>, fallback:String):String {
			var kept = names.filter(n -> !isInitial(n)).map(n -> v(n));
			return kept.length == 0 ? v(fallback) : kept.join(" ");
		}
		return switch shorthand {
			case "margin" | "padding" | "inset" | "border-width" | "border-style" | "border-color":
				var names = shorthand == "inset" ? SIDES : [for (s in SIDES) shorthand.startsWith("border-") ? 'border-$s-${shorthand.substr(7)}' : '$shorthand-$s'];
				sides([for (n in names) v(n)]);
			case "border-radius":
				var h = [], vv = [];
				for (c in CORNERS) {
					var parts = v('border-$c-radius').split(" ");
					h.push(parts[0]);
					vv.push(parts.length > 1 ? parts[1] : parts[0]);
				}
				var a = sides(h), b = sides(vv);
				a == b ? a : '$a / $b';
			case "border" | "border-top" | "border-right" | "border-bottom" | "border-left":
				var sidesOf = shorthand == "border" ? SIDES : [shorthand.substr(7)];
				var w = [for (s in sidesOf) v('border-$s-width')], st = [for (s in sidesOf) v('border-$s-style')], c = [for (s in sidesOf) v('border-$s-color')];
				if (!same(w) || !same(st) || !same(c)) return "";
				if (shorthand == "border" && CssGrammars.property("border-image").longhands.exists(l -> !isInitial(l))) return "";
				var s0 = sidesOf[0];
				omitting(['border-$s0-width', 'border-$s0-style', 'border-$s0-color'], 'border-$s0-style');
			case "flex": '${v("flex-grow")} ${v("flex-shrink")} ${v("flex-basis")}';
			case "gap" | "grid-gap" | "place-content" | "place-items" | "place-self" | "overflow":
				var names = CssGrammars.property(shorthand).longhands;
				v(names[0]) == v(names[1]) ? v(names[0]) : '${v(names[0])} ${v(names[1])}';
			case "flex-flow": omitting(["flex-direction", "flex-wrap"], "flex-direction");
			// (computed: its colour always, as browsers write it)
			case "text-emphasis" if (computed): '${v("text-emphasis-style")} ${v("text-emphasis-color")}';
			case "text-emphasis": omitting(["text-emphasis-style", "text-emphasis-color"], "text-emphasis-style");
			case "text-decoration": omitting(["text-decoration-line", "text-decoration-thickness", "text-decoration-style", "text-decoration-color"], "text-decoration-line");
			case "outline": omitting(["outline-width", "outline-style", "outline-color"], "outline-style");
			case "list-style":
				var image = v("list-style-image"), type = v("list-style-type");
				// (a type named as a position keeps the position, so the text reads back the same)
				var parts = isInitial("list-style-position") && type != "inside" && type != "outside" ? [] : [v("list-style-position")];
				if (image == "none" && type == "none") parts.push("none") else {
					if (!isInitial("list-style-image")) parts.push(image);
					if (!isInitial("list-style-type")) parts.push(type);
				}
				parts.length == 0 ? v("list-style-position") : parts.join(" ");
			case "grid-template": template_(v("grid-template-rows"), v("grid-template-columns"), v("grid-template-areas"));
			case "grid":
				var rows = v("grid-template-rows"), cols = v("grid-template-columns"), areas = v("grid-template-areas");
				var flow = v("grid-auto-flow"), autoRows = v("grid-auto-rows"), autoCols = v("grid-auto-columns");
				if (autoRows == "auto" && autoCols == "auto" && flow == "row") template_(rows, cols, areas) else if (areas == "none" && rows == "none" && autoCols == "auto"
					&& (flow == "row" || flow == "row dense" || flow == "dense"))
					'auto-flow${flow == "row" ? "" : " dense"}${autoRows == "auto" ? "" : " " + autoRows} / $cols'
				else if (areas == "none" && cols == "none" && autoRows == "auto" && (flow == "column" || flow == "column dense"))
					'$rows / auto-flow${flow == "column" ? "" : " dense"}${autoCols == "auto" ? "" : " " + autoCols}'
				else "";
			case "grid-row" | "grid-column":
				var a = v('$shorthand-start'), b = v('$shorthand-end');
				b == a && isIdent(a) || b == "auto" && !isIdent(a) ? a : '$a / $b';
			case "grid-area":
				var rs = v("grid-row-start"), cs = v("grid-column-start"), re = v("grid-row-end"), ce = v("grid-column-end");
				inline function omits(end:String, start:String):Bool
					return end == start && isIdent(start) || end == "auto" && !isIdent(start);
				var out = [rs, cs, re, ce];
				if (omits(ce, cs)) {
					out.pop();
					if (omits(re, rs)) {
						out.pop();
						if (omits(cs, rs)) out.pop();
					}
				}
				out.join(" / ");
			case "text-align":
				var all = v("text-align-all"), last = v("text-align-last");
				if (last == "auto") all else if (all == "justify" && last == "justify") "justify-all" else if (all == last && all == "match-parent") all else "";
			case "white-space":
				var c = v("white-space-collapse"), w = v("text-wrap-mode");
				switch [c, w] {
					case ["collapse", "wrap"]: "normal";
					case ["preserve", "nowrap"]: "pre";
					case ["preserve", "wrap"]: "pre-wrap";
					case ["preserve-breaks", "wrap"]: "pre-line";
					case _: [c == "collapse" ? null : c, w == "wrap" ? null : w].filter(x -> x != null).join(" ");
				}
			case "vertical-align":
				var source = v("baseline-source"), align = v("alignment-baseline"), shift = v("baseline-shift");
				// (a baseline-shift alone, or a keyword alone, as vertical-align was in CSS 2.1)
				var parts = [source == "auto" ? null : source, align == "baseline" ? null : align, shift == "0px" || shift == "0" || shift == "baseline" ? null : shift].filter(x -> x != null);
				parts.length == 0 ? "baseline" : parts.join(" ");
			case "font-synthesis":
				var on = ["weight", "style", "small-caps", "position"].filter(k -> v('font-synthesis-$k') == "auto");
				on.length == 0 ? "none" : on.join(" ");
			case "font-variant":
				var names = ["font-variant-ligatures", "font-variant-caps", "font-variant-alternates", "font-variant-numeric", "font-variant-east-asian", "font-variant-position",
					"font-variant-emoji"];
				var kept = names.filter(n -> !isInitial(n));
				if (kept.length == 0) "normal" else if (kept.length == 1 && v(kept[0]) == "none" && kept[0] == "font-variant-ligatures") "none" else if (v("font-variant-ligatures") == "none") "" else kept.map(n -> v(n)).join(" ");
			case "font":
				for (l in ["font-variant-ligatures", "font-variant-alternates", "font-variant-numeric", "font-variant-east-asian", "font-variant-position", "font-variant-emoji",
					"font-feature-settings", "font-kerning", "font-language-override", "font-optical-sizing", "font-size-adjust", "font-variation-settings"])
					if (!isInitial(l)) return "";
				var caps = v("font-variant-caps"), width = v("font-width");
				if (caps != "normal" && caps != "small-caps") return "";
				if (!["normal", "ultra-condensed", "extra-condensed", "condensed", "semi-condensed", "semi-expanded", "expanded", "extra-expanded", "ultra-expanded", "50%",
					"62.5%", "75%", "87.5%", "100%", "112.5%", "125%", "150%", "200%"].contains(width)) return "";
				var parts = [for (l in ["font-style", "font-variant-caps", "font-weight", "font-width"]) if (!isInitial(l)) l == "font-width" ? widthKeyword(v(l)) : v(l)];
				parts.push(isInitial("line-height") ? v("font-size") : '${v("font-size")} / ${v("line-height")}');
				parts.push(v("font-family"));
				parts.join(" ");
			case "background-position": layered(["background-position-x", "background-position-y"], texts, l -> '${l[0]} ${l[1]}');
			case "background":
				var names = ["background-image", "background-position-x", "background-position-y", "background-size", "background-repeat", "background-attachment",
					"background-origin", "background-clip"];
				var lists = [for (n in names) n => split(v(n))];
				var count = lists["background-image"].length;
				for (n in names) if (lists[n].length != count) return "";
				var layers = [];
				for (k in 0...count) {
					inline function at(n:String)
						return lists[n][k];
					var parts = [];
					if (at("background-image") != "none") parts.push(at("background-image"));
					var pos = '${at("background-position-x")} ${at("background-position-y")}', size = at("background-size");
					var initialPos = pos == "0% 0%", initialSize = size == "auto" || size == "auto auto";
					if (!initialPos || !initialSize) parts.push(initialSize ? pos : '$pos / $size');
					if (at("background-repeat") != "repeat") parts.push(at("background-repeat"));
					if (at("background-attachment") != "scroll") parts.push(at("background-attachment"));
					var origin = at("background-origin"), clip = at("background-clip");
					if (origin != "padding-box" || clip != "border-box") parts.push(origin == clip ? origin : '$origin $clip');
					if (k == count - 1 && !isInitial("background-color")) parts.push(v("background-color"));
					layers.push(parts.length == 0 ? "none" : parts.join(" "));
				}
				layers.join(", ");
			case "border-image":
				var source = v("border-image-source"), slice = v("border-image-slice"), width = v("border-image-width"), outset = v("border-image-outset"),
					repeat = v("border-image-repeat");
				var parts = [];
				if (!isInitial("border-image-source")) parts.push(source);
				var s = isInitial("border-image-slice") && isInitial("border-image-width") && isInitial("border-image-outset") ? null : slice;
				if (!isInitial("border-image-outset")) s = isInitial("border-image-width") ? '$slice / / $outset' : '$slice / $width / $outset' else if (!isInitial("border-image-width"))
					s = '$slice / $width';
				if (s != null) parts.push(s);
				if (!isInitial("border-image-repeat")) parts.push(repeat);
				parts.length == 0 ? "none" : parts.join(" ");
			case "margin-block" | "margin-inline" | "padding-block" | "padding-inline" | "inset-block" | "inset-inline" | "border-block-width" | "border-block-style"
				| "border-block-color" | "border-inline-width" | "border-inline-style" | "border-inline-color":
				var names = CssGrammars.property(shorthand).longhands;
				v(names[0]) == v(names[1]) ? v(names[0]) : '${v(names[0])} ${v(names[1])}';
			case "border-block" | "border-inline" | "border-block-start" | "border-block-end" | "border-inline-start" | "border-inline-end":
				var bs = borders(shorthand);
				if (!same([for (b in bs) v('$b-width')]) || !same([for (b in bs) v('$b-style')]) || !same([for (b in bs) v('$b-color')])) return "";
				omitting(['${bs[0]}-width', '${bs[0]}-style', '${bs[0]}-color'], '${bs[0]}-style');
			// (each transition: what isn't initial, the duration where a delay follows; all when nothing is)
			case "transition":
				layered(TRANSITION, texts, l -> {
					var out = [];
					if (l[0] != "all") out.push(l[0]);
					if (l[1] != "0s" || l[3] != "0s") out.push(l[1]);
					if (l[2] != "ease") out.push(l[2]);
					if (l[3] != "0s") out.push(l[3]);
					if (l[4] != "normal") out.push(l[4]);
					out.length == 0 ? "all" : out.join(" ");
				});
			case "line-clamp":
				var c = v("continue"), lines = v("max-lines"), e = v("block-ellipsis");
				if (c == "normal") return lines == "auto" && e == "no-ellipsis" ? "none" : "";
				if (c != "collapse" && c != "-webkit-legacy") return "";
				var legacy = c == "-webkit-legacy", out = [];
				if (lines != "auto" || e == "ellipsis" || !legacy) out.push(lines);
				if (e != "ellipsis") out.push(e);
				if (legacy) out.push(c);
				out.join(" ");
			case "all": "";
			case _:
				var names = CssGrammars.property(shorthand).longhands;
				omitting(names, names[0]);
		}
	}

	// ---- grid-template

	// none; rows / columns; or the areas' form: [names] "row" size [names] ... [/ columns]
	static function template(t:Array<CssTerm>):Null<Map<String, Array<CssTerm>>> {
		var out = new Map<String, Array<CssTerm>>();
		if (t.length == 1 && t[0].match(Keyword("none"))) {
			for (l in ["grid-template-rows", "grid-template-columns", "grid-template-areas"]) out.set(l, [Keyword("none")]);
			return out;
		}
		var halves = slashed(t);
		if (!t.exists(x -> x.match(Str(_)))) {
			if (halves.length != 2) return null;
			out.set("grid-template-rows", halves[0]);
			out.set("grid-template-columns", halves[1]);
			out.set("grid-template-areas", [Keyword("none")]);
			return out;
		}
		// (rows: names merged where two meet, auto for a row without a size)
		var rows:Array<CssTerm> = [], areas:Array<CssTerm> = [];
		var k = 0, h = halves[0];
		inline function names(into:Array<CssTerm>, b:CssTerm)
			switch [into.length > 0 ? into[into.length - 1] : null, b] {
				case [Brackets("[", a), Brackets("[", c)]: into[into.length - 1] = Brackets("[", a.concat(c));
				case _: into.push(b);
			}
		while (k < h.length) {
			if (h[k].match(Brackets(_, _))) {
				names(rows, h[k]);
				k++;
				continue;
			}
			if (!h[k].match(Str(_))) return null;
			areas.push(h[k++]);
			if (k < h.length && !h[k].match(Str(_) | Brackets(_, _))) rows.push(h[k++]) else rows.push(Keyword("auto"));
		}
		out.set("grid-template-areas", areas);
		out.set("grid-template-rows", [for (r in rows) r.match(Brackets("[", [])) ? null : r].filter(r -> r != null));
		out.set("grid-template-columns", halves.length > 1 ? halves[1] : [Keyword("none")]);
		return out;
	}

	static function template_(rows:String, cols:String, areas:String):String {
		if (areas == "none") return rows == "none" && cols == "none" ? "none" : '$rows / $cols';
		// (the areas' form: each string beside its row's size and names; a row track list of repeat() can't be)
		var strings = [for (a in spaced(areas)) if (a.fastCodeAt(0) == '"'.code) a];
		var out = [], row = 0;
		for (v in spaced(rows))
			if (v.fastCodeAt(0) == "[".code) out.push(v) else if (Css.lower(v).startsWith("repeat(")) return "" else {
				if (row >= strings.length) return "";
				out.push(strings[row++] + (v == "auto" ? "" : " " + v));
			}
		if (row != strings.length) return "";
		return out.join(" ") + (cols == "none" ? "" : ' / $cols');
	}

	// (a serialized value's items at its top level: split at white space
	// outside strings, brackets and functions, with no tokenizer)
	static function spaced(text:String):Array<String> {
		var out = [], depth = 0, quote = 0, start = -1, k = 0;
		while (k < text.length) {
			var c = text.fastCodeAt(k);
			if (quote != 0) {
				if (c == "\\".code) k++ else if (c == quote) quote = 0;
			} else if (c == '"'.code || c == "'".code) quote = c else if (c == "(".code || c == "[".code) depth++ else if (c == ")".code
				|| c == "]".code) depth-- else if (depth == 0 && (c == " ".code || c == "\t".code || c == "\n".code)) {
				if (start >= 0) out.push(text.substring(start, k));
				start = -1;
				k++;
				continue;
			}
			if (start < 0) start = k;
			k++;
		}
		if (start >= 0) out.push(text.substring(start));
		return out;
	}

	// ---- parts

	// (a shorthand's top-level parts by longhand: name to its terms)
	static function top(terms:Array<CssTerm>):Map<String, Array<CssTerm>> {
		var out = new Map<String, Array<CssTerm>>();
		function walk(ts:Array<CssTerm>)
			for (t in ts) switch t {
				case Part(n, inner) if (!n.startsWith("<") && !n.endsWith(")")): out.set(n, inner);
				case Part(_, inner): walk(inner);
				case _:
			}
		walk(terms);
		return out;
	}

	// (terms without Parts, functions' too)
	public static function plain(terms:Array<CssTerm>):Array<CssTerm> {
		var out = [];
		for (t in terms) switch t {
			case Part(_, inner): for (x in plain(inner)) out.push(x);
			case Func(n, args): out.push(Func(n, plain(args)));
			case Brackets(o, args): out.push(Brackets(o, plain(args)));
			case _: out.push(t);
		}
		return out;
	}

	// (a {1,4}'s items: each a part's terms, else each term)
	static function values(terms:Array<CssTerm>):Array<Array<CssTerm>>
		return [for (t in terms) switch t {
			case Part(_, inner): plain(inner);
			case _: [t];
		}];

	// (which of n values a side k takes: 1 all; 2 top-bottom and left-right; 3 top, left-right, bottom)
	static function side(n:Int, k:Int):Int
		return switch n {
			case 1: 0;
			case 2: k % 2;
			case 3: k == 3 ? 1 : k;
			case _: k;
		}

	static function sides(v:Array<String>):String {
		var n = 4;
		if (v[3] == v[1]) n = 3;
		if (n == 3 && v[2] == v[0]) n = 2;
		if (n == 2 && v[1] == v[0]) n = 1;
		return v.slice(0, n).join(" ");
	}

	static function same(xs:Array<String>):Bool
		return xs.foreach(x -> x == xs[0]);

	static function slashed(terms:Array<CssTerm>):Array<Array<CssTerm>> {
		var out = [[]];
		for (t in terms) if (t.match(Delim("/"))) out.push([]) else out[out.length - 1].push(t);
		return out;
	}

	static function ident(line:Array<CssTerm>):Bool
		return line.length == 1 && line[0].match(Ident(_));

	// (a line's text that is a name alone: not a number, auto, or span with one)
	static function isIdent(text:String):Bool {
		var l = Css.lower(text);
		if (text == "" || l == "auto" || l == "span") return false;
		var k = text.fastCodeAt(0) == "-".code ? 1 : 0;
		if (k == text.length) return false;
		var c = text.fastCodeAt(k);
		if (!(c == "_".code || c == "\\".code || c >= 0x80 || (c | 32) >= "a".code && (c | 32) <= "z".code || k == 1 && c == "-".code)) return false;
		var i = k;
		while (i < text.length) {
			var c = text.fastCodeAt(i++);
			// (an escape: up to six hex digits and the space after them, or one code point)
			if (c == "\\".code) {
				var n = 0;
				while (n < 6 && i < text.length && CssChars.isHex(text.fastCodeAt(i))) {
					i++;
					n++;
				}
				if (n == 0) i++ else if (i < text.length && text.fastCodeAt(i) == " ".code) i++;
			} else if (c == " ".code || c == "/".code || c == "(".code || c == "[".code || c == ",".code || c == '"'.code) return false;
		}
		return true;
	}

	// a position's horizontal and vertical parts (one value: the other centre)
	static function axes(l:Array<CssTerm>):Null<{x:Array<CssTerm>, y:Array<CssTerm>}> {
		inline function vertical(t:CssTerm):Bool
			return t.match(Keyword("top" | "bottom" | "y-start" | "y-end" | "block-start" | "block-end"));
		inline function horizontal(t:CssTerm):Bool
			return t.match(Keyword("left" | "right" | "x-start" | "x-end" | "inline-start" | "inline-end"));
		return switch l.length {
			case 1: vertical(l[0]) ? {x: [Keyword("center")], y: [l[0]]} : {x: [l[0]], y: [Keyword("center")]};
			case 2:
				var swap = vertical(l[0]) || horizontal(l[1]);
				{x: [swap ? l[1] : l[0]], y: [swap ? l[0] : l[1]]};
			case 3 | 4:
				var first = l[1].match(Keyword(_)) ? [l[0]] : [l[0], l[1]];
				var second = l.slice(first.length);
				var swap = vertical(first[0]) || horizontal(second[0]);
				{x: swap ? second : first, y: swap ? first : second};
			case _: null;
		}
	}

	// (font-variant's keywords by longhand)
	static function variant(t:CssTerm):String
		return switch t {
			case Keyword("common-ligatures" | "no-common-ligatures" | "discretionary-ligatures" | "no-discretionary-ligatures" | "historical-ligatures" |
				"no-historical-ligatures" | "contextual" | "no-contextual"):
				"font-variant-ligatures";
			case Keyword("small-caps" | "all-small-caps" | "petite-caps" | "all-petite-caps" | "unicase" | "titling-caps"): "font-variant-caps";
			case Keyword("lining-nums" | "oldstyle-nums" | "proportional-nums" | "tabular-nums" | "diagonal-fractions" | "stacked-fractions" | "ordinal" | "slashed-zero"):
				"font-variant-numeric";
			case Keyword("jis78" | "jis83" | "jis90" | "jis04" | "simplified" | "traditional" | "full-width" | "proportional-width" | "ruby"): "font-variant-east-asian";
			case Keyword("sub" | "super"): "font-variant-position";
			case Keyword("text" | "emoji" | "unicode"): "font-variant-emoji";
			case _: "font-variant-alternates";
		}

	static function widthKeyword(v:String):String
		return switch v {
			case "50%": "ultra-condensed";
			case "62.5%": "extra-condensed";
			case "75%": "condensed";
			case "87.5%": "semi-condensed";
			case "100%": "normal";
			case "112.5%": "semi-expanded";
			case "125%": "expanded";
			case "150%": "extra-expanded";
			case "200%": "ultra-expanded";
			case w: w;
		}

	// (a list's items at top-level commas)
	static function split(text:String):Array<String> {
		var out = [], depth = 0, start = 0;
		for (k in 0...text.length) switch text.charAt(k) {
			case "(": depth++;
			case ")": depth--;
			case "," if (depth == 0):
				out.push(text.substring(start, k).trim());
				start = k + 1;
			case _:
		}
		out.push(text.substring(start).trim());
		return out;
	}

	static function layered(names:Array<String>, texts:Map<String, String>, f:Array<String>->String):String {
		var lists = [for (n in names) split(texts[n])];
		for (l in lists) if (l.length != lists[0].length) return "";
		return [for (k in 0...lists[0].length) f([for (l in lists) l[k]])].join(", ");
	}

	// ---- initial values

	static final initials = new Map<String, Null<Array<CssTerm>>>();
	static final initialTexts = new Map<String, String>();

	// A longhand's initial value as terms (null when its spec says it in prose).
	public static function initialTerms(longhand:String):Null<Array<CssTerm>> {
		if (initials.exists(longhand)) return initials[longhand];
		#if macro
		var p = CssGrammars.property(longhand);
		var text = INITIAL.get(longhand) ?? (p == null ? null : p.initial);
		var v = text == null ? null : CssValues.parse(longhand, text);
		#else
		var v = CssInitial.of(longhand);
		#end
		var t = switch v {
			case Terms(t): t;
			case _: null;
		}
		initials.set(longhand, t);
		return t;
	}

	// (initial values webref has in prose, as their specs give them)
	static final INITIAL = [
		"font-family" => "serif", "font-size" => "medium", "color" => "CanvasText", "text-align-all" => "start", "font-feature-settings" => "normal",
		"font-variation-settings" => "normal", "font-language-override" => "normal", "background-position-x" => "0%", "background-position-y" => "0%",
		"line-height" => "normal", "quotes" => "auto"
	];

	public static function initialText(longhand:String, computed:Bool):String {
		var key = (computed ? "c " : "s ") + longhand;
		if (initialTexts.exists(key)) return initialTexts[key];
		var t = initialTerms(longhand);
		var text = t == null ? "" : computed ? CssValues.compute(longhand, Terms(t)) ?? "" : CssValues.serialize(longhand, Terms(t));
		initialTexts.set(key, text);
		return text;
	}
}
