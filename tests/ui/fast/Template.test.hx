package ui.fast;

import helder.test.Test;
import helder.ui.fast.FastTags.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// Markup on fast nodes: an element's fixed attributes set once, on a
// template its mounts clone (FastRenderer.cloneNode), each clone its own.
function tests() {
	describe("markup templates", () -> {
		test("a list's rows: clones of one template, each its own", () -> {
			var ui = new helder.ui.Ui(null, 300, 200), tree:Null<helder.ui.fast.Tree> = null;
			var items = signal([1, 2, 3]), picked = signal(2);
			Render.render(<Fast ref={t -> tree = t}>
				<view tag="list">
					<For each={items()}>{i -> <view tag="row" padding="4 6" role="listitem" aria-selected={picked() == i()} data-state={picked() == i() ? "selected" : null}>
						<text>{"Row " + i()}</text>
					</view>}</For>
				</view>
			</Fast>, ui.root);
			flush();
			ui.update();
			var list = tree.root.children()[0], rows = list.children().filter(r -> r.tag == "row");
			equals(rows.length, 3);
			equals([for (r in rows) r.tag].join(","), "row,row,row");
			// (one look for all: one resolution)
			equals(@:privateAccess rows[0].box.style == @:privateAccess rows[2].box.style, true);
			equals(Std.string(@:privateAccess rows[0].box.style.model().padding[1]), "Px(6)");
			// (their own semantics: the template's copied, not shared)
			equals([for (r in rows) r.semantics.selected].join(","), "false,true,false");
			picked(3);
			flush();
			equals([for (r in rows) r.semantics.selected].join(","), "false,false,true");
			equals(rows[0].semantics.role, ListItem);
			items([1, 2, 3, 4]);
			flush();
			var now = list.children().filter(r -> r.tag == "row");
			equals(now.length, 4);
			equals(now[3].semantics.selected, false);
		});
	});
}
