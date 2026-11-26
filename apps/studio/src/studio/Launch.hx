package studio;

using StringTools;

// `helder dev` playing a window (Studio.playWindow), read from its lines:
// "starting" until its program is built, "running" then, "failed" at a
// failed build (its first error, where: "file:line", the project's), an
// error or a crash, "ended" when it exits on its own (the window closed).
// A failed first build does not end helder dev (it waits for a change):
// told from its lines, not its exit.
class Launch {
	public var state(default, null) = "starting";
	// what is shown beside Play: the last line on its way, or what failed
	public var note(default, null) = "";
	public var at(default, null):Null<String> = null;
	// its devtools' address (the program's methods through helder dev: Scenario.play), null until said
	public var devtools(default, null):Null<String> = null;
	// the builds that landed in the window (built, rebuilt, reloaded, patched)
	public var builds(default, null) = 0;

	final dir:String;
	// (an [ERROR]'s place, its message the next "| ..." line; the build's first error)
	var place:Null<String> = null;
	var first:Null<{at:String, message:String}> = null;

	public function new(dir:String, note:String) {
		this.dir = dir;
		this.note = note;
	}

	// a line of its output: whether what it shows changed
	public function read(raw:String):Bool {
		var line = new EReg(String.fromCharCode(27) + "\\[[0-9;]*m", "g").replace(raw, "").trim();
		if (line == "") return false;
		var error = ~/^\[ERROR\] (.+?):(\d+):/;
		if (error.match(line)) {
			if (first == null) place = rel(error.matched(1)) + ":" + error.matched(2);
			return false;
		}
		var message = ~/^\|\s+([^\s^].*)$/;
		if (place != null && message.match(line)) {
			first = {at: place, message: message.matched(1)};
			place = null;
			return false;
		}
		var status = ~/^([a-z]+)(?:\s+(.*))?$/;
		var verb = status.match(line) ? status.matched(1) : "", rest = verb == "" ? line : status.matched(2) ?? "";
		switch verb {
			case "built" | "rebuilt" | "reloaded" | "patched" | "shown" | "started" | "connected":
				first = null;
				if (verb != "shown" && verb != "started" && verb != "connected") builds++;
				return set("running", line, null);
			case "devtools" if (~/^wss?:\/\/\S+$/.match(rest)):
				devtools = rest;
				return state == "starting" && set("starting", line, null);
			case "failed":
				var f = first;
				first = null;
				return f == null ? set("failed", "the build failed", null) : set("failed", f.message, f.at);
			case "error" | "crashed":
				return set("failed", rest, null);
			case "closed":
				return set("ended", rest, null);
			case _:
				// (on its way: its last line shown, not a diagnostic's; a running window's own output not)
				return state == "starting" && !~/^(\[[A-Z]+\]|\d+ \||- \||\|)/.match(line) && set("starting", line, null);
		}
	}

	// its exit (code): an early or failed one keeps what failed, else it ended
	public function exited(code:Int) {
		if (state == "failed") return;
		if (code != 0) set("failed", 'helder dev ended (exit code $code)', null) else set("ended", "", null);
	}

	function set(s:String, n:String, a:Null<String>):Bool {
		if (s == state && n == note && a == at) return false;
		state = s;
		note = n;
		at = a;
		return true;
	}

	function rel(f:String):String
		return f.startsWith(dir + "/") ? f.substr(dir.length + 1) : haxe.io.Path.withoutDirectory(f);
}
