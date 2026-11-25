package helder.scene.render;

// the curve from linear light to the display
enum abstract ToneMap(String) {
	// Sobotka's AgX: hues kept, highlights to white
	var AgX = "agx";
	// ACES filmic, Narkowicz's fit: the 8-bit path's (aces), so a
	// scene tuned there keeps its look
	var Aces = "aces";
	// none: clipped at 1
	var Clamp = "clamp";

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);
}
