package studio;

import haxe.Json;
import helder.test.Test;

// studio.ask over the studio's tools, and <Group> on the canvas (natively:
// a design file of a group of three frames): the question's id at once, a
// pick in the card delivered with the agent's next tool result; wait's
// pending; the user's own words; the group's frames side by side
function tests() {
	describe("Asks", () -> {
		#if !(hxmc.target == "wasm32-wasi")
		final sketch = '<Design>\n\t<Group title="Which start screen?" canvas:at="0 0">\n\t\t<Frame name="Dawn" width={200} height={300}><text>Dawn</text></Frame>\n\t\t<Frame name="Dusk" width={200} height={300}><text>Dusk</text></Frame>\n\t\t<Frame name="Night" width={200} height={300}><text>Night</text></Frame>\n\t</Group>\n</Design>\n';
		function studio(dir:String):Studio {
			helder.cli.TestCommand.mkdirs(dir);
			sys.io.File.saveContent('$dir/sketches.helder', sketch);
			var s = new Studio(dir, {});
			s.presence.arrive("a", "claude-code");
			return s;
		}
		function options():Array<Dynamic>
			return [for (n in ["Dawn", "Dusk", "Night"]) {id: n.toLowerCase(), label: n, frame: 'sketches.helder#$n'}];
		test("a group's frames side by side, 28 apart; its box", () -> {
			var s = studio("bin/asks-test-0");
			equals([for (r in s.layout.screens()) r.x], [0.0, 228.0, 456.0]);
			equals(s.groupAt(s.project.dir + "/sketches.helder", "Which start screen?"), {x: 0.0, y: 0.0, w: 656.0, h: 300.0});
		});
		test("asked: its id at once; picked: the answer with the next tool result", async(() -> {
			var s = studio("bin/asks-test-1");
			var r = s.tools.call("studio.ask", {question: "Which start screen?", options: options()}, "a");
			equals(r.isError, false);
			var id:String = Json.parse(r.content[0].text).id;
			equals(s.questions.open().length, 1);
			s.questions.pick(id, "dusk");
			equals(s.questions.get(id).answered, true);
			var next = s.tools.call("studio.focus", {}, "a");
			equals(next.content.length, 2);
			equals(next.content[1].text, 'The user answered "Which start screen?": Dusk. (picked: dusk)');
			equals(s.inbox.pending().length, 0);
		}));
		test("wait: pending past its time, the answer the inbox's then", async(() -> {
			var s = studio("bin/asks-test-2");
			Tools.WAIT = 0.2;
			var r = s.tools.call("studio.ask", {question: "Which start screen?", options: options(), wait: true}, "a");
			Tools.WAIT = 600;
			var a:Dynamic = Json.parse(r.content[0].text);
			equals(a.pending, true);
			s.questions.pick(a.id, "night");
			var inbox = s.tools.call("studio.inbox", {}, "a");
			equals(inbox.content[0].text, 'The user answered "Which start screen?": Night. (picked: night)');
		}));
		test("the user's own words; a frame not on the canvas", async(() -> {
			var s = studio("bin/asks-test-3");
			var id:String = Json.parse(s.tools.call("studio.ask", {question: "Which start screen?", options: options()}, "a").content[0].text).id;
			s.questions.replyTo(id);
			s.ask("Dusk, but warmer");
			equals(s.questions.get(id).text, "Dusk, but warmer");
			equals(s.inbox.pending()[0].text, 'The user answered "Which start screen?": Dusk, but warmer.');
			var bad = s.tools.call("studio.ask", {question: "Which?", options: [{label: "X", frame: "sketches.helder#Nope"}]}, "a");
			equals(bad.isError, true);
		}));
		#end
	});
}
