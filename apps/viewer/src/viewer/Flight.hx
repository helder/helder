package viewer;

import helder.os.Rect;
import helder.image.Image;
import helder.ui.Clock;
import helder.ui.Event;
import helder.ui.Key;
import helder.ui.Node;
import helder.ui.Transition;
import helder.ui.controls.Look;
import helder.ui.motion.Curve;
import helder.ui.motion.Track;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// A file opening from its tile and closing into it, as iOS Photos' and
// Quick Look's: its thumbnail (a document's page where it has none) flies
// from the tile to where the file is shown full size (an image fitted, a
// PDF's page, a Markdown document's column) on a spring (SPRING: quick to
// start, settling soft, under 1% over), uncropping as it grows (the tile's
// square cover crop opening to the picture's own shape), its corners the
// tile's to none, a shadow while it is lifted, the sharp decode faded in
// over the thumbnail as soon as it is there; the browser behind a little
// smaller and darker (DEPTH_*), the viewer fading in over it. Closed,
// back into the tile of the file shown last, scrolled into view first.
// One progress (0 the tile, 1 full size) carries it all, its velocity
// kept: closed mid-flight it turns back from where it is and as fast; the
// rects it flies between are springs of their own, so that a decode
// landing elsewhere than the thumbnail guessed, a file stepped to, a tile
// scrolled to are flown on to, never jumped to. A gesture moves it with
// the fingers (a pinch out on a tile, a pinch in at the fit or a swipe
// down full size; a phone's swipe down) and lets it go into the spring
// with its speed, on to the end it was going to or back. The tile hides
// while its picture is in flight, the image view draws none (no double).
// No tile (a file opened by its path, one gone from the folder), no
// picture or reduced motion: the viewer's fade alone (reduced: a short one).
class Flight implements Markup {
	// (SwiftUI's response and bounce: 0.6% over, settled by its thresholds)
	public static final SPRING = Curve.spring(0.36, 0.15);
	// (the sharp picture over its thumbnail)
	static final SHARPEN = Curve.tween(0.12, Transition.EASE_OUT);
	// the browser behind the file full size: this much smaller, this much darker
	public static inline var DEPTH_SCALE = 0.03;
	public static inline var DEPTH_DIM = 0.18;
	// (how long a tile is waited for; a decode held for; a wheel's gesture let go after)
	static inline var WAIT = 0.25;
	static inline var HOLD = 1.0;
	static inline var IDLE = 0.15;
	// (a Markdown document's column: Shell's markdown-row)
	static inline var COLUMN = 760.0;
	// (a sharp picture made of a decode no larger than this many pixels)
	static inline var SHARP_PIXELS = 3000 * 3000;

	// the path whose picture is in flight ("" none)
	public final flying = signal("");
	// how far the file full size is shown over the browser, 0 to 1 (the fade, the depth)
	public final shown = signal(0.0);
	// the picture in flight: where (in the root's points), its corners, how
	// lifted (its shadow), its thumbnail and where it is drawn in the box
	// (its cover crop), the sharp picture and how far it is faded in; a
	// document's page (no picture) and that page's opacity
	public final box = signal(({x: 0.0, y: 0.0, width: 0.0, height: 0.0} : Rect));
	public final radius = signal(0.0);
	public final lift = signal(0.0);
	public final image = signal((null : Null<Image>));
	public final crop = signal(({x: 0.0, y: 0.0, width: 0.0, height: 0.0} : Rect));
	public final sharp = signal((null : Null<Image>));
	public final sharpness = signal(0.0);
	public final page = signal(1.0);

