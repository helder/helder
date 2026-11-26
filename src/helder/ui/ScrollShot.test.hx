package helder.ui;

import helder.test.Test;
import helder.view.Render;

// The compositor's shot of the scrollers: one in a subtree that takes no
// input (pointer-events none, hidden: a closed view kept drawn transparent
// over the page) is none of its, so a wheel there scrolls the page as the
// program's own hit test sends it; one taking input again inside is
function tests() {
	describe("ScrollShot", () -> {
		// (the scrollers the shot has, by tag, in paint order)
		function scrollers(ui:Ui):Array<String> {
			var shot = new ScrollShot();
			ScrollShot.take(ui, shot);
			return [for (i in 0...shot.count) if (shot.entries[i].kind == ScrollShot.SCROLLER) shot.entries[i].node.tag];
		}
		test("a scroller that takes no input is not the compositor's; the page under it is", () -> {
			var ui = new Ui(null, 300, 200), on = helder.view.graph.Graph.signal("none"), shown = helder.view.graph.Graph.signal("visible");
			var dispose = Render.render(Fixture.page(on, shown), ui.root);
			ui.update();
			equals(scrollers(ui), ["page"]);
			equals(ui.hit(150, 100) != null && isIn(ui.hit(150, 100), "page"), true);
			// (taking input again inside: its own)
			on("auto");
			helder.view.graph.Graph.flush();
			ui.update();
			equals(scrollers(ui), ["page", "closed-scroll"]);
			// (hidden: none again)
			shown("hidden");
			helder.view.graph.Graph.flush();
			ui.update();
			equals(scrollers(ui), ["page"]);
			dispose();
		});
	});
}

private function isIn(n:Null<Node>, tag:String):Bool {
	while (n != null) {
		if (n.tag == tag) return true;
		n = n.parent;
	}
	return false;
}

private class Fixture implements helder.view.Markup {
	public static function page(on:helder.view.graph.Read<String>, shown:helder.view.graph.Read<String>)
		return <view width={300} height={200}>
			<scroll tag="page" position="absolute" inset={0}><view height={1000} flexShrink={0}/></scroll>
			<view tag="closed" position="absolute" inset={0} pointerEvents="none" visibility={shown()}>
				<scroll tag="closed-scroll" position="absolute" inset={0} pointerEvents={on()}><view height={1000} flexShrink={0}/></scroll>
			</view>
		</view>;
}
