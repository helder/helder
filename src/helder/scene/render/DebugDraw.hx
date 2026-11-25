package helder.scene.render;

import haxe.ds.Vector;
import helder.gfx.Encoder;
import helder.math.Mat4;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.scene.Camera;
import helder.scene.Node;
import helder.scene.math.Aabb;
import helder.scene.math.Curve3;
import helder.scene.math.MathTools;

// Immediate-mode debug drawing (Bevy's gizmos, PlayCanvas' drawLine): a
// frame's calls, from anywhere (a script, the physics step, a loop), are
// written into a ring of segments, drawn by the DebugDraw feature
// (renderer.use(new DebugDraw())) as one draw of lines through the
// renderer's LineRenderer, another for those drawn over everything
// (onTop), then cleared: nothing to keep or remove, and nothing allocated
// a frame. A colour is 0xRRGGBB as a page writes it (shown as written: not
// lit, fogged or tone mapped).
//
//   DebugDraw.line(a, b, 0xFF4040);
//   DebugDraw.aabb(mesh.bounds, 0x40FF40);
//   DebugDraw.onTop = true;               // the calls from here on over everything
//   DebugDraw.axes(player.worldMatrix(), 0.5);
//   DebugDraw.onTop = false;
//
// Debug's calls are these, compiled out of a release build (helder build's
// -D helder.release) unless -D helder.debugdraw: their arguments not
// computed either. The helpers (AxesHelper, GridHelper, BoundsHelper,
// LightHelper, CameraHelper, SkeletonHelper: components of a node) draw
// through them each frame the feature draws.
//
// The ring holds capacity segments (set before the first call): calls past
// it in a frame are dropped (dropped counts them). Several renderers
// drawing in a frame: the first one's DebugDraw takes them.
class DebugDraw implements RenderFeature {
	// the segments a frame holds (before the first call), and those dropped
	// past it (the last frame's)
	public static var capacity = 16384;
	public static var dropped(default, null) = 0;
	// whether the calls from here on are drawn over everything (not depth tested)
	public static var onTop = false;

	// (two rings: depth tested, on top; a segment's a and b, then its colour: 9 floats)
	static inline var FIELDS = 9;
	static var rings:Null<Array<Vector<Float>>> = null;
	static final counts = [0, 0];

	// its lines' width in pixels (2 by default)
	public var width(default, set):Float;
	final tested:Lines;
	final over:Lines;
	var lines:Null<LineRenderer> = null;

	public function new(?options:{?width:Float}) {
		var n = capacity * 2;
		tested = new Lines(n, {segments: true, toneMapped: false, cap: Round});
		over = new Lines(n, {segments: true, toneMapped: false, cap: Round, onTop: true});
		width = options?.width ?? 2.0;
	}

	function set_width(w:Float):Float {
		tested.width = over.width = w;
		return width = w;
	}

	// the renderer's DebugDraw, made and turned on when it has none
	public static function of(renderer:Renderer):DebugDraw {
		var d = Std.downcast(@:privateAccess renderer.debug, DebugDraw);
		if (d != null) return d;
		var made = new DebugDraw();
		renderer.use(made);
		return made;
	}

	public function attach(renderer:Renderer) {
		@:privateAccess renderer.debug = this;
		lines = LineRenderer.of(renderer);
		lines.extras.push(tested);
		lines.extras.push(over);
		lines.before = take;
	}

	// (before the frame's lines: the helpers' calls, then the rings into the lines, cleared)
	function take(enc:Encoder, frame:Renderer.FrameInfo, renderer:Renderer) {
		var world = frame.world;
		if (world != null) {
			var helpers = world.store(Helper.KIND);
			for (k in 0...helpers.length) {
				var node = helpers.nodeAt(k);
				if (!node.shown() || !world.inTree(node)) continue;
				var h:Null<Helper> = helpers.valueAt(k);
				while (h != null) {
					if (h.visible) h.draw(h.ofParent ? node.parent : node, enc, frame, renderer);
					h = h.next;
				}
			}
		}
		fill(tested, 0);
		fill(over, 1);
	}

	function fill(l:Lines, ring:Int) {
		var n = counts[ring];
		l.count = n * 2;
		if (n > 0) {
			var r = rings[ring];
			for (i in 0...n) {
				var o = i * FIELDS;
				l.setPoint(i * 2, r[o], r[o + 1], r[o + 2], r[o + 6], r[o + 7], r[o + 8]);
				l.setPoint(i * 2 + 1, r[o + 3], r[o + 4], r[o + 5], r[o + 6], r[o + 7], r[o + 8]);
			}
		}
		counts[ring] = 0;
	}

