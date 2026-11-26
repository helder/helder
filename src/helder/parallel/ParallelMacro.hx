package helder.parallel;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import helder.compiler.Kernel;
import helder.gfx.shader.Ir;
import helder.gfx.shader.ShaderDefinition;
import helder.gfx.shader.Soft;
import helder.parallel.ParallelScan;

using haxe.macro.Tools;

// each, map, the reductions and kernel in Haxe (Parallel.hx's macros): the
// body typed in the caller's scope and scanned (ParallelScan: its captures,
// its rules), lowered to the shader IR (ParallelLower), and its CPU forms
// printed from it by the CPU back end's emitter (helder.gfx.shader.Soft):
// the lanes form run over a range, 4 items a call (its reads and writes at
// the item's own index as rows: Soft.rowsRead), the scalar form one item a
// call. Each call site is a class of its own beside the caller
// (<Module>_<method>_<what>_<hash>): those forms, the jobs form's callback
// (chunks of the range on helder.jobs.Spread's threads), its Site (the
// timings Auto picks by), and dispatch(n, on, args...), what the call
// becomes. A reduction cuts the items into chunks of CHUNK, each reduced
// in its lanes then the lanes in pairs, the chunks' results combined in
// order: the same bits on one thread or many.
@:access(helder.gfx.shader.Soft)
@:access(helder.parallel.ParallelLower)
@:access(helder.gfx.shader.Lower)
class ParallelMacro {
	public static inline var CHUNK = 1024;

	// (the context's layout: count, chunk, partials, the reduction's identity, then the arguments)
	public static inline var C_COUNT = 0;
	public static inline var C_CHUNK = 4;
	public static inline var C_PARTIALS = 8;
	public static inline var C_EMPTY = 16;
	public static inline var C_ARGS = 48;


	public static function each(n:Expr, body:Expr, on:Null<Expr>):Expr
		return site("each", Each, n, body, on, null, null);

	// map(out, i -> v): each(out.length, i -> out[i] = v), each return of the body a store
	public static function map(out:Expr, body:Expr, on:Null<Expr>):Expr {
		switch out.expr {
			case EConst(CIdent(_)) | haxe.macro.Expr.ExprDef.EField(_, _):
			case _: Context.error("map: out is an Items named (a local or a field)", out.pos);
		}
		var f = lambda(body, "map", 1);
		var i = f.args[0].name;
		function rewrite(e:Expr):Expr
			return switch e.expr {
				case EMeta({name: ":implicitReturn"}, {expr: EReturn(x = {expr: EBlock(_)})}): rewrite(x);
				case EMeta({name: ":implicitReturn"}, x): rewrite(x);
				case EReturn(x) if (x != null): macro @:pos(e.pos) {
						$out[$i{i}] = $x;
						return;
					};
				case EFunction(_, _): e;
				case _: e.map(rewrite);
			}
		var g = {expr: EFunction(FAnonymous, {args: f.args, ret: null, expr: rewrite(f.expr)}), pos: body.pos};
		return site("map", Each, macro @:pos(out.pos) $out.length, g, on, null, null);
	}

	public static function reduction(what:String, n:Expr, body:Expr, on:Null<Expr>, ?empty:Expr, ?combine:Expr):Expr
		return site(what, switch what {
			case "sum": Sum;
			case "min": Min;
			case "max": Max;
			case _: Reduce;
		}, n, body, on, empty, combine);

	// min(a, b) and max(a, b) where a reduction's name is ShaderMath's (its second argument no function)
	public static function minMax(what:String, n:Expr, body:Expr, on:Null<Expr>):Expr
		return switch body.expr {
			case EFunction(_, _): reduction(what, n, body, on);
			case _ if (on == null || isNull(on)): macro @:pos(Context.currentPos()) helder.gfx.shader.ShaderMath.$what($n, $body);
			case _: Context.error('$what: $what(n, i -> v) or $what(a, b)', Context.currentPos());
		}

	static function lambda(body:Expr, what:String, args:Int):Function {
		var f = switch body.expr {
			case EFunction(_, f): f;
			case EParenthesis(x) | EMeta(_, x): return lambda(x, what, args);
			case _: Context.error('$what: the body is a function literal (i -> ...), not ${body.expr.getName()}', body.pos);
		}
		if (f.args.length != args)
			Context.error(args == 1 ? '$what: the body takes the item\'s index (i -> ...)' : '$what: a kernel takes the item\'s index and its parameters: function(i:Int, p:{...})', body.pos);
		switch f.args[0].type {
			case null | TPath({name: "Int", pack: []}):
			case t: Context.error('$what: the item\'s index is an Int, not ${t.toString()}', body.pos);
		}
		return f;
	}

	static function hxmcOnly(what:String) {
		if (Context.definedValue("target.name") != "hxmc") Context.error('$what: helder.parallel runs on hxmc\'s targets', Context.currentPos());
	}

	// the On of the call: Auto when none, a name of one, else the expression
	static function onOf(on:Null<Expr>):Expr
		return on == null || isNull(on) ? macro helder.parallel.On.Auto : switch on.expr {
			case EConst(CIdent(n = "Auto" | "Scalar" | "Simd" | "Jobs" | "Gpu")): macro @:pos(on.pos) helder.parallel.On.$n;
			case _: macro @:pos(on.pos) ($on : helder.parallel.On);
		}

	// (an optional argument left out: the macro's null)
	static function isNull(e:Expr):Bool
		return e.expr.match(EConst(CIdent("null")));

	// ---- each, map and the reductions at a call

	static function site(what:String, kind:Kind, n:Expr, body:Expr, on:Null<Expr>, empty:Null<Expr>, combine:Null<Expr>):Expr {
		hxmcOnly(what);
		var pos = Context.currentPos();
		var f = lambda(body, what, 1);
		var iname = f.args[0].name;
		// (each's value none: an arrow's last value dropped; a reduction's block of returns its own)
		var fx = switch f.expr.expr {
			case EMeta({name: ":implicitReturn"}, {expr: EReturn(x = {expr: EBlock(_)})}) if (kind != Each): x;
			case _: f.expr;
		}
		var fe:Expr = {expr: EFunction(FAnonymous, {args: [{name: iname, type: macro :Int}], ret: kind == Each ? macro :Void : null, expr: fx}), pos: body.pos};
		var te = Context.withOptions({allowInlining: false}, () -> Context.typeExpr(fe));
		var tf = switch te.expr {
			case TFunction(tf): tf;
			case _: throw "parallel";
		}
		var scan = new ParallelScan(what, tf, null);
		var lower = new ParallelLower(what);
		var args = [for (c in scan.captures) arg(c, what, lower)];
		var reduced:Null<Type> = null;
		if (kind != Each) {
			reduced = Context.follow(tf.t);
			var ok = switch [kind, lower.typeOf(reduced, body.pos)] {
				case [Min | Max, TFloat | TInt]: true;
				case [Sum | Reduce, TFloat | TInt | TVec(_)]: true;
				case _: false;
			}
			if (!ok) Context.error('$what: a body\'s value is ' + (kind == Min || kind == Max ? "an Int or a Float" : "an Int, a Float or a vector") + ', not ${reduced.toString()}', body.pos);
		}
		var sf = lower.lowerStage(new KFunction(null, [iname], body.pos, fe), what);
		var cf:Null<SFunction> = null;
		if (combine != null) {
			var g = lambda(combine, what, 2);
			var ct = reduced.toComplexType();
			var ge:Expr = {expr: EFunction(FAnonymous, {args: [for (a in g.args) {name: a.name, type: a.type ?? ct}], ret: ct, expr: g.expr}), pos: combine.pos};
			cf = lower.lowerPlain(ge, "combine");
		}
		lower.finish();
		var label = location(pos) + " " + what;
		var name = className(what, label + new haxe.macro.Printer().printExpr(body) + (combine == null ? "" : new haxe.macro.Printer().printExpr(combine)));
		var forms = new Forms(what, name, label, sf, cf, kind, reduced, args, lower, empty != null);
		forms.define([]);
		var call = [n, onOf(on)].concat([for (a in args) a.call]);
		if (empty != null) {
			var ct = reduced.toComplexType();
			call.push(macro @:pos(empty.pos) ($empty : $ct));
		}
		var path = forms.pack.concat([name, "dispatch"]);
		return macro @:pos(pos) $p{path}($a{call});
	}

