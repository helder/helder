package helder.ui.flow;

import haxe.ds.ObjectMap;
import helder.ui.box.Box;
import helder.ui.flow.Fragmentation.Deferred;
import helder.ui.flow.Fragmentation.Resume;

// A fragmentainer's content laid out whole: where it resumes the
// fragmentainer's, no break taken in it (a box that clips, ending here: its
// content past its height clipped, not broken into fragmentainers after it).
class Unbroken implements Fragmentation {
	public var size(default, null):Float;
	final outer:Fragmentation;

	public function new(outer:Fragmentation) {
		this.outer = outer;
		size = Math.POSITIVE_INFINITY;
	}

	public var stopped(get, never):Bool;

	inline function get_stopped():Bool
		return false;

	public function resume(box:Box):Null<Resume>
		return outer.resume(box);

	public function enter(box:Box, top:Float) {}

	public function between(box:Box, before:Null<Box>, after:Box, bottom:Float):Bool
		return false;

	public function inLines(box:Box, first:Int, line:Int, count:Int, bottom:Float, at:InlineBreak):Bool
		return false;

	public function after(box:Box, bottom:Float):Bool
		return false;

	public function floated(bottom:Float) {}

	public function placed(bottom:Float) {}

	public function defer(d:Deferred)
		outer.defer(d);

	// (a parallel flow laid out whole too: where it resumes the outer's)
	public function parallel(box:Box, child:Box):Null<Breaks> {
		var r = outer.resume(box);
		if (r != null && r.parallel != null) {
			var t = r.parallel.get(child);
			return t == null ? null : new Breaks(Math.POSITIVE_INFINITY, t);
		}
		return new Breaks(Math.POSITIVE_INFINITY, null);
	}

	public function split(box:Box, tokens:ObjectMap<Box, BreakToken>, bottom:Float, ?tall:Bool):Bool
		return false;

	public function carry(float:Box, token:BreakToken)
		outer.carry(float, token);

	public function uncarry(float:Box)
		outer.uncarry(float);

	public function carried(host:Box):Array<{box:Box, token:BreakToken}>
		return outer.carried(host);
}
