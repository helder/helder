package helder.ui.draw;

import helder.gfx.shader.Vec4;

import helder.gfx.Device;
import helder.gfx.PassDesc;
import helder.os.Surface;
import helder.image.Image;
import helder.test.Test;

// The renderer's textures given back when the system wants memory (trim:
// helder.os.App.lowMemory, an iOS app gone to the background): an image
// not drawn in the last frame lets its texture go, one drawn keeps it, and
// one drawn again is uploaded again. What the compositor's frames show (a
// scroller's tiles, the images and opacity groups they were drawn from) is
// not freed while only the compositor draws it
function tests() {
	describe("Renderer", () -> {
		// (natively: a headless device; a browser's needs WebGPU or WebGL2)
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		test("trim: what the last frame did not draw let go", () -> {
			var device = Device.create(Surface.headless(64, 64)), r = new Renderer(device);
			// (larger than a page's images: a texture each)
			var a = new Image(300, 300), b = new Image(300, 300);
			function frame(images:Array<Image>) {
				var enc = device.beginFrame();
				enc.beginPass(({colors: [{load: Clear, clear: new Vec4(1, 1, 1, 1)}]} : PassDesc));
				r.begin(64, 64);
				for (img in images)
					r.image(img, 0, 0, 32, 32, 0, 0, 1, 1, 0);
				r.end(enc);
				enc.endPass();
				device.endFrame();
			}
			var none = device.textureBytes;
			frame([a, b]);
			var both = device.textureBytes;
			assert(both - none >= 2 * 300 * 300 * 4, 'both uploaded: ${both - none} bytes');
			frame([a]);
			r.trim();
			equals(device.textureBytes, both - 300 * 300 * 4);
			frame([a, b]);
			equals(device.textureBytes, both);
			device.dispose();
		});
		// (the compositor's frames drawn alone while the program draws
		// elsewhere: its frame kept (system layers off), or only into targets
		// (on); what they show not freed)
		for (keep in [true, false])
			test("what the compositor shows kept: " + (keep ? "a frame kept" : "the system's layers"), () -> {
				var w = new Grid(keep);
				w.frames(12);
				var rest = w.composed(), tiles = w.tiles(), images = w.images(), groups = w.groups(), blank = -1;
				for (k in 0...400) {
					w.elsewhere();
					if (blank < 0 && w.differ(rest) > 0) blank = k;
				}
				function kept(a:Array<Dynamic>, b:Array<Dynamic>)
					return a.filter(x -> b.indexOf(x) >= 0).length;
				var after = {blank: blank, tiles: kept(tiles, w.tiles()), images: kept(images, w.images()), groups: kept(groups, w.groups())};
				w.dispose();
				equals(after, {blank: -1, tiles: tiles.length, images: images.length, groups: groups.length});
			});
		#end
	});
}

