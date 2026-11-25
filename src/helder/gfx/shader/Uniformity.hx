package helder.gfx.shader;

import helder.gfx.shader.Ir;

// Where a compute stage's barrier() and subgroup operations may be: where
// every invocation of the workgroup reaches them together (WGSL's uniform
// control flow, which the other languages want as well, and which keeps
// the emulated subgroups' barriers legal), in the compute function itself:
// not under an if or a loop whose condition differs between invocations,
// nor after a return, break or continue under one (the rest of the
// function, or of the loop, then runs on some of them), nor in a loop's
// condition. What differs between invocations: ComputeInput's fields (one
// struct, as WGSL counts it), RWStorage and Workgroup reads, atomics,
// subgroup results, and the locals assigned any of those or where the
// flow differs; what does not: constants, uniform blocks, Storage read at
// an index that does not, textures. A subgroupBroadcast's lane is a
// constant of 0 to 3 (WGSL and GLSL want a constant; 4 lanes a subgroup
// at least, emulated and on the CPU).
class Uniformity {
	final varying = new Map<SVar, Bool>();
	var changed = false;
	var report = false;
	var found:Null<{e:SExpr, message:String}> = null;
	// (the exits taken where the flow differs: a loop's body that takes one diverges)
	var exits = 0;

	function new() {}

	// the first call misplaced in the stage's function, and why (null: none)
	public static function check(f:SFunction):Null<{e:SExpr, message:String}> {
		var u = new Uniformity();
		u.varying.set(f.params[0], true);
		do {
			u.changed = false;
			u.walk(f.body, true);
		} while (u.changed);
		u.report = true;
		u.walk(f.body, true);
		return u.found;
	}

	// the first call of barrier() or a subgroup operation in a function (null: none)
	public static function find(f:SFunction):Null<SExpr> {
		var found:Null<SExpr> = null;
		function first(e:SExpr)
			if (found == null) found = e;
		function stmts(ss:Array<SStmt>)
			for (s in ss)
				switch s {
					case SDecl(_, x) | SReturn(x) if (x != null): calls(x, first);
					case SAssign(_, _, x) | SEval(x): calls(x, first);
					case SStore(_, i, x):
						calls(i, first);
						calls(x, first);
					case SIf(c, a, b):
						calls(c, first);
						stmts(a);
						if (b != null) stmts(b);
					case SWhile(c, b):
						calls(c, first);
						stmts(b);
					case _:
				}
		stmts(f.body);
		return found;
	}

	public static function isCall(name:String):Bool
		return name == "barrier" || Subgroups.isOp(name);

	// each call of barrier() or a subgroup operation in e
	static function calls(e:SExpr, f:SExpr->Void)
		switch e.e {
			case EBuiltin(name, args):
				for (a in args)
					calls(a, f);
				if (isCall(name)) f(e);
			case EField(x, _) | ESwizzle(x, _) | EColumn(x, _) | EUnop(_, x) | EConvert(x): calls(x, f);
			case EIndex(x, i):
				calls(x, f);
				calls(i, f);
			case EBinop(_, a, b):
				calls(a, f);
				calls(b, f);
			case ECond(c, a, b):
				calls(c, f);
				calls(a, f);
				calls(b, f);
			case ENew(args) | ECall(_, args): for (a in args) calls(a, f);
			case EFloat(_) | EInt(_) | EBool(_) | ELocal(_):
		}

	function mark(v:SVar)
		if (!varying.exists(v)) {
			varying.set(v, true);
			changed = true;
		}

	function offend(e:SExpr, message:String)
		if (report && found == null) found = {e: e, message: message};

	// whether every invocation has e's value
	function uni(e:SExpr):Bool
		return switch e.e {
			case EFloat(_) | EInt(_) | EBool(_): true;
			case ELocal(v): !varying.exists(v);
			case EField(x, _) | ESwizzle(x, _) | EColumn(x, _) | EUnop(_, x) | EConvert(x): uni(x);
			case EIndex(x, i):
				switch x.t {
					case TStorage(_, true) | TWorkgroup(_): false;
					case _: uni(x) && uni(i);
				}
			case EBinop(_, a, b): uni(a) && uni(b);
			case ECond(c, a, b): uni(c) && uni(a) && uni(b);
			case ENew(args) | ECall(_, args): Lambda.foreach(args, uni);
			case EBuiltin(name, args): !Subgroups.isOp(name) && !StringTools.startsWith(name, "atomic") && Lambda.foreach(args, uni);
		}

