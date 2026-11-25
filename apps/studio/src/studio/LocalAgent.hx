package studio;

import helder.async.*;
import studio.Agent;

using StringTools;

// The agent without a model: a prompt that names a tool ("/tree", "/check",
// "/snap", "/read app.tsx") calls it on the local tool surface (Tools, the
// MCP server's); anything else says how to drive the studio from an agent
// over MCP (README.md, "Agents").
class LocalAgent implements Agent {
	final studio:Studio;

	public function new(studio)
		this.studio = studio;

	public function cancel() {}

	public function close() {}

	// the tool a prompt names (null: none)
	public static function tool(prompt:String):Null<String>
		return switch prompt.trim().split(" ")[0] {
			case "/tree": "run.tree";
			case "/snap": "run.snap";
			case "/check": "build.check";
			case "/read": "project.read";
			case _: null;
		}

	public function ask(prompt:String, context:AgentContext, on:AgentEvent->Void) {
		var words = prompt.trim().split(" ").filter(w -> w != "");
		var tool = LocalAgent.tool(prompt);
		if (tool == null) {
			var url = studio.mcp?.url ?? "(no MCP server)";
			on(Text('No agent is connected. Drive the studio from an agent over MCP at $url (project.read, project.patch, build.check, run.snap, run.tree), or try /tree, /snap, /check, /read <file>.'));
			on(Done("end_turn"));
			return;
		}
		var args:Dynamic = {};
		if (tool == "project.read" && words.length > 1) args.path = words[1];
		if ((tool == "run.tree" || tool == "run.snap") && context.screen != null) args.screen = context.screen;
		var t = studio.tools;
		Async.launch(_ -> {
			var r = t.call(tool, args);
			var texts = [for (c in r.content) if (c.type == "text") (c.text : String)];
			// (one line: its whitespace collapsed, at most 240 characters)
			var first = ~/\s+/g.replace(texts.length == 0 ? "" : texts[texts.length - 1], " ");
			on(Text('$tool: ' + (first.length > 240 ? first.substr(0, 240) + "…" : first)));
			on(Done("end_turn"));
		});
	}
}
