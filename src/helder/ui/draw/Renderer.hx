package helder.ui.draw;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.text.GlyphAtlas;
import helder.ui.*;
import helder.ui.Paint;
import helder.ui.Stroke;
import helder.ui.draw.DrawText;
import helder.image.Image;
import helder.image.PngDecoder;
import helder.image.Resize;
import helder.ui.draw.UiShader;

// helder.ui's Canvas on helder.gfx (Ui.paint walks its layers' display
// lists onto it: Layer, DisplayList): a frame's rectangles, borders, shadows, glyphs and
// images are instances of one quad (UiShader's, after Rune's
// uber-quad: anomalyco/rune, MIT), each a kind of it, all in one instance
// buffer (helder.gfx's QuadBatch, instanced; the batcher SpriteBatch is on
// too), in the order drawn, and drawn as one instanced draw: a frame is one
// draw call, one pipeline. What would split it is shared instead: every
// instance carries the clip (a rectangle in target pixels and its corners'
// radii) that UiShader clips its fragments by, so clips need no scissor and
// rounded ones clip to their corners; the glyph atlas is read filtered (a
// glyph under a turning transform) or at its texels' centres, an instance
// choosing; images of up to PAGED pixels a side (paths' and SVGs'
// rasterizations, gradients, icons, colour glyphs) share atlas pages
// (PAGE pixels square, up to PAGES of them, an image's place in one kept
// while it is drawn), each read clamped to its own texels, so that images
// do not split the draw either. What has a texture of its own (a larger
// image, a browser's, a <Scene>'s GPU texture) is bound in the image slot
// in turn: a draw for each change of it, in the order drawn, painter's
// order kept. Opacity multiplies each quad's colour (pushOpacity), or,
// a group (pushGroup, where the caller records prepare's passes: groups),
// its quads are drawn into a render target of their bounds' size in a pass
// of their own before the frame's, inner groups first, and that drawn in
// their place as an image at its opacity, as CSS's opacity is: a faded box's
// children not seen through each other nor its background through them.
// Transforms are each quad's, so they need no pass; a <Scene>'s passes come
// before the frame's (beforePass: recorded into the display list a node
// found the renderer through, so that a list kept still runs them). A
// layer (Layer) may be drawn from tiles of its own, render targets kept
// from frame to frame (layerTiles); a window's frame kept, only what changed
// drawn into it (keep). The instance buffer is kept between frames: only the
// instances that changed since the last frame are written (QuadBatch). The UI's pixels are scaled
// to the target's (scale: a Retina display's 2); glyphs are rasterized at the
// scaled size into the GlyphAtlas, its coverage uploaded into a texture's
// red channel where it changed. An image is
// uploaded once (premultiplied, filtered linearly) and again when its
// version changes; forget(image) frees its texture. Under a transform
// (pushTransform) a quad is built in the transform's scaled pixels (its
// scale: the square root of its determinant) and its corners turned into the
// target's by what remains (a rotation, or a skew), so that edges stay
// anti-aliased over a pixel; glyphs are rasterized at the scaled size, and
// read filtered where the transform turns them; culled before they are
// rasterized; while its scale moves (a pinch) at the nearest quarter
// octave, stretched, at their own once it rests (again). Glyphs past LARGE
// are images of their own; the atlas begins with each frame, so that it is
// never changed under one (GlyphAtlas), and grows to the GPU's largest
// texture (at most 4096 a side). A clip pushed under a turning
// transform clips to its bounds. Snapped (snap, the default), what is laid
// out without a transform lies on the target's pixel grid, as a browser's
// layout snaps its boxes: a box's edges, a clip's, an image's origin (its
// size whole pixels), a border's width (at least a pixel), a line of text's
// origin, each rounded to a whole device pixel, so that at a fractional
// scale (a phone's 2.8125) a box or a line of text at rest is crisp and the
// same wherever its points fall, and a hairline is not smeared over two.
// What is under a transform is never snapped: a transform is how things
// move (a mark following the camera, a spring, a tween), and a moving thing
// placed at whole pixels steps from one to the next instead of gliding.
class Renderer implements TextureCanvas {
	public final device:Device;
	public var scale = 1.0;
	// whether unturned, unscaled drawing is put on the pixel grid
	public var snap = true;
	public final atlas:GlyphAtlas;

	final pipeline:Pipeline;
	var atlasTexture:Texture;
	var atlasW = 0;
	var atlasH = 0;
	final blank:Texture;
	final linear:Sampler;
	// the shader's texture slots: the atlas's, the image's
	final atlasSlot:Int;
	final imageSlot:Int;
	// the frame's quads, an instance each, in runs: a run's image texture bound (its index)
	final quads = new QuadBatch(STRIDE, 1024, true);
	// the runs' image textures (null: none drawn)
	final frameTextures:Array<Null<Texture>> = [];
	// (the quads drawn into: the frame's, or an opacity group's; its runs' textures, its run)
	var batch:QuadBatch;
	var runTextures:Array<Null<Texture>>;
	var run = 0;
	// whether pushGroup draws a group into a texture of its own: the caller
	// records prepare's passes before the frame's (else its opacity is each quad's)
	public var groups = false;
	// (the groups open, closed this frame (inner first), and kept for the
	// next frames; what pushOpacity and pushGroup pushed: 1 a group, 0 not)
	final openGroups:Array<Group> = [];
	final closedGroups:Array<Group> = [];
	final groupPool:Array<Group> = [];
	final pushed:Array<Int> = [];
	var groupPipeline:Null<Pipeline> = null;
	var clearPipeline:Null<Pipeline> = null;
	// (where the quads' target pixels start in the target drawn into: a group's origin)
	var ox = 0.0;
	var oy = 0.0;
	// (an image by its id: its texture and place; frame: the last one that drew it; one not drawn for EVICT frames is freed)
	final textures = new Map<Int, ImageEntry>();
	// the images' atlas pages
	final pages:Array<ImagePage> = [];
	// other processes' textures by their handles (shared images: helder.story's
	// native preview host's frames), opened once, the last frame that drew each
	final opened = new Map<String, {texture:Texture, frame:Int}>();
	final staleShared:Array<String> = [];
	// the frames begun (begin)
	public var frames(default, null) = 0;
	// the GPU textures drawn this frame (texture: by their negative ids), the passes to record before the frame's (beforePass)
	final gpu = new Map<Int, Texture>();
	final before:Array<Encoder->Void> = [];
	final next:Array<Encoder->Void> = [];
	// (the atlas's changed region as RGBA: grown, kept)
	var region = Bytes.alloc(0);
	// (the ids evicted, kept)
	final stale:Array<Int> = [];
	final stalePaths:Array<Path> = [];

	static inline var EVICT = 300;
	// an image page's size, how many there may be, the largest side of an image put in one
	public static inline var PAGE = 1024;
	public static inline var PAGES = 4;
	public static inline var PAGED = 256;
	// (when the frame began: FrameCounts.uiMs from it to the pass encoded)
	var began = 0.0;
	var beganBytes = 0.0;
	var targetW = 1.0;
	var targetH = 1.0;

	// the state
	var tx = 0.0;
	var ty = 0.0;
	var alpha = 1.0;
	final alphas:Array<Float> = [];
	final clips:Array<Float> = []; // the clips pushed over: x0, y0, x1, y1, the corners' radii (8 each)
	var clipX0 = 0.0;
	var clipY0 = 0.0;
	var clipX1 = 0.0;
	var clipY1 = 0.0;
	// (its corners' radii: top left, top right, bottom right, bottom left)
	var clipR0 = 0.0;
	var clipR1 = 0.0;
	var clipR2 = 0.0;
	var clipR3 = 0.0;
	// the next quad's corners' radii and border sides (top, right, bottom, left), in its pixels
	var qr0 = 0.0;
	var qr1 = 0.0;
	var qr2 = 0.0;
	var qr3 = 0.0;
	var qw0 = 0.0;
	var qw1 = 0.0;
	var qw2 = 0.0;
	var qw3 = 0.0;
	// the transform pushed (target pixels from the scaled pixels after the
	// translation, scale, and transforms before it): m* (flat: none), its
	// scale (mk), whether it keeps glyphs on the pixel grid (aligned: no
	// turn, no skew, the same scale on both axes)
	var ma = 1.0;
	var mb = 0.0;
	var mc = 0.0;
	var md = 1.0;
	var me = 0.0;
	var mf = 0.0;
	var mk = 1.0;
	var flat = true;
	var aligned = true;
	// (on the pixel grid: snapped, and no transform)
	var grid = true;
	final transforms:Array<Float> = []; // (10 each)
	// (the transforms' scales this frame and the last, in the order pushed,
	// each with the frames it has kept it; steady: each pushed over has kept
	// its for STILL frames, a pinch's events coming slower than frames)
	static inline var STILL = 6;
	final scales:Array<Float> = [];
	final last:Array<Float> = [];
	var steady = true;
	// (a glyph read stretched: drawn at a step's size, scaled)
	var stretched = false;
	// whether glyphs under a scale that moves are drawn at steps (a
	// window's, which draws again once it rests: UiWindow; not a renderer
	// drawing several surfaces in turn, whose transforms are not one's)
	public var steps = false;
	// whether the frame drew glyphs at a step's size under a scale that
	// moved: the next frame draws them at theirs
	public var again(default, null) = false;

	static inline var STRIDE = 224; // UiVertex's instance: 56 floats

	// (UiShader's vertex: its corner from a buffer of four, the rest an instance's)
	static function layout():Array<VertexBufferLayout> {
		var a = UiShader.layout[0].attributes;
		return [
			{stride: 8, attributes: [a[0]]},
			{
				stride: STRIDE,
				step: Instance,
				attributes: [for (k in 1...a.length) {location: a[k].location, format: a[k].format, offset: a[k].offset - 8}]
			}
		];
	}

	// (format: a render target's, drawn into in a pass of its own; by default the frame's)
	public function new(device:Device, ?atlas:GlyphAtlas, ?format:TextureFormat) {
		this.device = device;
		this.atlas = atlas == null ? new GlyphAtlas(1024, 1024) : atlas;
		// (grown to what the GPU takes, at most 4096 a side: 64 MB as RGBA)
		this.atlas.max = Std.int(Math.min(device.maxTextureSize, 4096));
		var d = UiShader.pipeline({blend: Premultiplied});
		d.layout = layout();
		if (format != null) d.colorFormat = format;
		pipeline = device.createPipeline(d);
		atlasTexture = device.createTexture({width: atlasW = this.atlas.width, height: atlasH = this.atlas.height, format: RGBA8});
		blank = device.createTexture({width: 1, height: 1, format: RGBA8, data: Bytes.ofHex("ffffffff")});
		linear = device.createSampler({filter: Linear, wrap: Clamp});
		atlasSlot = UiShader.textures[0].binding;
		imageSlot = UiShader.textures[1].binding;
		batch = quads;
		runTextures = frameTextures;
	}

