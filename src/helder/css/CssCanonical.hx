package helder.css;

import helder.css.CssGrammar;
import helder.css.CssTerm;

using Lambda;
using StringTools;

// A specified value's canonical form: what CSSOM serializes when a value
// can be written several ways. The grammar's order comes from the
// matcher; here, the shortest of equivalent forms where the property's
// spec (or every browser) says so, and the rules a grammar can't say
// (a feature tag's four letters, one auto repetition of grid tracks).
class CssCanonical {
	public static function terms(property:String, terms:Array<CssTerm>):Array<CssTerm>
		return collapse(property, forms(property, [for (t in terms) images(t)]));

	// What the property's prose adds to its grammar: false where a matched value is invalid.
	public static function valid(property:String, terms:Array<CssTerm>):Bool {
		terms = CssShorthands.plain(terms);
		for (t in terms) if (!symbols(t) || !image(t)) return false;
		return switch property {
			// (CSS UI 4 §5.1: a cursor's image-set() of URLs only)
			case "cursor": !terms.exists(t -> switch t {
					case Func("image-set", args): args.exists(a -> a.match(Func(_, _)) && !a.match(Func("url" | "src", _)));
					case _: false;
				});
			// (Transitions 1 §2.2: a duration not negative; Easing 1 §2.3: steps() at least 1, 2 for jump-none)
			case "transition" | "transition-timing-function" | "transition-duration":
				var ok = true;
				for (layer in CssText.layers(terms)) {
					var times = layer.filter(t -> t.match(Dimension(_, "s" | "ms")));
					if (property != "transition-timing-function" && times.length > 0 && switch times[0] {
						case Dimension(v, _): v < 0;
						case _: false;
					}) ok = false;
					for (t in layer) switch t {
						case Func("steps", [Number(n, _), Delim(","), Keyword("jump-none")]) if (n < 2): ok = false;
						case Func("steps", [Number(n, _)]) | Func("steps", [Number(n, _), Delim(","), _]) if (n < 1): ok = false;
						case _:
					}
				}
				ok;
			// (Filter Effects 1 §5.1: no negative amounts, nor a negative blur)
			case "filter" | "backdrop-filter": terms.foreach(t -> switch t {
					case Func("drop-shadow", args): !blurNegative(args);
					case Func("hue-rotate", _): true;
					case Func(_, [Number(v, _) | Percentage(v) | Dimension(v, _)]): v >= 0;
					case _: true;
				});
			case "font-feature-settings" | "font-variation-settings": terms.foreach(t -> switch t {
					case Str(s): tag(s);
					case _: true;
				});
			case "font-language-override": terms.foreach(t -> switch t {
					case Str(s): s.length >= 1 && s.length <= 4 && ascii(s);
					case _: true;
				});
			case "grid-template-areas": areas(terms) != null;
			case "grid-template-columns" | "grid-template-rows" | "grid-template":
				terms.filter(t -> t.match(Func("repeat", [Keyword("auto-fill" | "auto-fit"), _]) | Func("repeat", [Keyword("auto-fill" | "auto-fit"), _, _])))
					.length <= 1;
			case "text-shadow":
				// (a text shadow's lengths: two or three, no spread)
				CssText.layers(terms).foreach(l -> l.filter(t -> t.match(Dimension(_, _) | Calc(_, _, _))).length <= 3);
			case _: true;
		}
	}

	// (drop-shadow()'s third length, its blur, negative)
	static function blurNegative(args:Array<CssTerm>):Bool {
		var lengths = args.filter(a -> a.match(Dimension(_, _)));
		return lengths.length >= 3 && switch lengths[2] {
			case Dimension(v, _): v < 0;
			case _: false;
		}
	}

	// (an axis along x, y or z as its name, the angle negated for a negative one; z alone left out)
	static function rotate(terms:Array<CssTerm>):Array<CssTerm> {
		inline function neg(a:CssTerm):CssTerm
			return switch a {
				case Dimension(v, u): Dimension(-v, u);
				case _: a;
			}
		return switch terms {
			case [Keyword("z"), a]: [a];
			case [Number(x, _), Number(y, _), Number(z, _), a]:
				if (y == 0 && z == 0 && x != 0) [Keyword("x"), x < 0 ? neg(a) : a] else if (x == 0 && z == 0 && y != 0) [Keyword("y"), y < 0 ? neg(a) : a] else
					if (x == 0 && y == 0 && z != 0) [z < 0 ? neg(a) : a] else terms;
			case _: terms;
		}
	}

