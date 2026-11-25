package studio;

import haxe.Exception;
import haxe.coro.Coroutine;
import haxe.coro.IContinuation;
import helder.async.*;
import helder.syntax.Transaction;
import studio.Acp;
import studio.Agent;

using StringTools;

// The user's own coding agent (Claude Code, Codex, Gemini CLI: Agents) over
// the Agent Client Protocol (agentclientprotocol.com, version 1): started
// on the first prompt (initialize, then session/new in the project's
// directory, the studio's MCP server given to it when it takes one over
// HTTP), each prompt a session/prompt (the text, the selection's file:line,
// the focused screen's PNG), its session/update notifications the turn's
// events. What it asks the user (session/request_permission) is an Ask;
// what it reads (fs/read_text_file) is the files as the studio has them,
// unsaved edits too; what it writes (fs/write_text_file) one edit of the
// studio's history, shown on the canvas and undone like any other. The
// process ending fails the turn (its last log lines told); the next prompt
// starts it again.
class AcpAgent implements Agent {
	public final command:AgentCommand;
	final work:Workspace;
	var acp:Null<Acp> = null;
	var session:Null<String> = null;
	var caps:Dynamic = {};
	var on:Null<AgentEvent->Void> = null;
	final asks = new Map<Int, Int->Void>();
	var asked = 0;
	final log:Array<String> = [];

	public function new(command:AgentCommand, work:Workspace) {
		this.command = command;
		this.work = work;
	}

	public function ask(prompt:String, context:AgentContext, on:AgentEvent->Void) {
		this.on = on;
		var self = this;
		Async.launch(_ -> self.turn(prompt, context, on));
	}

	public function cancel() {
		for (a in [for (a in asks) a])
			a(-1);
		var a = acp, s = session;
		if (a == null || s == null || a.closed) return;
		Async.launch(_ -> a.notify("session/cancel", {sessionId: s}));
	}

	public function close() {
		if (acp != null) acp.close();
	}

	@:coroutine function turn(prompt:String, context:AgentContext, on:AgentEvent->Void) {
		var r:Dynamic = try {
			var a = start();
			a.request("session/prompt", {sessionId: session, prompt: blocks(prompt, context)});
		} catch (e:Exception) {
			if (this.on == on) this.on = null;
			on(Failed(failure(e)));
			return;
		}
		if (this.on == on) this.on = null;
		on(Done(r?.stopReason ?? "end_turn"));
	}

	// (the agent running, its session made: lazily, again after it ended)
	@:coroutine function start():Acp {
		if (acp != null && !acp.closed) return acp;
		log.resize(0);
		var a = Acp.spawn(command.cmd, command.args, {cwd: work.dir});
		acp = a;
		var self = this;
		a.onLog = line -> {
			log.push(line);
			if (log.length > 20) log.shift();
		}
		a.onNotification = (method, params) -> if (method == "session/update") update(params);
		a.handle("session/request_permission", p -> self.permission(p));
		a.handle("fs/read_text_file", p -> self.read(p));
		a.handle("fs/write_text_file", p -> self.write(p));
		Async.launch(task -> a.run(task));
		try {
			var init:Dynamic = a.request("initialize", {
				protocolVersion: 1,
				clientCapabilities: {fs: {readTextFile: true, writeTextFile: true}, terminal: false},
				clientInfo: {name: "helder-studio", title: "helder studio", version: "0.1.0"}
			});
			caps = init?.agentCapabilities ?? {};
			var url = work.mcp(), http = caps.mcpCapabilities?.http == true;
			if (url != null && !http) Sys.println('studio: ${command.name} takes no MCP server over HTTP: the studio\'s tools are not its');
			var s:Dynamic = try a.request("session/new", {
				cwd: work.dir,
				mcpServers: url != null && http ? [{type: "http", name: "helder-studio", url: url, headers: []}] : []
			}) catch (e:AcpError) {
				var methods:Array<Dynamic> = init?.authMethods ?? [];
				if (e.code != -32000 || methods.length == 0) throw e;
				throw new AcpError(e.code, '${e.message} (${[for (m in methods) m.description ?? m.name].join("; ")})');
			}
			session = s.sessionId;
		} catch (e:Exception) {
			a.close();
			throw e;
		}
		return a;
	}

	function failure(e:Exception):String {
		var a = acp;
		var ended = a != null && a.closed;
		return '${command.name}: ${e.message}' + (ended && log.length > 0 ? "\n" + log.slice(-6).join("\n") : "");
	}