	// starts a frame's drawing into a target of width x height pixels
	public function begin(width:Int, height:Int) {
		// (the textures of images no longer drawn: a replaced image, an svg drawn again at another size)
		frames++;
		began = haxe.Timer.stamp();
		#if (target.name == "hxmc")
		beganBytes = hxmc.GcStats.bytesAllocated();
		#end
		if (frames % 60 == 0) evict(EVICT);
		recording = null;
		drawn = 0;
		regions.resize(0);
		whole = cutting = false;
		if (!keep) keptValid = false;
		if (tileBytes > tileBudget || frames % 60 == 0) evictTiles(false);
		atlas.begin();
		// (the large glyphs the last frame did not draw: their textures freed)
		if (large.iterator().hasNext()) {
			for (k in [for (k => e in large) if (e.frame < frames - 1) k]) {
				forget(large.get(k).image);
				large.remove(k);
			}
		}
		again = false;
		backdropsLast = backdrops;
		backdrops = 0;
		last.resize(0);
		for (k in scales)
			last.push(k);
		scales.resize(0);
		steady = true;
		targetW = frameW = width;
		targetH = frameH = height;
		gpu.clear();
		before.resize(0);
		for (f in next)
			before.push(f);
		next.resize(0);
		quads.clear();
		batch = quads;
		runTextures = frameTextures;
		run = 0;
		runTextures.resize(0);
		runTextures.push(null);
		openGroups.resize(0);
		closedGroups.resize(0);
		pushed.resize(0);
		ox = oy = 0;
		tx = ty = 0;
		alpha = 1;
		alphas.resize(0);
		clips.resize(0);
		clipFrames.resize(0);
		clipFrame = contentFrame = thumbTag = -1;
		frameStack.resize(0);
		uncull = templating = false;
		transforms.resize(0);
		ma = md = mk = 1;
		mb = mc = me = mf = 0;
		flat = aligned = true;
		grid = snap;
		clipX0 = clipY0 = clipR0 = clipR1 = clipR2 = clipR3 = 0;
		clipX1 = width;
		clipY1 = height;
	}

	// uploads and draws what was drawn since begin, in the pass the encoder
	// is in: one draw, or one more for each change of the image texture bound
	public function end(enc:Encoder) {
		var ending = haxe.Timer.stamp();
		if (keptAt == frames) present();
		else keptValid = false;
		uploadAtlas();
		FrameCounts.quads += quads.count;
		var uploaded = quads.upload(device), encoding = haxe.Timer.stamp();
		FrameCounts.uploadMs += (encoding - ending) * 1000;
		if (uploaded) {
			enc.setPipeline(pipeline);
			draw(enc, quads, frameTextures);
			FrameCounts.uploaded += quads.uploaded;
		}
		var now = haxe.Timer.stamp();
		FrameCounts.uiMs += (now - began) * 1000;
		FrameCounts.encodeMs += (now - encoding) * 1000;
		#if (target.name == "hxmc")
		FrameCounts.uiBytes += hxmc.GcStats.bytesAllocated() - beganBytes;
		#end
	}

	// what end does but drawing onto the target (the system's layers draw
	// the frame from the compositor's: apple.Layers): the atlas uploaded, the
	// quads once, for the buffers their copies share
	public function upload() {
		uploadAtlas();
		if (quads.shared().corners == null) quads.upload(device);
		FrameCounts.uiMs += (haxe.Timer.stamp() - began) * 1000;
	}

	// (a batch's runs drawn, each with its image texture)
	function draw(enc:Encoder, b:QuadBatch, textures:Array<Null<Texture>>) {
		b.bind(enc);
		enc.setTexture(atlasSlot, atlasTexture, linear);
		for (r in 0...b.draws()) {
			var t = textures[b.runs[r * 3]];
			if (r == 0 || t != null) enc.setTexture(imageSlot, t == null ? blank : t, linear);
			b.draw(enc, r);
		}
	}

	// (the glyph atlas's texels changed since the last upload: uploaded)
	function uploadAtlas() {
		// (the atlas grown between frames: a texture of its size)
		if (atlasW != atlas.width || atlasH != atlas.height) {
			device.destroyTexture(atlasTexture);
			atlasTexture = device.createTexture({width: atlasW = atlas.width, height: atlasH = atlas.height, format: RGBA8});
		}
		if (atlas.dirtyX1 > atlas.dirtyX0) {
			var x = atlas.dirtyX0, y = atlas.dirtyY0, w = atlas.dirtyX1 - x, h = atlas.dirtyY1 - y;
			// (coverage in the red channel)
			if (region.length < w * h * 4) region = Bytes.alloc(w * h * 4);
			for (r in 0...h) {
				var src = (y + r) * atlas.width + x, dst = r * w * 4;
				for (c in 0...w)
					region.set(dst + c * 4, atlas.pixels.get(src + c));
			}
			device.writeTexture(atlasTexture, region, x, y, w, h);
			FrameCounts.glyphTexels += w * h;
			atlas.clean();
		}
	}

	// (the image texture bound for a quad: the run's, else a new run's)
	inline function bind(t:Texture) {
		var r = runTextures[run];
		if (r == null) runTextures[run] = t;
		else if (r != t) {
			run++;
			runTextures.push(t);
		}
	}

	// the renderer a canvas draws onto: c, or what a display list is
	// replayed onto (DisplayList.target), its passes (beforePass) recorded
	// into that list until another is found through it
	public static function of(c:Null<Canvas>):Null<Renderer> {
		var l = Std.downcast(c, DisplayList);
		if (l != null) {
			var r = of(l.target);
			if (r != null) r.recording = l;
			return r;
		}
		var r = Std.downcast(c, Renderer);
		if (r != null) r.recording = null;
		return r;
	}

	// (the list a node found this renderer through: its passes recorded
	// there, run as it is replayed, so that a list kept still runs them in order)
	var recording:Null<DisplayList> = null;

	// f records a pass of its own before the frame's (prepare): what a
	// texture drawn this frame shows, rendered first (a <Scene>'s)
	public function beforePass(f:Encoder->Void) {
		if (templating) return;
		if (recording != null) recording.pass(f) else before.push(f);
	}

	// a pass replayed from a display list (beforePass's), or a backdrop to capture
	public function pass(f:Any) {
		if (Std.isOfType(f, Backdrop)) {
			if (templating) composite.backdrops++ else capture(cast f);
			return;
		}
		if (!templating) before.push(cast f);
	}

	// --- backdrops (helder.ui.Glass's: Backdrop) ---

	// the backdrops captured this frame; a frame with one is drawn whole
	// (damage), as is the next one where it was drawn only in part
	public var backdrops(default, null) = 0;
	var backdropsLast = 0;
	var wholeNext = false;

	// (what was drawn so far under b's rectangle (into the target drawn into:
	// the frame, a group), its quads that meet it, drawn into a target of its
	// own in a pass before the frame's, over the frame's background; under a
	// transform its bounds)
	function capture(b:Backdrop) {
		backdrops++;
		if (keptAt == frames) {
			wholeNext = true;
			again = true;
		}
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
		var gx0 = Math.floor(Math.max(x0, ox)), gy0 = Math.floor(Math.max(y0, oy));
		var gx1 = Math.ceil(Math.min(x1, ox + targetW)), gy1 = Math.ceil(Math.min(y1, oy + targetH));
		var gw = Std.int(gx1 - gx0), gh = Std.int(gy1 - gy0);
		if (gw <= 0 || gh <= 0 || gw > device.maxTextureSize || gh > device.maxTextureSize) {
			b.texture = null;
			return;
		}
		var g:Null<Group> = b.held;
		if (g == null) b.held = g = new Group();
		g.open(device, gw, gh);
		b.texture = g.texture;
		b.px = Std.int(gx0);
		b.py = Std.int(gy0);
		b.pw = gw;
		b.ph = gh;
		b.tw = g.textureWidth;
		b.th = g.textureHeight;
		// (the quads in the target's pixels from its origin, moved to the backdrop's)
		var src = batch.bytes, dst = g.batch, n = batch.count, lx0 = gx0 - ox, ly0 = gy0 - oy, lx1 = gx1 - ox, ly1 = gy1 - oy;
		var tw = g.textureWidth, th = g.textureHeight, r = 0, runs = batch.runs, last:Null<Texture> = null, key = -1;
		for (i in 0...n) {
			while (r < batch.draws() - 1 && i >= runs[r * 3 + 1] + runs[r * 3 + 2])
				r++;
			var o = i * STRIDE;
			var ax = src.getFloat(o + 8), ay = src.getFloat(o + 12), bx = src.getFloat(o + 24), by = src.getFloat(o + 28), cx = src.getFloat(o + 40),
				cy = src.getFloat(o + 44);
			var dx = bx + cx - ax, dy = by + cy - ay;
			var qx0 = Math.min(Math.min(ax, bx), Math.min(cx, dx)), qx1 = Math.max(Math.max(ax, bx), Math.max(cx, dx));
			var qy0 = Math.min(Math.min(ay, by), Math.min(cy, dy)), qy1 = Math.max(Math.max(ay, by), Math.max(cy, dy));
			if (qx1 <= lx0 || qx0 >= lx1 || qy1 <= ly0 || qy0 >= ly1) continue;
			var t = runTextures[runs[r * 3]];
			if (key < 0 || t != last) {
				if (key >= 0 || g.textures[0] != null) g.textures.push(t) else g.textures[0] = t;
				key = g.textures.length - 1;
				last = t;
			}
			var at = dst.add(key), out = dst.bytes;
			out.blit(at, src, o, STRIDE);
			for (c in 0...3) {
				var p = at + c * 16, X = out.getFloat(p + 8) - lx0, Y = out.getFloat(p + 12) - ly0;
				out.setFloat(p, X / tw * 2 - 1);
				out.setFloat(p + 4, 1 - Y / th * 2);
				out.setFloat(p + 8, X);
				out.setFloat(p + 12, Y);
			}
			for (j in 0...2) {
				out.setFloat(at + 160 + j * 8, out.getFloat(at + 160 + j * 8) - lx0);
				out.setFloat(at + 164 + j * 8, out.getFloat(at + 164 + j * 8) - ly0);
				out.setFloat(at + 208 + j * 8, out.getFloat(at + 208 + j * 8) - lx0);
				out.setFloat(at + 212 + j * 8, out.getFloat(at + 212 + j * 8) - ly0);
			}
			if (out.getFloat(at + 192) != -1e9) {
				out.setFloat(at + 192, out.getFloat(at + 192) - lx0);
				out.setFloat(at + 196, out.getFloat(at + 196) - ly0);
			}
		}
		// (over the frame's background; in a group, over nothing)
		var c = g.pass.colors[0].clear, bg = batch == quads || batch == kept.batch ? background : Color.TRANSPARENT;
		@:privateAccess {
			c.r = bg.r / 255;
			c.g = bg.g / 255;
			c.b = bg.b / 255;
			c.a = bg.a / 255;
		}
		if (groupPipeline == null) {
			var d = UiShader.pipeline({blend: Premultiplied});
			d.layout = layout();
			d.colorFormat = RGBA8;
			groupPipeline = device.createPipeline(d);
		}
		uploadAtlas();
		before.push(enc -> render(enc, g, g.pass));
	}

	// --- layers' tiles ---

	// whether layers are drawn from tiles of their own (Layer.tiled): a
	// window's; else, and for a layer whose texture would differ from
	// drawing it again (under a transform it does not move by), replayed.
	// Tiles are TILE device pixels square, drawn into where the layer is
	// first drawn, kept while it paints the same at the same scale and
	// moves by whole device pixels; drawn where they fall (snapped) while
	// it moves by fractions of one, as browsers snap scroll offsets; drawn
	// again where it comes to rest. Those in view are drawn the frame they
	// come into it, those next to it after (PREFETCH a frame at rest, one
	// moving); a rounded clip's corners replayed; past tileBudget,
	// those longest unseen and farthest go first
	public var tiles = false;
	public var tileBudget = 96 << 20;
	public var tileBytes(default, null) = 0;
	// (the tiles drawn into so far)
	public var rastered(default, null) = 0;
	public static inline var TILE = 512;
	static inline var PREFETCH = 2;
	final tiled = new haxe.ds.ObjectMap<Layer, LayerTiles>();
	final tileWalk = new Walk();
	var rastering = false;

