package helder.ui;

// whether the pointer finds a node (CSS's pointer-events): None lets it
// through to what is under it; inherited, so a descendant can be Auto again
enum abstract PointerEvents(String) {
	var Auto = "auto";
	var None = "none";

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);
}
