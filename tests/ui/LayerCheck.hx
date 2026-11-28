import helder.math.Vec4;
import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;

// Layers drawn from their tiles (Renderer.tiles, a window's) against the
// same tree replayed (the reference every golden image is drawn by), pixel
// for pixel, headless on the GPU (bun run test ui-draw): random trees of
// rounded scrollers (rows of text, boxes, borders, shadows, groups) and a
// node moving, scrolled by whole pixels at scales 1 and 2 (exact), by
// fractions of one and under a moving transform (the difference reported)
//   LayerCheck
class LayerCheck {
	static inline var W = 320;
	static inline var H = 240;

	static var failed = 0;

	static function main() {
		for (scale in [1, 2]) {
			var device = Device.create(Surface.headless(W * scale, H * scale));
			for (tree in 0...4)
				compare(device, scale, tree);
			device.dispose();
		}
		Sys.println("LayerCheck: " + (failed == 0 ? "ok" : '$failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function compare(device:Device, scale:Int, tree:Int) {
		var w = W * scale, h = H * scale;
		var made = [build(tree), build(tree)];
		var uis = [for (m in made) m.ui], rs = [for (k in 0...2) new Renderer(device)];
		for (k in 0...2) {
			rs[k].scale = scale;
			rs[k].groups = true;
			uis[k].scale = scale;
		}
		rs[1].tiles = true;
		var pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(1, 1, 1, 1)}]};
		var pixels = [Bytes.alloc(w * h * 4), Bytes.alloc(w * h * 4)], whole = true;
		function frame() {
			for (k in 0...2) {
				uis[k].update();
				var enc = device.beginFrame();
				rs[k].begin(w, h);
				uis[k].paint(rs[k]);
				rs[k].prepare(enc);
				enc.beginPass(pass);
				rs[k].end(enc);
				enc.endPass();
				device.readPixels(pixels[k]);
				device.endFrame();
			}
			var off = 0;
			for (i in 0...w * h)
				if (pixels[0].getInt32(i * 4) != pixels[1].getInt32(i * 4)) {
					if (off++ < 4 && whole) where(made[1], scale, i % w, Std.int(i / w), pixels[0].getInt32(i * 4), pixels[1].getInt32(i * 4));
				}
			return off;
		}
		function scroll(by:Float) {
			for (m in made)
				for (s in m.scrollers)
					m.ui.scrollTo(s, 0, Math.max(0, s.scrollY + by));
		}
		var exact = 0, frames = 0;
		exact += frame();
		for (by in [24.0, 37, 113, -40, 300, 1, 2]) {
			scroll(by);
			exact += frame();
			frames++;
		}
		// (a row changed: its scroller's tiles drawn again)
		for (m in made)
			(cast m.rows[3] : TextNode).text = "changed, row three";
		exact += frame();
		var fraction = 0, moving = 0;
		whole = false;
		for (by in [10.5, 0.25]) {
			scroll(by);
			fraction += frame();
		}
		for (i in 0...4) {
			for (m in made)
				m.card.style.transform = Transform.parse('translate(${i * 3.5}px, ${i}px) rotate(${i * 2}deg)');
			moving += frame();
		}
		var tiles = rs[1].tileBytes, drawn = rs[1].rastered;
		var ok = exact == 0 && drawn > 0;
		if (!ok) failed++;
		Sys.println('LayerCheck: scale $scale tree $tree: ${ok ? "ok" : "FAIL"}: $exact pixels differ at whole pixels ($frames scrolls); '
			+ '$fraction at fractions, $moving under a moving transform; $drawn tiles drawn, ${Math.round(tiles / 1024)} KB of them');
	}

	// (a pixel differing at whole pixels: where it is from the nearest
	// scroller's clip corner and in its tile, as a failure names it)
	static function where(m:{scrollers:Array<Node>}, scale:Int, x:Int, y:Int, want:Int, got:Int) {
		var near = "";
		for (sc in m.scrollers) {
			var be = sc.style.borderEdges, x0 = (sc.absX + be.left) * scale, y0 = (sc.absY + be.top) * scale;
			var x1 = (sc.absX + sc.width - be.right) * scale, y1 = (sc.absY + sc.height - be.bottom) * scale;
			if (x < x0 || x >= x1 || y < y0 || y >= y1) continue;
			var dx = x - x0 < x1 - 1 - x ? x - x0 : x - x1, dy = y - y0 < y1 - 1 - y ? y - y0 : y - y1;
			var ty = Std.int(y + sc.scrollY * scale - y0) % Renderer.TILE;
			near = ' in the clip ${x0},${y0} ${x1},${y1} (r ${sc.style.borderRadius * scale}), $dx, $dy from its nearest corner, row $ty of its tile';
		}
		Sys.println('LayerCheck:   $x,$y: ${StringTools.hex(want, 8)} drawn, ${StringTools.hex(got, 8)} from tiles$near');
	}

	// (a tree: a header, a moving card, scrollers of rows, the same for the same seed)
	static function build(tree:Int):{ui:Ui, scrollers:Array<Node>, rows:Array<Node>, card:Node} {
		var seed = tree * 7919 + 1;
		function rnd(n:Int):Int {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return (seed >> 8) % n;
		}
		var ui = new Ui(helder.ui.TextEngines.standard(), W, H), scrollers:Array<Node> = [], rows:Array<Node> = [];
		var top = new Node();
		top.style.set({flexDirection: Row, height: H, padding: 8, columnGap: 8, background: 0xFFF4F4F5, fontSize: 13});
		var card = new Node();
		card.style.set({width: 60, height: 40, background: 0xFF3B82F6, borderRadius: 6, position: Absolute, left: 200, top: 150});
		for (k in 0...1 + rnd(2)) {
			var list = new Node();
			list.style.set({overflow: Scroll, flexGrow: 1, background: 0xFFFFFFFF, rowGap: 2, padding: 4, minHeight: 0, borderRadius: [8, 6.5, 12][rnd(3)]});
			if (rnd(2) == 0) list.style.set({borderWidth: 1, borderColor: 0xFFE4E4E7});
			for (i in 0...30 + rnd(30)) {
				var row = new Node();
				row.style.set({flexDirection: Row, padding: 3, columnGap: 6, background: rnd(3) == 0 ? 0xFFEFF6FF : 0xFFFFFFFF, alignItems: Center});
				if (rnd(4) == 0) row.style.boxShadow = Shadow.parse("0 1px 3px rgba(0,0,0,0.3)");
				if (rnd(5) == 0) row.style.set({borderWidth: 1, borderColor: 0xFF71717A});
				var box = new Node();
				box.style.set({width: 10 + rnd(20), height: 10, background: Color.rgb(rnd(0xFFFFFF)), borderRadius: rnd(2) * 5});
				var text = new TextNode("Row " + i + [" alpha", " beta gamma", " delta"][rnd(3)]);
				if (rnd(4) == 0) text.style.opacity = 0.5;
				row.append(box);
				row.append(text);
				rows.push(text);
				list.append(row);
			}
			scrollers.push(list);
			top.append(list);
		}
		ui.root.append(top);
		ui.root.append(card);
		return {ui: ui, scrollers: scrollers, rows: rows, card: card};
	}
}