	final x:Explorer;
	// (0: the tile, 1: full size)
	final p = new Track(0, 1e-3);
	final clear = new Track(0, 1e-3);
	final small = [for (_ in 0...4) new Track(0, 0.01)];
	final large = [for (_ in 0...4) new Track(0, 0.01)];
	final tiles:Array<{node:Node, path:String}> = [];
	var root:Null<Node> = null;
	var stage:Null<Node> = null;
	var path = "";
	var opening = false;
	var running = false;
	var tileKnown = false;
	var since = -1.0;
	var r0 = 0.0;
	var sharpTried = false;
	// (a gesture's: its kind ("pinch", "swipe", "drag": a phone's), where
	// it began, how far, its last time, its speed, what its end does)
	var gesture = "";
	var p0 = 0.0;
	var moved = 0.0;
	var lastAt = -1.0;
	var lastP = 0.0;
	var speed = 0.0;
	var ended:Null<Bool->Void> = null;

	public function new(x:Explorer)
		this.x = x;

	// the window's content it flies over (its origin the box's)
	public function attach(n:Node)
		root = n;

	// the image view, where an image is fitted
	public function view(n:Node)
		stage = n;

	// a tile's picture of the file at path (cleaned up with its view)
	public function tile(n:Node, path:String) {
		var t = {node: n, path: path};
		tiles.push(t);
		onCleanup(() -> tiles.remove(t));
	}

	// how far it is now (0 the tile, 1 full size)
	public function progress():Float
		return p.value;

	// whether a gesture holds it (its fingers down, a wheel's moves coming)
	public function holding():Bool
		return gesture != "";

	public function open(path:String)
		begin(path, true);

	public function close(path:String)
		begin(path, false);

	function begin(path:String, opening:Bool) {
		this.opening = opening;
		var r = root, to = opening ? 1.0 : 0.0;
		if (r == null || r.ui == null) {
			p.set(to);
			shown(to);
			land();
			gesture = "";
			return;
		}
		var reduced = Clock.reducedMotion, curve = reduced ? Curve.REDUCED_FADE : SPRING;
		// (the same file in flight, or held by a gesture: on from where it is, as fast)
		if (!reduced && path == this.path && (flying.peek() != "" || gesture != "")) {
			p.animate(-1, to, curve, gesture != "" ? speed : null);
			gesture = "";
			ended = null;
			run();
			return;
		}
		gesture = "";
		ended = null;
		var e = x.browser.entry(Browser.name(path)), img = e == null ? null : Tiles.cached(x, e);
		var from = opening ? tileAt(path) : fileAt(path, img);
		if (reduced || e == null || from == null || img == null && !document(path)) land() else {
			// (a new flight: from its own end)
			p.set(opening ? 0 : 1);
			start(path, img, opening ? null : from);
		}
		p.animate(-1, to, curve);
		run();
	}

	// (a new flight of path's picture: from its tile (full null) or from full size)
	function start(path:String, img:Null<Image>, from:Null<Rect>) {
		this.path = path;
		var t = tileAt(path), f = from ?? fileAt(path, img);
		tileKnown = t != null;
		// (a tile not shown yet: it grows out of, or shrinks into, the picture's middle until it is)
		set(small, t ?? shrunk(f));
		set(large, f ?? t);
		r0 = tileRadius(path);
		since = -1;
		sharpTried = false;
		sharp(null);
		clear.set(0);
		// (closed from full size: the sharp picture first, the thumbnail's as it lands)
		if (from != null) {
			var s = sharpOf(path);
			if (s != null) {
				sharp(s);
				clear.set(1);
				sharpTried = true;
			}
		}
		image(img);
		flying(path);
		place();
	}

	function run() {
		if (running) return;
		running = true;
		var r = root;
		if (r != null) Clock.addFor(r, step);
	}

	function step(t:Float):Bool {
		if (gesture == "") p.sample(t) else {
			// (a gesture's speed: what its moves did since the last frame; a wheel's still a while: let go)
			if (lastAt >= 0 && t > lastAt) speed = speed * 0.5 + (p.value - lastP) / (t - lastAt) * 0.5;
			lastAt = t;
			lastP = p.value;
			if (gesture != "drag" && t - moved > IDLE) release();
		}
		shown(Math.max(0, Math.min(1, p.value)));
		if (flying.peek() != "") fly(t);
		running = flying.peek() != "" || p.moving() || gesture != "";
		return running;
	}

