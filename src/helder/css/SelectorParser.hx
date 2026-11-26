package helder.css;

import helder.css.CssSelector;
import helder.css.CssToken.CssTokenKind;
import helder.dom.ElementState;

using StringTools;

// Selectors 4's grammar over component values (a rule's prelude, a
// pseudo-class's arguments): whitespace is a descendant combinator, a
// namespace prefix must be declared, an unknown pseudo-class or
// pseudo-element makes its selector invalid. Inside :is(), :where(),
// :not(), :has() and :nth-child(of) a pseudo-element is invalid, and
// :has() does not nest.
class SelectorParser {
	final namespaces:Null<CssNamespaces>;
	// (in a pseudo-class's arguments: no pseudo-elements there)
	var inner = 0;
	var inHas = false;

	public function new(?namespaces:CssNamespaces)
		this.namespaces = namespaces;

	// a list: each top-level comma's part a complex selector; forgiving:
	// an invalid one dropped (:is(), :where()), else the whole list null
	public function list(values:Array<CssValue>, relative:Bool, forgiving:Bool):Null<Array<CssSelector>> {
		var out = [];
		for (part in split(values)) {
			var s = complex(new Cursor(part), relative);
			if (s != null) out.push(s) else if (!forgiving) return null;
		}
		return out;
	}

	static function split(values:Array<CssValue>):Array<Array<CssValue>> {
		var parts = [], part = [];
		for (v in values)
			if (v.match(Token({kind: Comma}))) {
				parts.push(part);
				part = [];
			} else part.push(v);
		parts.push(part);
		return parts;
	}

	function complex(c:Cursor, relative:Bool):Null<CssSelector> {
		c.whitespace();
		var lead = null;
		if (relative) {
			lead = c.combinator() ?? Descendant;
			c.whitespace();
		}
		var compounds = [], combinators = [], pseudo:Null<CssPseudoElement> = null;
		while (true) {
			if (pseudo != null) return null;
			var r = compound(c);
			if (r == null) return null;
			compounds.push(r.simple);
			pseudo = r.pseudo;
			var spaced = c.whitespace();
			if (c.end()) break;
			var k = c.combinator();
			if (k != null) c.whitespace() else if (spaced) k = Descendant else return null;
			if (c.end()) return null;
			combinators.push(k);
		}
		return new CssSelector(compounds, combinators, lead, pseudo);
	}

	function compound(c:Cursor):Null<{simple:CssCompound, pseudo:Null<CssPseudoElement>}> {
		var simple:CssCompound = [], pseudo:Null<CssPseudoElement> = null;
		switch type(c) {
			case Fail: return null;
			case None:
			case Some(s): simple.push(s);
		}
		while (!c.end()) {
			if (pseudo != null) {
				// (after a pseudo-element: the user-action pseudo-classes alone)
				if (!c.is(Colon) || c.isAt(1, Colon)) break;
				var name = switch c.at(1) {
					case Token({kind: Ident(n)}): Css.lower(n);
					default: return null;
				}
				if (!STATES.exists(name) || name == "target") return null;
				c.skip(2);
				simple.push(Pseudo(State(STATES.get(name), name)));
				continue;
			}
			switch c.peek() {
				case Token({kind: Hash(name, id)}):
					if (!id) return null;
					c.skip(1);
					simple.push(Id(name));
				case Token({kind: Delim(".")}):
					switch c.at(1) {
						case Token({kind: Ident(name)}):
							c.skip(2);
							simple.push(Class(name));
						default: return null;
					}
				case Block({kind: OpenSquare}, values, _):
					c.skip(1);
					var a = attribute(new Cursor(values));
					if (a == null) return null;
					simple.push(a);
				case Token({kind: Colon}):
					if (c.isAt(1, Colon)) {
						if (inner > 0) return null;
						c.skip(2);
						pseudo = pseudoElement(c.next());
						if (pseudo == null) return null;
					} else {
						c.skip(1);
						var v = c.next();
						var legacy = switch v {
							case Token({kind: Ident(n)}): LEGACY.get(Css.lower(n));
							default: null;
						}
						if (legacy != null) {
							if (inner > 0) return null;
							pseudo = legacy;
						} else {
							var p = pseudoClass(v);
							if (p == null) return null;
							simple.push(Pseudo(p));
						}
					}
				default:
					break;
			}
		}
		if (simple.length == 0 && pseudo == null) return null;
		return {simple: simple, pseudo: pseudo};
	}

