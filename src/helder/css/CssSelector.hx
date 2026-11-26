package helder.css;

// A complex selector (Selectors 4): compounds left to right, a combinator
// between each two (combinators[k] between compounds[k] and [k + 1]; a
// relative selector's leading one is `relative`), the pseudo-element its
// subject is (null: the element itself), and its specificity.
// hashes: CssHash's of the ids, classes and types of its compounds that
// are ancestors of its subject (those a child or descendant combinator follows),
// at most MAX_HASHES: an element whose ancestors' Bloom filter has not
// each of them cannot match (CssBloom)
class CssSelector {
	public final compounds:Array<CssCompound>;
	public final combinators:Array<CssCombinator>;
	public final relative:Null<CssCombinator>;
	public final pseudo:Null<CssPseudoElement>;
	public final specificity:CssSpecificity;
	public final hashes:Array<Int>;
	// whether its match reads only the element's own tag, id, classes,
	// attributes (without a namespace) and state, and its ancestors': no
	// sibling's or child's (combinators + and ~, :nth-*, :first-child...,
	// :has(), :empty), no place (:root, :scope), no other element's form
	// state (:checked's options, :disabled's fieldset legend). Two such
	// elements with equivalent ancestors match it alike: the style-sharing
	// cache's test
	public final local:Bool;

	// where a CssRuleIndex files it (by its rightmost compound)
	public final bucket:CssBucket;

	public static inline var MAX_HASHES = 4;

	// (what a sheet compiled at build time makes, its parts worked out then: CssTheme)
	function new(compounds:Array<CssCompound>, combinators:Array<CssCombinator>, relative:Null<CssCombinator>, pseudo:Null<CssPseudoElement>,
			specificity:CssSpecificity, hashes:Array<Int>, local:Bool, bucket:CssBucket) {
		this.compounds = compounds;
		this.combinators = combinators;
		this.relative = relative;
		this.pseudo = pseudo;
		this.specificity = specificity;
		this.hashes = hashes;
		this.local = local;
		this.bucket = bucket;
	}

	public static function of(compounds:Array<CssCompound>, combinators:Array<CssCombinator>, relative:Null<CssCombinator>,
			pseudo:Null<CssPseudoElement>):CssSelector {
		var s = CssSpecificity.ZERO;
		for (c in compounds)
			for (p in c)
				s = s.add(CssSpecificity.of(p));
		if (pseudo != null) s = s.add(CssSpecificity.make(0, 0, 1));
		return new CssSelector(compounds, combinators, relative, pseudo, s, ancestorHashes(compounds, combinators), isLocal(compounds, combinators, relative),
			bucketOf(compounds[compounds.length - 1]));
	}

	static function isLocal(compounds:Array<CssCompound>, combinators:Array<CssCombinator>, relative:Null<CssCombinator>):Bool {
		for (c in combinators)
			if (c == NextSibling || c == SubsequentSibling) return false;
		if (relative != null) return false;
		for (c in compounds)
			for (x in c)
				switch x {
					case Attribute(_, ns, _, _, _) if (ns != NoNamespace): return false;
					case Pseudo(Is(l) | Where(l) | Not(l)):
						for (i in l)
							if (!i.local) return false;
					case Pseudo(Has(_) | NthChild(_, _) | NthLastChild(_, _) | NthOfType(_) | NthLastOfType(_) | FirstChild | LastChild | OnlyChild | FirstOfType
						| LastOfType | OnlyOfType | Empty | Root | Scope | Checked | Enabled | Disabled | ReadOnly | ReadWrite | PlaceholderShown | Valid | Invalid):
						return false;
					default:
				}
		return true;
	}

	// (its id, else a class, else its type, else :is()'s types or a link's,
	// else :root, else an attribute's name, else none)
	static function bucketOf(last:CssCompound):CssBucket {
		var id = null, cls = null, tag = null, attr = null, kinds:Null<Array<String>> = null, isRoot = false;
		for (s in last)
			switch s {
				case Id(n) if (id == null): id = n;
				case Class(n) if (cls == null): cls = n;
				case Type(n, _) if (tag == null): tag = n;
				case Attribute(n, NoNamespace, _, _, _) if (attr == null): attr = n;
				case Pseudo(Link | AnyLink) if (kinds == null): kinds = ["a", "area"];
				case Pseudo(Root): isRoot = true;
				case Pseudo(Is(list)) if (kinds == null): kinds = types(list);
				default:
			}
		return if (id != null) ById(Css.lower(id)) else if (cls != null) ByClass(Css.lower(cls)) else if (tag != null) ByTag([Css.lower(tag)]) else
			if (kinds != null) ByTag(kinds) else if (isRoot) ByRoot else if (attr != null) ByAttribute(attr) else Anywhere;
	}

	// (:is()'s arguments' types when each is a type alone, lowercased, each once; else null)
	static function types(list:Array<CssSelector>):Null<Array<String>> {
		var out = [];
		for (x in list)
			switch x.compounds {
				case [[Type(n, _)]] if (x.pseudo == null):
					var k = Css.lower(n);
					if (!out.contains(k)) out.push(k);
				default:
					return null;
			}
		return out.length == 0 ? null : out;
	}

