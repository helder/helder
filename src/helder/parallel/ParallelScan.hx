package helder.parallel;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.Tools;

// A body's typed tree read before it is lowered: what it captures (the
// locals, fields of this and statics it reads from around it: read at the
// call) and how it reaches each Items, checked by the body's rules, each
// error at its expression:
//
// - a capture is read, never assigned (a body runs on many items at once);
// - the index is not assigned;
// - an Items is indexed (items[i], items[i] = v) or its length read, not
//   passed on;
// - an Items is written at the item's own index only (the index, or a
//   local copy of it never assigned), and one it writes is not read at
//   another index: the items are then independent, and the order and the
//   threads change nothing.
//
// A kernel's Items are its parameter's fields (p.from); its captures may
// be statics only (its run is elsewhere).
class ParallelScan {
	public final captures:Array<Capture> = [];

	final byKey = new Map<String, Capture>();
	final what:String;
	final index:TVar;
	final params:Null<TVar>;
	final inner = new Map<Int, Bool>();
	final copies = new Map<Int, Bool>();
	final assigned = new Map<Int, Bool>();
	final aliases = new Map<Int, Capture>();
	final reads:Array<{c:Capture, pos:Position}> = [];
	final names = new Map<String, Bool>();

	// (params: a kernel's object of parameters)
	public function new(what:String, tf:TFunc, params:Null<TVar>) {
		this.what = what;
		index = tf.args[0].v;
		this.params = params;
		inner.set(index.id, true);
		if (params != null) inner.set(params.id, true);
		assignments(tf.expr);
		walk(tf.expr);
		for (r in reads)
			if (r.c.written)
				error('${r.c.display} is written by the body (${r.c.display}[${index.name}] = ...), and so read at the item\'s own index only (${r.c.display}[${index.name}]): a body\'s items are independent', r.pos);
	}

	function error(message:String, pos:Position):Dynamic
		return Context.error('$what: $message', pos);

	// a value's key as a capture: a local, a field of this, a static
	// variable (Math's constants left to the shader compiler), a field of a
	// kernel's parameters; else null
	public static function key(e:TypedExpr, params = -1):Null<String>
		return switch e.expr {
			case TParenthesis(x) | TMeta(_, x) | TCast(x, null): key(x, params);
			case TLocal(v): "local:" + v.id;
			case TField({expr: TConst(TThis)}, FInstance(_, _, cf)): "this:" + cf.get().name;
			case TField(_, FStatic(c, cf)):
				var cf = cf.get(), c = c.get();
				switch cf.kind {
					case FVar(_, AccInline): null;
					case FVar(_, _) if (c.pack.length == 0 && c.name == "Math"): null;
					case FVar(_, _): "static:" + c.pack.concat([c.name, cf.name]).join(".");
					case _: null;
				}
			case TField({expr: TLocal(v)}, FAnon(cf)) if (v.id == params): "param:" + cf.get().name;
			case _: null;
		}

	static function strip(e:TypedExpr):TypedExpr
		return switch e.expr {
			case TParenthesis(x) | TMeta(_, x) | TCast(x, null): strip(x);
			case _: e;
		}

	// (the locals assigned anywhere, before the walk: a copy of the index is one when never assigned)
	function assignments(e:TypedExpr) {
		switch e.expr {
			case TBinop(OpAssign | OpAssignOp(_), l, _) | TUnop(OpIncrement | OpDecrement, _, l):
				switch strip(l).expr {
					case TLocal(v):
						if (v.id == index.id) error('${index.name} is the item\'s index: a body does not assign it', e.pos);
						assigned.set(v.id, true);
					case _:
				}
			case _:
		}
		e.iter(assignments);
	}

	function own(e:TypedExpr):Bool
		return switch strip(e).expr {
			case TLocal(v): (v.id == index.id || copies.exists(v.id)) && !assigned.exists(v.id);
			case _: false;
		}

	static function isItemsImpl(c:ClassType):Bool
		return switch c.kind {
			case KAbstractImpl(a): a.get().meta.has(":parallel.items");
			case _: false;
		}

