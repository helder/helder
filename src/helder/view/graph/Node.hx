package helder.view.graph;

import helder.view.graph.Awaitable.NotReady;
import helder.view.graph.Owner.GraphError;
import helder.async.Errors;

// A node of the graph: a signal (a value), a computed (a memo, or a
// derived signal, which can also be written) or an effect.
//
// Writes are deferred (Scheduler): a written node keeps the new value
// pending until the flush, which stages it in a transaction (Tx); a node
// keeps its committed value (the screen's) and, while a transaction holds
// it, a staged one. A computation run for a transaction reads its staged
// values and so joins it (reading another's joins both); one that reads
// none of it commits at once. Reading inside a computation makes the node
// its source; a staging marks the observers (Reactively's colouring: a
// direct observer dirty, those further down to check), effects and owned
// memos queued, an unowned memo recomputed when read.
//
// A computed that returns an Awaitable is pending until it answers, in
// the transaction that asked; reading it there stops the reader
// (NotReady): a memo is pending in turn, a render effect blocks the
// transaction (or an armed loading boundary above it catches it), a user
// effect waits. The answer lands into that transaction (Scheduler).
@:allow(helder.view.graph)
class Node<T> extends Owner implements Read.Reader<T> {
	static inline var SIGNAL = 0;
	static inline var COMPUTED = 1;
	static inline var EFFECT = 2;
	static inline var RENDER = 3;

	static inline var CLEAN = 0;
	static inline var CHECK = 1;
	static inline var DIRTY = 2;

	static inline var PROBE_NONE = 0;
	static inline var PROBE_PENDING = 1;
	static inline var PROBE_LATEST = 2;

	// the computation whose reads are tracked now (null: none)
	static var observer:Null<Node<Dynamic>> = null;
	// the computation running now, tracked or not (its reads join transactions)
	static var runner:Null<Node<Dynamic>> = null;
	// (isPending, latest: reads that look ahead, and whether one saw a value on its way)
	static var probe = PROBE_NONE;
	static var probeHit = false;
	// (each run's number: a source read twice in a run is tracked once)
	static var runs = 0;
	// (the transaction a NotReady thrown came from, and the node not ready)
	static var notReadyIn:Null<Tx> = null;
	static var notReadyNode:Null<Node<Dynamic>> = null;

	final kind:Int;
	// the committed value (the screen's), and the staged one while a transaction holds it
	var value:T;
	var staged:Null<T> = null;
	var stagedIn:Null<Tx> = null;
	// (a write waiting for the flush)
	var pendingValue:Null<T> = null;
	var hasPending = false;
	// (a computed: no committed value yet; its async in flight, for that transaction)
	var uninit = false;
	var pendingIn:Null<Tx> = null;
	var awaiting:Null<Awaitable<Dynamic>> = null;
	var asked = 0;
	var answer:Dynamic = null;
	var answerFailed = false;
	final fn:Null<Null<T>->Dynamic>;
	final equals:Null<(T, T) -> Bool>;
	final unobserved:Null<Void->Void>;
	final ownedWrite:Bool;
	// (one node for every store: NodeOptions.shared)
	final shared:Bool;
	var state = CLEAN;
	var error:Dynamic = null;
	var hasError = false;
	var stagedError:Dynamic = null;
	// (the exception the last error came as: where it was thrown)
	var thrown:Null<haxe.Exception> = null;
	var stagedFailed = false;
	var sources:Null<Array<Node<Dynamic>>> = null;
	// (one more than its highest source's, a signal's 0: a queue runs the lower
	// first among those of one owner depth, Solid 2's heap)
	@:allow(helder.view.graph) var height = 0;
	var observers:Null<Array<Node<Dynamic>>> = null;
	// (a run's tracking: the old sources read again in order, then the new ones)
	var run = 0;
	var kept = 0;
	// (the node its last run stopped at, not ready: an equal answer of it still runs it again)
	var stalledOn:Null<Node<Dynamic>> = null;
	// (its function running, its sources reconciled after: the run's to settle, not let go under it)
	var computing = false;
	var added:Null<Array<Node<Dynamic>>> = null;
	var trackedBy:Null<Node<Dynamic>> = null;
	var trackedIn = -1;
	// (its run's world: the transaction it runs for, null the screen; and
	// whether it read what that transaction staged)
	var world:Null<Tx> = null;
	var joined = false;
	// (it has read a verdict: a render effect that has is a verdict reader,
	// served the screen; kept across runs, a run's reads not always in the same order)
	var verdictRun = false;
	// (an effect's: its second half, its last applied value, its cleanup,
	// its error handler, whether it waits in a queue or for its apply)
	var apply:Null<(T, Null<T>) -> Null<Void->Void>> = null;
	var applied:Null<T> = null;
	var applyCleanup:Null<Void->Void> = null;
	var onFailure:Null<Dynamic->Void> = null;
	var queued = false;
	var toApply = false;
	// (a render effect waiting on a value not ready: the transaction it blocks, or the boundary that caught it)
	var blockedIn:Null<Tx> = null;
	var caughtBy:Null<Boundary> = null;
	// (an unowned memo nothing observes: the commit it was last computed after)
	var tick = -1;
	// (a derived signal: its written value kept until a source changes)
	var writable = false;
	// (a boundary's output: it decides what a pending read under it does, so it runs again)
	var catcher = false;
	// (a computed's frame on screen: its last committed run's children and
	// cleanups, kept while a replacement is in flight, disposed when one
	// lands (a value or an error); and whether its current run is that frame)
	var retired:Null<Owner> = null;
	var shown = false;
	// its home: the store it was made in (Atoms; null: the default), what a
	// computation runs in; its initial value, another store's node of it made
	// from it (or from its function) and kept by that store; what each is given
	// when made (fast refresh)
	final home:Null<Atoms>;
	final init:Null<T>;
	// (made with no owner: a memo then computes when read, nothing keeps it up to
	// date; a store's node of it the same, though its store's root owns it)
	var free:Bool;
	var copied:Null<(Node<Dynamic>, Atoms) -> Void> = null;
	// (a node made with state of its own beside it, a boundary: made again by
	// this in another store, not copied)
	var remake:Null<Void->Node<Dynamic>> = null;

