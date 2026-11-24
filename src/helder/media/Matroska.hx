package helder.media;

import haxe.io.Bytes;

// Matroska and WebM (RFC 9559): the EBML header, then the Segment's
// elements up to the first Cluster (SeekHead, Info, Tracks, Cues; Cues
// and Tracks after the clusters found through SeekHead); clusters read one
// at a time when packets there are wanted: from a seek's Cue on, or from
// the first (live WebM, no Cues). SimpleBlocks and BlockGroups, Xiph, EBML
// and fixed lacing, clusters and a Segment of unknown size. Matroska keeps
// presentation times only: a packet's dts is its pts. CodecDelay is taken
// off every pts, as ffmpeg does (Opus's first packet before 0); a
// BlockGroup's DiscardPadding is its last frame's trim (Opus's end).
class Matroska implements Demuxer {
	public var tracks(default, null):Array<MediaTrack> = [];
	public var duration(default, null) = -1.0;
	// "matroska" or "webm"
	public var doc(default, null) = "";

	public var body(default, null) = 0.0;
	public var next(default, null) = -1.0;

	// Matroska's own: TrackNumber, its CodecDelay and DefaultDuration in ticks
	final numbers:Array<Int> = [];
	final delays:Array<Float> = [];
	final defaults:Array<Float> = [];
	final cues:Array<Cue> = [];
	final runs:Array<Run> = [];
	var scale = 1000000.0;
	var segment = 0.0;
	var segmentEnd = Math.POSITIVE_INFINITY;
	var clusters = -1.0;
	// (the walk: its phase, the element whose body it asked for, its size)
	var phase = HEAD;
	var pending = 0;
	var size = 0.0;
	var steps = 0;
	// (SeekHead's places of Info, Tracks and Cues; those read, a bit each)
	var seekInfo = -1.0;
	var seekTracks = -1.0;
	var seekCues = -1.0;
	var seen = 0;
	// (the run growing; what an unknown-size cluster's read takes, and where it starts)
	var growing:Null<Run>;
	var want = 0;
	var clusterAt = 0.0;

	static inline var HEAD = 0;
	static inline var SEGMENT_HEAD = 1;
	static inline var TOP = 2;
	static inline var SEEKS = 3;
	static inline var GROW = 4;

	static inline var EBML = 0x1A45DFA3;
	static inline var SEGMENT = 0x18538067;
	static inline var SEEKHEAD = 0x114D9B74;
	static inline var INFO = 0x1549A966;
	static inline var TRACKS = 0x1654AE6B;
	static inline var CUES = 0x1C53BB6B;
	static inline var CLUSTER = 0x1F43B675;
	static inline var TAGS = 0x1254C367;
	static inline var CHAPTERS = 0x1043A770;
	static inline var ATTACHMENTS = 0x1941A469;

	// size: the file's, -1 while not known
	public function new(size:Float)
		if (size >= 0) segmentEnd = size;

	public function walk(at:Float, head:Bytes):Int {
		next = -1;
		if (++steps > 1000000) throw new MediaError("too many elements");
		var d = new Data(head);
		switch phase {
			case HEAD:
				if (d.id() != EBML) throw new MediaError("not EBML");
				size = d.vsize();
				if (size < 0 || size > 4096) throw new MediaError("bad EBML header");
				body = at + d.pos;
				doc = "matroska";
				return Std.int(size);
			case SEGMENT_HEAD:
				if (d.id() != SEGMENT) throw new MediaError("no Segment");
				var length = d.vsize();
				segment = at + d.pos;
				if (length >= 0 && segment + length < segmentEnd) segmentEnd = segment + length;
				phase = TOP;
				next = segment;
				return -1;
			case TOP:
				if (at >= segmentEnd || d.left < 2) return seeks();
				var id = d.id(), n = d.vsize();
				if (id == CLUSTER) {
					clusters = at;
					return seeks();
				}
				if (n < 0) throw new MediaError("unknown size outside a cluster");
				body = at + d.pos;
				next = body + n;
				pending = id;
				return id == SEEKHEAD || id == INFO || id == TRACKS || id == CUES ? size32(n) : -1;
			case SEEKS:
				var id = d.left < 2 ? 0 : d.id(), n = d.left < 2 ? -1.0 : d.vsize();
				pending = id;
				body = at + d.pos;
				if (n >= 0 && (id == INFO || id == TRACKS || id == CUES) && seen & bit(id) == 0) return size32(n);
				return seeks();
			case _:
				var run = growing;
				if (at >= segmentEnd || d.left < 2) return end(run);
				var id = d.id(), n = d.vsize();
				body = at + d.pos;
				if (id != CLUSTER) {
					// (Cues, Tags or Void between or after the clusters; a live stream's next EBML header ends it)
					if (n < 0 || id == EBML) return end(run);
					run.end = body + n;
					for (r in runs) if (r != run && r.start == run.end) {
						merge(run, r);
						return -1;
					}
					next = run.end;
					return -1;
				}
				size = n;
				clusterAt = at;
				return n >= 0 ? size32(n) : want;
		}
	}

