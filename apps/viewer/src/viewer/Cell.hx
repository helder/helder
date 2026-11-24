package viewer;

import helder.view.graph.Graph;
import helder.view.graph.Signal;

// A model's value: read back at once where the model writes it (value),
// and by the window as a signal (c(), tracked), whose writes land at the
// next flush as every signal's do.
abstract Cell<T>(CellOf<T>) {
	public var value(get, never):T;

	public inline function new(v:T)
		this = new CellOf(v);

	inline function get_value():T
		return this.value;

	@:op(a()) public inline function read():T
		return this.signal();

	@:op(a()) public inline function write(v:T):Void {
		this.value = v;
		this.signal(v);
	}
}

private class CellOf<T> {
	public var value:T;
	public final signal:Signal<T>;

	public function new(v:T) {
		value = v;
		signal = Graph.signalOf(v, {ownedWrite: true});
	}
}
