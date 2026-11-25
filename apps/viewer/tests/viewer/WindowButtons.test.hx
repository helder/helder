package viewer;

import helder.os.Rect;
import helder.os.DragOperation;
import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Node;
import helder.ui.SafeArea;
import helder.ui.TextNode;
import helder.ui.Ui;
import helder.ui.WindowHost;
import helder.view.Render;
import helder.view.graph.Graph;

// The window's buttons never over the window's content: at every size
// from the window's least up (the shells each width shows: the browser,
// a tablet's, a phone's), macOS's at the start and Windows' and Linux's at
// the end, the browser in its grid, its list, a tablet's sidebar drawn
// over it, or a file full size,
// their rect meets no node a user reads or presses, as it is seen (within
// the scrollers clipping it, not see-through)
function tests() {
	describe("Window buttons", () -> {
		afterEach(() -> SafeArea.setTitlebar(null));
		for (kind in ["system", "windows"])
			for (full in [false, true])
				test('over no text nor control at any size (${kind == "system" ? "macOS" : "Windows, Linux"}, ${full ? "a file full size" : "the browser"})', () -> {
					var bad = [];
					// (the window's least size up: the tablet's shell to 1024, the browser's past it)
					var w = Shell.MIN_WIDTH;
					while (w <= 1500) {
						for (h in [Shell.MIN_HEIGHT, 560, 780])
							for (lay in ["grid", "list", "drawer"]) {
								var hit = overlaps(kind, w, h, full, lay);
								if (hit != "") bad.push('${w}x$h $lay: $hit');
							}
						w += w < 1100 ? 40 : 200;
					}
					equals(bad.join("\n"), "");
				});
	});
}

// (what the buttons' rect meets at that size: "" none)
function overlaps(kind:String, w:Float, h:Float, full:Bool, lay:String):String {
	Ui.now = () -> 0.0;
	var x = Fixtures.explorer();
	x.start("tests/fixtures/folder");
	if (lay == "list") x.browser.layout(List);
	// (a tablet's sidebar over the folder)
	if (lay == "drawer") x.sidebarOpen(true);
	if (full) x.open("photo 2.jpg");
	var ui = new Ui(new StoryText(), w, h);
	ui.window = new Host(kind);
	// (macOS's bar after its buttons at the left; Windows' to its buttons at the right)
	SafeArea.setTitlebar(kind == "system" ? {x: 78, y: 0, width: w - 78, height: 28} : {x: 0, y: 0, width: w - 138, height: 32});
	var dispose = Render.render(Shell.view(x), ui.root);
	for (_ in 0...3) {
		Graph.flush();
		ui.update();
	}
	var controls = ui.root.find("window-controls");
	if (controls == null) {
		dispose();
		return "no buttons";
	}
	var b = controls.windowBounds(), out = [];
	function walk(n:Node, clip:{x0:Float, y0:Float, x1:Float, y1:Float}) {
		if (n == controls || n.style.display == None || n.style.opacity == 0 || !n.visible()) return;
		var r = n.windowBounds();
		if (n.style.overflow != Visible) clip = {
			x0: Math.max(clip.x0, r.x),
			y0: Math.max(clip.y0, r.y),
			x1: Math.min(clip.x1, r.x + r.width),
			y1: Math.min(clip.y1, r.y + r.height)
		};
		// (a scrim's press, the window's whole, is not content: the buttons over it, as over any modal's)
		var scrim = n.tag != null && (StringTools.endsWith(n.tag, "scrim") || StringTools.endsWith(n.tag, "backdrop"));
		var shown = !scrim && (Std.isOfType(n, TextNode) && StringTools.trim((cast n : TextNode).text) != "" || n.focusable || n.onClick != null);
		if (shown) {
			var x0 = Math.max(Math.max(r.x, clip.x0), b.x), y0 = Math.max(Math.max(r.y, clip.y0), b.y);
			var x1 = Math.min(Math.min(r.x + r.width, clip.x1), b.x + b.width), y1 = Math.min(Math.min(r.y + r.height, clip.y1), b.y + b.height);
			if (x1 - x0 > 0.5 && y1 - y0 > 0.5) out.push(name(n));
		}
		for (c in n.children)
			walk(c, clip);
	}
	walk(ui.root, {x0: 0.0, y0: 0.0, x1: w, y1: h});
	dispose();
	return out.join(", ");
}

// (a node as the failure says it: its tag, else its text, else its parent's)
function name(n:Node):String {
	if (Std.isOfType(n, TextNode)) return '"' + (cast n : TextNode).text + '"';
	var a = n;
	while (a != null && (a.tag == null || a.tag == "view"))
		a = a.parent;
	return a == null ? "?" : a.tag;
}

private class Host implements WindowHost {
	final kind:String;

	public function new(kind:String)
		this.kind = kind;

	public function controls():String
		return kind;

	// (macOS's three buttons: 54 by 16)
	public function systemControls():Null<Rect> {
		var b = {x: 0.0, y: 0.0, width: 0.0, height: 0.0};
		b.width = 54;
		b.height = 16;
		return b;
	}

	public function placeControls(x:Float, y:Float) {}

	public function minimize() {}

	public function maximized():Bool
		return false;

	public function maximize(on:Bool) {}

	public function close() {}

	public function dragFiles(paths:Array<String>, image:Null<helder.image.Image>, offsetX:Float, offsetY:Float, allowed:Array<DragOperation>,
		done:DragOperation->Void):Bool
		return false;
}