	function new(kind:Int, value:Null<T>, fn:Null<Null<T>->Dynamic>, options:Null<NodeOptions<T>>) {
		// (a signal belongs to no owner: only computations are disposed with theirs)
		super(kind == SIGNAL ? null : Owner.current);
		this.kind = kind;
		this.value = value;
		this.fn = fn;
		uninit = kind == COMPUTED;
		equals = options != null ? options.equals : null;
		unobserved = options != null ? options.unobserved : null;
		ownedWrite = options != null && options.ownedWrite == true;
		shared = kind == SIGNAL && options != null && options.shared == true;
		free = Owner.current == null;
		// (a shared signal the default store's, wherever it was first read)
		home = shared || Atoms.homeless && kind <= COMPUTED && Owner.current == null ? null : Atoms.current;
		init = value;
		if (home == null && (kind == EFFECT || kind == RENDER) && Atoms.record && Owner.current == null && !Atoms.screen) Atoms.effects.push(cast this);
	}

	// (its store's flushes of writes so far: another store's leave its memos alone)
	inline function ticks():Int
		return home == null ? Scheduler.ticks : home.ticks;

	// (read or written in a store not its home: that store's node of it; the
	// default store sees through to its home)
	inline function at():Node<T> {
		var s = Atoms.current;
		return s == null || s == home || shared ? this : of(s);
	}

	inline function of(s:Atoms):Node<T>
		return s.of(this);

	// (its node in store: its initial value, or its function, owned by the store's root)
	function copy(store:Atoms):Node<T> {
		var savedOwner = Owner.current, savedAtoms = Atoms.current, savedHomeless = Atoms.homeless;
		Owner.current = kind == SIGNAL ? null : store.root;
		Atoms.current = store;
		Atoms.homeless = false;
		var make = remake;
		var n:Node<T> = make != null ? cast make() : new Node(kind, init, fn, {equals: equals, unobserved: unobserved, ownedWrite: ownedWrite});
		Owner.current = savedOwner;
		Atoms.current = savedAtoms;
		Atoms.homeless = savedHomeless;
		n.writable = writable;
		n.free = free;
		return n;
	}

	public static function signal<T>(value:T, options:Null<NodeOptions<T>>):Node<T> {
		if (Reflect.isFunction(value)) throw new GraphError("a signal never holds a function: signal(fn) derives its value from fn (give its parameter a type: (prev:Null<T>) -> ...)");
		return new Node(SIGNAL, value, null, options);
	}

