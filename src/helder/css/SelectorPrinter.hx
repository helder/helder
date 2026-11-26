package helder.css;

import helder.css.CssSelector;

// A selector as text (CSSOM's serialize a selector, near enough to read
// back the same): a namespace's URI has no prefix to print, so it is
// written in braces, {uri}|name, which does not parse
class SelectorPrinter {
	public static function list(l:Array<CssSelector>):String
		return [for (s in l) selector(s)].join(", ");

	public static function selector(s:CssSelector):String {
		var b = new StringBuf();
		if (s.relative != null && s.relative != Descendant) b.add(combinator(s.relative) + " ");
		for (k in 0...s.compounds.length) {
			if (k > 0) b.add(s.combinators[k - 1] == Descendant ? " " : " " + combinator(s.combinators[k - 1]) + " ");
			for (p in s.compounds[k])
				simple(b, p);
		}
		if (s.pseudo != null) b.add("::" + element(s.pseudo));
		return b.toString();
	}

	static function combinator(c:CssCombinator):String
		return switch c {
			case Descendant: " ";
			case Child: ">";
			case NextSibling: "+";
			case SubsequentSibling: "~";
		}

	static function ns(b:StringBuf, n:CssNamespace)
		switch n {
			case AnyNamespace:
			case NoNamespace: b.add("|");
			case Uri(u): b.add('{$u}|');
		}

	static function ident(v:String):String {
		var b = new StringBuf();
		Serializer.ident(b, v);
		return b.toString();
	}

	static function simple(b:StringBuf, s:CssSimple)
		switch s {
			case Type(name, n):
				ns(b, n);
				b.add(ident(name));
			case Universal(n):
				ns(b, n);
				b.add("*");
			case Id(name):
				b.add("#" + ident(name));
			case Class(name):
				b.add("." + ident(name));
			case Attribute(name, n, op, value, flag):
				b.add("[");
				if (n == AnyNamespace) b.add("*|") else if (n != NoNamespace) ns(b, n);
				b.add(ident(name));
				if (op != Exists) {
					b.add(switch op {
						case Equals: "=";
						case Includes: "~=";
						case DashMatch: "|=";
						case Prefix: "^=";
						case Suffix: "$=";
						case Substring: "*=";
						case Exists: "";
					});
					Serializer.string(b, value);
					if (flag == Insensitive) b.add(" i") else if (flag == Sensitive) b.add(" s");
				}
				b.add("]");
			case Pseudo(p):
				b.add(":" + pseudo(p));
		}

	static function pseudo(p:CssPseudoClass):String
		return switch p {
			case Is(l): 'is(${list(l)})';
			case Where(l): 'where(${list(l)})';
			case Not(l): 'not(${list(l)})';
			case Has(l): 'has(${list(l)})';
			case NthChild(anb, of): 'nth-child($anb${of == null ? "" : " of " + list(of)})';
			case NthLastChild(anb, of): 'nth-last-child($anb${of == null ? "" : " of " + list(of)})';
			case NthOfType(anb): 'nth-of-type($anb)';
			case NthLastOfType(anb): 'nth-last-of-type($anb)';
			case Lang(ranges): 'lang(${[for (r in ranges) ident(r)].join(", ")})';
			case Dir(rtl): rtl ? "dir(rtl)" : "dir(ltr)";
			case Never(name) | State(_, name): name;
			case Valid: "valid";
			case Invalid: "invalid";
			case FirstChild: "first-child";
			case LastChild: "last-child";
			case OnlyChild: "only-child";
			case FirstOfType: "first-of-type";
			case LastOfType: "last-of-type";
			case OnlyOfType: "only-of-type";
			case Root: "root";
			case Empty: "empty";
			case Scope: "scope";
			case Link: "link";
			case AnyLink: "any-link";
			case Enabled: "enabled";
			case Disabled: "disabled";
			case Checked: "checked";
			case Indeterminate: "indeterminate";
			case Default: "default";
			case Required: "required";
			case Optional: "optional";
			case ReadOnly: "read-only";
			case ReadWrite: "read-write";
			case PlaceholderShown: "placeholder-shown";
			case Defined: "defined";
		}

	static function element(e:CssPseudoElement):String
		return switch e {
			case Before: "before";
			case After: "after";
			case Marker: "marker";
			case FirstLine: "first-line";
			case FirstLetter: "first-letter";
			case Placeholder: "placeholder";
			case Selection: "selection";
			case Backdrop: "backdrop";
			case FileSelectorButton: "file-selector-button";
			case FootnoteCall: "footnote-call";
			case FootnoteMarker: "footnote-marker";
			case Slotted(l): 'slotted(${list(l)})';
			case Part(names): 'part(${names.join(" ")})';
		}
}