	public function layerTiles(l:Layer):Bool {
		if (!tiles || rastering) return false;
		if (templating) return tileGroup(l);
		if (!flat && (l.scroll || !l.moving)) return false;
		// (a scroller's tiles drawn over its background, as in place: what its
		// content blends over the same, rounded the same at each step, the
		// tiles opaque; one with none opaque under it replayed)
		if (l.scroll && l.backdrop == 0) return false;
		var t = tiled.get(l), s = scale;
		if (t == null) tiled.set(l, t = new LayerTiles());
		t.frame = frames;
		if (t.content != l.content || t.scale != s) {
			t.drop();
			t.content = l.content;
			t.scale = s;
		}
		// (moved by a fraction of a device pixel and at rest: drawn again where it is)
		var fx = (tx - t.rx) * s, fy = (ty - t.ry) * s;
		if (t.tiles.length == 0 || !l.moving && (fx != Math.fround(fx) || fy != Math.fround(fy))) {
			t.drop();
			t.rx = tx;
			t.ry = ty;
			fx = fy = 0;
		}
		// (what is seen, in the device pixels it was drawn at: the clip's, a moving node's all of it)
		var vx0 = (l.x0 + t.rx) * s, vy0 = (l.y0 + t.ry) * s, vx1 = (l.x1 + t.rx) * s, vy1 = (l.y1 + t.ry) * s;
		if (flat) {
			// (in a kept frame's rectangle: the tiles under it)
			var cut = cutting && batch == kept.batch;
			vx0 = Math.max(vx0, Math.max(clipX0, cut ? cutX0 : ox) - fx);
			vy0 = Math.max(vy0, Math.max(clipY0, cut ? cutY0 : oy) - fy);
			vx1 = Math.min(vx1, Math.min(clipX1, cut ? cutX1 : ox + targetW) - fx);
			vy1 = Math.min(vy1, Math.min(clipY1, cut ? cutY1 : oy + targetH) - fy);
		}
		if (!l.scroll) {
			vx0 = Math.max(vx0, (l.bx0 + t.rx) * s);
			vy0 = Math.max(vy0, (l.by0 + t.ry) * s);
			vx1 = Math.min(vx1, (l.bx1 + t.rx) * s);
			vy1 = Math.min(vy1, (l.by1 + t.ry) * s);
		}
		if (vx1 <= vx0 || vy1 <= vy0) return true;
		var i0 = Math.floor(vx0 / TILE), j0 = Math.floor(vy0 / TILE), i1 = Math.ceil(vx1 / TILE), j1 = Math.ceil(vy1 / TILE);
		if ((i1 - i0) * (j1 - j0) * TILE * TILE * 4 > tileBudget / 2) return false;
		// (a rounded clip: a tile's pixels at its corners would be blended once
		// at the clip's coverage, where drawing in place blends each thing
		// drawn there at it; so the corners' boxes, the list replayed into
		// each under its corner, the tiles under the rest: whole pixels, as
		// the clip's edges are, the shader's coverage there the same)
		var a = 0.0;
		if (flat && clipR0 + clipR1 + clipR2 + clipR3 > 0) {
			if (clipX0 != Math.ffloor(clipX0) || clipY0 != Math.ffloor(clipY0) || clipX1 != Math.ffloor(clipX1) || clipY1 != Math.ffloor(clipY1))
				return false;
			a = 2 * Math.ceil(Math.max(Math.max(clipR0, clipR1), Math.max(clipR2, clipR3))) + 2;
			if (2 * a > clipX1 - clipX0 || 2 * a > clipY1 - clipY0) return false;
		}
		for (j in j0...j1)
			for (i in i0...i1) {
				var k = t.get(i, j);
				if (k == null || !k.valid(l)) k = raster(l, t, i, j);
				k.frame = frames;
			}
		if (a == 0) drawTiles(t, i0, j0, i1, j1) else {
			var x0 = clipX0, y0 = clipY0, x1 = clipX1, y1 = clipY1, r0 = clipR0, r1 = clipR1, r2 = clipR2, r3 = clipR3;
			clipR0 = clipR1 = clipR2 = clipR3 = 0;
			// (each tile in the bands it meets, one after another: its texture bound once)
			for (j in j0...j1)
				for (i in i0...i1)
					for (band in 0...3) {
						clipX0 = band == 1 ? x0 : x0 + a;
						clipX1 = band == 1 ? x1 : x1 - a;
						clipY0 = band == 0 ? y0 : band == 1 ? y0 + a : y1 - a;
						clipY1 = band == 0 ? y0 + a : band == 1 ? y1 - a : y1;
						drawTiles(t, i, j, i + 1, j + 1);
					}
			var w = tileWalk;
			w.mark = false;
			w.draw = true;
			w.host = null;
			rastering = true;
			for (c in 0...4) {
				var cx = c == 0 || c == 3 ? x0 : x1 - a, cy = c < 2 ? y0 : y1 - a;
				clipX0 = cx;
				clipY0 = cy;
				clipX1 = cx + a;
				clipY1 = cy + a;
				clipR0 = c == 0 ? r0 : 0;
				clipR1 = c == 1 ? r1 : 0;
				clipR2 = c == 2 ? r2 : 0;
				clipR3 = c == 3 ? r3 : 0;
				w.set(cx / s - tx, cy / s - ty, (cx + a) / s - tx, (cy + a) / s - ty);
				w.ptx = w.pty = 0;
				l.list.replay(this, w);
			}
			rastering = false;
			clipX0 = x0;
			clipY0 = y0;
			clipX1 = x1;
			clipY1 = y1;
			clipR0 = r0;
			clipR1 = r1;
			clipR2 = r2;
			clipR3 = r3;
		}
		// (the ones around what is seen, within what it was recorded over: one
		// a frame while it moves, two while it rests, none once they are drawn)
		if (l.scroll) {
			var budget = l.moving ? 1 : PREFETCH, ri0 = Math.floor((l.x0 + t.rx) * s / TILE), rj0 = Math.floor((l.y0 + t.ry) * s / TILE);
			var ri1 = Math.ceil((l.x1 + t.rx) * s / TILE), rj1 = Math.ceil((l.y1 + t.ry) * s / TILE);
			for (j in Std.int(Math.max(j0 - 1, rj0))...Std.int(Math.min(j1 + 1, rj1)))
				for (i in Std.int(Math.max(i0 - 1, ri0))...Std.int(Math.min(i1 + 1, ri1))) {
					if (budget == 0 || i >= i0 && i < i1 && j >= j0 && j < j1) continue;
					var k = t.get(i, j);
					if (k != null && k.valid(l)) continue;
					raster(l, t, i, j).frame = frames - 1;
					budget--;
				}
		}
		return true;
	}

	// (the tiles i0...i1, j0...j1 drawn where their layer is now, under the
	// clip; flat, each cut to it, so that no pixel outside is shaded)
	function drawTiles(t:LayerTiles, i0:Int, j0:Int, i1:Int, j1:Int) {
		var s = scale, fx = (tx - t.rx) * s, fy = (ty - t.ry) * s;
		if (grid) {
			fx = Math.fround(fx);
			fy = Math.fround(fy);
		}
		var cx0 = Math.max(clipX0, ox), cy0 = Math.max(clipY0, oy), cx1 = Math.min(clipX1, ox + targetW), cy1 = Math.min(clipY1, oy + targetH);
		for (j in j0...j1)
			for (i in i0...i1) {
				var k = t.get(i, j), g = k.group;
				if (!flat) {
					gpuTexture(g.texture, g.id, i * TILE / s - t.rx, j * TILE / s - t.ry, TILE / s, TILE / s);
					continue;
				}
				var x0 = i * TILE + fx, y0 = j * TILE + fy;
				var qx0 = Math.max(x0, cx0), qy0 = Math.max(y0, cy0), qx1 = Math.min(x0 + TILE, cx1), qy1 = Math.min(y0 + TILE, cy1);
				if (qx1 <= qx0 || qy1 <= qy0) continue;
				gpu.set(g.id, g.texture);
				qr0 = qr1 = qr2 = qr3 = qw0 = qw1 = qw2 = qw3 = 0;
				quad(qx0, qy0, qx1, qy1, (qx0 - x0) / TILE, (qy0 - y0) / TILE, (qx1 - x0) / TILE, (qy1 - y0) / TILE, Color.WHITE, 0, 2, 0, 1, g.id);
			}
	}

	// (a tile of l drawn into, as l would be drawn in place: in the frame's
	// device pixels at its translation then, its tile's part of them)
	function raster(l:Layer, t:LayerTiles, i:Int, j:Int):LayerTile {
		var k = t.get(i, j);
		if (k == null) {
			k = new LayerTile(i, j);
			t.put(k);
			tileBytes += TILE * TILE * 4;
		}
		var g = k.group;
		g.open(device, TILE, TILE);
		g.frame = frames;
		var c = g.pass.colors[0].clear, b:Color = l.scroll ? l.backdrop : 0;
		@:privateAccess {
			c.r = b.r / 255;
			c.g = b.g / 255;
			c.b = b.b / 255;
			c.a = b.a / 255;
		}
		var s = scale, x0 = i * TILE, y0 = j * TILE;
		k.content = l.content;
		k.stamp = l.stamp;
		k.whole = l.covers(x0 / s - t.rx, y0 / s - t.ry, (x0 + TILE) / s - t.rx, (y0 + TILE) / s - t.ry);
		var sBatch = batch, sTextures = runTextures, sRun = run, sOx = ox, sOy = oy, sW = targetW, sH = targetH;
		var c0 = clipX0, c1 = clipY0, c2 = clipX1, c3 = clipY1, r0 = clipR0, r1 = clipR1, r2 = clipR2, r3 = clipR3;
		var sTx = tx, sTy = ty, sAlpha = alpha, sa = ma, sb = mb, sc = mc, sd = md, se = me, sf = mf, sk = mk, sFlat = flat, sAligned = aligned, sGrid = grid;
		batch = g.batch;
		runTextures = g.textures;
		run = 0;
		ox = x0;
		oy = y0;
		targetW = g.textureWidth;
		targetH = g.textureHeight;
		clipX0 = x0;
		clipY0 = y0;
		clipX1 = x0 + TILE;
		clipY1 = y0 + TILE;
		clipR0 = clipR1 = clipR2 = clipR3 = 0;
		tx = t.rx;
		ty = t.ry;
		alpha = 1;
		ma = md = mk = 1;
		mb = mc = me = mf = 0;
		flat = aligned = true;
		grid = snap;
		var w = tileWalk;
		w.set(x0 / s - t.rx, y0 / s - t.ry, (x0 + TILE) / s - t.rx, (y0 + TILE) / s - t.ry);
		w.ptx = w.pty = 0;
		w.mark = false;
		w.draw = true;
		w.host = null;
		rastering = true;
		l.list.replay(this, w);
		rastering = false;
		batch = sBatch;
		runTextures = sTextures;
		run = sRun;
		ox = sOx;
		oy = sOy;
		targetW = sW;
		targetH = sH;
		clipX0 = c0;
		clipY0 = c1;
		clipX1 = c2;
		clipY1 = c3;
		clipR0 = r0;
		clipR1 = r1;
		clipR2 = r2;
		clipR3 = r3;
		tx = sTx;
		ty = sTy;
		alpha = sAlpha;
		ma = sa;
		mb = sb;
		mc = sc;
		md = sd;
		me = se;
		mf = sf;
		mk = sk;
		flat = sFlat;
		aligned = sAligned;
		grid = sGrid;
		closedGroups.push(g);
		rastered++;
		return k;
	}

