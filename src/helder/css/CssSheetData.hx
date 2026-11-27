package helder.css;

import helder.css.CssCalc;
import helder.css.CssColors;
import helder.css.CssGrammar;
import helder.css.CssMedia;
import helder.css.CssSelector;
import helder.css.CssSheet;
import helder.css.CssTerm;
import helder.css.CssToken;
import helder.css.CssValue;

// A compiled sheet as data: what CssTheme writes at build time and the
// cascade reads back when first asked, one decoder for every sheet rather
// than code per rule, no tokenizer or parser. CssPacked's encoding; each
// type written and read in its fields' order, enums by their
// constructor's index. Also CssInitial's table of initial values.
class CssSheetData {
	public static function decode(data:String):CssSheet
		return new Reader(data).sheet();

	// urls: false leaves the sheets' URLs out (CssTheme's: the build machine's paths)
	public static function encode(sheet:CssSheet, urls = true):String {
		var w = new Writer(urls);
		w.sheet(sheet);
		return w.toString();
	}

	// (CssInitial's: each property's initial value as its table says it, and with prose written out)
	public static function encodeInitials(entries:Array<{name:String, specified:Null<CssSpecified>, of:Null<CssSpecified>}>):String {
		var w = new Writer(false);
		w.list(entries, e -> {
			w.str(e.name);
			w.bool(e.specified != null);
			if (e.specified != null) w.spec(e.specified);
			// (0 none, 1 the same as specified, 2 its own)
			w.uint(e.of == null ? 0 : e.specified != null && w.same(e.of, e.specified) ? 1 : 2);
			if (e.of != null && !(e.specified != null && w.same(e.of, e.specified))) w.spec(e.of);
		});
		return w.toString();
	}

	public static function decodeInitials(data:String):Map<String, CssInitial.CssInitialValue> {
		var r = new Reader(data), out = new Map<String, CssInitial.CssInitialValue>();
		for (_ in 0...r.uint()) {
			var name = r.str();
			var specified = r.bool() ? r.spec() : null;
			var of = switch r.uint() {
				case 0: null;
				case 1: specified;
				case _: r.spec();
			}
			out.set(name, {specified: specified, of: of});
		}
		return out;
	}
}

private class Writer extends CssPackedWriter {
	final urls:Bool;

	public function new(urls:Bool) {
		super();
		this.urls = urls;
	}

	// (the same encoding: CssInitial's prose value where it is its table's)
	public function same(a:CssSpecified, b:CssSpecified):Bool {
		var x = new Writer(false), y = new Writer(false);
		x.spec(a);
		y.spec(b);
		return x.toString() == y.toString();
	}

	public function sheet(s:CssSheet) {
		uint(s.origin.getIndex());
		nstr(urls ? s.url : null);
		list(s.rules, rule);
	}

	function rule(r:CssSheetRule) {
		uint(r.getIndex());
		switch r {
			case Style(selectors, declarations):
				list(selectors, selector);
				list(declarations, declared);
			case Media(m, rules):
				media(m);
				list(rules, rule);
			case Layer(name, rules):
				nstr(name);
				nlist(rules, rule);
			case Import(s, m, layer, anonymous):
				sheet(s);
				media(m);
				nstr(layer);
				bool(anonymous);
			case Page(p):
				list(p.selectors, s -> {
					nstr(s.name);
					list(s.pseudos, str);
				});
				list(p.declarations, declared);
				list(p.descriptors, declaration);
				var names = [for (k in p.margins.keys()) k];
				names.sort(Reflect.compare);
				list(names, k -> {
					str(k);
					list(p.margins[k], declared);
				});
				uint(p.origin.getIndex());
				int(p.order);
			case FontFace(f):
				list(f.descriptors, declaration);
				nstr(f.url);
			case CounterStyle(c):
				str(c.name);
				list(c.descriptors, declaration);
			case FontPaletteValues(p):
				str(p.name);
				list(p.descriptors, declaration);
		}
	}

	function declared(d:CssDeclared) {
		str(d.property);
		int(d.id);
		spec(d.value);
		bool(d.important);
		nlist(d.values, value);
		nstr(d.shorthand);
	}

	public function spec(v:CssSpecified)
		switch v {
			case Wide(k):
				uint(0);
				str(k);
			case Unresolved(t):
				uint(1);
				str(t);
			case Terms(ts):
				uint(2);
				list(ts, term);
		}

