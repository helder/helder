package helder.ui;

import helder.os.App;
import helder.test.Test;
import helder.ui.Stack;
import helder.ui.Ui;
import helder.view.Render;
import helder.view.graph.Graph;

// Stack: its entries mounted once, kept below the top (hidden once covered),
// a popped one disposed after its exit; a still entry faded in place and
// popped so, the slide the stack's again after; the system's back while
// deep (App.back, App.backDepth), the app's own onBack again at the root
// and once it is gone
function tests() {
	function nav():Router
		return new Router()
			.route("/", _ -> <view tag="home" focusable/>)
			.route("/item/:id", p -> <view tag={"item-" + p.id} focusable/>);
	function shown(ui:Ui):String
		return [for (n in ui.root.find("stack").children) if (n.tag == "screen") n.children[0].tag + (n.visible() ? "" : " (hidden)")].join(", ");
	describe("Stack", () -> {
		test("entries kept below the top, a popped one disposed after its exit", () -> {
			var ui = new Ui(null, 300, 400), r = nav();
			var dispose = Render.render(<Stack router={r} transition={Slide}/>, ui.root);
			equals(shown(ui), "home");
			r.go("/item/1");
			Graph.flush();
			Clock.tick(Clock.now + 0.1);
			equals(shown(ui), "home, item-1");
			Clock.finish();
			equals(shown(ui), "home (hidden), item-1");
			equals(ui.focus?.tag, "item-1");
			r.back();
			Graph.flush();
			Clock.tick(Clock.now + 0.1);
			equals(shown(ui), "home, item-1");
			Clock.finish();
			equals(shown(ui), "home");
			equals(ui.focus?.tag, "home");
			dispose();
		});
		test("a still entry: faded in place, popped so; the slide after", () -> {
			var ui = new Ui(null, 300, 400), r = nav();
			var dispose = Render.render(<Stack router={r} transition={Slide}/>, ui.root);
			function screens()
				return [for (n in ui.root.find("stack").children) if (n.tag == "screen") n];
			function still(n:helder.ui.Node)
				return n.style.transform == null || n.style.transform.isIdentity();
			r.go("/item/1", true);
			Graph.flush();
			Clock.tick(Clock.now + 0.01);
			Clock.tick(Clock.now + 0.11);
			var s = screens();
			assert(still(s[0]) && still(s[1]), "not slid");
			assert(s[1].style.opacity > 0.5 && s[1].style.opacity < 1, "faded in: " + s[1].style.opacity);
			assert(s[0].style.opacity > 0 && s[0].style.opacity < 0.5, "faded out: " + s[0].style.opacity);
			Clock.finish();
			equals(shown(ui), "home (hidden), item-1");
			r.back();
			Graph.flush();
			Clock.tick(Clock.now + 0.01);
			Clock.tick(Clock.now + 0.11);
			s = screens();
			assert(still(s[0]) && still(s[1]), "popped in place");
			Clock.finish();
			equals(shown(ui), "home");
			r.go("/item/2");
			Graph.flush();
			Clock.tick(Clock.now + 0.01);
			Clock.tick(Clock.now + 0.11);
			assert(!still(screens()[1]), "slid");
			Clock.finish();
			dispose();
		});
		test("the system's back pops while deep; the app's own onBack after", () -> {
			var ui = new Ui(null, 300, 400), r = nav();
			var own = () -> false;
			App.onBack = own;
			var dispose = Render.render(<Stack router={r} transition={None}/>, ui.root);
			equals(App.backDepth, 0);
			r.go("/item/1");
			r.go("/item/2");
			Graph.flush();
			equals(App.backDepth, 2);
			equals(@:privateAccess App.back(), true);
			equals(r.path(), "/item/1");
			equals(App.backDepth, 1);
			equals(@:privateAccess App.back(), true);
			equals(App.backDepth, 0);
			assert(App.onBack == own);
			r.go("/item/3");
			Graph.flush();
			equals(App.backDepth, 1);
			dispose();
			assert(App.onBack == own);
			equals(App.backDepth, 0);
			App.onBack = null;
		});
	});
}