	// a memo (writable: a derived signal), computed now
	public static function computed<T>(fn:Compute<T>, options:Null<NodeOptions<T>>, writable:Bool):Node<T> {
		var n = new Node(COMPUTED, null, fn, options);
		n.writable = writable;
		n.recompute();
		// (a derived signal of a function: signal(() -> fn), which Haxe types as a Signal of a function type)
		if (writable && Reflect.isFunction(n.value)) throw new GraphError("a signal never holds a function: signal(() -> fn) derives a function (keep it in a structure, signal({fn: fn}))");
		return n;
	}

	// compute run now; apply at the next flush, a render effect's first now
	public static function effect<T>(compute:Compute<T>, apply:Apply<T>, error:Null<Dynamic->Void>, render:Bool) {
		var n = new Node(render ? RENDER : EFFECT, null, compute, null);
		n.apply = apply;
		n.onFailure = error;
		n.recompute();
		if (render && n.toApply) {
			Scheduler.applies.remove(n);
			n.runApply(true);
		}
	}

	public static function untrack<T>(fn:Void->T):T {
		var saved = observer;
		observer = null;
		try {
			var r = fn();
			observer = saved;
			return r;
		} catch (e:haxe.Exception) {
			observer = saved;
			throw Errors.kept(e);
		}
	}

	// fn run with o the owner and obs the observer
	static function within<T>(o:Null<Owner>, obs:Null<Node<Dynamic>>, fn:Void->T):T {
		var savedOwner = Owner.current, savedObserver = observer;
		Owner.current = o;
		observer = obs;
		try {
			var r = fn();
			Owner.current = savedOwner;
			observer = savedObserver;
			return r;
		} catch (e:haxe.Exception) {
			Owner.current = savedOwner;
			observer = savedObserver;
			throw Errors.kept(e);
		}
	}

	// fn's reads looking ahead: whether one saw a value on its way (isPending), or
	// those values (latest); a first load gives no verdict (NotReady: tracked, it
	// suspends as the read would; untracked, isPending is false)
	static function probing<R>(mode:Int, fn:Void->R):{result:Null<R>, hit:Bool, notReady:Bool, error:Dynamic, failed:Bool} {
		var savedProbe = probe, savedHit = probeHit;
		probe = mode;
		probeHit = false;
		if (runner != null) runner.verdictRun = true;
		var r:Null<R> = null, notReady = false, error:Dynamic = null, failed = false;
		try r = fn() catch (e:NotReady) notReady = true catch (e:Dynamic) {
			error = e;
			failed = true;
		}
		var hit = probeHit;
		probe = savedProbe;
		// (a hit inside a nested probe is the enclosing one's too: isPending(() -> latest(x)))
		probeHit = savedProbe != PROBE_NONE ? savedHit || hit : savedHit;
		return {result: r, hit: hit, notReady: notReady, error: error, failed: failed};
	}

	public function read():T {
		var s = Atoms.current;
		if (s != null && s != home && !shared) return of(s).read();
		// (read by its own run: a cycle, an error, not a run started again without end)
		if (computing) throw new GraphError("a computation read itself while it ran (a cycle)");
		if (kind != SIGNAL) fresh();
		if (observer != null) observer.track(this);
		return serve();
	}

	public function peek():T {
		var s = Atoms.current;
		if (s != null && s != home && !shared) return of(s).peek();
		if (kind != SIGNAL) fresh();
		return serve();
	}

	// the value a read gets (Solid 2's F-2, F-3, A29). In the world of the
	// transaction that staged it: the staging (pending: not ready). A frame
	// reader (a render effect, isPending, latest) outside it is served the
	// committed value, holds nothing for it and runs again at its commit; a
	// pass (a memo, an effect's compute, made in a flush or not) reading
	// the future derives from it: it joins that transaction (born held).
	function serve():T {
		var t = stagedIn != null ? stagedIn.find() : null;
		var p = pendingIn != null ? pendingIn.find() : null;
		// (a flight whose transaction committed without it: the transaction that
		// reads it now adopts it, and lands with it (A15: a reveal that discovers
		// a flight holds on it))
		if (p != null && p.committed && probe == PROBE_NONE && runner != null) {
			var w = runner.world != null ? runner.world.find() : Scheduler.world != null ? Scheduler.world.find() : null;
			if (w != null) pendingIn = p = w.held();
		}
		if (probe != PROBE_NONE) return probed(t, p);
		var ahead = t != null ? t : p;
		if (ahead != null) {
			var w = runner != null && runner.world != null ? runner.world.find() : null;
			if (ahead != w && runner != null && runner.kind != RENDER) {
				// (a pass joins it)
				w = runner.world = w == null ? ahead : Tx.merge(w, ahead);
				if (p != null && t != null && p != w) w = runner.world = Tx.merge(w, p);
				if (Scheduler.world != null) Scheduler.world = Scheduler.world.find();
				// (merged: one transaction now, whichever was kept as its root)
				ahead = ahead.find();
				if (p != null) p = p.find();
			}
			// (a render effect that read a verdict is a verdict reader: served the
			// screen, shown now; a pending value it reads still holds the change)
			var screen = runner != null && runner.kind == RENDER && runner.verdictRun && !uninit;
			if (screen && p != null) {
				runner.blockedIn = p;
				p.block(runner);
				p.awaits(this);
			}
			if (!screen && (ahead == w || (p != null && p == w))) {
				if (runner != null) runner.joined = true;
				if (p != null) notReady(w);
				if (stagedFailed) throwError(stagedError);
				return staged;
			}
			// (a frame reader: the screen, again at the commit)
			if (runner != null && !ahead.readers.contains(runner)) ahead.readers.push(runner);
			if (uninit) notReady(ahead);
		} else if (uninit) notReady(null);
		if (hasError) throwError(error);
		return value;
	}

