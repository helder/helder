package helder.media;

import haxe.io.Bytes;

// MP4 and QuickTime (ISO/IEC 14496-12, 14): the top-level boxes walked by
// their headers (mdat skipped, never read), moov and each moof read whole.
// Every sample's offset, size, times and keyframe flag come from the
// sample tables (stts, ctts, stss, stsc, stsz or stz2, stco or co64) and the
// fragments (trex's defaults, tfhd, tfdt, trun), all at open. Times are the
// edit list's: an empty edit first delays the track, the first other one's
// media time is its start (so a frame before it has a pts below 0); more
// edits are not followed. sidx's references are kept (segments).
class Mp4 implements Demuxer {
	public var tracks(default, null):Array<MediaTrack> = [];
	public var duration(default, null) = -1.0;
	// sidx's: each fragment's track ID, earliest presentation time (seconds), offset and size
	public var segments(default, null):Array<{track:Int, time:Float, offset:Float, size:Float}> = [];

	public var body(default, null) = 0.0;
	public var next(default, null) = -1.0;

	final total:Float;
	final traks:Array<Trak> = [];
	var movieScale = 1000.0;
	var movieDuration = 0.0;
	var moovSeen = false;
	var boxCount = 0;
	var pending = "";
	var pendingAt = 0.0;
	var run:Null<Run>;

	// size: the file's, -1 while not known
	public function new(size:Float)
		total = size;

	// (the top-level boxes: moov, moof and sidx read, the others skipped)
	public function walk(at:Float, head:Bytes):Int {
		next = -1;
		if (head.length < 8) return -1;
		var d = new Data(head), size = d.u32(), type = d.fourcc(), h = 8;
		if (size == 1) {
			size = d.u64();
			h = 16;
		} else if (size == 0) {
			if (total < 0) return -1;
			size = total - at;
		}
		if (size < h) throw new MediaError('bad $type box');
		if (++boxCount > 1000000) throw new MediaError("too many boxes");
		next = at + size;
		body = at + h;
		pending = type;
		pendingAt = at;
		return switch type {
			case "moof" if (!moovSeen): throw new MediaError("moof before moov");
			case "moov" | "moof" | "sidx": bodySize(size - h);
			case _: -1;
		}
	}

	public function take(b:Bytes) {
		var d = new Data(b);
		switch pending {
			case "moov":
				moov(d);
				moovSeen = true;
			case "moof":
				moof(pendingAt, d);
			case "sidx":
				sidx(next, d);
			case _:
		}
	}

	public function opened() {
		if (!moovSeen) throw new MediaError("no moov box");
		finish();
	}

	static function bodySize(n:Float):Int {
		if (n > Read.LIMIT) throw new MediaError("box too large");
		return Std.int(n);
	}

	public function first():Run
		return run;

	public function locate(track:Int, time:Float):Run
		return run;

	public function grow(run:Run):Float
		return -1;

	// (each child box of d: its type and body)
	static function boxes(d:Data, f:(type:String, b:Data) -> Void) {
		while (d.left >= 8) {
			var size = d.u32(), type = d.fourcc(), head = 8;
			if (size == 1) {
				size = d.u64();
				head = 16;
			} else if (size == 0) size = d.left + 8;
			if (size < head || size - head > d.left) throw new MediaError('bad $type box');
			f(type, d.sub(Std.int(size - head)));
		}
	}

	function moov(d:Data)
		boxes(d, (type, b) -> switch type {
			case "mvhd":
				var v = b.u8();
				b.skip(3);
				b.skip(v == 1 ? 16 : 8);
				movieScale = b.u32();
				movieDuration = v == 1 ? b.u64() : b.u32();
				if (movieScale <= 0) throw new MediaError("bad mvhd timescale");
			case "trak":
				var t = new Trak(traks.length);
				trak(t, b);
				if (t.info.id != 0) traks.push(t);
			case "mvex":
				boxes(b, (type, b) -> if (type == "trex") {
					b.skip(4);
					var id = b.count();
					for (t in traks) if (t.info.id == id) {
						b.skip(4);
						t.defaultDuration = b.u32();
						t.defaultSize = b.u32();
						t.defaultFlags = b.i32();
					}
				});
			case _:
		});

