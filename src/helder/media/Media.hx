package helder.media;

import haxe.io.Bytes;

// A video or audio file read from a ByteSource: its tracks, its packets in
// the file's order, and exact seeking. MP4 and QuickTime (Mp4), Matroska
// and WebM (Matroska), told apart by their first bytes.
//
//   var media = Media.open(new FileSource("clip.mp4"));
//   for (s in media.seek(12.5)) trace(s.track.codec, s.packet.time, s.drop);
//   var p; while ((p = media.next()) != null) decode(p, media.read(p));
class Media {
	public final tracks:Array<MediaTrack>;
	// seconds; -1 when the file does not say
	public final duration:Float;
	public final demuxer:Demuxer;

	final source:ByteSource;
	// (where each track reads next: a run and a row of its samples)
	final runs:Array<Run>;
	final rows:Array<Int>;

	function new(source:ByteSource, demuxer:Demuxer, first:Run) {
		this.source = source;
		this.demuxer = demuxer;
		tracks = demuxer.tracks;
		duration = demuxer.duration;
		runs = [for (_ in tracks) first];
		rows = [for (_ in tracks) 0];
	}

	@:coroutine public static function open(source:ByteSource):Media {
		var d = sniff(Read.bytes(source, 0, 12), source.size);
		walk(source, d, 0);
		d.opened();
		var first = d.first();
		var m = new Media(source, d, first);
		m.load(first);
		return m;
	}

	// (the demuxer's walk: the bytes it asks for read, until it is done)
	@:coroutine static function walk(source:ByteSource, d:Demuxer, at:Float)
		while (at >= 0) {
			var n = d.walk(at, Read.bytes(source, at, 16));
			if (n >= 0) d.take(Read.bytes(source, d.body, n));
			at = d.next;
		}

	// (run's next stretch read: whether packets came)
	@:coroutine function extend(run:Run):Bool {
		var at = demuxer.grow(run);
		if (at == -2) return true;
		if (at < 0) return false;
		var before = rowsOf(run);
		walk(source, demuxer, at);
		return rowsOf(run) > before;
	}

	// (a run just made: its first stretch)
	@:coroutine function load(run:Run)
		if (run.end == run.start) extend(run);

	static function rowsOf(run:Run):Int {
		var n = 0;
		for (s in run.samples) n += s.length;
		return n;
	}

	// (EBML's magic, else an MP4 box's type)
	static function sniff(h:Bytes, size:Float):Demuxer {
		if (h.length >= 4 && h.get(0) == 0x1A && h.get(1) == 0x45 && h.get(2) == 0xDF && h.get(3) == 0xA3) return new Matroska(size);
		if (h.length >= 8 && BOXES.contains(h.getString(4, 4))) return new Mp4(size);
		throw new MediaError("not MP4 or Matroska");
	}

	static final BOXES = ["ftyp", "moov", "mdat", "free", "skip", "wide", "styp", "moof", "sidx", "pnot", "uuid"];

	// the next packet of any track, in the file's order (each track's in
	// decode order); null at the end
	@:coroutine public function next():Null<Packet> {
		while (true) {
			var best = -1, at = Math.POSITIVE_INFINITY;
			for (i in 0...tracks.length) {
				var s = samples(i);
				if (rows[i] < s.length && s.offset[rows[i]] < at) {
					best = i;
					at = s.offset[rows[i]];
				}
			}
			// (a track at its run's end: the next cluster may come first)
			var grown = false;
			for (i in 0...tracks.length) {
				var r = runs[i];
				if (rows[i] >= samples(i).length && r.end >= 0 && r.end < at && extend(r)) {
					grown = true;
					break;
				}
			}
			if (grown) continue;
			if (best < 0) return null;
			return samples(best).packet(tracks[best], rows[best]++);
		}
	}

	// a packet's bytes
	@:coroutine public function read(p:Packet):Bytes {
		var b = Read.bytes(source, p.offset, p.size);
		if (b.length < p.size) throw new MediaError("packet cut short");
		return b;
	}

	// every track to the time (seconds): video from the keyframe before the
	// frame due then, frames to drop up to it; audio from the packet that
	// holds it. next() goes on from there.
	@:coroutine public function seek(time:Float):Array<Seek>
		return [for (i in 0...tracks.length) seekTrack(i, time)];

	@:coroutine function seekTrack(i:Int, time:Float):Seek {
		var run = demuxer.locate(i, time);
		load(run);
		while (run.into != null) run = run.into;
		var ticks = time * tracks[i].timescale;
		while (short(run.samples[i], ticks) && extend(run)) {}
		var target = due(run.samples[i], ticks);
		while (target >= 0 && keyAfter(run.samples[i], target) < 0 && extend(run)) {}
		return found(i, run, target, time);
	}

	// (whether a track's packets read so far end before the time)
	static function short(s:Samples, ticks:Float):Bool
		return s.length == 0 || s.pts[s.length - 1] < ticks;

	// (the frame due: the latest pts at or before the time, else the earliest; -1 for none)
	static function due(s:Samples, ticks:Float):Int {
		var target = -1, first = 0;
		for (j in 0...s.length) {
			if (s.pts[j] <= ticks && (target < 0 || s.pts[j] > s.pts[target])) target = j;
			if (s.pts[j] < s.pts[first]) first = j;
		}
		return target < 0 && s.length > 0 ? first : target;
	}

	static function keyAfter(s:Samples, j:Int):Int {
		for (k in j + 1...s.length) if (s.key[k]) return k;
		return -1;
	}

	// (the keyframe before the target, the frames shown before it up to the next keyframe)
	function found(i:Int, run:Run, target:Int, time:Float):Seek {
		var track = tracks[i], s = run.samples[i];
		runs[i] = run;
		rows[i] = 0;
		if (target < 0) return {track: track, packet: null, drop: 0, time: time};
		var key = target;
		while (key > 0 && !(s.key[key] && s.pts[key] <= s.pts[target])) key--;
		var after = keyAfter(s, target), drop = 0;
		for (j in key...(after < 0 ? s.length : after)) if (s.pts[j] < s.pts[target]) drop++;
		rows[i] = key;
		return {track: track, packet: s.packet(track, key), drop: drop, time: s.pts[target] / track.timescale};
	}

	function samples(i:Int):Samples {
		var r = runs[i];
		while (r.into != null) {
			rows[i] += r.shift[i];
			r = runs[i] = r.into;
		}
		return r.samples[i];
	}

	public function close()
		source.close();
}