	// (the flight's frame at t: its rects' goals, where it is between them)
	function fly(t:Float) {
		if (since < 0) since = t;
		// (stepped to another file meanwhile: on to it)
		var current = x.viewer.folder.current;
		if (opening && gesture == "" && x.full.value && current != null && current != path) {
			var e = x.browser.entry(Browser.name(current));
			path = current;
			image(e == null ? null : Tiles.cached(x, e));
			sharp(null);
			clear.set(0);
			sharpTried = false;
			flying(path);
		}
		var f = fileAt(path, image.peek()), g = tileAt(path);
		if (f != null) goal(large, f, t);
		if (g != null) {
			goal(small, g, t);
			tileKnown = true;
		}
		// (no tile to close into: the fade alone)
		if (!tileKnown && !opening && gesture == "" && t - since > WAIT) {
			land();
			return;
		}
		for (k in 0...4) {
			small[k].sample(t);
			large[k].sample(t);
		}
		// (the sharp picture as soon as it is decoded; closing, the thumbnail's again near the tile)
		if (!sharpTried && opening && decodedFor(path)) {
			sharpTried = true;
			var s = sharpOf(path);
			if (s != null) {
				sharp(s);
				clear.animate(t, 1, SHARPEN);
			}
		}
		if (!opening && clear.target > 0 && p.value < 0.4) clear.animate(t, 0, SHARPEN);
		clear.sample(t);
		place();
		var still = !p.moving() && !moving(small) && !moving(large) && !clear.moving();
		if (gesture == "" && still && !(opening && held(t))) land();
	}

	// (an image still decoding, opened: its thumbnail kept in its place a while)
	function held(t:Float):Bool {
		var v = x.viewer;
		return opening && v.state.peek() == Loading && !decodedFor(path) && t - since < HOLD;
	}

	// (the flight over: the tile and the image shown again)
	function land() {
		image(null);
		sharp(null);
		flying("");
		path = "";
	}

	function place() {
		var o = root.windowBounds(), k = p.value;
		var a = rect(small), b = rect(large), r = lerp(a, b, k);
		box({x: r.x - o.x, y: r.y - o.y, width: r.width, height: r.height});
		radius(Math.max(0, r0 * (1 - k)));
		// (lifted most half way, none at either end)
		lift(Math.max(0, Math.min(1, 4 * k * (1 - k))));
		var img = image.peek();
		if (img != null) crop(cover(r.width, r.height, img.width, img.height));
		sharpness(clear.value);
		// (a document's page into its column: it gives way to it)
		page(1 - Math.max(0, Math.min(1, k)));
	}

	// --- gestures

	// a wheel over the tile of name (the grid's): a pinch out opens the file
	// following the fingers (on past a third of the way or let go quick,
	// else back); whether it took it
	public function tileWheel(name:String, e:Event):Bool {
		if (x.full.value) return false;
		var at = x.browser.path(name);
		if (gesture == "pinch" && opening && path == at) {
			pinched(e.deltaY);
			return true;
		}
		if (e.mods & helder.os.Mods.CONTROL == 0 || e.deltaY >= 0 || Clock.reducedMotion) return false;
		var entry = x.browser.entry(name);
		if (entry == null || !Kinds.viewable(entry) || Tiles.cached(x, entry) == null || tileAt(at) == null) return false;
		if (!hold(at, true, "pinch", commit -> if (commit) x.open(name))) return false;
		pinched(e.deltaY);
		return true;
	}