	// palette-mix() as Fonts 4 §9.3 serializes it, as color-mix() does: the
	// default method (in oklab, shorter hue) left out, each item's percentage
	// after it; with no calc() left, the percentages left out share what the
	// others leave of 100%, and they're all left out when they're equal and
	// come to 100%, or one item's at 100%. (CssComputed asks again once its
	// calc()s are resolved.)
	public static function paletteMix(t:CssTerm):CssTerm {
		var args = switch t {
			case Func("palette-mix", a): CssShorthands.plain(a);
			case _: return t;
		}
		var layers = CssText.layers(args);
		var method = layers.length > 1 && layers[0].length > 0 && layers[0][0].match(Keyword("in")) ? layers.shift() : null;
		if (method != null) {
			inline function word(x:CssTerm):String
				return CssText.term(x).toLowerCase();
			if (method.length >= 4 && word(method[method.length - 2]) == "shorter" && word(method[method.length - 1]) == "hue")
				method = method.slice(0, -2);
			if (method.length == 2 && word(method[1]) == "oklab") method = null;
		}
		var items = [for (l in layers) {
			var value:Null<CssTerm> = null, share:Null<CssTerm> = null;
			for (x in l) switch x {
				case Percentage(_) | Calc(_, _, _): share = x;
				case _: value = paletteMix(x);
			}
			{value: value, share: share};
		}];
		var given = [for (i in items) switch i.share {
			case Percentage(p): p;
			case null: null;
			case _: Math.NaN;
		}];
		if (!given.exists(p -> p != null && Math.isNaN(p))) {
			var missing = given.filter(p -> p == null).length, sum = 0.0;
			for (p in given) if (p != null) sum += p;
			if (items.length == 1) {
				if (given[0] == 100) items[0].share = null;
			} else if (missing < items.length) {
				var each = Math.max(0, 100 - sum) / Math.max(missing, 1);
				var all = [for (p in given) p ?? each];
				var total = 0.0;
				for (p in all) total += p;
				var equal = !all.exists(p -> Math.abs(p - all[0]) > 1e-9) && Math.abs(total - 100) < 1e-9;
				for (k in 0...items.length) items[k].share = equal ? null : Percentage(all[k]);
			}
		}
		var out:Array<CssTerm> = method == null ? [] : method.concat([Delim(",")]);
		for (k in 0...items.length) {
			if (k > 0) out.push(Delim(","));
			if (items[k].value != null) out.push(items[k].value);
			if (items[k].share != null) out.push(items[k].share);
		}
		return Func("palette-mix", out);
	}