	// e's calls where the flow is (true: every invocation's)
	function visit(e:SExpr, flow:Bool)
		switch e.e {
			case EBuiltin(name, args):
				for (a in args)
					visit(a, flow);
				if (!isCall(name)) return;
				if (!flow)
					offend(e, '$name(): not every invocation of the workgroup reaches it here (under an if or a loop on values that differ between invocations, or after a return under one): it needs uniform control flow, as WGSL does');
				if (name == "subgroupBroadcast") switch args[1].e {
					case EInt(k) if (k >= 0 && k < Subgroups.EMULATED):
					case _: offend(e, 'subgroupBroadcast(x, lane): lane is a constant of 0 to 3 (subgroups have 4 lanes at least; use subgroupShuffle for one that varies)');
				}
			case ECond(c, a, b):
				visit(c, flow);
				visit(a, flow && uni(c));
				visit(b, flow && uni(c));
			case EBinop(And | Or, a, b):
				visit(a, flow);
				visit(b, flow && uni(a));
			case EBinop(_, a, b):
				visit(a, flow);
				visit(b, flow);
			case EField(x, _) | ESwizzle(x, _) | EColumn(x, _) | EUnop(_, x) | EConvert(x): visit(x, flow);
			case EIndex(x, i):
				visit(x, flow);
				visit(i, flow);
			case ENew(args) | ECall(_, args): for (a in args) visit(a, flow);
			case EFloat(_) | EInt(_) | EBool(_) | ELocal(_):
		}

	// the flow after the statements, from the flow before them
	function walk(ss:Array<SStmt>, flow:Bool):Bool {
		for (s in ss)
			switch s {
				case SDecl(v, init):
					if (init != null) visit(init, flow);
					if (!flow || (init != null && !uni(init))) mark(v);
				case SAssign(v, _, x):
					visit(x, flow);
					if (!flow || !uni(x)) mark(v);
				case SEval(x):
					visit(x, flow);
				case SStore(_, i, x):
					visit(i, flow);
					visit(x, flow);
				case SReturn(x):
					if (x != null) visit(x, flow);
					if (!flow) exits++;
				case SBreak | SContinue:
					if (!flow) exits++;
				case SIf(c, a, b):
					visit(c, flow);
					var inner = flow && uni(c);
					var fa = walk(a, inner), fb = b == null ? inner : walk(b, inner);
					// (on values that differ: the flow joins again after it, unless a branch left there)
					flow = inner ? fa && fb : flow && !leaves(a) && (b == null || !leaves(b));
				case SWhile(c, body):
					calls(c, e -> offend(e, '${switch e.e {
						case EBuiltin(n, _): n;
						case _: "";
					}}(): not in a loop\'s condition (not every invocation evaluates it as often): put it before the loop, and at the end of its body'));
					if (Phases.barriers(body) && leavesLoop(body))
						calls(barrierOf(body), e -> offend(e, 'barrier(): in a loop with no break or continue (the CPU back end cuts the loop at its barriers)'));
					var inner = flow && uni(c), before = exits;
					if (inner && (!walk(body, true) || exits > before)) inner = false;
					if (!inner) walk(body, false);
					flow = inner;
			}
		return flow;
	}

	// whether the statements break or continue the loop they are in
	static function leavesLoop(ss:Array<SStmt>):Bool {
		for (s in ss)
			switch s {
				case SBreak | SContinue: return true;
				case SIf(_, a, b): if (leavesLoop(a) || (b != null && leavesLoop(b))) return true;
				case _:
			}
		return false;
	}

	// (the loop's first barrier, where the error points)
	static function barrierOf(ss:Array<SStmt>):SExpr {
		for (s in ss)
			switch s {
				case SEval(e = {e: EBuiltin("barrier", _)}): return e;
				case SIf(_, a, b):
					if (Phases.barriers(a)) return barrierOf(a);
					if (b != null && Phases.barriers(b)) return barrierOf(b);
				case SWhile(_, body) if (Phases.barriers(body)): return barrierOf(body);
				case _:
			}
		throw "barrier";
	}

	// whether the statements leave where they are (a return, or a break or continue of a loop around them)
	static function leaves(ss:Array<SStmt>):Bool {
		for (s in ss)
			switch s {
				case SReturn(_) | SBreak | SContinue: return true;
				case SIf(_, a, b): if (leaves(a) || (b != null && leaves(b))) return true;
				case SWhile(_, body): if (returns(body)) return true;
				case _:
			}
		return false;
	}

	static function returns(ss:Array<SStmt>):Bool {
		for (s in ss)
			switch s {
				case SReturn(_): return true;
				case SIf(_, a, b): if (returns(a) || (b != null && returns(b))) return true;
				case SWhile(_, body): if (returns(body)) return true;
				case _:
			}
		return false;
	}
}
