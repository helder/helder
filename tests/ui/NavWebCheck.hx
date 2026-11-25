import helder.ui.nav.Routes;
import helder.ui.Stack;
import helder.ui.UiWindow;
import helder.view.*;

// helder.ui's Stack in a browser (nav-web.mjs): the key "n" pushes the next
// item (/item/1, /item/2...), each frame whose top changed prints it ("at
// /item/1 1": its path and depth), so that the page checks the URL each
// push makes, the history's back popping and a reload restoring the screen
class NavWebCheck implements Markup {
	static function main() {
		var w = new UiWindow("NavWebCheck", 200, 120);
		final nav = new Routes();
		nav.route("/", _ -> <view tag="home" grow={1}/>).route("/item/:id", p -> <view tag={"item-" + p.id} grow={1}/>);
		Render.render(<Stack router={nav} transition={None}/>, w.root);
		var n = 0, last = "";
		w.root.onKeyDown = e -> if (e.key == "n".code) nav.go("/item/" + (++n));
		w.onFrame = () -> {
			var s = "at " + nav.path() + " " + nav.depth();
			if (s != last) Sys.println(last = s);
		};
		UiWindow.run();
	}
}