	static function forms(property:String, terms:Array<CssTerm>):Array<CssTerm> {
		return switch property {
			case "font-palette": [for (t in terms) paletteMix(t)];
			case "display": display(terms);
			case "align-content" | "align-items" | "align-self" | "justify-content" | "justify-items" | "justify-self" | "place-content" | "place-items"
				| "place-self":
				// (`first baseline` is `baseline`)
				[for (k in 0...terms.length) if (!(terms[k].match(Keyword("first")) && k + 1 < terms.length && terms[k + 1].match(Keyword("baseline")))) terms[k]];
			case "grid-auto-flow" if (terms.length == 2 && terms[0].match(Keyword("row"))): [terms[1]];
			case "counter-increment" | "counter-reset" | "counter-set":
				// (a counter's number when it has none: 1 to increment, 0 to set; a reversed one's counts down from its items)
				var out:Array<CssTerm> = [];
				for (k in 0...terms.length) {
					out.push(terms[k]);
					if (terms[k].match(Ident(_)) && (k + 1 >= terms.length || !terms[k + 1].match(Number(_, _) | Calc(_, _, _))))
						out.push(Number(property == "counter-increment" ? 1 : 0, true));
				}
				out;
			case "background-size": CssText.unlayers([for (l in CssText.layers(terms)) switch l {
					case [Keyword("auto"), Keyword("auto")]: [l[0]];
					case [Keyword("cover" | "contain" | "auto")]: l;
					case [_]: l.concat([Keyword("auto")]);
					case _: l;
				}]);
			case "background-repeat": CssText.unlayers([for (l in CssText.layers(terms)) repeat(l)]);
			case "background-position" | "object-position": CssText.unlayers([for (l in CssText.layers(terms)) position(l)]);
			case "transform-origin" if (terms.length == 1): position(terms);
			case "transform":
				// (rotate(0) and skew(0): their 0 an angle)
				[for (t in terms) switch t {
					case Func(f = "rotate" | "skew" | "skewx" | "skewy", args): Func(f, [for (a in args) a.match(Number(0, _)) ? Dimension(0, "deg") : a]);
					case _: t;
				}];
			// (a ratio's second number, 1 when left out, Values 4 §7.5)
			case "aspect-ratio":
				var out = [];
				for (k in 0...terms.length) {
					out.push(terms[k]);
					if (terms[k].match(Number(_, _) | Calc(_, _, _)) && (k + 1 >= terms.length || !terms[k + 1].match(Delim("/"))) && (k == 0 || !terms[k - 1].match(Delim("/"))))
						for (x in [Delim("/"), Number(1, true)]) out.push(x);
				}
				out;
			// (the shortest of Transforms 2's forms: a z of 0, a y of 0 after it; a z scale of 1, one x and y alike; an axis that is x, y or z)
			case "translate":
				var t = terms.copy();
				// (a 0% stays: it's a percentage of the box)
				if (t.length == 3 && t[2].match(Dimension(0, _) | Number(0, _))) t.pop();
				if (t.length == 2 && t[1].match(Dimension(0, _) | Number(0, _))) t.pop();
				t;
			case "scale":
				var t = [for (x in terms) switch x {
					case Percentage(p): Number(p / 100, false);
					case _: x;
				}];
				if (t.length == 3 && t[2].match(Number(1, _))) t.pop();
				if (t.length == 2 && CssText.term(t[0]) == CssText.term(t[1])) t.pop();
				t;
			case "rotate": rotate(terms);
			case "filter" | "backdrop-filter":
				// (grayscale(), invert(), opacity() and sepia() at most 100%; hue-rotate(0) an angle)
				[for (t in terms) switch t {
					case Func(f = "grayscale" | "invert" | "opacity" | "sepia", [Number(v, i)]) if (v > 1): Func(f, [Number(1, i)]);
					case Func(f = "grayscale" | "invert" | "opacity" | "sepia", [Percentage(v)]) if (v > 100): Func(f, [Percentage(100)]);
					case Func("hue-rotate", [Number(0, _)]): Func("hue-rotate", [Dimension(0, "deg")]);
					case _: t;
				}];
			// (Easing 1 §2.3: step-start and step-end as steps(); end, the default, left out)
			case "transition-timing-function":
				[for (t in terms) switch t {
					case Keyword("step-start"): Func("steps", [Number(1, true), Delim(","), Keyword("start")]);
					case Keyword("step-end"): Func("steps", [Number(1, true)]);
					case Func("steps", [n, Delim(","), Keyword("end" | "jump-end")]): Func("steps", [n]);
					case _: t;
				}];
			case "opacity":
				[for (t in terms) switch t {
					case Percentage(p): Number(p / 100, false);
					case _: t;
				}];
			case "font-feature-settings":
				// (a feature's value 1 or on is its default, off is 0)
				var out:Array<CssTerm> = [];
				for (k in 0...terms.length) {
					var after = k > 0 && terms[k - 1].match(Str(_));
					if (after && terms[k].match(Keyword("on") | Number(1, _))) continue;
					out.push(after && terms[k].match(Keyword("off")) ? Number(0, true) : terms[k]);
				}
				out;
			case "font-language-override":
				[for (t in terms) switch t {
					case Str(s): Str(s.rtrim());
					case _: t;
				}];
			case "font-family": [for (t in terms) family(t)];
			case "font-size-adjust": terms.filter(t -> !t.match(Keyword("ex-height")));
			case "font-style":
				switch terms {
					case [Keyword("oblique"), Dimension(0, "deg")]: [Keyword("normal")];
					case _: terms;
				}
			case "grid-template-areas": areas(terms) ?? terms;
			case "grid-template-columns" | "grid-template-rows" if (!terms.exists(t -> t.match(Keyword("subgrid")))):
				[for (t in terms) names(t)].filter(t -> !t.match(Brackets("[", [])));
			case "border-image-slice" | "border-image-width" | "border-image-outset":
				// (sides as few as say the same, fill after)
				var fill = terms.filter(t -> t.match(Keyword("fill"))), sides = terms.filter(t -> !t.match(Keyword("fill")));
				var s = [for (t in sides) CssText.term(t)], n = s.length;
				if (n == 4 && s[3] == s[1]) n = 3;
				if (n == 3 && s[2] == s[0]) n = 2;
				if (n == 2 && s[1] == s[0]) n = 1;
				sides.slice(0, n).concat(fill);
			case "grid-row-start" | "grid-row-end" | "grid-column-start" | "grid-column-end":
				// (span 1 with a name is span and the name)
				switch terms {
					case [Keyword("span"), Number(1, _), name = Ident(_)]: [terms[0], name];
					case _: terms;
				}
			case "text-emphasis-position": terms.length > 1 ? terms.filter(t -> !t.match(Keyword("right"))) : terms;
			case "content" | "list-style-type" | "list-style": [for (t in terms) counters(t)];
			case _: terms;
		}
	}

