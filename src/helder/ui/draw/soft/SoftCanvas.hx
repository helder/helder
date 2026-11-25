package helder.ui.draw.soft;

import haxe.io.Bytes;
import helder.canvas.Bitmap;
import helder.gfx.Texture;
import helder.image.Image;
import helder.image.PngDecoder;
import helder.image.Resize;
import helder.text.GlyphAtlas;
import helder.ui.*;
import helder.ui.draw.DrawText;
import helder.ui.draw.Backdrop;

// helder.ui's Canvas on the CPU, no GPU: what the Renderer draws, into a
// helder.canvas Bitmap (RGBA8, premultiplied) through Quads, UiShader's
// quads shaded pixel by pixel by the shader's own functions, so that its
// pixels are the GPU's within a rounding (headless runs, screenshots,
// golden images: the same on every machine). Every call is placed as the
// Renderer places it (its snapping to the pixel grid, its clips' radii,
// its transforms' scale and turn, a glyph's pen and phase, an image's
// whole pixels), then drawn at once rather than batched: a group
// (pushGroup) into a buffer of its bounds, composited at its opacity at
// popOpacity. Glyphs come from a GlyphAtlas (the GPU's coverage, read as
// UiShader reads its texture), paths and SVGs are helder.canvas's
// rasterizations (Path.render), images are premultiplied once and read
// bilinearly. What needs a GPU (a part's shader, a <Scene>, a sprite box)
// draws on the CPU's device in a -D helder.soft build (SoftGpu: helder.gfx's
// soft back end), its texture composited as an image; elsewhere (a GPU
// build's fallback) it is a grey box (GpuPlaceholder), and so is another
// process's image.
class SoftCanvas implements TextureCanvas implements GpuPlaceholder.Gpuless {
	public var scale = 1.0;
	// whether unturned, unscaled drawing is put on the pixel grid (Renderer.snap)
	public var snap = true;
	// whether pushGroup draws a group as one (CSS's opacity), else its opacity each thing's (Renderer.groups)
	public var groups = false;
	// whether glyphs under a scale that moves are drawn at steps (Renderer.steps)
	public var steps = false;
	public var again(default, null) = false;
	// a window's: the frame kept from one to the next, only what the UI
	// damaged drawn into it (keeps, damage, redraw: as the Renderer's kept
	// frame); regions: what the last frame drew (x0, y0, x1, y1 each; null all of it)
	public var keep = false;
	public var regions(default, null):Null<Array<Int>> = null;
	public final atlas:GlyphAtlas;
	// the frame drawn (begin's size), painted when read
	@:isVar public var frame(get, null):Bitmap;

	final quads:Quads;
	// (the frame's pixels outside the collector's heap, which bands paint
	// on any thread; the atlas's coverage there, as of the last paint;
	// images let go once what drew them is painted)
	@:hxmc.unsafe(gc) var pixels = hxmc.unsafe.Ptr.nil();
	var width = 0;
	var height = 0;
	@:hxmc.unsafe(gc) var atlasCopy = hxmc.unsafe.Ptr.nil();
	var atlasW = 0;
	var atlasH = 0;
	final retired:Array<SoftImage> = [];
	var damaged:Null<Damage> = null;
	var fresh = true;
	var backgroundWord = 0;
	var frames = 0;
	// (the images' premultiplied pixels, by id; the paths' images; the large and colour glyphs)
	final images = new Map<Int, SoftImage>();
	final paths = new haxe.ds.ObjectMap<Path, PathImage>();
	final large = new Map<String, {image:Image, left:Int, top:Int, frame:Int}>();
	final colorGlyphs = new Map<String, Null<{image:Image, left:Float, top:Int}>>();
	// (the groups open: each its buffer and place, the target and alpha it was opened in)
	final open:Array<SoftGroup> = [];
	final pool:Array<SoftGroup> = [];
	final pushed:Array<Int> = [];

	static inline var EVICT = 300;
	// (Renderer.LARGE: glyphs past it images of their own)
	static inline var LARGE = 256;

	// the state, as the Renderer's
	var tx = 0.0;
	var ty = 0.0;
	var alpha = 1.0;
	final alphas:Array<Float> = [];
	final clips:Array<Float> = [];
	var clipX0 = 0.0;
	var clipY0 = 0.0;
	var clipX1 = 0.0;
	var clipY1 = 0.0;
	var clipR0 = 0.0;
	var clipR1 = 0.0;
	var clipR2 = 0.0;
	var clipR3 = 0.0;
	var qr0 = 0.0;
	var qr1 = 0.0;
	var qr2 = 0.0;
	var qr3 = 0.0;
	var qw0 = 0.0;
	var qw1 = 0.0;
	var qw2 = 0.0;
	var qw3 = 0.0;
	var ma = 1.0;
	var mb = 0.0;
	var mc = 0.0;
	var md = 1.0;
	var me = 0.0;
	var mf = 0.0;
	var mk = 1.0;
	var flat = true;
	var aligned = true;
	var grid = true;
	final transforms:Array<Float> = [];
	static inline var STILL = 6;
	final scales:Array<Float> = [];
	final last:Array<Float> = [];
	var steady = true;
	var stretched = false;
	var dash:BorderStyle = Solid;
	var blend:Null<helder.text.Shaping.GlyphBlend> = null;
	var ex0 = 0.0;
	var ey0 = 0.0;
	var ex1 = 0.0;
	var ey1 = 0.0;

	// whether a headless run draws on it (UiWindow): -D helder.soft (no GPU
	// linked), else HELDER_SOFT=1
	public static function wanted():Bool {
		#if helder.soft
		return true;
		#else
		var v = Sys.getEnv("HELDER_SOFT");
		return v != null && v != "" && v != "0";
		#end
	}

	public function new(?atlas:GlyphAtlas) {
		this.atlas = atlas == null ? new GlyphAtlas(1024, 1024) : atlas;
		this.atlas.max = 4096;
		frame = new Bitmap(1, 1);
		var env = Sys.getEnv("HELDER_SOFT_THREADS"), n = env == null ? -1 : Std.parseInt(env);
		quads = new Quads(n == null ? -1 : n - 1);
	}