	static inline function bit(id:Int):Int
		return id == INFO ? 1 : id == TRACKS ? 2 : 4;

	function end(run:Run):Int {
		run.end = -1;
		return -1;
	}

	// (after the elements before the clusters: Info, Tracks or Cues not read yet, where SeekHead says)
	function seeks():Int {
		phase = SEEKS;
		var p = -1.0;
		if (seen & 1 == 0 && seekInfo >= 0) {
			p = seekInfo;
			seekInfo = -1;
		} else if (seen & 2 == 0 && seekTracks >= 0) {
			p = seekTracks;
			seekTracks = -1;
		} else if (seen & 4 == 0 && seekCues >= 0) {
			p = seekCues;
			seekCues = -1;
		}
		next = p < 0 ? -1 : segment + p;
		return -1;
	}

	public function take(b:Bytes) {
		var d = new Data(b);
		switch phase {
			case HEAD:
				if (b.length < size) throw new MediaError("EBML header cut short");
				elements(d, (id, e) -> if (id == 0x4282) doc = e.text(e.left));
				phase = SEGMENT_HEAD;
				next = body + size;
			case TOP:
				top(pending, d);
			case SEEKS:
				top(pending, d);
				seeks();
			case _:
				var run = growing;
				if (size >= 0) {
					if (b.length < size) throw new MediaError("cluster cut short");
					blocks(run, d, body, false);
					run.end = body + size;
					return;
				}
				// (unknown size: read on until an element of the Segment's, or the end)
				var whole = b.length < want;
				var end = blocks(new Run(0, 0, tracks.length), new Data(b), body, true);
				if (end >= 0 || whole) {
					blocks(run, new Data(b, 0, end >= 0 ? end : b.length), body, true);
					run.end = end >= 0 ? body + end : -1;
					return;
				}
				if (want >= Read.LIMIT) throw new MediaError("cluster too large");
				want *= 4;
				next = clusterAt;
		}
	}

	public function opened()
		if (tracks.length == 0) throw new MediaError("no tracks");

	static function size32(n:Float):Int {
		if (n > Read.LIMIT) throw new MediaError("element too large");
		return Std.int(n);
	}

	// each element in d: its ID and body
	static function elements(d:Data, f:(id:Int, body:Data) -> Void)
		while (d.left > 0) {
			var id = d.id(), n = d.vsize();
			if (n < 0 || n > d.left) throw new MediaError("bad element size");
			f(id, d.sub(Std.int(n)));
		}

	function top(id:Int, d:Data) {
		if (id == INFO || id == TRACKS || id == CUES) seen |= bit(id);
		switch id {
			case SEEKHEAD:
				elements(d, (id, e) -> if (id == 0x4DBB) {
					var target = 0, pos = -1.0;
					elements(e, (id, v) -> if (id == 0x53AB) target = new Data(v.take(v.left)).id() else if (id == 0x53AC) pos = v.uint(v.left));
					if (pos >= 0) switch target {
						case INFO if (seekInfo < 0): seekInfo = pos;
						case TRACKS if (seekTracks < 0): seekTracks = pos;
						case CUES if (seekCues < 0): seekCues = pos;
						case _:
					}
				});
			case INFO:
				var length = -1.0;
				elements(d, (id, v) -> switch id {
					case 0x2AD7B1:
						scale = v.uint(v.left);
					case 0x4489:
						length = v.float(v.left);
					case _:
				});
				if (scale <= 0) throw new MediaError("bad TimestampScale");
				if (length >= 0) duration = length * scale / 1e9;
			case TRACKS:
				if (tracks.length > 0) return;
				elements(d, (id, e) -> if (id == 0xAE) entry(e));
			case CUES:
				elements(d, (id, e) -> if (id == 0xBB) {
					var time = 0.0;
					elements(e, (id, v) -> switch id {
						case 0xB3:
							time = v.uint(v.left);
						case 0xB7:
							var track = 0, at = -1.0;
							elements(v, (id, w) -> if (id == 0xF7) track = Std.int(w.uint(w.left)) else if (id == 0xF1) at = w.uint(w.left));
							if (at >= 0) {
								// (in time's order: they come so, an insertion keeps it)
								var i = cues.length;
								while (i > 0 && cues[i - 1].time > time) i--;
								cues.insert(i, new Cue(time, track, segment + at));
							}
						case _:
					});
				});
			case _:
		}
	}