	// (past the budget: the tiles longest unseen first, of layers not drawn
	// for EVICT frames all of them; none at all: trim)
	function evictTiles(all:Bool) {
		var gone:Array<Layer> = null;
		for (l => t in tiled)
			if (all || frames - t.frame > EVICT) {
				tileBytes -= t.tiles.length * TILE * TILE * 4;
				t.free(device);
				if (gone == null) gone = [];
				gone.push(l);
			}
		if (gone != null)
			for (l in gone)
				tiled.remove(l);
		while (tileBytes > tileBudget) {
			var worst:Null<LayerTile> = null, from:Null<LayerTiles> = null;
			for (t in tiled)
				for (k in t.tiles)
					if (k.frame < frames && (worst == null || k.frame < worst.frame)) {
						worst = k;
						from = t;
					}
			if (worst == null) break;
			from.remove(worst, device);
			tileBytes -= TILE * TILE * 4;
		}
	}

	// a pass recorded before the next frame's, asked outside a paint
	public function nextPass(f:Encoder->Void)
		next.push(f);

	// records the passes asked for since begin, outside the frame's pass
	// (UiWindow: after painting, before it): a <Scene>'s, then the opacity
	// groups', inner ones first (an outer group draws what they drew); a
	// kept frame's rectangles drawn, then into the frame kept
	public function prepare(enc:Encoder) {
		for (f in before)
			f(enc);
		before.resize(0);
		if (closedGroups.length == 0 && regions.length == 0) return;
		uploadAtlas();
		if (groupPipeline == null) {
			var d = UiShader.pipeline({blend: Premultiplied});
			d.layout = layout();
			d.colorFormat = RGBA8;
			groupPipeline = device.createPipeline(d);
		}
		for (g in closedGroups) {
			render(enc, g, g.pass);
			if (composite != null) composite.fresh.push(cast g.texture);
		}
		closedGroups.resize(0);
		if (regions.length > 0) paste(enc);
	}

	// (a group's quads drawn into its texture in a pass of their own)
	function render(enc:Encoder, g:Group, pass:PassDesc) {
		FrameCounts.quads += g.batch.count;
		pass.colors[0].texture = g.texture;
		enc.beginPass(pass);
		if (g.batch.upload(device)) {
			enc.setPipeline(groupPipeline);
			draw(enc, g.batch, g.textures);
			FrameCounts.uploaded += g.batch.uploaded;
		}
		enc.endPass();
	}

	// --- the compositor's frame (Layers' step 4b) ---

	// what the compositor draws its frames from (UiWindow's, when it has
	// one): each frame Ui.paint walks the tree whole once more into it
	// (composites), the quads tagged with the scrollers they move with
	// (enter, leave), what is under a scroller not culled to what is seen
	// but walked over what its layer was recorded over, its tiles kept as
	// tiles (tileGroup), what moves on its own tagged too (mover: drawn at
	// its opacity's 1, the compositor turns and fades it); nothing of it
	// drawn by the frame
	public var composite:Null<helder.ui.layers.CompositeFrame> = null;
	var templating = false;
	// (the scroller frame the quads are in (-1: none), their clip's, a thumb's; under a frame nothing culled)
	var contentFrame = -1;
	var clipFrame = -1;
	var thumbTag = -1;
	var uncull = false;
	final frameStack:Array<Int> = [];
	final clipFrames:Array<Int> = [];
	// (the mover the quads are in (-1: none), their clip's; a thumb's fade; what enter and mover entered)
	var moverTag = -1;
	var clipMover = -1;
	var fadeTag = 0;
	final moverStack:Array<Int> = [];
	final clipMovers:Array<Int> = [];
	final entered:Array<Int> = [];
	// (the next pushGroup a mover's; the compositor's frames' groups, those
	// of the one being filled taken so far)
	var groupNext = false;
	final composedGroups = new haxe.ds.ObjectMap<helder.ui.layers.CompositeFrame, Array<Group>>();
	var composed = 0;
	// (the frame's state, put back after the walk)
	var savedGroups = false;
	var savedClip:Array<Float> = [];

	public function composites():Bool
		return composite != null && !rastering && !templating;

	public function enter(n:Node, kind:Int):Bool {
		if (!templating) return false;
		var f = composite.frameOf(n, contentFrame);
		if (kind & 3 != 0) {
			thumbTag = f << 1 | (kind & 3 == 2 ? 1 : 0);
			fadeTag = kind >> 2;
			entered.push(1);
			return true;
		}
		// (a scroller inside what moves: those the compositor leaves as drawn)
		var m = moverTag;
		while (m >= 0) {
			composite.freeze(m);
			m = composite.moverParent(m);
		}
		frameStack.push(contentFrame);
		contentFrame = f;
		uncull = true;
		entered.push(0);
		return true;
	}

	// what is drawn until leave is m's: moved by its transform and opacity
	// as the compositor samples them (drawn here at its opacity's 1, under
	// its transform as drawn)
	public function mover(m:helder.ui.Mover):Bool {
		if (!templating) return false;
		groupNext = m.grouped;
		var c = composite, sc = m.scroller, f = sc == null ? -1 : c.nodes.indexOf(sc);
		moverStack.push(moverTag);
		moverTag = c.addMover(m, moverTag, f, flat, ma, mb, mc, md, me, mf, scale, tx, ty);
		entered.push(2);
		return true;
	}

	public function leave() {
		if (!templating || entered.length == 0) return;
		switch entered.pop() {
			case 1:
				thumbTag = -1;
				fadeTag = 0;
			case 2:
				moverTag = moverStack.pop();
			case _:
				contentFrame = frameStack.length > 0 ? frameStack.pop() : -1;
				uncull = contentFrame >= 0;
		}
	}

	public function slot(sl:helder.ui.LayerSlot, x:Float, y:Float, w:Float, h:Float) {
		if (!templating || w <= 0 || h <= 0) return;
		var c = composite, s = scale, x0 = (x + tx) * s, y0 = (y + ty) * s, x1 = (x + w + tx) * s, y1 = (y + h + ty) * s;
		var ra = flat ? 1 : ma, rb = flat ? 0 : mb, rc = flat ? 0 : mc, rd = flat ? 1 : md, te = flat ? 0 : me, tf = flat ? 0 : mf;
		c.slots.push(sl);
		for (v in [batch.count, c.groups.length, contentFrame, clipFrame, moverTag, clipMover, ra * x0 + rc * y0 + te, rb * x0 + rd * y0 + tf,
			ra * x1 + rc * y0 + te, rb * x1 + rd * y0 + tf, ra * x0 + rc * y1 + te, rb * x0 + rd * y1 + tf, clipX0, clipY0, clipX1, clipY1, clipR0, clipR1,
			clipR2, clipR3])
			c.slotData.push(v);
	}

	function beginComposite() {
		var c = composite;
		if (c == null) return;
		c.clear();
		c.width = Std.int(frameW);
		c.height = Std.int(frameH);
		c.scale = scale;
		c.background = (background : Int);
		c.snap = snap;
		c.pipeline = pipeline;
		if (clearPipeline == null) {
			var d = UiShader.pipeline({blend: Opaque});
			d.layout = layout();
			clearPipeline = device.createPipeline(d);
		}
		c.clearPipeline = clearPipeline;
		c.atlasSlot = atlasSlot;
		c.imageSlot = imageSlot;
		c.blank = blank;
		c.sampler = linear;
		batch = c.batch;
		runTextures = c.textures;
		run = 0;
		cutting = false;
		savedGroups = groups;
		groups = false;
		templating = true;
		contentFrame = clipFrame = thumbTag = moverTag = clipMover = -1;
		fadeTag = 0;
		groupNext = false;
		composed = 0;
		uncull = false;
		frameStack.resize(0);
		clipFrames.resize(0);
		moverStack.resize(0);
		clipMovers.resize(0);
		entered.resize(0);
		savedClip = [clipX0, clipY0, clipX1, clipY1, clipR0, clipR1, clipR2, clipR3];
		clipX0 = clipY0 = clipR0 = clipR1 = clipR2 = clipR3 = 0;
		clipX1 = frameW;
		clipY1 = frameH;
	}

	function endComposite() {
		var c = composite;
		if (c == null || !templating) return;
		templating = uncull = false;
		contentFrame = clipFrame = thumbTag = moverTag = clipMover = -1;
		fadeTag = 0;
		groups = savedGroups;
		batch = quads;
		runTextures = frameTextures;
		run = 0;
		var k = savedClip;
		clipX0 = k[0];
		clipY0 = k[1];
		clipX1 = k[2];
		clipY1 = k[3];
		clipR0 = k[4];
		clipR1 = k[5];
		clipR2 = k[6];
		clipR3 = k[7];
		c.ready = true;
	}

	// (the composite's state once the frame ended: the atlas as end uploaded
	// it, grown maybe; the quads' corners and indices, made at their first
	// upload; false: none yet)
	@:allow(helder.ui.layers.Compositor) function ended(c:helder.ui.layers.CompositeFrame):Bool {
		var sh = quads.shared();
		if (sh.corners == null || sh.indices == null) return false;
		c.atlas = atlasTexture;
		c.corners = sh.corners;
		c.indices = sh.indices;
		return true;
	}

	// (a scroller's layer in the compositor's frame: its tiles over what it
	// was recorded over, those drawn and still valid, where they are now;
	// else replayed)
	function tileGroup(l:Layer):Bool {
		var c = composite;
		if (!l.scroll || contentFrame < 0 || !flat || l.backdrop == 0) return false;
		var t = tiled.get(l), s = scale;
		if (t == null || t.content != l.content || t.scale != s || t.tiles.length == 0) return false;
		c.groups.push(batch.count);
		c.tileAt.push(Std.int(c.tiles.length / 2));
		for (v in [contentFrame, clipFrame, clipX0, clipY0, clipX1, clipY1, clipR0, clipR1, clipR2, clipR3, t.rx, t.ry, tx, ty, alpha, 0])
			c.groupData.push(v);
		var ri0 = Math.floor((l.x0 + t.rx) * s / TILE), rj0 = Math.floor((l.y0 + t.ry) * s / TILE);
		var ri1 = Math.ceil((l.x1 + t.rx) * s / TILE), rj1 = Math.ceil((l.y1 + t.ry) * s / TILE);
		for (j in rj0...rj1)
			for (i in ri0...ri1) {
				var k = t.get(i, j);
				if (k == null || !k.valid(l) || k.group.texture == null) continue;
				c.tiles.push(i);
				c.tiles.push(j);
				c.tileTextures.push(cast k.group.texture);
			}
		return true;
	}

	// --- a kept frame ---