	// starts a frame of width x height pixels, cleared to background
	@:hxmc.unsafe(gc) public function begin(width:Int, height:Int, background:Color) {
		paint();
		for (e in retired)
			e.free();
		retired.resize(0);
		frames++;
		if (frames % 60 == 0) evict(EVICT);
		if (this.width != width || this.height != height || pixels.isNull()) {
			fresh = true;
			hxmc.unsafe.LibC.free(pixels);
			var n = 4 * (width > 0 ? width : 1) * (height > 0 ? height : 1);
			pixels = hxmc.unsafe.LibC.malloc((n : hxmc.I64));
			this.width = width;
			this.height = height;
		}
		var a = background.a / 255;
		var word = Math.round(background.r * a) | Math.round(background.g * a) << 8 | Math.round(background.b * a) << 16 | background.a << 24;
		if (word != backgroundWord) fresh = true;
		backgroundWord = word;
		var q = quads;
		q.frame(height);
		q.target = pixels;
		q.tw = width;
		q.th = height;
		q.ox = q.oy = 0;
		q.cut();
		regions = null;
		// (kept: the background where the UI's damage is, redraw)
		if (!keep) q.fill(0, 0, width, height, word);
		q.drawnX0 = q.drawnY0 = 0;
		q.drawnX1 = width;
		q.drawnY1 = height;
		atlas.begin();
		// (the atlas's copy the size it is now: copied whole at the next paint)
		if (atlas.width != atlasW || atlas.height != atlasH) {
			hxmc.unsafe.LibC.free(atlasCopy);
			atlasW = atlas.width;
			atlasH = atlas.height;
			var n = atlasW * atlasH;
			atlasCopy = hxmc.unsafe.LibC.malloc((n : hxmc.I64));
			copyAtlas(0, atlasH);
		}
		for (k in [for (k => e in large) if (e.frame < frames - 1) k])
			large.remove(k);
		again = false;
		last.resize(0);
		for (k in scales)
			last.push(k);
		scales.resize(0);
		steady = true;
		open.resize(0);
		pushed.resize(0);
		tx = ty = 0;
		alpha = 1;
		alphas.resize(0);
		clips.resize(0);
		transforms.resize(0);
		ma = md = mk = 1;
		mb = mc = me = mf = 0;
		flat = aligned = true;
		grid = snap;
		clipX0 = clipY0 = clipR0 = clipR1 = clipR2 = clipR3 = 0;
		clipX1 = width;
		clipY1 = height;
	}

	// what was drawn painted: the bands of the frame at once
	@:hxmc.unsafe(gc) function paint() {
		if (atlas.dirtyY1 > atlas.dirtyY0 && atlas.width == atlasW && atlas.height == atlasH) copyAtlas(atlas.dirtyY0, atlas.dirtyY1);
		atlas.clean();
		quads.paint();
	}

	@:hxmc.unsafe(gc) function copyAtlas(y0:Int, y1:Int)
		hxmc.unsafe.LibC.memcpy(atlasCopy.add(y0 * atlasW), hxmc.unsafe.BytesPtr.of(atlas.pixels, y0 * atlasW, (y1 - y0) * atlasW), ((y1 - y0) * atlasW : hxmc.I64));

	@:hxmc.unsafe(gc) function get_frame():Bitmap {
		paint();
		if (frame.width != width || frame.height != height) frame = new Bitmap(width, height);
		if (width * height > 0) hxmc.unsafe.BytesPtr.copyIn(frame.pixels, 0, pixels, width * height * 4);
		return frame;
	}

	#if (helder.soft && !helder.headless)
	// the frame shown in a window, where it changed (helder.os.Blit)
	@:hxmc.unsafe(gc) public function present(s:helder.os.Surface) {
		paint();
		helder.os.Blit.present(s, pixels, width, height, regions);
	}
	#end

	// the frame's pixels as RGBA8, rows top to bottom (as Device.readPixels gives a frame)
	@:hxmc.unsafe(gc) public function readPixels(dst:Bytes) {
		if (dst.length < width * height * 4) throw "SoftCanvas: readPixels: " + width * height * 4 + " bytes needed";
		paint();
		hxmc.unsafe.BytesPtr.copyIn(dst, 0, pixels, width * height * 4);
	}

	function evict(age:Int) {
		for (id in [for (id => e in images) if (frames - e.frame > age) id]) {
			images.get(id).free();
			images.remove(id);
		}
		for (p in [for (p => e in paths) if (frames - e.frame > age) p])
			paths.remove(p);
	}

	// forgets an image's pixels (Renderer.forget)
	public function forget(img:Image) {
		var e = images.get(img.id);
		if (e != null) retired.push(e);
		images.remove(img.id);
	}

	// --- TextureCanvas: no GPU, no layers' tiles, no kept frame or compositor

	#if helder.soft
	// (-D helder.soft: the nodes drawn on a GPU draw on the CPU's, GpuHost)
	var softGpu:Null<SoftGpu> = null;

	public function gpu():SoftGpu {
		if (softGpu == null) softGpu = new SoftGpu(this);
		return softGpu;
	}

	// (its texels as they are now, composited as the Renderer composites a
	// GPU texture: an image's quad of premultiplied pixels)
	@:hxmc.unsafe(gc) public function gpuTexture(t:Texture, id:Int, x:Float, y:Float, w:Float, h:Float, radius:Float = 0.0, ?corners:Corners) {
		var g = softGpu;
		var r = g == null ? hxmc.unsafe.Ptr.nil() : @:privateAccess g.device.impl.textureRecord(t.id());
		if (r.isNull()) return rect(x, y, w, h, radius, GpuPlaceholder.COLOR, 0, 0, corners);
		if (w <= 0 || h <= 0) return;
		var pw = helder.gfx.soft.SoftTexture.width(r, 0), ph = helder.gfx.soft.SoftTexture.height(r, 0);
		var e = images.get(id);
		if (e == null || e.width != pw || e.height != ph) {
			if (e != null) retired.push(e);
			e = new SoftImage(0, pw, ph, Bytes.alloc(pw * ph * 4));
			images.set(id, e);
		}
		helder.gfx.soft.SoftTexture.read(r, 0, 0, e.pixels, 0);
		e.frame = frames;
		// (its texels as they are now: the texture may be drawn again before the frame is painted)
		var texels = quads.scratch(pw * ph * 4);
		hxmc.unsafe.LibC.memcpy(texels, hxmc.unsafe.BytesPtr.of(e.pixels, 0, pw * ph * 4), (pw * ph * 4 : hxmc.I64));
		var s = scale;
		var x0 = (x + tx) * s, y0 = (y + ty) * s, x1 = (x + w + tx) * s, y1 = (y + h + ty) * s;
		this.corners(corners, radius);
		fit(x1 - x0, y1 - y0);
		sides(null, 0);
		var q = quads;
		q.tex = texels;
		q.texW = pw;
		q.texH = ph;
		if (!flat) return shape(x0, y0, x1, y1, 0, 0, 1, 1, Color.WHITE, 0, 2, 0, 0);
		if (culled(x0 - 1, y0 - 1, x1 + 1, y1 + 1)) return;
		quad(x0, y0, x1, y1, 0, 0, 1, 1, Color.WHITE, 0, 2, 0, 1);
	}

