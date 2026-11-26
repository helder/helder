package helder.view;

import helder.view.graph.Graph;
import helder.view.graph.Signal;

// A screen's data signals by name (helder.scenario's store): under helder
// dev each signal(value) bound to a variable is named by it, `Game.score`
// for `const score = signal(...)` in Game (Haxe: the class and the function,
// `Pong.Game.score`; a constructor's or a field's, `Game.score`), and added
// to the names of the screen it is made in (ScreenContext's, current while
// it runs). A second of one name in a screen is name#1, and so on; a signal
// let go (its owner disposed) gives its name back. A scenario's values
// (preset) are set as each is made, before anything reads it, checked
// against its initial value's shape.
class Named {
	// the current screen's (ScreenContext.run's; null: none named)
	public static var current:Null<Named> = null;

	// the values signals start at, by name (a scenario's set)
	public var preset:Null<Map<String, Dynamic>> = null;
	// the preset names made
	public final used:Array<String> = [];

	final signals = new Map<String, Signal<Dynamic>>();

	public function new() {}

	// s named in the current screen (a value preset for the name its own)
	@:noCompletion public static function add<T>(s:Signal<T>, name:String):Signal<T> {
		var n = current;
		if (n == null) return s;
		var k = name, i = 0;
		while (n.signals.exists(k))
			k = name + "#" + ++i;
		n.signals.set(k, cast s);
		var p = n.preset;
		if (p != null && p.exists(k)) {
			var v = p.get(k), why = Shape.differs(s.peek(), v);
			if (why != null) throw '$k: $why';
			@:privateAccess s.node().value = v;
			if (!n.used.contains(k)) n.used.push(k);
		}
		if (Graph.getOwner() != null) Graph.onCleanup(() -> if (n.signals.get(k) == cast s) n.signals.remove(k));
		return s;
	}

	public function get(name:String):Null<Signal<Dynamic>>
		return signals.get(name);

	// the names made, sorted
	public function names():Array<String> {
		var l = [for (k in signals.keys()) k];
		l.sort(Reflect.compare);
		return l;
	}

	// the preset names no signal took (an error's: each with the nearest name made)
	public function unknown():Array<String> {
		if (preset == null) return [];
		var made = names(), out = [];
		for (k in preset.keys())
			if (!used.contains(k)) {
				var near = Shape.nearest(k, made);
				out.push(near == null ? '"$k"' : '"$k" (did you mean "$near"?)');
			}
		out.sort(Reflect.compare);
		return out;
	}
}

// (a value's shape against a signal's: what a scenario's set may give it)
class Shape {
	// why v cannot be like was (null: it can)
	public static function differs(was:Dynamic, v:Dynamic):Null<String> {
		if (was == null || v == null) return null;
		var a = kind(was), b = kind(v);
		if (a != b) return 'a $b, not $a';
		switch a {
			case "array":
				var l:Array<Dynamic> = was, m:Array<Dynamic> = v;
				if (l.length > 0) for (x in m) {
					var why = differs(l[0], x);
					if (why != null) return 'an item: $why';
				}
			case "object":
				var fields = Reflect.fields(was);
				if (fields.length > 0) for (f in Reflect.fields(v)) {
					if (!fields.contains(f)) {
						var near = nearest(f, fields);
						return 'no field "$f"' + (near == null ? "" : ' (did you mean "$near"?)');
					}
					var why = differs(Reflect.field(was, f), Reflect.field(v, f));
					if (why != null) return '$f: $why';
				}
			case _:
		}
		return null;
	}

	static function kind(v:Dynamic):String
		return if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) "number" else if (Std.isOfType(v, String)) "string" else if (Std.isOfType(v, Bool))
			"boolean" else if (Std.isOfType(v, Array)) "array" else if (Reflect.isObject(v) && Type.getClass(v) == null) "object" else "value";

	// the name of names nearest to name (null: none near enough)
	public static function nearest(name:String, names:Array<String>):Null<String> {
		var best:Null<String> = null, d = Std.int(name.length / 3) + 1;
		for (n in names) {
			var e = distance(name.toLowerCase(), n.toLowerCase());
			if (e < d) {
				d = e;
				best = n;
			}
		}
		return best;
	}

	static function distance(a:String, b:String):Int {
		var row = [for (j in 0...b.length + 1) j];
		for (i in 1...a.length + 1) {
			var prev = row[0];
			row[0] = i;
			for (j in 1...b.length + 1) {
				var t = row[j];
				row[j] = Std.int(Math.min(Math.min(row[j] + 1, row[j - 1] + 1), prev + (a.charCodeAt(i - 1) == b.charCodeAt(j - 1) ? 0 : 1)));
				prev = t;
			}
		}
		return row[b.length];
	}
}
