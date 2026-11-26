package helder.ui;

import helder.os.Mods;
import helder.test.Choices;
import helder.test.Gen;
import helder.test.Test;
import helder.ui.view.UiFlow.VirtualGrid;
import helder.view.Render;
import helder.view.graph.Graph;

// A VirtualGrid under random input (a stateful property, headless):
// wheel scrolls, resizes, presses on cells (Shift, the secondary key),
// the keyboard's moves, items put in, taken out (the selection pruned, as
// its owner does) and moved. After each step the scroll stays within the
// content, the cells made are the items' at their places, the selection
// and the focus are items of the grid, and after a key the focused item's
// cell is in view.
function tests() {
	test("a VirtualGrid's scroll, selection and focus under random input", () -> stateful({
		setup: () -> new Fixture(),
		steps: [
			{name: "wheel", run: (f, c) -> f.wheel(c.draw(int(-2000, 2000)))},
			{name: "resize", run: (f, c) -> f.resize(c.draw(int(40, 900)), c.draw(int(40, 900)))},
			{name: "press", run: (f, c) -> f.press(c.draw(int(0, 999)), c.draw(pick(["", "shift", "meta", "control"])))},
			{name: "key", run: (f, c) -> f.key(c.draw(pick([for (k in KEYS.keys()) k])), c.draw(bool()))},
			{name: "insert", run: (f, c) -> f.insert(c.draw(int(0, 1 << 20)), c.draw(oneOf([int(1, 3), int(1, 40)])))},
			{name: "remove", run: (f, c) -> f.remove(c.draw(int(0, 1 << 20)), c.draw(oneOf([int(1, 3), int(1, 40)]))), when: f -> f.items.length > 0},
			{name: "move", run: (f, c) -> f.move(c.draw(int(0, 1 << 20)), c.draw(int(0, 1 << 20))), when: f -> f.items.length > 1}
		],
		check: f -> f.check(),
		teardown: f -> f.dispose()
	}, {cases: 60, steps: 30}));
	test("a grid made one cell high by a resize: Up shows the first cell whole", () -> {
		var f = new Fixture();
		f.resize(40, 70);
		f.key("up", false);
		f.check();
		f.dispose();
	});
}

private final KEYS = [
	"up" => Key.UP, "down" => Key.DOWN, "left" => Key.LEFT, "right" => Key.RIGHT,
	"home" => Key.HOME, "end" => Key.END, "page up" => Key.PAGE_UP, "page down" => Key.PAGE_DOWN
];
// (a modifier's key and its bit)
private final MODS = ["shift" => [Key.SHIFT, Mods.SHIFT], "meta" => [Key.META, Mods.META], "control" => [Key.CONTROL, Mods.CONTROL]];

private class Fixture {
	final ui:Ui;
	final grid:GridScroll;
	public var items = [for (i in 0...500) "f" + i];
	final each = Graph.signal([for (i in 0...500) "f" + i]);
	var next = 500;
	final close:() -> Void;
	var keyed = false;

	public function new() {
		Ui.now = () -> 0;
		ui = new Ui(new helder.story.StoryText(), 400, 300);
		var g:Null<GridScroll> = null;
		close = Render.render(<view flexGrow={1}>
			<VirtualGrid each={each} by={f -> f} cellWidth={90} cellHeight={70} ref={r -> g = r}>
				{(f, i) -> <view flexGrow={1}/>}
			</VirtualGrid>
		</view>, ui.root);
		grid = g;
		settle();
		ui.setFocus(grid);
	}

	public function wheel(dy:Int) {
		var b = grid.windowBounds();
		ui.wheel(b.x + b.width / 2, b.y + b.height / 2, 0, dy);
		settle();
	}

	public function insert(at:Int, n:Int) {
		at %= items.length + 1;
		for (k in 0...n)
			items.insert(at + k, "f" + next++);
		write();
	}

	public function remove(at:Int, n:Int) {
		items.splice(at % items.length, n);
		write();
		grid.selection.prune();
		settle();
	}

	public function move(from:Int, to:Int) {
		var f = items.splice(from % items.length, 1)[0];
		items.insert(to % (items.length + 1), f);
		write();
	}

	public function resize(w:Int, h:Int) {
		ui.resize(w, h);
		settle();
	}

	// (a press on a cell in view, the index modulo them: on its part shown)
	public function press(at:Int, mods:String) {
		var view = grid.windowBounds(), parts = [];
		for (r in grid.rows()) if (r.index >= grid.first && r.index < grid.end) for (n in r.node.children) {
			var b = n.windowBounds();
			var top = Math.max(b.y, view.y), bottom = Math.min(Math.min(b.y + b.height, view.y + view.height), ui.height);
			var left = Math.max(b.x, view.x), right = Math.min(Math.min(b.x + b.width, view.x + view.width), ui.width);
			if (bottom - top >= 1 && right - left >= 1) parts.push({x: (left + right) / 2, y: (top + bottom) / 2});
		}
		if (parts.length == 0) return;
		var p = parts[at % parts.length];
		var held = MODS[mods];
		if (held != null) ui.keyDown(held[0], held[1]);
		ui.pointerDown(p.x, p.y, 1, 1, Mouse);
		ui.pointerUp(p.x, p.y, 1, 1);
		if (held != null) ui.keyUp(held[0], 0);
		settle();
	}

	// (the focus in view after it only when the grid had it)
	public function key(name:String, shift:Bool) {
		keyed = @:privateAccess grid.focusWithin();
		ui.keyDown(KEYS[name], shift ? Mods.SHIFT : 0);
		settle();
	}

	public function check() {
		var max = @:privateAccess Scrolling.maxScroll(grid, false);
		assert(grid.scrollY >= 0 && grid.scrollY <= max + 0.5, 'scrollY ${grid.scrollY} outside 0 to $max');
		for (r in grid.rows()) {
			var g:{keys:Array<String>, cells:Array<Dynamic>} = r.data, start = r.index * grid.columns;
			equals(g.keys, items.slice(start, start + grid.columns), 'row ${r.index}\'s keys');
			equals([for (c in g.cells) c.item], items.slice(start, start + grid.columns), 'row ${r.index}\'s items');
		}
		var s = grid.selection;
		for (k in s.keys()) assert(items.contains(k), 'selected $k, not an item');
		equals(s.size(), s.keys().length, "the selection's size");
		if (s.focus != null) assert(items.contains(s.focus), 'focus on ${s.focus}, not an item');
		if (!keyed || s.focus == null) return;
		keyed = false;
		// (the focused item's cell made and within the grid's view)
		var i = s.focusIndex(), row = Std.int(i / grid.columns);
		var r = grid.rowAt(row);
		if (r == null || row < grid.first || row >= grid.end) {
			fail('the focused item $i not made after a key (rows ${grid.first} to ${grid.end})');
			return;
		}
		var cell = r.node.children[i % grid.columns].windowBounds(), view = grid.windowBounds();
		assert(cell.y >= view.y - 0.5 && cell.y + cell.height <= view.y + view.height + 0.5 || cell.height > view.height,
			'the focused item $i at ${cell.y} to ${cell.y + cell.height}, the view ${view.y} to ${view.y + view.height}');
	}

	public function dispose()
		close();

	function write() {
		each(items.copy());
		settle();
	}

	function settle() {
		Graph.flush();
		ui.update();
		ui.update();
	}
}
