package helder.scene.render;

// where a polyline's segments meet
enum abstract LineJoin(String) {
	var Miter = "miter";
	var Round = "round";
	var Bevel = "bevel";

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);
}