	// (a type or universal selector, its namespace prefix if any)
	function type(c:Cursor):Parsed<CssSimple> {
		inline function named(v:Null<CssValue>, ns:CssNamespace):Parsed<CssSimple>
			return switch v {
				case Token({kind: Ident(n)}): Some(Type(n, ns));
				case Token({kind: Delim("*")}): Some(Universal(ns));
				default: Fail;
			}
		switch [c.peek(), c.at(1)] {
			case [Token({kind: Ident(_) | Delim("*")}), Token({kind: Delim("|")})] if (c.at(2) != null && isName(c.at(2))):
				var ns = switch c.peek() {
					case Token({kind: Ident(p)}):
						var uri = namespaces?.prefixes?.get(p);
						if (uri == null) return Fail;
						uri == "" ? NoNamespace : Uri(uri);
					default: AnyNamespace;
				}
				c.skip(2);
				return named(c.next(), ns);
			case [Token({kind: Delim("|")}), v] if (v != null && isName(v)):
				c.skip(1);
				return named(c.next(), NoNamespace);
			case [Token({kind: Ident(_) | Delim("*")}), _]:
				return named(c.next(), defaultNamespace());
			case [Token({kind: Delim("|")}), _]:
				return Fail;
			default:
				return None;
		}
	}

	static function isName(v:CssValue):Bool
		return v.match(Token({kind: Ident(_) | Delim("*")}));

	function defaultNamespace():CssNamespace {
		var d = namespaces?.defaultNamespace;
		return d == null ? AnyNamespace : d == "" ? NoNamespace : Uri(d);
	}

	// ([...]'s contents)
	function attribute(c:Cursor):Null<CssSimple> {
		c.whitespace();
		var ns = NoNamespace, name = null;
		switch [c.peek(), c.at(1), c.at(2)] {
			case [Token({kind: Delim("*")}), Token({kind: Delim("|")}), Token({kind: Ident(n)})]:
				ns = AnyNamespace;
				name = n;
				c.skip(3);
			case [Token({kind: Delim("|")}), Token({kind: Ident(n)}), _]:
				name = n;
				c.skip(2);
			case [Token({kind: Ident(p)}), Token({kind: Delim("|")}), Token({kind: Ident(n)})]:
				var uri = namespaces?.prefixes?.get(p);
				if (uri == null) return null;
				ns = uri == "" ? NoNamespace : Uri(uri);
				name = n;
				c.skip(3);
			case [Token({kind: Ident(n)}), _, _]:
				name = n;
				c.skip(1);
			default:
				return null;
		}
		c.whitespace();
		if (c.end()) return Attribute(name, ns, Exists, "", AsDocument);
		var op = switch c.next() {
			case Token({kind: Delim("=")}): Equals;
			case Token({kind: Delim(d)}) if (c.is(Delim("="))):
				c.skip(1);
				switch d {
					case "~": Includes;
					case "|": DashMatch;
					case "^": Prefix;
					case "$": Suffix;
					case "*": Substring;
					default: return null;
				}
			default: return null;
		}
		c.whitespace();
		var value = switch c.next() {
			case Token({kind: Ident(v) | Str(v)}): v;
			default: return null;
		}
		c.whitespace();
		var flag = AsDocument;
		if (!c.end()) {
			flag = switch c.next() {
				case Token({kind: Ident(f)}) if (Css.lower(f) == "i"): Insensitive;
				case Token({kind: Ident(f)}) if (Css.lower(f) == "s"): Sensitive;
				default: return null;
			}
			c.whitespace();
			if (!c.end()) return null;
		}
		return Attribute(name, ns, op, value, flag);
	}

	function pseudoClass(v:Null<CssValue>):Null<CssPseudoClass> {
		switch v {
			case Token({kind: Ident(n)}):
				var name = Css.lower(n);
				var p = PLAIN.get(name);
				if (p != null) return p;
				var bits = STATES.get(name);
				if (bits != null) return State(bits, name);
				if (NEVER.contains(name)) return Never(name);
				return null;
			case Function(n, args, _, _):
				var name = Css.lower(n);
				return switch name {
					case "is": nested(() -> {var l = list(args, false, true); l == null ? null : Is(l);});
					case "where": nested(() -> {var l = list(args, false, true); l == null ? null : Where(l);});
					case "not": nested(() -> {var l = list(args, false, false); l == null ? null : Not(l);});
					case "has":
						if (inHas) return null;
						inHas = true;
						var p = nested(() -> {var l = list(args, true, false); l == null ? null : Has(l);});
						inHas = false;
						p;
					case "nth-child" | "nth-last-child":
						var at = ofAt(args);
						var anb = CssAnB.parse(at < 0 ? args : args.slice(0, at));
						if (anb == null) return null;
						var of = null;
						if (at >= 0) {
							of = nested(() -> list(args.slice(at + 1), false, false));
							if (of == null) return null;
						}
						name == "nth-child" ? NthChild(anb, of) : NthLastChild(anb, of);
					case "nth-of-type" | "nth-last-of-type":
						var anb = CssAnB.parse(args);
						if (anb == null) return null;
						name == "nth-of-type" ? NthOfType(anb) : NthLastOfType(anb);
					case "lang":
						var ranges = [];
						for (part in split(args)) {
							var c = new Cursor(part);
							c.whitespace();
							switch c.next() {
								case Token({kind: Ident(r) | Str(r)}): ranges.push(r);
								default: return null;
							}
							c.whitespace();
							if (!c.end()) return null;
						}
						Lang(ranges);
					case "dir":
						var c = new Cursor(args);
						c.whitespace();
						var d = switch c.next() {
							case Token({kind: Ident(d)}): Css.lower(d);
							default: return null;
						}
						c.whitespace();
						if (!c.end() || (d != "ltr" && d != "rtl")) return null;
						Dir(d == "rtl");
					default: null;
				}
			default:
				return null;
		}
	}

