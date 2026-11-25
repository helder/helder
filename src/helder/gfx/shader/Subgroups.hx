package helder.gfx.shader;

import helder.gfx.shader.Ir;

// A compute stage's subgroups (ShaderMath's subgroupAdd ..., ComputeInput's
// subgroupLane ...): whether it uses them, and its second form for the
// devices without them (Feature.Subgroups: D3D11, WebGPU and GL without
// them), made of workgroup memory and barriers in subgroups of 4 lanes,
// the CPU back end's: each operation a statement of its own before the one
// it is in, its value written at the invocation's place in a scratch array
// as long as the workgroup (one for each type the operations take), a
// barrier, its subgroup's 4 values read and combined, a barrier again (the
// scratch free for the next). Uniformity keeps every invocation of the
// workgroup at those barriers.
class Subgroups {
	public static final OPS = [
		"subgroupAdd", "subgroupMin", "subgroupMax", "subgroupBroadcast", "subgroupShuffle", "subgroupAll", "subgroupAny"
	];
	// (ComputeInput's)
	public static final FIELDS = ["subgroupLane", "subgroupSize", "subgroupIndex", "subgroups"];
	// the lanes of a subgroup where they are emulated
	public static inline var EMULATED = 4;

	public static function isOp(name:String):Bool
		return OPS.contains(name);

	// the operations a function calls, and whether it reads a subgroup field of its input
	public static function used(f:SFunction):{ops:Array<String>, fields:Bool} {
		var ops = [], fields = false;
		var input = f.params.length == 0 ? null : f.params[0];
		function ex(e:SExpr)
			switch e.e {
				case EBuiltin(name, args):
					if (isOp(name) && !ops.contains(name)) ops.push(name);
					for (a in args)
						ex(a);
				case EField({e: ELocal(v)}, n) if (v == input && FIELDS.contains(n)): fields = true;
				case EField(x, _) | ESwizzle(x, _) | EColumn(x, _) | EUnop(_, x) | EConvert(x): ex(x);
				case EIndex(x, i):
					ex(x);
					ex(i);
				case EBinop(_, a, b):
					ex(a);
					ex(b);
				case ECond(c, a, b):
					ex(c);
					ex(a);
					ex(b);
				case ENew(args) | ECall(_, args): for (a in args) ex(a);
				case EFloat(_) | EInt(_) | EBool(_) | ELocal(_):
			}
		statements(f.body, ex);
		return {ops: ops, fields: fields};
	}

	// whether a stage's function uses subgroups
	public static function uses(f:SFunction):Bool {
		var u = used(f);
		return u.ops.length > 0 || u.fields;
	}

	// the scratch arrays' bytes its emulated form adds, for a workgroup of n
	public static function scratch(f:SFunction, n:Int):Int {
		var types:Array<SType> = [];
		function ex(e:SExpr) {
			switch e.e {
				case EBuiltin(name, _) if (isOp(name)):
					var t = scratchType(e);
					if (!Lambda.exists(types, u -> Names.same(u, t))) types.push(t);
				case _:
			}
			children(e, ex);
		}
		statements(f.body, ex);
		var bytes = 0;
		for (t in types)
			bytes += size(t) * n;
		return bytes;
	}

	// (All and Any: Ints)
	static function scratchType(e:SExpr):SType
		return switch e.e {
			case EBuiltin("subgroupAll" | "subgroupAny", _): TInt;
			case _: e.t;
		}

	static function size(t:SType):Int
		return switch t {
			case TVec(2): 8;
			case TVec(_): 16;
			case _: 4;
		}