	function term(t:CssTerm) {
		uint(t.getIndex());
		switch t {
			case Keyword(s) | Ident(s) | Str(s) | Delim(s) | Raw(s):
				str(s);
			case Number(v, integer):
				float(v);
				bool(integer);
			case Percentage(v):
				float(v);
			case Dimension(v, unit):
				float(v);
				str(unit);
			case Url(v, modifiers):
				str(v);
				list(modifiers, str);
			case Color(c):
				color(c);
			case Calc(c, type, range):
				calc(c);
				str(type);
				bool(range != null);
				if (range != null) {
					float(range.min);
					float(range.max);
					str(range.unit);
				}
			case Func(name, args) | Brackets(name, args) | Part(name, args):
				str(name);
				list(args, term);
		}
	}

	function color(c:CssColorValue) {
		str(c.space);
		list(c.c, float);
		float(c.alpha);
		nstr(c.keyword);
		nlist(c.parts, p -> {
			float(p.v);
			int(p.kind);
			bool(p.expr != null);
			if (p.expr != null) calc(p.expr);
		});
	}

	function calc(c:CssCalcNode) {
		uint(c.getIndex());
		switch c {
			case Value(v, unit):
				float(v);
				str(unit);
			case Sum(items) | Product(items):
				list(items, calc);
			case Negate(i) | Invert(i):
				calc(i);
			case Fn(name, args):
				str(name);
				list(args, calc);
			case Word(name):
				str(name);
		}
	}

	function selector(s:CssSelector) {
		list(s.compounds, c -> list(c, simple));
		list(s.combinators, c -> uint(c.getIndex()));
		bool(s.relative != null);
		if (s.relative != null) uint(s.relative.getIndex());
		bool(s.pseudo != null);
		if (s.pseudo != null) pseudoElement(s.pseudo);
		uint(s.specificity.toInt());
		list(s.hashes, int);
		bool(s.local);
		uint(s.bucket.getIndex());
		switch s.bucket {
			case ById(k) | ByClass(k) | ByAttribute(k): str(k);
			case ByTag(keys): list(keys, str);
			case ByRoot | Anywhere:
		}
	}

	function namespace(n:CssNamespace) {
		uint(n.getIndex());
		switch n {
			case Uri(u): str(u);
			case _:
		}
	}

	function simple(s:CssSimple) {
		uint(s.getIndex());
		switch s {
			case Type(name, ns):
				str(name);
				namespace(ns);
			case Universal(ns):
				namespace(ns);
			case Id(name) | Class(name):
				str(name);
			case Attribute(name, ns, op, value, sensitivity):
				str(name);
				namespace(ns);
				uint(op.getIndex());
				str(value);
				uint(sensitivity.getIndex());
			case Pseudo(p):
				pseudoClass(p);
		}
	}

	function pseudoClass(p:CssPseudoClass) {
		uint(p.getIndex());
		switch p {
			case Is(l) | Where(l) | Not(l) | Has(l):
				list(l, selector);
			case NthChild(anb, of) | NthLastChild(anb, of):
				int(anb.a);
				int(anb.b);
				nlist(of, selector);
			case NthOfType(anb) | NthLastOfType(anb):
				int(anb.a);
				int(anb.b);
			case Lang(ranges):
				list(ranges, str);
			case Dir(rtl):
				bool(rtl);
			case State(bits, name):
				int(bits);
				str(name);
			case Never(name):
				str(name);
			case _:
		}
	}

	function pseudoElement(p:CssPseudoElement) {
		uint(p.getIndex());
		switch p {
			case Slotted(l): list(l, selector);
			case Part(names): list(names, str);
			case _:
		}
	}

	function media(m:CssMedia)
		list(@:privateAccess m.queries, query);

	function query(q:CssMediaQuery) {
		uint(q.getIndex());
		switch q {
			case Never:
			case Typed(type, not, c):
				str(type);
				bool(not);
				bool(c != null);
				if (c != null) condition(c);
			case Condition(c):
				condition(c);
		}
	}

	function condition(c:CssMediaCondition) {
		uint(c.getIndex());
		switch c {
			case Feature(name, op, values):
				str(name);
				nstr(op);
				nlist(values, value);
			case Negate(i):
				condition(i);
			case And(items) | Or(items):
				list(items, condition);
			case Unknown:
		}
	}

