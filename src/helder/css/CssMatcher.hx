package helder.css;

import helder.css.CssSelector;
import helder.dom.Document;
import helder.dom.Element;
import helder.dom.HTMLOptionElement;
import helder.dom.Node;

using StringTools;

// Selectors matched on helder.dom's elements, right to left. In an HTML
// document an HTML element's type selectors and attribute names match
// ASCII case-insensitively, as do the values of HTML's case-insensitive
// attributes (lang, type, dir...: the HTML Standard's list); in quirks
// mode classes and IDs too. A selector's pseudo-element is the caller's
// (the cascade's): matching here is its originating element's.
class CssMatcher {
	static inline var HTML = "http://www.w3.org/1999/xhtml";
	static inline var XML = "http://www.w3.org/XML/1998/namespace";

	// scope: what :scope is (null: the root element)
	public static function matches(s:CssSelector, el:Element, ?scope:Element):Bool
		return complex(s, s.compounds.length - 1, el, null, scope);

	public static function matchesAny(list:Array<CssSelector>, el:Element, ?scope:Element):Bool {
		for (s in list)
			if (matches(s, el, scope)) return true;
		return false;
	}

	// the elements under root (itself not) any of list matches, in document order
	public static function query(list:Array<CssSelector>, root:Node, ?scope:Element):Array<Element> {
		var out = [];
		var n = root.firstChild;
		while (n != null) {
			if (n.nodeType == Node.ELEMENT_NODE && matchesAny(list, cast n, scope)) out.push(cast n);
			n = next(n, root);
		}
		return out;
	}

	// (the node after n in tree order, within root)
	static function next(n:Node, root:Node):Null<Node> {
		if (n.firstChild != null) return n.firstChild;
		while (n != root) {
			if (n.nextSibling != null) return n.nextSibling;
			n = n.parentNode;
			if (n == null) return null;
		}
		return null;
	}

	// (compound k matched on el, then the combinators left of it; anchor:
	// a relative selector's, :has()'s element, which its lead combinator
	// relates the leftmost compound to)
	static function complex(s:CssSelector, k:Int, el:Element, anchor:Null<Element>, scope:Null<Element>):Bool {
		if (!compound(s.compounds[k], el, scope)) return false;
		if (k == 0) return anchor == null || related(s.relative ?? Descendant, anchor, el);
		switch s.combinators[k - 1] {
			case Child:
				var p = el.parentElement;
				return p != null && complex(s, k - 1, p, anchor, scope);
			case Descendant:
				var p = el.parentElement;
				while (p != null) {
					if (complex(s, k - 1, p, anchor, scope)) return true;
					p = p.parentElement;
				}
				return false;
			case NextSibling:
				var p = el.previousElementSibling;
				return p != null && complex(s, k - 1, p, anchor, scope);
			case SubsequentSibling:
				var p = el.previousElementSibling;
				while (p != null) {
					if (complex(s, k - 1, p, anchor, scope)) return true;
					p = p.previousElementSibling;
				}
				return false;
		}
	}

	// (b is to a as the combinator says: a child, descendant, next or later sibling)
	static function related(c:CssCombinator, a:Element, b:Element):Bool
		return switch c {
			case Child: b.parentElement == a;
			case Descendant:
				var p = b.parentElement;
				while (p != null && p != a)
					p = p.parentElement;
				p == a;
			case NextSibling: b.previousElementSibling == a;
			case SubsequentSibling:
				var p = b.previousElementSibling;
				while (p != null && p != a)
					p = p.previousElementSibling;
				p == a;
		}

	static function compound(c:CssCompound, el:Element, scope:Null<Element>):Bool {
		for (s in c)
			if (!simple(s, el, scope)) return false;
		return true;
	}

	static function htmlDocument(el:Element):Bool {
		var d = el.ownerDocument;
		return d != null && d.contentType == "text/html";
	}

	// (an HTML element in an HTML document: names ASCII case-insensitive)
	static inline function htmlNames(el:Element):Bool
		return el.namespaceURI == HTML && htmlDocument(el);

	static function quirks(el:Element):Bool {
		var d = el.ownerDocument;
		return d != null && d.mode == Quirks;
	}

