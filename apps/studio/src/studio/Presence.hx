package studio;

import helder.view.graph.Graph.*;
import helder.view.graph.Signal;

using StringTools;

// The agents connected to the studio and where each works: one a session
// of the MCP server's (Mcp), named after its client ("Claude", "Claude 2"),
// a colour of Theme.AGENTS while it is here. The tools it calls move it
// (Tools: a file read, a screen's tree or frame, a patch's lines), without
// a call of its own; studio.working and studio.done say what it does.
// Quiet for IDLE seconds it no longer works (its marks fade), for GONE it
// leaves. The views read peers; the clock is the checks' to set.
class Presence {
	public static inline var IDLE = 60.0;
	public static inline var GONE = 600.0;

	public final peers:Signal<Array<Peer>> = signal([]);
	// (the truth: a signal's write lands at the event's end)
	var all:Array<Peer> = [];
	final clock:Void->Float;

	public function new(?clock:Void->Float)
		this.clock = clock ?? haxe.Timer.stamp;

	public function peer(id:String):Null<Peer>
		return Lambda.find(all, p -> p.id == id);

	public function list():Array<Peer>
		return all;

	// an agent here (again): its name its client's, numbered past the ones here
	public function arrive(id:String, client:Null<String>):Peer {
		var p = peer(id);
		if (p != null) return p;
		var base = name(client), n = 1;
		function taken(s:String)
			return Lambda.exists(all, p -> p.name == s);
		while (taken(n == 1 ? base : '$base ${n}')) n++;
		var used = [for (p in all) p.colour];
		var colour = Lambda.find(Theme.AGENTS, c -> !used.contains(c)) ?? Theme.AGENTS[all.length % Theme.AGENTS.length];
		var p:Peer = {
			id: id,
			name: n == 1 ? base : '$base $n',
			colour: colour,
			screen: null,
			file: null,
			spans: [],
			status: "",
			working: false,
			lastSeen: clock(),
			touched: 0
		};
		set(all.concat([p]));
		return p;
	}

	public function leave(id:String)
		if (peer(id) != null) set(all.filter(p -> p.id != id));

	// a request of its: still here
	public function seen(id:String)
		update(id, p -> p.lastSeen = clock());

	// a tool called: where it works now
	public function called(id:String, tool:String, args:Dynamic) {
		if (args == null) args = {};
		update(id, p -> {
			p.lastSeen = clock();
			p.working = tool != "studio.done";
			switch tool {
				case "project.read" if (args.path != null && args.path != ""):
					p.file = args.path;
				case "run.tree" | "run.snap" if (args.screen != null):
					p.screen = args.screen;
				case "project.patch" if (args.path != null):
					p.file = args.path;
					p.status = 'Editing ${args.path}';
				case "build.check":
					p.status = "Checking";
				case _:
			}
		});
	}

	// what it is about to do (studio.working)
	public function working(id:String, note:Null<String>, ?screen:String, ?file:String)
		update(id, p -> {
			p.working = true;
			if (note != null) p.status = note;
			if (screen != null) p.screen = screen;
			if (file != null) p.file = file;
		});

	// it finished (studio.done): its marks fade
	public function done(id:String, ?note:String)
		update(id, p -> {
			p.working = false;
			p.status = note ?? "Done";
		});

	// the lines a patch of its changed (each file's, the text after it)
	public function patched(id:String, file:String, spans:Array<Span>)
		update(id, p -> {
			p.file = file;
			p.spans = spans;
			p.touched = clock();
		});

	// (each second: the quiet no longer work, the long quiet leave)
	public function tick() {
		var now = clock();
		var next = [for (p in all) if (now - p.lastSeen < GONE) p];
		var idle = Lambda.exists(next, p -> p.working && now - p.lastSeen >= IDLE);
		if (!idle && next.length == all.length) return;
		set([
			for (p in next)
				if (p.working && now - p.lastSeen >= IDLE) {var q = Reflect.copy(p); q.working = false; q;} else p
		]);
	}

	// a client's name as the studio shows it
	public static function name(client:Null<String>):String {
		var c = (client ?? "").trim().toLowerCase();
		if (c == "") return "Agent";
		if (c == "claude-code" || c.startsWith("claude")) return "Claude";
		if (c.startsWith("codex")) return "Codex";
		if (c.startsWith("gemini")) return "Gemini";
		if (c.startsWith("cursor")) return "Cursor";
		if (c == "opencode") return "OpenCode";
		var words = ~/[-_ ]+/g.split(client.trim()).filter(w -> w != "");
		return [for (w in words) w.charAt(0).toUpperCase() + w.substr(1)].join(" ");
	}

	// (peers are values: a changed one a copy)
	function update(id:String, f:Peer->Void) {
		var i = Lambda.findIndex(all, p -> p.id == id);
		if (i < 0) return;
		var p:Peer = Reflect.copy(all[i]);
		f(p);
		var next = all.copy();
		next[i] = p;
		set(next);
	}

	function set(next:Array<Peer>) {
		all = next;
		peers(next);
	}
}

typedef Peer = {
	id:String,
	name:String,
	// one of Theme.AGENTS
	colour:String,
	// the screen it is on, the file it read or patched last
	screen:Null<String>,
	file:Null<String>,
	// the lines its last patch made (touched: when; 0, none yet)
	spans:Array<Span>,
	touched:Float,
	// what it says it does (a note, "Editing app.tsx", "Checking")
	status:String,
	working:Bool,
	lastSeen:Float,
}

// lines of a file, from and to (1-based, both in)
typedef Span = {file:String, from:Int, to:Int};
