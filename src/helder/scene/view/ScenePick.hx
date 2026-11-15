package helder.scene.view;

// <Scene pick>: "bounds" (the default: Pick.ray, the meshes' boxes) or
// "triangles" (Raycaster: the triangles, SceneEvent.normal and uv), told
// when compiling so that a program picking by bounds links no raycaster; or
// a ScenePicker of the program's. (Its macro types nothing of the scene:
// the module holds no other type.)
#if macro
abstract ScenePick(Dynamic) {
#else
abstract ScenePick(ScenePicker) to ScenePicker {
	inline function new(p:ScenePicker)
		this = p;

	@:from static inline function ofPicker(p:ScenePicker):ScenePick
		return new ScenePick(p);
#end

	@:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr {
		return switch e.expr {
			case EConst(CString("triangles", _)): macro @:pos(e.pos) @:privateAccess new helder.scene.view.ScenePick(new helder.scene.view.ScenePicker.TrianglePicker());
			case EConst(CString("bounds", _)): macro @:pos(e.pos) (cast null : helder.scene.view.ScenePick);
			case _: haxe.macro.Context.error('<Scene pick>: "bounds" or "triangles"', e.pos);
		}
	}
}