	// whether its frame is kept from frame to frame (a window's): Ui.paint
	// draws only what changed into it (damage), each rectangle straight
	// into the frame kept (a texture of the frame's size, so that what is
	// drawn there is what drawing onto the target gives), its background
	// first, what is drawn in it cut to it: an unturned quad's corners (its
	// fragments the same, measured from their pixels' centres: UiShader), a
	// turned one's fragments outside it nothing (UiShader's region); then
	// the frame kept copied onto the target (end), as a swap chain does
	// not keep its frames (Metal's drawables, a browser's canvas). Where
	// most of it changed, the frame is drawn whole onto the target, kept
	// again once less does. background: the frame's pass's colour (opaque);
	// flash: the rectangles drawn shown over the frame (HELDER_DAMAGE=flash)
	public var keep = false;
	public var background:Color = Color.WHITE;
	public var flash = false;
	// the pixels drawn this frame (a frame drawn whole: all of them); the rectangles drawn into the frame kept (x0, y0, x1, y1)
	public var drawn(default, null) = 0;
	public final regions:Array<Int> = [];
	// (the frame kept: its texture, its quads; whether it holds the last
	// frame drawn, at what scale, the frame that drew into it; the
	// rectangle drawn into it (cut), one the whole frame (then cleared))
	final kept = new Group();
	var keptValid = false;
	var keptScale = 0.0;
	var keptAt = -1;
	var cutting = false;
	var cutX0 = 0.0;
	var cutY0 = 0.0;
	var cutX1 = 0.0;
	var cutY1 = 0.0;
	var whole = false;
	var damaged:Null<Damage> = null;
	final keptPass:PassDesc = {colors: [{load: Load, clear: new helder.gfx.Color(1, 1, 1)}]};
	var frameW = 1.0;
	var frameH = 1.0;

	static inline var MOST = 0.4;

	public function keeps():Bool
		return keep;

	public function damage(d:Damage) {
		if (!keep) return;
		var w = Std.int(frameW), h = Std.int(frameH), s = scale, k = kept, t = k.texture;
		// (single-sampled in a multisampled window too: UiShader grows each
		// quad past its anti-aliased edge, so samples change no pixel the UI
		// draws; DamageTest --window checks it)
		k.open(device, w, h, true);
		var gone = !keptValid || k.texture != t || keptScale != s;
		d.round(s, w, h);
		damaged = d;
		// (most of it: drawn whole straight onto the target, as copying it
		// in and out would draw more; kept again once less changes, the
		// frame kept drawn whole then; a backdrop's frame whole: what it reads reaches past what changed)
		var glass = backdropsLast > 0 || wholeNext;
		wholeNext = false;
		if (d.all || glass || d.area() * s * s > MOST * w * h) {
			d.everything();
			d.round(s, w, h);
			keptValid = false;
			keptAt = -1;
			drawn = w * h;
			return;
		}
		if (gone) {
			d.everything();
			d.round(s, w, h);
		}
		keptValid = true;
		keptScale = s;
		keptAt = frames;
	}

	public function redraw(i:Int) {
		if (i == -2) {
			beginComposite();
			return;
		}
		if (i == -3) {
			endComposite();
			return;
		}
		if (keptAt != frames) return;
		if (i < 0) {
			cutting = false;
			batch = quads;
			runTextures = frameTextures;
			run = 0;
			return;
		}
		var d = damaged, s = scale, k = kept, w = k.width, h = k.height;
		var x0 = Std.int(Math.max(0, Math.round(d.x0(i) * s))), y0 = Std.int(Math.max(0, Math.round(d.y0(i) * s)));
		var x1 = Std.int(Math.min(w, Math.round(d.x1(i) * s))), y1 = Std.int(Math.min(h, Math.round(d.y1(i) * s)));
		if (x0 == 0 && y0 == 0 && x1 == w && y1 == h) whole = true;
		regions.push(x0);
		regions.push(y0);
		regions.push(x1);
		regions.push(y1);
		drawn += (x1 - x0) * (y1 - y0);
		batch = k.batch;
		runTextures = k.textures;
		run = k.textures.length - 1;
		cutting = true;
		cutX0 = x0;
		cutY0 = y0;
		cutX1 = x1;
		cutY1 = y1;
		// (its background first, over what was there)
		qr0 = qr1 = qr2 = qr3 = qw0 = qw1 = qw2 = qw3 = 0;
		var sa = alpha;
		alpha = 1;
		quad(x0, y0, x1, y1, 0, 0, 0, 0, (background : Int) | 0xFF000000, 0, 0, 0, 1, 0);
		alpha = sa;
	}

	// (the rectangles drawn into the frame kept, in a pass of their own)
	function paste(enc:Encoder) {
		var c = background, k = kept, p = keptPass.colors[0];
		@:privateAccess {
			p.clear.r = c.r / 255;
			p.clear.g = c.g / 255;
			p.clear.b = c.b / 255;
			p.clear.a = 1;
		}
		p.load = whole ? Clear : Load;
		render(enc, k, keptPass);
	}

	// (the frame kept onto the target, the rectangles drawn flashed over it)
	function present() {
		var k = kept, s = scale;
		gpu.set(k.id, k.texture);
		qr0 = qr1 = qr2 = qr3 = qw0 = qw1 = qw2 = qw3 = 0;
		quad(0, 0, k.width, k.height, 0, 0, 1, 1, Color.WHITE, 0, 2, 0, 1, k.id);
		if (!flash) return;
		var i = 0, tint:Color = [0x5000FF00, 0x50FF00FF, 0x5000C0FF][frames % 3];
		while (i < regions.length) {
			rect(regions[i] / s, regions[i + 1] / s, (regions[i + 2] - regions[i]) / s, (regions[i + 3] - regions[i + 1]) / s, 0, tint, 0, 0);
			i += 4;
		}
	}

	// what was not drawn in the last frame let go (the textures of images, of
	// opacity groups, of shared images; the rasterized paths): the system
	// asks for memory back (helder.os.App.lowMemory, an app gone to the
	// background); made again when drawn
	public function trim() {
		evict(0);
		evictTiles(true);
	}

	// (what no frame drew for more than `age` frames freed)
	function evict(age:Int) {
		stale.resize(0);
		for (id => e in textures)
			if (frames - e.frame > age) stale.push(id);
		for (id in stale) {
			release(textures.get(id));
			textures.remove(id);
		}
		staleShared.resize(0);
		for (h => o in opened)
			if (frames - o.frame > age) staleShared.push(h);
		for (h in staleShared) {
			var t = opened.get(h).texture;
			if (t != blank) device.destroyTexture(t);
			opened.remove(h);
		}
		// (a group's texture not drawn into for `age` frames: freed, made again if it is)
		for (g in groupPool)
			if (g.texture != null && frames - g.frame > age) g.free(device);
		for (pool in composedGroups)
			for (g in pool)
				if (g.texture != null && frames - g.frame > age) g.free(device);
		stalePaths.resize(0);
		for (p => e in paths)
			if (frames - e.frame > age) stalePaths.push(p);
		for (p in stalePaths)
			paths.remove(p);
	}

	// frees the texture of an image drawn before
	public function forget(img:Image) {
		var e = textures.get(img.id);
		if (e == null) return;
		release(e);
		textures.remove(img.id);
	}

	// (an image's texture or its place in a page given up)
	function release(e:ImageEntry) {
		if (e.external) return;
		if (e.page < 0) device.destroyTexture(e.texture);
		else pages[e.page].live--;
	}

	// the image's texture, uploaded (premultiplied) when new or changed: an
	// image of up to PAGED pixels a side with its pixels here into a page,
	// any other (a browser's, a large one) a texture of its own
	function texture(img:Image):ImageEntry {
		if (img.shared != null) return sharedTexture(img);
		var e = textures.get(img.id);
		if (e != null) e.frame = frames;
		if (e != null && e.version == img.version) return e;
		// (another size: Image.replace's)
		if (e != null && (e.width != img.width || e.height != img.height)) {
			release(e);
			textures.remove(img.id);
			e = null;
		}
		if (e == null) {
			e = new ImageEntry(img.version, frames, img.width, img.height);
			var browser = img.browser != 0 && !img.hasPixels && device.decodesImages;
			if (!browser && img.width <= PAGED && img.height <= PAGED && allocate(e)) {
				var p = pages[e.page];
				e.texture = p.texture;
				if (composite != null) composite.fresh.push(p.texture);
				img.premultiplied(pre -> device.writeTexture(p.texture, pre, e.x, e.y, e.width, e.height));
				img.uploaded();
			} else
				// (its pixels dropped after, where they can come back: Image.uploaded)
				e.texture = helder.gfx.ImageTexture.create(device, img, {premultiply: true});
			textures.set(img.id, e);
		} else {
			var t = e.texture;
			if (composite != null) composite.fresh.push(t);
			// (a browser's image replaced by another, a frame of a worker's: uploaded from its bitmap)
			if (e.page < 0 && img.browser != 0 && !img.hasPixels && device.decodesImages) device.writeTextureImage(t, img.browser);
			else if (e.page >= 0) img.premultiplied(pre -> device.writeTexture(t, pre, e.x, e.y, e.width, e.height));
			else img.premultiplied(pre -> device.writeTexture(t, pre));
			e.version = img.version;
		}
		return e;
	}

	// another process's texture (Image.ofShared: its handle), opened once and
	// drawn as it is (premultiplied, opaque frames), never uploaded; the
	// frames that drew the image counted (Image.drawn: the studio's previews
	// let go of a frame's target once a newer one was drawn)
	function sharedTexture(img:Image):ImageEntry {
		var e = textures.get(img.id);
		if (e == null || !e.external || e.width != img.width || e.height != img.height) {
			if (e != null) release(e);
			e = new ImageEntry(img.version - 1, frames - 1, img.width, img.height);
			e.external = true;
			textures.set(img.id, e);
		}
		if (e.frame != frames) {
			e.frame = frames;
			img.drawn++;
		}
		var o = opened.get(img.shared);
		if (o == null) {
			// (not opened: blank, not tried again)
			o = {texture: device.openShared(img.shared, img.width, img.height) ?? blank, frame: frames};
			opened.set(img.shared, o);
		}
		o.frame = frames;
		e.texture = o.texture;
		e.version = img.version;
		return e;
	}

	// (a place in a page for the entry: in one there is room in, else in one
	// emptied (every image in it evicted or forgotten), else in a new one,
	// up to PAGES; false: none)
	function allocate(e:ImageEntry):Bool {
		for (k in 0...pages.length)
			if (pages[k].allocate(e)) {
				e.page = k;
				return true;
			}
		for (k in 0...pages.length) {
			var p = pages[k];
			if (p.live == 0 && p.used) {
				p.reset();
				if (p.allocate(e)) {
					e.page = k;
					return true;
				}
			}
		}
		if (pages.length >= PAGES) return false;
		var p = new ImagePage(device.createTexture({width: PAGE, height: PAGE, format: RGBA8}));
		pages.push(p);
		if (!p.allocate(e)) return false;
		e.page = pages.length - 1;
		return true;
	}

	// --- Canvas ---

	public function translate(dx:Float, dy:Float) {
		tx += dx;
		ty += dy;
	}

