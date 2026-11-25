package helder.scene.render;

// a line's ends
enum abstract LineCap(String) {
	var Butt = "butt";
	var Round = "round";
	var Square = "square";

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);
}
