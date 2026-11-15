package helder.scene.view;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

// SceneRenderer's tags' options made from their props (SceneProps).
class SceneOptions {
	// an options structure of type T from an element's props, each field
	// its prop's (null where not set; a Float's from an Int too): written
	// out from T's fields when compiling
	public static macro function of(type:Expr, props:Expr):Expr {
		var t = Context.follow(Context.getType(haxe.macro.ExprTools.toString(type)));
		var fields = switch t {
			case TAnonymous(a): a.get().fields;
			case _: Context.error("SceneOptions.of: a structure", type.pos);
		}
		var obj:Array<ObjectField> = [];
		for (f in fields) {
			var name = f.name;
			var float = switch Context.follow(f.type) {
				case TAbstract(_.get() => {name: "Null"}, [p]): Context.follow(p).match(TAbstract(_.get() => {name: "Float"}, _));
				case TAbstract(_.get() => {name: "Float"}, _): true;
				case _: false;
			}
			var get = float ? macro helder.scene.view.SceneOptions.float($props.get($v{name})) : macro $props.get($v{name});
			obj.push({field: name, expr: get});
		}
		var ct = Context.toComplexType(Context.getType(haxe.macro.ExprTools.toString(type)));
		var made:Expr = {expr: EObjectDecl(obj), pos: Context.currentPos()};
		return macro($made : $ct);
	}

	// a prop's number as a Float (an Int's too), null when not set
	public static function float(v:Dynamic):Null<Float>
		return v == null ? null : Std.isOfType(v, Int) ? (v : Int) * 1.0 : (v : Float);
}
