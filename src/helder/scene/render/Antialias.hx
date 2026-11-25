package helder.scene.render;

// antialiasing in post (PostProcess.antialias), beside a <Scene>'s MSAA:
// None, or Fxaa (in the composite: its read of the scene along the edges);
// SMAA and TAA are effects of their own (post.smaa, post.taa: an enum's
// value set at run time would link every technique's passes)
enum abstract Antialias(String) {
	var None = "none";
	var Fxaa = "fxaa";

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);
}
