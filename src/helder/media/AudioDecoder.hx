package helder.media;

import haxe.io.Bytes;

// A system's audio decoder (Decoders.audio): packets in, interleaved
// 32-bit floats out at the track's rate, two channels (mono doubled, more
// than two: the first two), into samples from 0; the frames written.
interface AudioDecoder {
	final rate:Int;
	function decode(p:Packet, bytes:Bytes, samples:AudioBuffer):Int;
	// (a seek: what it holds of the packets before dropped)
	function reset():Void;
	function close():Void;
}
