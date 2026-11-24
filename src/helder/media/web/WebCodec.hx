package helder.media.web;

import haxe.io.Bytes;

// A track as WebCodecs names it: its codec string (RFC 6381's, read from
// the config: avcC, hvcC, vpcC, av1C, AAC's AudioSpecificConfig) and its
// description (the config, FLAC's as "fLaC" and its blocks); null: one
// WebCodecs has no name for (ALAC, big-endian PCM)
class WebCodec {
	public static function name(t:MediaTrack, ?first:Bytes):Null<String> {
		var c = t.config;
		inline function at(i:Int):Int
			return c != null && i < c.length ? c.get(i) : 0;
		return switch t.codec {
			case H264: 'avc1.' + hex(at(1)) + hex(at(2)) + hex(at(3));
			case Hevc: hevc(t.tag == "hev1" ? "hev1" : "hvc1", c);
			case Vp8: "vp8";
			case Vp9:
				// (a WebM's: its first keyframe's profile; 10 bits from profile 2)
				var profile = c != null ? at(4) : first != null && first.length > 0 ? ((first.get(0) >> 5) & 1) | (((first.get(0) >> 4) & 1) << 1) : 0;
				var depth = c != null ? at(6) >> 4 : profile >= 2 ? 10 : 8;
				'vp09.' + two(profile) + '.' + two(c != null && at(5) > 0 ? at(5) : 10) + '.' + two(depth);
			case Av1:
				var high = (at(2) >> 6) & 1, twelve = (at(2) >> 5) & 1;
				'av01.' + (at(1) >> 5) + '.' + two(at(1) & 31) + ((at(2) & 128) != 0 ? "H" : "M") + '.' + two(high == 0 ? 8 : twelve == 1 ? 12 : 10);
			case Aac:
				var type = at(0) >> 3;
				'mp4a.40.' + (type == 0 || type == 31 ? 2 : type);
			case Mp3: "mp3";
			case Opus: "opus";
			case Vorbis: "vorbis";
			case Flac: "flac";
			case Pcm if (t.tag == "A_PCM/INT/LIT" || t.tag == "sowt"):
				t.bits == 16 || t.bits == 24 || t.bits == 32 ? 'pcm-s${t.bits}' : null;
			case Pcm if (t.tag == "A_PCM/FLOAT/IEEE" || t.tag == "fl32"): t.bits == 32 ? "pcm-f32" : null;
			case _: null;
		}
	}

	// what the decoder is configured with beside the name (null: nothing)
	public static function description(t:MediaTrack):Null<Bytes> {
		var c = t.config;
		if (c == null || t.codec == Vp9 || t.codec == Av1 || t.codec == Mp3 || t.codec == Pcm) return null;
		// (MP4's FLAC: STREAMINFO's body, made a stream's header and its last block)
		if (t.codec == Flac && c.length == 34) {
			var b = Bytes.alloc(42);
			b.blit(0, Bytes.ofString("fLaC"), 0, 4);
			b.set(4, 0x80);
			b.set(7, 34);
			b.blit(8, c, 0, 34);
			return b;
		}
		return c;
	}

	// a stream that names no colours (no matrix, or "unspecified"): BT.601's
	// (ffmpeg's and Apple's reading; a browser's is BT.709's), its range the
	// stream's: 1 video range, 2 full; 0: the stream names them, the browser
	// reads them. H.264's SPS, VP9's vpcC or keyframe, AV1's sequence header
	// (av1C's, else the first packet's)
	public static function untagged(t:MediaTrack, ?first:Bytes):Int {
		var c = t.config;
		return switch t.codec {
			case H264 if (c != null): avc(c);
			// (vpcC: its matrix, unspecified 2)
			case Vp9 if (c != null): c.length >= 10 && c.get(9) == 2 ? (c.get(6) & 1) + 1 : 0;
			case Vp9 if (first != null): vp9(first);
			case Av1:
				var obus = c != null && c.length > 4 ? c.sub(4, c.length - 4) : first;
				obus == null ? 0 : av1(obus);
			case _: 0;
		}
	}

	// (VP9's keyframe: its colour space unknown, 0)
	static function vp9(f:Bytes):Int {
		var r = new Bits(f);
		r.u(2);
		var profile = r.u(1) | (r.u(1) << 1);
		if (profile == 3) r.u(1);
		if (r.u(1) == 1 || r.u(1) != 0) return 0;
		r.u(2);
		r.u(24);
		if (profile >= 2) r.u(1);
		return r.u(3) != 0 ? 0 : r.u(1) + 1;
	}

	// (AV1's OBUs: the sequence header's colour description)
	static function av1(b:Bytes):Int {
		var at = 0;
		while (at < b.length) {
			var head = b.get(at++), type = (head >> 3) & 15;
			if (head & 4 != 0) at++;
			var size = b.length - at;
			if (head & 2 != 0) {
				size = 0;
				var shift = 0, x = 128;
				while (x & 128 != 0 && at < b.length && shift < 35) {
					x = b.get(at++);
					size |= (x & 127) << shift;
					shift += 7;
				}
			}
			if (type == 1) return sequence(new Bits(b.sub(at, Std.int(Math.min(size, b.length - at)))));
			at += size;
		}
		return 0;
	}