	// the clip becomes the intersection, with the new clip's radii where the
	// new clip is inside the old one (a rounded clip inside a rounded clip
	// that cuts into its corners keeps only the inner one's corners), else
	// the smaller of each
	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners) {
		clipFrames.push(clipFrame);
		clipFrame = contentFrame;
		clipMovers.push(clipMover);
		clipMover = moverTag;
		clips.push(clipX0);
		clips.push(clipY0);
		clips.push(clipX1);
		clips.push(clipY1);
		clips.push(clipR0);
		clips.push(clipR1);
		clips.push(clipR2);
		clips.push(clipR3);
		var k = scale;
		var x0 = (x + tx) * scale, y0 = (y + ty) * scale, x1 = (x + w + tx) * scale, y1 = (y + h + ty) * scale;
		if (grid && snap) {
			x0 = Math.fround(x0);
			y0 = Math.fround(y0);
			x1 = Math.fround(x1);
			y1 = Math.fround(y1);
		}
		if (!flat) {
			// (the transformed corners' bounds)
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
		// (scaled down together as CSS's, where a side's two add up to more than it: fit)
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
		clipFrame = clipFrames.length > 0 ? clipFrames.pop() : -1;
		clipMover = clipMovers.length > 0 ? clipMovers.pop() : -1;
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
		transforms.push(ma);
		transforms.push(mb);
		transforms.push(mc);
		transforms.push(md);
		transforms.push(me);
		transforms.push(mf);
		transforms.push(mk);
		transforms.push(flat ? 1 : 0);
		transforms.push(aligned ? 1 : 0);
		transforms.push(steady ? 1 : 0);
		// (in the scaled pixels after the translation: moved to it, transformed, moved back)
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
		// (its scale as the last frame's transform at its place had it for STILL frames: a new one too)
		var i = scales.length, still = i >= last.length ? STILL : last[i] == mk ? last[i + 1] + 1 : 0;
		scales.push(mk);
		scales.push(still);
		steady = steady && still >= STILL;
		// (under a transform: where it puts it, not snapped)
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

	// what is drawn until popOpacity as one at opacity a (x, y, w, h: its
	// bounds, the clip's part of them drawn): into a render target of its own
	// where groups, else as pushOpacity
	public function pushGroup(a:Float, x:Float, y:Float, w:Float, h:Float) {
		// (a mover's in the compositor's frame: a group of its own at 1, the compositor fading it whole)
		var mine = templating && groupNext;
		groupNext = false;
		if (!mine && (!groups || a >= 1)) {
			pushOpacity(a);
			return;
		}
		// (its bounds in the target's pixels: the transformed corners' bounds, within the clip and the target)
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
		var gx0 = Math.floor(Math.max(Math.max(x0, clipX0), ox)), gy0 = Math.floor(Math.max(Math.max(y0, clipY0), oy));
		var gx1 = Math.ceil(Math.min(Math.min(x1, clipX1), ox + targetW)), gy1 = Math.ceil(Math.min(Math.min(y1, clipY1), oy + targetH));
		var gw = gx1 - gx0, gh = gy1 - gy0;
		// (nothing of it seen, or too large for a texture: its opacity each quad's)
		if (gw <= 0 || gh <= 0 || gw > device.maxTextureSize || gh > device.maxTextureSize) {
			pushOpacity(a);
			return;
		}
		// (the tiles drawn this frame are closed groups too, not the pool's; the
		// compositor's frame's its own, kept while it draws from them)
		var pool = groupPool, k = openGroups.length + closedGroups.length;
		if (mine) {
			pool = composedGroups.get(composite);
			if (pool == null) composedGroups.set(composite, pool = []);
			k = composed++;
		}
		while (k >= pool.length)
			pool.push(new Group());
		var g = pool[k];
		g.open(device, gw, gh);
		g.x = gx0;
		g.y = gy0;
		g.alpha = alpha * a;
		g.frame = frames;
		// (the state it is drawn in, given back at popOpacity)
		g.outer = batch;
		g.outerTextures = runTextures;
		g.outerRun = run;
		g.outerX = ox;
		g.outerY = oy;
		g.outerW = targetW;
		g.outerH = targetH;
		openGroups.push(g);
		alphas.push(alpha);
		pushed.push(1);
		batch = g.batch;
		runTextures = g.textures;
		run = 0;
		ox = gx0;
		oy = gy0;
		// (clip space: the whole texture's, the part drawn its top left)
		targetW = g.textureWidth;
		targetH = g.textureHeight;
		alpha = 1;
	}

	public function popOpacity() {
		alpha = alphas.pop();
		if (pushed.pop() == 0) return;
		var g = openGroups.pop();
		batch = g.outer;
		runTextures = g.outerTextures;
		run = g.outerRun;
		ox = g.outerX;
		oy = g.outerY;
		targetW = g.outerW;
		targetH = g.outerH;
		g.outer = null;
		g.outerTextures = null;
		closedGroups.push(g);
		// (its texture where it was, at its opacity: an image in the target's pixels, untransformed)
		gpu.set(g.id, g.texture);
		var sa = ma, sb = mb, sc = mc, sd = md, se = me, sf = mf, sk = mk, sflat = flat, salign = aligned, a = alpha;
		ma = md = mk = 1;
		mb = mc = me = mf = 0;
		flat = aligned = true;
		alpha = g.alpha;
		qr0 = qr1 = qr2 = qr3 = qw0 = qw1 = qw2 = qw3 = 0;
		quad(g.x, g.y, g.x + g.width, g.y + g.height, 0, 0, g.width / g.textureWidth, g.height / g.textureHeight, Color.WHITE, 0, 2, 0, 0, g.id);
		ma = sa;
		mb = sb;
		mc = sc;
		md = sd;
		me = se;
		mf = sf;
		mk = sk;
		flat = sflat;
		aligned = salign;
		alpha = a;
	}

	// (the next quad's corners: each corner's, else radius; sides: each side's, else width; in device pixels)
	inline function corners(c:Null<Corners>, radius:Float) {
		var s = scale;
		qr0 = (c == null ? radius : c.topLeft) * s;
		qr1 = (c == null ? radius : c.topRight) * s;
		qr2 = (c == null ? radius : c.bottomRight) * s;
		qr3 = (c == null ? radius : c.bottomLeft) * s;
	}

	// (the corners scaled down together where two of a side's add up to
	// more than it, as CSS's border-radius: a huge radius a pill, not an ellipse)
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

	// (a border's width on the grid: whole pixels, at least one)
	inline function side(w:Float):Float
		return grid && w > 0 ? Math.max(1, Math.fround(w)) : w;

	// (a box's edges on the grid: each rounded, so that boxes side by side stay so)
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

	var ex0 = 0.0;
	var ey0 = 0.0;
	var ex1 = 0.0;
	var ey1 = 0.0;

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges,
			style:BorderStyle = Solid) {
		if (w <= 0 || h <= 0) return;
		dash = style;
		var s = scale;
		edges((x + tx) * s, (y + ty) * s, (x + w + tx) * s, (y + h + ty) * s);
		var x0 = ex0, y0 = ey0, x1 = ex1, y1 = ey1;
		// (a thumb's edges before the grid: the compositor rounds them where they fall)
		if (templating && thumbTag >= 0 && grid && batch == composite.batch) for (v in [batch.count, (x + tx) * s, (y + ty) * s, (x + w + tx) * s, (y + h + ty) * s])
			composite.thumbEdges.push(v);
		this.corners(corners, radius);
		fit(x1 - x0, y1 - y0);
		this.sides(sides, borderWidth);
		if (!flat) {
			shape(x0, y0, x1, y1, 0, 0, 0, 0, fill, border, 0, 0, 0, 0);
			return;
		}
		if (culled(x0 - 1, y0 - 1, x1 + 1, y1 + 1)) return;
		quad(x0, y0, x1, y1, 0, 0, 0, 0, fill, border, 0, 0, 1, 0);
	}

	// (the next rectangle's border style: UiShader's params.z in mode 0)
	var dash:BorderStyle = Solid;

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners, ?offset:Array<Float>) {
		if (w <= 0 || h <= 0 || color.a == 0) return;
		var s = scale;
		edges((x + tx) * s, (y + ty) * s, (x + w + tx) * s, (y + h + ty) * s);
		var x0 = ex0, y0 = ey0, x1 = ex1, y1 = ey1;
		this.corners(corners, radius);
		fit(x1 - x0, y1 - y0);
		// (the box casting it, not shaded: its offset and the spread)
		if (offset != null) {
			qw0 = offset[0] * s;
			qw1 = offset[1] * s;
			qw2 = offset[2] * s;
			qw3 = 1;
		} else sides(null, 0);
		// (CSS's blur: a Gaussian whose standard deviation is half of it, drawn out to three of them)
		var sigma = blur * s / 2;
		if (!flat) {
			shape(x0, y0, x1, y1, 0, 0, 0, 0, color, 0, 3, sigma, 3 * sigma, 0);
			return;
		}
		var m = 3 * sigma + 1;
		if (culled(x0 - m, y0 - m, x1 + m, y1 + m)) return;
		quad(x0, y0, x1, y1, 0, 0, 0, 0, color, 0, 3, sigma, m, 0);
	}

	// an inset shadow in a padding box x, y, w, h (its corners): darkened from
	// outside the box moved by dx, dy and shrunk by spread, blurred
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
		if (!flat) {
			shape(x0, y0, x1, y1, 0, 0, 0, 0, color, 0, 4, sigma, 0, 0);
			return;
		}
		if (culled(x0 - 1, y0 - 1, x1 + 1, y1 + 1)) return;
		quad(x0, y0, x1, y1, 0, 0, 0, 0, color, 0, 4, sigma, 1, 0);
	}

	// (a path rasterized at the scale it is drawn at, its stroke's reach
	// around it, kept while it is drawn the same way: by path, its paints and
	// the scale, compared without allocating)
	final paths = new haxe.ds.ObjectMap<Path, PathImage>();

	public function path(p:Path, fill:Null<Paint>, ?stroke:Stroke) {
		var b = p.bounds(), s = scale;
		var reach = stroke == null ? 0.0 : stroke.width / 2 * ((stroke.join ?? Miter) == Miter ? Math.max(1, stroke.miterLimit ?? 4) : 1.5);
		var x0 = Math.floor((b.x - reach) * s) - 1, y0 = Math.floor((b.y - reach) * s) - 1;
		var w = Std.int(Math.ceil((b.x + b.width + reach) * s) + 1 - x0), h = Std.int(Math.ceil((b.y + b.height + reach) * s) + 1 - y0);
		// (untransformed: only the part inside the clip rasterized, so a path
		// far larger than the window (a glyph zoomed in) costs the window)
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
		// (on the grid: its origin rounded, its size whole pixels, the same wherever it is)
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
			texture(img);
			shape(x0, y0, x1, y1, u0, v0, u1, v1, Color.WHITE, 0, 2, 0, 0, img.id);
			return;
		}
		if (culled(x0 - 1, y0 - 1, x1 + 1, y1 + 1)) return;
		texture(img);
		quad(x0, y0, x1, y1, u0, v0, u1, v1, Color.WHITE, 0, 2, 0, 1, img.id);
	}

	// a GPU texture (a render target, rows top to bottom: a <Scene>'s) at x, y, w x h; id names it, negative, one per texture
	public function gpuTexture(t:Texture, id:Int, x:Float, y:Float, w:Float, h:Float, radius:Float = 0.0, ?corners:Corners) {
		if (w <= 0 || h <= 0 || id >= 0) return;
		gpu.set(id, t);
		if (composite != null && composite.fresh.indexOf(t) < 0) composite.fresh.push(t);
		var s = scale;
		edges((x + tx) * s, (y + ty) * s, (x + w + tx) * s, (y + h + ty) * s);
		var x0 = ex0, y0 = ey0, x1 = ex1, y1 = ey1;
		this.corners(corners, radius);
		fit(x1 - x0, y1 - y0);
		sides(null, 0);
		if (!flat) {
			shape(x0, y0, x1, y1, 0, 0, 1, 1, Color.WHITE, 0, 2, 0, 0, id);
			return;
		}
		if (culled(x0 - 1, y0 - 1, x1 + 1, y1 + 1)) return;
		quad(x0, y0, x1, y1, 0, 0, 1, 1, Color.WHITE, 0, 2, 0, 1, id);
	}

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>)
		glyphs(p, x, y, width, align, color, colors, -1);

	// (a text shadow's glyphs: their outlines, a colour font's too, in its
	// colour, blurred: CSS's blur, the Gaussian's standard deviation half of
	// it; a colour bitmap's glyph has none and casts none)
	public function textShadow(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, blur:Float, ?colors:Array<Color>)
		glyphs(p, x, y, width, align, color, colors, blur);

	// (blur < 0: the text itself)
	function glyphs(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, colors:Null<Array<Color>>, blur:Float) {
		var dp = cast(p, DrawParagraph);
		var t = dp.layout, s = scale;
		var size = t.fonts.size * s;
		var ox = x + tx, oy = y + ty;
		if (!flat) {
			if (mk < 1e-6) return;
			// (in the scaled pixels: on the target's grid where aligned)
			s *= mk;
			size *= mk;
		}
		// (a shadow's blur in device pixels, to a quarter: the atlas keeps each; how far it reaches)
		var sigma = blur > 0 ? Math.round(blur * s / 2 * 4) / 4 : 0.0, reach = 3 * sigma;
		for (l in t.lines) {
			var lx = switch align {
				case Center: (width - l.width) / 2;
				case Right: width - l.width;
				case _: 0.0;
			}
			var by = Math.round((oy + l.top + l.baseline) * s + (flat ? 0 : mf - Std.int(mf)));
			// (the line's origin on the grid: its glyphs placed from a whole pixel)
			var lineX = (ox + lx) * s;
			if (grid) lineX = Math.fround(lineX);
			if (flat && !uncull && (by - size * 1.5 - reach > clipY1 || by + size + reach < clipY0)) continue;
			if (!flat && !uncull && away(lineX - size, by - size * 1.5 - reach, lineX + l.width * s + size, by + size + reach)) continue;
			for (i in l.glyphStart...l.glyphEnd) {
				var c = t.glyphChar(i);
				if (c == 32 || c == 10 || c == 9 || t.glyphHidden(i)) continue;
				var id = t.glyphId(i), run = t.glyphRun(i);
				var gx = lineX + (t.glyphX(i) + t.glyphOffsetX(i)) * s, gy = by + Math.round(t.glyphOffsetY(i) * s);
				var f = t.glyphFont(i);
				// (a run's glyphs: its size and colour)
				var set = t.glyphFontSet(i);
				var size = run < 0 ? size : set.size * s, oblique = set.oblique;
				var color = run >= 0 && colors != null && run < colors.length ? colors[run] : color;
				if (f.hasColor && blur < 0) {
					// (colour layers: each its glyph in its colour; else a colour bitmap)
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
						if (!flat || !culled(qx, qy, qx + b.image.width, qy + b.image.height)) {
							texture(b.image);
							qr0 = qr1 = qr2 = qr3 = qw0 = qw1 = qw2 = qw3 = 0;
							quad(qx, qy, qx + b.image.width, qy + b.image.height, 0, 0, 1, 1, Color.WHITE, 0, 2, 0, 1, b.image.id);
						}
						continue;
					}
				}
				glyph(f, id, size, gx, gy, color, oblique, sigma);
			}
		}
	}

	// glyphs past this ppem (device pixels) are drawn alone, each an image of
	// its own, not packed into the atlas (Skia's limit for its atlas too): a
	// 1024 atlas holds a dozen of them, a design zoomed into (28 points at 3x
	// zoomed 8 times: 670) would hold none
	public static inline var LARGE = 256;

	// a glyph from the atlas at (gx, gy): device pixels, the baseline
	// (under a transform: scaled pixels, gy whole on the target's grid less
	// the translation's fraction, which the glyph is moved back by); one too
	// large for it, or that did not fit this frame, an image of its own
	// (the glyph quad's blend: the platform's, its coverage's contrast and gamma)
	var blend:Null<helder.text.Shaping.GlyphBlend> = null;

	inline function glyph(f:helder.text.FontFile, id:Int, size:Float, gx:Float, gy:Int, color:Color, oblique:Bool, sigma = 0.0) {
		// (aligned: the subpixel offset on the target's grid, as the transform moves it;
		// the pen floored to CoreGraphics' step for its ppem, as CoreText places it;
		// the colour's luminance sets font smoothing's dilation)
		var ex = flat ? 0.0 : me - Std.int(me), ey = flat ? 0.0 : mf - Std.int(mf);
		// (under a transform: culled before it is drawn, by a box any glyph's ink is in)
		if (!flat && away(gx - size, gy - size * 1.5 - 3 * sigma, gx + size * 2, gy + size + 3 * sigma)) return;
		// (under a scale that moved since the last frame, a pinch's or a zoom's
		// flight: drawn at the nearest quarter octave and stretched, so that
		// a zoom draws a few sizes, not one a frame; at its own once it rests)
		var at = size;
		if (steps && !steady && mk != 1) {
			at = Math.pow(2, Math.round(Math.log(size) / Math.log(2) * 4) / 4);
			sigma = sigma * at / size;
			again = true;
		}
		var k = size / at, ix = GlyphAtlas.pixel(gx + ex, size), sub = k == 1 ? GlyphAtlas.phase(gx + ex, size) : 0;
		var a = at > LARGE ? null : atlas.get(f, id, at, sub, oblique, sigma, color & 0xFFFFFF);
		if (a == null) {
			alone(f, id, at, k, gx, gy, ix, ex, ey, sub, color, oblique, sigma);
			return;
		}
		if (a.w > 0) {
			var qx = k == 1 ? ix - ex + a.left : gx + a.left * k, qy = gy + a.top * k - ey;
			if (!flat || !culled(qx, qy, qx + a.w, qy + a.h)) {
				qr0 = qr1 = qr2 = qr3 = qw0 = qw1 = qw2 = qw3 = 0;
				stretched = k != 1;
				blend = a.blend;
				quad(qx, qy, qx + a.w * k, qy + a.h * k, a.x / atlas.width, a.y / atlas.height, (a.x + a.w) / atlas.width, (a.y + a.h) / atlas.height, color,
					0, 1, 0, 0, 0);
				stretched = false;
				blend = null;
			}
		}
	}

	// (the large glyphs drawn this frame or the last, images of their own,
	// in their colour: by font, glyph, size, phase, oblique, blur and colour)
	final large = new Map<String, LargeGlyph>();

	function alone(f:helder.text.FontFile, id:Int, size:Float, k:Float, gx:Float, gy:Int, ix:Int, ex:Float, ey:Float, sub:Int, color:Color,
			oblique:Bool, sigma:Float) {
		var key = f.id + ":" + id + ":" + size + ":" + sub + (oblique ? ":o" : "") + ":" + sigma + ":" + (color & 0xFFFFFF);
		var e = large.get(key);
		if (e == null) {
			var b = atlas.bitmap(f, id, size, sub, oblique, sigma, color & 0xFFFFFF);
			if (b == null) return;
			var w = b.width, h = b.height, rgba = Bytes.alloc(w * h * 4);
			FrameCounts.glyphTexels += w * h;
			var r = color.r, g = color.g, bl = color.b;
			for (i in 0...w * h) {
				rgba.set(i * 4, r);
				rgba.set(i * 4 + 1, g);
				rgba.set(i * 4 + 2, bl);
				rgba.set(i * 4 + 3, b.pixels.get(i));
			}
			large.set(key, e = new LargeGlyph(new Image(w, h, rgba), b.left, b.top));
		}
		e.frame = frames;
		var img = e.image;
		var qx = k == 1 ? ix - ex + e.left : gx + e.left * k, qy = gy + e.top * k - ey;
		var x1 = qx + img.width * k, y1 = qy + img.height * k;
		if (flat && culled(qx, qy, x1, y1)) return;
		texture(img);
		qr0 = qr1 = qr2 = qr3 = qw0 = qw1 = qw2 = qw3 = 0;
		quad(qx, qy, x1, y1, 0, 0, 1, 1, ((color : Int) | 0xFFFFFF : Color), 0, 2, 0, 0, img.id);
	}

	// a colour bitmap glyph at a size (device pixels): its PNG decoded and
	// scaled down (averaged over each pixel's area, as a browser draws it
	// small), kept per face, glyph and size; its place from the origin
	final colorGlyphs = new Map<String, Null<{image:Image, left:Float, top:Int}>>();

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

	// --- vertices ---

	inline function culled(x0:Float, y0:Float, x1:Float, y1:Float)
		return !uncull && (x1 <= clipX0 || y1 <= clipY0 || x0 >= clipX1 || y0 >= clipY1  || clipX1 <= clipX0 || clipY1 <= clipY0);

	// (a box in the scaled pixels under the transform outside the clip: its turned corners' bounds)
	function away(x0:Float, y0:Float, x1:Float, y1:Float):Bool {
		var k = mk, ra = ma / k, rb = mb / k, rc = mc / k, rd = md / k;
		var ax = ra * x0 + rc * y0, bx = ra * x1 + rc * y0, cx = ra * x0 + rc * y1, dx = ra * x1 + rc * y1;
		var ay = rb * x0 + rd * y0, by = rb * x1 + rd * y0, cy = rb * x0 + rd * y1, dy = rb * x1 + rd * y1;
		return culled(Math.min(Math.min(ax, bx), Math.min(cx, dx)) + me, Math.min(Math.min(ay, by), Math.min(cy, dy)) + mf,
			Math.max(Math.max(ax, bx), Math.max(cx, dx)) + me, Math.max(Math.max(ay, by), Math.max(cy, dy)) + mf);
	}

	// a rectangle, shadow or image under a transform: from device pixels to
	// the scaled ones (lengths too), culled by its turned corners' bounds;
	// blur: the margin it grows by before its anti-aliased pixel
	function shape(x0:Float, y0:Float, x1:Float, y1:Float, u0:Float, v0:Float, u1:Float, v1:Float, fill:Color, border:Color, mode:Float, blur:Float,
			grow:Float, image:Int) {
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
		quad(x0, y0, x1, y1, u0, v0, u1, v1, fill, border, mode, blur * k, m, image);
	}

	// a quad over x0, y0, x1, y1 grown by margin m (a rectangle's anti-aliased
	// edge, a shadow's blur), its texture coordinates growing with it; its
	// corners and border sides: qr*, qw*; an instance of UiShader's quad
	function quad(x0:Float, y0:Float, x1:Float, y1:Float, u0:Float, v0:Float, u1:Float, v1:Float, fill:Color, border:Color, mode:Float, blur:Float,
			m:Float, image:Int) {
		// (an image: its texture bound, its place in a page and its texels'
		// bounds there (read clamped to them); a glyph: read filtered where turned)
		var w0 = qw0, w1 = qw1, w2 = qw2, w3 = qw3, filtered = 0;
		var ax = x0 - m, ay = y0 - m, bx = x1 + m, by = y1 + m;
		// (in a kept frame's rectangle: an unturned quad's corners cut to it)
		var cut = cutting && batch == kept.batch;
		if (cut && flat) {
			ax = Math.max(ax, cutX0);
			ay = Math.max(ay, cutY0);
			bx = Math.min(bx, cutX1);
			by = Math.min(by, cutY1);
			if (ax >= bx || ay >= by) return;
		}
		if (mode == 2) {
			var e = image < 0 ? null : textures.get(image);
			if (e == null || e.page < 0) {
				bind(e == null ? gpu.get(image) : e.texture);
				w0 = w1 = -1e9;
				w2 = w3 = 1e9;
			} else {
				bind(e.texture);
				var k = 1 / PAGE;
				u0 = (e.x + u0 * e.width) * k;
				u1 = (e.x + u1 * e.width) * k;
				v0 = (e.y + v0 * e.height) * k;
				v1 = (e.y + v1 * e.height) * k;
				w0 = (e.x + 0.5) * k;
				w1 = (e.y + 0.5) * k;
				w2 = (e.x + e.width - 0.5) * k;
				w3 = (e.y + e.height - 0.5) * k;
			}
		} else if (mode == 1) {
			w0 = atlas.width;
			w1 = atlas.height;
			w2 = w3 = 0;
			filtered = aligned && !stretched ? 0 : 1;
		} else if (mode == 0) {
			filtered = (cast dash : Int);
			dash = Solid;
		}
		var o = batch.add(run), b = batch.bytes;
		// (the compositor's frame's own quads: not those drawn into a mover's group)
		if (templating && batch == composite.batch) {
			var c = composite;
			c.content.push(contentFrame);
			c.clip.push(clipFrame);
			c.thumb.push(thumbTag);
			c.mover.push(moverTag);
			c.clipMover.push(clipMover);
			c.fade.push(thumbTag >= 0 ? fadeTag : 0);
		}
		var fa = fill.a / 255 * alpha, ba = border.a / 255 * alpha;
		var hx = (x1 - x0) / 2, hy = (y1 - y0) / 2;
		var mu = (u1 - u0) * m / (x1 - x0), mv = (v1 - v0) * m / (y1 - y0);
		// (the corners in target pixels and clip space: the transform less its scale, exact for none)
		var k = mk, ra = flat ? 1 : ma / k, rb = flat ? 0 : mb / k, rc = flat ? 0 : mc / k, rd = flat ? 1 : md / k, te = flat ? 0 : me, tf = flat ? 0 : mf;
		inline function corner(at:Int, px:Float, py:Float) {
			var X = ra * px + rc * py + te - ox, Y = rb * px + rd * py + tf - oy;
			b.setFloat(at, X / targetW * 2 - 1);
			b.setFloat(at + 4, 1 - Y / targetH * 2);
			b.setFloat(at + 8, X);
			b.setFloat(at + 12, Y);
		}
		corner(o, ax, ay);
		corner(o + 16, bx, ay);
		corner(o + 32, ax, by);
		b.setFloat(o + 48, u0 - mu);
		b.setFloat(o + 52, v0 - mv);
		b.setFloat(o + 56, u1 + mu);
		b.setFloat(o + 60, v1 + mv);
		b.setFloat(o + 64, hx);
		b.setFloat(o + 68, hy);
		b.setFloat(o + 72, hx + m);
		b.setFloat(o + 76, hy + m);
		b.setFloat(o + 80, fill.r / 255 * fa);
		b.setFloat(o + 84, fill.g / 255 * fa);
		b.setFloat(o + 88, fill.b / 255 * fa);
		b.setFloat(o + 92, fa);
		// (a glyph blended as the platform blends it: the gamma's ratios where a border's colour is, its contrast in params.w)
		var gb = mode == 1 ? blend : null;
		if (gb != null) {
			b.setFloat(o + 96, gb.ratios[0]);
			b.setFloat(o + 100, gb.ratios[1]);
			b.setFloat(o + 104, gb.ratios[2]);
			b.setFloat(o + 108, gb.ratios[3]);
		} else {
			b.setFloat(o + 96, border.r / 255 * ba);
			b.setFloat(o + 100, border.g / 255 * ba);
			b.setFloat(o + 104, border.b / 255 * ba);
			b.setFloat(o + 108, ba);
		}
		b.setFloat(o + 112, qr0);
		b.setFloat(o + 116, qr1);
		b.setFloat(o + 120, qr2);
		b.setFloat(o + 124, qr3);
		b.setFloat(o + 128, w0);
		b.setFloat(o + 132, w1);
		b.setFloat(o + 136, w2);
		b.setFloat(o + 140, w3);
		b.setFloat(o + 144, mode);
		b.setFloat(o + 148, blur);
		b.setFloat(o + 152, filtered);
		b.setFloat(o + 156, gb != null ? 1 + gb.contrast : 0);
		b.setFloat(o + 160, clipX0 - ox);
		b.setFloat(o + 164, clipY0 - oy);
		b.setFloat(o + 168, clipX1 - ox);
		b.setFloat(o + 172, clipY1 - oy);
		b.setFloat(o + 176, clipR0);
		b.setFloat(o + 180, clipR1);
		b.setFloat(o + 184, clipR2);
		b.setFloat(o + 188, clipR3);
		// (an unturned quad's centre, whole and fraction: its fragments' positions from it, Uishader)
		if (flat) {
			var cx = (x0 + x1) / 2 - ox, cy = (y0 + y1) / 2 - oy, ix = Math.ffloor(cx), iy = Math.ffloor(cy);
			b.setFloat(o + 192, ix);
			b.setFloat(o + 196, iy);
			b.setFloat(o + 200, cx - ix);
			b.setFloat(o + 204, cy - iy);
		} else {
			b.setFloat(o + 192, -1e9);
			b.setFloat(o + 196, 0);
			b.setFloat(o + 200, 0);
			b.setFloat(o + 204, 0);
		}
		// (what it may change: the target, or a kept frame's rectangle)
		b.setFloat(o + 208, cut ? cutX0 - ox : -1e9);
		b.setFloat(o + 212, cut ? cutY0 - oy : -1e9);
		b.setFloat(o + 216, cut ? cutX1 - ox : 1e9);
		b.setFloat(o + 220, cut ? cutY1 - oy : 1e9);
	}
}