	function trak(t:Trak, d:Data)
		boxes(d, (type, b) -> switch type {
			case "tkhd":
				var v = b.u8();
				b.skip(3);
				b.skip(v == 1 ? 16 : 8);
				t.info.id = b.count();
				b.skip(4);
				b.skip(v == 1 ? 8 : 4);
				b.skip(16);
				// (the matrix's a and b: its turn, a quarter's)
				var a = b.i32(), c = b.i32();
				t.info.rotation = a > 0x8000 ? 0 : a < -0x8000 ? 180 : c > 0 ? 90 : c < 0 ? 270 : 0;
			case "edts":
				boxes(b, (type, b) -> if (type == "elst") {
					var v = b.u8();
					b.skip(3);
					var n = b.count();
					for (_ in 0...n) {
						var length = v == 1 ? b.u64() : b.u32(), media = v == 1 ? b.i64() : b.i32();
						b.skip(4);
						if (t.edit != null) continue;
						if (media < 0) t.empty += length;
						else t.edit = {media: media, length: length};
					}
				});
			case "mdia":
				mdia(t, b);
			case _:
		});

	function mdia(t:Trak, d:Data)
		boxes(d, (type, b) -> switch type {
			case "mdhd":
				var v = b.u8();
				b.skip(3);
				b.skip(v == 1 ? 16 : 8);
				t.info.timescale = b.u32();
				t.mediaDuration = v == 1 ? b.u64() : b.u32();
				if (t.info.timescale <= 0) throw new MediaError("bad mdhd timescale");
			case "hdlr":
				b.skip(8);
				t.handler = b.fourcc();
				t.info.kind = t.handler == "vide" ? Video : t.handler == "soun" ? Audio : Other;
			case "minf":
				boxes(b, (type, b) -> if (type == "stbl") stbl(t, b));
			case _:
		});

	function stbl(t:Trak, d:Data)
		boxes(d, (type, b) -> {
			if (type == "stsd") return stsd(t, b);
			b.skip(4);
			switch type {
				case "stts":
					t.stts = table(b, 2);
				case "ctts":
					// (signed in either version, as ffmpeg reads them)
					t.ctts = table(b, 2);
				case "stss":
					t.stss = table(b, 1);
				case "stsc":
					t.stsc = table(b, 3);
				case "stsz":
					t.sampleSize = b.u32();
					var n = b.count();
					if (t.sampleSize == 0) {
						if (n > b.left >> 2) throw new MediaError("bad stsz");
						t.sizes = [for (_ in 0...n) b.count()];
					} else t.samples = n;
				case "stz2":
					b.skip(3);
					var bits = b.u8(), n = b.count();
					if (bits != 4 && bits != 8 && bits != 16) throw new MediaError("bad stz2");
					if (n > b.left * 8 / bits) throw new MediaError("bad stz2");
					t.sizes = [];
					for (i in 0...n) t.sizes.push(bits == 16 ? b.u16() : bits == 8 ? b.u8() : {
						if (i & 1 == 0) b.u8() >> 4 else b.bytes.get(b.pos - 1) & 15;
					});
				case "stco":
					var n = b.count();
					if (n > b.left >> 2) throw new MediaError("bad stco");
					t.chunks = [for (_ in 0...n) b.u32()];
				case "co64":
					var n = b.count();
					if (n > b.left >> 3) throw new MediaError("bad co64");
					t.chunks = [for (_ in 0...n) b.u64()];
				case _:
			}
		});

	// a table of n columns of 32-bit entries, ctts' offsets signed
	static function table(b:Data, columns:Int):Array<Int> {
		var n = b.count();
		if (n > b.left / (4 * columns)) throw new MediaError("bad sample table");
		return [for (_ in 0...n * columns) b.i32()];
	}

