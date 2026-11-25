package helder.scene.render;

// what a Lightmap holds: the ambient light alone (the lights added), or all of it
enum abstract LightmapMode(String) {
	var Indirect = "indirect";
	var All = "all";

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);
}