	function entry(d:Data) {
		var t = new TrackInfo(), number = 0, type = 0, codec = "", delay = 0.0, dur = 0.0;
		t.timescale = 1e9 / scale;
		elements(d, (id, v) -> switch id {
			case 0xD7:
				number = Std.int(v.uint(v.left));
			case 0x83:
				type = Std.int(v.uint(v.left));
			case 0x86:
				codec = v.text(v.left);
			case 0x63A2:
				t.config = v.take(v.left);
			case 0x23E383:
				dur = v.uint(v.left);
			case 0x56AA:
				delay = v.uint(v.left);
			case 0x56BB:
				t.preroll = v.uint(v.left) / 1e9;
			case 0xE0:
				elements(v, (id, w) -> switch id {
					case 0xB0:
						t.width = Std.int(w.uint(w.left));
					case 0xBA:
						t.height = Std.int(w.uint(w.left));
					case 0x7670:
						elements(w, (id, p) -> if (id == 0x7675) {
							// (ProjectionPoseRoll: degrees counterclockwise)
							var r = Math.round(-p.float(p.left) / 90) * 90;
							t.rotation = (r % 360 + 360) % 360;
						});
					case _:
				});
			case 0xE1:
				elements(v, (id, w) -> switch id {
					case 0xB5:
						t.sampleRate = Std.int(w.float(w.left));
					case 0x9F:
						t.channels = Std.int(w.uint(w.left));
					case 0x6264:
						t.bits = Std.int(w.uint(w.left));
					case _:
				});
			case _:
		});
		if (number == 0) return;
		t.index = tracks.length;
		t.id = number;
		t.tag = codec;
		t.kind = type == 1 ? Video : type == 2 ? Audio : Other;
		t.codec = switch codec {
			case "V_MPEG4/ISO/AVC": H264;
			case "V_MPEGH/ISO/HEVC": Hevc;
			case "V_VP8": Vp8;
			case "V_VP9": Vp9;
			case "V_AV1": Av1;
			case "A_MPEG/L3": Mp3;
			case "A_OPUS": Opus;
			case "A_VORBIS": Vorbis;
			case "A_FLAC": Flac;
			case "A_ALAC": Alac;
			case c if (StringTools.startsWith(c, "A_AAC")): Aac;
			case c if (StringTools.startsWith(c, "A_PCM/")): Pcm;
			case _: Other;
		}
		if (t.codec != Pcm) t.bits = 0;
		t.delay = delay / 1e9;
		t.duration = duration;
		numbers.push(number);
		delays.push(Math.round(delay / scale));
		defaults.push(dur / scale);
		tracks.push(new MediaTrack(t));
	}

	public function first():Run {
		if (clusters < 0) return new Run(0, -1, tracks.length);
		return at(clusters);
	}

	public function locate(track:Int, time:Float):Run {
		if (cues.length == 0) return first();
		var ticks = time * 1e9 / scale, number = numbers[track], own = false;
		for (c in cues) if (c.track == number) own = true;
		var pick = -1.0;
		for (c in cues) if ((!own || c.track == number) && (c.time <= ticks || pick < 0)) pick = c.at;
		if (pick < segment || pick >= segmentEnd) return first();
		return at(pick);
	}

	// the run holding the cluster at offset p, else a new one there (its
	// end at its start: nothing read yet)
	function at(p:Float):Run {
		for (r in runs) if (r.start == p || (r.start <= p && (r.end < 0 || p < r.end))) return r;
		var r = new Run(p, p, tracks.length);
		var i = 0;
		while (i < runs.length && runs[i].start < p) i++;
		runs.insert(i, r);
		return r;
	}