	// a capture as an argument of dispatch: its value at the call
	static function arg(c:Capture, what:String, lower:ParallelLower):Arg {
		if (c.element == null && !capturable(c.type))
			Context.error('$what: ${c.display}\'s type is ${c.type.toString()}: a body captures Int, Float, Bool, vectors, Mat4 and Items', c.pos);
		var t:SType = c.element != null ? TStorage(lower.typeOf(c.element, c.pos), true) : lower.typeOf(c.type, c.pos);
		switch t {
			case TStorage(_, _) | TInt | TFloat | TBool | TVec(_) | TMat4:
			case t: Context.error('$what: ${c.display} is a ${helder.gfx.shader.Names.typeName(t)}: a body captures Int, Float, Bool, vectors, Mat4 and Items', c.pos);
		}
		lower.captures.set(c.key, {name: c.name, type: t});
		if (c.element != null) lower.captures.set("length:" + c.key, {name: c.name + "_length", type: TInt});
		return {
			name: c.name,
			display: c.display,
			call: c.kernel ? null : Context.storeTypedExpr(c.expr),
			type: c.type.toComplexType(),
			stype: t,
			own: c.own,
			written: c.written
		};
	}

	// (Int, Float, Bool, the vectors and Mat4: what a body's lanes hold)
	static function capturable(t:Type):Bool
		return switch Context.follow(t) {
			case TAbstract(_.get() => {pack: [], name: "Int" | "Float" | "Bool"}, _): true;
			case TAbstract(_.get() => {name: "Vec2" | "Vec3" | "Vec4" | "Mat4"}, _): true;
			case _: false;
		}

	// ---- kernel(function(i:Int, p:{...}) ...)

	public static function kernel(def:Expr):Expr {
		hxmcOnly("kernel");
		var pos = Context.currentPos();
		var f = lambda(def, "kernel", 2);
		if (f.args[1].type == null) Context.error('kernel: its parameters are typed: function(${f.args[0].name}:Int, ${f.args[1].name}:{...})', def.pos);
		var fe:Expr = {
			expr: EFunction(FAnonymous, {args: [{name: f.args[0].name, type: macro :Int}, f.args[1]], ret: null, expr: f.expr}),
			pos: def.pos
		};
		var te = Context.withOptions({allowInlining: false}, () -> Context.typeExpr(fe));
		var tf = switch te.expr {
			case TFunction(tf): tf;
			case _: throw "parallel";
		}
		var pv = tf.args[1].v;
		var fields = switch Context.follow(pv.t) {
			case TAnonymous(a): a.get().fields;
			case t: Context.error('kernel: its parameters are an object type ({from:Items<Vec4>, omega:Float}), not ${t.toString()}', def.pos);
		}
		var scan = new ParallelScan("kernel", tf, pv);
		var lower = new ParallelLower("kernel");
		// (its parameters' fields, as the stage flattens them: by position; then the statics it reads)
		var byName = new Map<String, Capture>();
		for (c in scan.captures)
			if (c.kernel) byName.set(c.display, c);
		var sorted = fields.copy();
		sorted.sort((x, y) -> Context.getPosInfos(x.pos).min - Context.getPosInfos(y.pos).min);
		var args:Array<Arg> = [];
		var pt = pv.t.toComplexType();
		for (fd in sorted) {
			var c = byName.get(fd.name);
			var key = "param:" + fd.name;
			if (c == null) c = {
				key: key,
				name: fd.name,
				display: fd.name,
				expr: null,
				type: fd.type,
				pos: fd.pos,
				element: ParallelLower.itemsElement(fd.type),
				written: false,
				own: false,
				length: false,
				kernel: true
			};
			var a = arg(c, "kernel", lower);
			// (a parameter of the stage already: no capture of it)
			lower.captures.remove(c.key);
			var n = fd.name;
			a.call = macro p.$n;
			args.push(a);
		}
		for (c in scan.captures)
			if (!c.kernel) args.push(arg(c, "kernel", lower));
		var sf = lower.lowerStage(new KFunction(null, [f.args[0].name, f.args[1].name], def.pos, fe), "kernel");
		lower.finish();
		var label = location(pos) + " kernel";
		var name = className("kernel", label + new haxe.macro.Printer().printExpr(def));
		var forms = new Forms("kernel", name, label, sf, null, Each, null, args, lower, false);
		var self:TypePath = {pack: forms.pack, name: name};
		var call = [macro n, macro on].concat([for (a in args) a.call]);
		var run = (macro class {
			public static final instance = new $self();

			function new() {}

			// the body for each i of 0...n, with p's Items and values (On: where)
			public function run(n:Int, p:$pt, on:helder.parallel.On = helder.parallel.On.Auto):Void
				dispatch($a{call});
		}).fields;
		// (on: optional, Auto)
		for (f in run)
			switch f.kind {
				case FFun(fn) if (f.name == "run"):
					fn.args[2].opt = true;
					fn.args[2].value = macro helder.parallel.On.Auto;
				case _:
			}
		forms.define(run);
		return macro @:pos(pos) $p{forms.pack.concat([name, "instance"])};
	}

	// ---- names

	static function location(pos:Position):String {
		var l = haxe.macro.PositionTools.toLocation(pos);
		var file = haxe.io.Path.withoutDirectory(l.file.toString());
		return '$file:${l.range.start.line}';
	}

	static function className(what:String, text:String):String {
		var module = Context.getLocalModule().split(".").pop();
		var method = Context.getLocalMethod() ?? "module";
		return module + "_" + helder.gfx.shader.Names.sanitize(method) + "_" + what + "_" + haxe.crypto.Md5.encode(text).substr(0, 8);
	}
}

// (GpuForm's kinds of a captured value)
class GpuKind {
	public static inline var KINT = 0;
	public static inline var KBOOL = 1;
	public static inline var KFLOAT = 2;
	public static inline var KMAT = 3;
	public static inline var KVEC = 10;
}

enum Kind {
	Each;
	Sum;
	Min;
	Max;
	Reduce;
}

typedef Arg = {
	name:String,
	display:String,
	// its value at the call (a kernel's: p.<name>)
	call:Expr,
	type:ComplexType,
	stype:SType,
	own:Bool,
	written:Bool
}

