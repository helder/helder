package helder.gfx.shader;

import helder.gfx.shader.Ir;

// A slot object's variant, after its constants are folded (ShaderDefinition.
// variant): what it never reads of the optional fields dropped. The
// varyings' optional fields neither stage reads (their values with them),
// the locals nothing reads any more, then the vertex's optional fields
// (its attributes) and the stages' optional parameters nothing reads. So a
// variant of the combined vertex (pos, normal, uv, ?tangent, ?joints,
// ?weights, ?m0...) has the layout of the attributes it uses, in order.
class Prune {
	public static function program(vf:SFunction, ff:SFunction) {
		var vfs = reachable(vf), ffs = reachable(ff);
		var all = vfs.concat([for (f in ffs) if (!vfs.contains(f)) f]);
		ungiven(all, [vf.ret, vf.params.length > 0 ? vf.params[0].type : TVoid]);
		// (the branches folded away may have been a function's only call)
		vfs = reachable(vf);
		ffs = reachable(ff);
		all = vfs.concat([for (f in ffs) if (!vfs.contains(f)) f]);
		switch vf.ret {
			case TStruct(varyings):
				var read = fieldsRead(all, varyings);
				var drop = [for (i in 0...varyings.fields.length) if (varyings.fields[i].optional && !read.exists(varyings.fields[i].field)) i];
				if (drop.length > 0) {
					for (f in vfs)
						eachExpr(f.body, x -> switch x.e {
							case ENew(args) if (x.t.match(TStruct(_)) && sameStruct(x.t, varyings)):
								var k = drop.length;
								while (k-- > 0)
									args.splice(drop[k], 1);
							case _:
						});
					var k = drop.length;
					while (k-- > 0)
						varyings.fields.splice(drop[k], 1);
				}
			case _:
		}
		for (f in all)
			deadLocals(f);
		switch vf.params.length > 0 ? vf.params[0].type : TVoid {
			case TStruct(input):
				var read = fieldsRead(vfs, input);
				var k = input.fields.length;
				while (k-- > 0)
					if (input.fields[k].optional && !read.exists(input.fields[k].field)) input.fields.splice(k, 1);
			case _:
		}
		for (f in [vf, ff]) {
			var read = localsRead(f.body);
			var k = f.params.length;
			while (k-- > 1)
				if (f.params[k].optional && !read.exists(f.params[k])) {
					f.params.splice(k, 1);
					f.fields.splice(k - 1, 1);
				}
		}
	}

	// The optional fields of a struct of values (not the vertex's, not the
	// varyings', handled above: a struct the functions build) that the
	// variant never gives (every value of them built zero: left out, or the
	// same field of a value of the struct copied) read as their zero, the
	// tests on them folded (an if, a ?: and the comparisons of constants), the
	// fields dropped. So a stage that fills a field only under an option
	// (helder.scene's pbr: a glTF extension's layer of its LitSurface) has,
	// without it, neither the field nor the code that reads it.
	static function ungiven(fs:Array<SFunction>, skip:Array<SType>) {
		var structs:Array<SStruct> = [];
		for (f in fs)
			eachExpr(f.body, x -> switch [x.e, x.t] {
				case [ENew(_), TStruct(s)] if (!structs.contains(s) && Lambda.exists(s.fields, g -> g.optional == true) && !Lambda.exists(skip, t -> sameStruct(t, s))):
					structs.push(s);
				case _:
			});
		var changed = false;
		for (s in structs) {
			var never = [for (g in s.fields) g.optional == true];
			for (f in fs)
				eachExpr(f.body, x -> switch [x.e, x.t] {
					case [ENew(args), TStruct(t)] if (t == s):
						for (i in 0...args.length)
							if (never[i] && !zeroOf(args[i]) && !copied(args[i], s, s.fields[i].name)) never[i] = false;
					case _:
				});
			for (i in 0...never.length)
				if (never[i]) {
					var name = s.fields[i].name, type = s.fields[i].type;
					for (f in fs)
						eachExpr(f.body, x -> switch x.e {
							case EField(o, n) if (n == name && sameStruct(o.t, s)):
								x.e = Names.zero(type).e;
								changed = true;
							case _:
						});
				}
			var k = never.length;
			while (k-- > 0)
				if (never[k]) {
					for (f in fs)
						eachExpr(f.body, x -> switch [x.e, x.t] {
							case [ENew(args), TStruct(t)] if (t == s): args.splice(k, 1);
							case _:
						});
					s.fields.splice(k, 1);
				}
		}
		if (changed)
			for (f in fs)
				f.body = folded(f.body);
	}

	// a value built of zeros (a field left out: Names.zero's)
	static function zeroOf(x:SExpr):Bool
		return switch x.e {
			case EFloat(v): v == 0;
			case EInt(v): v == 0;
			case EBool(b): !b;
			case ENew(args): Lambda.foreach(args, zeroOf);
			case _: false;
		}

	// a value's field of the same name, of the same struct (a copy of the field)
	static function copied(x:SExpr, s:SStruct, name:String):Bool
		return switch x.e {
			case EField(o, n): n == name && sameStruct(o.t, s);
			case _: false;
		}