	// the segments the last frame drew (both rings)
	public var drawn(get, never):Int;

	function get_drawn():Int
		return (tested.count + over.count) >> 1;

	public function dispose() {
		if (lines == null) return;
		tested.dispose(lines.device);
		over.dispose(lines.device);
	}

	// (a segment into the ring onTop picks)
	static function segment(ax:Float, ay:Float, az:Float, bx:Float, by:Float, bz:Float, color:Int) {
		if (rings == null) rings = [new Vector(capacity * FIELDS), new Vector(capacity * FIELDS)];
		var ring = onTop ? 1 : 0, n = counts[ring];
		if (n >= capacity) {
			dropped++;
			return;
		}
		var r = rings[ring], o = n * FIELDS;
		r[o] = ax;
		r[o + 1] = ay;
		r[o + 2] = az;
		r[o + 3] = bx;
		r[o + 4] = by;
		r[o + 5] = bz;
		// (0xRRGGBB as written: sRGB, into linear light)
		r[o + 6] = linear((color >> 16) & 255);
		r[o + 7] = linear((color >> 8) & 255);
		r[o + 8] = linear(color & 255);
		counts[ring] = n + 1;
	}

	static inline function linear(c:Int):Float
		return Math.pow(c / 255, 2.2);

	// a segment from a to b
	public static function line(a:Vec3, b:Vec3, color = 0xFFFFFF)
		segment(a.x, a.y, a.z, b.x, b.y, b.z, color);

