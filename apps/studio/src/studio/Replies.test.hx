package studio;

import helder.markdown.Doc;
import helder.test.Test;
import studio.Replies.Spot;

// The chat's reading of a reply: chips for screens and the project's
// files, a code span naming a file a chip, tools folded past the last few
function tests() {
	describe("Replies", () -> {
		test("chips: a screen's, a file's, else a link", () -> {
			equals(Replies.chip("studio:screen/Pond", "/p"), "chip-screen");
			equals(Replies.place("studio:screen/Fish%20list"), Screen("Fish list"));
			equals(Replies.place("studio:frame/pages/pond.helder#Pond"), Frame("pages/pond.helder", "Pond"));
			equals(Replies.chip("studio:group/pond.helder#Bobbers", "/p"), "chip-group");
			equals(Replies.place("studio:group/pond.helder#Three%20bobbers"), Group("pond.helder", "Three bobbers"));
			equals(Replies.place("studio:frame/pond.helder"), null);
			equals(Replies.chip("pond.helder:41", "/p"), "chip-file");
			equals(Replies.chip("https://helder.build", "/p"), null);
		});
		test("a code span naming a file of the project: a file's chip", () -> {
			var d = Replies.parse("Drawn in `pond.helder:41`, not `x + 1`.", "/p", f -> f == "/p/pond.helder");
			equals(d.blocks, [Paragraph([Text("Drawn in "), Link("pond.helder:41", "", [Text("pond.helder:41")]), Text(", not "), CodeSpan("x + 1"), Text(".")])]);
		});
		test("tools: the last few, the rest folded", () -> {
			equals(Replies.tools([1, 2, 3, 4], false), {folded: 0, shown: [1, 2, 3, 4]});
			equals(Replies.tools([1, 2, 3, 4, 5, 6], false), {folded: 3, shown: [4, 5, 6]});
			equals(Replies.tools([1, 2, 3, 4, 5, 6], true).shown.length, 6);
			equals([Replies.mark("completed"), Replies.mark("in_progress"), Replies.mark("failed")], ["✓", "◌", "✗"]);
		});
	});
}