	function declaration(d:CssDeclaration) {
		str(d.name);
		list(d.value, value);
		bool(d.important);
		nstr(d.text);
		int(d.start);
		int(d.end);
	}

	function value(v:CssValue) {
		uint(v.getIndex());
		switch v {
			case Token(t):
				token(t);
			case Function(name, values, open, close):
				str(name);
				list(values, value);
				token(open);
				bool(close != null);
				if (close != null) token(close);
			case Block(open, values, close):
				token(open);
				list(values, value);
				bool(close != null);
				if (close != null) token(close);
		}
	}

	function token(t:CssToken) {
		var k = t.kind;
		uint(k.getIndex());
		switch k {
			case Ident(s) | Function(s) | AtKeyword(s) | Str(s) | Url(s) | Delim(s):
				str(s);
			case Hash(s, id):
				str(s);
				bool(id);
			case Number(v, integer, text) | Percentage(v, integer, text):
				float(v);
				bool(integer);
				str(text);
			case Dimension(v, integer, text, unit):
				float(v);
				bool(integer);
				str(text);
				str(unit);
			case UnicodeRange(a, b):
				int(a);
				int(b);
			case _:
		}
		int(t.start);
		int(t.end);
	}
}

private class Reader extends CssPacked {
	static final ORIGINS:Array<CssOrigin> = [UserAgent, User, Author];
	static final COMBINATORS:Array<CssCombinator> = [Descendant, Child, NextSibling, SubsequentSibling];
	static final OPS:Array<CssAttributeOp> = [Exists, Equals, Includes, DashMatch, Prefix, Suffix, Substring];
	static final SENSITIVITIES:Array<CssSensitivity> = [AsDocument, Insensitive, Sensitive];

	public function sheet():CssSheet {
		var origin = ORIGINS[uint()];
		var url = nstr();
		return @:privateAccess new CssSheet(origin, url, list(rule));
	}

	function rule():CssSheetRule
		return switch uint() {
			case 0:
				var s = list(selector);
				CssSheetRule.Style(s, list(declared));
			case 1:
				var m = media();
				CssSheetRule.Media(m, list(rule));
			case 2:
				var name = nstr();
				CssSheetRule.Layer(name, nlist(rule));
			case 3:
				var s = sheet(), m = media(), layer = nstr();
				CssSheetRule.Import(s, m, layer, bool());
			case 4:
				var selectors = list(() -> {
					var name = nstr();
					{name: name, pseudos: list(str)};
				});
				var declarations = list(declared), descriptors = list(declaration);
				var margins = new Map<String, Array<CssDeclared>>();
				for (_ in 0...uint()) {
					var k = str();
					margins.set(k, list(declared));
				}
				var origin = ORIGINS[uint()];
				CssSheetRule.Page({selectors: selectors, declarations: declarations, descriptors: descriptors, margins: margins, origin: origin, order: int()});
			case 5:
				var d = list(declaration);
				CssSheetRule.FontFace({descriptors: d, url: nstr()});
			case 6:
				var name = str();
				CssSheetRule.CounterStyle({name: name, descriptors: list(declaration)});
			case _:
				var name = str();
				CssSheetRule.FontPaletteValues({name: name, descriptors: list(declaration)});
		}

	function declared():CssDeclared {
		var property = str(), id = int();
		var specified = spec();
		var important = bool(), values = nlist(value), shorthand = nstr();
		var d:CssDeclared = {property: property, id: id, value: specified, important: important};
		if (values != null) d.values = values;
		if (shorthand != null) d.shorthand = shorthand;
		return d;
	}

	public function spec():CssSpecified
		return switch uint() {
			case 0: Wide(str());
			case 1: Unresolved(str());
			case _: Terms(list(term));
		}

	function term():CssTerm
		return switch uint() {
			case 0: CssTerm.Keyword(str());
			case 1: CssTerm.Ident(str());
			case 2:
				var v = float();
				CssTerm.Number(v, bool());
			case 3: CssTerm.Percentage(float());
			case 4:
				var v = float();
				CssTerm.Dimension(v, str());
			case 5: CssTerm.Str(str());
			case 6:
				var v = str();
				CssTerm.Url(v, list(str));
			case 7: CssTerm.Color(color());
			case 8:
				var c = calc(), type = str();
				var range:Null<CssRange> = null;
				if (bool()) {
					var min = float(), max = float();
					range = {min: min, max: max, unit: str()};
				}
				CssTerm.Calc(c, type, range);
			case 9:
				var name = str();
				CssTerm.Func(name, list(term));
			case 10:
				var open = str();
				CssTerm.Brackets(open, list(term));
			case 11: CssTerm.Delim(str());
			case 12: CssTerm.Raw(str());
			case _:
				var name = str();
				CssTerm.Part(name, list(term));
		}

