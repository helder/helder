package helder.ui.flow;

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
}
