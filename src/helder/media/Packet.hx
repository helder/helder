package helder.media;

// A compressed frame of a track (an audio packet: several of its frames),
// its bytes in the source until Media.read: offset and size there, its
// times in the track's ticks (MediaTrack.timescale) and seconds.
class Packet {
	public final track:MediaTrack;
	public final offset:Float;
	public final size:Int;
	// decode and presentation times, its duration: ticks
	public final dts:Float;
	public final pts:Float;
	public final duration:Float;
	// decoding can start here
	public final key:Bool;

	// seconds: when it shows, when it is decoded, when it ends
	public var time(get, never):Float;
	public var decodeTime(get, never):Float;
	public var end(get, never):Float;

	@:allow(helder.media)
	function new(track, offset, size, dts, pts, duration, key) {
		this.track = track;
		this.offset = offset;
		this.size = size;
		this.dts = dts;
		this.pts = pts;
		this.duration = duration;
		this.key = key;
	}

	function get_time()
		return pts / track.timescale;

	function get_decodeTime()
		return dts / track.timescale;

	function get_end()
		return (pts + duration) / track.timescale;
}
