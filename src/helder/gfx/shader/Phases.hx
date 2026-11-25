package helder.gfx.shader;

import helder.gfx.shader.Ir;

// A compute stage's function cut at its barrier()s into phases, for the CPU
// back end (Soft), which runs each phase over the whole workgroup before
// the next: a phase is statements without a barrier, then where the
// workgroup goes on (the next phase, one of two by a condition every
// invocation shares, or the end). A barrier ends a phase; an if or a loop
// with one in it becomes phases of its branches or its body, its
// condition the choice (Uniformity: every invocation has its value). A
// loop with a barrier in it has no break or continue.
class Phases {
	public final phases:Array<Phase> = [];

	var at:Int;

	function new() {}

	// (null: a break or continue in a loop with a barrier, which this cannot cut)
	public static function cut(body:Array<SStmt>):Null<Phases> {
		var p = new Phases();
		p.at = p.make();
		if (!p.emit(body)) return null;
		p.phases[p.at].next = End;
		return p;
	}

	// whether the statements have a barrier, at any depth
	public static function barriers(ss:Array<SStmt>):Bool {
		for (s in ss)
			if (has(s)) return true;
		return false;
	}

	static function has(s:SStmt):Bool
		return switch s {
			case SEval({e: EBuiltin("barrier", _)}): true;
			case SIf(_, a, b): barriers(a) || (b != null && barriers(b));
			case SWhile(_, body): barriers(body);
			case _: false;
		}

	static function exits(ss:Array<SStmt>):Bool {
		for (s in ss)
			switch s {
				case SBreak | SContinue: return true;
				case SIf(_, a, b): if (exits(a) || (b != null && exits(b))) return true;
				case _:
			}
		return false;
	}

	function make():Int {
		phases.push({body: [], next: End});
		return phases.length - 1;
	}

	function emit(ss:Array<SStmt>):Bool {
		for (s in ss) {
			if (!has(s)) {
				phases[at].body.push(s);
				continue;
			}
			switch s {
				case SIf(c, a, b):
					var then = make(), other = b == null ? -1 : make(), join = make();
					phases[at].next = Branch(c, then, other < 0 ? join : other);
					at = then;
					if (!emit(a)) return false;
					phases[at].next = Next(join);
					if (b != null) {
						at = other;
						if (!emit(b)) return false;
						phases[at].next = Next(join);
					}
					at = join;
				case SWhile(c, body):
					if (exits(body)) return false;
					var head = make(), inner = make(), exit = make();
					phases[at].next = Next(head);
					phases[head].next = Branch(c, inner, exit);
					at = inner;
					if (!emit(body)) return false;
					phases[at].next = Next(head);
					at = exit;
				case _:
					var next = make();
					phases[at].next = Next(next);
					at = next;
			}
		}
		return true;
	}
}

typedef Phase = {
	body:Array<SStmt>,
	next:PhaseNext
}

enum PhaseNext {
	Next(phase:Int);
	// (c: a value every invocation of the workgroup shares)
	Branch(c:SExpr, then:Int, other:Int);
	End;
}