	static function sequence(r:Bits):Int {
		var profile = r.u(3);
		r.u(1);
		var reduced = r.u(1) == 1, model = false, delay = 0;
		if (reduced) r.u(5) else {
			if (r.u(1) == 1) {
				r.u(32);
				r.u(32);
				if (r.u(1) == 1) {
					var z = 0;
					while (r.u(1) == 0 && z < 32) z++;
					r.u(z);
				}
				if (model = r.u(1) == 1) {
					delay = r.u(5) + 1;
					r.u(32);
					r.u(10);
				}
			}
			var initial = r.u(1) == 1;
			for (_ in 0...r.u(5) + 1) {
				r.u(12);
				if (r.u(5) > 7) r.u(1);
				if (model && r.u(1) == 1) {
					r.u(delay);
					r.u(delay);
					r.u(1);
				}
				if (initial && r.u(1) == 1) r.u(4);
			}
		}
		var wb = r.u(4) + 1, hb = r.u(4) + 1;
		r.u(wb);
		r.u(hb);
		if (!reduced && r.u(1) == 1) r.u(7);
		r.u(3);
		if (!reduced) {
			r.u(4);
			var hint = r.u(1) == 1;
			if (hint) r.u(2);
			var force = r.u(1) == 1 ? 2 : r.u(1);
			if (force > 0 && r.u(1) == 0) r.u(1);
			if (hint) r.u(3);
		}
		r.u(3);
		var high = r.u(1) == 1;
		if (profile == 2 && high) r.u(1);
		var mono = profile == 1 ? false : r.u(1) == 1, matrix = 2;
		if (r.u(1) == 1) {
			var primaries = r.u(8), transfer = r.u(8);
			matrix = r.u(8);
			// (sRGB's: no range bit)
			if (primaries == 1 && transfer == 13 && matrix == 0) return 0;
		}
		var full = r.u(1) == 1;
		return matrix != 2 || mono ? 0 : full ? 2 : 1;
	}

	static function avc(c:Bytes):Int {
		if (c.length < 8 || c.get(5) & 31 == 0) return 0;
		var n = (c.get(6) << 8) | c.get(7);
		if (8 + n > c.length) return 0;
		// (the SPS's RBSP: emulation prevention's 3s out)
		var b = new haxe.io.BytesBuffer(), zeros = 0;
		for (i in 9...8 + n) {
			var x = c.get(i);
			if (zeros >= 2 && x == 3) {
				zeros = 0;
				continue;
			}
			zeros = x == 0 ? zeros + 1 : 0;
			b.addByte(x);
		}
		var r = new Bits(b.getBytes());
		var profile = r.u(8);
		r.u(16);
		r.ue();
		if ([100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135].indexOf(profile) >= 0) {
			if (r.ue() == 3) r.u(1);
			r.ue();
			r.ue();
			r.u(1);
			if (r.u(1) == 1) for (i in 0...8) if (r.u(1) == 1) {
				var last = 8, next = 8;
				for (_ in 0...(i < 6 ? 16 : 64)) {
					if (next != 0) next = (last + r.se() + 256) % 256;
					if (next != 0) last = next;
				}
			}
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
		if (r.u(1) == 0) return 1;
		if (r.u(1) == 1 && r.u(8) == 255) r.u(32);
		if (r.u(1) == 1) r.u(1);
		if (r.u(1) == 0) return 1;
		r.u(3);
		var full = r.u(1) == 1;
		// (colours named, and a matrix not "unspecified")
		if (r.u(1) == 1) {
			r.u(16);
			if (r.u(8) != 2) return 0;
		}
		return full ? 2 : 1;
	}

	// (hvcC's: "hvc1.1.6.L93.B0": profile space and idc, compatibility
	// flags reversed, tier and level, constraint bytes without trailing zeros)
	static function hevc(tag:String, c:Null<Bytes>):String {
		if (c == null || c.length < 13) return tag + ".1.6.L93.B0";
		var space = c.get(1) >> 6, flags = 0;
		for (i in 0...4) flags = flags << 8 | c.get(2 + i);
		var reversed = 0;
		for (i in 0...32) if (flags & (1 << i) != 0) reversed |= 1 << (31 - i);
		var s = tag + '.' + ["", "A", "B", "C"][space] + (c.get(1) & 31) + '.' + StringTools.hex(reversed).toLowerCase() + '.' + ((c.get(1) & 32) != 0 ? "H" : "L") + c.get(12);
		var last = 11;
		while (last >= 6 && c.get(last) == 0) last--;
		for (i in 6...last + 1) s += '.' + StringTools.hex(c.get(i)).toLowerCase();
		return s;
	}

	static function hex(v:Int):String
		return StringTools.hex(v, 2).toLowerCase();

	static function two(v:Int):String
		return v < 10 ? '0$v' : '$v';
}

// (bits of an RBSP, read from the top; past its end zeros)
private class Bits {
	final b:Bytes;
	var at = 0;

	public function new(b)
		this.b = b;

	public function u(n:Int):Int {
		var v = 0;
		for (_ in 0...n) {
			var i = at >> 3;
			v = (v << 1) | (i < b.length ? (b.get(i) >> (7 - (at & 7))) & 1 : 0);
			at++;
		}
		return v;
	}

	public function ue():Int {
		var z = 0;
		while (u(1) == 0 && z < 32) z++;
		return (1 << z) - 1 + u(z);
	}

	public function se():Int {
		var k = ue();
		return k & 1 == 1 ? (k + 1) >> 1 : -(k >> 1);
	}
}