	// (a read looking ahead: the staging of a transaction other than the run's
	// world, a pending answer to a new question; a hit for isPending)
	function probed(t:Null<Tx>, p:Null<Tx>):T {
		var w = runner != null && runner.world != null ? runner.world.find() : null;
		var ahead = t != null && t != w ? t : null;
		if ((ahead != null || (p != null && !uninit)) && probeHit == false) probeHit = true;
		// (the verdict of a staging of its own flush is the seam's: whether that
		// flush parks; it runs again when the flush settles, either way)
		var watch = t != null ? t : p;
		if (watch != null && runner != null && !watch.readers.contains(runner)) watch.readers.push(runner);
		if (t != null) {
			if (stagedFailed) throwError(stagedError);
			return staged;
		}
		if (uninit) notReady(p);
		if (hasError) throwError(error);
		return value;
	}

	inline function notReady(tx:Null<Tx>):Dynamic {
		notReadyIn = tx;
		notReadyNode = this;
		throw NotReady.instance;
	}

	public function write(v:T) {
		var s = Atoms.current;
		if (s != null && s != home && !shared) {
			of(s).write(v);
			return;
		}
		checkWritable();
		if (same(latest(), v)) return;
		pendingValue = v;
		if (!hasPending) {
			hasPending = true;
			Scheduler.enqueueWrite(this);
		}
	}

	// a Signal's write (s(v)): a function never written (a value of no static
	// type, Dynamic, that is one: Haxe chose the write by the type, never by
	// the value, view's README, Signals)
	public function set(v:T) {
		if (Reflect.isFunction(v))
			throw new GraphError("a signal never holds a function: a Dynamic value that is one written (an update is a function of its type, s(v -> ...), chosen by its static type)");
		write(v);
	}

	// f given the latest value written (pending, else staged, else committed)
	public function update(f:T->T)
		if (Atoms.current != null && Atoms.current != home && !shared) at().update(f) else write(f(latest()));

	inline function latest():Null<T>
		return hasPending ? pendingValue : stagedIn != null ? staged : value;

	// (a computed up to date: an unowned memo nothing observes is not kept
	// up to date by the flushes, it computes again when read after one of
	// its store's, as Solid 2 releases it)
	inline function fresh() {
		if (kind == COMPUTED && !writable && free && tick != ticks() && (observers == null || observers.length == 0)) state = DIRTY;
		if (state != CLEAN) updateIfNecessary();
	}

	function checkWritable() {
		if (ownedWrite || Owner.current == null || Owner.disposing > 0) return;
		throw new GraphError("a write inside an owned scope (a root's body, a component, a computation): write from an event or an effect's apply, or make the signal with ownedWrite");
	}

	inline function same(a:Null<T>, b:Null<T>):Bool
		return equals != null ? equals(a, b) : a == b;

	// (the flush: a pending write staged in tx; one that nets to the current value is none)
	function stageWrite(tx:Tx) {
		hasPending = false;
		var v = pendingValue;
		pendingValue = null;
		if (!uninit && same(stagedIn != null ? staged : value, v)) return;
		stage(v, tx);
		markObservers(DIRTY);
	}

