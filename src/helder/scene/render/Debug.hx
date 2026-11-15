package helder.scene.render;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

// Debug drawing from anywhere, compiled out of release builds (helder
// build's -D helder.release) unless -D helder.debugdraw: each call is
// DebugDraw's of the same name where it is kept, and nothing at all where
// it is not (not even its arguments: a call's work costs nothing in a
// release). Drawn by the DebugDraw feature (renderer.use(new
// DebugDraw(device))), each frame's calls then gone (Bevy's gizmos):
//
//   Debug.line(a, b, 0xFF4040);
//   Debug.ray(origin, dir, 2.0);
//   Debug.aabb(box);  Debug.boxOf(node.worldMatrix(), min, max);
//   Debug.sphere(centre, r);  Debug.circle(centre, normal, r);
//   Debug.axes(node.worldMatrix(), 0.5);  Debug.grid(centre, 10, 10);
//   Debug.frustum(camera, aspect);  Debug.light(lamp);  Debug.skeleton(skin);
//   Debug.path(curve, 64);  Debug.arrow(a, b);  Debug.cross3(p);
//   Debug.onTop(true);  ...  Debug.onTop(false);   // drawn over everything
//
// A colour is 0xRRGGBB, as written. TypeScript, which has no such builds,
// calls DebugDraw's own.
class Debug {
	public static macro function line(a:Expr, b:Expr, rest:Array<Expr>):Expr
		return call("line", [a, b].concat(rest));

	public static macro function ray(origin:Expr, dir:Expr, rest:Array<Expr>):Expr
		return call("ray", [origin, dir].concat(rest));

	public static macro function arrow(a:Expr, b:Expr, rest:Array<Expr>):Expr
		return call("arrow", [a, b].concat(rest));

	public static macro function aabb(box:Expr, rest:Array<Expr>):Expr
		return call("aabb", [box].concat(rest));

	public static macro function boxOf(m:Expr, min:Expr, max:Expr, rest:Array<Expr>):Expr
		return call("boxOf", [m, min, max].concat(rest));

	public static macro function sphere(centre:Expr, radius:Expr, rest:Array<Expr>):Expr
		return call("sphere", [centre, radius].concat(rest));

	public static macro function circle(centre:Expr, normal:Expr, radius:Expr, rest:Array<Expr>):Expr
		return call("circle", [centre, normal, radius].concat(rest));

	public static macro function cross3(p:Expr, rest:Array<Expr>):Expr
		return call("cross3", [p].concat(rest));

	public static macro function axes(m:Expr, rest:Array<Expr>):Expr
		return call("axes", [m].concat(rest));

	public static macro function grid(centre:Expr, rest:Array<Expr>):Expr
		return call("grid", [centre].concat(rest));

	public static macro function frustum(camera:Expr, aspect:Expr, rest:Array<Expr>):Expr
		return call("frustum", [camera, aspect].concat(rest));

	public static macro function light(node:Expr, rest:Array<Expr>):Expr
		return call("light", [node].concat(rest));

	public static macro function skeleton(skin:Expr, rest:Array<Expr>):Expr
		return call("skeleton", [skin].concat(rest));

	public static macro function path(curve:Expr, rest:Array<Expr>):Expr
		return call("path", [curve].concat(rest));

	// the calls from here on drawn over everything (true) or depth tested
	public static macro function onTop(on:Expr):Expr
		return kept() ? macro helder.scene.render.DebugDraw.onTop = $on : macro {};

	#if macro
	// (whether the calls are compiled: not in a release, unless asked)
	static function kept():Bool
		return !Context.defined("helder.release") || Context.defined("helder.debugdraw");

	static function call(name:String, args:Array<Expr>):Expr
		return kept() ? macro @:pos(Context.currentPos()) helder.scene.render.DebugDraw.$name($a{args}) : macro {};
	#end
}
