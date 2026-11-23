package helder.media;

// Where a track's decoding starts for a time (Media.seek): the keyframe
// packet, then drop frames decoded (in presentation order) are not shown,
// and the next is the target, the frame due at that time (its pts in
// seconds, time). For audio packet holds the time and drop is 0. packet
// is null for a track without packets.
@:structInit
class Seek {
	public final track:MediaTrack;
	public final packet:Null<Packet>;
	public final drop:Int;
	public final time:Float;
}