	// (v staged in tx: a node another transaction holds joins it with tx)
	function stage(v:Null<T>, tx:Tx) {
		var t = stagedIn != null ? stagedIn.find() : null;
		if (t == null) {
			stagedIn = tx.find();
			stagedIn.nodes.push(this);
		} else if (t != tx.find()) {
			Scheduler.join(t);
		}
		staged = v;
		stagedFailed = false;
		stagedError = null;
	}

	function stageError(e:Dynamic, tx:Tx) {
		stage(null, tx);
		stagedFailed = true;
		stagedError = e;
	}

	// (its transaction committed: the staging is the value)
	function commitStaged() {
		if (stagedFailed) {
			error = stagedError;
			hasError = true;
		} else {
			value = staged;
			hasError = false;
			error = null;
		}
		uninit = false;
		staged = null;
		stagedIn = null;
		var failed = stagedFailed;
		stagedFailed = false;
		stagedError = null;
		replaced(!failed);
	}

	// (its current run is the frame on screen: the one it replaces disposed;
	// an errored frame is not kept for its own replacement)
	function replaced(value:Bool) {
		shown = value;
		if (retired == null) return;
		var r = retired;
		retired = null;
		try r.dispose() catch (e:haxe.Exception) Scheduler.report(e);
	}

	// (its async answered: the answer staged in the transaction that asked, its readers run again)
	function land() {
		var w = Scheduler.world;
		var v = answer;
		answer = null;
		// (a source pending again: the answer is to a question no longer asked; it waits with that source)
		if (sources != null) for (src in sources) if (src.pendingIn != null) {
			pendingIn = src.pendingIn.held();
			return;
		}
		var t = stagedIn != null ? stagedIn.find() : null;
		// (an answer equal to the value it would replace: its dependents' wait ends, nothing runs again)
		if (!answerFailed && !uninit && !(t == w ? stagedFailed : hasError) && same(t == w ? staged : value, v)) {
			clearPending(w);
			return;
		}
		if (answerFailed) stageError(v, w) else stage(v, w);
		if (observers != null) for (o in observers) o.mark(DIRTY);
	}

	// (pending in tx, as a status: its computed dependents pending in turn, not
	// run again; a render effect reading it holds tx, or an armed boundary
	// catches it; a boundary's output runs again; Solid 2's propagation)
	function propagatePending(tx:Tx) {
		if (observers == null) return;
		for (o in observers) {
			if (o.disposed) continue;
			// (a boundary's output decides; a verdict reader shows the wait: both run again)
			if (o.catcher || o.verdictRun) {
				o.mark(DIRTY);
				continue;
			}
			switch o.kind {
				case COMPUTED:
					if (o.pendingIn == null) {
						o.pendingIn = tx.held();
						o.propagatePending(tx);
					}
				case RENDER:
					if (o.blockedIn != null || o.caughtBy != null) continue;
					var b = Boundary.catching(o);
					if (b != null) {
						o.caughtBy = b;
						b.caught(o);
					} else {
						o.blockedIn = tx;
						tx.block(o);
						tx.awaits(this);
					}
				case _:
			}
		}
	}

	// (the wait on tx ended without a new value: its dependents' pending status cleared)
	function clearPending(tx:Tx) {
		if (observers == null) return;
		for (o in observers) {
			if (o.disposed) continue;
			// (one whose last run stopped at this node shows nothing yet: it runs
			// again, whichever transaction it waited in)
			if (o.stalledOn == this) {
				if (o.kind == RENDER && (o.blockedIn != null || o.caughtBy != null)) o.release();
				o.mark(DIRTY);
				continue;
			}
			if (o.catcher || o.verdictRun) {
				o.mark(DIRTY);
				continue;
			}
			switch o.kind {
				case COMPUTED:
					if (o.pendingIn != null && o.awaiting == null && o.pendingIn.find() == tx.find()) {
						o.pendingIn = null;
						o.clearPending(tx);
					}
				case RENDER:
					if (o.blockedIn != null || o.caughtBy != null) o.release();
				case _:
			}
		}
	}

	function markObservers(s:Int) {
		if (observers == null) return;
		for (o in observers)
			o.mark(s);
	}

	function mark(s:Int) {
		if (state >= s) return;
		var was = state;
		state = s;
		if (was == CLEAN) {
			// (an owned memo is eager: brought up to date by the flush, read or not)
			if (kind >= EFFECT || !free) Scheduler.enqueue(this);
			if (kind == COMPUTED) markObservers(CHECK);
		}
	}

