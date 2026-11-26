package helder.math;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

// The members of the math types written out by a macro, each a small
// inline function (so that CPU code pays nothing for them):
//
//   vector(n)   Vec<n>'s operators (+ - * / componentwise; with a Float on
//               either side; unary -) and its swizzles of 2 to 4 components
//               (v.yx, v.xyy, v.wzyx), read only
//
// The shader definition's adapter (helder.gfx.shader's Lower) knows them by
// name, so the names here are part of its interface.
class VecBuild {
	static final XYZW = ["x", "y", "z", "w"];

	public static function vector(n:Int):Array<Field> {
		var fields = Context.getBuildFields();
		var self = 'Vec$n', c = XYZW.slice(0, n);
		// componentwise: one expression per component, $ standing for it
		function each(f:String):String
			return 'new $self(' + [for (k in c) StringTools.replace(f, "$", k)].join(", ") + ")";
		function op(name, op, args:Array<Array<String>>, body, commutative = false)
			fields.push(fn(name, args, self, body, [{name: ":op", params: [Context.parse(op, Context.currentPos())], pos: Context.currentPos()}]
				.concat(commutative ? [{name: ":commutative", params: [], pos: Context.currentPos()}] : [])));
		var vv = [["a", self], ["b", self]], vs = [["a", self], ["s", "Float"]], sv = [["s", "Float"], ["a", self]];
		op("add", "A + B", vv, each("a.$ + b.$"));
		op("sub", "A - B", vv, each("a.$ - b.$"));
		op("mul", "A * B", vv, each("a.$ * b.$"));
		op("div", "A / B", vv, each("a.$ / b.$"));
		op("adds", "A + B", vs, each("a.$ + s"), true);
		op("subs", "A - B", vs, each("a.$ - s"));
		op("ssub", "A - B", sv, each("s - a.$"));
		op("scale", "A * B", vs, each("a.$ * s"), true);
		op("divs", "A / B", vs, each("a.$ / s"));
		op("sdiv", "A / B", sv, each("s / a.$"));
		op("neg", "-A", [["a", self]], each("-a.$"));
		// swizzles: every sequence of 2 to 4 of the components
		function swizzles(prefix:String, len:Int) {
			if (prefix.length == len) {
				var t = 'Vec$len';
				fields.push({
					name: prefix,
					access: [APublic],
					kind: FProp("get", "never", ct(t)),
					pos: Context.currentPos()
				});
				var get = fn("get_" + prefix, [], t, 'new $t(' + [for (i in 0...len) "this." + prefix.charAt(i)].join(", ") + ")");
				get.access = [AInline];
				get.meta = [{name: ":noCompletion", pos: get.pos}];
				fields.push(get);
				return;
			}
			for (k in c)
				swizzles(prefix + k, len);
		}
		for (len in 2...5)
			swizzles("", len);
		return fields;
	}

	static function ct(name:String):ComplexType
		return name == "Float" ? macro :Float : TPath({pack: ["helder", "math"], name: name});

	static function fn(name:String, args:Array<Array<String>>, ret:String, body:String, ?meta:Metadata):Field {
		var pos = Context.currentPos();
		return {
			name: name,
			access: [AStatic, AInline],
			meta: meta,
			kind: FFun({args: [for (a in args) {name: a[0], type: ct(a[1])}], ret: ct(ret), expr: macro return ${Context.parse(body, pos)}}),
			pos: pos
		};
	}
}
#end