	// (a pass recorded into a display list, replayed: run now, before the texture it fills is drawn;
	// a backdrop: captured now)
	public function pass(f:Any) {
		if (Std.isOfType(f, Backdrop)) capture(cast f) else if (softGpu != null) softGpu.run(cast f);
	}

	// (what is drawn so far under b's rectangle, in the target drawn into
	// (the frame, a group), painted first (the bands drawn up to here): its
	// pixels into a texture on the CPU's device; under a transform its bounds)
	@:hxmc.unsafe(gc) function capture(b:Backdrop) {
		var s = scale, x0 = (b.x + tx) * s, y0 = (b.y + ty) * s, x1 = (b.x + b.width + tx) * s, y1 = (b.y + b.height + ty) * s;
		if (!flat) {
			var ax = ma * x0 + mc * y0 + me, bx = ma * x1 + mc * y0 + me, cx = ma * x0 + mc * y1 + me, dx = ma * x1 + mc * y1 + me;
			var ay = mb * x0 + md * y0 + mf, by = mb * x1 + md * y0 + mf, cy = mb * x0 + md * y1 + mf, dy = mb * x1 + md * y1 + mf;
			x0 = Math.min(Math.min(ax, bx), Math.min(cx, dx));
			x1 = Math.max(Math.max(ax, bx), Math.max(cx, dx));
			y0 = Math.min(Math.min(ay, by), Math.min(cy, dy));
			y1 = Math.max(Math.max(ay, by), Math.max(cy, dy));
		}
		b.scale = s;
		b.fx = x0;
		b.fy = y0;
		paint();
		var q = quads, t = q.target;
		var gx0 = Std.int(Math.max(Math.floor(x0), q.ox)), gy0 = Std.int(Math.max(Math.floor(y0), q.oy));
		var gx1 = Std.int(Math.min(Math.ceil(x1), q.ox + q.tw)), gy1 = Std.int(Math.min(Math.ceil(y1), q.oy + q.th));
		var w = gx1 - gx0, h = gy1 - gy0;
		if (w <= 0 || h <= 0) {
			b.texture = null;
			return;
		}
		var d = gpu().device, tex:Null<helder.gfx.Texture> = b.held;
		if (tex == null || b.tw != w || b.th != h) {
			if (tex != null) d.destroyTexture(tex);
			b.held = tex = d.createTexture({width: w, height: h});
		}
		var px = Bytes.alloc(w * h * 4);
		for (r in 0...h)
			hxmc.unsafe.BytesPtr.copyIn(px, r * w * 4, t.add(((gy0 - q.oy + r) * q.tw + gx0 - q.ox) * 4), w * 4);
		d.writeTexture(tex, px);
		b.texture = tex;
		b.px = gx0;
		b.py = gy0;
		b.pw = b.tw = w;
		b.ph = b.th = h;
	}
	#else
	public function gpuTexture(t:Texture, id:Int, x:Float, y:Float, w:Float, h:Float, radius:Float = 0.0, ?corners:Corners)
		rect(x, y, w, h, radius, GpuPlaceholder.COLOR, 0, 0, corners);

	public function pass(f:Any) {}
	#end

	public function layerTiles(l:Layer):Bool
		return false;

	public function keeps():Bool
		return keep;

	public function damage(d:Damage) {
		if (!keep) return;
		// (a new frame's buffer, or another background: all of it)
		if (fresh) d.everything();
		fresh = false;
		d.round(scale, width, height);
		damaged = d;
		regions = d.all ? null : [];
	}

	public function redraw(i:Int) {
		var d = damaged, q = quads;
		if (d == null || i < -1) return;
		if (i < 0) {
			q.cut();
			return;
		}
		var s = scale;
		var x0 = Std.int(Math.max(0, Math.round(d.x0(i) * s))), y0 = Std.int(Math.max(0, Math.round(d.y0(i) * s)));
		var x1 = Std.int(Math.min(width, Math.round(d.x1(i) * s))), y1 = Std.int(Math.min(height, Math.round(d.y1(i) * s)));
		if (regions != null) for (v in [x0, y0, x1, y1])
			regions.push(v);
		q.cut(x0, y0, x1, y1);
		q.fill(x0, y0, x1, y1, backgroundWord);
	}

	public function composites():Bool
		return false;

	public function enter(n:Node, kind:Int):Bool
		return false;

	public function mover(m:Mover):Bool
		return false;

	public function leave() {}

	public function slot(s:LayerSlot, x:Float, y:Float, w:Float, h:Float) {}

	// --- the state