	function color():CssColorValue {
		var space = str(), c = list(float), alpha = float(), keyword = nstr();
		var parts = nlist(() -> {
			var v = float(), kind = int();
			var p:CssColorPart = {v: v, kind: kind};
			if (bool()) p.expr = calc();
			p;
		});
		var out:CssColorValue = {space: space, c: c, alpha: alpha};
		if (keyword != null) out.keyword = keyword;
		if (parts != null) out.parts = parts;
		return out;
	}

	function calc():CssCalcNode
		return switch uint() {
			case 0:
				var v = float();
				CssCalcNode.Value(v, str());
			case 1: CssCalcNode.Sum(list(calc));
			case 2: CssCalcNode.Product(list(calc));
			case 3: CssCalcNode.Negate(calc());
			case 4: CssCalcNode.Invert(calc());
			case 5:
				var name = str();
				CssCalcNode.Fn(name, list(calc));
			case _: CssCalcNode.Word(str());
		}

	function selector():CssSelector {
		var compounds = list(() -> list(simple));
		var combinators = list(() -> COMBINATORS[uint()]);
		var relative = bool() ? COMBINATORS[uint()] : null;
		var pseudo = bool() ? pseudoElement() : null;
		var specificity:CssSpecificity = cast uint();
		var hashes = list(int), local = bool();
		var bucket:CssBucket = switch uint() {
			case 0: ById(str());
			case 1: ByClass(str());
			case 2: ByTag(list(str));
			case 3: ByRoot;
			case 4: ByAttribute(str());
			case _: Anywhere;
		}
		return @:privateAccess new CssSelector(compounds, combinators, relative, pseudo, specificity, hashes, local, bucket);
	}

	function namespace():CssNamespace
		return switch uint() {
			case 0: CssNamespace.AnyNamespace;
			case 1: CssNamespace.NoNamespace;
			case _: CssNamespace.Uri(str());
		}

	function simple():CssSimple
		return switch uint() {
			case 0:
				var name = str();
				CssSimple.Type(name, namespace());
			case 1: CssSimple.Universal(namespace());
			case 2: CssSimple.Id(str());
			case 3: CssSimple.Class(str());
			case 4:
				var name = str(), ns = namespace(), op = OPS[uint()], value = str();
				CssSimple.Attribute(name, ns, op, value, SENSITIVITIES[uint()]);
			case _: CssSimple.Pseudo(pseudoClass());
		}

	function anb():CssAnB {
		var a = int();
		return new CssAnB(a, int());
	}

	function pseudoClass():CssPseudoClass
		return switch uint() {
			case 0: CssPseudoClass.Is(list(selector));
			case 1: CssPseudoClass.Where(list(selector));
			case 2: CssPseudoClass.Not(list(selector));
			case 3: CssPseudoClass.Has(list(selector));
			case 4:
				var n = anb();
				CssPseudoClass.NthChild(n, nlist(selector));
			case 5:
				var n = anb();
				CssPseudoClass.NthLastChild(n, nlist(selector));
			case 6: CssPseudoClass.NthOfType(anb());
			case 7: CssPseudoClass.NthLastOfType(anb());
			case 8: CssPseudoClass.FirstChild;
			case 9: CssPseudoClass.LastChild;
			case 10: CssPseudoClass.OnlyChild;
			case 11: CssPseudoClass.FirstOfType;
			case 12: CssPseudoClass.LastOfType;
			case 13: CssPseudoClass.OnlyOfType;
			case 14: CssPseudoClass.Root;
			case 15: CssPseudoClass.Empty;
			case 16: CssPseudoClass.Scope;
			case 17: CssPseudoClass.Link;
			case 18: CssPseudoClass.AnyLink;
			case 19: CssPseudoClass.Lang(list(str));
			case 20: CssPseudoClass.Dir(bool());
			case 21: CssPseudoClass.Enabled;
			case 22: CssPseudoClass.Disabled;
			case 23: CssPseudoClass.Checked;
			case 24: CssPseudoClass.Indeterminate;
			case 25: CssPseudoClass.Default;
			case 26: CssPseudoClass.Required;
			case 27: CssPseudoClass.Optional;
			case 28: CssPseudoClass.ReadOnly;
			case 29: CssPseudoClass.ReadWrite;
			case 30: CssPseudoClass.PlaceholderShown;
			case 31: CssPseudoClass.Defined;
			case 32: CssPseudoClass.Valid;
			case 33: CssPseudoClass.Invalid;
			case 34:
				var bits = int();
				CssPseudoClass.State(bits, str());
			case _: CssPseudoClass.Never(str());
		}