	// up to date: recomputed if a source really changed
	function updateIfNecessary() {
		if (disposed) return;
		if (state == CHECK && sources != null) {
			for (s in sources) {
				if (s.kind == COMPUTED) s.updateIfNecessary();
				if (state == DIRTY) break;
			}
		}
		if (state == DIRTY) recompute();
		state = CLEAN;
	}

	// runs its function, tracking what it reads
	function recompute() {
		if (disposed) return;
		// (a computed's committed frame stays until its replacement lands; a run
		// that never committed is cleaned up when superseded)
		if (kind == COMPUTED && shown && retired == null && (children != null || cleanups != null)) {
			retired = new Owner(null);
			retired.children = children;
			retired.cleanups = cleanups;
			children = null;
			cleanups = null;
		} else
			try clean() catch (e:haxe.Exception) Scheduler.report(e);
		shown = false;
		tick = ticks();
		// (a superseded async run: cancelled, its answer dropped)
		asked++;
		if (awaiting != null) {
			var a = awaiting;
			awaiting = null;
			a.cancel();
		}
		pendingIn = null;
		release();
		var savedOwner = Owner.current, savedObserver = observer, savedRunner = runner, savedProbe = probe, savedAtoms = Atoms.current;
		Owner.current = this;
		Atoms.current = home;
		observer = this;
		runner = this;
		probe = PROBE_NONE;
		// (the transaction running, if it is its store's: another store's never takes it in)
		var running = Scheduler.world != null ? Scheduler.world.find() : null;
		world = running != null && running.store == home ? running : null;
		joined = false;
		run = ++runs;
		kept = 0;
		added = null;
		var r:Dynamic = null, failure:Dynamic = null, failed = false, waiting = false;
		computing = true;
		try r = call() catch (e:NotReady) waiting = true catch (e:haxe.Exception) {
			failure = e.native;
			thrown = e;
			failed = true;
		}
		Owner.current = savedOwner;
		Atoms.current = savedAtoms;
		observer = savedObserver;
		runner = savedRunner;
		probe = savedProbe;
		reconcile();
		computing = false;
		state = CLEAN;
		var w = world != null ? world.find() : null;
		var mine = w != null && joined;
		stalledOn = waiting ? notReadyNode : null;
		if (waiting) wait(notReadyIn != null ? notReadyIn.find() : null)
		else if (failed) failWith(failure, mine ? w : null)
		else if (kind == COMPUTED && Std.isOfType(r, Awaitable)) ask(r, w)
		else settle(r, mine ? w : null);
	}

	// (its function run, given the previous value; hxmc dev: in a scope of
	// its own, the same each run, fast refresh's keys: helder.view.Refresh)
	#if hxmc.dev
	var hotPath:Null<String> = null;

	function call():Dynamic {
		var arg = kind == COMPUTED ? current() : value;
		if (hotPath == null) return helder.dev.Hot.scope("$c", () -> {
			hotPath = helder.dev.Hot.path();
			fn(arg);
		});
		return helder.dev.Hot.at(hotPath, () -> fn(arg));
	}
	#else
	inline function call():Dynamic
		return fn(kind == COMPUTED ? current() : value);
	#end

	// (the value its run builds on: the world's staging, else the committed one)
	function current():Null<T> {
		var w = world != null ? world : Scheduler.world;
		if (stagedIn != null && w != null && stagedIn.find() == w.find()) return staged;
		return uninit ? null : value;
	}

	// (its run read a value not ready, in tx)
	function wait(tx:Null<Tx>) {
		switch kind {
			case COMPUTED:
				// (pending in turn: its readers wait with it)
				pendingIn = tx != null ? tx.held() : null;
				if (tx != null) propagatePending(tx);
			case RENDER:
				// (an armed boundary above catches it, else it holds the transaction)
				var b = Boundary.catching(this);
				if (b != null) {
					caughtBy = b;
					b.caught(this);
				} else if (tx != null) {
					blockedIn = tx;
					tx.block(this);
					tx.awaits(notReadyNode);
				}
			case _:
				// (a user effect holds nothing: it runs again when the value lands)
		}
	}

	// (no longer waiting: off the transaction it blocked, the boundary that caught it)
	function release() {
		if (blockedIn != null) {
			blockedIn.find().unblock(this);
			blockedIn = null;
		}
		if (caughtBy != null) {
			var b = caughtBy;
			caughtBy = null;
			b.released(this);
		}
	}