	public function translate(dx:Float, dy:Float) {
		tx += dx;
		ty += dy;
	}

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners) {
		for (v in [clipX0, clipY0, clipX1, clipY1, clipR0, clipR1, clipR2, clipR3])
			clips.push(v);
		var k = scale;
		var x0 = (x + tx) * scale, y0 = (y + ty) * scale, x1 = (x + w + tx) * scale, y1 = (y + h + ty) * scale;
		if (grid && snap) {
			x0 = Math.fround(x0);
			y0 = Math.fround(y0);
			x1 = Math.fround(x1);
			y1 = Math.fround(y1);
		}
		if (!flat) {
			var k = mk, ra = ma / k, rb = mb / k, rc = mc / k, rd = md / k;
			x0 *= k;
			y0 *= k;
			x1 *= k;
			y1 *= k;
			var ax = ra * x0 + rc * y0, bx = ra * x1 + rc * y0, cx = ra * x0 + rc * y1, dx = ra * x1 + rc * y1;
			var ay = rb * x0 + rd * y0, by = rb * x1 + rd * y0, cy = rb * x0 + rd * y1, dy = rb * x1 + rd * y1;
			x0 = Math.min(Math.min(ax, bx), Math.min(cx, dx)) + me;
			x1 = Math.max(Math.max(ax, bx), Math.max(cx, dx)) + me;
			y0 = Math.min(Math.min(ay, by), Math.min(cy, dy)) + mf;
			y1 = Math.max(Math.max(ay, by), Math.max(cy, dy)) + mf;
			k *= mk;
		}
		var inside = x0 >= clipX0 && y0 >= clipY0 && x1 <= clipX1 && y1 <= clipY1;
		var outside = x0 <= clipX0 && y0 <= clipY0 && x1 >= clipX1 && y1 >= clipY1;
		clipX0 = Math.max(clipX0, x0);
		clipY0 = Math.max(clipY0, y0);
		clipX1 = Math.min(clipX1, x1);
		clipY1 = Math.min(clipY1, y1);
		var c0 = (corners == null ? radius : corners.topLeft) * k, c1 = (corners == null ? radius : corners.topRight) * k;
		var c2 = (corners == null ? radius : corners.bottomRight) * k, c3 = (corners == null ? radius : corners.bottomLeft) * k;
		var f = 1.0, cw = w * k, ch = h * k;
		if (c0 + c1 > cw && c0 + c1 > 0) f = Math.min(f, cw / (c0 + c1));
		if (c3 + c2 > cw && c3 + c2 > 0) f = Math.min(f, cw / (c3 + c2));
		if (c0 + c3 > ch && c0 + c3 > 0) f = Math.min(f, ch / (c0 + c3));
		if (c1 + c2 > ch && c1 + c2 > 0) f = Math.min(f, ch / (c1 + c2));
		c0 *= f;
		c1 *= f;
		c2 *= f;
		c3 *= f;
		if (inside) {
			clipR0 = c0;
			clipR1 = c1;
			clipR2 = c2;
			clipR3 = c3;
		} else if (!outside) {
			clipR0 = Math.min(clipR0, c0);
			clipR1 = Math.min(clipR1, c1);
			clipR2 = Math.min(clipR2, c2);
			clipR3 = Math.min(clipR3, c3);
		}
	}

	public function popClip() {
		var n = clips.length - 8, c = clips;
		clipX0 = c[n];
		clipY0 = c[n + 1];
		clipX1 = c[n + 2];
		clipY1 = c[n + 3];
		clipR0 = c[n + 4];
		clipR1 = c[n + 5];
		clipR2 = c[n + 6];
		clipR3 = c[n + 7];
		clips.resize(n);
	}

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {
		for (v in [ma, mb, mc, md, me, mf, mk, flat ? 1 : 0, aligned ? 1 : 0, steady ? 1 : 0])
			transforms.push(v);
		var s = scale;
		var ne = s * (e - a * tx - c * ty + tx), nf = s * (f - b * tx - d * ty + ty);
		var na = ma * a + mc * b, nb = mb * a + md * b, nc = ma * c + mc * d, nd = mb * c + md * d;
		var e2 = ma * ne + mc * nf + me, f2 = mb * ne + md * nf + mf;
		ma = na;
		mb = nb;
		mc = nc;
		md = nd;
		me = e2;
		mf = f2;
		mk = Math.sqrt(Math.abs(ma * md - mb * mc));
		flat = ma == 1 && mb == 0 && mc == 0 && md == 1 && me == 0 && mf == 0;
		aligned = mb == 0 && mc == 0 && ma == md && ma > 0;
		var i = scales.length, still = i >= last.length ? STILL : last[i] == mk ? last[i + 1] + 1 : 0;
		scales.push(mk);
		scales.push(still);
		steady = steady && still >= STILL;
		grid = snap && flat;
	}

	public function popTransform() {
		var n = transforms.length - 10, t = transforms;
		ma = t[n];
		mb = t[n + 1];
		mc = t[n + 2];
		md = t[n + 3];
		me = t[n + 4];
		mf = t[n + 5];
		mk = t[n + 6];
		flat = t[n + 7] == 1;
		aligned = t[n + 8] == 1;
		steady = t[n + 9] == 1;
		transforms.resize(n);
		grid = snap && flat;
	}

	public function pushOpacity(a:Float) {
		alphas.push(alpha);
		pushed.push(0);
		alpha *= a;
	}

	// (as the Renderer's: its bounds' pixels within the clip and the target, a buffer of their own)
	@:hxmc.unsafe(gc) public function pushGroup(a:Float, x:Float, y:Float, w:Float, h:Float) {
		if (!groups || a >= 1) return pushOpacity(a);
		var s = scale;
		var x0 = (x + tx) * s, y0 = (y + ty) * s, x1 = (x + w + tx) * s, y1 = (y + h + ty) * s;
		if (!flat) {
			var k = mk, ra = ma / k, rb = mb / k, rc = mc / k, rd = md / k;
			x0 *= k;
			y0 *= k;
			x1 *= k;
			y1 *= k;
			var ax = ra * x0 + rc * y0, bx = ra * x1 + rc * y0, cx = ra * x0 + rc * y1, dx = ra * x1 + rc * y1;
			var ay = rb * x0 + rd * y0, by = rb * x1 + rd * y0, cy = rb * x0 + rd * y1, dy = rb * x1 + rd * y1;
			x0 = Math.min(Math.min(ax, bx), Math.min(cx, dx)) + me;
			x1 = Math.max(Math.max(ax, bx), Math.max(cx, dx)) + me;
			y0 = Math.min(Math.min(ay, by), Math.min(cy, dy)) + mf;
			y1 = Math.max(Math.max(ay, by), Math.max(cy, dy)) + mf;
		}
		var q = quads, ox = q.ox, oy = q.oy;
		var gx0 = Math.floor(Math.max(Math.max(x0, clipX0), ox)), gy0 = Math.floor(Math.max(Math.max(y0, clipY0), oy));
		var gx1 = Math.ceil(Math.min(Math.min(x1, clipX1), ox + q.tw)), gy1 = Math.ceil(Math.min(Math.min(y1, clipY1), oy + q.th));
		var gw = gx1 - gx0, gh = gy1 - gy0;
		if (gw <= 0 || gh <= 0) return pushOpacity(a);
		var k = open.length;
		while (k >= pool.length)
			pool.push(new SoftGroup());
		var g = pool[k];
		g.open(q.scratch(gw * gh * 4), gw, gh);
		g.x = Std.int(gx0);
		g.y = Std.int(gy0);
		g.alpha = alpha * a;
		g.outer = q.target;
		g.outerW = q.tw;
		g.outerH = q.th;
		g.outerX = ox;
		g.outerY = oy;
		g.outerDrawn = [q.drawnX0, q.drawnY0, q.drawnX1, q.drawnY1];
		q.drawnX0 = q.drawnY0 = 0x3FFFFFFF;
		q.drawnX1 = q.drawnY1 = -0x3FFFFFFF;
		open.push(g);
		alphas.push(alpha);
		pushed.push(1);
		q.target = g.buffer;
		q.tw = gw;
		q.th = gh;
		q.ox = gx0;
		q.oy = gy0;
		// (cleared first, in the bands as what is drawn into it: only where it was drawn, popOpacity)
		g.clear = q.fill(g.x, g.y, g.x + gw, g.y + gh, 0);
		alpha = 1;
	}

	@:hxmc.unsafe(gc) public function popOpacity() {
		alpha = alphas.pop();
		if (pushed.pop() == 0) return;
		var g = open.pop(), q = quads;
		// (what it drew, kept: cleared when it is opened again)
		g.drawn(q.drawnX0 - g.x, q.drawnY0 - g.y, q.drawnX1 - g.x, q.drawnY1 - g.y);
		Quads.narrow(g.clear, g.x + g.dx0, g.y + g.dy0, g.x + g.dx1, g.y + g.dy1);
		q.target = g.outer;
		q.tw = g.outerW;
		q.th = g.outerH;
		q.ox = g.outerX;
		q.oy = g.outerY;
		var d = g.outerDrawn;
		q.drawnX0 = d[0];
		q.drawnY0 = d[1];
		q.drawnX1 = d[2];
		q.drawnY1 = d[3];
		g.outer = hxmc.unsafe.Ptr.nil();
		// (its pixels where they were, at its opacity, as the Renderer's image of it: within its clip)
		q.cx0 = clipX0;
		q.cy0 = clipY0;
		q.cx1 = clipX1;
		q.cy1 = clipY1;
		q.cr0 = clipR0;
		q.cr1 = clipR1;
		q.cr2 = clipR2;
		q.cr3 = clipR3;
		q.group(g.buffer, g.width, g.x, g.y, g.alpha, g.x + g.dx0, g.y + g.dy0, g.x + g.dx1, g.y + g.dy1);
	}

	inline function corners(c:Null<Corners>, radius:Float) {
		var s = scale;
		qr0 = (c == null ? radius : c.topLeft) * s;
		qr1 = (c == null ? radius : c.topRight) * s;
		qr2 = (c == null ? radius : c.bottomRight) * s;
		qr3 = (c == null ? radius : c.bottomLeft) * s;
	}

	inline function fit(w:Float, h:Float) {
		var f = 1.0;
		inline function side(len:Float, a:Float, b:Float)
			if (a + b > len && a + b > 0) f = Math.min(f, len / (a + b));
		side(w, qr0, qr1);
		side(w, qr3, qr2);
		side(h, qr0, qr3);
		side(h, qr1, qr2);
		if (f < 1) {
			qr0 *= f;
			qr1 *= f;
			qr2 *= f;
			qr3 *= f;
		}
	}

	inline function sides(e:Null<Edges>, width:Float) {
		var s = scale;
		qw0 = side((e == null ? width : e.top) * s);
		qw1 = side((e == null ? width : e.right) * s);
		qw2 = side((e == null ? width : e.bottom) * s);
		qw3 = side((e == null ? width : e.left) * s);
	}

	inline function side(w:Float):Float
		return grid && w > 0 ? Math.max(1, Math.fround(w)) : w;

	inline function edges(x0:Float, y0:Float, x1:Float, y1:Float) {
		if (grid) {
			ex0 = Math.fround(x0);
			ey0 = Math.fround(y0);
			ex1 = Math.fround(x1);
			ey1 = Math.fround(y1);
		} else {
			ex0 = x0;
			ey0 = y0;
			ex1 = x1;
			ey1 = y1;
		}
	}

	// --- the drawing

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges,
			style:BorderStyle = Solid) {
		if (w <= 0 || h <= 0) return;
		dash = style;
		var s = scale;
		edges((x + tx) * s, (y + ty) * s, (x + w + tx) * s, (y + h + ty) * s);
		var x0 = ex0, y0 = ey0, x1 = ex1, y1 = ey1;
		this.corners(corners, radius);
		fit(x1 - x0, y1 - y0);
		this.sides(sides, borderWidth);
		if (!flat) return shape(x0, y0, x1, y1, 0, 0, 0, 0, fill, border, 0, 0, 0);
		if (culled(x0 - 1, y0 - 1, x1 + 1, y1 + 1)) return;
		quad(x0, y0, x1, y1, 0, 0, 0, 0, fill, border, 0, 0, 1);
	}

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners, ?offset:Array<Float>) {
		if (w <= 0 || h <= 0 || color.a == 0) return;
		var s = scale;
		edges((x + tx) * s, (y + ty) * s, (x + w + tx) * s, (y + h + ty) * s);
		var x0 = ex0, y0 = ey0, x1 = ex1, y1 = ey1;
		this.corners(corners, radius);
		fit(x1 - x0, y1 - y0);
		if (offset != null) {
			qw0 = offset[0] * s;
			qw1 = offset[1] * s;
			qw2 = offset[2] * s;
			qw3 = 1;
		} else sides(null, 0);
		var sigma = blur * s / 2;
		if (!flat) return shape(x0, y0, x1, y1, 0, 0, 0, 0, color, 0, 3, sigma, 3 * sigma);
		var m = 3 * sigma + 1;
		if (culled(x0 - m, y0 - m, x1 + m, y1 + m)) return;
		quad(x0, y0, x1, y1, 0, 0, 0, 0, color, 0, 3, sigma, m);
	}

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, dx:Float, dy:Float, spread:Float,
			?corners:Corners) {
		if (w <= 0 || h <= 0 || color.a == 0) return;
		var s = scale;
		edges((x + tx) * s, (y + ty) * s, (x + w + tx) * s, (y + h + ty) * s);
		var x0 = ex0, y0 = ey0, x1 = ex1, y1 = ey1;
		this.corners(corners, radius);
		fit(x1 - x0, y1 - y0);
		qw0 = dx * s;
		qw1 = dy * s;
		qw2 = spread * s;
		qw3 = 0;
		var sigma = blur * s / 2;
		if (!flat) return shape(x0, y0, x1, y1, 0, 0, 0, 0, color, 0, 4, sigma, 0);
		if (culled(x0 - 1, y0 - 1, x1 + 1, y1 + 1)) return;
		quad(x0, y0, x1, y1, 0, 0, 0, 0, color, 0, 4, sigma, 1);
	}

	// (rasterized by helder.canvas at the scale drawn, as the Renderer's, kept while drawn the same way)
	public function path(p:Path, fill:Null<Paint>, ?stroke:Stroke) {
		var b = p.bounds(), s = scale;
		var reach = stroke == null ? 0.0 : stroke.width / 2 * ((stroke.join ?? Miter) == Miter ? Math.max(1, stroke.miterLimit ?? 4) : 1.5);
		var x0 = Math.floor((b.x - reach) * s) - 1, y0 = Math.floor((b.y - reach) * s) - 1;
		var w = Std.int(Math.ceil((b.x + b.width + reach) * s) + 1 - x0), h = Std.int(Math.ceil((b.y + b.height + reach) * s) + 1 - y0);
		if (flat) {
			var cx0 = Math.floor(clipX0 - tx * s) - 1, cy0 = Math.floor(clipY0 - ty * s) - 1;
			var cx1 = Math.ceil(clipX1 - tx * s) + 1, cy1 = Math.ceil(clipY1 - ty * s) + 1;
			var nx0 = Std.int(Math.max(x0, cx0)), ny0 = Std.int(Math.max(y0, cy0));
			var nx1 = Std.int(Math.min(x0 + w, cx1)), ny1 = Std.int(Math.min(y0 + h, cy1));
			if (nx1 <= nx0 || ny1 <= ny0) return;
			x0 = nx0;
			y0 = ny0;
			w = nx1 - nx0;
			h = ny1 - ny0;
		}
		if (w <= 0 || h <= 0 || w * h > 4096 * 4096) return;
		var e = paths.get(p);
		if (e == null || !e.same(s, p, fill, stroke) || e.x != x0 / s || e.y != y0 / s || e.img.width != w || e.img.height != h) {
			e = new PathImage(s, p, fill, stroke, p.render(w, h, [s, 0, 0, s, -x0, -y0], fill, stroke), x0 / s, y0 / s);
			paths.set(p, e);
		}
		e.frame = frames;
		image(e.img, e.x, e.y, w / s, h / s, 0, 0, 1, 1, 0);
	}

	public function image(img:Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners) {
		if (w <= 0 || h <= 0) return;
		var s = scale;
		var x0 = (x + tx) * s, y0 = (y + ty) * s, x1 = (x + w + tx) * s, y1 = (y + h + ty) * s;
		if (grid) {
			var iw = Math.max(1, Math.fround(x1 - x0)), ih = Math.max(1, Math.fround(y1 - y0));
			x0 = Math.fround(x0);
			y0 = Math.fround(y0);
			x1 = x0 + iw;
			y1 = y0 + ih;
		}
		this.corners(corners, radius);
		fit(x1 - x0, y1 - y0);
		sides(null, 0);
		if (!flat) {
			if (!texture(img)) return;
			return shape(x0, y0, x1, y1, u0, v0, u1, v1, Color.WHITE, 0, 2, 0, 0);
		}
		if (culled(x0 - 1, y0 - 1, x1 + 1, y1 + 1) || !texture(img)) return;
		quad(x0, y0, x1, y1, u0, v0, u1, v1, Color.WHITE, 0, 2, 0, 1);
	}

	// (an image's premultiplied pixels for Quads: kept by id while its version
	// stands; another process's texture has none here: its place grey)
	@:hxmc.unsafe(gc) function texture(img:Image):Bool {
		var e = images.get(img.id);
		if (e == null || e.version != img.version || e.width != img.width || e.height != img.height) {
			var px:Null<Bytes> = null;
			if (img.shared == null) try img.premultiplied(pre -> {
				px = Bytes.alloc(img.width * img.height * 4);
				px.blit(0, pre, 0, px.length);
			}) catch (e:Dynamic) {}
			var old = images.get(img.id);
			if (old != null) retired.push(old);
			if (px == null) {
				px = Bytes.alloc(4);
				px.fill(0, 3, GpuPlaceholder.COLOR.r);
				px.set(3, 255);
				e = new SoftImage(img.version, 1, 1, px);
			} else e = new SoftImage(img.version, img.width, img.height, px);
			images.set(img.id, e);
		}
		e.frame = frames;
		var q = quads;
		q.tex = e.ptr;
		q.texW = e.width;
		q.texH = e.height;
		return true;
	}

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>)
		glyphs(p, x, y, width, align, color, colors, -1);

	public function textShadow(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, blur:Float, ?colors:Array<Color>)
		glyphs(p, x, y, width, align, color, colors, blur);

	// (as Renderer.glyphs: blur < 0 the text itself)
	function glyphs(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, colors:Null<Array<Color>>, blur:Float) {
		var dp = cast(p, DrawParagraph);
		var t = dp.layout, s = scale;
		var size = t.fonts.size * s;
		var ox = x + tx, oy = y + ty;
		if (!flat) {
			if (mk < 1e-6) return;
			s *= mk;
			size *= mk;
		}
		var sigma = blur > 0 ? Math.round(blur * s / 2 * 4) / 4 : 0.0, reach = 3 * sigma;
		for (l in t.lines) {
			var lx = switch align {
				case Center: (width - l.width) / 2;
				case Right: width - l.width;
				case _: 0.0;
			}
			var by = Math.round((oy + l.top + l.baseline) * s + (flat ? 0 : mf - Std.int(mf)));
			var lineX = (ox + lx) * s;
			if (grid) lineX = Math.fround(lineX);
			if (flat && (by - size * 1.5 - reach > clipY1 || by + size + reach < clipY0)) continue;
			if (!flat && away(lineX - size, by - size * 1.5 - reach, lineX + l.width * s + size, by + size + reach)) continue;
			for (i in l.glyphStart...l.glyphEnd) {
				var c = t.glyphChar(i);
				if (c == 32 || c == 10 || c == 9 || t.glyphHidden(i)) continue;
				var id = t.glyphId(i), run = t.glyphRun(i);
				var gx = lineX + (t.glyphX(i) + t.glyphOffsetX(i)) * s, gy = by + Math.round(t.glyphOffsetY(i) * s);
				var f = t.glyphFont(i);
				var set = t.glyphFontSet(i);
				var size = run < 0 ? size : set.size * s, oblique = set.oblique;
				var color = run >= 0 && colors != null && run < colors.length ? colors[run] : color;
				if (f.hasColor && blur < 0) {
					var layers = f.colorLayers(id);
					if (layers != null) {
						for (layer in layers)
							glyph(f, layer.glyph, size, gx, gy, layer.color == -1 ? color : (layer.color : Color), oblique);
						continue;
					}
					var b = colorGlyph(f, id, size);
					if (b != null) {
						var ex = flat ? 0.0 : me - Std.int(me), ey = flat ? 0.0 : mf - Std.int(mf);
						var qx = Math.round(gx + b.left + ex) - ex, qy = gy - b.top - ey;
						if ((!flat || !culled(qx, qy, qx + b.image.width, qy + b.image.height)) && texture(b.image)) {
							qr0 = qr1 = qr2 = qr3 = qw0 = qw1 = qw2 = qw3 = 0;
							quad(qx, qy, qx + b.image.width, qy + b.image.height, 0, 0, 1, 1, Color.WHITE, 0, 2, 0, 1);
						}
						continue;
					}
				}
				glyph(f, id, size, gx, gy, color, oblique, sigma);
			}
		}
	}

	@:hxmc.unsafe(gc) function glyph(f:helder.text.FontFile, id:Int, size:Float, gx:Float, gy:Int, color:Color, oblique:Bool, sigma = 0.0) {
		var ex = flat ? 0.0 : me - Std.int(me), ey = flat ? 0.0 : mf - Std.int(mf);
		if (!flat && away(gx - size, gy - size * 1.5 - 3 * sigma, gx + size * 2, gy + size + 3 * sigma)) return;
		var at = size;
		if (steps && !steady && mk != 1) {
			at = Math.pow(2, Math.round(Math.log(size) / Math.log(2) * 4) / 4);
			sigma = sigma * at / size;
			again = true;
		}
		var k = size / at, ix = GlyphAtlas.pixel(gx + ex, size), sub = k == 1 ? GlyphAtlas.phase(gx + ex, size) : 0;
		var a = at > LARGE ? null : atlas.get(f, id, at, sub, oblique, sigma, color & 0xFFFFFF);
		if (a == null) return alone(f, id, at, k, gx, gy, ix, ex, ey, sub, color, oblique, sigma);
		if (a.w <= 0) return;
		var qx = k == 1 ? ix - ex + a.left : gx + a.left * k, qy = gy + a.top * k - ey;
		if (flat && culled(qx, qy, qx + a.w, qy + a.h)) return;
		qr0 = qr1 = qr2 = qr3 = qw0 = qw1 = qw2 = qw3 = 0;
		stretched = k != 1;
		blend = a.blend;
		var q = quads, w = atlas.width, h = atlas.height;
		q.tex = atlasCopy;
		q.texW = w;
		q.texH = h;
		quad(qx, qy, qx + a.w * k, qy + a.h * k, a.x / w, a.y / h, (a.x + a.w) / w, (a.y + a.h) / h, color, 0, 1, 0, 0);
		stretched = false;
		blend = null;
	}

	function alone(f:helder.text.FontFile, id:Int, size:Float, k:Float, gx:Float, gy:Int, ix:Int, ex:Float, ey:Float, sub:Int, color:Color,
			oblique:Bool, sigma:Float) {
		var key = f.id + ":" + id + ":" + size + ":" + sub + (oblique ? ":o" : "") + ":" + sigma + ":" + (color & 0xFFFFFF);
		var e = large.get(key);
		if (e == null) {
			var b = atlas.bitmap(f, id, size, sub, oblique, sigma, color & 0xFFFFFF);
			if (b == null) return;
			var w = b.width, h = b.height, rgba = Bytes.alloc(w * h * 4);
			var r = color.r, g = color.g, bl = color.b;
			for (i in 0...w * h) {
				rgba.set(i * 4, r);
				rgba.set(i * 4 + 1, g);
				rgba.set(i * 4 + 2, bl);
				rgba.set(i * 4 + 3, b.pixels.get(i));
			}
			large.set(key, e = {image: new Image(w, h, rgba), left: b.left, top: b.top, frame: 0});
		}
		e.frame = frames;
		var img = e.image;
		var qx = k == 1 ? ix - ex + e.left : gx + e.left * k, qy = gy + e.top * k - ey;
		var x1 = qx + img.width * k, y1 = qy + img.height * k;
		if (flat && culled(qx, qy, x1, y1) || !texture(img)) return;
		qr0 = qr1 = qr2 = qr3 = qw0 = qw1 = qw2 = qw3 = 0;
		quad(qx, qy, x1, y1, 0, 0, 1, 1, ((color : Int) | 0xFFFFFF : Color), 0, 2, 0, 0);
	}

	function colorGlyph(f:helder.text.FontFile, id:Int, size:Float):Null<{image:Image, left:Float, top:Int}> {
		var key = f.id + ":" + id + ":" + size;
		if (colorGlyphs.exists(key)) return colorGlyphs.get(key);
		var r:Null<{image:Image, left:Float, top:Int}> = null;
		var b = f.colorBitmap(id, size);
		if (b != null) {
			var d = try PngDecoder.decode(b.png) catch (e:Dynamic) null;
			if (d != null) {
				var k = size / b.ppem;
				var w = Std.int(Math.max(1, Math.round(d.width * k))), h = Std.int(Math.max(1, Math.round(d.height * k)));
				r = {image: new Image(w, h, Resize.area(d.rgba, d.width, d.height, w, h)), left: b.left * k, top: Math.round(b.top * k)};
			}
		}
		colorGlyphs.set(key, r);
		return r;
	}

	// --- quads

	inline function culled(x0:Float, y0:Float, x1:Float, y1:Float)
		return x1 <= clipX0 || y1 <= clipY0 || x0 >= clipX1 || y0 >= clipY1 || clipX1 <= clipX0 || clipY1 <= clipY0;

	function away(x0:Float, y0:Float, x1:Float, y1:Float):Bool {
		var k = mk, ra = ma / k, rb = mb / k, rc = mc / k, rd = md / k;
		var ax = ra * x0 + rc * y0, bx = ra * x1 + rc * y0, cx = ra * x0 + rc * y1, dx = ra * x1 + rc * y1;
		var ay = rb * x0 + rd * y0, by = rb * x1 + rd * y0, cy = rb * x0 + rd * y1, dy = rb * x1 + rd * y1;
		return culled(Math.min(Math.min(ax, bx), Math.min(cx, dx)) + me, Math.min(Math.min(ay, by), Math.min(cy, dy)) + mf,
			Math.max(Math.max(ax, bx), Math.max(cx, dx)) + me, Math.max(Math.max(ay, by), Math.max(cy, dy)) + mf);
	}

	function shape(x0:Float, y0:Float, x1:Float, y1:Float, u0:Float, v0:Float, u1:Float, v1:Float, fill:Color, border:Color, mode:Int, blur:Float,
			grow:Float) {
		var k = mk;
		if (k < 1e-6) return;
		x0 *= k;
		y0 *= k;
		x1 *= k;
		y1 *= k;
		var m = grow * k + 1;
		if (away(x0 - m, y0 - m, x1 + m, y1 + m)) return;
		qr0 *= k;
		qr1 *= k;
		qr2 *= k;
		qr3 *= k;
		qw0 *= k;
		qw1 *= k;
		qw2 *= k;
		qw3 *= k;
		quad(x0, y0, x1, y1, u0, v0, u1, v1, fill, border, mode, blur * k, m);
	}

	// (Renderer.quad's instance, drawn: its texture set before, Quads.tex)
	function quad(x0:Float, y0:Float, x1:Float, y1:Float, u0:Float, v0:Float, u1:Float, v1:Float, fill:Color, border:Color, mode:Int, blur:Float,
			m:Float) {
		var q = quads;
		var w0 = qw0, w1 = qw1, w2 = qw2, w3 = qw3, filtered = 0.0;
		var ax = x0 - m, ay = y0 - m, bx = x1 + m, by = y1 + m;
		if (mode == 1) {
			filtered = aligned && !stretched ? 0 : 1;
		} else if (mode == 0) {
			filtered = (cast dash : Int);
			dash = Solid;
		}
		var fa = fill.a / 255 * alpha, ba = border.a / 255 * alpha;
		if (fa <= 0 && (mode != 0 || ba <= 0)) return;
		var hx = (x1 - x0) / 2, hy = (y1 - y0) / 2;
		var mu = (u1 - u0) * m / (x1 - x0), mv = (v1 - v0) * m / (y1 - y0);
		var k = mk, ra = flat ? 1 : ma / k, rb = flat ? 0 : mb / k, rc = flat ? 0 : mc / k, rd = flat ? 1 : md / k, te = flat ? 0 : me, tf = flat ? 0 : mf;
		var pax = ra * ax + rc * ay + te, pay = rb * ax + rd * ay + tf;
		var pbx = ra * bx + rc * ay + te, pby = rb * bx + rd * ay + tf;
		var pcx = ra * ax + rc * by + te, pcy = rb * ax + rd * by + tf;
		var pdx = pbx + pcx - pax, pdy = pby + pcy - pay;
		q.mode = mode;
		q.flat = flat;
		q.ax = pax;
		q.ay = pay;
		q.bx = pbx;
		q.by = pby;
		q.lx = pcx;
		q.ly = pcy;
		q.x0 = Math.min(Math.min(pax, pbx), Math.min(pcx, pdx));
		q.y0 = Math.min(Math.min(pay, pby), Math.min(pcy, pdy));
		q.x1 = Math.max(Math.max(pax, pbx), Math.max(pcx, pdx));
		q.y1 = Math.max(Math.max(pay, pby), Math.max(pcy, pdy));
		if (flat) {
			var cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, ix = Math.ffloor(cx), iy = Math.ffloor(cy);
			q.cx = ix;
			q.cy = iy;
			q.fx = cx - ix;
			q.fy = cy - iy;
		}
		q.hx = hx;
		q.hy = hy;
		q.ex = hx + m;
		q.ey = hy + m;
		q.u0 = u0 - mu;
		q.v0 = v0 - mv;
		q.u1 = u1 + mu;
		q.v1 = v1 + mv;
		q.fr = fill.r / 255 * fa;
		q.fg = fill.g / 255 * fa;
		q.fb = fill.b / 255 * fa;
		q.fa = fa;
		q.br = border.r / 255 * ba;
		q.bg = border.g / 255 * ba;
		q.bb = border.b / 255 * ba;
		q.ba = ba;
		var gb = mode == 1 ? blend : null;
		q.contrast = gb != null ? 1 + gb.contrast : 0;
		if (gb != null) {
			q.g0 = gb.ratios[0];
			q.g1 = gb.ratios[1];
			q.g2 = gb.ratios[2];
			q.g3 = gb.ratios[3];
		}
		q.r0 = qr0;
		q.r1 = qr1;
		q.r2 = qr2;
		q.r3 = qr3;
		q.w0 = mode == 1 || mode == 2 ? 0 : w0;
		q.w1 = mode == 1 || mode == 2 ? 0 : w1;
		q.w2 = mode == 1 || mode == 2 ? 0 : w2;
		q.w3 = mode == 1 || mode == 2 ? 0 : w3;
		q.blur = blur;
		q.style = filtered;
		q.cx0 = clipX0;
		q.cy0 = clipY0;
		q.cx1 = clipX1;
		q.cy1 = clipY1;
		q.cr0 = clipR0;
		q.cr1 = clipR1;
		q.cr2 = clipR2;
		q.cr3 = clipR3;
		q.draw();
	}
}

