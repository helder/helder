package viewer;

import helder.os.Rect;
import helder.image.Image;
import helder.ui.Clock;
import helder.ui.Node;
import helder.ui.Transition;
import helder.ui.controls.Look;
import helder.ui.motion.Curve;
import helder.ui.motion.Track;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// A file opening from its tile and closing into it, as Quick Look and
// photo apps do: its thumbnail (a document's page where it has none)
// moves and scales from the tile to where the file is shown full size
// (an image fitted, a PDF's page, a Markdown document's column) over
// CURVE while the viewer fades in over the browser; closed, back into the
// tile of the file shown last, once it is scrolled into view. The tile
// hides while its picture is in flight and the image view draws none (no
// double); a decode landing elsewhere than the thumbnail guessed is flown
// on to, one still coming held for. No tile (a file opened by its path,
// one gone from the folder), no picture or reduced motion: the fade alone.
class Flight implements Markup {
	public static final CURVE = Curve.tween(0.22, Transition.EASE_OUT);
	// (how long a tile or the full view is waited for, a decode held for)
	static inline var WAIT = 0.25;
	static inline var HOLD = 1.0;
	// (a Markdown document's column: Shell's markdown-row)
	static inline var COLUMN = 760.0;

	// the path whose picture is in flight ("" none)
	public final flying = signal("");
	// how far the file full size is shown over the browser (the desktop's fade)
	public final shown = signal(0.0);
	// the picture in flight: where (in the root's points), its corners, its
	// image (null: a document's page) and that page's opacity
	public final box = signal(({x: 0.0, y: 0.0, width: 0.0, height: 0.0} : Rect));
	public final radius = signal(0.0);
	public final image = signal((null : Null<Image>));
	public final page = signal(1.0);

	final x:Explorer;
	final fade = new Track(0, 1e-4);
	final move = new Track(0, 1e-4);
	final tiles:Array<{node:Node, path:String}> = [];
	var root:Null<Node> = null;
	var stage:Null<Node> = null;
	var opening = false;
	var running = false;
	var from:Null<Rect> = null;
	var to:Null<Rect> = null;
	var at:Null<Rect> = null;
	var r0 = 0.0;
	var r1 = 0.0;
	var since = -1.0;

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

	public function open(path:String)
		begin(path, true);

	public function close(path:String)
		begin(path, false);

	function begin(path:String, opening:Bool) {
		var was = flying.peek() != "" ? at : null;
		this.opening = opening;
		var r = root;
		if (r == null || r.ui == null) {
			fade.set(opening ? 1 : 0);
			shown(fade.value);
			land();
			return;
		}
		fade.animate(-1, opening ? 1 : 0, Clock.reducedMotion ? Curve.REDUCED_FADE : CURVE);
		var e = x.browser.entry(Browser.name(path)), img = e == null ? null : Tiles.cached(x, e);
		var start = was ?? (opening ? tileAt(path) : fileAt(img));
		if (Clock.reducedMotion || e == null || start == null || img == null && !document(path)) land() else {
			from = at = start;
			to = null;
			r0 = radius.peek();
			if (was == null) r0 = opening ? tileRadius(path) : 0;
			r1 = opening ? 0 : tileRadius(path);
			since = -1;
			image(img);
			place(start, r0);
			flying(path);
		}
		if (running) return;
		running = true;
		Clock.addFor(r, step);
	}

	function step(t:Float):Bool {
		fade.sample(t);
		shown(fade.value);
		var path = flying.peek();
		// (stepped to another file meanwhile: no flight)
		if (path != "" && opening && x.viewer.folder.current != path) land();
		path = flying.peek();
		if (path != "") fly(path, t);
		running = fade.moving() || flying.peek() != "";
		return running;
	}

	// (the flight's frame at t: where it goes found, again, or waited for)
	function fly(path:String, t:Float) {
		var goal = opening ? fileAt(image.peek()) : tileAt(path);
		if (since < 0) since = t;
		if (goal == null) {
			if (to == null && t - since > WAIT) land();
			if (to == null) return;
		} else if (to == null || apart(goal, to)) {
			// (from where it is now: nothing jumps)
			from = at;
			r0 = radius.peek();
			to = goal;
			move.set(0);
			move.animate(t, 1, CURVE);
		}
		move.sample(t);
		var k = move.value, a = from, b = to;
		at = {
			x: a.x + (b.x - a.x) * k,
			y: a.y + (b.y - a.y) * k,
			width: a.width + (b.width - a.width) * k,
			height: a.height + (b.height - a.height) * k
		};
		place(at, r0 + (r1 - r0) * k);
		if (!move.moving() && !held(t)) land();
	}

	// (an image still decoding, opened: its thumbnail kept in its place a while)
	function held(t:Float):Bool {
		var v = x.viewer;
		return opening && v.state.peek() == Loading && !decoded() && t - since < HOLD;
	}

	// (the flight over: the tile and the image shown again)
	function land() {
		image(null);
		flying("");
		at = from = to = null;
	}

	function place(r:Rect, corner:Float) {
		var o = root.windowBounds();
		box({x: r.x - o.x, y: r.y - o.y, width: r.width, height: r.height});
		radius(corner);
		// (a document's page into its column: it gives way to it)
		page(1 - fade.value);
	}

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

	// (where the file is shown full size: a decoded image's rect, a PDF's
	// page, a document's column, else the picture fitted to the view)
	function fileAt(img:Null<Image>):Null<Rect> {
		var s = stage;
		if (s == null || s.ui == null || s.width <= 0 || !s.visible()) return null;
		var b = s.windowBounds(), v = x.viewer, name = v.folder.name;
		if (FolderModel.isMarkdown(name)) {
			var w = Math.min(COLUMN, b.width);
			return {x: b.x + (b.width - w) / 2, y: b.y, width: w, height: b.height};
		}
		if (Viewer.isPdf(name)) {
			var p = pageOf(s.parent, b);
			if (p != null) return p;
		} else if (decoded()) return imageAt(s, b);
		var w = img == null ? 1.0 : img.width, h = img == null ? 1.4142 : img.height;
		var k = Math.min(b.width / w, b.height / h);
		// (a thumbnail smaller than its side is the whole image: at its own size)
		if (img != null && img.width < Thumbnails.SIDE && img.height < Thumbnails.SIDE) k = Math.min(k, 1 / s.ui.scale);
		return {x: b.x + (b.width - w * k) / 2, y: b.y + (b.height - h * k) / 2, width: w * k, height: h * k};
	}

	function decoded():Bool {
		var v = x.viewer;
		return v.shown != null && v.shownPath == v.key();
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

	static function apart(a:Rect, b:Rect):Bool
		return Math.abs(a.x - b.x) > 0.5 || Math.abs(a.y - b.y) > 0.5 || Math.abs(a.width - b.width) > 0.5 || Math.abs(a.height - b.height) > 0.5;

	// the picture in flight, over everything in the root
	public static function layer(z:Flight):View
		return <Show when={z.flying() != ""}>
			<view tag="zoom" position="absolute" left={z.box().x} top={z.box().y} width={z.box().width} height={z.box().height} radius={z.radius()}
				overflow="hidden" pointer-events="none">
				<Show when={z.image() != null}><image src={z.image()} width="100%" height="100%" fit="cover"/></Show>
				<Show when={z.image() == null}>
					<view tag="zoom-page" grow={1} radius={z.radius()} background={Look.ref.raised} border-width={1} border-color={Look.ref.edge} opacity={z.page()}/>
				</Show>
			</view>
		</Show>;
}