	// a capture (or a kernel's field) of e, made when first read
	function capture(e:TypedExpr):Null<Capture> {
		var k = key(e, params == null ? -1 : params.id);
		if (k == null) return null;
		var c = byKey.get(k);
		if (c != null) return c;
		var s = strip(e);
		var name:String, kernel = false;
		switch s.expr {
			case TLocal(v):
				if (inner.exists(v.id)) return null;
				if (params != null) error('${v.name} is a local: a kernel reads its parameters (${params.name}.x) and statics', e.pos);
				name = v.name;
			case TField({expr: TConst(TThis)}, FInstance(_, _, cf)):
				if (params != null) error('this.${cf.get().name}: a kernel reads its parameters (${params.name}.x) and statics', e.pos);
				name = cf.get().name;
			case TField({expr: TLocal(v)}, FAnon(cf)):
				if (params == null || v.id != params.id) return null;
				name = cf.get().name;
				kernel = true;
			case TField(_, FStatic(_, cf)):
				name = cf.get().name;
			case _:
				return null;
		}
		var unique = name, n = 1;
		while (names.exists(unique))
			unique = name + "_" + ++n;
		names.set(unique, true);
		c = {
			key: k,
			name: unique,
			display: name,
			expr: s,
			type: s.t,
			pos: e.pos,
			element: ParallelLower.itemsElement(s.t),
			written: false,
			own: false,
			length: false,
			kernel: kernel
		};
		byKey.set(k, c);
		captures.push(c);
		return c;
	}

	// (the Items an expression is: a captured one, a kernel's field, a local copy)
	function items(e:TypedExpr):Null<Capture> {
		switch strip(e).expr {
			case TLocal(v) if (aliases.exists(v.id)): return aliases.get(v.id);
			case _:
		}
		var c = capture(e);
		return c != null && c.element != null ? c : null;
	}

	function target(l:TypedExpr) {
		var c = capture(l);
		if (c != null && !c.kernel) error('${c.display} is captured: a body reads what it captures, and assigns its own locals and Items\' elements only', l.pos);
		if (c != null) error('${c.display} is a parameter: a body assigns its own locals and Items\' elements only', l.pos);
	}

	function walk(e:TypedExpr) {
		switch e.expr {
			case TVar(v, init):
				inner.set(v.id, true);
				if (init == null) return;
				if (ParallelLower.itemsElement(v.t) != null) {
					var c = items(init);
					if (c == null) error('${v.name}: an Items in a body is a captured one${params == null ? "" : " or a parameter"}', init.pos);
					aliases.set(v.id, c);
					return;
				}
				if (own(init)) copies.set(v.id, true);
				walk(init);
			case TFor(v, it, body):
				inner.set(v.id, true);
				walk(it);
				walk(body);
			case TFunction(f):
				for (a in f.args)
					inner.set(a.v.id, true);
				walk(f.expr);
			case TBinop(OpAssign | OpAssignOp(_), l, r):
				target(l);
				walk(l);
				walk(r);
			case TUnop(OpIncrement | OpDecrement, _, x):
				target(x);
				walk(x);
			case TCall({expr: TField(_, FStatic(c, cf))}, args) if (isItemsImpl(c.get())):
				var name = cf.get().name;
				var t = items(args[0]);
				if (t == null) error('an Items in a body is a captured one${params == null ? "" : " or a parameter"}, indexed (items[i])', args[0].pos);
				switch name {
					case "get":
						if (own(args[1])) t.own = true else reads.push({c: t, pos: e.pos});
						walk(args[1]);
					case "set" | "setFields":
						if (!own(args[1]))
							error('${t.display}[...] = ...: a body writes at the item\'s own index only (${t.display}[${index.name}] = ...)', e.pos);
						t.own = true;
						t.written = true;
						walk(args[2]);
					case "get_length":
						t.length = true;
					case _:
						error('${t.display}.$name: an Items in a body is indexed (items[i], items[i] = v) or its length read', e.pos);
				}
			case _:
				var c = capture(e);
				if (c != null) {
					if (c.element != null) error('${c.display}: an Items in a body is indexed (${c.display}[${index.name}]) or its length read, not passed on', e.pos);
					return;
				}
				switch e.expr {
					case TLocal(v) if (aliases.exists(v.id)):
						error('${v.name}: an Items in a body is indexed (${v.name}[${index.name}]) or its length read, not passed on', e.pos);
					case _:
				}
				e.iter(walk);
		}
	}
}

typedef Capture = {
	key:String,
	// (its parameter's name, unique; display: as written)
	name:String,
	display:String,
	expr:TypedExpr,
	type:Type,
	pos:Position,
	// an Items' element type, else null
	element:Null<Type>,
	written:Bool,
	// indexed at the item's own index somewhere (its length checked against n)
	own:Bool,
	length:Bool,
	// a kernel's parameter (p.x): not captured, passed
	kernel:Bool
}
#end
