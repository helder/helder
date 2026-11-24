import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;
import helder.ui.widgets.TextField;

// A window's frame kept from frame to frame and drawn only where it
// changed (Renderer.keep: Ui.paint's damage) against the same tree drawn
// whole, pixel for pixel, headless on the GPU (bun run test ui-draw):
// random trees (a header, rounded scrollers of rows, a text field, a card,
// a popup) changed at random over frames (the header's label, its width
// with it; rows restyled, relabelled, hidden; whole
// pixel scrolls; the card's transform and opacity moving; the popup opened
// and closed; the caret moved, text typed), at scales 1 and 2, layers
// replayed and from their tiles; with --window, in a window whose frame
// is multisampled where it can be (the frame kept is not). And
// that a row toggled damages that row, the caret moved only the caret;
// under Liquid Glass (helder.ui.Glass: what it reads reaches past what
// changed) every frame drawn whole, as the tree drawn whole
//   DamageTest [--window]
class DamageTest {
	static inline var W = 320;
	static inline var H = 240;

	static var failed = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		if (!ok) failed++;
		Sys.println('DamageTest: ${ok ? "ok" : "FAIL"}: $what' + (detail == null ? "" : ' ($detail)'));
	}

	static function main() {
		if (Sys.args().indexOf("--window") >= 0) return window();
		for (scale in [1, 2]) {
			var device = Device.create(Surface.headless(W * scale, H * scale));
			for (tiles in [false, true])
				for (tree in 0...3)
					compare(device, scale, tree, tiles);
			for (tiles in [false, true])
				compare(device, scale, 0, tiles, true);
			if (scale == 1) damages(device);
			for (tiles in [false, true])
				see(device, scale, tiles);
			rests(device, scale);
			device.dispose();
			planes(scale);
		}
		// (last: motion, once declared, is on for the process)
		for (scale in [1, 2]) {
			var device = Device.create(Surface.headless(W * scale, H * scale));
			for (how in [Plain, Moving, Scrolled, Presence])
				for (tiles in [false, true])
					swaps(device, scale, how, tiles);
			device.dispose();
		}
		Sys.println("DamageTest: " + (failed == 0 ? "ok" : '$failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static final pass:PassDesc = {colors: [{load: Clear, clear: new helder.gfx.Color(1, 1, 1)}]};

	// (a frame drawn as a window draws it: the passes before, the frame's pass; read back)
	static function frame(device:Device, ui:Ui, r:Renderer, w:Int, h:Int, pixels:Bytes) {
		ui.update();
		var enc = device.beginFrame();
		r.begin(w, h);
		ui.paint(r);
		r.prepare(enc);
		enc.beginPass(pass);
		r.end(enc);
		enc.endPass();
		device.readPixels(pixels);
		device.endFrame();
	}

	// (a window's frame, multisampled where the GPU has it: drawn with damage
	// against drawn whole, both into its frame, read back resolved)
	static function window() {
		var win = new helder.os.Window("DamageTest", W, H);
		var device = Device.create(win.surface, {antialias: true});
		helder.os.App.run(() -> {
			var scale = device.width / W;
			Sys.println('DamageTest: a window of ${device.width}x${device.height}, multisampled where the GPU has it');
			for (tiles in [false, true])
				for (tree in 0...2)
					compare(device, scale, tree, tiles);
			Sys.println("DamageTest: " + (failed == 0 ? "ok" : '$failed FAILED'));
			device.dispose();
			Sys.exit(failed == 0 ? 0 : 1);
		}, e -> {});
	}

	// (glass: a Liquid Glass capsule over the tree, its backdrop read each frame: drawn whole)
	static function compare(device:Device, scale:Float, tree:Int, tiles:Bool, glass = false) {
		var w = device.width, h = device.height;
		var made = [build(tree), build(tree)], rs = [for (k in 0...2) new Renderer(device)];
		if (glass) for (m in made) {
			var g = new Glass();
			g.style.set({position: Absolute, left: 60, top: 40, width: 180, height: 50});
			m.ui.root.append(g);
		}
		for (k in 0...2) {
			rs[k].scale = scale;
			rs[k].groups = true;
			rs[k].tiles = tiles;
			made[k].ui.scale = scale;
		}
		rs[1].keep = true;
		var pixels = [Bytes.alloc(w * h * 4), Bytes.alloc(w * h * 4)];
		var seed = tree * 7919 + Math.round(scale * 104729) + (tiles ? 13 : 0) + 1;
		function rnd(n:Int):Int {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return (seed >> 8) % n;
		}
		var off = 0, first = "", kept = 0, area = 0.0, frames = 80, t = Clock.now + 10;
		for (f in 0...frames) {
			var op = rnd(10), i = rnd(1000), j = rnd(1000);
			for (m in made)
				change(m, op, i, j, f, tiles);
			t += 0.016;
			Clock.tick(t);
			for (k in 0...2)
				frame(device, made[k].ui, rs[k], w, h, pixels[k]);
			var n = 0;
			for (p in 0...w * h)
				if (pixels[0].getInt32(p * 4) != pixels[1].getInt32(p * 4)) {
					if (n++ == 0 && first == "")
						first = 'frame $f (op $op) at ${p % w},${Std.int(p / w)}: ${StringTools.hex(pixels[0].getInt32(p * 4), 8)} drawn, ${StringTools.hex(pixels[1].getInt32(p * 4), 8)} kept';
				}
			off += n;
			if (rs[1].drawn < w * h) kept++;
			area += rs[1].drawn;
		}
		check('scale $scale tree $tree${tiles ? " from tiles" : ""}${glass ? " under glass" : ""}: drawn where it changed as drawn whole', off == 0 && (glass || kept > frames / 3),
			'$off pixels differ${first == "" ? "" : ", first " + first}; $kept of $frames frames drawn in part, ${Math.round(area / frames / (w * h) * 100)}% a frame drawn');
	}

	// (the same change to each copy: a row restyled, relabelled or hidden, a
	// scroll, the card moved, the popup, the caret, text typed; the card
	// moving every frame for a while, so that it gets a layer of its own)
	static function change(m:Made, op:Int, i:Int, j:Int, frame:Int, tiles:Bool) {
		var ui = m.ui, row = m.rows[i % m.rows.length];
		if (frame >= 20 && frame < 32) move(m, frame, tiles);
		switch op {
			case 0:
				row.style.background = [0xFFEFF6FF, 0xFFFFFFFF, 0xFFFDE68A][j % 3];
			case 1:
				(cast row.children[1] : TextNode).text = ["changed", "Row " + j, "a longer label here"][j % 3];
			case 2:
				var s = m.scrollers[j % m.scrollers.length];
				ui.scrollTo(s, 0, Math.max(0, s.scrollY + [7, -5, 23, 1][j % 4]));
			case 3:
				move(m, j, tiles);
			case 4:
				if (m.popup.ui == null) ui.open(m.popup) else ui.close(m.popup);
			case 5:
				if (ui.focus != m.field) ui.setFocus(m.field);
				ui.keyDown(j % 2 == 0 ? Key.LEFT : Key.RIGHT, 0);
			case 6:
				if (ui.focus != m.field) ui.setFocus(m.field);
				ui.textInput(["a", "bc", " "][j % 3]);
			case 7:
				row.style.display = row.style.display == None ? Flex : None;
			case 8:
				// (light on dark, its width changing with its digits: #98's header)
				m.title.text = "Header " + [j, j % 10, j * 37 % 1000][i % 3];
			case _:
		}
	}

	// (a sidebar with no background of its own switched between two views of
	// different sizes and places, as the viewer's between its overview and a
	// folder's level (#111: one's pixels left under the other): Plain; the
	// view coming in moved and faded in on a transition (Moving); the sidebar
	// in a scroller, scrolled (Scrolled); the views entering and leaving on
	// their presence (Presence: drawn until their exits settle))
	static function swaps(device:Device, scale:Float, how:Swap, tiles:Bool) {
		var w = device.width, h = device.height;
		var made = [new Sidebar(how), new Sidebar(how)], rs = [for (k in 0...2) new Renderer(device)];
		for (k in 0...2) {
			rs[k].scale = scale;
			rs[k].groups = true;
			rs[k].tiles = tiles;
			made[k].ui.scale = scale;
		}
		rs[1].keep = true;
		var pixels = [Bytes.alloc(w * h * 4), Bytes.alloc(w * h * 4)];
		var seed = how.getIndex() * 31 + Math.round(scale) * 7 + (tiles ? 3 : 0) + 1;
		function rnd(n:Int):Int {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return (seed >> 8) % n;
		}
		var off = 0, first = "", kept = 0, swapped = 0, frames = 120, t = Clock.now + 10;
		// (what moves or fades in is mostly drawn whole while it does: only its pixels count)
		var moving = how == Moving || how == Presence;
		for (f in 0...frames) {
			var op = rnd(12), j = rnd(1000);
			if (op == 0) swapped++;
			for (m in made)
				m.change(op, j);
			t += 0.016;
			Clock.tick(t);
			for (k in 0...2)
				frame(device, made[k].ui, rs[k], w, h, pixels[k]);
			var n = 0;
			for (p in 0...w * h)
				if (pixels[0].getInt32(p * 4) != pixels[1].getInt32(p * 4)) {
					if (n++ == 0 && first == "")
						first = 'frame $f (op $op) at ${p % w},${Std.int(p / w)}: ${StringTools.hex(pixels[0].getInt32(p * 4), 8)} drawn, ${StringTools.hex(pixels[1].getInt32(p * 4), 8)} kept';
				}
			off += n;
			if (rs[1].drawn < w * h) kept++;
		}
		check('scale $scale ${how}${tiles ? " from tiles" : ""}: a sidebar switched between two views, drawn where it changed as drawn whole',
			off == 0 && (moving || kept > frames / 4), '$off pixels differ${first == "" ? "" : ", first " + first}; $swapped switches, $kept of $frames frames drawn in part');
	}

	// (whole pixels from tiles, as tiles are exact there; turned where replayed)
	static function move(m:Made, k:Int, tiles:Bool) {
		var turn = tiles ? '' : ' rotate(${k % 5}deg)';
		m.card.style.transform = Transform.parse('translate(${k % 7}px, ${k % 3}px)$turn');
		m.card.style.opacity = [1, 0.75, 0.5][k % 3];
	}

	// (a box moving to 0.4, then to 0.6, frames drawn only while something
	// moves, as a window draws them: at rest, its colour that of 0.6 over
	// the background, kept and drawn whole, replayed and from tiles (#94
	// saw a translucent mover drawn by the program alone at about 0.4 of that))
	static function see(device:Device, scale:Float, tiles:Bool) {
		var w = device.width, h = device.height, pixels = Bytes.alloc(w * h * 4), t = Clock.now + 10;
		var got = [for (keep in [false, true]) {
			var ui = new Ui(new DrawText(), W, H), r = new Renderer(device), box = new Node();
			r.scale = ui.scale = scale;
			r.groups = true;
			r.tiles = tiles;
			r.keep = keep;
			box.style.set({position: Absolute, left: 20, top: 30, width: 88, height: 64, radius: 10, background: 0xFF2A7AE2});
			box.style.transform = Transform.parse("translate(0px, 0px)");
			box.style.transition = Transition.parse("transform 0.5s linear, opacity 0.5s linear");
			ui.root.append(box);
			function frames(n:Int)
				for (_ in 0...n) {
					t += 1 / 60;
					Clock.tick(t);
					ui.update();
					if (ui.needsFrame || Clock.active) frame(device, ui, r, w, h, pixels);
				}
			frames(5);
			box.style.transform = Transform.parse("translate(100px, 60px)");
			box.style.opacity = 0.4;
			frames(60);
			box.style.transform = Transform.parse("translate(60px, 40px)");
			box.style.opacity = 0.6;
			frames(120);
			pixels.getInt32((Std.int(102 * scale) * w + Std.int(124 * scale)) * 4);
		}];
		// (0.6 of 0x2A7AE2 over white)
		var want = [0x7F, 0xAF, 0xEE], off = 0;
		for (v in got)
			for (k in 0...3)
				off = Std.int(Math.max(off, Math.abs((v >> (8 * k) & 0xFF) - want[k])));
		check('scale $scale${tiles ? " from tiles" : ""}: a box moved to 0.4, then 0.6, at rest at 0.6, drawn whole and kept', off <= 1,
			[for (v in got) StringTools.hex(v & 0xFFFFFF, 6)].join(" ") + ' (ABGR), at most $off levels off');
	}

	// (a scroller at rest at a fraction of a device pixel, its tiles drawn
	// there, then its offset set by the program, nothing else changing,
	// frames drawn only while the ui asks for them: its tiles drawn snapped
	// as it moved, then again where it rests, as the same replayed (#100: no
	// paint at rest asked for, rows a pixel off))
	static function rests(device:Device, scale:Float) {
		var w = device.width, h = device.height, t = Clock.now + 10;
		var got = [for (tiles in [true, false]) {
			var ui = new Ui(new DrawText(), W, H), r = new Renderer(device), list = new Node(), pixels = Bytes.alloc(w * h * 4);
			r.scale = ui.scale = scale;
			r.groups = true;
			r.tiles = r.keep = tiles;
			list.style.set({overflow: Scroll, width: 200, height: H, background: 0xFFFFFFFF, rowGap: 2, padding: 4, fontSize: 13});
			for (i in 0...60) {
				var row = new Node(), box = new Node();
				row.style.set({direction: Row, padding: 3, columnGap: 6, alignItems: Center, background: i % 3 == 0 ? 0xFFEFF6FF : 0xFFFFFFFF});
				box.style.set({width: 12, height: 12, radius: 3, background: 0xFF000000 | ((i * 40503) & 0xFFFFFF)});
				row.append(box);
				row.append(new TextNode("Row " + i));
				list.append(row);
			}
			ui.root.append(list);
			function frames()
				for (_ in 0...20) {
					t += 1 / 60;
					Clock.tick(t);
					ui.update();
					if (ui.needsFrame) frame(device, ui, r, w, h, pixels);
				}
			// (at rest at a fraction of a device pixel, its tiles drawn there: as a fling may leave it)
			list.scrollY = 40 + 0.5 / scale;
			for (_ in 0...5) {
				ui.requestFrame();
				frames();
			}
			list.scrollY = 120;
			frames();
			pixels;
		}];
		var off = 0, first = "";
		for (p in 0...w * h)
			if (got[0].getInt32(p * 4) != got[1].getInt32(p * 4) && off++ == 0)
				first = ' first at ${p % w},${Std.int(p / w)}: ${StringTools.hex(got[0].getInt32(p * 4), 8)} from tiles, ${StringTools.hex(got[1].getInt32(p * 4), 8)} replayed';
		check('scale $scale: a scroll offset set by the program, its tiles drawn again at rest', off == 0, '$off pixels differ$first');
	}

	// (the system layers' buffers drawn only where they changed (LayerPlane:
	// cut, as CaLayers and ScLayers draw them) against drawn whole: two
	// stacks given the same changes, the window's layer of each drawn from
	// its compositor's frame onto its frame, one whole each frame, the other
	// its last frame loaded and only the rectangles that changed drawn over
	// it; a header's label, a badge in it, its colour, the list below
	// scrolled, a row toggled)
	static function planes(scale:Int) {
		var stacks = [for (_ in 0...2) new PlaneStack(W * scale, H * scale, scale)];
		var seed = 5 + scale, off = 0, first = "", cut = 0, drawn = 0, area = 0.0, frames = 60;
		function rnd(n:Int):Int {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return (seed >> 8) % n;
		}
		for (f in 0...frames) {
			var op = rnd(6), j = rnd(1000);
			for (st in stacks)
				st.change(op, j, f);
			var a = stacks[0].frame(false), b = stacks[1].frame(true);
			if (b >= 0) {
				drawn++;
				if (b < stacks[1].w * stacks[1].h) cut++;
				area += b;
			}
			var n = 0, pa = stacks[0].pixels, pb = stacks[1].pixels;
			for (p in 0...Std.int(pa.length / 4))
				if (pa.getInt32(p * 4) != pb.getInt32(p * 4)) {
					if (n++ == 0 && first == "")
						first = 'frame $f (op $op) at ${p % stacks[0].w},${Std.int(p / stacks[0].w)}: ${StringTools.hex(pa.getInt32(p * 4), 8)} whole, ${StringTools.hex(pb.getInt32(p * 4), 8)} cut';
				}
			off += n;
		}
		for (st in stacks)
			st.dispose();
		check('scale $scale: the window\'s system layer drawn where it changed as drawn whole', off == 0 && cut > drawn / 2,
			'$off pixels differ${first == "" ? "" : ", first " + first}; $cut of $drawn draws in part, ${Math.round(area / Math.max(1, drawn))} pixels a draw');
	}

	// a row toggled damages that row's bounds; the caret moved, only the caret
	static function damages(device:Device) {
		var m = build(0), ui = m.ui, r = new Renderer(device), pixels = Bytes.alloc(W * H * 4);
		r.groups = true;
		r.keep = true;
		for (i in 0...3)
			frame(device, ui, r, W, H, pixels);
		var row = m.rows[2], b = row.windowBounds();
		row.style.background = 0xFFFDE68A;
		frame(device, ui, r, W, H, pixels);
		var d = ui.damage, x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
		for (i in 0...d.count) {
			x0 = Math.min(x0, d.x0(i));
			y0 = Math.min(y0, d.y0(i));
			x1 = Math.max(x1, d.x1(i));
			y1 = Math.max(y1, d.y1(i));
		}
		// (its box, grown by the pixel its edge is anti-aliased over, rounded out)
		var within = x0 >= b.x - 3 && y0 >= b.y - 3 && x1 <= b.x + b.width + 3 && y1 <= b.y + b.height + 3;
		var covers = x0 <= b.x && y0 <= b.y && x1 >= b.x + b.width && y1 >= b.y + b.height;
		check("a row toggled damages its bounds", !d.all && within && covers,
			'damaged $x0,$y0 $x1,$y1, the row ${b.x},${b.y} ${b.x + b.width},${b.y + b.height}, ${r.drawn} pixels drawn');
		ui.setFocus(m.field);
		ui.keyDown(Key.LEFT, 0);
		for (i in 0...3)
			frame(device, ui, r, W, H, pixels);
		ui.keyDown(Key.LEFT, 0);
		frame(device, ui, r, W, H, pixels);
		var f = m.field.windowBounds(), wide = 0.0, tall = 0.0, inside = d.count > 0 && !d.all;
		for (i in 0...d.count) {
			wide = Math.max(wide, d.x1(i) - d.x0(i));
			tall = Math.max(tall, d.y1(i) - d.y0(i));
			if (d.x0(i) < f.x || d.y0(i) < f.y || d.x1(i) > f.x + f.width || d.y1(i) > f.y + f.height) inside = false;
		}
		// (a caret is a pixel or two wide: its old place and its new, a letter apart, grown and rounded out)
		check("the caret moved damages only the caret", inside && d.count <= 2 && wide <= 16 && tall <= f.height,
			'${d.count} rectangles, at most $wide x $tall, in the field ${f.width} x ${f.height}; ${r.drawn} pixels drawn');
	}

	// (a tree: a header, a field, a moving card, rounded scrollers of rows, a
	// popup to open; the same for the same seed)
	static function build(tree:Int):Made {
		var seed = tree * 7919 + 1;
		function rnd(n:Int):Int {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return (seed >> 8) % n;
		}
		var ui = new Ui(new DrawText(), W, H), scrollers:Array<Node> = [], rows:Array<Node> = [];
		var top = new Node();
		top.style.set({direction: Column, height: H, padding: 8, rowGap: 6, background: 0xFFF4F4F5, fontSize: 13});
		var head = new Node(), title = new TextNode("Header");
		head.style.set({shrink: 0, background: 0xFF18181B, padding: 4});
		title.style.set({color: 0xFFFFFFFF, fontSize: 14});
		head.append(title);
		top.append(head);
		var field = new TextField("some text to edit");
		field.style.set({background: 0xFFFFFFFF, borderWidth: 1, borderColor: 0xFFA1A1AA, padding: 3, width: 180, shrink: 0});
		top.append(field);
		var lists = new Node();
		lists.style.set({direction: Row, grow: 1, minHeight: 0, columnGap: 8});
		top.append(lists);
		var card = new Node();
		card.style.set({width: 60, height: 40, background: 0xFF3B82F6, radius: 6, position: Absolute, left: 230, top: 12});
		// (a blurred shadow turned with it: the one quad whose edge is not wholly clear)
		card.style.shadow = Shadow.parse("0 6px 6px rgba(0,0,0,0.9)");
		for (k in 0...1 + rnd(2)) {
			var list = new Node();
			list.style.set({overflow: Scroll, grow: 1, background: 0xFFFFFFFF, rowGap: 2, padding: 4, minHeight: 0, radius: [8, 6.5, 12][rnd(3)]});
			if (rnd(2) == 0) list.style.set({borderWidth: 1, borderColor: 0xFFE4E4E7});
			for (i in 0...30 + rnd(30)) {
				var row = new Node();
				row.style.set({direction: Row, padding: 3, columnGap: 6, background: rnd(3) == 0 ? 0xFFEFF6FF : 0xFFFFFFFF, alignItems: Center});
				if (rnd(4) == 0) row.style.shadow = Shadow.parse("0 1px 3px rgba(0,0,0,0.3)");
				if (rnd(5) == 0) row.style.set({borderWidth: 1, borderColor: 0xFF71717A, borderStyle: rnd(2) == 0 ? Solid : Dashed});
				if (rnd(6) == 0) row.style.opacity = 0.6;
				if (rnd(7) == 0) row.style.shadow = Shadow.parse("inset 1px 1px 3px rgba(0,0,0,0.4)");
				if (i == 0) row.style.set({position: Sticky, top: 0});
				var box = new Node();
				box.style.set({width: 10 + rnd(20), height: 10, background: Color.rgb(rnd(0xFFFFFF)), radius: rnd(2) * 5});
				var text = new TextNode("Row " + i + [" alpha", " beta gamma", " delta"][rnd(3)]);
				if (rnd(4) == 0) text.style.opacity = 0.5;
				row.append(box);
				row.append(text);
				rows.push(row);
				list.append(row);
			}
			scrollers.push(list);
			lists.append(list);
		}
		ui.root.append(top);
		ui.root.append(card);
		var popup = new Popup();
		popup.placement = Manual;
		popup.style.set({left: 120, top: 60, width: 120, height: 70, background: 0xFFFFFFFF, borderWidth: 1, borderColor: 0xFF71717A, radius: 6, padding: 6});
		popup.style.shadow = Shadow.parse("0 4px 12px rgba(0,0,0,0.3)");
		popup.append(new TextNode("A popup"));
		return {ui: ui, scrollers: scrollers, rows: rows, card: card, field: field, popup: popup, title: title};
	}
}

enum Swap {
	Plain;
	Moving;
	Scrolled;
	Presence;
}

// (the viewer's sidebar, #111: no background of its own; an overview (a
// scroller of a heading and rows) or a folder's level (a back row with a
// button, a title, a scroller of a few rows, a foot), one at a time)
class Sidebar {
	public final ui = new Ui(new DrawText(), 320, 240);
	final how:Swap;
	final side = new Node();
	final outer = new Node();
	var view:Null<Node> = null;
	var level = false;
	var rows:Array<Node> = [];
	var list:Null<Node> = null;
	var button:Null<Node> = null;
	var arriving:Null<Node> = null;
	var depth = 0;

	public function new(how:Swap) {
		this.how = how;
		ui.root.style.set({direction: Row, background: 0xFFF4F4F5, fontSize: 13});
		side.style.set({width: 150, shrink: 0, padding: 8, rowGap: 10, overflow: Hidden});
		if (how == Scrolled) {
			outer.style.set({overflow: Scroll, width: 170, shrink: 0, minHeight: 0});
			side.style.set({height: 400});
			outer.append(side);
			ui.root.append(outer);
		} else
			ui.root.append(side);
		if (how == Presence) side.motion = helder.ui.motion.MotionSpec.DEFAULT;
		var pane = new Node();
		pane.style.set({grow: 1, background: 0xFFFFFFFF, radius: 10, margin: 8});
		ui.root.append(pane);
		show();
	}

	public function change(op:Int, j:Int) {
		if (arriving != null) {
			arriving.style.transform = Transform.parse("translate(0px, 0px)");
			arriving.style.opacity = 1;
			arriving = null;
		}
		switch op {
			case 0:
				level = !level;
				depth = j % 4;
				show();
			case 3:
				var r = rows[j % rows.length];
				r.style.background = r.style.background == 0xFFE4E4E7 ? 0x00000000 : 0xFFE4E4E7;
			case 4:
				if (list != null) ui.scrollTo(list, 0, Math.max(0, list.scrollY + [9, -6, 30][j % 3]));
			case 5:
				if (how == Scrolled) ui.scrollTo(outer, 0, Math.max(0, outer.scrollY + [11, -7, 40][j % 3]));
			case 6:
				if (button != null) button.style.background = button.style.background == 0xFFE4E4E7 ? 0xFFD4D4D8 : 0xFFE4E4E7;
			case _:
		}
	}

	function show() {
		if (view != null) side.remove(view);
		var v = view = level ? makeLevel() : makeOverview();
		if (how == Presence) v.style.transition = Transition.parse("fade slide-up");
		if (how == Moving) {
			v.style.transition = Transition.parse("transform 0.2s linear, opacity 0.2s linear");
			v.style.transform = Transform.parse('translate(${level ? 24 : -24}px, 0px)');
			v.style.opacity = 0.3;
			arriving = v;
		}
		side.append(v);
	}

	function text(s:String, ?size:Float, ?weight:Int):TextNode {
		var t = new TextNode(s);
		if (size != null) t.style.fontSize = size;
		if (weight != null) t.style.fontWeight = weight;
		return t;
	}

	function row(s:String, selected:Bool):Node {
		var r = new Node(), icon = new Node();
		r.style.set({direction: Row, alignItems: Center, columnGap: 6, padding: 4, radius: 5, background: selected ? 0xFFE4E4E7 : 0x00000000});
		icon.style.set({width: 12, height: 12, radius: 3, borderWidth: 1, borderColor: 0xFF52525B});
		r.append(icon);
		r.append(text(s));
		rows.push(r);
		return r;
	}

	function makeOverview():Node {
		rows = [];
		button = null;
		var s = list = new Node();
		s.style.set({overflow: Scroll, grow: 1, minHeight: 0, rowGap: 1});
		s.append(text("Locations", 11, 600));
		for (i in 0...12)
			s.append(row(["ben", "Desktop", "Documents", "Downloads", "Pictures", "Movies"][i % 6] + (i < 6 ? "" : " " + i), i == 2));
		return s;
	}

	function makeLevel():Node {
		rows = [];
		var v = new Node(), back = new Node(), head = new Node(), foot = new Node();
		v.style.set({grow: 1, minHeight: 0, rowGap: 6});
		back.style.set({direction: Row, alignItems: Center, justify: SpaceBetween});
		back.append(text("< " + ["ben", "Documents", "a longer folder", "x"][depth]));
		var b = button = new Node();
		b.style.set({width: 22, height: 22, radius: 6, background: 0xFFE4E4E7});
		back.append(b);
		head.style.set({direction: Row, alignItems: Center, justify: SpaceBetween});
		head.append(text(["Documents", "CyFun", "Pictures", "A"][depth], 17, 700));
		head.append(text('${depth + 1} folders', 10));
		var s = list = new Node();
		s.style.set({overflow: Scroll, grow: 1, minHeight: 0, rowGap: 1});
		for (i in 0...depth + 1)
			s.append(row("Folder " + i, i == 0));
		foot.style.set({borders: [1, 0, 0, 0], borderColor: 0xFFD4D4D8, paddingTop: 6});
		foot.append(text("Macintosh HD"));
		v.append(back);
		v.append(head);
		v.append(s);
		v.append(foot);
		return v;
	}
}

typedef Made = {ui:Ui, scrollers:Array<Node>, rows:Array<Node>, card:Node, field:TextField, popup:Popup, title:TextNode};

// (a window's stack as the system layers see it: its program's frames
// composed (Compositor), split (LayerSplit), the window's layer drawn
// onto the frame from them, whole or only where it changed)
@:access(helder.ui.draw.LayerSplit)
@:access(helder.ui.draw.LayerPlane)
@:access(helder.ui.draw.CompositeFrame)
@:access(helder.ui.draw.Compositor)
@:access(helder.ui.draw.Renderer)
class PlaneStack {
	public final w:Int;
	public final h:Int;
	public final pixels:Bytes;
	final device:Device;
	final r:Renderer;
	final c:Compositor;
	final ui:Ui;
	final split = new PlaneSplit();
	final title = new TextNode("Header");
	final badge = new Node();
	final head = new Node();
	final list = new Node();
	final rows:Array<Node> = [];
	var buffer:Null<Buffer> = null;
	var room = 0;
	var drawnAt = -1;
	var t = 20.0;

	public function new(w:Int, h:Int, scale:Int) {
		this.w = w;
		this.h = h;
		pixels = Bytes.alloc(w * h * 4);
		device = Device.create(Surface.headless(w, h));
		r = new Renderer(device);
		r.scale = scale;
		r.groups = true;
		r.tiles = true;
		ui = new Ui(new DrawText(), w / scale, h / scale);
		ui.scale = scale;
		ui.root.style.set({direction: Column, background: 0xFFFFFFFF});
		head.style.set({direction: Row, height: 40, shrink: 0, padding: 10, columnGap: 8, alignItems: Center, background: 0xFF18181B});
		title.style.set({color: 0xFFFFFFFF, fontSize: 15});
		badge.style.set({width: 18, height: 18, radius: 9, background: 0xFFE2462A});
		head.append(title);
		ui.root.append(head);
		list.style.set({grow: 1, minHeight: 0, overflow: Scroll, rowGap: 2, padding: 4, background: 0xFFFFFFFF});
		for (i in 0...80) {
			var row = new Node();
			row.style.set({direction: Row, padding: 4, columnGap: 6, background: i % 3 == 0 ? 0xFFEFF6FF : 0xFFFFFFFF, alignItems: Center});
			row.append(new TextNode("Row " + i));
			rows.push(row);
			list.append(row);
		}
		ui.root.append(list);
		c = new Compositor(device);
	}

	public function change(op:Int, j:Int, f:Int) {
		switch op {
			case 0 | 1:
				title.text = "Header " + j;
			case 2:
				if (badge.parent == null) head.append(badge) else head.remove(badge);
			case 3:
				head.style.background = [0xFF18181B, 0xFF1E3A8A, 0xFF18181B][j % 3];
			case 4:
				ui.scrollTo(list, 0, Math.max(0, list.scrollY + [7, -5, 23][j % 3]));
			case _:
				var row = rows[j % rows.length];
				row.style.background = row.style.background == 0xFFFDE68A ? 0xFFFFFFFF : 0xFFFDE68A;
		}
	}

	// (a frame: the program's, composed, its window's layer drawn; the
	// pixels drawn (-1: not drawn, its last as it was), read back)
	public function frame(cut:Bool):Float {
		t += 0.016;
		Clock.tick(t);
		ui.update();
		var enc = device.beginFrame();
		r.begin(w, h);
		c.begin(r);
		ui.paint(r);
		r.prepare(enc);
		r.upload();
		c.end(ui, r);
		device.endFrame();
		var fr = c.frames[1 - c.filling];
		split.adopt();
		split.compose(fr, fr.offsets, Ui.now(), null, true);
		var p = split.base;
		p.place(0, 0, fr.width, fr.height);
		var changed = p.local(split.out, split.quadTextures, split.fresh);
		var drawn = -1.0;
		if (changed || drawnAt < 0) {
			var parts = cut && p.cut(drawnAt, fr.background | 0xFF000000);
			draw(fr, p, parts);
			drawnAt = p.serial;
			drawn = parts ? p.cutArea() : w * h;
		}
		var e = device.beginFrame();
		e.beginPass({colors: [{load: Load}]});
		e.endPass();
		device.readPixels(pixels);
		device.endFrame();
		return drawn;
	}

	// (its quads onto the frame, as ScLayers draws them into a buffer)
	function draw(f:CompositeFrame, p:LayerPlane, parts:Bool) {
		var bytes = parts ? p.cutBytes : p.bytes, len = parts ? p.cutLen : p.len;
		if (buffer == null || room < len) {
			if (buffer != null) device.destroyBuffer(buffer);
			room = len * 2 + CompositeFrame.STRIDE;
			buffer = device.createBuffer({size: room, usage: Vertex});
		}
		device.writeBuffer(buffer, 0, bytes, 0, len);
		var bg:Int = f.background, enc = device.beginFrame();
		enc.beginPass({colors: [{load: parts ? Load : Clear, clear: new helder.gfx.Color((bg >> 16 & 0xFF) / 255, (bg >> 8 & 0xFF) / 255, (bg & 0xFF) / 255)}]});
		enc.setVertexBuffer(0, f.corners);
		enc.setIndexBuffer(f.indices, UInt32);
		enc.setTexture(f.atlasSlot, f.atlas, f.sampler);
		var from = 0;
		if (parts) {
			enc.setPipeline(f.clearPipeline);
			enc.setTexture(f.imageSlot, f.blank, f.sampler);
			enc.setVertexBuffer(1, buffer, 0);
			enc.drawIndexed(6, p.clears);
			from = p.clears * CompositeFrame.STRIDE;
		}
		enc.setPipeline(f.pipeline);
		var runs = parts ? p.cutRuns : p.runs, textures = parts ? p.cutTextures : p.runTextures, k = 0;
		while (k < runs.length) {
			var t = textures[k >> 1];
			enc.setTexture(f.imageSlot, t == null ? f.blank : t, f.sampler);
			enc.setVertexBuffer(1, buffer, from + runs[k] * CompositeFrame.STRIDE);
			enc.drawIndexed(6, runs[k + 1]);
			k += 2;
		}
		enc.endPass();
		device.endFrame();
	}

	public function dispose() {
		c.dispose();
		device.dispose();
	}
}

// (the split alone: its layers LayerPlane's own, nothing of a system's)
private class PlaneSplit extends LayerSplit {
	public function new()
		super(new LayerPlane(LayerPlane.BASE, null));

	override function plane(kind:Int, key:Dynamic):LayerPlane
		return new LayerPlane(kind, key);
}
