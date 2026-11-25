package studio;

using StringTools;

// The coding agents the studio knows, each spoken to over ACP (AcpAgent):
//
//   claude   Claude Code through its ACP adapter (the Claude Agent SDK's:
//            npx -y @agentclientprotocol/claude-agent-acp), Claude Code's login
//   codex    Codex's adapter (codex-acp, else npx -y @agentclientprotocol/codex-acp)
//   gemini   gemini --experimental-acp (Gemini CLI; newer ones also take --acp)
//   local    none: the studio's tools alone (LocalAgent)
//   any other ACP agent by its command line ("node my-agent.mjs", "/path/to/agent --acp")
//
// The one used: --agent, else HELDER_STUDIO_AGENT, else the first of claude,
// codex and gemini whose CLI is on the PATH, else local.
class Agents {
	public static final names = ["claude", "codex", "gemini", "local"];

	// the agent of that name (null: the default), how it starts (null: local)
	public static function command(name:Null<String>):Null<AgentCommand> {
		if (name == "local") return null;
		if (name != null && !names.contains(name)) {
			var words = name.split(" ").filter(w -> w != "");
			if (words.length < 2 && !name.contains("/")) throw '$name: not an agent (${names.join(", ")}, or a command line)';
			var last = words[words.length - 1];
			return run(haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(last)), words[0], words.slice(1));
		}
		var tried = name == null ? ["claude", "codex", "gemini"] : [name];
		for (n in tried) {
			var c = of(n, name == null);
			if (c != null) return c;
		}
		if (name != null) throw '$name: not found on the PATH';
		return null;
	}

	// the agents found on this machine (the chat's menu), local last
	public static function found():Array<String> {
		#if (hxmc.target == "wasm32-wasi")
		return ["local"];
		#else
		return [for (n in ["claude", "codex", "gemini"]) if (of(n, true) != null) n].concat(["local"]);
		#end
	}

	// an agent's name as the chat writes it ("Claude"; local: the studio's tools)
	public static function label(id:String):String
		return switch id {
			case "local": "Studio";
			case _: id.charAt(0).toUpperCase() + id.substr(1);
		}

	// its colour: the known ones' in Theme.AGENTS' order (Claude's the warm orange), another's after them
	public static function colour(id:String):String {
		var i = ["claude", "codex", "gemini"].indexOf(id);
		return id == "local" ? "#8b8b94" : Theme.AGENTS[i < 0 ? 3 : i];
	}

	// (fallback: chosen by default, it needs its own CLI on the PATH, not npx alone)
	static function of(name:String, fallback:Bool):Null<AgentCommand> {
		switch name {
			case "claude":
				if (fallback && which("claude") == null) return null;
				return npx(name, "@agentclientprotocol/claude-agent-acp");
			case "codex":
				var own = which("codex-acp");
				if (own != null) return run(name, own, []);
				if (fallback && which("codex") == null) return null;
				return npx(name, "@agentclientprotocol/codex-acp");
			case "gemini":
				var g = which("gemini");
				return g == null ? null : run(name, g, ["--experimental-acp"]);
			case _:
				return null;
		}
	}

	static function npx(name:String, pkg:String):Null<AgentCommand> {
		var n = which("npx");
		return n == null ? null : run(name, n, ["-y", pkg]);
	}

	// (Windows: a .cmd is cmd.exe's to run)
	static function run(name:String, path:String, args:Array<String>):AgentCommand {
		var l = path.toLowerCase();
		if (l.endsWith(".cmd") || l.endsWith(".bat")) return {name: name, cmd: "cmd.exe", args: ["/c", path].concat(args)};
		return {name: name, cmd: path, args: args};
	}

	// a program's path on the PATH (null: none)
	public static function which(cmd:String):Null<String> {
		var windows = Sys.systemName() == "Windows";
		var exts = windows ? (Sys.getEnv("PATHEXT") ?? ".EXE;.CMD;.BAT").split(";") : [""];
		for (dir in (Sys.getEnv("PATH") ?? "").split(windows ? ";" : ":")) {
			if (dir == "") continue;
			for (e in exts) {
				var p = '$dir/$cmd$e';
				if (sys.FileSystem.exists(p) && !sys.FileSystem.isDirectory(p)) return p;
			}
		}
		return null;
	}
}

// how an agent is started: its name, its command and arguments
typedef AgentCommand = {
	name:String,
	cmd:String,
	args:Array<String>,
}