	function stsd(t:Trak, d:Data) {
		d.skip(4);
		if (d.count() < 1) return;
		var size = d.count();
		if (size < 16) throw new MediaError("bad stsd");
		var entry = d.sub(size - 4);
		var type = entry.fourcc();
		entry.skip(8);
		var info = t.info;
		info.tag = type;
		info.codec = switch type {
			case "avc1" | "avc3": H264;
			case "hvc1" | "hev1": Hevc;
			case "vp08": Vp8;
			case "vp09": Vp9;
			case "av01": Av1;
			case ".mp3": Mp3;
			case "Opus": Opus;
			case "fLaC": Flac;
			case "alac": Alac;
			case "sowt" | "twos" | "lpcm" | "ipcm" | "fpcm" | "fl32" | "fl64" | "in24" | "in32" | "raw ": Pcm;
			case _: Other;
		}
		if (t.handler == "vide") {
			entry.skip(16);
			info.width = entry.u16();
			info.height = entry.u16();
			entry.skip(50);
		} else if (t.handler == "soun") {
			var v = entry.u16();
			entry.skip(6);
			info.channels = entry.u16();
			info.bits = entry.u16();
			entry.skip(4);
			info.sampleRate = Std.int(entry.u32() / 65536);
			if (v == 1 && entry.left >= 16) entry.skip(16);
			else if (v == 2) {
				entry.skip(4);
				info.sampleRate = Std.int(entry.f64());
				info.channels = entry.count();
				entry.skip(4);
				info.bits = entry.count();
				entry.skip(12);
			}
			if (info.codec != Pcm) info.bits = 0;
		} else return;
		entryBoxes(t, entry);
	}

	function entryBoxes(t:Trak, d:Data) {
		var info = t.info;
		boxes(d, (type, b) -> switch type {
			case "avcC" | "hvcC" | "av1C" | "vpcC":
				info.config = b.take(b.left);
			case "esds":
				b.skip(4);
				esds(info, b);
			case "dOps":
				info.config = opusHead(b);
			case "dfLa":
				b.skip(4);
				// (the first metadata block, STREAMINFO: its body)
				b.skip(1);
				info.config = b.take(b.u24());
			case "alac" if (b.left >= 28):
				var whole = Bytes.alloc(b.left + 8);
				whole.set(0, (b.left + 8) >>> 24);
				whole.set(1, ((b.left + 8) >> 16) & 255);
				whole.set(2, ((b.left + 8) >> 8) & 255);
				whole.set(3, (b.left + 8) & 255);
				whole.blit(4, Bytes.ofString("alac"), 0, 4);
				whole.blit(8, b.bytes, b.pos, b.left);
				info.config = whole;
			case "wave":
				// (QuickTime's sound description: its own esds or alac inside)
				entryBoxes(t, b);
			case "frma":
				info.tag = b.fourcc();
			case _:
		});
	}

	// ES_Descriptor > DecoderConfigDescriptor (the codec) > DecoderSpecificInfo (config)
	static function esds(info:TrackInfo, d:Data) {
		while (d.left > 1) {
			var tag = d.u8(), n = 0;
			for (_ in 0...4) {
				var c = d.u8();
				n = (n << 7) | (c & 127);
				if (c & 128 == 0) break;
			}
			if (n > d.left) throw new MediaError("bad esds");
			var body = d.sub(n);
			switch tag {
				case 3:
					body.skip(2);
					var flags = body.u8();
					if (flags & 128 != 0) body.skip(2);
					if (flags & 64 != 0) body.skip(body.u8());
					if (flags & 32 != 0) body.skip(2);
					esds(info, body);
				case 4:
					var oti = body.u8();
					if (info.tag == "mp4a") info.codec = switch oti {
						case 0x40 | 0x66 | 0x67 | 0x68: Aac;
						case 0x69 | 0x6b: Mp3;
						case 0xad: Opus;
						case _: Other;
					}
					body.skip(12);
					esds(info, body);
				case 5:
					info.config = body.take(body.left);
				case _:
			}
		}
	}

	// dOps (big-endian) as OpusHead (little-endian), what decoders and Matroska take
	static function opusHead(d:Data):Bytes {
		d.skip(1);
		var channels = d.u8(), preskip = d.u16(), rate = d.u32(), gain = d.u16(), family = d.u8();
		var map = family == 0 ? Bytes.alloc(0) : d.take(2 + channels);
		var b = Bytes.alloc(19 + map.length);
		b.blit(0, Bytes.ofString("OpusHead"), 0, 8);
		b.set(8, 1);
		b.set(9, channels);
		b.setUInt16(10, preskip);
		b.setInt32(12, Std.int(rate));
		b.setUInt16(16, gain);
		b.set(18, family);
		b.blit(19, map, 0, map.length);
		return b;
	}