	// from origin along dir for length (dir's length times it), an arrow's head at its end
	public static function ray(origin:Vec3, dir:Vec3, length = 1.0, color = 0xFFFF00) {
		var e = origin + dir * length;
		segment(origin.x, origin.y, origin.z, e.x, e.y, e.z, color);
		arrowHead(e, dir, Math.sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z) * length * 0.12, color);
	}

	// an arrow from a to b
	public static function arrow(a:Vec3, b:Vec3, color = 0xFFFF00) {
		segment(a.x, a.y, a.z, b.x, b.y, b.z, color);
		var d = b - a;
		arrowHead(b, d, Math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z) * 0.12, color);
	}

	static function arrowHead(tip:Vec3, dir:Vec3, size:Float, color:Int) {
		var l = Math.sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z);
		if (l == 0 || size == 0) return;
		var d = dir / l, u = anyPerp(d), v = cross(d, u);
		for (k in 0...4) {
			var a = k * Math.PI / 2;
			var p = tip - d * size + (u * Math.cos(a) + v * Math.sin(a)) * (size * 0.5);
			segment(tip.x, tip.y, tip.z, p.x, p.y, p.z, color);
		}
	}

	// a box's twelve edges (in the world)
	public static function aabb(box:Aabb, color = 0x40FF40)
		if (!box.isEmpty()) boxOf(Mat4.identity(), box.min, box.max, color);

	// the box min to max moved by m (an oriented box: a node's bounds through its world matrix)
	public static function boxOf(m:Mat4, min:Vec3, max:Vec3, color = 0x40FF40) {
		for (k in 0...12) {
			// (an edge: the corner it starts at, the axis it runs along)
			var axis = Std.int(k / 4), c = k % 4;
			var x0 = axis == 0 ? 0 : c & 1, y0 = axis == 1 ? 0 : axis == 0 ? c & 1 : c >> 1, z0 = axis == 2 ? 0 : c >> 1;
			var x1 = axis == 0 ? 1 : x0, y1 = axis == 1 ? 1 : y0, z1 = axis == 2 ? 1 : z0;
			var a = MathTools.transformPoint(m, new Vec3(x0 == 0 ? min.x : max.x, y0 == 0 ? min.y : max.y, z0 == 0 ? min.z : max.z));
			var b = MathTools.transformPoint(m, new Vec3(x1 == 0 ? min.x : max.x, y1 == 0 ? min.y : max.y, z1 == 0 ? min.z : max.z));
			segment(a.x, a.y, a.z, b.x, b.y, b.z, color);
		}
	}

	// a circle about center facing normal
	public static function circle(center:Vec3, normal:Vec3, radius:Float, color = 0xFFFFFF, segments = 32) {
		var l = Math.sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z);
		var n = l > 0 ? normal / l : new Vec3(0, 1, 0), u = anyPerp(n), v = cross(n, u);
		var px = center.x + u.x * radius, py = center.y + u.y * radius, pz = center.z + u.z * radius;
		for (k in 1...segments + 1) {
			var a = k / segments * Math.PI * 2;
			var p = center + (u * Math.cos(a) + v * Math.sin(a)) * radius;
			segment(px, py, pz, p.x, p.y, p.z, color);
			px = p.x;
			py = p.y;
			pz = p.z;
		}
	}

	// a sphere as its three great circles
	public static function sphere(center:Vec3, radius:Float, color = 0x4080FF, segments = 32) {
		circle(center, new Vec3(1, 0, 0), radius, color, segments);
		circle(center, new Vec3(0, 1, 0), radius, color, segments);
		circle(center, new Vec3(0, 0, 1), radius, color, segments);
	}

	// a point's three crossed strokes, size long
	public static function cross3(p:Vec3, size = 0.1, color = 0xFFFFFF) {
		var h = size / 2;
		segment(p.x - h, p.y, p.z, p.x + h, p.y, p.z, color);
		segment(p.x, p.y - h, p.z, p.x, p.y + h, p.z, color);
		segment(p.x, p.y, p.z - h, p.x, p.y, p.z + h, color);
	}

	// a frame's axes from its origin, size long: x red, y green, z blue (a node's: its worldMatrix())
	public static function axes(m:Mat4, size = 1.0) {
		var o = MathTools.transformPoint(m, new Vec3(0, 0, 0));
		for (k in 0...3) {
			var e = MathTools.transformPoint(m, new Vec3(k == 0 ? size : 0, k == 1 ? size : 0, k == 2 ? size : 0));
			segment(o.x, o.y, o.z, e.x, e.y, e.z, k == 0 ? 0xFF3030 : k == 1 ? 0x30FF30 : 0x3080FF);
		}
	}

	// a node's axes (axes of its world matrix)
	public static function axesOf(node:Node, size = 1.0)
		axes(node.worldMatrix(), size);

	// a square grid on the xz plane about center, size wide, of divisions cells a side
	public static function grid(center:Vec3, size = 10.0, divisions = 10, color = 0x808080) {
		var h = size / 2;
		for (k in 0...divisions + 1) {
			var t = -h + size * k / divisions;
			segment(center.x + t, center.y, center.z - h, center.x + t, center.y, center.z + h, color);
			segment(center.x - h, center.y, center.z + t, center.x + h, center.y, center.z + t, color);
		}
	}

	// a camera's view volume (its frustum) at an aspect (width over height)
	public static function frustum(camera:Camera, aspect:Float, color = 0xFFC040) {
		var inv = MathTools.inverse(camera.viewProjection(aspect));
		// (the clip cube's corners, depth 0 to 1, back into the world)
		for (k in 0...12) {
			var axis = Std.int(k / 4), c = k % 4;
			var x0 = axis == 0 ? 0 : c & 1, y0 = axis == 1 ? 0 : axis == 0 ? c & 1 : c >> 1, z0 = axis == 2 ? 0 : c >> 1;
			var x1 = axis == 0 ? 1 : x0, y1 = axis == 1 ? 1 : y0, z1 = axis == 2 ? 1 : z0;
			var a = unproject(inv, x0 * 2 - 1, y0 * 2 - 1, z0), b = unproject(inv, x1 * 2 - 1, y1 * 2 - 1, z1);
			segment(a.x, a.y, a.z, b.x, b.y, b.z, color);
		}
		// (its up: a triangle over the near plane's top)
		var tl = unproject(inv, -0.6, 1.1, 0), tr = unproject(inv, 0.6, 1.1, 0), top = unproject(inv, 0, 1.6, 0);
		segment(tl.x, tl.y, tl.z, top.x, top.y, top.z, color);
		segment(top.x, top.y, top.z, tr.x, tr.y, tr.z, color);
	}

	static function unproject(inv:Mat4, x:Float, y:Float, z:Float):Vec3 {
		var p = inv * new Vec4(x, y, z, 1);
		return new Vec3(p.x / p.w, p.y / p.w, p.z / p.w);
	}

	// a light of a node: a directional one's arrows down its -z, a point
	// light's range, a spot's cone to its range, a hemisphere's two halves;
	// in its colour unless one is given (-1)
	public static function light(node:Node, color = -1) {
		var l = Light.of(node);
		if (l == null) return;
		var c = color >= 0 ? color : rgb(l.color);
		var m = node.worldMatrix(), p = node.worldPosition();
		var down = MathTools.transformDir(m, new Vec3(0, 0, -1)), len = Math.sqrt(down.x * down.x + down.y * down.y + down.z * down.z);
		if (len > 0) down = down / len;
		switch l.kind {
			case Directional:
				var u = anyPerp(down), v = cross(down, u);
				circle(p, down, 0.25, c, 16);
				for (k in 0...4) {
					var a = k * Math.PI / 2, s = p + (u * Math.cos(a) + v * Math.sin(a)) * 0.25;
					ray(s, down, 1, c);
				}
				ray(p, down, 1.2, c);
			case Point:
				sphere(p, l.range, c, 24);
				cross3(p, 0.2, c);
			case Spot:
				var r = l.range * Math.tan(l.outerCone), base = p + down * l.range;
				circle(base, down, r, c, 24);
				var u = anyPerp(down), v = cross(down, u);
				for (k in 0...4) {
					var a = k * Math.PI / 2, e = base + (u * Math.cos(a) + v * Math.sin(a)) * r;
					segment(p.x, p.y, p.z, e.x, e.y, e.z, c);
				}
				if (l.innerCone > 0) circle(p + down * l.range, down, l.range * Math.tan(l.innerCone), c, 24);
			case Hemisphere:
				var up = new Vec3(0, 1, 0);
				circle(p, up, 0.5, rgb(l.color), 24);
				ray(p, up, 0.6, rgb(l.color));
				ray(p, up * -1, 0.6, rgb(l.groundColor));
			case RectArea | DiscArea:
				// (its shape, its facing: down its node's -z)
				var x = MathTools.transformDir(m, new Vec3(1, 0, 0)), y = MathTools.transformDir(m, new Vec3(0, 1, 0));
				if (l.kind == RectArea) {
					var hx = x * (l.width * 0.5), hy = y * (l.height * 0.5);
					var a = p + hx + hy, b = p - hx + hy, d = p - hx - hy, e = p + hx - hy;
					segment(a.x, a.y, a.z, b.x, b.y, b.z, c);
					segment(b.x, b.y, b.z, d.x, d.y, d.z, c);
					segment(d.x, d.y, d.z, e.x, e.y, e.z, c);
					segment(e.x, e.y, e.z, a.x, a.y, a.z, c);
				} else
					circle(p, down, l.width, c, 24);
				ray(p, down, 0.5, c);
		}
	}

	// a skin's bones: each joint to its parent where that is a joint too
	public static function skeleton(skin:Skin, color = 0xFFA0FF)
		bones(skin.joints, color);

	// joints' bones: each joint to its parent where that is one of them too
	public static function bones(joints:Array<Node>, color = 0xFFA0FF) {
		for (j in joints) {
			var parent = j.parent, joined = false;
			for (o in joints)
				if (o == parent) joined = true;
			if (parent.isNone || !joined) {
				cross3(j.worldPosition(), 0.05, color);
				continue;
			}
			var a = parent.worldPosition(), b = j.worldPosition();
			segment(a.x, a.y, a.z, b.x, b.y, b.z, color);
		}
	}

	// a curve as n segments
	public static function path(curve:Curve3, n = 32, color = 0x40E0FF) {
		var p = curve.point(0);
		for (k in 1...n + 1) {
			var q = curve.point(k / n);
			segment(p.x, p.y, p.z, q.x, q.y, q.z, color);
			p = q;
		}
	}

	// (a linear colour as 0xRRGGBB, clamped: a light's)
	static function rgb(c:Vec3):Int {
		var m = Math.max(c.x, Math.max(c.y, Math.max(c.z, 1e-9)));
		var s = m > 1 ? 1 / m : 1.0;
		return (channel(c.x * s) << 16) | (channel(c.y * s) << 8) | channel(c.z * s);
	}

	static inline function channel(x:Float):Int
		return Std.int(Math.round(Math.pow(Math.max(0, x), 1 / 2.2) * 255));

	static inline function cross(a:Vec3, b:Vec3):Vec3
		return new Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);

	// (a unit vector across d)
	static function anyPerp(d:Vec3):Vec3 {
		var a = Math.abs(d.x) < 0.9 ? new Vec3(1, 0, 0) : new Vec3(0, 1, 0);
		var c = cross(d, a), l = Math.sqrt(c.x * c.x + c.y * c.y + c.z * c.z);
		return c / l;
	}
}