	public function grow(run:Run):Float {
		if (run.end < 0) return -1;
		if (run.end >= segmentEnd) {
			run.end = -1;
			return -1;
		}
		for (r in runs) if (r != run && r.start == run.end) {
			merge(run, r);
			return -2;
		}
		phase = GROW;
		growing = run;
		want = 65536;
		return run.end;
	}

	function merge(run:Run, next:Run) {
		next.shift = [for (s in run.samples) s.length];
		for (i in 0...tracks.length) run.samples[i].append(next.samples[i]);
		run.end = next.end;
		next.into = run;
		runs.remove(next);
	}

	// the cluster's blocks in d (at offset base in the file) into run; for
	// a cluster of unknown size, where in d it ends (-1: past d)
	function blocks(run:Run, d:Data, base:Float, open:Bool):Int {
		var time = 0.0;
		while (d.left > 0) {
			var start = d.pos;
			if (open && d.left < 12) {
				d.pos = start;
				if (!complete(d)) return -1;
			}
			var id = d.id(), n = d.vsize();
			if (open && (id == CLUSTER || id == CUES || id == TAGS || id == SEEKHEAD || id == INFO || id == TRACKS || id == CHAPTERS || id == ATTACHMENTS || id == EBML))
				return start;
			if (n < 0) throw new MediaError("bad element size in a cluster");
			if (n > d.left) {
				if (open) return -1;
				throw new MediaError("cluster cut short");
			}
			var e = d.sub(Std.int(n));
			switch id {
				case 0xE7:
					time = e.uint(e.left);
				case 0xA3:
					block(run, e, base, time, -1, true, true);
				case 0xA0:
					var b:Null<Data> = null, length = -1.0, key = true, trim = 0.0;
					elements(e, (id, v) -> switch id {
						case 0xA1:
							b = v;
						case 0x9B:
							length = v.uint(v.left);
						case 0xFB:
							key = false;
						case 0x75A2:
							trim = v.sint(v.left) / 1e9;
						case _:
					});
					if (b != null) block(run, b, base, time, length, key, false, trim);
				case _:
			}
		}
		return open ? -1 : 0;
	}

	// whether an element header is whole in what d has left
	static function complete(d:Data):Bool {
		var start = d.pos;
		var ok = try {
			d.id();
			d.vsize();
			true;
		} catch (e:MediaError) false;
		d.pos = start;
		return ok;
	}

	function block(run:Run, d:Data, base:Float, cluster:Float, length:Float, key:Bool, simple:Bool, trim = 0.0) {
		var number = Std.int(d.vsize()), rel = d.i16(), flags = d.u8();
		var track = numbers.indexOf(number);
		if (track < 0) return;
		if (simple) key = flags & 0x80 != 0;
		var frames = 1, lacing = (flags >> 1) & 3;
		var sizes:Array<Int> = [];
		if (lacing != 0) {
			frames = d.u8() + 1;
			switch lacing {
				case 1:
					for (_ in 0...frames - 1) {
						var s = 0, c = 255;
						while (c == 255) {
							c = d.u8();
							s += c;
						}
						sizes.push(s);
					}
				case 3:
					var s = d.vsize();
					if (s < 0) throw new MediaError("bad lace size");
					sizes.push(Std.int(s));
					for (_ in 1...frames - 1) {
						s += d.vsigned();
						if (s < 0) throw new MediaError("bad lace size");
						sizes.push(Std.int(s));
					}
				case _:
					if (d.left % frames != 0) throw new MediaError("bad fixed lacing");
					for (_ in 0...frames - 1) sizes.push(Std.int(d.left / frames));
			}
		}
		var sum = 0;
		for (s in sizes) sum += s;
		if (sum > d.left || sum < 0) throw new MediaError("bad lacing");
		sizes.push(d.left - sum);
		var pts = cluster + rel - delays[track], each = length >= 0 ? length / frames : defaults[track];
		var at = base + d.pos, s = run.samples[track];
		for (i in 0...frames) {
			var t = pts + i * defaults[track];
			s.add(at, sizes[i], t, t, each, key, i == frames - 1 ? trim : 0);
			at += sizes[i];
		}
	}
}

private class Cue {
	public final time:Float;
	public final track:Int;
	public final at:Float;

	public function new(time, track, at) {
		this.time = time;
		this.track = track;
		this.at = at;
	}
}
