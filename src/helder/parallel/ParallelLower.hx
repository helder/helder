package helder.parallel;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import helder.gfx.shader.Ir;

using haxe.macro.Tools;

private typedef L = helder.gfx.shader.Lower;

// A body lowered to the shader IR (helder.gfx.shader.Lower, as a compute
// stage's is): its index the stage's input, each value it captures (a
// local, a field of this, a static's) a parameter of the stage made where
// first read (Lower.stageParam: a scalar every lane shares, an Items a
// storage buffer), an Items' get, set and length its storage's element
// read, written and a captured length, a local copy of an Items the same
// buffer. Errors say the definition's name (each: ..., kernel: ...).
@:access(helder.gfx.shader.Lower)
class ParallelLower extends helder.gfx.shader.Lower {
	final what:String;

	// the captures by key (ParallelScan.key): their parameter's name and type
	public final captures = new Map<String, {name:String, type:SType}>();

	final aliases = new Map<Int, SExpr>();

	public function new(what:String) {
		super();
		this.what = what;
	}

	override public function error(message:String, pos:helder.compiler.Kernel.KPos):Dynamic
		return Context.error('$what: $message', pos);

	// an Items type's element type (helder.parallel.gen.Items_*: its get's result), else null
	public static function itemsElement(t:Type):Null<Type>
		return switch t {
			case TMono(r) if (r.get() != null): itemsElement(r.get());
			case TLazy(f): itemsElement(f());
			case TType(_, _): itemsElement(Context.follow(t, true));
			case TAbstract(a, _) if (a.get().meta.has(":parallel.items")):
				var impl = a.get().impl;
				var get = impl == null ? null : Lambda.find(impl.get().statics.get(), f -> f.name == "get");
				get == null ? null : switch Context.follow(get.type) {
					case TFun(_, r): r;
					case _: null;
				}
			case _: null;
		}

	static function isItemsImpl(c:ClassType):Bool
		return switch c.kind {
			case KAbstractImpl(a): a.get().meta.has(":parallel.items");
			case _: false;
		}

	override function type(t:Type, pos:Position):SType {
		var e = itemsElement(t);
		return e != null ? TStorage(super.type(e, pos), true) : super.type(t, pos);
	}

	// a Haxe type's IR type (an Items: a storage buffer of its elements)
	public function typeOf(t:Type, pos:Position):SType
		return type(t, pos);

	// (a capture's parameter, made where first read)
	function param(key:String, pos:Position):Null<SExpr> {
		var c = captures.get(key);
		return c == null ? null : L.local(stageParam(c.name, c.type, pos));
	}

	override function expr(e:TypedExpr, out:Array<SStmt>):SExpr {
		if (kind == Stage) {
			var k = ParallelScan.key(e);
			if (k != null) {
				var p = param(k, e.pos);
				if (p != null) return p;
			}
			switch e.expr {
				case TLocal(v) if (aliases.exists(v.id)): return aliases.get(v.id);
				case _:
			}
		}
		return super.expr(e, out);
	}

	override function stmt(e:TypedExpr, out:Array<SStmt>) {
		switch e.expr {
			// (a local copy of an Items, Haxe's temporaries for items[i] += x: the same buffer)
			case TVar(v, init) if (kind == Stage && init != null && itemsElement(v.t) != null):
				aliases.set(v.id, expr(init, out));
				return;
			case _:
		}
		super.stmt(e, out);
	}

	override function call(f:TypedExpr, args:Array<TypedExpr>, e:TypedExpr, out:Array<SStmt>):SExpr {
		switch L.strip(f).expr {
			case TField(_, FStatic(c, cf)) if (isItemsImpl(c.get())):
				var name = cf.get().name;
				switch name {
					case "get":
						var b = expr(args[0], out);
						return {e: EIndex(b, coerce(expr(args[1], out), TInt, args[1].pos)), t: type(e.t, e.pos)};
					case "set" | "setFields":
						var b = expr(args[0], out);
						var t = switch b.t {
							case TStorage(t, _): t;
							case _: error("an Items' element", e.pos);
						}
						var i = coerce(expr(args[1], out), TInt, args[1].pos);
						var v = name == "set" ? coerce(expr(args[2], out), t, args[2].pos) : literal(t, args[2], out);
						// (the index and the value read once: locals unless they are)
						if (!i.e.match(ELocal(_) | EInt(_))) {
							var tmp = temp(TInt);
							out.push(SDecl(tmp, i));
							i = L.local(tmp);
						}
						if (!v.e.match(ELocal(_))) {
							var tmp = temp(t);
							out.push(SDecl(tmp, v));
							v = L.local(tmp);
						}
						out.push(SStore(b, i, v));
						return v;
					case "get_length":
						var k = ParallelScan.key(args[0], paramsObject == null ? -1 : paramsObject.id);
						var p = k == null ? null : param("length:" + k, e.pos);
						if (p == null) error("an Items' length is read in a body as a captured Items' (items.length)", e.pos);
						return p;
					case _:
						error('Items.$name is not read in a body (an Items is indexed there: items[i], items[i] = v, items.length)', e.pos);
				}
			case _:
		}
		return super.call(f, args, e, out);
	}

	// (a struct element of an object literal of its fields: items[i] = {pos: p, vel: v})
	function literal(t:SType, x:TypedExpr, out:Array<SStmt>):SExpr {
		var s = switch t {
			case TStruct(s): s;
			case _: error("an Items' struct element", x.pos);
		}
		var fs = switch L.strip(x).expr {
			case TObjectDecl(fs): fs;
			case _: error('an item of ${s.path} is set to a ${s.path} or to an object literal of its fields ({${[for (f in s.fields) f.field].join(", ")}})', x.pos);
		}
		var given:Array<Null<TypedExpr>> = [];
		for (f in s.fields) {
			var g = Lambda.find(fs, y -> y.name == f.field);
			if (g == null) error('${s.path}: the field ${f.field} is not given', x.pos);
			given.push(g.expr);
		}
		return build(s, given, out);
	}

	// a function of the definition that is no stage (a reduction's combine), in the caller's scope
	public function lowerPlain(e:Expr, name:String):SFunction {
		var te = typeIn(e, e);
		var tf = switch L.strip(te).expr {
			case TFunction(tf): tf;
			case _: error("a function literal", e.pos);
		}
		return lower("<" + name + ">", name, tf, e.pos);
	}
}
#end
