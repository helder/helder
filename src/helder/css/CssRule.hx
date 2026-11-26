package helder.css;

// A rule as Syntax 3's parser reads it, nesting included: a block's
// contents are rules and runs of declarations, in order
enum CssRule {
	// declarations: the block's first run; rules: what follows, later
	// runs of declarations as Declarations (nested declarations rules)
	Qualified(prelude:Array<CssValue>, declarations:Array<CssDeclaration>, rules:Array<CssRule>);
	// block: null for a statement at-rule (ended by ";"); its items as
	// read, runs of declarations as Declarations: how they apply is the
	// at-rule's to say
	At(name:String, prelude:Array<CssValue>, block:Null<Array<CssRule>>);
	Declarations(declarations:Array<CssDeclaration>);
}
