package helder.css;

// A complex selector (Selectors 4): compounds left to right, a combinator
// between each two (combinators[k] between compounds[k] and [k + 1]; a
// relative selector's leading one is `relative`), the pseudo-element its
// subject is (null: the element itself), and its specificity.
class CssSelector {
	public final compounds:Array<CssCompound>;
	public final combinators:Array<CssCombinator>;
	public final relative:Null<CssCombinator>;
	public final pseudo:Null<CssPseudoElement>;
	public final specificity:CssSpecificity;

	public function new(compounds:Array<CssCompound>, combinators:Array<CssCombinator>, relative:Null<CssCombinator>, pseudo:Null<CssPseudoElement>) {
		this.compounds = compounds;
		this.combinators = combinators;
		this.relative = relative;
		this.pseudo = pseudo;
		var s = CssSpecificity.ZERO;
		for (c in compounds)
			for (p in c)
				s = s.add(CssSpecificity.of(p));
		if (pseudo != null) s = s.add(CssSpecificity.make(0, 0, 1));
		specificity = s;
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
	// parsed, never matching: a state of interaction or time a printed page
	// has not (:hover, :focus, :visited, :target...) or one not evaluated
	// (:valid, :invalid...); name: lowercase
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