	// Display 3's short forms: block flow is block, inline flex inline-flex, block flow list-item list-item.
	static function display(terms:Array<CssTerm>):Array<CssTerm> {
		var w = [for (t in terms) switch t {
			case Keyword(k): k;
			case _: return terms;
		}];
		var outside = w.filter(x -> x == "block" || x == "inline" || x == "run-in")[0];
		var inside = w.filter(x -> ["flow", "flow-root", "table", "flex", "grid", "ruby"].contains(x))[0];
		var out = if (w.contains("list-item")) {
			[outside == "block" ? null : outside, inside == "flow-root" ? inside : null, "list-item"].filter(x -> x != null);
		} else if (outside == null && inside == null) w else if (inside == null || inside == "flow") [outside ?? "block"] else if (inside == "ruby") {
			outside == null || outside == "inline" ? ["ruby"] : [outside, "ruby"];
		} else switch outside {
			case null | "block": [inside];
			case "inline": [inside == "flow-root" ? "inline-block" : 'inline-$inside'];
			case o: [o, inside];
		}
		return [for (x in out) Keyword(x)];
	}

	// a repeat-style's two of a kind as one, repeat no-repeat as repeat-x
	static function repeat(l:Array<CssTerm>):Array<CssTerm>
		return switch l {
			case [Keyword("repeat"), Keyword("no-repeat")]: [Keyword("repeat-x")];
			case [Keyword("no-repeat"), Keyword("repeat")]: [Keyword("repeat-y")];
			case [Keyword(a), Keyword(b)] if (a == b): [l[0]];
			case _: l;
		}

	// a one-value <position> as its two, horizontal first
	public static function position(l:Array<CssTerm>):Array<CssTerm>
		return switch l {
			case [Keyword("top" | "bottom" | "y-start" | "y-end")]: [Keyword("center"), l[0]];
			case [Keyword("center")]: [l[0], l[0]];
			case [Keyword("left" | "right" | "x-start" | "x-end")]: [l[0], Keyword("center")];
			case [Keyword(_)]: l;
			case [_]: [l[0], Keyword("center")];
			case [Keyword("top" | "bottom" | "y-start" | "y-end"), Keyword("left" | "right" | "center" | "x-start" | "x-end")]: [l[1], l[0]];
			case _: l;
		}

	// counter()'s and counters()' default style left out, symbols()' default type
	static function counters(t:CssTerm):CssTerm
		return switch t {
			case Func("counter", [name, Delim(","), Ident(s) | Keyword(s)]) if (Css.lower(s) == "decimal"): Func("counter", [name]);
			case Func("counters", [name, Delim(","), sep, Delim(","), Ident(s) | Keyword(s)]) if (Css.lower(s) == "decimal"): Func("counters", [name, Delim(","), sep]);
			case Func("counter", args): Func("counter", [for (a in args) counters(a)]);
			case Func("counters", args): Func("counters", [for (a in args) counters(a)]);
			case Func("symbols", args) if (args.length > 1 && args[0].match(Keyword("symbolic"))): Func("symbols", args.slice(1));
			case _: t;
		}