	function nested<T>(f:() -> Null<T>):Null<T> {
		inner++;
		var r = f();
		inner--;
		return r;
	}

	// (:nth-child()'s "of": a top-level ident after whitespace)
	static function ofAt(args:Array<CssValue>):Int {
		for (k in 1...args.length)
			switch args[k] {
				case Token({kind: Ident(n)}) if (Css.lower(n) == "of" && args[k - 1].match(Token({kind: Whitespace}))):
					return k;
				default:
			}
		return -1;
	}

	function pseudoElement(v:Null<CssValue>):Null<CssPseudoElement>
		return switch v {
			case Token({kind: Ident(n)}): ELEMENTS.get(Css.lower(n));
			case Function(n, args, _, _):
				switch Css.lower(n) {
					case "slotted":
						var l = nested(() -> list(args, false, false));
						l == null ? null : Slotted(l);
					case "part":
						var names = [];
						for (a in args)
							switch a {
								case Token({kind: Ident(name)}): names.push(name);
								case Token({kind: Whitespace}):
								default: return null;
							}
						names.length == 0 ? null : Part(names);
					default: null;
				}
			default: null;
		}

	static final PLAIN:Map<String, CssPseudoClass> = [
		"first-child" => FirstChild, "last-child" => LastChild, "only-child" => OnlyChild, "first-of-type" => FirstOfType, "last-of-type" => LastOfType,
		"only-of-type" => OnlyOfType, "root" => Root, "empty" => Empty, "scope" => Scope, "link" => Link, "any-link" => AnyLink, "enabled" => Enabled,
		"disabled" => Disabled, "checked" => Checked, "indeterminate" => Indeterminate, "default" => Default, "required" => Required,
		"optional" => Optional, "read-only" => ReadOnly, "read-write" => ReadWrite, "placeholder-shown" => PlaceholderShown, "defined" => Defined,
		"valid" => Valid, "invalid" => Invalid
	];

	// (the element's state bits; after a pseudo-element, these but :target)
	static final STATES:Map<String, Int> = [
		"hover" => ElementState.HOVER, "active" => ElementState.ACTIVE, "focus" => ElementState.FOCUS, "focus-visible" => ElementState.FOCUS_VISIBLE,
		"focus-within" => ElementState.FOCUS_WITHIN, "target" => ElementState.TARGET
	];

	static final NEVER = [
		"visited", "local-link", "target-within", "current", "past", "future", "playing", "paused", "seeking", "buffering", "stalled", "muted",
		"volume-locked", "autofill", "in-range", "out-of-range", "user-valid", "user-invalid", "blank", "modal", "popover-open", "fullscreen",
		"picture-in-picture", "open", "closed", "host"
	];

	static final LEGACY:Map<String, CssPseudoElement> = ["before" => Before, "after" => After, "first-line" => FirstLine, "first-letter" => FirstLetter];

	static final ELEMENTS:Map<String, CssPseudoElement> = [
		"before" => Before, "after" => After, "marker" => Marker, "first-line" => FirstLine, "first-letter" => FirstLetter,
		"placeholder" => Placeholder, "selection" => Selection, "backdrop" => Backdrop, "file-selector-button" => FileSelectorButton,
		"footnote-call" => FootnoteCall, "footnote-marker" => FootnoteMarker
	];
}

private enum Parsed<T> {
	Fail;
	None;
	Some(v:T);
}

// (a read position in a list of component values)
private class Cursor {
	final values:Array<CssValue>;
	var k = 0;

	public function new(values:Array<CssValue>)
		this.values = values;

	public inline function end():Bool
		return k >= values.length;

	public inline function peek():Null<CssValue>
		return k < values.length ? values[k] : null;

	public inline function at(d:Int):Null<CssValue>
		return k + d < values.length ? values[k + d] : null;

	public inline function next():Null<CssValue>
		return k < values.length ? values[k++] : null;

	public inline function skip(n:Int)
		k += n;

	public function is(kind:CssTokenKind):Bool
		return isAt(0, kind);

	public function isAt(d:Int, kind:CssTokenKind):Bool
		return switch at(d) {
			case Token(t): std.Type.enumEq(t.kind, kind);
			default: false;
		}

	// whether any whitespace was there
	public function whitespace():Bool {
		var from = k;
		while (k < values.length && values[k].match(Token({kind: Whitespace})))
			k++;
		return k > from;
	}

	public function combinator():Null<CssCombinator> {
		var c = switch peek() {
			case Token({kind: Delim(">")}): Child;
			case Token({kind: Delim("+")}): NextSibling;
			case Token({kind: Delim("~")}): SubsequentSibling;
			default: null;
		}
		if (c != null) k++;
		return c;
	}
}