	// (async: pending in the transaction that asked, until the answer lands)
	function ask(a:Awaitable<Dynamic>, w:Null<Tx>) {
		var tx = w != null ? w : Scheduler.newTx(home);
		pendingIn = tx.held();
		if (!tx.asks.contains(this)) tx.asks.push(this);
		awaiting = a;
		var id = asked;
		propagatePending(tx);
		a.onAnswer(v -> answered(id, v, false), e -> answered(id, e, true));
	}

	function answered(id:Int, v:Dynamic, failed:Bool) {
		if (id != asked || disposed) return;
		awaiting = null;
		answer = v;
		answerFailed = failed;
		Scheduler.landing(this);
	}

	// (a value computed: staged in tx when its run joined one, else committed)
	function settle(v:Null<T>, tx:Null<Tx>) {
		if (kind == COMPUTED) {
			// (a comparator's error is the computation's)
			var changed = try uninit || hasError || stagedFailed || !same(stagedIn != null ? staged : value, v) catch (e:haxe.Exception) {
				thrown = e;
				failWith(e.native, tx);
				return;
			};
			if (!changed) return;
			if (tx != null) stage(v, tx) else {
				value = v;
				uninit = false;
				hasError = false;
				error = null;
				replaced(true);
			}
			// (its observers read it again)
			if (observers != null) for (o in observers) o.state = DIRTY;
			return;
		}
		value = v;
		if (tx != null) {
			if (!tx.effects.contains(this)) tx.effects.push(this);
		} else
			Scheduler.enqueueApply(this);
	}

	function failWith(e:Dynamic, tx:Null<Tx>) {
		if (kind == COMPUTED) {
			// (the same error again is no change)
			// (against what it has staged, else what it shows, as a value is: settle)
			if (stagedIn != null ? (stagedFailed && stagedError == e) : (hasError && error == e)) return;
			if (tx != null) stageError(e, tx) else {
				error = e;
				hasError = true;
				uninit = false;
				replaced(false);
			}
			if (observers != null) for (o in observers) o.state = DIRTY;
			// (an owned computation's error reaches the error boundary above it)
			if (parent != null) parent.handle(e);
			return;
		}
		// (an effect's compute error is delivered with its frame, in the apply phase: runApply)
		error = e;
		hasError = true;
		if (tx != null) {
			if (!tx.effects.contains(this)) tx.effects.push(this);
		} else
			Scheduler.enqueueApply(this);
	}

	// (an effect's compute error, in the apply phase: its handler (a throw from
	// it goes on), else the nearest boundary; nothing: a user effect's is
	// logged and its run skipped, a render effect's halts (the flush throws it))
	function deliver(e:Dynamic) {
		if (onFailure != null) {
			// (in its store, as its apply)
			var savedAtoms = Atoms.current;
			Atoms.current = home;
			try {
				within(null, null, () -> onFailure(e));
				Atoms.current = savedAtoms;
				return;
			} catch (x:haxe.Exception) {
				Atoms.current = savedAtoms;
				e = x.native;
				thrown = x;
			}
		}
		if (parent != null && parent.handle(e)) return;
		if (kind == EFFECT && onFailure == null) {
			trace('helder.view: an effect failed, its run skipped: $e');
			return;
		}
		Scheduler.failed(exception(e));
	}

	// (e as the exception it was thrown as)
	function exception(e:Dynamic):haxe.Exception
		return thrown != null && thrown.native == e ? thrown : @:privateAccess haxe.Exception.caught(e);

	// (an error read: thrown again, where it was thrown kept)
	function throwError(e:Dynamic) {
		if (thrown != null && thrown.native == e) throw helder.async.Errors.carried(thrown);
		throw e;
	}

	// s read in the current run
	function track(s:Node<Dynamic>) {
		if (s.trackedBy == this && s.trackedIn == run) return;
		s.trackedBy = this;
		s.trackedIn = run;
		if (added == null && sources != null && kept < sources.length && sources[kept] == s) {
			kept++;
			return;
		}
		if (added == null) added = [];
		added.push(s);
	}

	// (after a run: the new sources subscribed, then those not read again left)
	function reconcile() {
		// (disposed during its run: it let go of its sources then, and keeps none)
		if (disposed) {
			added = null;
			return;
		}
		var old = sources;
		if (added != null) {
			var stale = old != null && kept < old.length ? old.slice(kept) : null;
			if (old == null) sources = old = [];
			old.resize(kept);
			for (s in added) {
				old.push(s);
				if (s.observers == null) s.observers = [];
				s.observers.push(this);
			}
			added = null;
			raise();
			if (stale != null) unlinkAll(stale);
		} else if (old != null && kept < old.length) {
			var stale = old.slice(kept);
			old.resize(kept);
			raise();
			unlinkAll(stale);
		}
	}