	// the stage's emulated form: its function's operations made of scratch
	// memory and barriers, the subgroup fields of its input 4 lanes'
	public static function emulate(c:SCompute):SCompute {
		var e = c.entry, f = e.fn, n = c.invocations;
		var input = f.params[0];
		var params = f.params.copy(), shared = c.shared.copy();
		var scratch = new Map<String, SShared>();
		var temps = 0;
		function local(v:SVar):SExpr
			return {e: ELocal(v), t: v.type};
		function int(i:Int):SExpr
			return {e: EInt(i), t: TInt};
		function bin(op:SBinop, a:SExpr, b:SExpr, t:SType):SExpr
			return {e: EBinop(op, a, b), t: t};
		function scratchOf(t:SType):SExpr {
			var k = Names.typeName(t), s = scratch.get(k);
			if (s == null) {
				var v = new SVar("sg_" + k, TWorkgroup(t));
				params.push(v);
				s = new SShared("(subgroups' " + k + ")", v, t, n, [0], size(t), shared.length);
				shared.push(s);
				scratch.set(k, s);
			}
			return local(s.v);
		}
		var li:SExpr = {e: EField(local(input), "localIndex"), t: TInt};
		var base = bin(BitAnd, li, int(-EMULATED), TInt);
		var barrier:SStmt = SEval({e: EBuiltin("barrier", []), t: TVoid});
		// (lane k of the invocation's subgroup; past the workgroup: the last invocation's)
		function at(k:SExpr):SExpr
			return n % EMULATED == 0 ? bin(Add, base, k, TInt) : {e: EBuiltin("min", [bin(Add, base, k, TInt), int(n - 1)]), t: TInt};
		function op(x:SExpr, out:Array<SStmt>):SExpr {
			var name = switch x.e {
				case EBuiltin(name, _): name;
				case _: throw "subgroups";
			}
			var args = switch x.e {
				case EBuiltin(_, args): args;
				case _: throw "subgroups";
			}
			var t = scratchType(x), b = scratchOf(t);
			var value = t == TInt && args[0].t == TBool ? {e: ECond(args[0], int(1), int(0)), t: TInt} : args[0];
			function read(i:SExpr):SExpr
				return {e: EIndex(b, i), t: t};
			// (lane k's value, or where it is past the workgroup the identity)
			function term(k:Int, identity:SExpr):SExpr {
				if (k == 0) return read(base);
				var x = read(bin(Add, base, int(k), TInt));
				return n % EMULATED == 0 ? x : {e: ECond(bin(Lt, bin(Add, base, int(k), TInt), int(n), TBool), x, identity), t: t};
			}
			function fold(combine:(SExpr, SExpr) -> SExpr, identity:SExpr):SExpr {
				var r = term(0, identity);
				for (k in 1...EMULATED)
					r = combine(r, term(k, identity));
				return r;
			}
			var combined = switch name {
				case "subgroupAdd": fold((a, b) -> bin(Add, a, b, t), Names.zero(t));
				case "subgroupMin" | "subgroupMax":
					var m = name == "subgroupMin" ? "min" : "max";
					fold((a, b) -> {e: EBuiltin(m, [a, b]), t: t}, read(base));
				case "subgroupAll": bin(Ne, fold((a, b) -> bin(BitAnd, a, b, TInt), int(1)), int(0), TBool);
				case "subgroupAny": bin(Ne, fold((a, b) -> bin(BitOr, a, b, TInt), int(0)), int(0), TBool);
				case "subgroupBroadcast": read(at(args[1]));
				case "subgroupShuffle": read(at(bin(BitAnd, args[1], int(EMULATED - 1), TInt)));
				case _: throw "subgroups";
			}
			var r = new SVar("sg_" + temps++, x.t);
			out.push(SStore(b, li, value));
			out.push(barrier);
			out.push(SDecl(r, combined));
			out.push(barrier);
			return local(r);
		}
		// e with its operations' values (out: their statements, innermost first)
		function rx(e:SExpr, out:Array<SStmt>):SExpr {
			var x:SExpr = {e: rebuild(e.e, a -> rx(a, out)), t: e.t};
			return switch x.e {
				case EBuiltin(name, _) if (isOp(name)): op(x, out);
				case _: x;
			}
		}
		function rs(ss:Array<SStmt>):Array<SStmt> {
			var out = [];
			for (s in ss)
				switch s {
					case SDecl(v, init):
						var x = init == null ? null : rx(init, out);
						out.push(SDecl(v, x));
					case SAssign(v, o, x):
						var y = rx(x, out);
						out.push(SAssign(v, o, y));
					case SEval(x):
						var y = rx(x, out);
						out.push(SEval(y));
					case SStore(b, i, x):
						var j = rx(i, out), y = rx(x, out);
						out.push(SStore(b, j, y));
					case SReturn(x):
						var y = x == null ? null : rx(x, out);
						out.push(SReturn(y));
					case SIf(c, a, b):
						var c2 = rx(c, out);
						out.push(SIf(c2, rs(a), b == null ? null : rs(b)));
					// (no operation in a loop's condition: Uniformity)
					case SWhile(c, body): out.push(SWhile(c, rs(body)));
					case SBreak | SContinue: out.push(s);
				}
			return out;
		}
		var g = new SFunction(f.name, params, f.ret);
		g.fields = f.fields;
		g.workgroup = f.workgroup;
		g.body = rs(f.body);
		var entry = new SEntry(Compute, g, e.input, e.resources, e.structs, [for (h in e.functions) h == f ? g : h]);
		return new SCompute(entry, c.size, shared, true, true);
	}

	// (an expression's definition, its operands mapped)
	static function rebuild(d:SExprDef, f:SExpr->SExpr):SExprDef
		return switch d {
			case EField(x, n): EField(f(x), n);
			case ESwizzle(x, cs): ESwizzle(f(x), cs);
			case EColumn(x, i): EColumn(f(x), i);
			case EIndex(x, i): EIndex(f(x), f(i));
			case EUnop(op, x): EUnop(op, f(x));
			case EBinop(op, a, b): EBinop(op, f(a), f(b));
			case ECond(c, a, b): ECond(f(c), f(a), f(b));
			case ENew(args): ENew([for (a in args) f(a)]);
			case EBuiltin(name, args): EBuiltin(name, [for (a in args) f(a)]);
			case ECall(g, args): ECall(g, [for (a in args) f(a)]);
			case EConvert(x): EConvert(f(x));
			case EFloat(_) | EInt(_) | EBool(_) | ELocal(_): d;
		}

	static function children(e:SExpr, f:SExpr->Void)
		rebuild(e.e, x -> {
			f(x);
			x;
		});

	static function statements(ss:Array<SStmt>, ex:SExpr->Void)
		for (s in ss)
			switch s {
				case SDecl(_, x) | SReturn(x) if (x != null): ex(x);
				case SAssign(_, _, x) | SEval(x): ex(x);
				case SStore(_, i, x):
					ex(i);
					ex(x);
				case SIf(c, a, b):
					ex(c);
					statements(a, ex);
					if (b != null) statements(b, ex);
				case SWhile(c, b):
					ex(c);
					statements(b, ex);
				case _:
			}
}
