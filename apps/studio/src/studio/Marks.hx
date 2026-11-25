package studio;

import helder.os.Rect;
import helder.syntax.Transaction;
import helder.ui.Clock;
import helder.ui.motion.Curve;
import helder.ui.motion.Track;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import studio.Presence.Peer;
import studio.Project.Source;

// What an agent's work leaves on the canvas, as it happens (Watch draws
// it): the nodes an edit of its made, flashed then outlined (touches); its
// cursor gliding to them; a frame's new image after a build it caused
// revealed behind a scan line (reveals); a new frame rising into place
// (arrivals); "Claude changed pond.helder · Undo" (toast). Times are the
// canvas' clock's (helder.ui.Clock: a headless run's virtual one), stepped
// only while something moves (time). Only agents' edits mark: the user's
// own do not move the canvas.
class Marks {
	// (seconds) a touch's flash and outline, a reveal's scan, a frame's
	// rise, between two frames rising, the toast, a done note shown
	public static inline var TOUCH = 1.8;
	public static inline var REVEAL = 1.0;
	public static inline var ARRIVE = 0.5;
	public static inline var STAGGER = 0.12;
	public static inline var TOAST = 5.0;
	public static inline var DONE = 4.0;
	// the cursor's glide (600 ms, ease in-out)
	static final GLIDE = Curve.tween(0.6, [0.45, 0, 0.2, 1]);

	final studio:Studio;
	// the canvas' clock as last stepped (read through time())
	public final now = signal(0.0);
	public final touches:Signal<Array<Touch>> = signal([]);
	public final reveals:Signal<Array<Reveal>> = signal([]);
	public final arrivals:Signal<Array<Arrival>> = signal([]);
	public final toast:Signal<Null<Toast>> = signal(null);
	// each agent's cursor (its hand) where it is now (world points), for the agents with a frame
	public final cursors:Signal<Array<Hand>> = signal([]);
	// (the truths: a signal's write lands at the event's end)
	var touchList:Array<Touch> = [];
	var revealList:Array<Reveal> = [];
	var arrivalList:Array<Arrival> = [];
	var next = 0;
	var ticking = false;
	// (an agent's last touched box, in its frame's points: where its cursor goes)
	final aims = new Map<String, {screen:String, x:Float, y:Float}>();
	final glides = new Map<String, {x:Track, y:Track, screen:String}>();
	// (an edit's touches waiting for what shows them: a design's next frames,
	// a program's frame after the edit landed: patched or built)
	var waiting:Array<Wait> = [];
	// (an edit of an agent's that is building: the frames drawn after it revealed)
	var building:Null<{colour:String, screens:Array<String>}> = null;
	final drawing = new Map<String, String>();
	// (the screens seen: one new after the first is an arrival)
	var seen:Null<Array<String>> = null;

	public function new(studio)
		this.studio = studio;

	// the clock, for a view that moves with it (stepped while one does)
	public function time():Float {
		wake();
		return now();
	}

	// an agent's edit of file (its history entry's: tx against the text
	// before): the elements it made outlined where they show, its cursor
	// there, the toast; its frames revealed when a build follows (landed)
	public function edited(peer:Peer, file:String, tx:Transaction) {
		var p = studio.project;
		if (p == null) return;
		var doc = studio.docs.get(file).doc, starts = [];
		for (c in tx.inverse.changes) {
			var held = doc.elementHolding(c.start);
			if (held != null && !starts.contains(held.start)) starts.push(held.start);
			for (e in doc.elements())
				if (e.start > c.start && e.start <= c.end && !starts.contains(e.start)) starts.push(e.start);
		}
		var name = p.dir.length < file.length ? file.substr(p.dir.length + 1) : file;
		toast({by: peer.name, colour: peer.colour, file: name, entry: studio.docs.nextUndo(), at: Clock.now});
		var shown = studio.layout.inView();
		var w:Wait = {peer: peer.id, colour: peer.colour, file: file, starts: starts, designs: [], live: [], frame: studio.frames, landed: false};
		for (s in p.screens)
			if (s.file == file && s.source.match(Design(_)) && shown.contains(s.name)) w.designs.push(s.name);
		if (studio.previews != null)
			for (s in studio.previews.screens)
				if (shown.contains(s.info.name)) w.live.push(s.info.name);
		if (starts.length > 0) waiting.push(w);
		building = {colour: peer.colour, screens: w.live};
		wake();
	}