	// a wheel over the file full size: a pinch in at the fit, or a swipe
	// down (a trackpad's, not a wheel's notches), closes it following the
	// fingers; whether it took it
	public function fullWheel(e:Event):Bool {
		var at = x.viewer.folder.current;
		if (!x.full.value || at == null) return false;
		if (gesture != "" && !opening && path == at) {
			if (gesture == "pinch") pinched(e.deltaY) else swiped(e.deltaY);
			return true;
		}
		var v = x.viewer, pinch = e.mods & helder.os.Mods.CONTROL != 0;
		if (Clock.reducedMotion || !v.camera.fitted || v.pdf.peek() != null || v.markdown.peek() != null) return false;
		if (pinch ? e.deltaY <= 0 : e.eased || e.deltaY >= 0 || Math.abs(e.deltaX) > Math.abs(e.deltaY)) return false;
		if (!hold(at, false, pinch ? "pinch" : "swipe", commit -> if (commit) x.close())) return false;
		if (pinch) pinched(e.deltaY) else swiped(e.deltaY);
		return true;
	}

	// a phone's drag down of the file full size by dy points of a view
	// height tall: it shrinks toward its tile as the finger goes; let go
	// (release) on to the tile, or back (done: whether it closed)
	public function drag(dy:Float, height:Float, done:Bool->Void) {
		var at = x.viewer.folder.current;
		if (at == null || Clock.reducedMotion) return;
		if (gesture == "" && !hold(at, false, "drag", done)) return;
		follow(dragged(p0, dy, height));
	}

	// the gesture let go: on to its end (its end's callback told) or back
	public function release() {
		if (gesture == "") return;
		var commit = commits(p.value, speed, opening), done = ended;
		if (commit && done != null) {
			done(true);
			// (its end's callback did not end it: on anyway)
			if (gesture != "") begin(path, opening);
			return;
		}
		gesture = "";
		ended = null;
		p.animate(-1, opening ? 0 : 1, SPRING, speed);
		if (done != null) done(false);
		run();
	}

	// (a gesture taken: the picture held where it is, or a flight begun from its start)
	function hold(at:String, opening:Bool, kind:String, end:Bool->Void):Bool {
		if (flying.peek() == "" || path != at) {
			var e = x.browser.entry(Browser.name(at)), img = e == null ? null : Tiles.cached(x, e);
			var from = opening ? tileAt(at) : fileAt(at, img);
			if (from == null || img == null && !document(at)) return false;
			this.opening = opening;
			p.set(opening ? 0 : 1);
			start(at, img, opening ? null : from);
		}
		this.opening = opening;
		gesture = kind;
		ended = end;
		p0 = p.value;
		spread = 0;
		moved = Clock.now;
		lastAt = -1;
		speed = 0;
		p.set(p.value);
		run();
		return true;
	}

	// (the fingers' spread so far: a wheel's -180 ln(scale) each (helder.os's pinch))
	var spread = 0.0;

	function pinched(dy:Float) {
		spread += dy;
		var a = rect(small), b = rect(large);
		follow(scaled(a.width, b.width, p0, Math.exp(-spread / 180)));
	}

	// (a swipe's way down so far: the scroll's the other way, the fingers' down)
	function swiped(dy:Float) {
		spread -= dy;
		var s = stage;
		follow(dragged(p0, spread, s == null || s.height <= 0 ? 600 : s.height));
	}

	function follow(v:Float) {
		p.set(Math.max(-0.02, Math.min(1.02, v)));
		moved = Clock.now;
		shown(Math.max(0, Math.min(1, p.value)));
		if (flying.peek() != "") place();
	}

	// the progress where a picture between width from (at 0) and to (at 1),
	// scaled by s since a gesture began at p0, is: the fingers' size followed
	public static function scaled(from:Float, to:Float, p0:Float, s:Float):Float {
		if (to == from) return p0;
		var w = (from + (to - from) * p0) * s;
		return (w - from) / (to - from);
	}

	// the progress after a drag down by dy from p0 in a view height tall:
	// the tile at half its height
	public static function dragged(p0:Float, dy:Float, height:Float):Float
		return p0 - dy / Math.max(1, height * 0.5);

