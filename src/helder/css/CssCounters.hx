package helder.css;

import helder.css.CssItems;
import helder.css.CssProperty;
import helder.css.CssTerm;
import helder.dom.Element;
import helder.dom.Node;

enum CssGeneratedPart {
	Text(text:String);
	Image(image:CssTerm);
	// GCPM 3, what the paged host fills: a named string's value on the page
	// (CssRunning), a running element, a leader's fill to the line's room
	StringValue(name:String, which:String);
	RunningElement(name:String, which:String);
	Leader(fill:String);
	// a cross-reference: its text once resolveTargets has run
	Target(target:CssTarget);
	Other(term:CssTerm);
}

// A cross-reference (Content 3 §3: target-counter(), target-counters(),
// target-text()): the element its fragment names (#id, in the document),
// what of it, and its text, null until CssCounters.resolveTargets fills
// it (a page counter needs the pages).
class CssTarget {
	public final element:Null<Element>;
	// "counter", "counters" or "text"
	public final kind:String;
	// the counter's name, or target-text()'s part (content, before, after, first-letter)
	public final name:String;
	public final separator:String;
	public final style:String;
	@:allow(helder.css.CssCounters) public var text(default, null):Null<String> = null;

	@:allow(helder.css.CssCounters)
	function new(element, kind, name, separator, style) {
		this.element = element;
		this.kind = kind;
		this.name = name;
		this.separator = separator;
		this.style = style;
	}
}

