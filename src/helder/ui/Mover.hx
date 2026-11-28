package helder.ui;

import helder.canvas.Matrix;
import helder.ui.box.Len.Lens;
import helder.ui.motion.Track;

// A node whose transform and opacity the compositor moves between the
// program's frames (Layers' step 4b, helder.ui.layers.Compositor): one with a
// layer of its own (its transform or opacity moving: a transition, a
// spring, a tween, its presence), or a sticky node in a scroller. Taken on
// the program's thread as its frame is drawn (of): each part of its
// transform and opacity as a closed form of the time (a Track's segment,
// copied), a sticky node's insets; sampled on the
// compositor's thread at any time and scroll offset (sample) the way
// Node.transformMatrix and Ui's paint sample them, so that the two agree at
// every time. A part whose start is not known yet (its first tick to come)
// stays where it is, as the program's does until that tick. Its layout
// moving (its edges' tracks) is not the compositor's: the program's alone.
@:access(helder.ui.Node)
class Mover {
	public final node:Node;
	// the transform and opacity it was drawn with (the program's frame's: null, none)
	public final drawn:Null<Matrix>;
	public final opacity:Float;
	// (where and how big it is drawn, its transform's origin (NaN: the centre))
	final x:Float;
	final y:Float;
	final w:Float;
	final h:Float;
	final ox:Float;
	final oy:Float;
	// (the style's transform)
	final transform:Null<Transform>;
	// (the opacity: as it is, or a track)
	final alpha:Float;
	var aTrack:Null<Track> = null;
	// (its presence and transform's lanes, copied; reduced motion then)
	var presence:Null<Track> = null;
	var effect = helder.ui.motion.Presence.FADE;
	var lanes:Null<Array<Track>> = null;
	final reduced:Bool;
	// (a sticky node's: per axis its place, size, its scroller's view less
	// the scroll, its parent's content box, its insets (NaN: none))
	public final sticky:Bool;
	public final scroller:Null<Node>;
	final stick:Array<Float> = [];
	// whether its opacity is a group's (more than one thing of it drawn: Ui's
	// paint), the compositor fading it whole
	public var grouped = false;
	// when it moves no more on its own (seconds, Ui.now's clock): its runs and tracks ended
	public var until(default, null) = -1e9;

	function new(n:Node, drawn:Null<Matrix>, opacity:Float) {
		node = n;
		this.drawn = drawn == null ? null : drawn.clone();
		this.opacity = opacity;
		var s = n.used, pr = n.props(), p = n.present;
		x = n.absX;
		y = n.absY;
		w = p != null ? p.width() : n.width;
		h = p != null ? p.height() : n.height;
		var o = pr.transformOrigin;
		ox = o == null ? Math.NaN : o[0].resolve(w);
		oy = o == null ? Math.NaN : o[1].resolve(h);
		transform = pr.transform;
		alpha = s.opacity;
		reduced = Clock.reducedMotion;
		if (p != null) {
			if (p.opacity != null && p.opacity.moving()) aTrack = track(p.opacity);
			if (p.presence != null) {
				presence = track(p.presence);
				effect = p.effect;
			}
			if (p.tx != null) lanes = [for (t in [p.tx, p.ty, p.sx, p.sy, p.rot]) track(t)];
		}
		sticky = s.position == "sticky";
		var sc = n.parent;
		while (sc != null && !sc.used.scrolls)
			sc = sc.parent;
		scroller = sticky ? sc : null;
		if (sticky) insets(n, sc);
	}

	// (a copy of t; a pending one stays where it is)
	function track(t:Track):Track {
		var c = t.copy();
		if (c.moving() && !c.pending()) until = Math.max(until, c.end);
		return c;
	}

	// n as the compositor may move it (drawn with transform m, its opacity
	// as drawn: Ui's paint takes those with a layer of their own and sticky
	// ones), or null: not one (flying, leaving, its layout moving)
	public static function of(n:Node, m:Null<Matrix>, opacity:Float):Null<Mover> {
		var p = n.present;
		if (p != null && (p.flying || p.away || p.exiting || p.l != null && (p.l.moving() || p.t.moving() || p.r.moving() || p.b.moving())))
			return null;
		return new Mover(n, m, opacity);
	}

	// whether its opacity may be other than 1 (faded, or moving)
	public function fades():Bool
		return opacity < 1 || aTrack != null || presence != null;

	// whether it moves with the time or a scroll at all
	public function moves():Bool
		return until > -1e9 || scroller != null;