// (an opacity group: its quads, its runs' textures, the render target they
// are drawn into (grown, kept), the part of it drawn and where that is in
// the target's pixels, its opacity; the state it was opened in)
private class Group {
	static var ids = 0;

	// (its texture's id among the GPU textures drawn: Renderer.gpu's)
	public final id = -(0x40000000 + ++ids);
	public final batch = new QuadBatch(@:privateAccess Renderer.STRIDE, 64, true);
	public final textures:Array<Null<Texture>> = [];
	public final pass:PassDesc = {colors: [{load: Clear, clear: new helder.gfx.Color(0, 0, 0, 0)}]};
	public var texture:Null<Texture> = null;
	public var textureWidth = 0;
	public var textureHeight = 0;
	public var x = 0.0;
	public var y = 0.0;
	public var width = 0;
	public var height = 0;
	public var alpha = 1.0;
	public var frame = 0;
	public var outer:Null<QuadBatch> = null;
	public var outerTextures:Null<Array<Null<Texture>>> = null;
	public var outerRun = 0;
	public var outerX = 0.0;
	public var outerY = 0.0;
	public var outerW = 0.0;
	public var outerH = 0.0;

	public function new() {}

	// (begun for a part of w x h: its texture at least that, grown by 64s; exact: that)
	public function open(device:Device, w:Int, h:Int, exact = false) {
		width = w;
		height = h;
		if (texture == null || textureWidth < w || textureHeight < h || exact && (textureWidth != w || textureHeight != h)) {
			free(device);
			textureWidth = Std.int(Math.min(device.maxTextureSize, exact ? w : Math.ceil(w / 64) * 64));
			textureHeight = Std.int(Math.min(device.maxTextureSize, exact ? h : Math.ceil(h / 64) * 64));
			texture = device.createTexture({width: textureWidth, height: textureHeight, format: RGBA8, renderTarget: true});
		}
		batch.clear();
		textures.resize(0);
		textures.push(null);
	}

