package helder.view.graph;

// A transaction (view's README, Holds): the change one flush makes, or an
// async answer landing, over the nodes it stages. Computations run for it
// read its staged values; a render effect that reads a value not ready
// (no armed boundary above it) blocks it, and it waits, parked, its
// stagings unseen, until nothing it renders waits; then it commits: every
// staging becomes the committed value, its effects' applies run in one
// frame. A computation that reads what another transaction staged joins
// it: the two become one (merged here, find() its survivor).
@:allow(helder.view.graph)
class Tx {
	var into:Null<Tx> = null;
	// the store whose nodes it stages (Atoms; null: the default): two stores' never merge
	var store:Null<Atoms> = null;
	var committed = false;
	// (pointed at from elsewhere: a node's pending flight or wait, a merge,
	// a park; such a one is never reused once committed)
	var shared = false;
	// the nodes it staged
	final nodes:Array<Node<Dynamic>> = [];
	// the effects run for it: their applies at its commit
	final effects:Array<Node<Dynamic>> = [];
	// the render effects waiting on a value not ready: it commits when none is left
	final blocked:Array<Node<Dynamic>> = [];
	// the frame readers (render effects, isPending, latest) served the committed
	// value of what it holds: run again at its commit
	final readers:Array<Node<Dynamic>> = [];
	// the async computations that asked in it, and those a render effect
	// waited on (upstream of what it read): it waits for their answers
	// (Solid 2's) though nothing reads them any more; one a boundary caught
	// holds nothing
	final asks:Array<Node<Dynamic>> = [];
	final awaited:Array<Node<Dynamic>> = [];

	function new() {}

	// (committed, nothing pointing at it: emptied for the next flush)
	function reset() {
		committed = false;
		store = null;
		nodes.resize(0);
		effects.resize(0);
		blocked.resize(0);
		readers.resize(0);
		asks.resize(0);
		awaited.resize(0);
	}

	function find():Tx {
		var t = this;
		while (t.into != null)
			t = t.into;
		return t;
	}

	// a and b one transaction
	static function merge(a:Tx, b:Tx):Tx {
		a = a.find();
		b = b.find();
		if (a == b) return a;
		if (a.store != b.store) throw new Owner.GraphError("two screens' transactions merged: a node of one store read another's (helder.view.graph.Atoms)");
		a.shared = true;
		b.shared = true;
		b.into = a;
		for (n in b.nodes)
			a.nodes.push(n);
		for (n in b.effects)
			if (!a.effects.contains(n)) a.effects.push(n);
		for (n in b.blocked)
			if (!a.blocked.contains(n)) a.blocked.push(n);
		for (n in b.readers)
			if (!a.readers.contains(n)) a.readers.push(n);
		for (n in b.asks)
			if (!a.asks.contains(n)) a.asks.push(n);
		for (n in b.awaited)
			if (!a.awaited.contains(n)) a.awaited.push(n);
		Scheduler.merged(a, b);
		return a;
	}

	// (it, now pointed at by a node's pending flight)
	inline function held():Tx {
		shared = true;
		return this;
	}

	function block(n:Node<Dynamic>) {
		shared = true;
		if (!blocked.contains(n)) blocked.push(n);
	}

	function unblock(n:Node<Dynamic>)
		blocked.remove(n);

	// (a render effect blocked on n, pending in it: the asks upstream of n awaited)
	function awaits(n:Null<Node<Dynamic>>) {
		if (n == null || awaited.contains(n)) return;
		if (asks.contains(n)) {
			awaited.push(n);
			return;
		}
		if (n.sources != null) for (s in n.sources)
			if (s.pendingIn != null && s.pendingIn.find() == this) awaits(s);
	}

	// (an answer a render effect waited on still to come)
	function waiting():Bool {
		for (n in awaited)
			if (!n.disposed && n.pendingIn != null && n.pendingIn.find() == this) return true;
		return false;
	}
}