	// whether a gesture let go at p going speed (progress a second) goes on
	// to its end: opening past a third, closing past a fifth, or flung that way
	public static function commits(p:Float, speed:Float, opening:Bool):Bool
		return opening ? speed > 1.5 || p > 0.33 && speed > -1.5 : speed < -1.5 || p < 0.8 && speed < 1.5;

	// a picture iw by ih covering a box w by h, centred: where it is drawn
	// in the box (the square's crop of a tile, none at the picture's own shape)
	public static function cover(w:Float, h:Float, iw:Float, ih:Float):Rect {
		if (iw <= 0 || ih <= 0) return {x: 0, y: 0, width: w, height: h};
		var k = Math.max(w / iw, h / ih);
		return {x: (w - iw * k) / 2, y: (h - ih * k) / 2, width: iw * k, height: ih * k};
	}

	// --- where it flies

	// (the rects' springs: set, or sprung to a new goal from where they are)
	static function set(tr:Array<Track>, r:Null<Rect>) {
		if (r == null) return;
		tr[0].set(r.x);
		tr[1].set(r.y);
		tr[2].set(r.width);
		tr[3].set(r.height);
	}

	static function goal(tr:Array<Track>, r:Rect, t:Float) {
		var v = [r.x, r.y, r.width, r.height];
		for (k in 0...4)
			if (Math.abs(tr[k].target - v[k]) > 0.5) tr[k].animate(t, v[k], SPRING);
	}

	static function moving(tr:Array<Track>):Bool {
		for (t in tr)
			if (t.moving()) return true;
		return false;
	}

	static function rect(tr:Array<Track>):Rect
		return {x: tr[0].value, y: tr[1].value, width: tr[2].value, height: tr[3].value};

	static function lerp(a:Rect, b:Rect, k:Float):Rect
		return {
			x: a.x + (b.x - a.x) * k,
			y: a.y + (b.y - a.y) * k,
			width: Math.max(1, a.width + (b.width - a.width) * k),
			height: Math.max(1, a.height + (b.height - a.height) * k)
		};

	// (a quarter of r, at its middle)
	static function shrunk(r:Null<Rect>):Null<Rect>
		return r == null ? null : {x: r.x + r.width * 3 / 8, y: r.y + r.height * 3 / 8, width: r.width / 4, height: r.height / 4};

	// (the tile of path drawn now, within its scroller's view)
	function tileAt(path:String):Null<Rect> {
		var i = tiles.length;
		while (i-- > 0) {
			var n = tiles[i].node;
			if (tiles[i].path != path || n.ui == null || !n.visible() || n.width <= 0) continue;
			var b = n.windowBounds(), clip = n.parent;
			while (clip != null && clip.style.overflow == Visible)
				clip = clip.parent;
			if (clip == null) return b;
			var c = clip.windowBounds(), cx = b.x + b.width / 2, cy = b.y + b.height / 2;
			return cx >= c.x && cx <= c.x + c.width && cy >= c.y && cy <= c.y + c.height ? b : null;
		}
		return null;
	}

	function tileRadius(path:String):Float {
		for (t in tiles)
			if (t.path == path && t.node.ui != null) return t.node.style.radius;
		return 0;
	}

	// (where path is shown full size: a decoded image's rect, a PDF's page,
	// a document's column, else the picture fitted to the view)
	function fileAt(path:String, img:Null<Image>):Null<Rect> {
		var s = stage;
		if (s == null || s.ui == null || s.width <= 0 || !s.visible()) return null;
		var b = s.windowBounds(), name = Browser.name(path);
		if (FolderModel.isMarkdown(name)) {
			var w = Math.min(COLUMN, b.width);
			return {x: b.x + (b.width - w) / 2, y: b.y, width: w, height: b.height};
		}
		if (Viewer.isPdf(name)) {
			var p = pageOf(s.parent, b);
			if (p != null && x.viewer.folder.current == path) return p;
		} else if (decodedFor(path)) return imageAt(s, b);
		var w = img == null ? 1.0 : img.width, h = img == null ? 1.4142 : img.height;
		var k = Math.min(b.width / w, b.height / h);
		// (a thumbnail smaller than its side is the whole image: at its own size)
		if (img != null && img.width < Thumbnails.SIDE && img.height < Thumbnails.SIDE) k = Math.min(k, 1 / s.ui.scale);
		return {x: b.x + (b.width - w * k) / 2, y: b.y + (b.height - h * k) / 2, width: w * k, height: h * k};
	}

