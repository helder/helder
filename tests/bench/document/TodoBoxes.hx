import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;
import BoxScreen;

// TodoDocument's screen as the engine's boxes made from code (BoxScreen,
// the "fast nodes" prototype): the same tree, its styles todo-app.css's as
// the cascade computes them, written as data by `DocumentBench boxstyles`
// (todo-app.boxes), so that no selector matching or cascade runs. What it
// still links (the size lane's measure of option C) is the question.
class TodoBoxes implements Markup {
	// (the tree, TodoDocument's: DocumentBench builds it as a document to write the styles)
	public static function spec():BoxSpec {
		function el(tag:String, cls:String, ?text:String, ?children:Array<BoxSpec>):BoxSpec
			return {tag: tag, attrs: [["class", cls]], text: text, children: children ?? []};
		var rows = [
			for (i in 0...20)
				el("view", i % 3 == 0 ? "row done" : "row", null,
					[el("view", "check"), el("text", "label", 'Task ${i + 1}: water the plants and call back'), el("view", "delete", "Remove")])
		];
		return el("view", "app", null, [
			el("text", "title", "todos"),
			el("view", "bar", null, [el("field", "input"), el("view", "button", "Add")]),
			el("scroll", "list", null, rows),
			el("text", "footer", "20 items left")
		]);
	}

	static function main() {
		var styles = new BoxStyles(Embed.text("tests/bench/document/todo-app.boxes"));
		var bb = new BoxBuild(styles), out = [];
		bb.box(spec(), null, out);
		var node = new BoxNode(out[0], bb.contexts);
		UiWindow.run(<Surface title="Todo" width={480} height={560}><view flexGrow={1}>{node}</view></Surface>);
	}
}
