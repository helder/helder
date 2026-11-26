package helder.css;

import helder.css.CssItems;
import helder.css.CssProperty;
import helder.css.CssTerm;
import helder.dom.Element;
import helder.dom.Node;

enum CssGeneratedPart {
	Text(text:String);
	Image(image:CssTerm);
	// what the paged stage resolves (string(), content(), leader(), target-counter()...)
	Other(term:CssTerm);
}

// Counters and quotes through a document in tree order (Lists 3 §4,
// Content 3 §3), as the box tree walks it: each element, then its
// ::marker, ::before, its children, its ::after. A counter an element
// makes (counter-reset, or a counter-increment, counter-set or counter()
// of a name not in scope) is in scope for its descendants and its
// following siblings, until a sibling makes one of the same name; resets
// apply, then increments (a list item's implicit list-item one: 1, or -1
// in a reversed counter), then sets. A reversed counter without a value
// starts at what its scope's increments say.
//
//   var counters = new CssCounters(styles);
//   counters.enter(li);
//   counters.marker(li);          // [Text("3. ")]
//   counters.enter(li, "before");
//   counters.content(li, "before");
//   counters.exit(li, "before");
//   ...children...
//   counters.exit(li);
class CssCounters {
	public final formats:CssCounterStyles;
	final styles:CssStyles;
	// (per name, the counters in scope, innermost last)
	final scopes = new Map<String, Array<Counter>>();
	// (per entered element, the names its children made: dropped when it exits)
	final levels:Array<Array<String>> = [[]];
	var quotes = 0;

	public function new(styles:CssStyles) {
		this.styles = styles;
		formats = new CssCounterStyles(styles.counterStyles);
	}

	// An element, or one of its pseudo-elements ("marker", "before",
	// "after": only those that are generated), entering: its counters.
	public function enter(el:Element, ?pseudo:String) {
		var s = styles.computed(el, pseudo);
		// (an element without a box of its own sets no counters, its children its parent's)
		if (pseudo == null && boxless(s)) return;
		var level = levels[levels.length - 1];
		// (counter-reset: only a name's last counts)
		var resets = s.counters(CounterReset);
		for (k in 0...resets.length) {
			var c = resets[k];
			if (Lambda.exists(resets.slice(k + 1), x -> x.name == c.name)) continue;
			make(level, c.name, c.value ?? (c.reversed ? reversedStart(c.name, el, pseudo) : 0), c.reversed);
		}
		var increments = s.counters(CounterIncrement);
		if (s.box.display.listItem && !Lambda.exists(increments, c -> c.name == "list-item")) {
			var current = innermost("list-item");
			increments.push({name: "list-item", value: current != null && current.reversed ? -1 : 1, reversed: false});
		}
		for (c in increments) {
			var counter = innermost(c.name) ?? make(level, c.name, 0, false);
			// (one that would overflow 32 bits is left out, as browsers do)
			var next = (counter.value : Float) + (c.value ?? 1);
			if (next <= 2147483647 && next >= -2147483648) counter.value = Std.int(next);
		}
		for (c in s.counters(CounterSet)) {
			var counter = innermost(c.name) ?? make(level, c.name, 0, false);
			counter.value = c.value ?? 0;
		}
		// (a counter content uses that isn't in scope: made here, at 0)
		var parts = s.generated();
		if (parts != null) for (p in parts) switch p {
			case Counter(name, _) | Counters(name, _, _) if (innermost(name) == null): make(level, name, 0, false);
			case _:
		}
		levels.push([]);
	}

	public function exit(el:Element, ?pseudo:String) {
		if (pseudo == null && boxless(styles.computed(el))) return;
		var made = levels.pop();
		for (name in made) scopes.get(name).pop();
	}

	static inline function boxless(s:CssStyle):Bool
		return s.box.display.outer == None || s.box.display.outer == Contents;

	// The innermost counter of the name's value (0 when there is none).
	public function value(name:String):Int {
		var c = innermost(name);
		return c == null ? 0 : c.value;
	}

	// Every counter of the name in scope, outermost first (counters()'s).
	public function values(name:String):Array<Int>
		return [for (c in scopes.get(name) ?? []) c.value];

	// The element's or pseudo-element's content resolved: strings,
	// counters in their styles, attributes, quotes (the depth kept from one
	// call to the next: call it once a box, in tree order), images; null
	// for normal and none.
	public function content(el:Element, ?pseudo:String):Null<Array<CssGeneratedPart>> {
		var s = styles.computed(el, pseudo);
		var items = s.generated();
		return items == null ? null : resolve(items, el, s);
	}

	// A list item's marker: ::marker's content, else list-style-image, else
	// list-style-type's text for its list-item counter (a style's prefix and
	// suffix, a string as it is); null for none.
	public function marker(el:Element):Null<Array<CssGeneratedPart>> {
		var s = styles.computed(el, "marker");
		if (s.keyword(Content) == "none") return null;
		var items = s.generated();
		if (items != null) return resolve(items, el, s);
		switch s.terms(ListStyleImage) {
			case [Keyword("none")]:
			case [image]: return [Image(image)];
			case _:
		}
		return switch s.terms(ListStyleType) {
			case [Keyword("none")]: null;
			case [Str(text)]: [Text(text)];
			case [Func("symbols", args)]: [Text(symbols(args, value("list-item"), true))];
			case [Keyword(name) | Ident(name)]: [Text(formats.marker(value("list-item"), name))];
			case _: null;
		}
	}

