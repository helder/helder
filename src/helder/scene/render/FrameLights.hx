package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec3;
import helder.scene.Node;
import helder.scene.World;
import helder.scene.math.MathTools;

// The frame's point, spot and area lights, gathered by the Renderer before its
// passes (gather): the world's shown local lights whose reach (a sphere of
// their range) meets the view, the most important to it first (the
// brightest over their distance beyond their range, as three's and
// Godot's light budgets rank them), at most capacity of them (MAX_LIGHTS,
// 32: a fragment stage's uniforms are 224 vectors in all on GL ES 3.0
// drivers that count blocks' members among them, Android's emulator's;
// or ClusteredLights' maxLights). As numbers, twelve a light (data):
// PbrLights' three vectors (its position and range, its colour times
// intensity and its first shadow tile plus 1, its cone), which the
// renderer writes into PbrLights' block (writeBlock) and ClusteredLights
// into its light data's rows (writeRows); Shadows sets the tiles (tile).
// A draw's list is the eight that reach its bounds most (select: by the
// same ranking, from its bounds' sphere). Nothing is allocated a frame.
class FrameLights {
	// PbrLights' rows
	public static inline var MAX_LIGHTS = 32;
	// a draw's list (PbrObject's lights0 and lights1)
	public static inline var PER_DRAW = 8;
	// floats a light in data
	public static inline var FLOATS = 12;

	// the lights gathered there is room for (MAX_LIGHTS, or more for ClusteredLights)
	public var capacity(default, null) = MAX_LIGHTS;
	// the last gather's
	public var count(default, null) = 0;
	// the lights in the world that the last gather left out (beyond capacity)
	public var dropped(default, null) = 0;
	// the area lights among the gathered (AreaLights' variants drawn when some)
	public var areas(default, null) = 0;
	// the lights, their nodes, in order
	public final lights:Array<Light> = [];
	public final nodes:Array<Node> = [];
	// FLOATS a light: x, y, z, range; r, g, b, tile + 1; the cone (PbrLights')
	public final data:Array<Float> = [];
	// how much each matters to the view (gather's ranking)
	public final score:Array<Float> = [];
	// each one's brightness (its colour's largest channel times its intensity)
	final bright:Array<Float> = [];
	// (the view's planes: a, b, c, d each, normalized)
	final planes:Array<Float> = Filled.floats(24, 0.0);

	public function new() {
		reserve(MAX_LIGHTS);
	}

	// room for n lights (ClusteredLights: its maxLights)
	public function reserve(n:Int) {
		if (n > capacity) capacity = n;
		while (lights.length < capacity) {
			lights.push(null);
			nodes.push(Node.NONE);
			score.push(0);
			bright.push(0);
			for (_ in 0...FLOATS)
				data.push(0);
		}
	}

