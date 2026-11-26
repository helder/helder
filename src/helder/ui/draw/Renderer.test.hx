package helder.ui.draw;

import helder.math.Vec4;

import helder.gfx.Device;
import helder.gfx.PassDesc;
import helder.os.Surface;
import helder.image.Image;
import helder.test.Choices;
import helder.test.Gen;
import helder.test.Test;

// The renderer's textures given back when the system wants memory (trim:
// helder.os.App.lowMemory, an iOS app gone to the background): an image
// not drawn in the last frame lets its texture go, one drawn keeps it, and
// one drawn again is uploaded again. What the compositor's frames show (a
// scroller's tiles, the images and opacity groups they were drawn from) is
// not freed while only the compositor draws it. A node drawn into a
// texture of its own, resized at random in frames whose walk runs again (a
// node entering under motion): the compositor never shows an undrawn
// texture of it
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
		// (trim, the system asking for memory back, between frames that draw
		// elsewhere: the compositor's frames still show the grid as at rest)
		for (keep in [true, false])
			test("trim: what the compositor shows kept: " + (keep ? "a frame kept" : "the system's layers"), () -> stateful({
				setup: () -> {
					var w = new Grid(keep);
					w.frames(12);
					w.rest = w.composed();
					w;
				},
				steps: [{name: "trim", run: (w, _) -> w.trim()}, {name: "elsewhere", run: (w, _) -> w.elsewhere()}],
				check: w -> equals(w.differ(w.rest), 0),
				teardown: w -> w.dispose()
			}, {cases: 8, steps: 8}));
		// (its pass asked for once a recording of its list (Renderer.passKey),
		// not once a frame: a frame that walks again (a node entering) records
		// the list again, the first recording's passes dropped with it, and a
		// texture made in the first was never drawn: magenta on Apple's GPUs
		// beside a picture as a window zoomed)
		for (keep in [true, false])
			test("a node's own texture resized as a node enters: the compositor shows what it drew, never an undrawn texture (" + (keep ? "a frame kept" : "the system's layers") + ")", () -> stateful({
				setup: () -> new Owned(keep),
				steps: [
					{name: "size", run: (w, c) -> w.size(c.draw(int(40, 700)), c.draw(int(30, 220)), c.draw(bool()))},
					{name: "label", run: (w, c) -> w.label()}
				],
				check: w -> w.check(),
				teardown: w -> w.dispose()
			}, {cases: 12, steps: 10}));
		#end
	});
}

#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
// (a window at scale 2: a node drawn into a texture of its own, cleared to
// its colour by its pass, a label and nodes that enter with a fade beside
// it; the compositor's frames read back, the node's box all its colour)
private class Owned {
	static inline var W = 800;
	static inline var H = 240;
	static final pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(1, 1, 1, 1)}]};

	final keep:Bool;
	final device = Device.create(Surface.headless(W * 2, H * 2));
	final r:Renderer;
	final ui = new helder.ui.Ui(new DrawText(), W, H);
	final c:helder.ui.layers.Compositor;
	final node = new OwnTexture();
	final side = new helder.ui.Node();
	final text = new helder.ui.TextNode("0");
	var count = 0;

	public function new(keep:Bool) {
		this.keep = keep;
		r = new Renderer(device);
		r.keep = keep;
		r.scale = ui.scale = 2;
		r.background = 0xFFFFFFFF;
		var row = new helder.ui.Node();
		row.style.set({flexDirection: Row, width: W, height: H, alignItems: Start});
		node.style.set({width: 300, height: 200, flexShrink: 0});
		side.style.set({flexDirection: Row, columnGap: 2});
		row.append(node);
		row.append(text);
		row.append(side);
		ui.root.append(row);
		c = new helder.ui.layers.Compositor(device);
		for (_ in 0...12)
			frame();
	}

	// (its size; entering: a node fading in, in the same frame)
	public function size(w:Int, h:Int, entering:Bool) {
		node.style.width = w;
		node.style.height = h;
		if (entering) {
			var n = new helder.ui.Node();
			n.style.set({width: 4, height: 4, background: 0xFF808080});
			n.style.transition = helder.ui.Transition.parse("fade");
			side.append(n);
		}
		frame();
	}

	public function label() {
		text.text = "" + ++count;
		frame();
	}

	function frame() {
		ui.update();
		var enc = device.beginFrame();
		r.begin(W * 2, H * 2);
		c.begin(r);
		ui.paint(r);
		r.prepare(enc);
		if (keep) {
			enc.beginPass(pass);
			r.end(enc);
			enc.endPass();
		} else
			r.upload();
		c.end(ui, r);
		device.endFrame();
	}

	// (the compositor's frame: the node's box, a few pixels in from its edges, all its colour)
	public function check() {
		var b = haxe.io.Bytes.alloc(W * H * 16);
		c.drawNow(b);
		var x0 = Std.int(node.absX * 2) + 4, y0 = Std.int(node.absY * 2) + 4, x1 = Std.int((node.absX + node.width) * 2) - 4,
			y1 = Std.int((node.absY + node.height) * 2) - 4, off = 0, seen = 0;
		var y = y0;
		while (y < y1) {
			var x = x0;
			while (x < x1) {
				var o = (y * W * 2 + x) * 4;
				// (RGBA: 0x33, 0x66, 0x99)
				if (b.get(o) != 0x33 || b.get(o + 1) != 0x66 || b.get(o + 2) != 0x99) {
					if (off == 0) seen = b.getInt32(o);
					off++;
				}
				x += 3;
			}
			y += 3;
		}
		equals('$off pixels not its colour (the first ${StringTools.hex(seen, 8)})', '0 pixels not its colour (the first 00000000)');
	}

	public function dispose() {
		c.dispose();
		device.dispose();
	}
}