	function resolve(items:Array<CssContentItem>, el:Element, s:CssStyle):Array<CssGeneratedPart> {
		var out:Array<CssGeneratedPart> = [];
		function text(t:String) {
			if (out.length > 0) switch out[out.length - 1] {
				case Text(before):
					out[out.length - 1] = Text(before + t);
					return;
				case _:
			}
			out.push(Text(t));
		}
		for (item in items) switch item {
			case Text(t): text(t);
			case Image(i): out.push(Image(i));
			case Counter(name, style): text(format(value(name), style));
			case Counters(name, separator, style): text([for (v in values(name)) format(v, style)].join(separator));
			case Attribute(name): text(el.getAttribute(name) ?? "");
			case Quote(kind): text(quote(kind, s));
			case Other(t): out.push(Other(t));
		}
		return out;
	}

	// (Content 3 §3.4: the depth's pair, the last one past the list's end; auto: English's)
	function quote(kind:String, s:CssStyle):String {
		var pairs = switch s.terms(Quotes) {
			case [Keyword("none")]: [];
			case [Keyword("auto")] | [Keyword("match-parent")]: AUTO;
			case list:
				var strings = [for (t in list) switch t {
					case Str(x): x;
					case _: null;
				}].filter(x -> x != null);
				[for (k in 0...Std.int(strings.length / 2)) [strings[2 * k], strings[2 * k + 1]]];
		}
		inline function pair(depth:Int):Array<String>
			return pairs.length == 0 ? ["", ""] : pairs[depth < pairs.length ? depth : pairs.length - 1];
		return switch kind {
			case "open-quote": pair(quotes++)[0];
			case "no-open-quote":
				quotes++;
				"";
			case "close-quote" if (quotes > 0): pair(--quotes)[1];
			case "no-close-quote" if (quotes > 0):
				quotes--;
				"";
			case _: "";
		}
	}

	static final AUTO = [["“", "”"], ["‘", "’"]];

	// (a counter in a style: a name, none, or symbols()'s text)
	function format(v:Int, style:String):String {
		if (style == "none") return "";
		if (!StringTools.startsWith(style, "symbols(")) return formats.format(v, style);
		return switch Css.values(style) {
			case [Function(_, args, _, _)]:
				var system = "symbolic", list = [];
				for (a in args) switch a {
					case Token(_.kind => Ident(k)): system = Css.lower(k);
					case Token(_.kind => Str(x)): list.push(x);
					case _:
				}
				CssCounterStyles.symbols(system, list, v, false);
			case _: formats.format(v, "decimal");
		}
	}

	// (symbols()'s anonymous style: its system, then its strings)
	function symbols(args:Array<CssTerm>, v:Int, asMarker:Bool):String {
		var system = "symbolic", list = [];
		for (a in args) switch a {
			case Keyword(k) | Ident(k): system = k;
			case Str(x): list.push(x);
			case _:
		}
		return CssCounterStyles.symbols(system, list, v, asMarker);
	}

	inline function innermost(name:String):Null<Counter> {
		var l = scopes.get(name);
		return l == null || l.length == 0 ? null : l[l.length - 1];
	}

	// (Lists 3 §4.4.2: a counter the element or a previous sibling made of
	// the name goes; one an ancestor made stays, this one inside it)
	function make(level:Array<String>, name:String, value:Int, reversed:Bool):Counter {
		var l = scopes.get(name);
		if (l == null) scopes.set(name, l = []);
		if (level.contains(name)) l.pop() else level.push(name);
		var c = {value: value, reversed: reversed};
		l.push(c);
		return c;
	}

	// (Lists 3 §4.4.2: a reversed counter without a value starts at the sum
	// of its scope's increments negated, and its last non-zero one again; a
	// counter-set in its scope ends the sum at its value)
	function reversedStart(name:String, el:Element, pseudo:Null<String>):Int {
		var num = 0, last = 0;
		var done = false;
		function visit(e:Element, p:Null<String>, own:Bool) {
			if (done) return;
			var s = styles.computed(e, p);
			var resets = s.counters(CounterReset);
			// (a nested counter of the name: its scope isn't this one's)
			if (!own && Lambda.exists(resets, c -> c.name == name)) return;
			var inc = 0, explicit = false;
			for (c in s.counters(CounterIncrement)) if (c.name == name) {
				inc += c.value ?? 1;
				explicit = true;
			}
			if (!explicit && name == "list-item" && s.box.display.listItem) inc = -1;
			var negated = -inc;
			if (negated != 0) last = negated;
			for (c in s.counters(CounterSet)) if (c.name == name) {
				num += c.value ?? 0;
				done = true;
				return;
			}
			num += negated;
		}
		function tree(e:Element, own:Bool) {
			if (done) return;
			var s = styles.computed(e);
			if (s.box.display.outer == None) return;
			visit(e, null, own);
			if (!own && Lambda.exists(s.counters(CounterReset), c -> c.name == name)) return;
			for (p in ["marker", "before"]) if (generated(e, p)) visit(e, p, false);
			var c = e.firstElementChild;
			while (c != null && !done) {
				if (nests(c, name)) break;
				tree(c, false);
				c = c.nextElementSibling;
			}
			if (generated(e, "after")) visit(e, "after", false);
		}
		if (pseudo != null) {
			visit(el, pseudo, true);
			return num + last;
		}
		tree(el, true);
		// (the following siblings and theirs, till one makes its own counter of the name)
		var sib = el.nextElementSibling;
		while (sib != null && !done) {
			if (nests(sib, name)) break;
			tree(sib, false);
			sib = sib.nextElementSibling;
		}
		return num + last;
	}

	function nests(e:Element, name:String):Bool
		return Lambda.exists(styles.computed(e).counters(CounterReset), c -> c.name == name);

	function generated(e:Element, pseudo:String):Bool {
		if (pseudo == "marker") return styles.computed(e).box.display.listItem;
		return styles.computed(e, pseudo).generated() != null;
	}

}

private typedef Counter = {value:Int, reversed:Bool}
