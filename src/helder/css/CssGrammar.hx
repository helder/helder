package helder.css;

// A value definition (CSS Values 4 §2) as a tree. Brackets only group: a
// bracketed combination keeps its own node, so `a || [ b || c ]` is not
// `a || b || c`. Repeat's max is -1 for no limit; `#` is a comma list.
enum CssGrammar {
	Keyword(name:String);
	Delim(text:String);
	Named(name:String, range:Null<CssRange>);
	Prop(name:String);
	Func(name:String, args:CssGrammar);
	Block(open:String, inner:CssGrammar);
	Sequence(items:Array<CssGrammar>);
	All(items:Array<CssGrammar>);
	Any(items:Array<CssGrammar>);
	One(items:Array<CssGrammar>);
	Repeat(item:CssGrammar, min:Int, max:Int, comma:Bool);
	Required(item:CssGrammar);
}

typedef CssRange = {min:Float, max:Float, unit:String}
