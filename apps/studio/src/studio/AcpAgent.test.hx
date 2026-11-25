package studio;

#if !(hxmc.target == "wasm32-wasi")
import haxe.Json;
import helder.async.*;
import helder.test.Test;
import studio.Agent;
import sys.FileSystem;
import sys.io.File;

// AcpAgent against a scripted agent (tests/studio/acp-agent.mjs, on node):
// a turn's events in order, the permission's answer reaching the agent,
// its reads of the studio's text and its write one entry of the history,
// a path outside the project refused; cancel; the process' end a failure,
// the next prompt starting it again
function tests() {
	describe("AcpAgent", () -> {
		test("a turn: its events, the answer, the write one edit", async(() -> {
			var w = workspace();
			var agent = new AcpAgent(fake(), w);
			var sel = {screen: "Home", file: w.dir + "/app.helder", start: w.docs.get(w.dir + "/app.helder").text.indexOf("<text"), tag: "text"};
			var events = turn(agent, "edit", {screen: "Home", selection: sel, problems: ["app.tsx:3: oops"], crashes: ["App/Bad: app.tsx:7: boom"]}, true);
			agent.close();
			var kinds = [for (e in events) e.getName()];
			equals(kinds, ["Text", "Thought", "Text", "Steps", "Tool", "Ask", "Tool", "Tool", "Text", "Done"]);
			equals(events[1], Thought("hmm"));
			equals(events[3], Steps([{text: "read", done: true}, {text: "write", done: false}]));
			equals(events[4], Tool("t1", "Edit app.helder", "edit", "pending"));
			equals(events[7], Tool("t1", "", "", "completed"));
			equals(events[9], Done("end_turn"));
			var report:Dynamic = switch events[8] {
				case Text(t): Json.parse(t);
				case _: null;
			}
			equals(report.permission, {outcome: "selected", optionId: "yes"});
			equals(report.line, '\t<text>Hello</text>');
			equals([report.wrote, report.outside, report.missing], ["ok", "error", -32601]);
			equals(report.servers, ["http helder-studio http://127.0.0.1:7340/mcp"]);
			equals(report.denied, AcpAgent.DENIED);
			equals(report.session, {tools: AcpAgent.TOOLS, strict: true, sources: [], settings: {disableClaudeAiConnectors: true, disableAllHooks: true}});
			equals(["Bash", "Write", "Agent", "Task", "Workflow", "Monitor"].filter(t -> !AcpAgent.DENIED.contains(t)), []);
			equals(report.link, "app.helder:2");
			equals(report.problems, "The studio's last build failed:\n- app.tsx:3: oops");
			equals(report.crashes, "It builds, but these screens threw when the studio ran them:\n- App/Bad: app.tsx:7: boom");
			var f = w.dir + "/app.helder";
			equals(w.docs.get(f).text, "<frame>\n\t<text>Hi</text>\n</frame>\n");
			var e = w.docs.undo();
			equals([e.by, e.label], ["Fake", "app.helder"]);
			equals(w.docs.get(f).text, "<frame>\n\t<text>Hello</text>\n</frame>\n");
			equals(w.docs.undo(), null);
		})).timeout(20);
		test("cancel: the question cancelled, the turn ends cancelled", async(() -> {
			var agent = new AcpAgent(fake(), workspace());
			var events = [];
			var done = false;
			agent.ask("wait", {screen: null, selection: null, problems: []}, e -> {
				events.push(e);
				switch e {
					case Ask(_, _, _): agent.cancel();
					case Done(_) | Failed(_): done = true;
					case _:
				}
			});
			while (!done)
				Async.delay(0.01);
			agent.close();
			equals(events.map(e -> e.getName()), ["Text", "Ask", "Text", "Done"]);
			equals(events[2], Text("cancelled"));
			equals(events[3], Done("cancelled"));
		})).timeout(20);
		test("the process ends: a failure with its log, then started again", async(() -> {
			var agent = new AcpAgent(fake(), workspace());
			var died = turn(agent, "die", {screen: null, selection: null, problems: []}, false);
			var message = switch died[died.length - 1] {
				case Failed(m): m;
				case _: "";
			}
			assert(message.indexOf("fake: about to die") > 0, message);
			var again = turn(agent, "wait", {screen: null, selection: null, problems: []}, false, true);
			agent.close();
			equals(again[again.length - 1], Done("cancelled"));
		})).timeout(20);
		test("started before the first prompt: it goes straight to the session", async(() -> {
			var agent = new AcpAgent(fake(), workspace());
			agent.boot();
			assert(agent.starting());
			while (agent.starting())
				Async.delay(0.01);
			assert(agent.bootedIn >= 0);
			var events = turn(agent, "markdown", {screen: null, selection: null, problems: []}, false);
			agent.close();
			equals(events[events.length - 1], Done("end_turn"));
		})).timeout(20);
		test("a start that fails: told, and the next prompt starts it again", async(() -> {
			var agent = new AcpAgent({name: "missing", cmd: "node", args: ["/no/such/agent.mjs"]}, workspace());
			var told:Null<String> = null;
			agent.boot(m -> told = m);
			while (agent.starting())
				Async.delay(0.01);
			assert(told != null && told.indexOf("missing: closed") == 0, told);
		})).timeout(20);
	});
}

// (the events of a prompt's turn, a question answered with the first option, or the turn cancelled)
@:coroutine private function turn(agent:AcpAgent, prompt:String, context:AgentContext, answer:Bool, cancel = false):Array<AgentEvent> {
	var events = [], done = false;
	agent.ask(prompt, context, e -> {
		events.push(e);
		switch e {
			case Ask(_, _, a): if (answer) a(0) else if (cancel) agent.cancel();
			case Done(_) | Failed(_): done = true;
			case _:
		}
	});
	while (!done)
		Async.delay(0.01);
	return events;
}

private function fake():Agents.AgentCommand {
	var script = FileSystem.exists("tests/studio/acp-agent.mjs") ? "tests/studio/acp-agent.mjs" : "../../tests/studio/acp-agent.mjs";
	return {name: "fake", cmd: "node", args: [FileSystem.fullPath(script)]};
}

private function workspace():AcpAgent.Workspace {
	FileSystem.createDirectory("bin/acp-test");
	var dir = FileSystem.fullPath("bin/acp-test").split("\\").join("/");
	File.saveContent(dir + "/app.helder", "<frame>\n\t<text>Hello</text>\n</frame>\n");
	return {dir: dir, docs: new Docs(), mcp: () -> "http://127.0.0.1:7340/mcp", snap: null};
}
#else
function tests() {}
#end