	// the edit told to the program: patched (its next frames show it), or
	// built (ok: the frames drawn next are the new build's, revealed)
	public function landed(built:Bool, ok = true) {
		for (w in waiting)
			w.landed = true;
		var b = building;
		building = null;
		if (built && ok && b != null)
			for (s in b.screens)
				drawing.set(s, b.colour);
	}

	// a screen's new frame (Studio.framed): its reveal started, the touches waiting for it found in its tree
	public function framed(name:String) {
		var colour = drawing.get(name);
		if (colour != null) {
			drawing.remove(name);
			reveals(revealList = revealList.filter(r -> r.screen != name).concat([{screen: name, colour: colour, at: Clock.now}]));
			wake();
		}
		for (w in waiting.copy())
			if (w.landed && w.live.contains(name)) {
				w.live.remove(name);
				find(w, name);
				if (w.live.length == 0 && w.designs.length == 0) waiting.remove(w);
			}
	}

	// the project's screens now: those new since the last (not the first time) rise into place, a stagger apart
	public function saw(names:Array<String>) {
		var was = seen;
		seen = names.copy();
		if (was == null) return;
		var t = Clock.now, k = 0;
		var fresh = [for (n in names) if (!was.contains(n)) {screen: n, at: t + STAGGER * k++}];
		if (fresh.length == 0) return;
		arrivals(arrivalList = arrivalList.concat(fresh));
		wake();
	}

	// (a program's screen's tree asked: the nodes whose markup the edit made)
	function find(w:Wait, name:String) {
		var pr = studio.previews, p = studio.project, s = pr?.screen(name);
		if (s == null) return;
		var doc = studio.docs.get(w.file).doc;
		pr.request(s, "Ui.getTree", {}, t -> {
			var found:Array<Rect> = [];
			function walk(n:Dynamic) {
				if (n == null) return;
				var at:Null<Array<Dynamic>> = n.source?.offsets;
				if (at != null && at.length > 0 && p.real(n.source.file) == w.file && w.starts.contains(doc.fromByte(Std.int(at[0]))))
					found.push({x: (n.x : Float), y: (n.y : Float), width: (n.width : Float), height: (n.height : Float)});
				for (c in (n.children : Array<Dynamic>) ?? []) walk(c);
			}
			walk(Studio.rootOf(t));
			add(w, name, found);
		});
	}

	// (flashed now, outlined, then let go; the agent's cursor to the first)
	function add(w:Wait, screen:String, found:Array<Rect>) {
		if (found.length == 0) return;
		var t = Clock.now;
		var made:Array<Touch> = [for (b in found.slice(0, 24)) {id: next++, colour: w.colour, screen: screen, x: b.x, y: b.y, w: b.width, h: b.height, at: t}];
		touches(touchList = touchList.concat(made));
		var b = found[0];
		aims.set(w.peer, {screen: screen, x: b.x + Math.min(b.width * 0.6, 48), y: b.y + Math.min(b.height * 0.6, 24)});
		wake();
	}

	function wake() {
		if (ticking) return;
		ticking = true;
		Clock.add(step);
	}

