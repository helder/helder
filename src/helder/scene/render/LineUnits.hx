package helder.scene.render;

// a line's width: in pixels on the screen, or in the world's units
enum abstract LineUnits(String) {
	var Pixels = "pixels";
	var World = "world";

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);
}
