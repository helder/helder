package helder.scene.render;

// how sprites face the camera (Sprites.mode)
enum abstract SpriteMode(String) {
	// facing the camera, upright on the screen
	var Spherical = "spherical";
	// turning about Sprites.axis only, upright along it
	var Axis = "axis";
	// facing +z, turned about z by their rotation
	var Fixed = "fixed";

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);
}