	// (each frame while something moves: the clock, what ended let go, the cursors moved)
	function step(t:Float):Bool {
		now(t);
		if (touchList.length > 0 && Lambda.exists(touchList, x -> t - x.at > TOUCH)) touches(touchList = touchList.filter(x -> t - x.at <= TOUCH));
		if (revealList.length > 0 && Lambda.exists(revealList, x -> t - x.at > REVEAL)) reveals(revealList = revealList.filter(x -> t - x.at <= REVEAL));
		if (arrivalList.length > 0 && Lambda.exists(arrivalList, x -> t - x.at > ARRIVE)) arrivals(arrivalList = arrivalList.filter(x -> t - x.at <= ARRIVE));
		var tst = toast.peek();
		if (tst != null && t - tst.at > TOAST) toast(null);
		// (a design's touches: its frame drawn again with the edit, two of the studio's frames on)
		for (w in waiting.copy())
			if (w.designs.length > 0 && studio.frames >= w.frame + 2) {
				for (n in w.designs)
					add(w, n, [for (x in studio.designs.nodesAt(n, w.starts)) {var b = studio.designs.box(n, x); {x: b.x, y: b.y, width: b.width, height: b.height};}]);
				w.designs = [];
				if (w.live.length == 0) waiting.remove(w);
			}
		var moving = glide(t);
		ticking = moving || touchList.length > 0 || revealList.length > 0 || arrivalList.length > 0 || toast.peek() != null || waiting.length > 0 || busy();
		return ticking;
	}

	// (the cursors aimed: at an agent's last touch on its frame, else its
	// frame's caption; gliding there; whether one moves)
	function glide(t:Float):Bool {
		var out:Array<Hand> = [], moving = false;
		for (p in studio.presence.list()) {
			var s = p.screen ?? aims.get(p.id)?.screen;
			var r = s == null ? null : studio.layout.rect(s);
			if (r == null) continue;
			var aim = aims.get(p.id);
			var x = r.x + (aim != null && aim.screen == s ? aim.x : 24), y = r.y + (aim != null && aim.screen == s ? aim.y : -8);
			var g = glides.get(p.id);
			if (g == null) {
				g = {x: new Track(x, 0.05), y: new Track(y, 0.05), screen: s};
				glides.set(p.id, g);
			} else if (g.x.target != x || g.y.target != y) {
				g.x.animate(t, x, GLIDE);
				g.y.animate(t, y, GLIDE);
			}
			g.x.sample(t);
			g.y.sample(t);
			if (g.x.kind != Track.REST || g.y.kind != Track.REST) moving = true;
			out.push({peer: p.id, name: p.name, colour: p.colour, screen: s, x: g.x.value, y: g.y.value, working: p.working});
		}
		for (k in [for (k in glides.keys()) k])
			if (studio.presence.peer(k) == null) glides.remove(k);
		if (!same(out, cursors.peek())) cursors(out);
		return moving;
	}

	static function same(a:Array<Hand>, b:Array<Hand>):Bool {
		if (a.length != b.length) return false;
		for (k in 0...a.length)
			if (a[k].peer != b[k].peer || a[k].x != b[k].x || a[k].y != b[k].y || a[k].working != b[k].working || a[k].screen != b[k].screen) return false;
		return true;
	}

	// (what loops while it is on: an agent at work (its halo), a done note
	// shown, a frame not drawn yet (its shimmer))
	function busy():Bool {
		var pr = studio.presence, at = pr.now();
		if (Lambda.exists(pr.list(), p -> p.working || (p.doneAt > 0 && at - p.doneAt < DONE))) return true;
		var pv = studio.previews;
		return pv != null && Lambda.exists(pv.screens, s -> s.version == 0 && !s.crashed);
	}
}

typedef Touch = {id:Int, colour:String, screen:String, x:Float, y:Float, w:Float, h:Float, at:Float};
typedef Reveal = {screen:String, colour:String, at:Float};
typedef Arrival = {screen:String, at:Float};
typedef Toast = {by:String, colour:String, file:String, entry:Null<Docs.Entry>, at:Float};
typedef Hand = {peer:String, name:String, colour:String, screen:String, x:Float, y:Float, working:Bool};
private typedef Wait = {peer:String, colour:String, file:String, starts:Array<Int>, designs:Array<String>, live:Array<String>, frame:Int, landed:Bool};