	function pseudoElement():CssPseudoElement
		return switch uint() {
			case 0: CssPseudoElement.Before;
			case 1: CssPseudoElement.After;
			case 2: CssPseudoElement.Marker;
			case 3: CssPseudoElement.FirstLine;
			case 4: CssPseudoElement.FirstLetter;
			case 5: CssPseudoElement.Placeholder;
			case 6: CssPseudoElement.Selection;
			case 7: CssPseudoElement.Backdrop;
			case 8: CssPseudoElement.FileSelectorButton;
			case 9: CssPseudoElement.FootnoteCall;
			case 10: CssPseudoElement.FootnoteMarker;
			case 11: CssPseudoElement.Slotted(list(selector));
			case 13: CssPseudoElement.BeforeMarker;
			case 14: CssPseudoElement.AfterMarker;
			case _: CssPseudoElement.Part(list(str));
		}

	function media():CssMedia
		return @:privateAccess new CssMedia(list(query));

	function query():CssMediaQuery
		return switch uint() {
			case 0: CssMediaQuery.Never;
			case 1:
				var type = str(), not = bool();
				CssMediaQuery.Typed(type, not, bool() ? condition() : null);
			case _: CssMediaQuery.Condition(condition());
		}

	function condition():CssMediaCondition
		return switch uint() {
			case 0:
				var name = str(), op = nstr();
				CssMediaCondition.Feature(name, op, nlist(value));
			case 1: CssMediaCondition.Negate(condition());
			case 2: CssMediaCondition.And(list(condition));
			case 3: CssMediaCondition.Or(list(condition));
			case _: CssMediaCondition.Unknown;
		}

	function declaration():CssDeclaration {
		var name = str(), v = list(value), important = bool(), text = nstr(), start = int();
		return new CssDeclaration(name, v, important, text, start, int());
	}

	function value():CssValue
		return switch uint() {
			case 0: CssValue.Token(token());
			case 1:
				var name = str(), values = list(value), open = token();
				CssValue.Function(name, values, open, bool() ? token() : null);
			case _:
				var open = token(), values = list(value);
				CssValue.Block(open, values, bool() ? token() : null);
		}

	function token():CssToken {
		var kind:CssTokenKind = switch uint() {
			case 0: CssTokenKind.Ident(str());
			case 1: CssTokenKind.Function(str());
			case 2: CssTokenKind.AtKeyword(str());
			case 3:
				var s = str();
				CssTokenKind.Hash(s, bool());
			case 4: CssTokenKind.Str(str());
			case 5: CssTokenKind.BadString;
			case 6: CssTokenKind.Url(str());
			case 7: CssTokenKind.BadUrl;
			case 8: CssTokenKind.Delim(str());
			case 9:
				var v = float(), integer = bool();
				CssTokenKind.Number(v, integer, str());
			case 10:
				var v = float(), integer = bool();
				CssTokenKind.Percentage(v, integer, str());
			case 11:
				var v = float(), integer = bool(), text = str();
				CssTokenKind.Dimension(v, integer, text, str());
			case 12:
				var a = int();
				CssTokenKind.UnicodeRange(a, int());
			case 13: CssTokenKind.Whitespace;
			case 14: CssTokenKind.Cdo;
			case 15: CssTokenKind.Cdc;
			case 16: CssTokenKind.Colon;
			case 17: CssTokenKind.Semicolon;
			case 18: CssTokenKind.Comma;
			case 19: CssTokenKind.OpenSquare;
			case 20: CssTokenKind.CloseSquare;
			case 21: CssTokenKind.OpenParen;
			case 22: CssTokenKind.CloseParen;
			case 23: CssTokenKind.OpenCurly;
			case _: CssTokenKind.CloseCurly;
		}
		var start = int();
		return new CssToken(kind, start, int());
	}
}
