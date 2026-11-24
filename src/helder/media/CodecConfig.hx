package helder.media;

import haxe.io.Bytes;

// What the systems' decoders need of a track's config (MediaTrack.config):
// avcC's and hvcC's NAL length size and parameter sets (as Annex B: each
// after a start code), the depth (hvcC's, vpcC's, av1C's; H.264 High 10's)
class CodecConfig {
	// (avcC's NAL length size, hvcC's; 0: none, the packets as they are)
	public static function lengths(t:MediaTrack):Int {
		var c = t.config;
		return c == null ? 0 : switch t.codec {
			case H264 if (c.length > 4): (c.get(4) & 3) + 1;
			case Hevc if (c.length > 21): (c.get(21) & 3) + 1;
			case _: 0;
		}
	}

	// bits a sample
	public static function depth(t:MediaTrack):Int {
		var c = t.config;
		if (c == null) return 8;
		return switch t.codec {
			case Hevc if (c.length > 17): (c.get(17) & 7) + 8;
			case Vp9 if (c.length > 6): c.get(6) >> 4;
			case Av1 if (c.length > 2): c.get(2) & 0x40 != 0 ? 10 : 8;
			case H264 if (c.length > 1): c.get(1) == 110 ? 10 : 8;
			case _: 8;
		}
	}

	// avcC's SPS and PPS (the first, the second), hvcC's VPS, SPS and PPS
	// all in the first: each after a start code; null: none
	public static function sets(t:MediaTrack):Null<Array<Bytes>> {
		var c = t.config;
		if (c == null || (t.codec != H264 && t.codec != Hevc)) return null;
		var lists = [new haxe.io.BytesBuffer(), new haxe.io.BytesBuffer()];
		function add(to:haxe.io.BytesBuffer, at:Int, size:Int) {
			for (b in [0, 0, 0, 1]) to.addByte(b);
			to.addBytes(c, at, size);
		}
		try {
			if (t.codec == H264) {
				var at = 5;
				for (kind in 0...2) {
					var n = c.get(at++) & (kind == 0 ? 31 : 255);
					for (_ in 0...n) {
						var size = c.get(at) << 8 | c.get(at + 1);
						add(lists[kind], at + 2, size);
						at += 2 + size;
					}
				}
			} else {
				var at = 23;
				for (_ in 0...c.get(22)) {
					var n = c.get(at + 1) << 8 | c.get(at + 2);
					at += 3;
					for (_ in 0...n) {
						var size = c.get(at) << 8 | c.get(at + 1);
						add(lists[0], at + 2, size);
						at += 2 + size;
					}
				}
			}
		} catch (_:Dynamic) return null;
		return [lists[0].getBytes(), lists[1].getBytes()];
	}

	// a packet's NAL units with start codes for their lengths (Annex B), n the length size
	public static function annexB(b:Bytes, n:Int):Bytes {
		if (n == 0) return b;
		var out = new haxe.io.BytesBuffer(), i = 0;
		while (i + n <= b.length) {
			var size = 0;
			for (k in 0...n) size = size << 8 | b.get(i + k);
			i += n;
			if (size > b.length - i) size = b.length - i;
			for (x in [0, 0, 0, 1]) out.addByte(x);
			out.addBytes(b, i, size);
			i += size;
		}
		return out.getBytes();
	}

	// the colours an H.264's or HEVC's SPS names in its VUI (avcC's, hvcC's):
	// its matrix ("601", "709", "2020") and range, as ffmpeg reads them
	// (unnamed: BT.601); null where the stream names none (no VUI, no
	// colour description) or it cannot be read. For a system decoder that
	// does not say them (Media Foundation's HEVC: BT.2020 read as 601)
	public static function colours(t:MediaTrack):Null<{matrix:String, full:Bool}> {
		var c = t.config;
		if (c == null) return null;
		return try switch t.codec {
			case H264: avc(c);
			case Hevc: hevc(c);
			case _: null;
		} catch (_:Dynamic) null;
	}

	static function named(m:Int, full:Bool):{matrix:String, full:Bool}
		return {matrix: m == 1 ? "709" : m == 9 || m == 10 ? "2020" : "601", full: full};

	// (avcC's first SPS: to its VUI)
	static function avc(c:Bytes):Null<{matrix:String, full:Bool}> {
		if (c.length < 8 || c.get(5) & 31 == 0) return null;
		var size = c.get(6) << 8 | c.get(7);
		if (8 + size > c.length) return null;
		var r = new Rbsp(c, 9, size - 1), profile = c.get(9);
		r.u(24);
		r.ue();
		if ([100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135].indexOf(profile) >= 0) {
			if (r.ue() == 3) r.u(1);
			r.ue();
			r.ue();
			r.u(1);
			if (r.u(1) == 1) for (i in 0...8) if (r.u(1) == 1) list(r, i < 6 ? 16 : 64);
		}
		r.ue();
		var poc = r.ue();
		if (poc == 0) r.ue() else if (poc == 1) {
			r.u(1);
			r.se();
			r.se();
			for (_ in 0...r.ue()) r.se();
		}
		r.ue();
		r.u(1);
		r.ue();
		r.ue();
		if (r.u(1) == 0) r.u(1);
		r.u(1);
		if (r.u(1) == 1) for (_ in 0...4) r.ue();
		if (r.u(1) == 0) return null;
		return signal(r);
	}

