package helder.os;

// a modifier key held with an event (Mods.has)
enum abstract Mod(String) {
	var Shift = "shift";
	var Control = "control";
	var Alt = "alt";
	var Meta = "meta";
}

// The modifier keys held with an event (Event.mods), a set of Mod kept as
// bits (`e.mods.has(Meta)`; `e.mods & Mods.META != 0`); TypeScript's are
// their names
@:typescript.type('Array<import("helder/os").Mod>')
abstract Mods(Int) from Int to Int {
	public static inline var NONE:Mods = 0;
	public static inline var SHIFT:Mods = 1;
	public static inline var CONTROL:Mods = 2;
	public static inline var ALT:Mods = 4;
	public static inline var META:Mods = 8;

	public inline function has(m:Mod):Bool
		return this & bit(m) != 0;

	public inline function with(m:Mod):Mods
		return this | bit(m);

	static inline function bit(m:Mod):Int
		return m == Shift ? 1 : m == Control ? 2 : m == Alt ? 4 : m == Meta ? 8 : 0;

	// (TypeScript's: the names, and the set from them)
	@:noCompletion public function names():Array<String>
		return [for (m in [Shift, Control, Alt, Meta]) if (has(m)) (cast m : String)];

	@:noCompletion public static function ofNames(names:Array<String>):Mods {
		var m:Mods = NONE;
		for (n in names) m = m.with(cast n);
		return m;
	}
}
