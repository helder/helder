package viewer;

import haxe.io.Bytes;
import helder.story.StoryText;
import helder.test.Gen;
import helder.test.Test;
import helder.ui.Clock;
import helder.ui.Key;
import helder.ui.Node;
import helder.os.Rect;
import helder.ui.Ui;
import helder.view.Render;
import helder.view.graph.Graph;
import viewer.Decode.Decoded;

// A PDF opened: its picture flying from the tile lands in the rect its
// first page shows in (clipped to its view, above the status line), never
// over the status line on the way, nothing moving after it lands; opened
// again after a page, a zoom or a scroll, it is on page 1 as it first
// opened, the open's picture what lands; no overlay scrollbar in any frame
// of an open; its page tag a field of the page's number, anything typed
// landing on a page or nowhere, the keys the document's after
function tests() {
	describe("PDF open", () -> {
		test("the page lands where it shows, never over the status line, still after", () -> property(c -> {
			w: c.draw(int(700, 1500)),
			h: c.draw(int(420, 1000)),
			shape: c.draw(pick(["portrait", "landscape", "tall", "strip"])),
			status: c.draw(bool()),
			before: c.draw(int(0, 30))
		}, k -> {
			var o = new Opened(k.w, k.h, shape(k.shape), k.status, k.before);
			var boxes = o.open();
			var bar = o.rect("status"), landed = o.shows();
			assert(landed != null, "the page shown");
			// (its tile out of view: no flight, the file shown at once)
			if (boxes.length == 0) return;
			var last = boxes[boxes.length - 1];
			if (bar != null) for (i in 0...boxes.length)
				assert(!overlaps(boxes[i], bar), 'frame $i: ${str(boxes[i])} over the status line ${str(bar)}');
			assert(near(last, landed), 'landed at ${str(last)}, the page shows at ${str(landed)}');
			// (nothing moving after)
			for (_ in 0...20) {
				o.frames(1);
				assert(near(o.shows(), landed), 'moved after: ${str(o.shows())}');
			}
		}, {cases: 60}));
		test("opened again: on page 1 as it first opened, no scrollbar in any frame", () -> stateful({
			setup: () -> {
				var o = new Opened(1100, 700, shape("portrait"), true, 0);
				o.open();
				o;
			},
			steps: [
				{name: "a page", run: (o, c) -> if (o.x.full.value) {
					o.doc().goTo(c.draw(int(0, 11)));
					o.frames(c.draw(int(1, 20)));
				}},
				{name: "scroll", run: (o, c) -> if (o.x.full.value) o.wheel(c.draw(int(-900, 900)))},
				{name: "zoom", run: (o, c) -> if (o.x.full.value) {
					o.doc().zoomBy(c.draw(pick([0.5, 0.8, 1.25, 2.0])), 200, 200);
					o.frames(5);
				}},
				{name: "close", run: (o, c) -> if (o.x.full.value) {
					o.x.close();
					o.frames(c.draw(int(1, 60)));
				}},
				{name: "open", run: (o, c) -> if (!o.x.full.value) {
					o.open();
					var d = o.doc(), s = o.ui.root.find("pdf-scroll");
					equals(d.page.value, 0, "page 1");
					equals(s.scrollY, 0.0, "at the top");
					equals(d.zoom.value, d.layout.auto(), "auto");
					equals(o.barsSeen, 0.0, "no scrollbar shown");
				}}
			]
		}, {cases: 40, steps: 14}));
		test("a typed page: a page's index, clamped, or none", () -> property(c -> {
			text: c.draw(string(pick(["0", "1", "2", "7", "9", " ", "-", "+", ".", "e", "x"]), 0, 7)),
			pages: c.draw(int(1, 500))
		}, k -> {
			var r = PdfDoc.typed(k.text, k.pages), t = StringTools.trim(k.text);
			if (!~/^[0-9]+$/.match(t)) equals(r, null) else {
				var n = Std.parseFloat(t);
				equals(r, Std.int(Math.max(1, Math.min(n, k.pages))) - 1);
			}
		}, {cases: 300}));
		test("the page tag: a field of the page, selected; typed, then Enter, Escape or left", () -> property(c -> {
			text: c.draw(string(pick(["0", "3", "5", "9", "1", " ", "-", "a"]), 0, 4)),
			end: c.draw(pick(["enter", "escape", "left"])),
			from: c.draw(int(0, 11))
		}, k -> {
			var o = new Opened(1100, 700, shape("portrait"), false, 0);
			o.open();
			var d = o.doc();
			d.goTo(k.from);
			o.frames(5);
			var before = d.page.value;
			o.press("page-indicator");
			var f:helder.ui.widgets.TextField = cast o.ui.root.find("page-field");
			assert(f != null, "a field");
			equals(o.ui.focus, (f : Node));
			equals([f.selectionStart, f.selectionEnd], [0, Std.string(before + 1).length]);
			o.ui.textInput(k.text);
			o.frames(1);
			switch k.end {
				case "enter":
					o.ui.keyDown(Key.ENTER, 0);
				case "escape":
					o.ui.keyDown(Key.ESCAPE, 0);
				case _:
					o.ui.setFocus(null);
			}
			o.frames(20);
			var want = k.end == "enter" ? PdfDoc.typed(k.text == "" ? Std.string(before + 1) : k.text, d.pages) ?? before : before;
			equals(d.page.value, want);
			equals(o.ui.root.find("page-field"), null);
			equals(o.x.full.value, true, "still open");
			if (k.end != "left") assert(Std.isOfType(o.ui.focus, ImageView), "the keys the document's: " + o.ui.focus?.tag);
		}, {cases: 60}));
	});
}

