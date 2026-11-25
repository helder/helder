package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.Buffer;
import helder.scene.Node;

// Lines with a width (three's Line2 and LineMaterial, Babylon's
// GreasedLine): a polyline through its points, or separate segments (a
// pair of points each), drawn by LineRenderer (renderer.use(new
// LineRenderer(device))) as quads on the screen, so a width is the same on
// every back end (gfx's Lines topology is 1 px, and WebGL ignores widths):
//
//   width        in pixels (widthUnits Pixels, the default) or in the
//                world's units (World: thinner far off, as geometry is)
//   join         where segments meet: Miter (Bevel past 4 half widths),
//                Round or Bevel
//   cap          the line's ends: Butt, Round or Square
//   dash, gap    a dashed line (lengths in the line's own units along it;
//                0: solid), dashOffset moving the dashes along (animated:
//                a marching line)
//   onTop        drawn over everything (not depth tested), after the
//                scene; else depth tested against it
//   transparent  blended by its colours' alpha, after the see-through
//                surfaces (not written to depth)
//   toneMapped   false: its colours as they are into an 8-bit target (a
//                debug colour's pure red), not tone mapped
//
// A point is a position in the node's frame (Lines.attach) and a colour
// (linear rgb and alpha, blended along a segment). The program writes
// them into the line's flat data, as InstancedMesh takes its instances:
// nothing is allocated a frame, and the line renderer uploads the points
// once they changed (one writeBuffer; its GPU copy made when first drawn,
// so lines themselves link no device).
//
//   var path = new Lines(512, {width: 6, join: Round, dash: 0.2, gap: 0.15});
//   Lines.attach(world.node("aim"), path);
//   // each frame:
//   path.count = n;
//   for (i in 0...n) path.setPoint(i, xs[i], ys[i], zs[i], 1, 1, 1, fade(i));
class Lines {
	@:noCompletion public static final KIND = new StoreKind<Lines>("lines");
	// the triangles of a join's or a round cap's fan
	@:noCompletion public static inline var FAN = 8;
	// (a point as kept: x, y, z, r, g, b, a; as uploaded: x, y, z, its
	// distance along, r, g, b, a: 32 bytes)
	static inline var FIELDS = 7;
	@:noCompletion public static inline var RECORD = 32;

	public final capacity:Int;
	// separate segments (points 2k and 2k + 1), not a polyline
	public final segments:Bool;
	// the points drawn (0 to capacity; a polyline's segments count - 1, closed's count)
	public var count(default, set):Int;
	public var width:Float;
	public var widthUnits:LineUnits;
	public var join:LineJoin;
	public var cap:LineCap;
	public var dash:Float;
	public var gap:Float;
	public var dashOffset:Float;
	// a polyline's last point joined back to its first
	public var closed:Bool;
	public var onTop:Bool;
	public var transparent:Bool;
	public var toneMapped:Bool;
	public var visible = true;

	final points:haxe.ds.Vector<Float>;
	// (the upload: a polyline's points with its neighbours' padding)
	final records:Bytes;
	// its GPU copy, LineRenderer's (made when first drawn: Buffer.NONE before)
	public var buffer(default, null):Buffer = Buffer.NONE;
	// (the records changed since the renderer's last upload)
	var dirty = true;
	@:allow(helder.scene.render.LineRenderer) var stale = true;
	// (the records written: a polyline's count + 2 or + 3, segments' count)
	@:allow(helder.scene.render.LineRenderer) var written = 0;

	// capacity points (count of them drawn: none by default)
	public function new(capacity:Int, ?options:LinesOptions) {
		this.capacity = capacity;
		segments = options?.segments ?? false;
		width = options?.width ?? 2.0;
		widthUnits = options?.widthUnits ?? Pixels;
		join = options?.join ?? Miter;
		cap = options?.cap ?? Butt;
		dash = options?.dash ?? 0.0;
		gap = options?.gap ?? 0.0;
		dashOffset = options?.dashOffset ?? 0.0;
		closed = options?.closed ?? false;
		onTop = options?.onTop ?? false;
		transparent = options?.transparent ?? false;
		toneMapped = options?.toneMapped ?? true;
		points = new haxe.ds.Vector(capacity * FIELDS);
		for (i in 0...capacity)
			for (k in 0...FIELDS)
				points[i * FIELDS + k] = k >= 3 ? 1 : 0;
		records = Bytes.alloc((capacity + 3) * RECORD);
		count = options?.count ?? 0;
	}

	public static inline function attach(node:Node, lines:Lines):Lines
		return node.world.store(KIND).set(node, lines);

	public static inline function of(node:Node):Null<Lines>
		return node.world.store(KIND).get(node);

	public static inline function detach(node:Node)
		node.world.store(KIND).remove(node);

	function set_count(n:Int):Int {
		if (n < 0 || n > capacity) throw 'helder.scene: Lines count $n outside 0...$capacity';
		dirty = true;
		return count = n;
	}