// A site's class: its CPU forms and dispatch
@:access(helder.gfx.shader.Soft)
@:access(helder.gfx.shader.Lower)
private class Forms {
	public final pack:Array<String>;

	final what:String;
	final name:String;
	final label:String;
	final sf:SFunction;
	final cf:Null<SFunction>;
	final kind:Kind;
	final reduced:Null<Type>;
	final args:Array<Arg>;
	final hasEmpty:Bool;
	final soft:Soft;
	final lower:ParallelLower;
	final pos:Position;
	final module:String;
	// the stage's parameters after the index: their argument (and whether its length), their offset in the context
	final params:Array<{arg:Int, length:Bool, offset:Int, type:SType}> = [];
	var size = 0;

	public function new(what:String, name:String, label:String, sf:SFunction, cf:Null<SFunction>, kind:Kind, reduced:Null<Type>, args:Array<Arg>, lower:ParallelLower, hasEmpty:Bool) {
		this.what = what;
		this.name = name;
		this.label = label;
		this.sf = sf;
		this.cf = cf;
		this.kind = kind;
		this.reduced = reduced;
		this.args = args;
		this.hasEmpty = hasEmpty;
		this.lower = lower;
		pos = Context.currentPos();
		module = Context.getLocalModule();
		pack = module.split(".");
		pack.pop();
		// (the stage's parameters: each an argument's value or length, at its place in the context)
		var off = ParallelMacro.C_ARGS;
		for (k in 0...sf.fields.length) {
			var field = sf.fields[k], t = sf.params[k + 1].type;
			var length = StringTools.endsWith(field, "_length") && Lambda.findIndex(args, a -> a.name + "_length" == field) >= 0;
			var at = Lambda.findIndex(args, a -> length ? a.name + "_length" == field : a.name == field);
			if (at < 0) Context.error('$what: no argument for $field', pos);
			params.push({arg: at, length: length, offset: off, type: t});
			off += bytes(t);
		}
		size = off;
		var entry = new SEntry(Compute, sf, new SStruct("Item", "Item", []), [], [], []);
		soft = new Soft(new SProgram(entry, entry, [], []), name, pack, module);
		for (k in 0...params.length) {
			var p = params[k], v = sf.params[k + 1];
			switch p.type {
				case TStorage(e, w):
					var l = ShaderDefinition.std430(new ParallelLower(what), e, args[p.arg].display, pos);
					soft.storage.push(new SStorage(args[p.arg].name, k, e, w, l.offsets, l.stride, k));
				case _:
			}
		}
		rows();
	}

	// (each value's bytes in the context)
	static function bytes(t:SType):Int
		return switch t {
			case TVec(n): 8 * n;
			case TMat4: 128;
			case _: 8;
		}

	// the locals whose lanes are consecutive: the index, the locals made of it and never assigned
	function rows() {
		var index = sf.params[0];
		soft.rows.set(index, true);
		function walk(ss:Array<SStmt>)
			for (s in ss)
				switch s {
					case SDecl(v, {e: ELocal(w)}) if (soft.rows.exists(w) && !v.assigned): soft.rows.set(v, true);
					case SIf(_, a, b):
						walk(a);
						if (b != null) walk(b);
					case SWhile(_, b): walk(b);
					case _:
				}
		walk(sf.body);
	}

	// ---- reading and writing the context

	// a parameter's value from the context (the forms', the callback's)
	function read(k:Int):Expr {
		var p = params[k], o = p.offset;
		return switch p.type {
			case TStorage(_, _): macro hxmc.unsafe.Mem.getPtr(ctx, $v{o});
			case TInt: macro hxmc.unsafe.Mem.getI32(ctx, $v{o});
			case TBool: macro hxmc.unsafe.Mem.getI32(ctx, $v{o}) != 0;
			case TFloat: macro hxmc.unsafe.Mem.getF64(ctx, $v{o});
			case TVec(n): vec(n, [for (c in 0...n) macro hxmc.unsafe.Mem.getF64(ctx, $v{o + 8 * c})]);
			case TMat4:
				var cols = [for (c in 0...4) vec(4, [for (r in 0...4) macro hxmc.unsafe.Mem.getF64(ctx, $v{o + 32 * c + 8 * r})])];
				macro new helder.math.Mat4($a{cols});
			case t: Context.error('$what: a ${helder.gfx.shader.Names.typeName(t)} in the context', pos);
		}
	}

	function vec(n:Int, cs:Array<Expr>):Expr
		return {expr: haxe.macro.Expr.ExprDef.ENew({pack: ["helder", "math"], name: 'Vec$n'}, cs), pos: pos};

	// a parameter's value into the context (dispatch's: aK its argument)
	function write(k:Int):Expr {
		var p = params[k], o = p.offset, a = macro $i{"a" + p.arg};
		if (p.length) return macro hxmc.unsafe.Mem.setI32(ctx, $v{o}, $a.length);
		return switch p.type {
			case TStorage(_, _): macro hxmc.unsafe.Mem.setPtr(ctx, $v{o}, $a.data().binding());
			case TInt: macro hxmc.unsafe.Mem.setI32(ctx, $v{o}, $a);
			case TBool: macro hxmc.unsafe.Mem.setI32(ctx, $v{o}, $a ? 1 : 0);
			case TFloat: macro hxmc.unsafe.Mem.setF64(ctx, $v{o}, $a);
			case TVec(n): macro $b{[for (c in 0...n) {var x = "xyzw".charAt(c); macro hxmc.unsafe.Mem.setF64(ctx, $v{o + 8 * c}, $a.$x);}]};
			case TMat4: macro $b{[for (c in 0...4) for (r in 0...4) {var col = "c" + c, x = "xyzw".charAt(r); macro hxmc.unsafe.Mem.setF64(ctx, $v{o + 32 * c + 8 * r}, $a.$col.$x);}]};
			case t: Context.error('$what: a ${helder.gfx.shader.Names.typeName(t)} in the context', pos);
		}
	}

	// (the parameters read into locals pK: the forms' heads)
	function head():Expr
		return params.length == 0 ? macro null : {expr: EVars([for (k in 0...params.length) {name: "p" + k, expr: read(k)}]), pos: pos};

	function paramsList():Array<Expr>
		return [for (k in 0...params.length) macro $i{"p" + k}];

	// ---- the reduction's values: T's lanes, scalars, identity

	function rt():SType
		return sf.ret;

	function scalarOf(t:SType):ComplexType
		return soft.scalarType(t);

	function lanesOf(t:SType):ComplexType
		return soft.laneType(t);

	// T's value from the context's F64s (or I32s) at o
	function scalarAt(p:Expr, o:Expr):Expr
		return switch rt() {
			case TInt: macro hxmc.unsafe.Mem.getI32($p, $o);
			case TFloat: macro hxmc.unsafe.Mem.getF64($p, $o);
			case TVec(n): vec(n, [for (c in 0...n) macro hxmc.unsafe.Mem.getF64($p, $o + $v{8 * c})]);
			case _: throw "parallel";
		}

	function setScalarAt(p:Expr, o:Expr, v:Expr):Expr
		return switch rt() {
			case TInt: macro hxmc.unsafe.Mem.setI32($p, $o, $v);
			case TFloat: macro hxmc.unsafe.Mem.setF64($p, $o, $v);
			case TVec(n): macro {
					var sv = $v;
					$b{[for (c in 0...n) {var x = "xyzw".charAt(c); macro hxmc.unsafe.Mem.setF64($p, $o + $v{8 * c}, sv.$x);}]};
				};
			case _: throw "parallel";
		}

