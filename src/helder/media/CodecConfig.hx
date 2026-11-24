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
}