	function moof(at:Float, d:Data) {
		var next = at;
		boxes(d, (type, b) -> if (type == "traf") next = traf(at, next, b));
	}

	// a track fragment: its samples added; where its data ends
	function traf(moofAt:Float, previous:Float, d:Data):Float {
		var t:Null<Trak> = null, base = previous, size = 0.0, length = 0.0, flags = 0, decode = -1.0, end = previous;
		boxes(d, (type, b) -> switch type {
			case "tfhd":
				var f = b.u8() << 24 | b.u24();
				var id = b.count();
				for (k in traks) if (k.info.id == id) t = k;
				if (t == null) return;
				length = t.defaultDuration;
				size = t.defaultSize;
				flags = t.defaultFlags;
				base = f & 0x20000 != 0 || previous == moofAt ? moofAt : previous;
				if (f & 1 != 0) base = b.u64();
				if (f & 2 != 0) b.skip(4);
				if (f & 8 != 0) length = b.u32();
				if (f & 0x10 != 0) size = b.u32();
				if (f & 0x20 != 0) flags = b.i32();
				end = base;
			case "tfdt" if (t != null):
				var v = b.u8();
				b.skip(3);
				decode = v == 1 ? b.u64() : b.u32();
			case "trun" if (t != null):
				var v = b.u8(), f = b.u24(), n = b.count();
				var data = f & 1 != 0 ? base + b.i32() : end;
				var firstFlags = f & 4 != 0 ? b.i32() : flags;
				var each = (f & 0x100 != 0 ? 4 : 0) + (f & 0x200 != 0 ? 4 : 0) + (f & 0x400 != 0 ? 4 : 0) + (f & 0x800 != 0 ? 4 : 0);
				if (each > 0 && n > b.left / each) throw new MediaError("bad trun");
				if (n > 10000000) throw new MediaError("bad trun");
				var dts = decode >= 0 ? decode : t.next;
				decode = -1;
				for (i in 0...n) {
					var dur = f & 0x100 != 0 ? b.u32() : length;
					var sz = f & 0x200 != 0 ? b.u32() : size;
					var fl = f & 0x400 != 0 ? b.i32() : i == 0 ? firstFlags : flags;
					var cto = f & 0x800 != 0 ? b.i32() : 0;
					if (sz > 0x7fffffff) throw new MediaError("bad trun");
					t.frag.add(data, Std.int(sz), dts, dts + cto, dur, fl & 0x10000 == 0);
					data += sz;
					dts += dur;
				}
				t.next = dts;
				end = data;
			case _:
		});
		return end;
	}

	function sidx(anchor:Float, d:Data) {
		var v = d.u8();
		d.skip(3);
		var id = d.count(), scale = d.u32();
		var time = v == 1 ? d.u64() : d.u32(), offset = anchor + (v == 1 ? d.u64() : d.u32());
		d.skip(2);
		var n = d.u16();
		if (scale <= 0) throw new MediaError("bad sidx");
		for (_ in 0...n) {
			var r = d.u32(), length = d.u32();
			d.skip(4);
			var size = r % 2147483648.0;
			if (r < 2147483648.0) segments.push({track: id, time: time / scale, offset: offset, size: size});
			offset += size;
			time += length;
		}
	}

	// the sample tables expanded, the fragments' added, the edits applied
	function finish() {
		run = new Run(0, -1, traks.length);
		for (t in traks) {
			var s = run.samples[t.index];
			samples(t, s);
			s.append(t.frag);
			var info = t.info;
			var shift = (t.empty / movieScale) * info.timescale - (t.edit?.media ?? 0);
			if (shift != 0)
				for (i in 0...s.length) {
					s.dts[i] += shift;
					s.pts[i] += shift;
				}
			info.duration = if (t.edit != null || t.empty > 0) (t.empty + (t.edit?.length ?? 0)) / movieScale
				else if (t.mediaDuration > 0) t.mediaDuration / info.timescale
				else end(s) / info.timescale;
			var track = new MediaTrack(info);
			tracks.push(track);
		}
		duration = movieDuration > 0 ? movieDuration / movieScale : -1.0;
		if (duration < 0) for (t in tracks) if (t.duration > duration) duration = t.duration;
	}

