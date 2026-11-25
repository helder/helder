package studio;

import haxe.Json;
import helder.async.*;
import helder.async.http.Http;

using StringTools;

// The studio's tools (Tools) over MCP, the Model Context Protocol's
// Streamable HTTP transport in its simplest form: JSON-RPC requests POSTed,
// each answered with one JSON response (no event stream; notifications
// answered 202). Listening on 127.0.0.1 only: --mcp-port, else
// HELDER_STUDIO_MCP_PORT, else 7340, the next ones up to 7359 when taken,
// then a free one; the URL is printed and written to
// <root>/bin/studio/<name>/mcp.json for an agent to find. Claude Code:
//
//   claude mcp add --transport http helder-studio http://127.0.0.1:7340/mcp
//
// /mcp follows the project in front, /mcp/<name> is the project named so
// (both through resolve). initialize starts a session (Mcp-Session-Id, its
// client's name: the agent's in Presence); a request without one is the
// one anonymous agent's ("Agent"), an unknown one a 404 (the client
// initializes again), DELETE ends it.
class Mcp {
	// (the studio's tools, each always in Claude Code's prompt: no tool search
	// before the first of them, anthropic/alwaysLoad)
	static function listed():Array<Dynamic>
		return [for (t in Tools.list) {name: t.name, description: t.description, inputSchema: t.inputSchema, _meta: {"anthropic/alwaysLoad": true}}];

	public static inline var VERSION = "2025-06-18";
	public static inline var PORT = 7340;
	public static inline var ANONYMOUS = "anonymous";

	final resolve:Null<String>->Null<Target>;
	final port:Int;
	// the sessions started: their clients' names
	final sessions = new Map<String, Null<String>>();
	public var url(default, null):Null<String> = null;

	public function new(resolve, port:Int) {
		this.resolve = resolve;
		this.port = port;
	}

	// (ready: the URL, once listening)
	@:coroutine public function serve(task:Node, ready:String->Void) {
		var server = try listen(port) catch (e:Dynamic) {
			Sys.println('studio: no MCP server ($e)');
			return;
		}
		url = 'http://127.0.0.1:${server.port}/mcp';
		Sys.println('studio: MCP at $url (claude mcp add --transport http helder-studio $url)');
		ready(url);
		Http.serve(server, handle);
	}

	// port, else the next of the 20 from it, else a free one (port 0: a free one)
	public static function listen(port:Int):Server {
		if (port > 0) for (p in port...port + 20) {
			var s = try Server.listen("127.0.0.1", p) catch (_:Dynamic) null;
			if (s != null) return s;
		}
		return Server.listen("127.0.0.1", 0);
	}

	@:coroutine function handle(req:Request):Null<Response>
		return respond(req.method, req.path, req.header("mcp-session-id"), req.body.toString());

	@:coroutine public function respond(method:String, path:String, session:Null<String>, body:String):Response {
		var name = route(path);
		if (name == null) return Response.text("helder studio: MCP is at /mcp\n", 404);
		var target = resolve(name == "" ? null : name);
		if (target == null) return error(-32001, 'no project $name open in the studio', 404);
		if (method == "GET") return Response.text("helder studio: no event stream; POST JSON-RPC to /mcp\n", 405);
		if (method == "DELETE") {
			if (session == null || !sessions.exists(session)) return error(-32001, "no such session", 404);
			sessions.remove(session);
			target.agents().leave(session);
			return new Response(200);
		}
		if (method != "POST") return Response.text("POST /mcp\n", 405);
		var m:Dynamic = try Json.parse(body) catch (_:Dynamic) null;
		if (m == null) return error(-32700, "not JSON", 400);
		var all:Array<Dynamic> = Std.isOfType(m, Array) ? m : [m];
		var init:Dynamic = Lambda.find(all, (x:Dynamic) -> x.method == "initialize");
		if (session != null && !sessions.exists(session) && init == null) return error(-32001, "no such session (initialize again)", 404);
		// (initialize: a session started, its agent here at its next request; without one, the anonymous agent)
		var id = session ?? ANONYMOUS;
		if (init != null) {
			id = newId();
			sessions.set(id, init.params?.clientInfo?.name);
		} else {
			var p = target.agents();
			p.arrive(id, id == ANONYMOUS ? null : sessions.get(id));
			p.seen(id);
		}
		var out = [];
		for (x in all) {
			var r = one(x, target, id);
			if (r != null) out.push(r);
		}
		var res = out.length == 0 ? new Response(202) : json(Std.isOfType(m, Array) ? out : out[0]);
		if (init != null) res.headers.set("mcp-session-id", id);
		return res;
	}

	// a path's project: "" the one in front, else its name (null: not MCP's)
	public static function route(path:String):Null<String> {
		if (path == "/mcp" || path == "/mcp/") return "";
		if (!path.startsWith("/mcp/")) return null;
		var name = StringTools.urlDecode(path.substr(5));
		return name.contains("/") ? null : name;
	}

	// one message: its response (null: a notification's, none)
	@:coroutine function one(m:Dynamic, target:Target, agent:String):Null<Dynamic> {
		var id:Dynamic = m.id;
		if (m.method == null || id == null) return null;
		var method:String = m.method;
		var result:Dynamic = switch method {
			case "initialize":
				{
					protocolVersion: m.params?.protocolVersion ?? VERSION,
					capabilities: {tools: {listChanged: false}},
					serverInfo: {name: "helder-studio", version: "0.1.0"},
					instructions: Instructions.text
				};
			case "ping": {};
			case "tools/list": {tools: listed()};
			case "tools/call":
				var name:String = m.params?.name;
				target.tool(name, m.params?.arguments, agent);
			case "resources/list": {resources: []};
			case "prompts/list": {prompts: []};
			case _: null;
		}
		if (result == null) return {jsonrpc: "2.0", id: id, error: {code: -32601, message: 'no method $method'}};
		return {jsonrpc: "2.0", id: id, result: result};
	}

	// (the clock's part: a session of a studio before this one not taken for one now)
	static function newId():String {
		var b = new StringBuf();
		b.add(StringTools.hex(Std.int(haxe.Timer.stamp() * 1000) & 0xffffff, 6));
		for (_ in 0...3) b.add(StringTools.hex(Std.random(0x10000), 4));
		return b.toString().toLowerCase();
	}

	static function error(code:Int, message:String, status:Int):Response
		return json({jsonrpc: "2.0", id: null, error: {code: code, message: message}}, status);

	static function json(v:Dynamic, status = 200):Response
		return Response.text(Json.stringify(v), status, "application/json");
}

// what a route reaches: a project open in the studio, its agents and its
// tools (Tools: the studio's own)
interface Target {
	function agents():Presence;
	@:coroutine function tool(name:String, args:Dynamic, agent:String):{content:Array<Dynamic>, isError:Bool};
}
