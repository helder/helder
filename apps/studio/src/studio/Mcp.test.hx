package studio;

import haxe.Json;
import helder.test.Test;

// The MCP server's requests (Mcp.respond, no socket): sessions, routes,
// the agent a session is
function tests() {
	describe("Mcp", () -> {
		final ready = {jsonrpc: "2.0", method: "notifications/initialized"};
		function make():{mcp:Mcp, agents:Presence} {
			var t = new Desk();
			return {mcp: new Mcp(name -> name == null || name == "todo" ? t : null, 0), agents: t.agents()};
		}
		test("initialize: a session, its agent named after its client", async(() -> {
			var s = make();
			var r = post(s.mcp, init("claude-code"));
			var id = r.headers.get("mcp-session-id");
			equals([r.status, id.length], [200, 18]);
			equals(Json.parse(r.body.toString()).result.instructions, Instructions.text);
			equals(post(s.mcp, ready, id).status, 202);
			var other = post(s.mcp, init("claude-code")).headers.get("mcp-session-id");
			post(s.mcp, ready, other);
			equals([for (p in s.agents.list()) p.name], ["Claude", "Claude 2"]);
		}));
		test("a tool call moves its agent, studio.done stops it", async(() -> {
			var s = make();
			var id = post(s.mcp, init("codex")).headers.get("mcp-session-id");
			post(s.mcp, {jsonrpc: "2.0", id: 2, method: "tools/call", params: {name: "run.tree", arguments: {screen: "Todo/Empty"}}}, id);
			var a = s.agents.peer(id);
			equals([a.name, a.screen], ["Codex", "Todo/Empty"]);
			equals(a.working, true);
			post(s.mcp, {jsonrpc: "2.0", id: 3, method: "tools/call", params: {name: "studio.done", arguments: {note: "done"}}}, id);
			equals(s.agents.peer(id).working, false);
		}));
		test("without a session the one anonymous agent; an unknown one 404; DELETE leaves", async(() -> {
			var s = make();
			var listed = post(s.mcp, {jsonrpc: "2.0", id: 1, method: "tools/list"});
			equals(listed.status, 200);
			var tools:Array<Dynamic> = Json.parse(listed.body.toString()).result.tools;
			equals([tools.length, Lambda.count(tools, t -> Reflect.field(t._meta, "anthropic/alwaysLoad") == true)], [Tools.list.length, Tools.list.length]);
			equals([for (p in s.agents.list()) p.name], ["Agent"]);
			equals(post(s.mcp, {jsonrpc: "2.0", id: 1, method: "ping"}, "nope").status, 404);
			var id = post(s.mcp, init("cursor")).headers.get("mcp-session-id");
			post(s.mcp, ready, id);
			equals(s.agents.peer(id).name, "Cursor");
			equals(s.mcp.respond("DELETE", "/mcp", id, "").status, 200);
			equals(s.agents.peer(id), null);
			equals(post(s.mcp, {jsonrpc: "2.0", id: 1, method: "ping"}, id).status, 404);
		}));
		test("/mcp/<name>: that project, another a 404", async(() -> {
			var s = make();
			equals(post(s.mcp, init("claude"), null, "/mcp/todo").status, 200);
			var r = post(s.mcp, init("claude"), null, "/mcp/other");
			equals([r.status, Json.parse(r.body.toString()).error.code], [404, -32001]);
			equals([Mcp.route("/mcp"), Mcp.route("/mcp/a%20b"), Mcp.route("/x"), Mcp.route("/mcp/a/b")], ["", "a b", null, null]);
		}));
		#if !(hxmc.target == "wasm32-wasi")
		test("the port taken: the next", () -> {
			var a = Mcp.listen(Mcp.PORT + 30), b = Mcp.listen(Mcp.PORT + 30);
			equals([a.port, b.port], [Mcp.PORT + 30, Mcp.PORT + 31]);
			a.close();
			b.close();
		});
		#end
	});
}

@:coroutine function post(m:Mcp, body:Dynamic, ?session:String, path = "/mcp"):helder.async.http.Http.Response
	return m.respond("POST", path, session, Json.stringify(body));

function init(client:String):Dynamic
	return {jsonrpc: "2.0", id: 1, method: "initialize", params: {protocolVersion: Mcp.VERSION, clientInfo: {name: client, version: "1"}}};

// (a project's tools as Mcp reaches them: the agent moved, the tool's name answered)
private class Desk implements Mcp.Target {
	final presence = new Presence();

	public function new() {}

	public function agents():Presence
		return presence;

	@:coroutine public function tool(name:String, args:Dynamic, agent:String):{content:Array<Dynamic>, isError:Bool} {
		presence.called(agent, name, args);
		if (name == "studio.done") presence.done(agent, args.note);
		return {content: [{type: "text", text: name}], isError: false};
	}
}