	static function list(r:Rbsp, n:Int) {
		var last = 8, next = 8;
		for (_ in 0...n) {
			if (next != 0) next = (last + r.se() + 256) % 256;
			if (next != 0) last = next;
		}
	}

	// (a VUI's aspect ratio and overscan passed, then its video signal type: H.264's and HEVC's alike)
	static function signal(r:Rbsp):Null<{matrix:String, full:Bool}> {
		if (r.u(1) == 1 && r.u(8) == 255) r.u(32);
		if (r.u(1) == 1) r.u(1);
		if (r.u(1) == 0) return null;
		r.u(3);
		var full = r.u(1) == 1;
		if (r.u(1) == 0) return named(2, full);
		r.u(16);
		return named(r.u(8), full);
	}

	// (hvcC's SPS (NAL type 33): to its VUI)
	static function hevc(c:Bytes):Null<{matrix:String, full:Bool}> {
		if (c.length < 23) return null;
		var at = 23, sps = -1, size = 0;
		for (_ in 0...c.get(22)) {
			if (at + 3 > c.length) return null;
			var type = c.get(at) & 63, n = c.get(at + 1) << 8 | c.get(at + 2);
			at += 3;
			for (_ in 0...n) {
				if (at + 2 > c.length) return null;
				var len = c.get(at) << 8 | c.get(at + 1);
				if (type == 33 && sps < 0) {
					sps = at + 2;
					size = len;
				}
				at += 2 + len;
			}
		}
		if (sps < 0 || sps + size > c.length) return null;
		var r = new Rbsp(c, sps + 2, size - 2);
		r.u(4);
		var layers = r.u(3);
		r.u(1);
		// (profile_tier_level: the general part, then each sub-layer's)
		r.u(32);
		r.u(32);
		r.u(32);
		var present = [for (_ in 0...layers) [r.u(1), r.u(1)]];
		if (layers > 0) for (_ in layers...8) r.u(2);
		for (p in present) {
			if (p[0] == 1) {
				r.u(32);
				r.u(32);
				r.u(24);
			}
			if (p[1] == 1) r.u(8);
		}
		r.ue();
		if (r.ue() == 3) r.u(1);
		r.ue();
		r.ue();
		if (r.u(1) == 1) for (_ in 0...4) r.ue();
		r.ue();
		r.ue();
		var lsb = r.ue() + 4;
		var all = r.u(1) == 1;
		for (_ in (all ? 0 : layers)...layers + 1) {
			r.ue();
			r.ue();
			r.ue();
		}
		for (_ in 0...6) r.ue();
		if (r.u(1) == 1 && r.u(1) == 1) for (size in 0...4) {
			var m = 0;
			while (m < 6) {
				if (r.u(1) == 0) r.ue() else {
					if (size > 1) r.se();
					for (_ in 0...Std.int(Math.min(64, 1 << (4 + (size << 1))))) r.se();
				}
				m += size == 3 ? 3 : 1;
			}
		}
		r.u(2);
		if (r.u(1) == 1) {
			r.u(8);
			r.ue();
			r.ue();
			r.u(1);
		}
		// (the short-term reference sets: each set's pictures, as later ones predict them from the one before)
		var sets = r.ue(), counts:Array<Int> = [];
		for (i in 0...sets) {
			if (i != 0 && r.u(1) == 1) {
				r.u(1);
				r.ue();
				var n = 0;
				for (_ in 0...counts[i - 1] + 1) if (r.u(1) == 1 || r.u(1) == 1) n++;
				counts.push(n);
			} else {
				var neg = r.ue(), pos = r.ue();
				for (_ in 0...neg + pos) {
					r.ue();
					r.u(1);
				}
				counts.push(neg + pos);
			}
		}
		if (r.u(1) == 1) for (_ in 0...r.ue()) {
			r.u(lsb);
			r.u(1);
		}
		r.u(2);
		if (r.u(1) == 0) return null;
		return signal(r);
	}
}

// (a NAL unit's payload read by bits, its emulation prevention bytes skipped)
private class Rbsp {
	final b:Bytes;
	final end:Int;
	var at:Int;
	var bit = 0;
	var zeros = 0;

	public function new(b:Bytes, from:Int, size:Int) {
		this.b = b;
		at = from;
		end = Std.int(Math.min(b.length, from + size));
	}

	function next():Int {
		if (at >= end) throw "the end";
		var v = b.get(at);
		// (0x000003: the 3 not the stream's)
		if (zeros >= 2 && v == 3 && bit == 0) {
			zeros = 0;
			at++;
			if (at >= end) throw "the end";
			v = b.get(at);
		}
		return v;
	}

	public function u(n:Int):Int {
		var v = 0;
		for (_ in 0...n) {
			var byte = next();
			v = v << 1 | (byte >> (7 - bit) & 1);
			if (++bit == 8) {
				bit = 0;
				zeros = byte == 0 ? zeros + 1 : 0;
				at++;
			}
		}
		return v;
	}

	public function ue():Int {
		var n = 0;
		while (u(1) == 0) if (++n > 31) throw "a code too long";
		return n == 0 ? 0 : (1 << n) - 1 + u(n);
	}

	public function se():Int {
		var k = ue();
		return k & 1 == 1 ? (k + 1) >> 1 : -(k >> 1);
	}
}