	// point i at x, y, z (the node's frame), of the linear colour r, g, b and alpha a
	public function setPoint(i:Int, x:Float, y:Float, z:Float, r = 1.0, g = 1.0, b = 1.0, a = 1.0) {
		var o = i * FIELDS;
		points[o] = x;
		points[o + 1] = y;
		points[o + 2] = z;
		points[o + 3] = r;
		points[o + 4] = g;
		points[o + 5] = b;
		points[o + 6] = a;
		dirty = true;
	}

	public function setPosition(i:Int, x:Float, y:Float, z:Float) {
		var o = i * FIELDS;
		points[o] = x;
		points[o + 1] = y;
		points[o + 2] = z;
		dirty = true;
	}

	public function setColor(i:Int, r:Float, g:Float, b:Float, a = 1.0) {
		var o = i * FIELDS;
		points[o + 3] = r;
		points[o + 4] = g;
		points[o + 5] = b;
		points[o + 6] = a;
		dirty = true;
	}

	// point i's field: 0 to 2 its position, 3 to 6 its colour
	public inline function get(i:Int, field:Int):Float
		return points[i * FIELDS + field];

	// the segments drawn (instances of LineRenderer's draw)
	public var drawn(get, never):Int;

	function get_drawn():Int
		return segments ? count >> 1 : count < 2 ? 0 : closed ? count : count - 1;

	// the records as uploaded (the point buffer's bytes: tests)
	public var data(get, never):Bytes;

	inline function get_data():Bytes
		return records;

	// the records made from the points, when they changed (the renderer
	// uploads them after: their bytes, data)
	public function prepare() {
		if (!dirty) return;
		dirty = false;
		stale = true;
		var at = 0;
		if (segments) {
			for (i in 0...(count >> 1) * 2) {
				// (each segment's distances from its own start)
				var d = (i & 1) == 0 ? 0.0 : span(i - 1, i);
				record(at++, i, d);
			}
		} else if (count > 0) {
			var total = 0.0;
			// (open: the first and the last again, as neighbours none; closed:
			// the last before the first, the first two after the last)
			record(at++, closed ? count - 1 : 0, 0);
			for (i in 0...count) {
				if (i > 0) total += span(i - 1, i);
				record(at++, i, total);
			}
			if (closed) {
				total += span(count - 1, 0);
				record(at++, 0, total);
				record(at++, count > 1 ? 1 : 0, total + span(0, count > 1 ? 1 : 0));
			} else
				record(at++, count - 1, total);
		}
		written = at;
	}

	inline function span(i:Int, j:Int):Float {
		var a = i * FIELDS, b = j * FIELDS;
		var dx = points[b] - points[a], dy = points[b + 1] - points[a + 1], dz = points[b + 2] - points[a + 2];
		return Math.sqrt(dx * dx + dy * dy + dz * dz);
	}

	inline function record(at:Int, i:Int, d:Float) {
		var o = at * RECORD, p = i * FIELDS;
		records.setFloat(o, points[p]);
		records.setFloat(o + 4, points[p + 1]);
		records.setFloat(o + 8, points[p + 2]);
		records.setFloat(o + 12, d);
		records.setFloat(o + 16, points[p + 3]);
		records.setFloat(o + 20, points[p + 4]);
		records.setFloat(o + 24, points[p + 5]);
		records.setFloat(o + 28, points[p + 6]);
	}

	// its GPU copy let go (made again if drawn again)
	public function dispose(device:helder.gfx.Device) {
		if (buffer != Buffer.NONE) device.destroyBuffer(buffer);
		buffer = Buffer.NONE;
		stale = true;
	}

	@:allow(helder.scene.render.LineRenderer) function upload(device:helder.gfx.Device) {
		if (!stale) return;
		stale = false;
		if (buffer == Buffer.NONE) buffer = device.createBuffer({size: records.length, usage: Vertex});
		if (written > 0) device.writeBuffer(buffer, 0, records, 0, written * RECORD);
	}
}

// a line's width: in pixels on the screen, or in the world's units
enum abstract LineUnits(Int) to Int {
	var Pixels;
	var World;
}

// where a polyline's segments meet
enum abstract LineJoin(Int) to Int {
	var Miter;
	var Round;
	var Bevel;
}

// a line's ends
enum abstract LineCap(Int) to Int {
	var Butt;
	var Round;
	var Square;
}

// what Lines are made with (each optional): 2 pixels wide, mitred, butt
// ends, solid, depth tested, opaque, tone mapped, none drawn
typedef LinesOptions = {
	?segments:Bool,
	?width:Float,
	?widthUnits:LineUnits,
	?join:LineJoin,
	?cap:LineCap,
	?dash:Float,
	?gap:Float,
	?dashOffset:Float,
	?closed:Bool,
	?onTop:Bool,
	?transparent:Bool,
	?toneMapped:Bool,
	?count:Int
}
