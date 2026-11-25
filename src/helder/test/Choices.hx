package helder.test;

// A property's test case as the choices it made (Hypothesis' choice
// sequence): each draw reads one or more ints, each in 0...=bound, made at
// random when generating and read back when replaying a sequence. Shrinking
// edits the sequence (Property), so 0 is each choice's simplest value and
// the generators (Gen) map it to theirs: an int's 0 or its bound nearest
// to it, an array's end, a pick's first item.
class Choices {
	// the most choices a case makes: past it the case is overran (a
	// recursion's bound in the last resort)
	public static inline var MAX = 8192;

	// (choices read back, then made at random if random is set, else overran)
	final prefix:Array<Int>;
	final random:Bool;
	var state:Int;
	@:allow(helder.test) final values:Array<Int> = [];
	// (each draw's start and end in values, for shrinking to delete)
	@:allow(helder.test) final spans:Array<Int> = [];
	@:allow(helder.test) final notes:Array<String> = [];
	// (the values drawn at the top, a stateful step's arguments)
	@:allow(helder.test) final drawn:Array<Dynamic> = [];
	var depth = 0;

	@:allow(helder.test) function new(prefix:Array<Int>, random:Bool, seed = 1) {
		this.prefix = prefix;
		this.random = random;
		state = seed == 0 ? 0x2545F491 : seed;
	}

	// a value of g (a Gen), drawn from these choices
	public function draw<T>(g:Choices->T):T {
		var start = values.length;
		depth++;
		var v = g(this);
		depth--;
		span(start);
		if (depth == 0) drawn.push(v);
		return v;
	}

	// a choice in 0...=bound, shrinking to 0 (when generating: a fifth of
	// them 0, bound or small, else uniform)
	public function choice(bound:Int):Int
		return next(bound, () -> switch below(16) {
			case 0: 0;
			case 1: bound;
			case 2 | 3 | 4: below((bound < 15 ? bound : 15) + 1);
			case _: bound == 0x7FFFFFFF ? int31() : below(bound + 1);
		});

	// true with probability p when generating (a choice of 0 or 1, false shrunk to)
	public function weighted(p:Float):Bool
		return next(1, () -> unit() < p ? 1 : 0) == 1;

	// text shown with a failing case (a stateful step's name and arguments)
	public function note(text:String)
		notes.push(text);

	// the case is left out (assume, filter): rejected, not failed
	public function reject():Dynamic
		throw Property.control = new Rejected();

	// (a choice, made by make when generating)
	@:allow(helder.test) function next(bound:Int, make:() -> Int):Int {
		if (bound <= 0) return 0;
		var i = values.length;
		if (i >= MAX) throw Property.control = new Overran();
		var v = if (i < prefix.length) {
			var p = prefix[i];
			p < 0 ? 0 : p > bound ? bound : p;
		} else if (random) make() else throw Property.control = new Overran();
		values.push(v);
		return v;
	}

	// (a choice in 0...weights.length, each made in proportion to its weight)
	@:allow(helder.test) function weightedChoice(weights:Array<Int>):Int
		return next(weights.length - 1, () -> {
			var total = 0, i = 0;
			for (w in weights) total += w;
			var r = below(total);
			while (r >= weights[i]) r -= weights[i++];
			i;
		});

	// (true with probability p when generating, false when replaying: a
	// generator's mode that changes only its probabilities, not recorded)
	@:allow(helder.test) function roll(p:Float):Bool
		return random && values.length >= prefix.length && unit() < p;

	// (a draw's span: from start to the choices made since)
	@:allow(helder.test) function span(start:Int)
		if (values.length - start > 0) {
			spans.push(start);
			spans.push(values.length);
		}

	// (xorshift32: shifts and xor only, the same on every target)
	function int31():Int {
		var x = state;
		x ^= x << 13;
		x ^= x >>> 17;
		x ^= x << 5;
		state = x;
		return x >>> 1;
	}

	function below(n:Int):Int
		return int31() % n;

	function unit():Float
		return (int31() >>> 7) / 16777216.0;
}

// thrown by assume and filter: the case is rejected
class Rejected extends haxe.Exception {
	public function new()
		super("rejected");
}

// thrown when a replayed sequence runs out (shrinking), or past Choices.MAX
class Overran extends haxe.Exception {
	public function new()
		super("overran");
}
