package helder.media;

// Packets of a contiguous stretch of the file, per track: MP4's are all in
// one; Matroska's grow a cluster at a time from where a seek landed, and
// two that meet become one (into: the run it went into, shift: the rows
// each track had there before).
class Run {
	public final start:Float;
	// where the next cluster to read is; -1 when nothing follows
	public var end:Float;
	public final samples:Array<Samples>;
	public var into:Null<Run> = null;
	public var shift:Array<Int> = [];

	public function new(start:Float, end:Float, tracks:Int) {
		this.start = start;
		this.end = end;
		samples = [for (_ in 0...tracks) new Samples()];
	}
}
