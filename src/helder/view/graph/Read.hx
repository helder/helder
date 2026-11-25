package helder.view.graph;

// A prop that reads (view's README, Signals): a constant, a signal, a memo or a
// function, each read by calling it (`props.step()`), tracked as what it
// reads is. Markup binds a prop of this type the way Solid binds props: a
// hole that may read (3.3) is given as a function of it, so the component
// reads the value when it uses it, not when it is made:
//
//   function Counter(props:{step:Read<Int>}) ...
//   <Counter step={1}/>  <Counter step={size}/>  <Counter step={a() + b()}/>
//
// A constant is a small cell, not a closure; a signal or a memo is its node.
abstract Read<T>(Reader<T>) from Reader<T> to Reader<T> {
	inline function new(r:Reader<T>)
		this = r;

	@:from static inline function ofSignal<T>(s:Signal<T>):Read<T>
		return new Read(s.node());

	@:from static inline function ofMemo<T>(m:Memo<T>):Read<T>
		return new Read(m.node());

	@:from static inline function ofThunk<T>(f:Void->T):Read<T>
		return new Read(new Thunk(f));

	@:from static inline function ofValue<T>(v:T):Read<T>
		return new Read(new Const(v));

	// (a value where a Read of a type made from it is wanted: Read<Color>'s
	// "#333333", Read<Dim>'s 320, converted as that type converts it)
	@:noCompletion @:from static macro function ofConverted(e:haxe.macro.Expr):haxe.macro.Expr {
		var inner = switch haxe.macro.Context.follow(haxe.macro.Context.getExpectedType()) {
			case TAbstract(_.get() => {name: "Read"}, [t]): haxe.macro.TypeTools.toComplexType(t);
			case _: return e;
		}
		// (a function of no arguments, a hole markup made one: each value converted)
		var fn = try switch haxe.macro.Context.follow(haxe.macro.Context.typeof(e)) {
			case TFun([], _): true;
			case _: false;
		} catch (_:Dynamic) false;
		if (fn) return macro {
			var f = $e;
			(new helder.view.graph.Read.Thunk<$inner>(() -> (f() : $inner)) : helder.view.graph.Read<$inner>);
		};
		return macro (new helder.view.graph.Read.Const<$inner>($e) : helder.view.graph.Read<$inner>);
	}

	@:op(a()) inline function get():T
		return this.read();

	// the value, not tracked
	public inline function peek():T
		return this.peek();

	// (a value given untyped, Dynamic (a component's prop: its Read already,
	// as it was given): a Read of it, a function read by calling it; once,
	// where a component takes it)
	public static function of<T>(v:Dynamic):Read<T> {
		if (Std.isOfType(v, Reader)) return new Read(v);
		if (Reflect.isFunction(v)) return new Read(new Thunk<T>(v));
		return new Read(new Const<T>(v));
	}
}

// What a Read reads: a node, a constant, a function.
interface Reader<T> {
	function read():T;
	function peek():T;
}

// A constant's cell (the runtime sets it once, binds nothing).
class Const<T> implements Reader<T> {
	public final value:T;

	public function new(v:T)
		value = v;

	public function read():T
		return value;

	public function peek():T
		return value;
}

// A function read through a Read.
class Thunk<T> implements Reader<T> {
	public final fn:Void->T;

	public function new(f:Void->T)
		fn = f;

	public function read():T
		return fn();

	public function peek():T
		return Node.untrack(fn);
}
