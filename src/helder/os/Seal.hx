package helder.os;

// A screen sealed off the machine: a scenario's in a preview host (the
// studio's) or a UI monkey's case (helder.scenario.Monkey), the current
// screen's (ScreenContext.environ) while it runs. What would change or open
// the machine's own files (the system's trash, the user's places, a store's
// file, an app's real files: the viewer's NativeFiles) calls check where it
// happens, which refuses it under a seal: thrown, and kept (refused), so
// the screen fails even when the program catches the throw. Outside every
// sealed screen check does nothing.
class Seal {
	// the current screen's (null: none)
	public static var current:Null<Seal> = null;

	// whose: a scenario's name, a monkey's case
	public final name:String;
	// what it refused, in order
	public final refused:Array<String> = [];

	public function new(name:String)
		this.name = name;

	// what would touch the machine (what: "helder.os.Trash.move", its
	// argument): refused under a seal, else nothing
	public static function check(what:String) {
		var s = current;
		if (s == null) return;
		var m = '$what refused: ${s.name} is sealed off the machine (its trash, places, stores and files)';
		s.refused.push(m);
		throw new SealError(m);
	}
}

// (an effect a seal refused)
class SealError extends haxe.Exception {}