	static function namespaced(ns:CssNamespace, uri:Null<String>):Bool
		return switch ns {
			case AnyNamespace: true;
			case NoNamespace: uri == null;
			case Uri(u): uri == u;
		}

	static function simple(s:CssSimple, el:Element, scope:Null<Element>):Bool
		return switch s {
			case Type(name, ns):
				namespaced(ns, el.namespaceURI) && (htmlNames(el) ? Css.lower(name) == el.localName : name == el.localName);
			case Universal(ns):
				namespaced(ns, el.namespaceURI);
			case Id(name):
				var id = el.getAttributeNS(null, "id");
				id != null && (quirks(el) ? Css.lower(id) == Css.lower(name) : id == name);
			case Class(name):
				var cls = el.getAttributeNS(null, "class");
				cls != null && includes(cls, name, quirks(el));
			case Attribute(name, ns, op, value, sensitivity):
				attribute(el, name, ns, op, value, sensitivity);
			case Pseudo(p):
				pseudo(p, el, scope);
		}

	static function attribute(el:Element, name:String, ns:CssNamespace, op:CssAttributeOp, value:String, sensitivity:CssSensitivity):Bool {
		var lower = htmlNames(el);
		var local = lower ? Css.lower(name) : name;
		var insensitive = switch sensitivity {
			case Insensitive: true;
			case Sensitive: false;
			case AsDocument: lower && INSENSITIVE.exists(local);
		}
		for (a in el.attributes) {
			if (a.localName != local || !namespaced(ns, a.namespaceURI)) continue;
			if (op == Exists || compare(op, a.value, value, insensitive)) return true;
		}
		return false;
	}

	static function compare(op:CssAttributeOp, actual:String, value:String, insensitive:Bool):Bool {
		if (insensitive) {
			actual = Css.lower(actual);
			value = Css.lower(value);
		}
		return switch op {
			case Exists: true;
			case Equals: actual == value;
			case Includes: value != "" && !hasSpace(value) && includes(actual, value, false);
			case DashMatch: actual == value || actual.startsWith(value + "-");
			case Prefix: value != "" && actual.startsWith(value);
			case Suffix: value != "" && actual.endsWith(value);
			case Substring: value != "" && actual.indexOf(value) >= 0;
		}
	}

	static inline function space(c:Int):Bool
		return c == 32 || c == 9 || c == 10 || c == 12 || c == 13;

	static function hasSpace(s:String):Bool {
		for (k in 0...s.length)
			if (space(s.fastCodeAt(k))) return true;
		return false;
	}

	// (whether a whitespace-separated list holds the token; insensitive: ASCII case-insensitively)
	static function includes(list:String, token:String, insensitive:Bool):Bool {
		if (insensitive) {
			list = Css.lower(list);
			token = Css.lower(token);
		}
		var n = list.length, m = token.length, k = 0;
		if (m == 0) return false;
		while (k < n) {
			while (k < n && space(list.fastCodeAt(k)))
				k++;
			var from = k;
			while (k < n && !space(list.fastCodeAt(k)))
				k++;
			if (k - from == m && list.substr(from, m) == token) return true;
		}
		return false;
	}