#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
// (a window's renderer at scale 2: a scroller of image rows, tiled, three
// tiles wide and two high, a half-opaque badge in each row; beside it a
// label that changes and a list that scrolls, its new tiles over the
// budget; the compositor's frames drawn from the program's)
private class Grid {
	static inline var W = 800;
	static inline var H = 240;
	static inline var GRID = 600;
	static final pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(1, 1, 1, 1)}]};

	final keep:Bool;
	final device = Device.create(Surface.headless(W * 2, H * 2));
	final r:Renderer;
	final ui = new helder.ui.Ui(new DrawText(), W, H);
	final c:helder.ui.layers.Compositor;
	final label = new helder.ui.TextNode("0");
	final notes = new helder.ui.Node();
	final list = new helder.ui.Node();
	final rows:Array<{node:helder.ui.Node, image:Image}> = [];
	var count = 0;

	public function new(keep:Bool) {
		this.keep = keep;
		r = new Renderer(device);
		r.tiles = r.groups = true;
		r.keep = keep;
		r.scale = ui.scale = 2;
		r.background = 0xFFFFFFFF;
		r.tileBudget = 12 * Renderer.TILE * Renderer.TILE * 4;
		var row = new helder.ui.Node(), side = new helder.ui.Node();
		row.style.set({direction: Row, width: W, height: H, columnGap: 40});
		list.style.set({overflow: Scroll, width: GRID, height: H, rowGap: 2, padding: 4, background: 0xFFFFFFFF, shrink: 0});
		for (i in 0...60) {
			var item = new helder.ui.Node(), badge = new helder.ui.Node(), img = swatch(i);
			item.style.set({direction: Row, padding: 3, columnGap: 6, alignItems: Center, shrink: 0});
			badge.style.set({width: 40, opacity: 0.5, background: 0xFF2060C0});
			badge.append(new helder.ui.TextNode("new"));
			rows.push({node: item, image: img});
			item.append(new helder.ui.ImageNode(img));
			item.append(new helder.ui.TextNode("Row " + i));
			item.append(badge);
			list.append(item);
		}
		side.style.set({width: 80, height: H, shrink: 0});
		notes.style.set({overflow: Scroll, height: H - 40, padding: 8, background: 0xFFEEEEEE, shrink: 0});
		for (i in 0...400)
			notes.append(new helder.ui.TextNode("Note " + i));
		side.append(label);
		side.append(notes);
		row.append(list);
		row.append(side);
		ui.root.append(row);
		c = new helder.ui.layers.Compositor(device);
	}

	static function swatch(i:Int):Image {
		var img = new Image(16, 16), color = 0xFF000000 | ((i * 40503) & 0xFFFFFF);
		for (k in 0...16 * 16)
			img.pixels.setInt32(k * 4, color);
		return img;
	}

	public function frames(n:Int)
		for (_ in 0...n) {
			ui.update();
			var enc = device.beginFrame();
			r.begin(W * 2, H * 2);
			c.begin(r);
			ui.paint(r);
			r.prepare(enc);
			// (the system's layers: the frame drawn only into targets, the layers from the compositor's)
			if (keep) {
				enc.beginPass(pass);
				r.end(enc);
				enc.endPass();
			} else
				r.upload();
			c.end(ui, r);
			device.endFrame();
		}

	// (a frame that changes the label, every other one the list scrolled)
	public function elsewhere() {
		label.text = "" + ++count;
		if (count % 2 == 0) ui.scrollTo(notes, 0, (count * 97) % 7000);
		frames(1);
	}

	// the compositor's frame now
	public function composed():haxe.io.Bytes {
		var b = haxe.io.Bytes.alloc(W * H * 16);
		c.drawNow(b);
		return b;
	}

	// (the grid's pixels that differ from those of a frame before)
	public function differ(before:haxe.io.Bytes):Int {
		var now = composed(), off = 0;
		for (y in 0...H * 2)
			for (x in 0...GRID * 2)
				if (now.getInt32((y * W * 2 + x) * 4) != before.getInt32((y * W * 2 + x) * 4)) off++;
		return off;
	}

	// (the grid's tiles, those in view and those past it the compositor
	// scrolls into, the images of the rows they hold and the opacity groups
	// (the badges'): their textures, another once freed and made again)
	public function tiles():Array<Dynamic> {
		for (l in @:privateAccess r.tiled.keys())
			if (l.x1 - l.x0 == GRID) {
				var t:Dynamic = @:privateAccess r.tiled.get(l), ks:Array<Dynamic> = t.tiles;
				return [for (k in ks) if (k.group.texture != null) k.group.texture];
			}
		return [];
	}

	public function images():Array<Dynamic> {
		var l = @:privateAccess list.contentLayer, out:Array<Dynamic> = [];
		for (row in rows)
			if (row.node.y + row.node.height <= l.y1) {
				var e = @:privateAccess r.textures.get(row.image.id);
				if (e != null) out.push(e);
			}
		return out;
	}

	public function groups():Array<Dynamic>
		return [for (g in @:privateAccess r.groupPool) if (g.texture != null) g.texture];

	public function dispose() {
		c.dispose();
		device.dispose();
	}
}
#end
