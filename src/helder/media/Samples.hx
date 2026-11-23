package helder.media;

// A track's packets in decode order, as columns (a long film's are
// hundreds of thousands: no object each).
class Samples {
	public final offset:Array<Float> = [];
	public final size:Array<Int> = [];
	public final dts:Array<Float> = [];
	public final pts:Array<Float> = [];
	public final duration:Array<Float> = [];
	public final key:Array<Bool> = [];
	public var length(get, never):Int;

	public function new() {}

	inline function get_length()
		return size.length;

	public function add(offset:Float, size:Int, dts:Float, pts:Float, duration:Float, key:Bool) {
		this.offset.push(offset);
		this.size.push(size);
		this.dts.push(dts);
		this.pts.push(pts);
		this.duration.push(duration);
		this.key.push(key);
	}

	public function append(s:Samples)
		for (i in 0...s.length)
			add(s.offset[i], s.size[i], s.dts[i], s.pts[i], s.duration[i], s.key[i]);

	public function packet(track:MediaTrack, i:Int):Packet
		return new Packet(track, offset[i], size[i], dts[i], pts[i], duration[i], key[i]);
}