	// (CSS's sticky as Node.stickyOffset has it: per axis its place, size,
	// its scroller's content box less the scroll, its parent's content box
	// (its margins inside), its insets)
	function insets(n:Node, sc:Null<Node>) {
		var p = n.parent, s = n.used, m = s.margin;
		for (axis in 0...2) {
			var x = axis == 0;
			var v0 = 0.0, v1 = n.ui == null ? 1e9 : x ? n.ui.width : n.ui.height;
			if (sc != null) {
				var ss = sc.used, be = ss.borderEdges, pad = ss.paddingEdges;
				v0 = x ? sc.absX + be.left + pad.left : sc.absY + be.top + pad.top;
				v1 = x ? sc.absX + sc.width - be.right - pad.right : sc.absY + sc.height - be.bottom - pad.bottom;
			}
			var c0 = 0.0, c1 = 0.0;
			if (p != null) {
				var ps = p.used, pbe = ps.borderEdges, ppad = ps.paddingEdges;
				// (an auto margin: 0)
				var m0 = Lens.resolve(m[x ? 3 : 0], Math.NaN, 0), m1 = Lens.resolve(m[x ? 1 : 2], Math.NaN, 0);
				c0 = (x ? p.absX + pbe.left + ppad.left : p.absY + pbe.top + ppad.top) + m0;
				c1 = (x ? p.absX + p.width - pbe.right - ppad.right : p.absY + p.height - pbe.bottom - ppad.bottom) - m1;
			}
			for (v in [x ? n.absX : n.absY, x ? n.width : n.height, v0, v1, c0, c1, Lens.resolve(s.inset(x ? 3 : 0), v1 - v0, Math.NaN),
				Lens.resolve(s.inset(x ? 1 : 2), v1 - v0, Math.NaN), p == null ? 0 : 1])
				stick.push(v);
		}
	}

	// (its sticky move along an axis at its scroller's offset there)
	function stuck(axis:Int, scroll:Float):Float {
		var k = axis * 9, a = stick;
		if (a[k + 8] == 0) return 0;
		var pos = a[k], size = a[k + 1], v0 = a[k + 2] + scroll, v1 = a[k + 3] + scroll, c0 = a[k + 4], c1 = a[k + 5];
		var start = a[k + 6], end = a[k + 7], d = 0.0;
		if (!Math.isNaN(start) && pos + d < v0 + start) d = Math.min(v0 + start - pos, Math.max(0, c1 - (pos + size)));
		if (!Math.isNaN(end) && pos + d + size > v1 - end) d = Math.max(v1 - end - (pos + size), Math.min(0, c0 - pos));
		return d;
	}

	// its transform at time t, its scroller at sx, sy, into out (identity:
	// none); its opacity then (its presence's share in it)
	public function sample(t:Float, sx:Float, sy:Float, out:Matrix):Float {
		var a = alpha;
		if (aTrack != null) {
			if (aTrack.moving() && !aTrack.pending()) aTrack.sample(t);
			a = aTrack.value;
		}
		var pr = presence;
		if (pr != null && pr.moving() && !pr.pending()) pr.sample(t);
		var l = lanes;
		if (l != null) {
			for (k in l)
				if (k.moving() && !k.pending()) k.sample(t);
			// (settled: the style's transform again, as Motions lets the lanes go)
			if (!l[0].moving() && !l[1].moving() && !l[2].moving() && !l[3].moving() && !l[4].moving()) l = lanes = null;
		}
		var tf = transform;
		var stx = 0.0, sty = 0.0;
		if (sticky) {
			stx = stuck(0, sx);
			sty = stuck(1, sy);
		}
		var shown = pr == null ? 1.0 : Math.max(0, Math.min(1, pr.value));
		var grows = pr != null && pr.value < 1 && (effect.scale != 1 || effect.dx != 0 || effect.dy != 0) && !reduced;
		// (Node.transformMatrix's, with Present.matrix's)
		if (l != null || grows) {
			out.identity();
			if (l != null) {
				out.translate(l[0].value, l[1].value);
				out.rotate(l[4].value);
				out.scale(l[2].value, l[3].value);
			} else if (tf != null && !tf.isIdentity()) out.copyFrom(tf.toMatrix(w, h));
			if (pr != null && pr.value < 1 && !reduced) {
				var k = 1 - shown, s = 1 + (effect.scale - 1) * k;
				out.premultiply(new Matrix(s, 0, 0, s, effect.dx * k, effect.dy * k));
			}
			var cx = x + (Math.isNaN(ox) ? w / 2 : ox), cy = y + (Math.isNaN(oy) ? h / 2 : oy);
			out.e += cx - (out.a * cx + out.c * cy) + stx;
			out.f += cy - (out.b * cx + out.d * cy) + sty;
		} else if (tf == null || tf.isIdentity()) {
			out.set(1, 0, 0, 1, stx, sty);
		} else {
			out.copyFrom(tf.toMatrix(w, h));
			var cx = x + (Math.isNaN(ox) ? w / 2 : ox), cy = y + (Math.isNaN(oy) ? h / 2 : oy);
			out.e += cx - (out.a * cx + out.c * cy) + stx;
			out.f += cy - (out.b * cx + out.d * cy) + sty;
		}
		return a * shown;
	}
}
