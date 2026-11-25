package helder.scene.render;

// how a see-through material is blended over what is behind (Material.blend)
enum abstract MaterialBlend(String) {
	var None = "none";
	var Alpha = "alpha";
	var Additive = "additive";
	var Premultiplied = "premultiplied";
	var Multiply = "multiply";

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);
}