	// (symbols(): numeric and alphabetic take two symbols or more, and no images)
	static function symbols(t:CssTerm):Bool
		return switch t {
			case Func("symbols", args):
				var n = args.filter(a -> !a.match(Keyword(_))).length;
				!args.exists(a -> a.match(Url(_, _) | Func(_, _))) && (args.length == 0 || !args[0].match(Keyword("numeric" | "alphabetic")) || n >= 2);
			case Func(_, args) | Brackets(_, args): args.foreach(symbols);
			case _: true;
		}

	// (a radial gradient's circle takes one length, an ellipse two; image-set()'s
	// resolutions are positive and its images no image-set())
	static function image(t:CssTerm):Bool
		return switch t {
			case Func("radial-gradient" | "repeating-radial-gradient", args):
				var head = [];
				for (a in args) {
					if (a.match(Delim(",") | Keyword("at"))) break;
					head.push(a);
				}
				var lengths = head.filter(a -> a.match(Dimension(_, _) | Percentage(_) | Calc(_, _, _)));
				var circle = head.exists(a -> a.match(Keyword("circle"))), ellipse = head.exists(a -> a.match(Keyword("ellipse")));
				!(circle && (lengths.length > 1 || lengths.exists(a -> a.match(Percentage(_))))) && !(ellipse && lengths.length == 1);
			case Func("image-set", args):
				args.foreach(a -> switch a {
					case Dimension(v, "x" | "dppx" | "dpi" | "dpcm"): v >= 0;
					case Func("image-set", _): false;
					case _: image(a);
				});
			case Func(_, args): args.foreach(image);
			case _: true;
		}

	// image-set()'s strings as url(), a resolution of 1x where none is given
	static function images(t:CssTerm):CssTerm
		return switch t {
			case Func("image-set", args): Func("image-set", CssText.unlayers([for (l in CssText.layers(args)) {
					var o = [for (a in l) switch a {
						case Str(s): Url(s, []);
						case _: images(a);
					}];
					o.exists(a -> a.match(Dimension(_, "x" | "dppx" | "dpi" | "dpcm") | Calc(_, "resolution", _))) ? o : [o[0], Dimension(1, "x")].concat(o.slice(1));
				}]));
			case Func(name = "radial-gradient" | "repeating-radial-gradient", args): Func(name, radial(args));
			case Func(name = "conic-gradient" | "repeating-conic-gradient", args): Func(name, centred(args));
			case Func(name, args): Func(name, [for (a in args) images(a)]);
			case _: t;
		}

	// radial-gradient()'s defaults left out: ellipse, farthest-corner, a single length's circle, a centre
	static function radial(args:Array<CssTerm>):Array<CssTerm> {
		var comma = -1;
		for (k in 0...args.length) if (args[k].match(Delim(","))) {
			comma = k;
			break;
		}
		if (comma < 0) return args;
		var head = args.slice(0, comma), at = -1;
		for (k in 0...head.length) if (head[k].match(Keyword("at"))) at = k;
		var shape = at < 0 ? head : head.slice(0, at), place = at < 0 ? [] : head.slice(at);
		var sizes = shape.filter(t -> !t.match(Keyword("circle" | "ellipse")));
		var circle = shape.exists(t -> t.match(Keyword("circle")));
		var size = sizes.filter(t -> !t.match(Keyword("farthest-corner")));
		var out:Array<CssTerm> = [];
		if (circle && !(size.length == 1 && size[0].match(Dimension(_, _) | Calc(_, _, _)))) out.push(Keyword("circle"));
		for (t in size) out.push(t);
		return finish(out.concat(center(place)), args.slice(comma));
	}

	static function centred(args:Array<CssTerm>):Array<CssTerm> {
		var comma = -1;
		for (k in 0...args.length) if (args[k].match(Delim(","))) {
			comma = k;
			break;
		}
		if (comma < 0) return args;
		var head = args.slice(0, comma), at = -1;
		// (from 0deg is the default)
		if (head.length >= 2 && head[0].match(Keyword("from")) && head[1].match(Dimension(0, _) | Number(0, _))) head = head.slice(2);
		for (k in 0...head.length) if (head[k].match(Keyword("at"))) at = k;
		if (at < 0) return finish(head, args.slice(comma));
		return finish(head.slice(0, at).concat(center(head.slice(at))), args.slice(comma));
	}