	// the prompt's content: its text, where the user is (the focused
	// screen, the selection's file and line), the screen's PNG when the agent takes images
	@:coroutine function blocks(prompt:String, context:AgentContext):Array<Dynamic> {
		var out:Array<Dynamic> = [{type: "text", text: prompt}];
		var sel = context.selection;
		if (sel != null) {
			var line = try work.docs.get(sel.file).doc.lineCol(sel.start).line catch (_:Exception) 1;
			var where = '${rel(sel.file)}:$line';
			out.push({type: "text", text: 'In helder studio: the screen ${sel.screen} is in focus, its <${sel.tag}> selected ($where).'});
			out.push({type: "resource_link", uri: uri(sel.file) + '#L$line', name: where});
		} else if (context.screen != null)
			out.push({type: "text", text: 'In helder studio: the screen ${context.screen} is in focus.'});
		if (context.screen != null && work.snap != null && caps.promptCapabilities?.image == true) {
			var png = try work.snap(context.screen) catch (_:Exception) null;
			if (png != null) out.push({type: "image", mimeType: "image/png", data: png});
		}
		return out;
	}

	function update(p:Dynamic) {
		var on = this.on, u:Dynamic = p?.update;
		if (on == null || u == null || p.sessionId != session) return;
		switch (u.sessionUpdate : String) {
			case "agent_message_chunk":
				if (u.content?.type == "text") on(Text(u.content.text));
			case "agent_thought_chunk":
				if (u.content?.type == "text") on(Thought(u.content.text));
			case "tool_call":
				on(Tool(u.toolCallId, u.title ?? "", u.kind ?? "other", u.status ?? "pending"));
			case "tool_call_update":
				on(Tool(u.toolCallId, u.title ?? "", u.kind ?? "", u.status ?? ""));
			case "plan":
				var entries:Array<Dynamic> = u.entries ?? [];
				on(Steps([for (e in entries) {text: (e.content : String), done: e.status == "completed"}]));
			case _:
		}
	}

	// (the user's answer: an option's id; cancelled when the turn is stopped)
	@:coroutine function permission(p:Dynamic):Dynamic {
		var on = this.on, options:Array<Dynamic> = p?.options ?? [];
		if (on == null || options.length == 0) return {outcome: {outcome: "cancelled"}};
		var question:String = p.toolCall?.title ?? '${command.name} asks';
		var asks = asks, id = ++asked;
		var i = Async.suspendCancellable((cont:IContinuation<Int>) -> {
			asks.set(id, i -> if (asks.remove(id)) cont.resume(i, null));
			on(Ask(question, [for (o in options) (o.name : String)], i -> {
				var a = asks.get(id);
				if (a != null) a(i);
			}));
			return _ -> asks.remove(id);
		});
		if (i < 0 || i >= options.length) return {outcome: {outcome: "cancelled"}};
		return {outcome: {outcome: "selected", optionId: options[i].optionId}};
	}

	function read(p:Dynamic):Dynamic {
		var f = inside(p?.path);
		if (!Files.exists(f)) throw new AcpError(-32002, '${p.path}: no such file');
		var text = work.docs.get(f).text;
		var line:Null<Int> = p.line, limit:Null<Int> = p.limit;
		if (line == null && limit == null) return {content: text};
		var lines = text.split("\n");
		var from = line == null ? 0 : Std.int(Math.max(line - 1, 0));
		var to = limit == null ? lines.length : Std.int(Math.min(from + limit, lines.length));
		return {content: lines.slice(from, to).join("\n")};
	}

	// (a file the studio has: one edit of its history; a new one written)
	function write(p:Dynamic):Dynamic {
		var f = inside(p?.path);
		var text:String = p.content ?? "";
		if (!Files.exists(f)) {
			#if !(hxmc.target == "wasm32-wasi")
			sys.FileSystem.createDirectory(haxe.io.Path.directory(f));
			#end
			Files.save(f, text);
			return null;
		}
		var d = work.docs.get(f);
		if (d.text != text) work.docs.apply(f, new Transaction([Docs.difference(d.text, text)], null, d.text), '${command.name}\'s edit of ${rel(f)}', "agent");
		return null;
	}

	function inside(p:Null<String>):String {
		if (p == null || p == "") throw new AcpError(-32602, "a path is needed");
		var full = haxe.io.Path.normalize(haxe.io.Path.isAbsolute(p) ? p : work.dir + "/" + p);
		if (!full.startsWith(work.dir + "/")) throw new AcpError(-32602, '$p is not in the project (${work.dir})');
		return full;
	}

	function rel(f:String):String
		return f.startsWith(work.dir + "/") ? f.substr(work.dir.length + 1) : f;

	static function uri(path:String):String
		return "file://" + (path.startsWith("/") ? "" : "/") + path.replace("%", "%25").replace(" ", "%20").replace("#", "%23");
}

// how an agent is started: its name, its command and arguments
typedef AgentCommand = {
	name:String,
	cmd:String,
	args:Array<String>,
}

// what an agent over ACP works in: the project's directory, its files as the
// studio has them (Docs: one history), the studio's MCP server (its URL once
// it listens), a screen's last frame (a PNG, base64)
typedef Workspace = {
	dir:String,
	docs:Docs,
	mcp:Void->Null<String>,
	snap:Null<Coroutine<String->Null<String>>>,
}