	// the world's local lights reaching the view (viewProj) seen from eye,
	// ranked, the first capacity kept
	public function gather(world:World, eye:Vec3, viewProj:Mat4) {
		count = 0;
		dropped = 0;
		areas = 0;
		frustum(viewProj);
		var store = world.store(Light.KIND);
		for (k in 0...store.length) {
			var node = store.nodeAt(k), light = store.valueAt(k);
			if (!light.local || light.range <= 0 || light.intensity <= 0 || !node.shown() || !world.inTree(node)) continue;
			var p = node.worldPosition();
			if (!sphereVisible(p.x, p.y, p.z, light.range)) continue;
			var c = light.color;
			var b = Math.max(c.x, Math.max(c.y, c.z)) * light.intensity;
			var dx = p.x - eye.x, dy = p.y - eye.y, dz = p.z - eye.z;
			var beyond = Math.max(Math.sqrt(dx * dx + dy * dy + dz * dz) - light.range, 0);
			var s = b / (1 + beyond * beyond);
			// (its place: after those that matter more; when full, the last one out)
			if (count == capacity) {
				dropped++;
				if (s <= score[count - 1]) continue;
			} else
				count++;
			var at = count - 1;
			while (at > 0 && score[at - 1] < s) {
				move(at - 1, at);
				at--;
			}
			if (light.area) areas++;
			lights[at] = light;
			nodes[at] = node;
			score[at] = s;
			bright[at] = b;
			var o = at * FLOATS;
			data[o] = p.x;
			data[o + 1] = p.y;
			data[o + 2] = p.z;
			data[o + 3] = light.range;
			data[o + 4] = c.x * light.intensity;
			data[o + 5] = c.y * light.intensity;
			data[o + 6] = c.z * light.intensity;
			data[o + 7] = 0;
			if (light.area) {
				// (an area light's row: cone its half width along its x, w its
				// normal (-z) packed, 2^22 past: a point light's cone to the
				// variants without area lights; colour's w -1 less its half
				// height (a rect) or -0.5 (a disc, its radius cone's length))
				var m = node.worldMatrix();
				var x = MathTools.transformDir(m, new Vec3(light.kind == RectArea ? light.width * 0.5 : light.width, 0, 0));
				var nz = MathTools.transformDir(m, new Vec3(0, 0, -1));
				data[o + 7] = light.kind == RectArea ? -1 - light.height * 0.5 * scaleY(m) : -0.5;
				data[o + 8] = x.x;
				data[o + 9] = x.y;
				data[o + 10] = x.z;
				data[o + 11] = packNormal(nz);
			} else if (light.kind == Spot) {
				var d = MathTools.transformDir(node.worldMatrix(), new Vec3(0, 0, -1));
				var len = Math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z);
				var outer = Math.cos(light.outerCone), inner = Math.cos(light.innerCone);
				// (the cone's smoothstep from one dot: (dot - outer) / (inner - outer))
				var scale = 1 / Math.max(inner - outer, 0.0001);
				data[o + 8] = d.x / len * scale;
				data[o + 9] = d.y / len * scale;
				data[o + 10] = d.z / len * scale;
				data[o + 11] = -outer * scale;
			} else {
				data[o + 8] = data[o + 9] = data[o + 10] = 0;
				data[o + 11] = 1;
			}
		}
	}

	// (an area light's height's scale: its node's y axis' length)
	static inline function scaleY(m:Mat4):Float {
		var c = m.c1;
		return Math.sqrt(c.x * c.x + c.y * c.y + c.z * c.z);
	}

	// a direction's octahedral place (Equirect's octahedral) as one float: 2^22
	// plus its u and v each of 2048 steps (exact in a 32-bit float)
	public static function packNormal(d:Vec3):Float {
		var s = Math.abs(d.x) + Math.abs(d.y) + Math.abs(d.z);
		var nx = d.x / s, ny = d.y / s, nz = d.z / s;
		var u = nx, v = nz;
		if (ny < 0) {
			u = (1 - Math.abs(nz)) * (nx >= 0 ? 1 : -1);
			v = (1 - Math.abs(nx)) * (nz >= 0 ? 1 : -1);
		}
		var qu = Math.round((u * 0.5 + 0.5) * 2047), qv = Math.round((v * 0.5 + 0.5) * 2047);
		return 4194304 + qu * 2048 + qv;
	}

	function move(from:Int, to:Int) {
		lights[to] = lights[from];
		nodes[to] = nodes[from];
		score[to] = score[from];
		bright[to] = bright[from];
		for (f in 0...FLOATS)
			data[to * FLOATS + f] = data[from * FLOATS + f];
	}

	// light k's first shadow tile in PbrLights' tiles (-1: unshadowed)
	public inline function setTile(k:Int, tile:Int)
		data[k * FLOATS + 7] = tile + 1;

	public inline function tile(k:Int):Int
		return Std.int(data[k * FLOATS + 7]) - 1;

	// whether light k is a point light (else a spot)
	public inline function isPoint(k:Int):Bool
		return lights[k].kind == Point;

	// light k's place
	public inline function x(k:Int):Float
		return data[k * FLOATS];

	public inline function y(k:Int):Float
		return data[k * FLOATS + 1];

	public inline function z(k:Int):Float
		return data[k * FLOATS + 2];

	public inline function range(k:Int):Float
		return data[k * FLOATS + 3];

	// the eight lights (of the gathered) that reach a sphere most (centre cx,
	// cy, cz, radius r), into out from at: their rows, -1 after the last
	public function select(cx:Float, cy:Float, cz:Float, r:Float, out:Array<Float>, at:Int) {
		for (i in 0...PER_DRAW)
			out[at + i] = -1;
		var n = 0;
		for (k in 0...count) {
			var o = k * FLOATS;
			var dx = data[o] - cx, dy = data[o + 1] - cy, dz = data[o + 2] - cz, range = data[o + 3];
			var d = Math.max(Math.sqrt(dx * dx + dy * dy + dz * dz) - r, 0);
			if (d >= range) continue;
			var q = d / range, w = 1 - q * q * q * q;
			var s = bright[k] * w * w / (d * d + 0.01);
			// (in order, the best first: an insertion into the eight, their scores beside)
			var j = n < PER_DRAW ? n : PER_DRAW;
			while (j > 0 && picked[j - 1] < s) {
				if (j < PER_DRAW) {
					picked[j] = picked[j - 1];
					out[at + j] = out[at + j - 1];
				}
				j--;
			}
			if (j < PER_DRAW) {
				picked[j] = s;
				out[at + j] = k;
				if (n < PER_DRAW) n++;
			}
		}
		// (then by row: the same lights, the same list, summed in the same order)
		for (i in 1...n) {
			var v = out[at + i], j = i - 1;
			while (j >= 0 && out[at + j] > v) {
				out[at + j + 1] = out[at + j];
				j--;
			}
			out[at + j + 1] = v;
		}
	}

	// the first eight, for what has no bounds (an instanced set without)
	public function first(out:Array<Float>, at:Int)
		for (i in 0...PER_DRAW)
			out[at + i] = i < count ? i : -1;

	final picked:Array<Float> = Filled.floats(PER_DRAW, 0.0);

	// PbrLights' block (std140: its three arrays of MAX_LIGHTS vectors one
	// after the other), the first MAX_LIGHTS lights, zeros after
	public function writeBlock(bytes:Bytes) {
		for (k in 0...MAX_LIGHTS)
			for (v in 0...3)
				for (c in 0...4)
					bytes.setFloat((v * MAX_LIGHTS + k) * 16 + c * 4, k < count ? data[k * FLOATS + v * 4 + c] : 0);
	}

	// the light data's rows (ClusteredLights: FLOATS R32F texels a row), the
	// gathered lights', rows of them
	public function writeRows(bytes:Bytes, rows:Int) {
		for (k in 0...rows)
			for (f in 0...FLOATS)
				bytes.setFloat((k * FLOATS + f) * 4, k < count ? data[k * FLOATS + f] : 0);
	}

	// (the view's planes, the gather's)
	inline function frustum(m:Mat4)
		planesOf(m, planes);

	// a view's six planes from viewProj's rows (Gribb and Hartmann's: x and
	// y within -w to w, z within 0 to w), a, b, c, d each, normalized, into out
	public static function planesOf(m:Mat4, planes:Array<Float>) {
		for (i in 0...6) {
			var a = 0.0, b = 0.0, c = 0.0, d = 0.0;
			// (row 3 plus or minus row 0, 1; z: row 2, row 3 less row 2)
			var axis = i >> 1, sign = (i & 1) == 0 ? 1.0 : -1.0;
			if (axis < 2) {
				a = entry(m, 3, 0) + sign * entry(m, axis, 0);
				b = entry(m, 3, 1) + sign * entry(m, axis, 1);
				c = entry(m, 3, 2) + sign * entry(m, axis, 2);
				d = entry(m, 3, 3) + sign * entry(m, axis, 3);
			} else if (sign > 0) {
				a = entry(m, 2, 0);
				b = entry(m, 2, 1);
				c = entry(m, 2, 2);
				d = entry(m, 2, 3);
			} else {
				a = entry(m, 3, 0) - entry(m, 2, 0);
				b = entry(m, 3, 1) - entry(m, 2, 1);
				c = entry(m, 3, 2) - entry(m, 2, 2);
				d = entry(m, 3, 3) - entry(m, 2, 3);
			}
			var len = Math.sqrt(a * a + b * b + c * c);
			if (len == 0) len = 1;
			planes[i * 4] = a / len;
			planes[i * 4 + 1] = b / len;
			planes[i * 4 + 2] = c / len;
			planes[i * 4 + 3] = d / len;
		}
	}

	// a matrix's entry at row r, column k
	public static function entry(m:Mat4, r:Int, k:Int):Float {
		var c = k == 0 ? m.c0 : k == 1 ? m.c1 : k == 2 ? m.c2 : m.c3;
		return r == 0 ? c.x : r == 1 ? c.y : r == 2 ? c.z : c.w;
	}

	// whether a sphere meets the last gather's view (frustum's planes)
	public function sphereVisible(x:Float, y:Float, z:Float, r:Float):Bool {
		for (i in 0...6)
			if (planes[i * 4] * x + planes[i * 4 + 1] * y + planes[i * 4 + 2] * z + planes[i * 4 + 3] < -r) return false;
		return true;
	}
}