	// (the identity's value: the reduction's own, or reduce's empty, from the context)
	function identity():Expr
		return switch [kind, rt()] {
			case [Sum, TInt]: macro 0;
			case [Sum, TFloat]: macro 0.0;
			case [Sum, TVec(n)]: vec(n, [for (_ in 0...n) macro 0.0]);
			case [Min, TInt]: macro 2147483647;
			case [Min, TFloat]: macro Math.POSITIVE_INFINITY;
			case [Max, TInt]: macro -2147483648;
			case [Max, TFloat]: macro Math.NEGATIVE_INFINITY;
			case [Reduce, _]: scalarAt(macro ctx, macro $v{ParallelMacro.C_EMPTY});
			case _: throw "parallel";
		}

	function combineScalar(a:Expr, b:Expr):Expr
		return switch [kind, rt()] {
			case [Sum, _]: macro $a + $b;
			case [Min, TFloat]: macro Math.min($a, $b);
			case [Max, TFloat]: macro Math.max($a, $b);
			case [Min, _]: macro {
					var x = $a, y = $b;
					x < y ? x : y;
				};
			case [Max, _]: macro {
					var x = $a, y = $b;
					x > y ? x : y;
				};
			case _: macro $i{soft.func(cf, false, true)}($a, $b);
		}

	function combineLanes(m:Expr, a:Expr, b:Expr):Expr
		return switch kind {
			case Sum: macro $a + $b;
			case Min: macro $a.min($b);
			case Max: macro $a.max($b);
			case _: macro $i{soft.func(cf, false, false)}($m, $a, $b);
		}

	function laneAt(v:Expr, k:Int):Expr
		return switch rt() {
			case TInt | TFloat: macro $v.get($v{k});
			case TVec(n): vec(n, [for (c in 0...n) {var x = "xyzw".charAt(c); macro $v.$x.get($v{k});}]);
			case _: throw "parallel";
		}

	// ---- the class

	public function define(extra:Array<Field>) {
		var lanes = soft.func(sf, false, false), scalar = soft.func(sf, false, true), full = soft.funcFull(sf);
		var ps = paramsList();
		// (the lanes' parameters: the captures splatted once, before the loop)
		var ls = [for (k in 0...params.length) params[k].type.match(TStorage(_, _)) ? macro $i{"p" + k} : macro $i{"l" + k}];
		var vars = [for (k in 0...params.length) if (!params[k].type.match(TStorage(_, _))) {name: "l" + k, expr: soft.splat(params[k].type, macro $i{"p" + k})}];
		var splats:Expr = vars.length == 0 ? macro null : {expr: EVars(vars), pos: pos};
		// (whole groups: the full form, rows written whole; the last few: the masked one)
		var lanesCall = (m:Expr) -> macro $i{m.expr.match(EConst(CIdent("all"))) ? full : lanes}($a{[m, macro helder.gfx.soft.LaneInt.splat(i) + iota].concat(ls)});
		var fields:Array<Field> = [];
		var each = kind == Each;
		if (each) {
			fields = fields.concat((macro class {
				// (items from...to, 4 a call; the last few under a mask)
				static function lanes(ctx:hxmc.unsafe.Ptr, from:Int, to:Int):Void {
					${head()};
					$splats;
					var iota = helder.gfx.soft.LaneInt.make(0, 1, 2, 3), all = helder.gfx.soft.LaneBool.splat(true);
					var i = from;
					while (i + 4 <= to) {
						${lanesCall(macro all)};
						i += 4;
					}
					if (i < to) ${lanesCall(macro helder.gfx.soft.LaneBool.ofMask((1 << (to - i)) - 1))};
				}

				static function scalar(ctx:hxmc.unsafe.Ptr, n:Int):Void {
					${head()};
					for (i in 0...n)
						$i{scalar}($a{[macro i].concat(ps)});
				}

				// (chunk k of the items, on a thread)
				@:hxmc.callback @:hxmc.unsafe static function chunk(ctx:hxmc.unsafe.Ptr, k:Int):Int {
					var n = hxmc.unsafe.Mem.getI32(ctx, $v{ParallelMacro.C_COUNT}), c = hxmc.unsafe.Mem.getI32(ctx, $v{ParallelMacro.C_CHUNK});
					var from = k * c, to = from + c;
					if (to > n) to = n;
					if (from < to) lanes(ctx, from, to);
					return 0;
				}
			}).fields);
		} else {
			var t = rt(), st = scalarOf(t), lt = lanesOf(t);
			var vt = soft.laneType(t);
			var splat = soft.splat(t, macro e);
			fields = fields.concat((macro class {
				// (chunk k's reduction into partials[k]: its lanes, then the lanes in pairs)
				static function partial(ctx:hxmc.unsafe.Ptr, k:Int):Void {
					${head()};
					$splats;
					var n = hxmc.unsafe.Mem.getI32(ctx, $v{ParallelMacro.C_COUNT});
					var from = k * $v{ParallelMacro.CHUNK}, to = from + $v{ParallelMacro.CHUNK};
					if (to > n) to = n;
					var iota = helder.gfx.soft.LaneInt.make(0, 1, 2, 3), all = helder.gfx.soft.LaneBool.splat(true);
					var e:$st = ${identity()};
					var acc:$lt = $splat;
					var i = from;
					while (i + 4 <= to) {
						var v:$vt = ${lanesCall(macro all)};
						acc = ${combineLanes(macro all, macro acc, macro v)};
						i += 4;
					}
					if (i < to) {
						var m = helder.gfx.soft.LaneBool.ofMask((1 << (to - i)) - 1);
						var v:$vt = ${lanesCall(macro m)};
						acc = ${soft.select(t, macro m, combineLanes(macro m, macro acc, macro v), macro acc)};
					}
					var s:$st = ${combineScalar(combineScalar(laneAt(macro acc, 0), laneAt(macro acc, 1)), combineScalar(laneAt(macro acc, 2), laneAt(macro acc, 3)))};
					${setScalarAt(macro hxmc.unsafe.Mem.getPtr(ctx, $v{ParallelMacro.C_PARTIALS}), macro k * 32, macro s)};
				}

				static function scalar(ctx:hxmc.unsafe.Ptr, n:Int):$st {
					${head()};
					var acc:$st = ${identity()};
					for (i in 0...n)
						acc = ${combineScalar(macro acc, macro $i{scalar}($a{[macro i].concat(ps)}))};
					return acc;
				}

				@:hxmc.callback @:hxmc.unsafe static function chunk(ctx:hxmc.unsafe.Ptr, k:Int):Int {
					partial(ctx, k);
					return 0;
				}
			}).fields);
		}
		fields = fields.concat((macro class {
			static final site = new helder.parallel.Site($v{label});
			static var chunkAt = hxmc.unsafe.Ptr.nil();

			static function chunkAddress():hxmc.unsafe.Ptr {
				if (chunkAt.isNull()) chunkAt = hxmc.unsafe.Callback.addr(chunk);
				return chunkAt;
			}
		}).fields);
		gpu();
		// (the Gpu form's Items, by its storage slots: refilled each dispatch)
		fields = fields.concat((macro class {
			static final gpuItems:Array<helder.parallel.ItemsData> = [];
		}).fields);
		fields.push(dispatch());
		fields = fields.concat(extra);
		soft.flush();
		// (the body's lanes inlined into the range's loop: measured faster, its
		// struct values kept out of calls; a value returned early can't be)
		var early = !each && earlyReturn(sf.body);
		for (f in soft.fields)
			if ((f.name == lanes || f.name == full) && !early && !f.access.contains(AInline)) f.access.push(AInline);
		fields = fields.concat(soft.fields);
		var exists = try Context.getType(pack.concat([name]).join(".")) != null catch (_:Dynamic) false;
		if (exists) return;
		// (-D helder.parallel.print: each site's class printed)
		if (Context.defined("helder.parallel.print")) {
			Sys.println("// " + pack.concat([name]).join("."));
			for (f in fields)
				Sys.println(new haxe.macro.Printer().printField(f));
		}
		Context.defineType({
			pack: pack,
			name: name,
			pos: pos,
			meta: [{name: ":noCompletion", pos: pos}, {name: ":hxmc.unsafe", params: [macro gc], pos: pos}],
			kind: TDClass(null, [], false, true),
			fields: fields
		}, module);
	}

