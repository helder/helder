package helder.scene.render;

// what kind of light a Light is
enum abstract LightKind(String) {
	var Directional = "directional";
	var Point = "point";
	var Spot = "spot";
	var Hemisphere = "hemisphere";
	var RectArea = "rect-area";
	var DiscArea = "disc-area";

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);
}