	static function pseudo(p:CssPseudoClass, el:Element, scope:Null<Element>):Bool
		return switch p {
			case Is(l) | Where(l): matchesAny(l, el, scope);
			case Not(l): !matchesAny(l, el, scope);
			case Has(l): has(l, el, scope);
			case NthChild(anb, of): (of == null || matchesAny(of, el, scope)) && anb.matches(position(el, false, e -> of == null || matchesAny(of, e, scope)));
			case NthLastChild(anb, of): (of == null || matchesAny(of, el, scope)) && anb.matches(position(el, true, e -> of == null || matchesAny(of, e, scope)));
			case NthOfType(anb): anb.matches(position(el, false, e -> sameType(e, el)));
			case NthLastOfType(anb): anb.matches(position(el, true, e -> sameType(e, el)));
			case FirstChild: el.previousElementSibling == null;
			case LastChild: el.nextElementSibling == null;
			case OnlyChild: el.previousElementSibling == null && el.nextElementSibling == null;
			case FirstOfType: position(el, false, e -> sameType(e, el)) == 1;
			case LastOfType: position(el, true, e -> sameType(e, el)) == 1;
			case OnlyOfType: position(el, false, e -> sameType(e, el)) == 1 && position(el, true, e -> sameType(e, el)) == 1;
			case Root: el.parentNode != null && el.parentNode.nodeType == Node.DOCUMENT_NODE;
			case Empty: empty(el);
			case Scope: scope != null ? el == scope : el.parentNode != null && el.parentNode.nodeType == Node.DOCUMENT_NODE;
			case Link | AnyLink: link(el);
			case Lang(ranges): lang(el, ranges);
			case Dir(rtl): direction(el) == rtl;
			case Enabled: formControl(el) && !disabled(el);
			case Disabled: formControl(el) && disabled(el);
			case Checked: checked(el);
			case Indeterminate: html(el, "progress") && el.getAttributeNS(null, "value") == null;
			case Default: html(el, "option") ? el.getAttributeNS(null, "selected") != null : checkable(el) && el.getAttributeNS(null, "checked") != null;
			case Required: requirable(el) && el.getAttributeNS(null, "required") != null;
			case Optional: requirable(el) && el.getAttributeNS(null, "required") == null;
			case ReadWrite: readWrite(el);
			case ReadOnly: !readWrite(el);
			case PlaceholderShown: placeholderShown(el);
			case Defined: el.namespaceURI != HTML || el.localName.indexOf("-") < 0;
			case Never(_): false;
		}

	// (:has(): an element its relative selectors reach from el matches)
	static function has(list:Array<CssSelector>, el:Element, scope:Null<Element>):Bool {
		for (s in list) {
			var last = s.compounds.length - 1;
			// (descendants for > and space, later siblings and theirs for + and ~)
			var sibling = s.relative == NextSibling || s.relative == SubsequentSibling;
			var root:Node = sibling ? el.parentNode : el;
			if (root == null) continue;
			var n = sibling ? el.nextSibling : el.firstChild;
			while (n != null) {
				if (n.nodeType == Node.ELEMENT_NODE && complex(s, last, cast n, el, scope)) return true;
				n = next(n, root);
			}
		}
		return false;
	}

	// (el's index from 1 among its element siblings counted, from the end if last)
	static function position(el:Element, last:Bool, counted:Element->Bool):Int {
		var k = 1, e = last ? el.nextElementSibling : el.previousElementSibling;
		while (e != null) {
			if (counted(e)) k++;
			e = last ? e.nextElementSibling : e.previousElementSibling;
		}
		return k;
	}

	static function sameType(a:Element, b:Element):Bool
		return a.localName == b.localName && a.namespaceURI == b.namespaceURI;

	// (no element children and no text: comments and processing instructions do not count)
	static function empty(el:Element):Bool {
		var n = el.firstChild;
		while (n != null) {
			if (n.nodeType == Node.ELEMENT_NODE) return false;
			if ((n.nodeType == Node.TEXT_NODE || n.nodeType == Node.CDATA_SECTION_NODE) && n.nodeValue != "") return false;
			n = n.nextSibling;
		}
		return true;
	}

	static inline function html(el:Element, name:String):Bool
		return el.namespaceURI == HTML && el.localName == name;

	static function link(el:Element):Bool
		return (html(el, "a") || html(el, "area")) && el.getAttributeNS(null, "href") != null;

	// (the element's language: the nearest xml:lang, or an HTML element's lang)
	static function lang(el:Element, ranges:Array<String>):Bool {
		var e = el, value:Null<String> = null;
		while (e != null && value == null) {
			value = e.getAttributeNS(XML, "lang");
			if (value == null && e.namespaceURI == HTML) value = e.getAttributeNS(null, "lang");
			e = e.parentElement;
		}
		if (value == null) return false;
		var tag = Css.lower(value).split("-");
		for (r in ranges)
			if (filter(Css.lower(r).split("-"), tag)) return true;
		return false;
	}

	// (RFC 4647's extended filtering, as Selectors 4's :lang() does)
	static function filter(range:Array<String>, tag:Array<String>):Bool {
		if (range[0] == "") return tag.length == 1 && tag[0] == "";
		if (range[0] != "*" && range[0] != tag[0]) return false;
		if (range[0] == "*" && tag[0] == "") return false;
		var i = 1, j = 1;
		while (i < range.length) {
			if (range[i] == "*") {
				i++;
				continue;
			}
			if (j >= tag.length) return false;
			if (range[i] == tag[j]) {
				i++;
				j++;
				continue;
			}
			if (tag[j].length == 1) return false;
			j++;
		}
		return true;
	}