// (an image's premultiplied pixels, the version they are of, the last
// frame that drew it; a copy outside the collector's heap, which bands read)
@:hxmc.unsafe(gc)
private class SoftImage {
	public final version:Int;
	public final width:Int;
	public final height:Int;
	public final pixels:Bytes;
	public var ptr:hxmc.unsafe.Ptr;
	public var frame = 0;

	public function new(version, width, height, pixels:Bytes) {
		this.version = version;
		this.width = width;
		this.height = height;
		this.pixels = pixels;
		var n = pixels.length > 0 ? pixels.length : 4;
		ptr = hxmc.unsafe.LibC.malloc((n : hxmc.I64));
		hxmc.unsafe.LibC.memcpy(ptr, hxmc.unsafe.BytesPtr.of(pixels, 0, pixels.length), (pixels.length : hxmc.I64));
	}

	public function free() {
		hxmc.unsafe.LibC.free(ptr);
		ptr = hxmc.unsafe.Ptr.nil();
	}
}

// (an opacity group: its buffer (grown, kept), the part drawn and where it
// is in the frame, its opacity, the target it was opened in)
@:hxmc.unsafe(gc)
private class SoftGroup {
	public var buffer = hxmc.unsafe.Ptr.nil();
	public var clear = hxmc.unsafe.Ptr.nil();
	public var x = 0;
	public var y = 0;
	// (what was drawn into it, from its top left: all that is not transparent)
	public var dx0 = 0;
	public var dy0 = 0;
	public var dx1 = 0;
	public var dy1 = 0;
	public var outerDrawn:Array<Int> = [];
	public var width = 0;
	public var height = 0;
	public var alpha = 1.0;
	public var outer = hxmc.unsafe.Ptr.nil();
	public var outerW = 0;
	public var outerH = 0;
	public var outerX = 0;
	public var outerY = 0;

	public function new() {}

	// (a buffer of a group's size, the frame's, cleared as it is painted)
	public function open(buffer:hxmc.unsafe.Ptr, w:Int, h:Int) {
		this.buffer = buffer;
		width = w;
		height = h;
		dx0 = dy0 = dx1 = dy1 = 0;
	}

	public function drawn(x0:Int, y0:Int, x1:Int, y1:Int) {
		dx0 = x0 < 0 ? 0 : x0;
		dy0 = y0 < 0 ? 0 : y0;
		dx1 = x1 > width ? width : x1;
		dy1 = y1 > height ? height : y1;
		if (dx1 <= dx0 || dy1 <= dy0) dx0 = dy0 = dx1 = dy1 = 0;
	}
}