	// statements with their constants folded: an if or a loop on a constant
	// taken or dropped, its expressions folded from the leaves up
	static function folded(ss:Array<SStmt>):Array<SStmt> {
		var out = [];
		for (st in ss)
			switch st {
				case SDecl(v, init): out.push(SDecl(v, init == null ? null : fold(init)));
				case SAssign(v, op, x): out.push(SAssign(v, op, fold(x)));
				case SEval(x): out.push(SEval(fold(x)));
				case SReturn(x): out.push(SReturn(x == null ? null : fold(x)));
				case SStore(b, i, v): out.push(SStore(fold(b), fold(i), fold(v)));
				case SIf(c, a, b):
					var cf = fold(c);
					switch cf.e {
						case EBool(true): for (x in folded(a)) out.push(x);
						case EBool(false): if (b != null) for (x in folded(b)) out.push(x);
						case _: out.push(SIf(cf, folded(a), b == null ? null : folded(b)));
					}
				case SWhile(c, body):
					var cf = fold(c);
					if (!cf.e.match(EBool(false))) out.push(SWhile(cf, folded(body)));
				case SBreak | SContinue: out.push(st);
			}
		return out;
	}

	static function fold(x:SExpr):SExpr {
		var e = switch x.e {
			case EField(a, n): EField(fold(a), n);
			case ESwizzle(a, c): ESwizzle(fold(a), c);
			case EColumn(a, i): EColumn(fold(a), i);
			case EUnop(op, a): EUnop(op, fold(a));
			case EConvert(a): EConvert(fold(a));
			case EIndex(a, i): EIndex(fold(a), fold(i));
			case EBinop(op, a, b): EBinop(op, fold(a), fold(b));
			case ECond(c, a, b): ECond(fold(c), fold(a), fold(b));
			case ENew(args): ENew([for (a in args) fold(a)]);
			case EBuiltin(n, args): EBuiltin(n, [for (a in args) fold(a)]);
			case ECall(f, args): ECall(f, [for (a in args) fold(a)]);
			case v: v;
		}
		var y:SExpr = {e: e, t: x.t};
		return switch e {
			case ECond({e: EBool(c)}, a, b): c ? a : b;
			// (a component of a vector of one constant: zero's)
			case ESwizzle({e: ENew([{e: EFloat(v)}])}, comps) if (comps.length == 1): {e: EFloat(v), t: x.t};
			case ESwizzle({e: ENew([{e: EFloat(v)}])}, _): {e: ENew([{e: EFloat(v), t: TFloat}]), t: x.t};
			case _: Fold.expr(y);
		}
	}

	static function sameStruct(t:SType, s:SStruct):Bool
		return switch t {
			case TStruct(x): x == s;
			case _: false;
		}

	// a function and those it calls
	static function reachable(f:SFunction):Array<SFunction> {
		var out = [];
		function visit(g:SFunction) {
			if (out.contains(g)) return;
			out.push(g);
			eachExpr(g.body, x -> switch x.e {
				case ECall(h, _): visit(h);
				case _:
			});
		}
		visit(f);
		return out;
	}

	// the fields of a struct read anywhere in these functions (a value of it read whole: all of them)
	static function fieldsRead(fs:Array<SFunction>, s:SStruct):Map<String, Bool> {
		var read = new Map<String, Bool>();
		for (f in fs)
			eachExpr(f.body, x -> switch x.e {
				case EField(o, name) if (sameStruct(o.t, s)):
					for (g in s.fields)
						if (g.name == name) read.set(g.field, true);
				case _:
			});
		return read;
	}

	// the locals nothing reads, their declarations and assignments dropped (until none is left)
	static function deadLocals(f:SFunction) {
		while (true) {
			var read = localsRead(f.body);
			var changed = false;
			function keep(ss:Array<SStmt>):Array<SStmt> {
				var out = [];
				for (s in ss)
					switch s {
						case SDecl(v, _) | SAssign(v, _, _) if (!read.exists(v) && !f.params.contains(v)):
							changed = true;
						case SIf(c, a, b): out.push(SIf(c, keep(a), b == null ? null : keep(b)));
						case SWhile(c, body): out.push(SWhile(c, keep(body)));
						case _: out.push(s);
					}
				return out;
			}
			f.body = keep(f.body);
			if (!changed) return;
		}
	}

	static function localsRead(ss:Array<SStmt>):Map<SVar, Bool> {
		var read = new Map<SVar, Bool>();
		eachExpr(ss, x -> switch x.e {
			case ELocal(v): read.set(v, true);
			case _:
		});
		return read;
	}

	// each expression of statements, outermost first
	public static function eachExpr(ss:Array<SStmt>, f:SExpr->Void) {
		function e(x:SExpr) {
			f(x);
			switch x.e {
				case EField(a, _) | ESwizzle(a, _) | EColumn(a, _) | EUnop(_, a) | EConvert(a): e(a);
				case EIndex(a, i):
					e(a);
					e(i);
				case EBinop(_, a, b):
					e(a);
					e(b);
				case ECond(c, a, b):
					e(c);
					e(a);
					e(b);
				case ENew(args) | EBuiltin(_, args) | ECall(_, args):
					for (a in args)
						e(a);
				case EFloat(_) | EInt(_) | EBool(_) | ELocal(_):
			}
		}
		function s(st:SStmt)
			switch st {
				case SDecl(_, init): if (init != null) e(init);
				case SAssign(_, _, x) | SEval(x): e(x);
				case SIf(c, a, b):
					e(c);
					for (x in a)
						s(x);
					if (b != null) for (x in b)
						s(x);
				case SWhile(c, body):
					e(c);
					for (x in body)
						s(x);
				case SReturn(x): if (x != null) e(x);
				case SStore(b, i, v):
					e(b);
					e(i);
					e(v);
				case SBreak | SContinue:
			}
		for (st in ss)
			s(st);
	}
}
