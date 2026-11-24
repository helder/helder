package helder.media;

import haxe.io.Bytes;

// A system's audio decoder (Decoders.audio): packets in, interleaved
// 32-bit floats out at the track's rate, two channels (mono doubled, more
// than two: the first two), into samples from 0; the frames written. One
// that decodes later (WebCodecs) gives a packet's frames at a later call:
// `decoded` is the packet the frames are of (null: none came); p null
// asks only for what came since.
interface AudioDecoder {
	final rate:Int;
	var decoded(default, null):Null<Packet>;
	function decode(p:Null<Packet>, bytes:Null<Bytes>, samples:AudioBuffer):Int;
	// (a seek: what it holds of the packets before dropped)
	function reset():Void;
	function close():Void;
}