	// (`at` a centre left out)
	static function center(place:Array<CssTerm>):Array<CssTerm> {
		if (place.length == 0) return place;
		var p = place.slice(1).map(t -> CssText.term(t));
		var centre = switch p {
			case ["center"] | ["center", "center"] | ["50%"] | ["50%", "50%"] | ["center", "50%"] | ["50%", "center"]: true;
			case _: false;
		}
		return centre ? [] : place;
	}

	static function finish(head:Array<CssTerm>, rest:Array<CssTerm>):Array<CssTerm>
		return head.length == 0 ? rest.slice(1) : head.concat(rest);

	// a family name of identifiers unquoted (as browsers write it), unless one is a keyword
	static function family(t:CssTerm):CssTerm
		return switch t {
			case Str(s):
				var words = s.split(" ");
				var plain = words.foreach(w -> ~/^-?[A-Za-z_][A-Za-z0-9_-]*$/.match(w)) && !GENERIC.contains(Css.lower(s))
					&& !words.exists(w -> ["initial", "inherit", "unset", "revert", "revert-layer", "default"].contains(Css.lower(w)));
				plain ? Raw(s) : t;
			case _: t;
		}

	static final GENERIC = [
		"serif", "sans-serif", "cursive", "fantasy", "monospace", "system-ui", "emoji", "math", "fangsong", "ui-serif", "ui-sans-serif", "ui-monospace",
		"ui-rounded", "generic"
	];

	// (empty line names left out: [] 150px is 150px)
	static function names(t:CssTerm):CssTerm
		return switch t {
			case Func("repeat", args): Func("repeat", [for (a in args) names(a)].filter(a -> !a.match(Brackets("[", []))));
			case _: t;
		}

	// grid-template-areas' strings: their cells one space apart, a run of
	// dots one; null when one is empty, or rows have different counts of cells
	static function areas(terms:Array<CssTerm>):Null<Array<CssTerm>> {
		if (terms.length == 1 && terms[0].match(Keyword("none"))) return terms;
		var out = [], columns = -1;
		for (t in terms) switch t {
			case Str(s):
				var cells = [], k = 0;
				while (k < s.length) {
					var c = s.charAt(k);
					if (c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\x0C") {
						k++;
						continue;
					}
					var start = k;
					if (c == ".") {
						while (k < s.length && s.charAt(k) == ".") k++;
						cells.push(".");
					} else {
						while (k < s.length && !" \t\n\r\x0C.".contains(s.charAt(k))) k++;
						cells.push(s.substring(start, k));
					}
				}
				if (cells.length == 0 || columns >= 0 && cells.length != columns) return null;
				columns = cells.length;
				out.push(Str(cells.join(" ")));
			case _: return null;
		}
		return out;
	}

	// (an OpenType tag: four printable ASCII characters)
	static function tag(s:String):Bool
		return s.length == 4 && ascii(s);

	static function ascii(s:String):Bool {
		for (k in 0...s.length) {
			var c = s.fastCodeAt(k);
			if (c < 0x20 || c > 0x7E) return false;
		}
		return true;
	}

	// (a {1,4} of sides as few as say the same, a {1,2} or `a b?` pair as one when both are)
	public static function collapse(property:String, terms:Array<CssTerm>):Array<CssTerm> {
		var p = CssGrammars.property(property);
		if (p == null) return terms;
		var max = switch CssGrammars.of(p.syntax) {
			case Repeat(_, 1, 4, false): 4;
			case Repeat(_, 1, 2, false): 2;
			case Sequence([a, Repeat(b, 0, 1, false)]) if (single(a) && single(b)): 2;
			case _: 0;
		}
		if (max == 0 || terms.length > max || terms.length < 2) return terms;
		for (t in terms) if (t.match(Delim(_))) return terms;
		var s = [for (t in terms) CssText.term(t)];
		var n = s.length;
		if (max == 2) return s[0] == s[1] ? [terms[0]] : terms;
		if (n == 4 && s[3] == s[1]) n = 3;
		if (n == 3 && s[2] == s[0]) n = 2;
		if (n == 2 && s[1] == s[0]) n = 1;
		return terms.slice(0, n);
	}

	static function single(g:CssGrammar):Bool
		return g.match(Prop(_) | Named(_, _));
}