	// (a compound is an ancestor of the subject when the combinator right
	// of it is a child or descendant one: in `div > p + * > li` the div,
	// not the p, a sibling of the li's parent; as WebKit collects them)
	static function ancestorHashes(compounds:Array<CssCompound>, combinators:Array<CssCombinator>):Array<Int> {
		var out = [], k = compounds.length - 2;
		while (k >= 0 && out.length < MAX_HASHES) {
			if (combinators[k] == Child || combinators[k] == Descendant)
				for (s in compounds[k])
					switch s {
						case Id(n) | Class(n) | Type(n, _):
							var h = CssHash.of(n);
							if (out.length < MAX_HASHES && !out.contains(h)) out.push(h);
						default:
					}
			k--;
		}
		return out;
	}

	// a selector list (a rule's prelude), null when any of it is invalid;
	// namespaces: @namespace's prefixes and default
	public static function list(values:Array<CssValue>, ?namespaces:CssNamespaces):Null<Array<CssSelector>>
		return new SelectorParser(namespaces).list(values, false, false);

	public static function parse(text:String, ?namespaces:CssNamespaces):Null<Array<CssSelector>>
		return list(Css.values(text), namespaces);

	// a relative selector list (:has()'s, a scoped query's: "> a, + b")
	public static function relativeList(values:Array<CssValue>, ?namespaces:CssNamespaces):Null<Array<CssSelector>>
		return new SelectorParser(namespaces).list(values, true, false);

	public function toString():String
		return SelectorPrinter.selector(this);
}

// Where CssRuleIndex files a selector, by its rightmost compound: its id's
// bucket, else a class's, else its type's (or the tag buckets of :is()'s
// types, a link's: an element has one tag, so it finds the entry once),
// else :root's, else an attribute's (its name as written; one with a
// namespace goes nowhere else), else the universal one. Keys ASCII lowercase.
enum CssBucket {
	ById(key:String);
	ByClass(key:String);
	ByTag(keys:Array<String>);
	ByRoot;
	ByAttribute(name:String);
	Anywhere;
}

// a compound selector's simple selectors, in order (a type or universal one first if any)
typedef CssCompound = Array<CssSimple>;

enum CssCombinator {
	Descendant;
	Child;
	NextSibling;
	SubsequentSibling;
}

// a selector's namespace: any, none (no namespace), or a URI
enum CssNamespace {
	AnyNamespace;
	NoNamespace;
	Uri(uri:String);
}

enum CssSimple {
	// name as written (an HTML element's matched ASCII case-insensitively)
	Type(name:String, ns:CssNamespace);
	Universal(ns:CssNamespace);
	Id(name:String);
	Class(name:String);
	// ns: an attribute's, NoNamespace without a prefix; value: "" for Exists
	Attribute(name:String, ns:CssNamespace, op:CssAttributeOp, value:String, sensitivity:CssSensitivity);
	Pseudo(p:CssPseudoClass);
}

enum CssAttributeOp {
	Exists;
	Equals;
	// ~=, |=, ^=, $=, *=
	Includes;
	DashMatch;
	Prefix;
	Suffix;
	Substring;
}

// an attribute selector's flag: none (the document language's), i, s
enum CssSensitivity {
	AsDocument;
	Insensitive;
	Sensitive;
}

enum CssPseudoClass {
	// :is() and :where() lists are forgiving: their invalid selectors dropped
	Is(list:Array<CssSelector>);
	Where(list:Array<CssSelector>);
	Not(list:Array<CssSelector>);
	// relative selectors
	Has(list:Array<CssSelector>);
	NthChild(anb:CssAnB, of:Null<Array<CssSelector>>);
	NthLastChild(anb:CssAnB, of:Null<Array<CssSelector>>);
	NthOfType(anb:CssAnB);
	NthLastOfType(anb:CssAnB);
	FirstChild;
	LastChild;
	OnlyChild;
	FirstOfType;
	LastOfType;
	OnlyOfType;
	Root;
	Empty;
	Scope;
	// :link (every link is unvisited) and :any-link
	Link;
	AnyLink;
	// language ranges ("en", "*-CH")
	Lang(ranges:Array<String>);
	Dir(rtl:Bool);
	Enabled;
	Disabled;
	Checked;
	Indeterminate;
	Default;
	Required;
	Optional;
	ReadOnly;
	ReadWrite;
	PlaceholderShown;
	Defined;
	// basic constraint validation: a required control with no value is invalid
	Valid;
	Invalid;
	// the element's dynamic state (helder.dom's ElementState bits: :hover,
	// :active, :focus, :focus-visible, :focus-within, :target), all off on a
	// printed page; name: lowercase
	State(bits:Int, name:String);
	// parsed, never matching: :visited (every link is unvisited), time's
	// (:current, :playing...) and those not evaluated (:in-range, :modal...);
	// name: lowercase
	Never(name:String);
}

enum CssPseudoElement {
	Before;
	After;
	Marker;
	FirstLine;
	FirstLetter;
	Placeholder;
	Selection;
	Backdrop;
	FileSelectorButton;
	// CSS GCPM's
	FootnoteCall;
	FootnoteMarker;
	// shadow trees': parsed, never matching
	Slotted(list:Array<CssSelector>);
	Part(names:Array<String>);
}

// what @namespace declares: prefix to URI, and the default (null: none)
typedef CssNamespaces = {
	?prefixes:Map<String, String>,
	?defaultNamespace:String
}