	// ---- the Gpu form: the stage again, as a compute stage in the build's
	// languages (helder.gfx.shader's emitters): its index x + y * 65535 *
	// size (65535 workgroups a row), its captured values the fields of one
	// uniform block (a Bool an Int there, then the count, then a reduction's
	// identity), its Items storage buffers at slots 1...; as data in a class
	// of its own beside the site's (<name>_Gpu.form: a GpuForm), with the
	// stage's CPU back end form under -D helder.soft. each: workgroups of 64,
	// the invocations past n returned. A reduction: workgroups of GROUP, each
	// invocation's EACH values (GROUP apart; the identity past n) combined,
	// reduced in its subgroup (sum,
	// min, max: the subgroups' own, emulated where the device has none) or
	// stored as it is (reduce), then in workgroup memory in halves, a barrier
	// between, into the workgroup's partial; a second stage (<name>_Gpu2)
	// reduces partials so, until one is left (GpuRunner.reduce)

	public static inline var GROUP = 256;
	// (a reduction's items an invocation: a workgroup's SPAN in a row, GROUP apart)
	public static inline var EACH = 8;
	public static inline var SPAN = GROUP * EACH;

	// (the Gpu form's Items: their arguments, by slot)
	var gpuStorage:Array<Int> = [];

	function gpu() {
		var ci = switch lower.typeOf(Context.getType("helder.gfx.shader.ComputeInput"), pos) {
			case TStruct(s): s;
			case _: throw "parallel";
		}
		function field(s:SStruct, name:String):SField
			return Lambda.find(s.fields, f -> f.field == name);
		// (the names the stage has: the new parameters' kept apart)
		var taken = new Map<String, Bool>();
		for (v in sf.params)
			taken.set(v.name, true);
		function names(ss:Array<SStmt>)
			for (st in ss)
				switch st {
					case SDecl(v, _): taken.set(v.name, true);
					case SIf(_, a, b):
						names(a);
						if (b != null) names(b);
					case SWhile(_, b): names(b);
					case _:
				}
		names(sf.body);
		function svar(n:String, t:SType, assigned = false):SVar {
			var v = new SVar(helder.gfx.shader.Names.unique(n, x -> !taken.exists(x)), t);
			taken.set(v.name, true);
			v.assigned = assigned;
			return v;
		}
		var each = kind == Each;
		var t = each ? TVoid : rt();
		var widened = t.match(TVec(3));
		// (a Vec3's partials a Vec4's: std430 and workgroup memory pad it anyway)
		var wt = widened ? TVec(4) : t;
		var fields:Array<SField> = [], scalars = new Map<SVar, SField>(), storage:Array<{v:SVar, k:Int}> = [];
		for (k in 0...params.length) {
			var v = sf.params[k + 1];
			switch v.type {
				case TStorage(_, _): storage.push({v: v, k: k});
				case t:
					var f:SField = {name: "c" + k, field: "c" + k, type: t == TBool ? TInt : t, position: false};
					fields.push(f);
					scalars.set(v, f);
			}
		}
		var countField:SField = {name: "count", field: "count", type: TInt, position: false};
		fields.push(countField);
		var emptyField:SField = {name: "empty", field: "empty", type: wt, position: false};
		if (!each) fields.push(emptyField);
		var cs = new SStruct(lower.names.global("Captures"), "Captures", fields);
		var id = svar("gid_in", TStruct(ci)), u = svar("captured", TStruct(cs));
		function local(v:SVar):SExpr
			return {e: ELocal(v), t: v.type};
		function int(i:Int):SExpr
			return {e: EInt(i), t: TInt};
		function bin(op:SBinop, a:SExpr, b:SExpr, t:SType):SExpr
			return {e: EBinop(op, a, b), t: t};
		function ex(e:SExpr):SExpr
			return switch e.e {
				case ELocal(v) if (scalars.exists(v)):
					var f = scalars.get(v), x:SExpr = {e: EField(local(u), f.name), t: f.type};
					v.type == TBool ? {e: EBinop(Ne, x, int(0)), t: TBool} : x;
				case EField(a, n): {e: EField(ex(a), n), t: e.t};
				case ESwizzle(a, c): {e: ESwizzle(ex(a), c), t: e.t};
				case EColumn(a, c): {e: EColumn(ex(a), c), t: e.t};
				case EIndex(a, i): {e: EIndex(ex(a), ex(i)), t: e.t};
				case EUnop(o, a): {e: EUnop(o, ex(a)), t: e.t};
				case EBinop(o, a, b): {e: EBinop(o, ex(a), ex(b)), t: e.t};
				case ECond(c, a, b): {e: ECond(ex(c), ex(a), ex(b)), t: e.t};
				case ENew(xs): {e: ENew([for (x in xs) ex(x)]), t: e.t};
				case EBuiltin(n, xs): {e: EBuiltin(n, [for (x in xs) ex(x)]), t: e.t};
				case ECall(g, xs): {e: ECall(g, [for (x in xs) ex(x)]), t: e.t};
				case EConvert(a): {e: EConvert(ex(a)), t: e.t};
				case _: e;
			}
		function st(x:SStmt):SStmt
			return switch x {
				case SDecl(v, i): SDecl(v, i == null ? null : ex(i));
				case SAssign(v, o, e): SAssign(v, o, ex(e));
				case SEval(e): SEval(ex(e));
				case SIf(c, a, b): SIf(ex(c), [for (y in a) st(y)], b == null ? null : [for (y in b) st(y)]);
				case SWhile(c, b): SWhile(ex(c), [for (y in b) st(y)]);
				case SReturn(e): SReturn(e == null ? null : ex(e));
				case SStore(b, i, v): SStore(ex(b), ex(i), ex(v));
				case _: x;
			}
		var size = each ? 64 : GROUP;
		function idField(v:SVar, n:String):SExpr
			return {e: EField(local(v), field(ci, n).name), t: TInt};
		function indexOf(v:SVar):SExpr
			return bin(Add, idField(v, "x"), bin(Mul, idField(v, "y"), int(65535 * size), TInt), TInt);
		var block:SUniform = @:privateAccess ShaderDefinition.std140(lower, cs, 0, pos);
		var resources:Array<SResource> = [RUniform(block)];
		var slot = 1;
		for (s in storage) {
			var e = switch s.v.type {
				case TStorage(e, _): e;
				case _: throw "parallel";
			}
			var l = ShaderDefinition.std430(lower, e, args[params[s.k].arg].display, pos);
			resources.push(RStorage(new SStorage(sf.fields[s.k], slot, e, true, l.offsets, l.stride, slot - 1)));
			slot++;
		}
		if (slot - (each ? 1 : 0) > 8)
			Context.error('$what: more than ${each ? 8 : 7} Items for the GPU (D3D11\'s compute stage writes 8 at most' + (each ? ")" : ", a reduction's partials one)"), pos);
		var kinds = [], from = [], to = [];
		function kindOf(t:SType):Int
			return switch t {
				case TInt: GpuKind.KINT;
				case TBool: GpuKind.KBOOL;
				case TFloat: GpuKind.KFLOAT;
				case TMat4: GpuKind.KMAT;
				case TVec(n): GpuKind.KVEC + n;
				case _: throw "parallel";
			}
		for (k in 0...params.length) {
			var v = sf.params[k + 1], f = scalars.get(v);
			if (f == null) continue;
			kinds.push(kindOf(v.type));
			from.push(params[k].offset);
			to.push(block.offsets[fields.indexOf(f)]);
		}
		// (a reduction's identity: from where dispatch writes it, its value read back there)
		if (!each) {
			kinds.push(kindOf(t));
			from.push(ParallelMacro.C_EMPTY);
			to.push(block.offsets[fields.indexOf(emptyField)]);
		}
		var countAt = block.offsets[fields.indexOf(countField)];
		var slots = [for (i in 0...storage.length) i + 1];
		var writes = [for (s in storage) args[params[s.k].arg].written];
		gpuStorage = [for (s in storage) params[s.k].arg];
		var index = sf.params[0];
		// (a reduction's invocation: its EACH items of its workgroup's span, combined into acc, then the tree)
		function items(id:SVar, acc:SVar, index:SVar, value:SVar, empty:SExpr, count:SExpr, computed:Array<SStmt>, combine:(SExpr, SExpr) -> SExpr):Array<SStmt> {
			var k = svar("k", TInt, true), base = svar("base", TInt);
			var group = bin(Add, idField(id, "groupX"), bin(Mul, idField(id, "groupY"), int(65535), TInt), TInt);
			return [
				SDecl(acc, empty),
				SDecl(base, bin(Add, bin(Mul, group, int(SPAN), TInt), idField(id, "localIndex"), TInt)),
				SDecl(k, int(0)),
				SWhile(bin(Lt, local(k), int(EACH), TBool), [
					SDecl(index, bin(Add, local(base), bin(Mul, local(k), int(GROUP), TInt), TInt)),
					SIf(bin(Lt, local(index), count, TBool), [SDecl(value, empty)].concat(computed).concat([SAssign(acc, null, combine(local(acc), local(value)))]), null),
					SAssign(k, null, bin(Add, local(k), int(1), TInt))
				])
			];
		}
		var gf = new SFunction(lower.names.global(sf.name + "_gpu"), [id, u].concat([for (s in storage) s.v]), TVoid);
		gf.fields = ["captured"].concat([for (s in storage) sf.fields[s.k]]);
		var gpuName = name + "_Gpu";
		if (each) {
			var body:Array<SStmt> = [SDecl(index, indexOf(id)), SIf(bin(Ge, local(index), {e: EField(local(u), countField.name), t: TInt}, TBool), [SReturn(null)], null)];
			gf.body = body.concat([for (s in sf.body) st(s)]);
			var c = code(gpuName, gf, ci, resources, [], false, size);
			stage(gpuName, macro new helder.parallel.GpuForm($c, $v{block.size}, 0, $v{countAt}, $v{kinds}, $v{from}, $v{to}, $v{slots}, $v{writes}));
			return;
		}
		function widen(e:SExpr):SExpr
			return widened ? {e: ENew([e, {e: EFloat(0), t: TFloat}]), t: wt} : e;
		function narrow(e:SExpr):SExpr
			return widened ? {e: ESwizzle(e, "xyz"), t: t} : e;
		function combine(a:SExpr, b:SExpr):SExpr
			return switch kind {
				case Sum: bin(Add, a, b, wt);
				case Min: {e: EBuiltin("min", [a, b]), t: wt};
				case Max: {e: EBuiltin("max", [a, b]), t: wt};
				case _: widen({e: ECall(cf, [narrow(a), narrow(b)]), t: t});
			}
		var subgroup = switch kind {
			case Sum: "subgroupAdd";
			case Min: "subgroupMin";
			case Max: "subgroupMax";
			case _: null;
		}
		var barrier = SEval({e: EBuiltin("barrier", []), t: TVoid});
		// (v reduced over the workgroup, its value out[the workgroup's index])
		function tree(id:SVar, v:SVar, wg:SVar, out:SExpr):Array<SStmt> {
			var li = idField(id, "localIndex"), ss:Array<SStmt> = [];
			var live = int(GROUP);
			if (subgroup != null) {
				ss.push(SAssign(v, null, {e: EBuiltin(subgroup, [local(v)]), t: wt}));
				ss.push(SIf(bin(Eq, idField(id, "subgroupLane"), int(0), TBool), [SStore(local(wg), idField(id, "subgroupIndex"), local(v))], null));
				live = idField(id, "subgroups");
			} else ss.push(SStore(local(wg), li, local(v)));
			ss.push(barrier);
			var half = svar("half", TInt, true);
			var other = bin(Add, li, local(half), TInt);
			ss.push(SDecl(half, int(GROUP >> 1)));
			ss.push(SWhile(bin(Gt, local(half), int(0), TBool), [
				SIf(bin(And, bin(Lt, li, local(half), TBool), bin(Lt, other, live, TBool), TBool),
					[SStore(local(wg), li, combine({e: EIndex(local(wg), li), t: wt}, {e: EIndex(local(wg), other), t: wt}))], null),
				barrier,
				SAssign(half, null, bin(Div, local(half), int(2), TInt))
			]));
			var group = bin(Add, idField(id, "groupX"), bin(Mul, idField(id, "groupY"), int(65535), TInt), TInt);
			ss.push(SIf(bin(Eq, li, int(0), TBool), [SStore(out, group, {e: EIndex(local(wg), int(0)), t: wt})], null));
			return ss;
		}
		var l = ShaderDefinition.std430(lower, wt, "a reduction's value", pos);
		function shared(v:SVar):SShared
			return new SShared("part", v, wt, GROUP, l.offsets, l.stride, 0);
		// (the body's returns its value: the last statement's as it is, the others a break out of a loop around)
		var value = svar("value", wt, true), done = svar("done", TBool, true);
		var early = earlyReturn(sf.body);
		function rets(ss:Array<SStmt>):Array<SStmt> {
			var out = [];
			for (s in ss)
				switch s {
					case SReturn(e) if (!early):
						out.push(SAssign(value, null, widen(ex(e))));
					case SReturn(e):
						out.push(SAssign(value, null, widen(ex(e))));
						out.push(SAssign(done, null, {e: EBool(true), t: TBool}));
						out.push(SBreak);
					case SIf(c, a, b): out.push(SIf(ex(c), rets(a), b == null ? null : rets(b)));
					case SWhile(c, b):
						out.push(SWhile(ex(c), rets(b)));
						if (early) out.push(SIf(local(done), [SBreak], null));
					case s: out.push(st(s));
				}
			return out;
		}
		var computed = rets(sf.body);
		if (early) computed = [SDecl(done, {e: EBool(false), t: TBool}), SWhile({e: EBool(true), t: TBool}, computed.concat([SBreak]))];
		var parts = svar("parts", TStorage(wt, true)), wg = svar("part", TWorkgroup(wt));
		var empty:SExpr = {e: EField(local(u), emptyField.name), t: wt};
		var count:SExpr = {e: EField(local(u), countField.name), t: TInt};
		gf.params.push(parts);
		gf.params.push(wg);
		gf.fields.push("parts");
		gf.workgroup = [{name: "part", length: 0}];
		var result = svar("result", wt, true);
		gf.body = items(id, result, index, value, empty, count, computed, combine);
		gf.body = gf.body.concat(tree(id, result, wg, local(parts)));
		var partSlot = storage.length + 1;
		resources.push(RStorage(new SStorage("parts", partSlot, wt, true, l.offsets, l.stride, partSlot - 1)));
		// (the partials' stage: from's values (the identity past the count) reduced into to)
		var id2 = svar("gid_in", TStruct(ci)), u2 = svar("captured", TStruct(cs));
		var at = svar("index", TInt), v2 = svar("value", wt, true), wg2 = svar("part", TWorkgroup(wt));
		var src = svar("from", TStorage(wt, true)), dst = svar("to", TStorage(wt, true));
		var g2 = new SFunction(lower.names.global(sf.name + "_partials"), [id2, u2, src, dst, wg2], TVoid);
		g2.fields = ["captured", "from", "to"];
		g2.workgroup = [{name: "part", length: 0}];
		var empty2:SExpr = {e: EField(local(u2), emptyField.name), t: wt}, r2v = svar("result", wt, true);
		g2.body = items(id2, r2v, at, v2, empty2, {e: EField(local(u2), countField.name), t: TInt}, [SAssign(v2, null, {e: EIndex(local(src), local(at)), t: wt})], combine);
		g2.body = g2.body.concat(tree(id2, r2v, wg2, local(dst)));
		var r2:Array<SResource> = [
			RUniform(block),
			RStorage(new SStorage("from", 1, wt, true, l.offsets, l.stride, 0)),
			RStorage(new SStorage("to", 2, wt, true, l.offsets, l.stride, 1))
		];
		var subgroups = subgroup != null;
		var nextName = name + "_Gpu2";
		var nextPath = pack.concat([nextName, "form"]);
		var c2 = code(nextName, g2, ci, r2, [shared(wg2)], subgroups, size);
		stage(nextName, macro new helder.parallel.GpuForm($c2, $v{block.size}, 0, $v{countAt}, $v{kinds}, $v{from}, $v{to}, [1, 2], [false, true]));
		var c = code(gpuName, gf, ci, resources, [shared(wg)], subgroups, size);
		stage(gpuName, macro new helder.parallel.GpuForm($c, $v{block.size}, 0, $v{countAt}, $v{kinds}, $v{from}, $v{to}, $v{slots.concat([partSlot])},
			$v{writes.concat([true])}, $p{nextPath}, $v{kindOf(t)}, $v{l.stride}));
	}