	// (where the last frame shown ends: a fragmented file's duration)
	static function end(s:Samples):Float {
		var e = -1.0;
		for (i in 0...s.length) if (s.pts[i] + s.duration[i] > e) e = s.pts[i] + s.duration[i];
		return e;
	}

	static final MAX_SAMPLES = 50000000;

	function samples(t:Trak, s:Samples) {
		var n = t.sizes != null ? t.sizes.length : t.samples;
		if (n == 0 || t.chunks.length == 0) return;
		if (n > MAX_SAMPLES || (t.sizes == null && total >= 0 && n * t.sampleSize > total)) throw new MediaError("too many samples");
		var stts = t.stts, ctts = t.ctts, stsc = t.stsc, keys = t.stss;
		// PCM's samples are single frames: a chunk a packet, as ffmpeg reads them
		var chunked = t.info.codec == Pcm && t.sizes == null;
		var sttsAt = 0, sttsLeft = stts.length > 0 ? stts[0] : 0, cttsAt = 0, cttsLeft = ctts.length > 0 ? ctts[0] : 0, keyAt = 0;
		var dts = 0.0, i = 0, entry = 0;
		inline function delta():Float {
			while (sttsLeft <= 0 && sttsAt + 2 < stts.length) {
				sttsAt += 2;
				sttsLeft = stts[sttsAt];
			}
			sttsLeft--;
			return stts.length > 0 ? stts[sttsAt + 1] : 0;
		}
		inline function offset():Float {
			if (ctts.length == 0) return 0;
			while (cttsLeft <= 0 && cttsAt + 2 < ctts.length) {
				cttsAt += 2;
				cttsLeft = ctts[cttsAt];
			}
			cttsLeft--;
			return ctts[cttsAt + 1];
		}
		for (c in 0...t.chunks.length) {
			if (i >= n) break;
			while (entry + 3 < stsc.length && stsc[entry + 3] - 1 <= c) entry += 3;
			if (stsc.length == 0) throw new MediaError("no stsc");
			var count = stsc[entry + 1];
			if (count < 0) throw new MediaError("bad stsc");
			var at = t.chunks[c];
			if (chunked) {
				var k = count < n - i ? count : n - i, dur = 0.0;
				for (_ in 0...k) dur += delta();
				var size = k * t.sampleSize;
				if (size > 0x7fffffff) throw new MediaError("chunk too large");
				s.add(at, Std.int(size), dts, dts, dur, true);
				dts += dur;
				i += k;
				continue;
			}
			for (_ in 0...count) {
				if (i >= n) break;
				var size = t.sizes != null ? t.sizes[i] : t.sampleSize;
				if (size > 0x7fffffff) throw new MediaError("bad sample size");
				var key = keys == null ? true : {
					while (keyAt < keys.length && keys[keyAt] - 1 < i) keyAt++;
					keyAt < keys.length && keys[keyAt] - 1 == i;
				}
				var dur = delta();
				s.add(at, Std.int(size), dts, dts + offset(), dur, key);
				at += size;
				dts += dur;
				i++;
			}
		}
	}
}

private class Trak {
	public final index:Int;
	public final info = new TrackInfo();
	public var handler = "";
	public var mediaDuration = 0.0;
	public var empty = 0.0;
	public var edit:Null<{media:Float, length:Float}> = null;
	public var stts:Array<Int> = [];
	public var ctts:Array<Int> = [];
	public var stss:Null<Array<Int>> = null;
	public var stsc:Array<Int> = [];
	public var sizes:Null<Array<Int>> = null;
	public var sampleSize = 0.0;
	public var samples = 0;
	public var chunks:Array<Float> = [];
	public var defaultDuration = 0.0;
	public var defaultSize = 0.0;
	public var defaultFlags = 0;
	// the fragments' samples, and the next one's dts
	public final frag = new Samples();
	public var next = 0.0;

	public function new(index) {
		this.index = index;
		info.index = index;
	}
}
