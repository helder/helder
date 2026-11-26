package helder.css;

import helder.css.CssCalc;
import helder.css.CssColors;
import helder.css.CssGrammar;

// A matched value's parts, typed by the grammar that matched them, in the
// grammar's order (a `||` or `&&` written in another order comes out in
// the grammar's): what CssValues serializes and computes.
enum CssTerm {
	// a keyword of the grammar, ASCII lowercase
	Keyword(name:String);
	// <custom-ident>, <dashed-ident>, <ident>: as written
	Ident(name:String);
	Number(value:Float, integer:Bool);
	Percentage(value:Float);
	// a length, angle, time, frequency, resolution or flex: its unit ASCII
	// lowercase (a unitless 0 where a length may be: px)
	Dimension(value:Float, unit:String);
	Str(value:String);
	// modifiers: integrity(), referrer-policy() and the rest, as written
	Url(value:String, modifiers:Array<String>);
	Color(color:CssColorValue);
	// a math function, simplified; type: the primitive it stands for
	// (length, integer, ...), range: the grammar's, both for computing
	Calc(calc:CssCalcNode, type:String, range:Null<CssRange>);
	// a function the grammar spells out (rect(), counter(), repeat()), its arguments matched
	Func(name:String, args:Array<CssTerm>);
	// a block the grammar spells out ('[' line names ']'): its open bracket
	Brackets(open:String, args:Array<CssTerm>);
	// `,`, `/` and the other delimiters of the grammar
	Delim(text:String);
	// <declaration-value>, <any-value>, <url-modifier>: the values as they are, serialized
	Raw(text:String);
	// a shorthand's match: what a <'property'> (name: the property) or a
	// named <type> (name: "<type>") of its grammar matched, for its
	// expansion to longhands; written as its terms
	Part(name:String, terms:Array<CssTerm>);
}

// A property's specified value: a CSS-wide keyword, a value with var() or
// env() kept to substitute later (its text), or the grammar's terms.
enum CssSpecified {
	Wide(keyword:String);
	Unresolved(text:String);
	Terms(terms:Array<CssTerm>);
}