private function shape(kind:String):Array<{width:Float, height:Float}>
	return [for (_ in 0...12) switch kind {
		case "landscape": {width: 842.0, height: 595.0};
		case "tall": {width: 400.0, height: 1400.0};
		case "strip": {width: 1200.0, height: 300.0};
		case _: {width: 595.0, height: 842.0};
	}];

private function overlaps(a:Rect, b:Rect):Bool
	return a.x < b.x + b.width - 0.5 && b.x < a.x + a.width - 0.5 && a.y < b.y + b.height - 0.5 && b.y < a.y + a.height - 0.5;

private function near(a:Null<Rect>, b:Null<Rect>):Bool
	return a != null && b != null && Math.abs(a.x - b.x) <= 0.5 && Math.abs(a.y - b.y) <= 0.5 && Math.abs(a.width - b.width) <= 0.5
		&& Math.abs(a.height - b.height) <= 0.5;

private function str(r:Null<Rect>):String
	return r == null ? "none" : '${Math.round(r.x * 10) / 10},${Math.round(r.y * 10) / 10} ${Math.round(r.width * 10) / 10}x${Math.round(r.height * 10) / 10}';

// (a folder of pictures and a PDF of sizes, the PDF's pages drawn at once
// (blank, at their shape), its tile's thumbnail its first page's shape; the
// window w by h, overlay scrollbars, the status line on or off)
private class Opened {
	public final x:Explorer;
	public final ui:Ui;
	// (the most an overlay scrollbar of the PDF's showed in the last open's frames)
	public var barsSeen = 0.0;
	var t = 10.0;

	public function new(w:Int, h:Int, sizes:Array<{width:Float, height:Float}>, status:Bool, before:Int) {
		Ui.now = () -> t;
		Clock.tick(t);
		Kinds.utc = true;
		Tiles.forget();
		var files = new MemoryFiles().add("/d/");
		for (i in 0...before)
			files.add('/d/a$i.png', Bytes.alloc(10));
		files.add("/d/doc.pdf", Bytes.alloc(1000));
		x = new Explorer(files, (path, side, done) -> {
			var s = sizes[Decode.parseKey(path).page];
			done(blank(side, s.width, s.height));
		}, [], [], Preview.now, (_, done) -> done({sizes: sizes, fileSize: 1000, error: null}), (p, done) -> done(null));
		x.viewer.measure = (paths, done) -> done([for (p in paths) null]);
		x.viewer.statusOn(status);
		x.start("/d");
		var s = sizes[0], k = 200 / Math.max(s.width, s.height);
		Tiles.remember(x, x.browser.entry("doc.pdf"), new helder.image.Image(Std.int(s.width * k), Std.int(s.height * k)));
		ui = new Ui(new StoryText(), w, h);
		ui.overlayBars = true;
		Render.render(Shell.view(x), ui.root);
		Shell.attach(ui.root, x);
		frames(20);
	}

	static function blank(side:Int, w:Float, h:Float):Decoded {
		var k = side / Math.max(w, h), pw = Std.int(Math.max(1, w * k)), ph = Std.int(Math.max(1, h * k));
		return {
			width: pw,
			height: ph,
			pixelsWidth: pw,
			pixelsHeight: ph,
			frames: [{pixels: new hxmc.Buffer(pw * ph * 4), delay: 0.0}],
			repetitions: 0,
			format: "PDF",
			fileSize: 0,
			page: 0,
			pages: 12,
			error: null,
			errorKind: ""
		};
	}

	public function frames(n:Int)
		for (_ in 0...n) {
			t += 1 / 60;
			Clock.tick(t);
			Graph.flush();
			ui.update();
			Graph.flush();
			ui.update();
			var s = ui.root.find("pdf-scroll");
			if (s != null && x.full.value) barsSeen = Math.max(barsSeen, @:privateAccess ui.barShown(s));
		}

	public function doc():PdfDoc
		return x.viewer.document();

	// (opened, its frames run until it lands and a while after: the picture's box in each frame of its flight)
	public function open():Array<Rect> {
		barsSeen = 0;
		x.open("doc.pdf");
		var boxes = [];
		for (_ in 0...120) {
			frames(1);
			if (x.zoom.flying.peek() != "") {
				var b = x.zoom.box.peek();
				boxes.push({x: b.x, y: b.y, width: b.width, height: b.height});
			}
		}
		return boxes;
	}

	public function rect(tag:String):Null<Rect> {
		var n = ui.root.find(tag);
		return n == null ? null : n.windowBounds();
	}

	// (what of the PDF's page across its view's middle (else its first) the view shows)
	public function shows():Null<Rect> {
		var v = rect("pdf-scroll"), pages = ui.root.find("pdf-pages");
		if (v == null || pages == null) return null;
		var first:Null<Rect> = null;
		for (p in pages.children) {
			if (p.width <= 0) continue;
			var b = p.windowBounds();
			if (b.y <= v.y + v.height / 2 && b.y + b.height >= v.y + v.height / 2) return clip(b, v);
			if (first == null) first = b;
		}
		return first == null ? null : clip(first, v);
	}

	static function clip(r:Rect, v:Rect):Rect {
		var x0 = Math.max(r.x, v.x), y0 = Math.max(r.y, v.y);
		return {x: x0, y: y0, width: Math.min(r.x + r.width, v.x + v.width) - x0, height: Math.min(r.y + r.height, v.y + v.height) - y0};
	}

	public function wheel(dy:Float) {
		var b = rect("pdf-scroll");
		ui.wheel(b.x + b.width / 2, b.y + b.height / 2, 0, dy);
		frames(30);
	}

	public function press(tag:String) {
		var b = rect(tag);
		ui.pointerDown(b.x + b.width / 2, b.y + b.height / 2, 1);
		ui.pointerUp(b.x + b.width / 2, b.y + b.height / 2, 1);
		frames(3);
	}
}
