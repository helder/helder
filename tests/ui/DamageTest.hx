import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;
import helder.ui.widgets.TextField;

// A window's frame kept from frame to frame and drawn only where it
// changed (Renderer.keep: Ui.paint's damage) against the same tree drawn
// whole, pixel for pixel, headless on the GPU (bun run test ui-draw):
// random trees (rounded scrollers of rows, a text field, a card, a popup)
// changed at random over frames (rows restyled, relabelled, hidden; whole
// pixel scrolls; the card's transform and opacity moving; the popup opened
// and closed; the caret moved, text typed), at scales 1 and 2, layers
// replayed and from their tiles; with --window, in a window whose frame
// is multisampled where it can be (the frame kept multisampled too). And
// that a row toggled damages that row, the caret moved only the caret
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
			if (scale == 1) damages(device);
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
			Sys.println('DamageTest: a window of ${device.width}x${device.height}, ${device.samples} samples a pixel');
			for (tiles in [false, true])
				for (tree in 0...2)
					compare(device, scale, tree, tiles);
			Sys.println("DamageTest: " + (failed == 0 ? "ok" : '$failed FAILED'));
			device.dispose();
			Sys.exit(failed == 0 ? 0 : 1);
		}, e -> {});
	}

	static function compare(device:Device, scale:Float, tree:Int, tiles:Bool) {
		var w = device.width, h = device.height;
		var made = [build(tree), build(tree)], rs = [for (k in 0...2) new Renderer(device)];
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
		check('scale $scale tree $tree${tiles ? " from tiles" : ""}: drawn where it changed as drawn whole', off == 0 && kept > frames / 3,
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
			case _:
		}
	}

	// (whole pixels from tiles, as tiles are exact there; turned where replayed)
	static function move(m:Made, k:Int, tiles:Bool) {
		var turn = tiles ? '' : ' rotate(${k % 5}deg)';
		m.card.style.transform = Transform.parse('translate(${k % 7}px, ${k % 3}px)$turn');
		m.card.style.opacity = [1, 0.75, 0.5][k % 3];
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
		return {ui: ui, scrollers: scrollers, rows: rows, card: card, field: field, popup: popup};
	}
}

typedef Made = {ui:Ui, scrollers:Array<Node>, rows:Array<Node>, card:Node, field:TextField, popup:Popup};
