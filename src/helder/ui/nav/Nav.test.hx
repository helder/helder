package helder.ui.nav;

import helder.test.Test;
import helder.ui.Node;
import helder.ui.ScreenContext;
import helder.ui.SizeClass;
import helder.ui.Stack;
import helder.ui.NavScreen;
import helder.ui.Sheet;
import helder.ui.TextNode;
import helder.ui.Ui;
import helder.ui.actions.Actions;
import helder.ui.gesture.LongPress;
import helder.ui.menu.Menu.MenuItem;
import helder.ui.view.UiFlow.VirtualGrid;
import helder.view.Render;
import helder.view.graph.Graph;
import helder.view.graph.Graph.*;

// The compact pieces: the size class from the surface's width; a
// NavScreen's bars (its title in the Stack, the back button titled by the
// screen below, its long press's menu popping several, the large title
// moving into the bar as the content scrolls); a sheet opened to its
// detent, dragged to the other and down to dismiss; a long press winning
// over the click; select mode's taps and its run
function tests() {
	var t = 0.0;
	function ui(w:Float, h:Float):Ui {
		t = 0;
		Ui.now = () -> t;
		var u = new Ui(new helder.story.StoryText(), w, h);
		return u;
	}
	function press(u:Ui, n:Node, hold = 0.0) {
		var b = n.windowBounds(), x = b.x + b.width / 2, y = b.y + b.height / 2;
		u.pointerDown(x, y, 1, 1, Touch);
		if (hold > 0) {
			t += hold;
			Clock.tick(Clock.now + hold);
		}
		u.pointerUp(x, y, 1, 1);
		Graph.flush();
		u.update();
	}
	function text(n:Null<Node>):String
		return n == null ? "(none)" : Std.isOfType(n, TextNode) ? (cast n : TextNode).text : [for (c in n.children) text(c)].join("");
	describe("size classes", () -> {
		test("from the surface's width", () -> {
			equals(SizeClass.of(390), Compact);
			equals(SizeClass.of(820), Medium);
			equals(SizeClass.of(1180), Expanded);
			var u = ui(390, 844);
			Graph.flush();
			equals(SizeClass.current.peek(), Compact);
			u.resize(820, 1180);
			Graph.flush();
			equals(SizeClass.current.peek(), Medium);
			u.resize(1180, 820);
			Graph.flush();
			equals(SizeClass.current.peek(), Expanded);
			equals(ScreenContext.current.width.peek(), 1180.0);
		});
	});
	describe("NavScreen", () -> {
		function nav():Router
			return new Router()
				.route("/", _ -> <NavScreen title="Browse" large><view tag="home" height={2000} shrink={0}/></NavScreen>)
				.route("/a", _ -> <NavScreen title="Photos" large><view height={2000} shrink={0}/></NavScreen>)
				.route("/b", _ -> <NavScreen title="Trip"><view tag="trip" height={100}/></NavScreen>);
		function top(u:Ui):Node {
			var screens = [for (n in u.root.find("stack").children) if (n.tag == "screen" && n.visible()) n];
			return screens[screens.length - 1];
		}
		test("the back button names the screen below; its long press pops several", () -> {
			var u = ui(390, 844), r = nav();
			var dispose = Render.render(<Stack router={r} transition={None}/>, u.root);
			u.update();
			equals(top(u).find("nav-back"), null);
			r.go("/a");
			r.go("/b");
			Graph.flush();
			u.update();
			equals(text(top(u).find("nav-back")), "Photos");
			equals(text(top(u).find("nav-title")), "Trip");
			var bb = top(u).find("nav-back");
			press(u, bb, LongPress.DURATION + 0.1);
			var menu = u.overlay.find("touch-menu-layer");
			equals([for (n in menu.find("touch-menu").children) text(n)], ["Photos", "Browse"]);
			press(u, menu.find("menu-Browse"));
			equals(r.path(), "/");
			equals(u.overlay.children.length, 0);
			r.go("/a");
			Graph.flush();
			u.update();
			press(u, top(u).find("nav-back"));
			equals(r.path(), "/");
			dispose();
		});
		test("the large title moves into the bar as the content scrolls", () -> {
			var u = ui(390, 844), r = nav();
			var dispose = Render.render(<Stack router={r} transition={None}/>, u.root);
			u.update();
			u.update();
			var s = top(u).find("nav-scroll"), title = top(u).find("nav-title");
			equals(title.style.opacity, 0.0);
			// (the content below the bar and the large title)
			equals(s.style.paddingTop, 44.0);
			assert(top(u).find("home").absY > 90);
			u.wheel(195, 400, 0, 200);
			Graph.flush();
			u.update();
			equals(title.style.opacity, 1.0);
			dispose();
		});
	});
	describe("Sheet", () -> {
		test("opens to its first detent, drags to large, down to dismiss", () -> {
			var u = ui(390, 844), open = signal(false), at = signal(Medium);
			var dispose = Render.render(<view grow={1}>
				<Sheet open={open} detents={[Medium, Large]} detent={at} onDismiss={() -> open(false)} label="Info"><text tag="body">Info</text></Sheet>
			</view>, u.root);
			u.update();
			open(true);
			Graph.flush();
			Clock.finish();
			u.update();
			var sheet = u.overlay.find("sheet");
			var b = sheet.windowBounds();
			// (Medium: about half the window shown)
			assert(Math.abs(b.y - 422) < 2);
			// (dragged up past half the way: Large)
			var g = sheet.find("sheet-grabber").windowBounds();
			u.pointerDown(195, g.y + 2, 1, 1, Touch);
			for (k in 1...9) {
				t += 0.05;
				u.pointerMove(195, g.y + 2 - k * 40, 1);
			}
			u.pointerUp(195, g.y + 2 - 320, 1, 1);
			Clock.finish();
			Graph.flush();
			u.update();
			equals(at.peek(), Large);
			assert(sheet.windowBounds().y < 120);
			// (and down, fast: dismissed, gone once it slid away)
			u.pointerDown(195, sheet.windowBounds().y + 4, 1, 1, Touch);
			for (k in 1...6) {
				t += 0.01;
				u.pointerMove(195, sheet.windowBounds().y + 4 + k * 60, 1);
			}
			u.pointerUp(195, 700, 1, 1);
			Graph.flush();
			equals(open.peek(), false);
			Clock.finish();
			Graph.flush();
			u.update();
			equals(u.overlay.find("sheet"), null);
			dispose();
		});
		test("a popover from its anchor on a wider screen", () -> {
			var u = ui(820, 1180), open = signal(false), button:Null<Node> = null;
			var dispose = Render.render(<view grow={1}>
				<view tag="info" width={44} height={44} ref={n -> button = n}/>
				<Sheet open={open} anchor={() -> button} onDismiss={() -> open(false)}><text>Info</text></Sheet>
			</view>, u.root);
			u.update();
			open(true);
			Graph.flush();
			u.update();
			assert(u.overlay.find("sheet-popover") != null);
			equals(u.overlay.find("sheet"), null);
			open(false);
			Graph.flush();
			equals(u.overlay.children.length, 0);
			dispose();
		});
	});
	describe("long press", () -> {
		test("held still it wins: no click; moved first it fails", () -> {
			var u = ui(300, 300), log = [];
			var n = new Node("card");
			n.style.height = 100;
			n.onClick = _ -> log.push("click");
			u.root.append(n);
			n.addGesture(new LongPress()).onGesture = g -> log.push(g.state == Began ? "Began" : g.state == Ended ? "Ended" : "other");
			u.update();
			press(u, n, 0.6);
			equals(log, ["Began", "Ended"]);
			log.resize(0);
			press(u, n);
			equals(log, ["click"]);
			log.resize(0);
			u.pointerDown(50, 50, 1, 1, Touch);
			u.pointerMove(50, 80, 1);
			Clock.tick(Clock.now + 0.6);
			u.pointerUp(50, 80, 1, 1);
			equals(log, []);
		});
		test("a context menu: the model's items, dispatched from the node", () -> {
			var u = ui(390, 844), log = [];
			actions("nav_test", NavTestAction);
			var n = new Node("tile");
			n.style.height = 100;
			n.on(NavTestAction, a -> {
				log.push(Std.string(a));
				true;
			});
			u.root.append(n);
			helder.ui.menu.ContextMenu.attach(n, () -> [Item("Open", Open), Separator, Item("Move to Trash", Trash)], () -> <view tag="lifted" height={100}/>,
				a -> a == Trash);
			u.update();
			press(u, n, 0.6);
			var layer = u.overlay.find("touch-menu-layer");
			assert(layer.find("lifted") != null);
			equals(layer.find("menu-Move to Trash").slot, "touch-menu-item-danger");
			press(u, layer.find("menu-Open"));
			equals(log, ["Open"]);
			equals(u.overlay.children.length, 0);
		});
	});
	describe("select mode", () -> {
		test("a tap toggles; a drag sideways selects a run", () -> {
			var u = ui(390, 844), grid:Null<helder.ui.GridScroll> = null;
			var files = [for (i in 0...12) "f" + i];
			var dispose = Render.render(<view grow={1}>
				<VirtualGrid each={files} by={f -> f} cellWidth={120} cellHeight={120} gap={0} padding={0} selectMode={true} ref={g -> grid = g}>
					{(f, i) -> <view grow={1} tag={f()}/>}
				</VirtualGrid>
			</view>, u.root);
			u.update();
			u.update();
			equals(grid.columns, 3);
			press(u, u.root.find("f1"));
			press(u, u.root.find("f4"));
			equals(grid.selection.keys(), ["f1", "f4"]);
			press(u, u.root.find("f1"));
			equals(grid.selection.keys(), ["f4"]);
			// (from f6 across to f8, then down a row to f11: f6 to f11)
			var a = u.root.find("f6").windowBounds(), b = u.root.find("f8").windowBounds(), c = u.root.find("f11").windowBounds();
			u.pointerDown(a.x + 20, a.y + 60, 1, 1, Touch);
			for (k in 1...5) {
				t += 0.016;
				u.pointerMove(a.x + 20 + (b.x - a.x) * k / 4, a.y + 60, 1);
			}
			t += 0.016;
			u.pointerMove(c.x + 30, c.y + 60, 1);
			u.pointerUp(c.x + 30, c.y + 60, 1, 1);
			Graph.flush();
			equals(grid.selection.keys(), ["f4", "f6", "f7", "f8", "f9", "f10", "f11"]);
			dispose();
		});
	});
}

enum NavTestAction {
	Open;
	Trash;
}