	// (path's image decoded and shown: the viewer's own)
	function decodedFor(path:String):Bool {
		var v = x.viewer;
		return v.folder.current == path && v.shown != null && v.shownPath == v.key();
	}

	// (the decode shown, as a picture to draw over the thumbnail: its first frame's pixels)
	function sharpOf(path:String):Null<Image> {
		if (!decodedFor(path)) return null;
		var d = x.viewer.shown;
		if (d.frames.length == 0 || d.pixelsWidth * d.pixelsHeight > SHARP_PIXELS) return null;
		var rgba = haxe.io.Bytes.alloc(d.pixelsWidth * d.pixelsHeight * 4);
		d.frames[0].pixels.blitToBytes(0, rgba, 0, rgba.length);
		return new Image(d.pixelsWidth, d.pixelsHeight, rgba);
	}

	// (the camera's rect in points; fitted, worked out for the view as it is laid out now)
	function imageAt(s:Node, b:Rect):Rect {
		var c = x.viewer.camera, d = s.ui.scale;
		if (!c.fitted) {
			var r = c.rect(), k = c.viewWidth / s.width;
			return {x: b.x + r.x / k, y: b.y + r.y / k, width: r.width / k, height: r.height / k};
		}
		var f = Math.min(1, Math.min(b.width * d / c.imageWidth, b.height * d / c.imageHeight));
		var w = c.imageWidth * f / d, h = c.imageHeight * f / d;
		return {x: b.x + (b.width - w) / 2, y: b.y + (b.height - h) / 2, width: w, height: h};
	}

	// (a PDF's page across the view's middle, else its first shown)
	static function pageOf(n:Null<Node>, view:Rect):Null<Rect> {
		var pages = n == null ? null : n.find("pdf-pages");
		if (pages == null) return null;
		var first:Null<Rect> = null, mid = view.y + view.height / 2;
		for (p in pages.children) {
			if (p.width <= 0) continue;
			var b = p.windowBounds();
			if (b.y <= mid && b.y + b.height >= mid) return b;
			if (first == null) first = b;
		}
		return first;
	}

	static function document(path:String):Bool
		return Viewer.isPdf(path) || FolderModel.isMarkdown(path);

	// the picture in flight, over everything in the root: its box (corners,
	// shadow) clipping the thumbnail and the sharp picture, each covering it
	public static function layer(z:Flight):View
		return <Show when={z.flying() != ""}>
			<view tag="zoom" position="absolute" left={z.box().x} top={z.box().y} width={z.box().width} height={z.box().height} radius={z.radius()}
				overflow="hidden" pointer-events="none"
				shadow={() -> '0 ${Math.round(14 * z.lift())}px ${Math.round(44 * z.lift())}px rgba(0,0,0,${Math.round(35 * z.lift()) / 100})'}>
				<Show when={z.image() != null}>
					<image tag="zoom-thumb" src={z.image()} position="absolute" left={z.crop().x} top={z.crop().y} width={z.crop().width}
						height={z.crop().height}/>
				</Show>
				<Show when={z.sharp() != null && z.sharpness() > 0}>
					<image tag="zoom-sharp" src={z.sharp()} position="absolute" left={z.crop().x} top={z.crop().y} width={z.crop().width}
						height={z.crop().height} opacity={z.sharpness()}/>
				</Show>
				<Show when={z.image() == null}>
					<view tag="zoom-page" grow={1} radius={z.radius()} background={Look.ref.raised} border-width={1} border-color={Look.ref.edge} opacity={z.page()}/>
				</Show>
			</view>
		</Show>;
}