	// (whether a return is other than the body's last statement)
	static function earlyReturn(body:Array<SStmt>):Bool {
		function scan(ss:Array<SStmt>, top:Bool):Bool {
			for (k in 0...ss.length)
				switch ss[k] {
					case SReturn(_) if (!top || k != body.length - 1): return true;
					case SIf(_, a, b) if (scan(a, false) || (b != null && scan(b, false))): return true;
					case SWhile(_, b) if (scan(b, false)): return true;
					case _:
				}
			return false;
		}
		return scan(body, true);
	}

	// (a stage's compute program)
	function program(gf:SFunction, ci:SStruct, resources:Array<SResource>, shared:Array<SShared>, subgroups:Bool, size:Int):SCompute
		return new SCompute(@:privateAccess ShaderDefinition.entry(Compute, gf, ci, resources), [size, 1, 1], shared, subgroups);

	// (the last stage's CPU back end form)
	var softForm:Null<{soft:Soft, code:Expr}> = null;

	// a stage's ShaderCode: its texts in the build's languages (with
	// subgroups, cs_5_0's only in the emulated form), its bindings, its size
	function code(gpuName:String, gf:SFunction, ci:SStruct, resources:Array<SResource>, shared:Array<SShared>, subgroups:Bool, size:Int):Expr {
		var c = program(gf, ci, resources, shared, subgroups, size);
		var android = StringTools.startsWith(Context.definedValue("hxmc.target") ?? "", "android");
		function texts(c:SCompute):Array<ObjectField>
			return [
				for (l in ShaderDefinition.languages(lower, pos))
					if (l != "hlsl" || !c.subgroups || c.emulated) {
						field: l,
						expr: macro $v{switch l {
							case "glsl": new helder.gfx.shader.Glsl(android).compute(c);
							case "wgsl": new helder.gfx.shader.Wgsl().compute(c);
							case "msl": new helder.gfx.shader.Msl().compute(c);
							case _: new helder.gfx.shader.Hlsl().compute(c);
						}}
					}
			];
		var code = texts(c);
		if (subgroups) code.push({field: "emulated", expr: {expr: EObjectDecl(texts(helder.gfx.shader.Subgroups.emulate(c))), pos: pos}});
		var bindings:Array<Expr> = [];
		for (r in resources)
			switch r {
				case RUniform(b):
					bindings.push(macro {
						name: $v{b.struct.name + "_block"},
						slot: $v{b.binding},
						kind: (cast 0 : helder.gfx.ShaderBinding.BindingKind),
						size: $v{b.size},
						index: $v{b.binding},
						format: 0,
						dimension: 0
					});
				case RStorage(b):
					bindings.push(macro {
						name: $v{"sb_" + b.slot},
						slot: $v{b.slot},
						kind: (cast 3 : helder.gfx.ShaderBinding.BindingKind),
						size: $v{b.stride},
						index: $v{b.index},
						format: 0,
						dimension: 0
					});
				case _:
			}
		code.push({field: "bindings", expr: macro [$a{bindings}]});
		code.push({field: "workgroupSize", expr: macro [$v{size}, 1, 1]});
		softForm = null;
		if (Soft.enabled()) {
			softForm = Soft.compute(c, gpuName, pack, module);
			code.push({field: "soft", expr: softForm.code});
		}
		return {expr: EObjectDecl(code), pos: pos};
	}

