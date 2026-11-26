package helder.ui;

import helder.test.Choices;
import helder.test.Gen;
import helder.test.Test;
import helder.ui.view.UiFlow.VirtualList;
import helder.view.Render;
import helder.view.graph.Graph;

// A VirtualList against an array of ids (a stateful property, headless):
// ids put in, taken out, moved and replaced, rows of their own heights,
// wheeled, resized and scrolled to. After each step its rows are the
// array's (each made row's item the id at its index), the window's rows
// made and laid out one under the other at their heights, the scroll
// within the content, and a row scrolled to in view.
function tests() {
	test("a VirtualList's rows against an array under splices and scrolls", () -> stateful({
		setup: () -> new Fixture(),
		steps: [
			{name: "insert", run: (f, c) -> f.insert(c.draw(int(0, 1 << 20)), c.draw(oneOf([int(1, 3), int(1, 60)])))},
			{name: "remove", run: (f, c) -> f.remove(c.draw(int(0, 1 << 20)), c.draw(oneOf([int(1, 3), int(1, 60)]))), when: f -> f.ids.length > 0},
			{name: "move", run: (f, c) -> f.move(c.draw(int(0, 1 << 20)), c.draw(int(0, 1 << 20))), when: f -> f.ids.length > 1},
			{name: "replace", run: (f, c) -> f.replace(c.draw(int(0, 1 << 20))), when: f -> f.ids.length > 0},
			{name: "wheel", run: (f, c) -> f.wheel(c.draw(int(-3000, 3000)))},
			{name: "resize", run: (f, c) -> f.resize(c.draw(int(40, 900)))},
			{name: "scroll to", run: (f, c) -> f.scrollTo(c.draw(int(0, 1 << 20)), c.draw(pick(["auto", "start", "center", "end"]))),
				when: f -> f.ids.length > 0}
		],
		check: f -> f.check(),
		teardown: f -> f.dispose()
	}, {cases: 60, steps: 25}));
}

// (a row's height: its id's)
private function height(id:Int):Float
	return 20 + (id * 7) % 5 * 12;

private class Fixture {
	public var ids = [for (i in 0...200) i];

	final ui:Ui;
	final list:VirtualScroll;
	final each = Graph.signal([for (i in 0...200) i]);
	final close:() -> Void;
	var next = 200;
	var shown = -1;

	public function new() {
		Ui.now = () -> 0;
		ui = new Ui(new helder.story.StoryText(), 300, 400);
		var v:Null<VirtualScroll> = null;
		close = Render.render(<view flexGrow={1}>
			<VirtualList each={each} by={id -> id} keep={8} ref={r -> v = r}>
				{(id, i) -> <view height={height(id())}/>}
			</VirtualList>
		</view>, ui.root);
		list = v;
		settle();
	}

	public function insert(at:Int, n:Int) {
		at %= ids.length + 1;
		for (k in 0...n)
			ids.insert(at + k, next++);
		write();
	}

	public function remove(at:Int, n:Int) {
		at %= ids.length;
		ids.splice(at, n);
		write();
	}

	public function move(from:Int, to:Int) {
		var id = ids.splice(from % ids.length, 1)[0];
		ids.insert(to % (ids.length + 1), id);
		write();
	}

	public function replace(at:Int) {
		ids[at % ids.length] = next++;
		write();
	}

	public function wheel(dy:Int) {
		var b = list.windowBounds();
		ui.wheel(b.x + b.width / 2, b.y + b.height / 2, 0, dy);
		settle();
	}

	public function resize(h:Int) {
		ui.resize(300, h);
		settle();
	}

	public function scrollTo(i:Int, align:String) {
		shown = i % ids.length;
		list.scrollToIndex(shown, align);
		settle();
	}

	public function check() {
		equals(list.count, ids.length, "count");
		var last = -1;
		for (r in list.rows()) {
			assert(r.index > last && r.index < ids.length, 'a row made at ${r.index} after $last of ${ids.length}');
			last = r.index;
			var item:Null<Int> = (r.data : Dynamic).item;
			if (r.index < ids.length && item != ids[r.index]) fail('row ${r.index}: ${item}, the array ${ids[r.index]}');
		}
		var max = @:privateAccess Scrolling.maxScroll(list, false);
		assert(list.scrollY >= 0 && list.scrollY <= max + 0.5, 'scrollY ${list.scrollY} outside 0 to $max');
		var top:Null<Float> = null;
		for (i in list.first...list.end) {
			var r = list.rowAt(i);
			if (r == null) {
				fail('row $i in the window (${list.first} to ${list.end}) not made');
				return;
			}
			var b = r.node.windowBounds();
			approx(b.height, height(ids[i]), 0.5, 'row $i\'s height');
			if (top != null) approx(b.y, top, 0.5, 'row $i under the one before');
			top = b.y + b.height;
		}
		if (shown < 0) return;
		var i = shown;
		shown = -1;
		var r = list.rowAt(i);
		if (r == null) {
			fail('row $i scrolled to, not made');
			return;
		}
		var b = r.node.windowBounds(), view = list.windowBounds();
		assert(b.y + b.height > view.y && b.y < view.y + view.height, 'row $i scrolled to at ${b.y} to ${b.y + b.height}, the view ${view.y} to ${view.y + view.height}');
	}

	public function dispose()
		close();

	function write() {
		each(ids.copy());
		settle();
	}

	function settle() {
		Graph.flush();
		ui.update();
		ui.update();
	}
}