// (a node drawn into its texture, made at its size, its pass asked for
// once a Renderer.passKey; byFrame: once a frame, as before)
private class OwnTexture extends helder.ui.Node {
	public static var byFrame = false;
	static var ids = 0;

	final id = -(++ids) - 6000000;
	var target:Null<helder.gfx.Texture> = null;
	var tw = 0;
	var th = 0;
	var queued = -1;

	public function new()
		super("own");

	override public function hasContent():Bool
		return true;

	override public function paintContent(canvas:helder.ui.Canvas, x:Float, y:Float, width:Float, height:Float) {
		var r = Renderer.of(canvas);
		if (r == null) return;
		var pw = Std.int(Math.max(1, Math.round(width * r.scale))), ph = Std.int(Math.max(1, Math.round(height * r.scale)));
		if (pw != tw || ph != th) {
			target = r.device.createTexture({width: pw, height: ph, renderTarget: true});
			tw = pw;
			th = ph;
		}
		var key = byFrame ? r.frames : r.passKey;
		if (queued != key) {
			queued = key;
			r.beforePass(record);
		}
		(cast canvas : TextureCanvas).gpuTexture(target, id, x, y, width, height);
	}

	function record(enc:helder.gfx.Encoder) {
		var t = target;
		if (t == null) return;
		enc.beginPass({colors: [{load: Clear, clear: new Vec4(0x33 / 255, 0x66 / 255, 0x99 / 255, 1), texture: t}]});
		enc.endPass();
	}
}

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
		row.style.set({flexDirection: Row, width: W, height: H, columnGap: 40});
		list.style.set({overflow: Scroll, width: GRID, height: H, rowGap: 2, padding: 4, background: 0xFFFFFFFF, flexShrink: 0});
		for (i in 0...60) {
			var item = new helder.ui.Node(), badge = new helder.ui.Node(), img = swatch(i);
			item.style.set({flexDirection: Row, padding: 3, columnGap: 6, alignItems: Center, flexShrink: 0});
			badge.style.set({width: 40, opacity: 0.5, background: 0xFF2060C0});
			badge.append(new helder.ui.TextNode("new"));
			rows.push({node: item, image: img});
			item.append(new helder.ui.ImageNode(img));
			item.append(new helder.ui.TextNode("Row " + i));
			item.append(badge);
			list.append(item);
		}
		side.style.set({width: 80, height: H, flexShrink: 0});
		notes.style.set({overflow: Scroll, height: H - 40, padding: 8, background: 0xFFEEEEEE, flexShrink: 0});
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

	// (its compositor's frame at rest: a test's)
	public var rest:Null<haxe.io.Bytes> = null;

	public function trim()
		r.trim();

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
