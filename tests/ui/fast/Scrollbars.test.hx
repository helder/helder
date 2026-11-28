package ui.fast;

import helder.test.Test;
import helder.ui.fast.FastTags.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// A scroller's thumb: its length the view's share of the content, dragged
// to scroll it; with overlay bars, shown while it moves. (Its rows kept
// at their height: empty, CSS shrinks them to fit, their automatic minimum 0.)
function tests() {
	describe("scrollbars", () -> {
		test("a thumb: its size, dragged, overlay bars", () -> {
			var ui = new helder.ui.Ui(null, 300, 200), tree:Null<helder.ui.fast.Tree> = null;
			Render.render(<Fast ref={t -> tree = t}>
				<scroll tag="list" height={100} width={200}>
					<For each={[for (i in 0...20) i]}>{i -> <view height={20} flexShrink={0}/>}</For>
				</scroll>
			</Fast>, ui.root);
			flush();
			ui.update();
			var list = @:privateAccess tree.root.children()[0].box;
			@:privateAccess tree.fragmentOf(list);
			var t = @:privateAccess tree.thumbOf(list, false);
			// (a 96 px track, the view a quarter of the content: a 24 px thumb at the track's start)
			equals(t.rect.join(","), "192,2,6,24");
			equals(@:privateAccess tree.thumbOf(list, true), null);
			// (dragged 24 px down: a third of the way, the content scrolled by a third of its 300)
			ui.pointerMove(195, 10);
			ui.pointerDown(195, 10, 1);
			ui.pointerMove(195, 34);
			ui.pointerUp(195, 34, 1);
			equals((@:privateAccess tree.scrolls.get(helder.ui.box.Box.scrollKey(list)))[1], 100);
			// (overlay bars: none until it moves)
			ui.overlayBars = true;
			var fresh = new helder.ui.Ui(null, 300, 200), other:Null<helder.ui.fast.Tree> = null;
			fresh.overlayBars = true;
			Render.render(<Fast ref={t -> other = t}><scroll height={100}><For each={[for (i in 0...20) i]}>{i -> <view height={20} flexShrink={0}/>}</For></scroll></Fast>, fresh.root);
			flush();
			fresh.update();
			var b = @:privateAccess other.root.children()[0].box;
			equals(@:privateAccess other.shownOf(b), 0);
			fresh.wheel(50, 50, 0, 30);
			equals(@:privateAccess other.shownOf(b), 1);
		});
		test("scrollbarWidth: thin, two thirds as wide; none, no thumb", () -> {
			var ui = new helder.ui.Ui(null, 300, 200), tree:Null<helder.ui.fast.Tree> = null;
			Render.render(<Fast ref={t -> tree = t}>
				<scroll height={100} width={200} scrollbarWidth="thin"><For each={[for (i in 0...20) i]}>{i -> <view height={20} flexShrink={0}/>}</For></scroll>
				<scroll height={100} width={200} scrollbarWidth="none"><For each={[for (i in 0...20) i]}>{i -> <view height={20} flexShrink={0}/>}</For></scroll>
			</Fast>, ui.root);
			flush();
			ui.update();
			var kids = @:privateAccess tree.root.children();
			@:privateAccess tree.fragmentOf(kids[0].box);
			equals(@:privateAccess tree.thumbOf(kids[0].box, false).rect[2], 4);
			equals(@:privateAccess tree.thumbOf(kids[1].box, false), null);
		});
	});
}
