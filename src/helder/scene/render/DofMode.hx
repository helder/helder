package helder.scene.render;

// how depth of field's circle grows (Dof.focus, Dof.tiltShift)
enum abstract DofMode(String) {
	var Focus = "focus";
	var TiltShift = "tilt-shift";

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);
}
