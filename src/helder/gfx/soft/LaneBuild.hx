package helder.gfx.soft;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

// The lane types' members written out, as VecBuild writes the scalar
// ones: Lane2..Lane4's componentwise operators (vector(n)) and Lanes' builtins
// (builtins()), each the scalar formula of VecBuild in the same order of
// operations, so that a shader's lanes compute what its scalar code does
// (exactly, with -D helder.soft.exact: SoftShaderTest)
class LaneBuild {
	static final XYZW = ["x", "y", "z", "w"];

	public static function vector(n:Int):Array<Field> {
		var fields = Context.getBuildFields();
		var self = 'Lane$n', c = XYZW.slice(0, n);
		function each(f:String):String
			return 'new $self(' + [for (k in c) StringTools.replace(f, "$", k)].join(", ") + ")";
		function op(name, op, body)
			fields.push(fn(name, [["a", self], ["b", self]], self, body, [{name: ":op", params: [Context.parse(op, Context.currentPos())], pos: Context.currentPos()}],
				false));
		op("add", "A + B", each("a.$ + b.$"));
		op("sub", "A - B", each("a.$ - b.$"));
		op("mul", "A * B", each("a.$ * b.$"));
		op("div", "A / B", each("a.$ / b.$"));
		fields.push(fn("neg", [["a", self]], self, each("-a.$"), [{name: ":op", params: [macro - A], pos: Context.currentPos()}], false));
		var pub = (f:Field) -> {
			f.access = [APublic, AStatic, AInline];
			fields.push(f);
		}
		pub(fn("fill", [["s", "Lane"]], self, each("s"), null, false));
		pub(fn("splat", [["v", 'helder.gfx.shader.Vec$n']], self, each("Lane.splat(v.$)"), null, false));
		pub(fn("zero", [], self, each("Lane.zero()"), null, false));
		pub(fn("select", [["m", "LaneBool"], ["a", self], ["b", self]], self, each("Lane.select(m, a.$, b.$)"), null, false));
		return fields;
	}

	public static function builtins():Array<Field> {
		var fields = Context.getBuildFields();
		function add(name, args:Array<Array<String>>, ret, body) {
			var f = fn(name, args, ret, body, null, true);
			f.access = [APublic, AStatic, AOverload, AExtern, AInline];
			fields.push(f);
		}
		function each(name:String, args:Array<Array<String>>, n:Int) {
			var self = 'Lane$n', comps = XYZW.slice(0, n);
			var vargs = [for (a in args) [a[0], self]];
			var call = (k:String) -> name + "(" + [for (a in args) a[0] + "." + k].join(", ") + ")";
			add(name, vargs, self, 'new $self(' + [for (k in comps) call(k)].join(", ") + ")");
		}
		function generic(name:String, args:Array<String>, scalar:String) {
			add(name, [for (a in args) [a, "Lane"]], "Lane", scalar);
			for (n in 2...5)
				each(name, [for (a in args) [a, "T"]], n);
		}
		// (lane by lane: no SIMD form of these, the scalar Math's)
		function lanes(f:String, args:Array<String>):String
			return "Lane.make(" + [for (i in 0...4) 'Math.$f(' + [for (a in args) '$a.get($i)'].join(", ") + ")"].join(", ") + ")";
		for (f in [
			["abs", "x.abs()"], ["sign", "Lane.select(x.gt(Lane.zero()), Lane.splat(1), Lane.select(x.lt(Lane.zero()), Lane.splat(-1), Lane.zero()))"],
			["floor", "x.floor()"], ["ceil", "x.ceil()"], ["fract", "x - x.floor()"], ["sqrt", "x.sqrt()"], ["inversesqrt", "Lane.splat(1) / x.sqrt()"]
		])
			generic(f[0], ["x"], f[1]);
		for (f in ["sin", "cos", "exp", "log"])
			generic(f, ["x"], 'x.$f()');
		for (f in ["tan", "asin", "acos", "atan"])
			generic(f, ["x"], lanes(f, ["x"]));
		generic("min", ["x", "y"], "x.min(y)");
		generic("max", ["x", "y"], "x.max(y)");
		generic("pow", ["x", "y"], "x.pow(y)");
		generic("atan2", ["y", "x"], lanes("atan2", ["y", "x"]));
		generic("step", ["edge", "x"], "Lane.select(x.lt(edge), Lane.zero(), Lane.splat(1))");
		generic("mix", ["x", "y", "a"], "x + (y - x) * a");
		generic("clamp", ["x", "lo", "hi"], "x.max(lo).min(hi)");
		generic("smoothstep", ["e0", "e1", "x"],
			"{var t = clamp((x - e0) / (e1 - e0), Lane.zero(), Lane.splat(1)); t * t * (Lane.splat(3) - Lane.splat(2) * t);}");
		for (n in 2...5) {
			var t = 'Lane$n', comps = XYZW.slice(0, n);
			var dot = [for (k in comps) 'a.$k * b.$k'].join(" + ");
			add("dot", [["a", t], ["b", t]], "Lane", dot);
			add("length", [["a", t]], "Lane", '(' + dot.split("b.").join("a.") + ').sqrt()');
			add("distance", [["a", t], ["b", t]], "Lane", "length(a - b)");
			add("normalize", [["a", t]], t, "a / " + t + ".fill(length(a))");
			add("reflect", [["i", t], ["n", t]], t, 'i - n * $t.fill(Lane.splat(2) * dot(n, i))');
		}
		add("cross", [["a", "Lane3"], ["b", "Lane3"]], "Lane3", "new Lane3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)");
		add("mulVec", [["m", "LaneMat"], ["v", "Lane4"]], "Lane4", "m.c0 * Lane4.fill(v.x) + m.c1 * Lane4.fill(v.y) + m.c2 * Lane4.fill(v.z) + m.c3 * Lane4.fill(v.w)");
		add("mulMat", [["a", "LaneMat"], ["b", "LaneMat"]], "LaneMat", "new LaneMat(mulVec(a, b.c0), mulVec(a, b.c1), mulVec(a, b.c2), mulVec(a, b.c3))");
		return fields;
	}

	static function ct(name:String):ComplexType
		return switch name {
			case "Lane" | "LaneBool" | "LaneInt" | "LaneMat" | "Lane2" | "Lane3" | "Lane4": TPath({pack: ["helder", "gfx", "soft"], name: name});
			case _: Context.toComplexType(Context.getType(name));
		}

	static function fn(name:String, args:Array<Array<String>>, ret:String, body:String, meta:Null<Metadata>, isStatic:Bool):Field {
		var pos = Context.currentPos();
		return {
			name: name,
			access: isStatic ? [AStatic, AInline] : [AStatic, AInline],
			meta: meta,
			kind: FFun({args: [for (a in args) {name: a[0], type: ct(a[1])}], ret: ct(ret), expr: macro return ${Context.parse(body, pos)}}),
			pos: pos
		};
	}
}
#end
