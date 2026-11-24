package helder.media;

import haxe.io.Bytes;

// A system's video decoder (Decoders.video): packets in decode order, the
// pictures out as they come (take; in presentation order once sorted by
// time: frames reorder). show false: decoded for the frames after it, not
// output (before an exact seek's target).
interface VideoDecoder {
	function decode(p:Packet, bytes:Bytes, show:Bool):Void;
	function take(into:Array<VideoFrame>):Void;
	// frames given and not out yet
	var pending(get, never):Int;
	// what it holds back put out (the stream's end)
	function flush():Void;
	// what is in flight dropped (a seek)
	function reset():Void;
	function release(f:VideoFrame):Void;
	// a plane of the frame's as helder.gfx opens it (Device.openShared): luma 0, chroma 1
	function plane(f:VideoFrame, plane:Int):Null<String>;
	// its planes' pixels, rows packed: luma, then chroma's pairs (P010: 16 bits a sample)
	function pixels(f:VideoFrame):haxe.io.Bytes;
	function close():Void;
}