	// (a stage's class beside the site's: its form, and the CPU back end's fields of the last code made)
	function stage(gpuName:String, made:Expr) {
		var gfields:Array<Field> = softForm == null ? [] : softForm.soft.fields.copy();
		gfields = gfields.concat((macro class {
			public static final form = $made;
		}).fields);
		var exists = try Context.getType(pack.concat([gpuName]).join(".")) != null catch (_:Dynamic) false;
		if (!exists) Context.defineType({
			pack: pack,
			name: gpuName,
			pos: pos,
			meta: [{name: ":noCompletion", pos: pos}, {name: ":hxmc.unsafe", params: [macro gc], pos: pos}],
			kind: TDClass(null, [], false, true),
			fields: gfields
		}, module);
	}

	// dispatch(n, on, a0, a1, ...): the checks, the form picked, the context written, the form run
	function dispatch():Field {
		var fargs:Array<FunctionArg> = [{name: "n", type: macro :Int}, {name: "on", type: macro :helder.parallel.On}];
		for (k in 0...args.length)
			fargs.push({name: "a" + k, type: args[k].type});
		if (hasEmpty) fargs.push({name: "empty", type: reduced.toComplexType()});
		var body:Array<Expr> = [];
		var each = kind == Each;
		var none = each ? macro return : macro return ${hasEmpty ? macro empty : identity()};
		// (the identity of min, max and sum needs no context: written here for none)
		if (!each && !hasEmpty) none = switch [kind, rt()] {
			case [Sum, TInt]: macro return 0;
			case [Sum, TFloat]: macro return 0.0;
			case [Sum, TVec(n)]: macro return ${vec(n, [for (_ in 0...n) macro 0.0])};
			case [Min, TInt]: macro return 2147483647;
			case [Min, TFloat]: macro return Math.POSITIVE_INFINITY;
			case [Max, TInt]: macro return -2147483648;
			case [Max, TFloat]: macro return Math.NEGATIVE_INFINITY;
			case _: throw "parallel";
		}
		// (the Items: not disposed, as long as n where read at the item's index; one written is no other's)
		for (k in 0...args.length) {
			var a = args[k];
			if (!a.stype.match(TStorage(_, _))) continue;
			var x = macro $i{"a" + k}, nm = a.display;
			body.push(macro if ($x.disposed) throw new haxe.Exception($v{'$what: $nm is disposed'}));
			if (a.own) body.push(macro if ($x.length < n) throw new haxe.Exception($v{'$what: $nm has '} + $x.length + $v{' items, fewer than n ('} + n + ")"));
		}
		for (k in 0...args.length)
			for (j in 0...args.length) {
				var a = args[k], b = args[j];
				if (j == k || !a.written || !b.stype.match(TStorage(_, _)) || (b.written && j < k)) continue;
				var x = macro $i{"a" + k}, y = macro $i{"a" + j};
				body.push(macro if ($x.data() == $y.data()) throw new haxe.Exception($v{'$what: ${a.display} is also ${b.display}: an Items a body writes is passed once'}));
			}
		// (Auto's residency: an Items the body writes the GPU's alone, or drawn
		// by it; a reduction's, an Items it reads whose values are the GPU's alone)
		var resident:Expr = macro false;
		for (k in 0...args.length) {
			var x = macro $i{"a" + k};
			if (each && args[k].written) resident = macro $resident || $x.data().byGpu || $x.data().drawn;
			if (!each && args[k].stype.match(TStorage(_, _))) resident = macro $resident || $x.data().state & helder.parallel.ItemsData.CPU == 0;
		}
		body.push(macro var form = site.pick(on, n, $resident, helder.parallel.Parallel.gpu()));
		body.push(macro if (n <= 0) $none);
		// (the CPU forms' Items their values on the CPU: read back where a dispatch
		// wrote them; written, the GPU's copies stale)
		var toCpu = [for (k in 0...args.length) if (args[k].stype.match(TStorage(_, _))) {var x = macro $i{"a" + k}; macro $x.data().cpu();}];
		var wrote = [for (k in 0...args.length) if (args[k].written) {var x = macro $i{"a" + k}; macro $x.data().cpuWrote();}];
		body.push(macro if (form != Gpu) $b{toCpu});
		body.push(macro var ctx = hxmc.unsafe.Mem.stack($v{size}));
		body.push(macro hxmc.unsafe.Mem.setI32(ctx, $v{ParallelMacro.C_COUNT}, n));
		for (k in 0...params.length)
			body.push(write(k));
		if (hasEmpty) body.push(setScalarAt(macro ctx, macro $v{ParallelMacro.C_EMPTY}, macro empty));
		body.push(macro var t0 = site.timing ? haxe.Timer.stamp() : 0.0);
		var fill = [for (j in 0...gpuStorage.length) {var x = macro $i{"a" + gpuStorage[j]}; macro gpuItems[$v{j}] = $x.data();}];
		var gpuPath = pack.concat([name + "_Gpu", "form"]);
		if (each) {
			body.push(macro switch form {
				case Gpu:
					$b{fill};
					helder.parallel.Parallel.dispatchGpu($p{gpuPath}, n, ctx, gpuItems);
				case Scalar: scalar(ctx, n);
				case Jobs:
					// (4 chunks a thread, each a multiple of 4 items)
					var pieces = (helder.jobs.Spread.threads() + 1) * 4;
					var c = ((Std.int((n + pieces - 1) / pieces) + 3) >> 2) << 2;
					hxmc.unsafe.Mem.setI32(ctx, $v{ParallelMacro.C_CHUNK}, c);
					helder.jobs.Spread.run(chunkAddress(), ctx, Std.int((n + c - 1) / c));
				case _: lanes(ctx, 0, n);
			});
			body.push(macro if (form != Gpu) $b{wrote});
			body.push(macro if (site.timing) site.took(form, n, haxe.Timer.stamp() - t0));
		} else {
			body.push(macro if (form != Gpu) $b{wrote});
			var st = scalarOf(rt());
			body.push(macro var r:$st);
			// (the Gpu form's identity in the context, its value read back there)
			var empty = hasEmpty ? macro null : setScalarAt(macro ctx, macro $v{ParallelMacro.C_EMPTY}, identity());
			body.push(macro if (form == Scalar) r = scalar(ctx, n) else if (form == Gpu) {
				$b{fill};
				$empty;
				helder.parallel.Parallel.reduceGpu($p{gpuPath}, n, ctx, gpuItems);
				r = ${scalarAt(macro ctx, macro $v{ParallelMacro.C_EMPTY})};
			} else {
				var chunks = Std.int((n + $v{ParallelMacro.CHUNK - 1}) / $v{ParallelMacro.CHUNK});
				var partials = hxmc.unsafe.LibC.malloc(chunks * 32);
				hxmc.unsafe.Mem.setPtr(ctx, $v{ParallelMacro.C_PARTIALS}, partials);
				if (form == Jobs) helder.jobs.Spread.run(chunkAddress(), ctx, chunks) else for (k in 0...chunks)
					partial(ctx, k);
				r = ${identity()};
				for (k in 0...chunks)
					r = ${combineScalar(macro r, scalarAt(macro partials, macro k * 32))};
				hxmc.unsafe.LibC.free(partials);
			});
			body.push(macro if (site.timing) site.took(form, n, haxe.Timer.stamp() - t0));
			body.push(macro return r);
		}
		return {
			name: "dispatch",
			access: [APublic, AStatic],
			meta: [{name: ":hxmc.unsafe", params: [macro gc], pos: pos}],
			kind: FFun({args: fargs, ret: each ? macro :Void : reduced.toComplexType(), expr: macro $b{body}}),
			pos: pos
		};
	}
}
#end