	function raise() {
		var h = 0;
		if (sources != null)
			for (s in sources)
				if (s.height >= h) h = s.height + 1;
		height = h;
	}

	// (each source told it lost this observer, though one's unobserved throws: the first error after)
	function unlinkAll(ss:Array<Node<Dynamic>>) {
		var first:Null<haxe.Exception> = null;
		for (s in ss)
			try s.unobserve(this) catch (e:haxe.Exception) if (first == null) first = e;
		if (first != null) throw Errors.kept(first);
	}

	function unobserve(o:Node<Dynamic>) {
		if (observers == null || !observers.remove(o) || observers.length > 0) return;
		// (a free memo nothing observes lets go of its sources at the flush's
		// end, each told in turn (Scheduler.releases): read again it computes
		// again, taking them back; Solid 2's)
		if (kind == COMPUTED && free && !writable && sources != null) Scheduler.enqueueRelease(this);
		if (unobserved != null) unobserved();
	}

	// (still unobserved at the flush's end: its sources let go; Scheduler.releases)
	function unlinkSources() {
		if (disposed || computing || sources == null || observers != null && observers.length > 0) return;
		var ss = sources;
		sources = null;
		state = DIRTY;
		unlinkAll(ss);
	}

	// (applies its second half; its error the nearest boundary's, else the flush's)
	function runApply(first = false) {
		toApply = false;
		// (behind a boundary's fallback: held until it reveals; a render effect's first render goes through)
		if (!first && !disposed && !hasError) {
			var b = Boundary.hiding(this);
			if (b != null) {
				b.hold(this);
				return;
			}
		}
		if (hasError) {
			var e = error;
			hasError = false;
			error = null;
			if (!disposed) deliver(e);
			return;
		}
		try applyNow() catch (e:haxe.Exception) if (parent == null || !parent.handle(e.native)) Scheduler.report(e);
	}

	// (the previous apply's cleanup first)
	function applyNow() {
		if (disposed || apply == null) return;
		if (applyCleanup != null) {
			var c = applyCleanup;
			applyCleanup = null;
			inHome(c);
		}
		var prev = applied;
		applied = value;
		// (with no owner, untracked: as within, with no closure made)
		var savedOwner = Owner.current, savedObserver = observer, savedAtoms = Atoms.current;
		Owner.current = null;
		Atoms.current = home;
		observer = null;
		#if hxmc.dev
		// (hxmc dev: in its compute's scope, what it makes keyed as there: helder.view.Refresh)
		// (an Exception caught, a thrown string wrapped: Errors.kept reads its stack)
		var c = try (hotPath == null ? apply(value, prev) : helder.dev.Hot.at(hotPath, () -> apply(value, prev))) catch (e:haxe.Exception) {
		#else
		var c = try apply(value, prev) catch (e:haxe.Exception) {
		#end
			Owner.current = savedOwner;
			Atoms.current = savedAtoms;
			observer = savedObserver;
			throw Errors.kept(e);
		}
		Owner.current = savedOwner;
		Atoms.current = savedAtoms;
		observer = savedObserver;
		if (c != null && !Reflect.isFunction(c))
			throw new GraphError("effect callback returned an invalid cleanup value: return a cleanup function or nothing");
		applyCleanup = c;
	}

	override function unlink() {
		release();
		if (retired != null) {
			var r = retired;
			retired = null;
			r.dispose();
		}
		if (awaiting != null) {
			var a = awaiting;
			awaiting = null;
			a.cancel();
		}
		if (sources != null) {
			var ss = sources;
			sources = null;
			unlinkAll(ss);
		}
		if (applyCleanup != null) {
			var c = applyCleanup;
			applyCleanup = null;
			Owner.disposing++;
			try inHome(c) catch (e:haxe.Exception) {
				Owner.disposing--;
				throw Errors.kept(e);
			}
			Owner.disposing--;
		}
	}

	// (an apply's cleanup in its store, as the apply)
	function inHome(c:Void->Void) {
		var saved = Atoms.current;
		Atoms.current = home;
		try c() catch (e:haxe.Exception) {
			Atoms.current = saved;
			throw Errors.kept(e);
		}
		Atoms.current = saved;
	}
}