// A heading's bookmark (GCPM 3 §4): its level, label and state.
typedef CssBookmark = {level:Int, label:String, open:Bool}

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
class CssCounters implements CssCounting {
	public final formats:CssCounterStyles;
	final styles:CssStyles;
	// (per name, the counters in scope, innermost last)
	final scopes = new Map<String, Array<Counter>>();
	// (per entered element, the names its children made: dropped when it exits)
	final levels:Array<Array<String>> = [[]];
	var quotes = 0;
	// (style containment's boundaries, innermost last: its element's level,
	// the counters made before it (counted: how many so far), the quote depth entering it)
	final contained:Array<{level:Int, counted:Int, quotes:Int}> = [];
	var counted = 0;
	// (cross-references made, and per element with an id, its counters and
	// its ::before's and ::after's text, as the walk met them)
	final targets:Array<CssTarget> = [];
	final snapshots = new haxe.ds.ObjectMap<Element, Map<String, Array<Int>>>();
	final pseudoText = new haxe.ds.ObjectMap<Element, Map<String, String>>();

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
			var current = inside("list-item");
			increments.push({name: "list-item", value: current != null && current.reversed ? -1 : 1, reversed: false});
		}
		for (c in increments) {
			var counter = inside(c.name) ?? make(level, c.name, 0, false);
			// (one that would overflow 32 bits is left out, as browsers do)
			var next = (counter.value : Float) + (c.value ?? 1);
			if (next <= 2147483647 && next >= -2147483648) counter.value = Std.int(next);
		}
		for (c in s.counters(CounterSet)) {
			var counter = inside(c.name) ?? make(level, c.name, 0, false);
			counter.value = c.value ?? 0;
		}
		// (a counter content uses that isn't in scope: made here, at 0)
		var parts = s.generated();
		if (parts != null) for (p in parts) switch p {
			case Counter(name, _) | Counters(name, _, _) if (innermost(name) == null): make(level, name, 0, false);
			case _:
		}
		// (an element a cross-reference may name: its counters as they are here)
		if (pseudo == null && el.getAttribute("id") != null) snapshots.set(el, [for (name => list in scopes) if (list.length > 0) name => [for (c in list) c.value]]);
		// (style containment, Contain 2 §3.3: in its subtree, below the element's own counters, increments and sets make counters
		// of their own, and quotes nest there alone)
		if (pseudo == null && s.containment().has(Style)) contained.push({level: levels.length - 1, counted: counted, quotes: quotes});
		levels.push([]);
	}

	public function exit(el:Element, ?pseudo:String) {
		var s = styles.computed(el);
		if (pseudo == null && boxless(s)) return;
		var made = levels.pop();
		for (name in made) scopes.get(name).pop();
		if (pseudo == null && contained.length > 0 && contained[contained.length - 1].level == levels.length - 1 && s.containment().has(Style))
			quotes = contained.pop().quotes;
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
		if (items == null) return null;
		var out = resolve(items, el, s);
		if ((pseudo == "before" || pseudo == "after") && el.getAttribute("id") != null) {
			var m = pseudoText.get(el);
			if (m == null) pseudoText.set(el, m = new Map());
			m.set(pseudo, plain(out));
		}
		return out;
	}

	// The element's string-set (GCPM 3 §1.1), each name's value evaluated
	// here: strings, counters as they are, attributes, content() of the
	// element (text: its text, white space collapsed; before, after,
	// marker; first-letter), quotes at their depth (left as they were);
	// page and pages: the page counters, once the host knows them (0: as
	// the counters in scope have them). Call it after entering the element.
	public function strings(el:Element, page = 0, pages = 0):Array<{name:String, value:String}> {
		var s = styles.computed(el);
		this.page = page;
		this.pages = pages;
		return [for (set in CssItems.strings(s.terms(StringSet))) {name: set.name, value: text(set.items, el, s)}];
	}

	var page = 0;
	var pages = 0;

	// The element's bookmark (GCPM 3 §4: bookmark-level, its label
	// evaluated here as string-set's, bookmark-state); null for a level of
	// none. HTML's headings have their levels (WeasyPrint's UA rules).
	public function bookmark(el:Element):Null<CssBookmark> {
		var s = styles.computed(el);
		var level = switch s.terms(BookmarkLevel) {
			case [Number(n, _)]: Std.int(n);
			case _: return null;
		}
		var label = CssItems.content(s.terms(BookmarkLabel)) ?? [ContentOf("text")];
		page = pages = 0;
		return {level: level, label: text(label, el, s), open: s.keyword(BookmarkState) != "closed"};
	}

	// Every cross-reference's text, once the pages are known (pageOf: the
	// page an element starts on, for target-counter(..., page)); the
	// walk must have passed their targets.
	public function resolveTargets(pageOf:Element->Int) {
		for (t in targets) t.text = if (t.element == null) "" else switch t.kind {
			case "counter" if (t.name == "page"): format(pageOf(t.element), t.style);
			case "counter":
				var list = snapshots.get(t.element)?.get(t.name);
				format(list == null ? 0 : list[list.length - 1], t.style);
			case "counters":
				var list = snapshots.get(t.element)?.get(t.name) ?? [0];
				[for (v in list) format(v, t.style)].join(t.separator);
			case _: switch t.name {
					case "before" | "after": pseudoText.get(t.element)?.get(t.name) ?? "";
					case "first-letter": firstLetter(textOf(t.element));
					case _: textOf(t.element);
				}
		}
	}

	// (items as text where they are: what string-set and bookmark-label take)
	function text(items:Array<CssContentItem>, el:Element, s:CssStyle):String {
		var b = new StringBuf();
		for (item in items) switch item {
			case Text(t): b.add(t);
			case Counter("page", style) if (page > 0): b.add(format(page, style));
			case Counter("pages", style) if (pages > 0): b.add(format(pages, style));
			case Counter(name, style): b.add(format(value(name), style));
			case Counters(name, separator, style): b.add([for (v in values(name)) format(v, style)].join(separator));
			case Attribute(name): b.add(el.getAttribute(name) ?? "");
			case Quote(kind): b.add(quoteAt(kind, s));
			case ContentOf(part = "before" | "after"):
				var p = styles.computed(el, part), items = p.generated();
				if (items != null) b.add(text(items, el, p));
			case ContentOf("marker"):
				var m = s.box.display.listItem ? marker(el) : null;
				if (m != null) b.add(plain(m));
			case ContentOf("first-letter"): b.add(firstLetter(textOf(el)));
			case ContentOf(_): b.add(textOf(el));
			case _:
		}
		return b.toString();
	}

	// (an element's text, white space collapsed as white-space: normal does)
	static function textOf(el:Element):String
		return StringTools.trim(~/[ \t\n\r\x0C]+/g.replace(el.textContent ?? "", " "));

	// (CSS 2.1 §5.12.2's first letter: punctuation before and after it with it)
	static function firstLetter(text:String):String {
		var i = 0, n = text.length;
		// (Unicode's punctuation where it is common: ASCII's, Latin-1's, General Punctuation, CJK's)
		inline function punct(c:Int):Bool
			return c < 0x80 ? c > 0x20 && !(c >= "0".code && c <= "9".code || c >= "A".code && c <= "Z".code || c >= "a".code && c <= "z".code)
				: c == 0xA1 || c == 0xA7 || c == 0xAB || c == 0xB6 || c == 0xB7 || c == 0xBB || c == 0xBF || c >= 0x2010 && c <= 0x2027
				|| c >= 0x2030 && c <= 0x205E || c >= 0x3001 && c <= 0x3003 || c >= 0x3008 && c <= 0x3011;
		while (i < n && punct(StringTools.fastCodeAt(text, i))) i++;
		if (i < n) i++;
		while (i < n && punct(StringTools.fastCodeAt(text, i))) i++;
		return text.substr(0, i);
	}

	static function plain(parts:Array<CssGeneratedPart>):String
		return [for (p in parts) switch p {
			case Text(t): t;
			case _: "";
		}].join("");

	// (a cross-reference's element: a fragment, "#id", in the element's document)
	function target(href:CssTerm, el:Element):Null<Element> {
		var u = switch href {
			case Str(v) | Url(v, _): v;
			case Func("attr", args):
				var name = switch args[0] {
					case Ident(n): n;
					case _: null;
				}
				name == null ? null : el.getAttribute(name);
			case _: null;
		}
		if (u == null) return null;
		var hash = u.indexOf("#");
		if (hash < 0) return null;
		var id = StringTools.urlDecode(u.substr(hash + 1));
		return id == "" ? null : el.ownerDocument?.getElementById(id);
	}

	// A list item's marker: ::marker's content, else list-style-image, else
	// list-style-type's text for its list-item counter (a style's prefix and
	// suffix, a string as it is); null for none.
	public function listMarker(v:Int, type:String):String
		return formats.marker(v, type);

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
			case StringValue(name, which): out.push(StringValue(name, which));
			case RunningElement(name, which): out.push(RunningElement(name, which));
			case Leader(fill): out.push(Leader(fill));
			case ContentOf(_): text(this.text([item], el, s));
			case TargetCounter(href, name, style): out.push(Target(made(new CssTarget(target(href, el), "counter", name, "", style))));
			case TargetCounters(href, name, separator, style):
				out.push(Target(made(new CssTarget(target(href, el), "counters", name, separator, style))));
			case TargetText(href, part): out.push(Target(made(new CssTarget(target(href, el), "text", part, "", ""))));
			case Other(t): out.push(Other(t));
		}
		return out;
	}

	function made(t:CssTarget):CssTarget {
		targets.push(t);
		return t;
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

	// (a quote's text at the depth, the depth left as it is: string-set's)
	function quoteAt(kind:String, s:CssStyle):String {
		var depth = quotes;
		var t = quote(kind, s);
		quotes = depth;
		return t;
	}

	static final AUTO = [["“", "”"], ["‘", "’"]];

	// (a counter in a style: a name, none, or symbols() as CssItems writes it)
	public function format(v:Int, style:String):String {
		if (style == "none") return "";
		if (!StringTools.startsWith(style, "symbols(")) return formats.format(v, style);
		var parts = style.substring("symbols(".length, style.length - 1).split("\x1f");
		return CssCounterStyles.symbols(Css.lower(parts[0]), parts.slice(1), v, false);
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

	// (the innermost counter of the name an increment or set may change: none made outside the innermost style containment)
	function inside(name:String):Null<Counter> {
		var c = innermost(name);
		return c == null || contained.length == 0 || c.order >= contained[contained.length - 1].counted ? c : null;
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
		var c = {value: value, reversed: reversed, order: counted++};
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
			// (a style-contained subtree's increments make its own counter, Contain 2 §3.3)
			if (!own && s.containment().has(Style)) return;
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

private typedef Counter = {value:Int, reversed:Bool, order:Int}