	public function free(device:Device) {
		if (texture != null) device.destroyTexture(texture);
		texture = null;
		textureWidth = textureHeight = 0;
	}
}

// (a layer's tiles: by their place, drawn at its translation rx, ry, at a scale, of what it painted then)
private class LayerTiles {
	public final tiles:Array<LayerTile> = [];
	final at = new haxe.ds.IntMap<LayerTile>();
	public var rx = 0.0;
	public var ry = 0.0;
	public var scale = 0.0;
	public var content = -1;
	// (the frame it was last drawn in)
	public var frame = 0;

	public function new() {}

	static inline function key(i:Int, j:Int):Int
		return (i & 0xFFFF) << 16 | (j & 0xFFFF);

	public inline function get(i:Int, j:Int):Null<LayerTile>
		return at.get(key(i, j));

	public function put(k:LayerTile) {
		at.set(key(k.i, k.j), k);
		tiles.push(k);
	}

	// (its tiles drawn again before they are drawn: kept, their textures too)
	public function drop()
		for (k in tiles)
			k.content = -1;

	public function remove(k:LayerTile, device:Device) {
		at.remove(key(k.i, k.j));
		tiles.remove(k);
		k.group.free(device);
	}

	public function free(device:Device) {
		for (k in tiles)
			k.group.free(device);
		tiles.resize(0);
		at.clear();
	}
}

private class LayerTile {
	public final i:Int;
	public final j:Int;
	public final group = new Group();
	// (what its layer painted, the layer's record, when drawn into; whether all of it was recorded then)
	public var content = -1;
	public var stamp = -1;
	public var whole = false;
	public var frame = 0;

	public function new(i, j) {
		this.i = i;
		this.j = j;
	}

	public inline function valid(l:Layer):Bool
		return content == l.content && (whole || stamp == l.stamp);
}

// (an image's texture: its own (page -1), or a page's, its place x, y in it)
private class ImageEntry {
	public var texture:Null<Texture> = null;
	public var version:Int;
	public var frame:Int;
	public final width:Int;
	public final height:Int;
	public var page = -1;
	// another process's texture (Renderer.opened's): not this entry's to free
	public var external = false;
	public var x = 0;
	public var y = 0;

	public function new(version, frame, width, height) {
		this.version = version;
		this.frame = frame;
		this.width = width;
		this.height = height;
	}
}

// (an atlas page of images: shelves, each a row of images as high as its
// first, filled left to right; live: the images in it; emptied when none are)
private class ImagePage {
	public final texture:Texture;
	public var live = 0;
	public var used = false;
	// (each shelf's top, height and the next x on it)
	final shelves:Array<Int> = [];
	var bottom = 0;

	public function new(texture)
		this.texture = texture;

	public function reset() {
		shelves.resize(0);
		bottom = 0;
		used = false;
	}

	public function allocate(e:ImageEntry):Bool {
		var w = e.width, h = e.height, size = Renderer.PAGE;
		var k = 0;
		while (k < shelves.length) {
			if (shelves[k + 1] >= h && shelves[k + 1] <= h * 2 && shelves[k + 2] + w <= size) {
				place(e, shelves[k + 2], shelves[k]);
				shelves[k + 2] += w;
				return true;
			}
			k += 3;
		}
		if (bottom + h > size) return false;
		shelves.push(bottom);
		shelves.push(h);
		shelves.push(w);
		place(e, 0, bottom);
		bottom += h;
		return true;
	}

	inline function place(e:ImageEntry, x:Int, y:Int) {
		e.x = x;
		e.y = y;
		live++;
		used = true;
	}
}

// (a glyph too large for the atlas: its image, in its colour, its top left from its origin, the last frame that drew it)
private class LargeGlyph {
	public final image:Image;
	public final left:Int;
	public final top:Int;
	public var frame = 0;

	public function new(image, left, top) {
		this.image = image;
		this.left = left;
		this.top = top;
	}
}
