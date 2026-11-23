package helder.compiler;

using StringTools;

// helder.os: the system an hxmc target's program runs on (linux, android,
// macos, ios, windows, web), which helder's shared code picks its platform's
// implementation by: `#if (!helder.os || helder.os == "windows")`. hxmc
// folds its Platform tests only while lowering, after Haxe has typed every
// branch and hxmc has met (and lowered) every class they name; under #if
// the others' modules are never loaded. A build without it (a type check,
// --no-output) types every platform's. hxmc.os would replace it (hxmc#205).
class Os {
	public static function of(target:String):String {
		if (target.startsWith("macos-catalyst-")) return "ios";
		var os = target.split("-")[0];
		return os == "wasm32" ? "web" : os;
	}

	// (given on the command line by whatever builds for a target: hxmc's own
	// compiler, which does not derive it as helder's does, gets it too)
	public static function define(target:String):Array<String>
		return ["-D", 'helder.os=${of(target)}'];
}
