package helder.ui.draw;

import haxe.io.Bytes;
import helder.ui.draw.FrameStreams.FrameInput;
import helder.ui.draw.FrameStreams.FrameRec;

// A loop's frames (a story's, played from its moment: FrameWriter.loop) as
// data, each from the one before as DisplayList.diff sees two recordings:
// the ops they begin and end with alike (the same calls but for their
// numbers) kept, only the numbers that changed written, each as its step
// from the last frame's; the ops between written whole (a node come, one
// gone). Every KEY frames one written from none, whole, where a player
// may start.
//
// A frame: how many ops it keeps from the start and the end of the last,
// how many of the last's it drops between them, how many it adds; which of
// the kept changed (runs: unchanged, changed, unchanged...), their numbers'
// steps; the added ops (code, ints, slots and floats).
class FrameLoop {
	public static inline var KEY = 30;

	// frames' records (FrameStreams' recording) as their deltas
	public static function encode(frames:Array<Array<FrameRec>>):Array<Bytes> {
		var out = [], prev:Array<FrameRec> = [];
		for (i => cur in frames) {
			if (i % KEY == 0) prev = [];
			out.push(delta(prev, cur));
			prev = cur;
		}
		return out;
	}

	static function delta(prev:Array<FrameRec>, cur:Array<FrameRec>):Bytes {
		var n = prev.length < cur.length ? prev.length : cur.length, p = 0, s = 0;
		while (p < n && prev[p].alike(cur[p]))
			p++;
		while (s < n - p && prev[prev.length - 1 - s].alike(cur[cur.length - 1 - s]))
			s++;
		var o = new FrameStreams();
		o.uint(p);
		o.uint(s);
		o.uint(prev.length - p - s);
		o.uint(cur.length - p - s);
		// (the kept ops: which changed, as runs)
		var kept = [for (k in 0...p) k].concat([for (k in 0...s) cur.length - s + k]);
		function before(k:Int):FrameRec
			return k < p ? prev[k] : prev[prev.length - (cur.length - k)];
		var changed = [for (k in kept) !cur[k].same(before(k))];
		var at = 0, want = false;
		while (at < changed.length) {
			var run = 0;
			while (at < changed.length && changed[at] == want) {
				run++;
				at++;
			}
			o.uint(run);
			want = !want;
		}
		for (i => k in kept)
			if (changed[i]) {
				var a = before(k), b = cur[k];
				for (j in 0...b.values.length)
					o.step(a.values[j], b.values[j]);
			}
		for (k in p...cur.length - s) {
			var r = cur[k];
			o.uint(r.op);
			o.uint(r.ints.length);
			o.ints.add(r.ints);
			o.uint(r.slots.length);
			for (j in 0...r.slots.length) {
				o.uint(r.slots[j]);
				o.float(r.slots[j], r.values[j]);
			}
		}
		return o.bytes();
	}

	// the deltas as each frame's records again (FrameStreams.of: its streams)
	public static function decode(deltas:Array<Bytes>):Array<Array<FrameRec>> {
		var out = [], prev:Array<FrameRec> = [];
		for (i => d in deltas) {
			if (i % KEY == 0) prev = [];
			var r = new FrameInput(d);
			var p = Std.int(r.uint()), s = Std.int(r.uint()), dropped = Std.int(r.uint()), added = Std.int(r.uint());
			if (p + s + dropped != prev.length) throw "FrameLoop: a frame not of the last";
			var kept = p + s, changed = [];
			var want = false;
			while (changed.length < kept) {
				for (_ in 0...Std.int(r.uint()))
					changed.push(want);
				want = !want;
			}
			var cur:Array<FrameRec> = [];
			function keep(a:FrameRec, change:Bool) {
				if (!change) {
					cur.push(a);
					return;
				}
				var b = new FrameRec(a.op, a.ints);
				for (j in 0...a.slots.length) {
					b.slots.push(a.slots[j]);
					b.values.push(r.step(a.values[j]));
				}
				cur.push(b);
			}
			for (k in 0...p)
				keep(prev[k], changed[k]);
			var tail = [for (k in 0...s) prev[prev.length - s + k]];
			// (the kept end's steps come after the start's, before the added ops)
			var ends = [];
			for (k in 0...s) {
				keep(tail[k], changed[p + k]);
				ends.push(cur.pop());
			}
			for (_ in 0...added) {
				var b = new FrameRec(Std.int(r.uint()), r.raw(Std.int(r.uint())));
				for (_ in 0...Std.int(r.uint())) {
					var slot = Std.int(r.uint());
					b.slots.push(slot);
					b.values.push(r.float(slot));
				}
				cur.push(b);
			}
			for (e in ends)
				cur.push(e);
			out.push(cur);
			prev = cur;
		}
		return out;
	}
}