	// (true: right to left, by the nearest dir attribute of ltr or rtl; auto and none: left to right)
	static function direction(el:Element):Bool {
		var e = el;
		while (e != null) {
			var d = e.namespaceURI == HTML ? e.getAttributeNS(null, "dir") : null;
			if (d != null) {
				var v = Css.lower(d);
				if (v == "rtl") return true;
				if (v == "ltr") return false;
			}
			e = e.parentElement;
		}
		return false;
	}

	static function formControl(el:Element):Bool
		return el.namespaceURI == HTML && FORM.contains(el.localName);

	// (HTML's actually disabled: its disabled attribute, an option's
	// optgroup's, a disabled fieldset's descendants but its first legend's)
	static function disabled(el:Element):Bool {
		if (el.getAttributeNS(null, "disabled") != null) return true;
		if (html(el, "option")) {
			var g = el.parentElement;
			return g != null && html(g, "optgroup") && g.getAttributeNS(null, "disabled") != null;
		}
		if (html(el, "optgroup")) return false;
		var child = el, p = el.parentElement;
		while (p != null) {
			if (html(p, "fieldset") && p.getAttributeNS(null, "disabled") != null) {
				var legend = p.firstElementChild;
				while (legend != null && !html(legend, "legend"))
					legend = legend.nextElementSibling;
				if (legend != child) return true;
			}
			child = p;
			p = p.parentElement;
		}
		return false;
	}

	static function checkable(el:Element):Bool {
		if (!html(el, "input")) return false;
		var t = el.getAttributeNS(null, "type");
		return t != null && (Css.lower(t) == "checkbox" || Css.lower(t) == "radio");
	}

	// (an option's: its selectedness, as its select's algorithm keeps it)
	static function checked(el:Element):Bool {
		if (checkable(el)) return el.getAttributeNS(null, "checked") != null;
		if (Std.isOfType(el, HTMLOptionElement)) return (cast el : HTMLOptionElement).selected;
		return false;
	}

	static function requirable(el:Element):Bool
		return html(el, "input") || html(el, "select") || html(el, "textarea");

	static function textInput(el:Element):Bool {
		if (!html(el, "input")) return false;
		var t = el.getAttributeNS(null, "type");
		return t == null || TEXT_TYPES.contains(Css.lower(t));
	}

	static function readWrite(el:Element):Bool {
		if (textInput(el) || html(el, "textarea")) return el.getAttributeNS(null, "readonly") == null && !disabled(el);
		var e = el;
		while (e != null) {
			var c = e.namespaceURI == HTML ? e.getAttributeNS(null, "contenteditable") : null;
			if (c != null) {
				var v = Css.lower(c);
				return v == "" || v == "true" || v == "plaintext-only";
			}
			e = e.parentElement;
		}
		return false;
	}

	static function placeholderShown(el:Element):Bool {
		if (el.getAttributeNS(null, "placeholder") == null) return false;
		if (textInput(el)) return (el.getAttributeNS(null, "value") ?? "") == "";
		if (html(el, "textarea")) return (el.textContent ?? "") == "";
		return false;
	}

	static final FORM = ["button", "input", "select", "textarea", "optgroup", "option", "fieldset"];

	static final TEXT_TYPES = ["text", "search", "url", "tel", "email", "password", "date", "month", "week", "time", "datetime-local", "number", ""];

	// (HTML's attributes whose values selectors match ASCII case-insensitively, §4.16.2)
	static final INSENSITIVE:Map<String, Bool> = [
		for (n in [
			"accept", "accept-charset", "align", "alink", "axis", "bgcolor", "charset", "checked", "clear", "codetype", "color", "compact", "declare",
			"defer", "dir", "direction", "disabled", "enctype", "face", "frame", "hreflang", "http-equiv", "lang", "language", "link", "media", "method",
			"multiple", "nohref", "noresize", "noshade", "nowrap", "readonly", "rel", "rev", "rules", "scope", "scrolling", "selected", "shape", "target",
			"text", "type", "valign", "valuetype", "vlink"
		]) n => true
	];
}
