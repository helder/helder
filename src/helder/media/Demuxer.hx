package helder.media;

import haxe.io.Bytes;

// What Media asks of a container's reader (Mp4, Matroska), synchronously:
// Media reads the bytes it asks for (one loop of coroutines for both). A
// walk goes from element to element: walk is given the 16 bytes at an
// offset (fewer at the end) and answers how many bytes from `body` it
// wants (take gets them; -1: none), then goes on at `next` (-1: done).
interface Demuxer {
	var tracks(default, null):Array<MediaTrack>;
	// seconds; -1 when not known
	var duration(default, null):Float;
	var body(default, null):Float;
	var next(default, null):Float;
	function walk(at:Float, head:Bytes):Int;
	function take(b:Bytes):Void;
	// the open's walk is over: its checks (a MediaError if no tracks)
	function opened():Void;
	// the run from the file's first packets
	function first():Run;
	// a run holding a keyframe of track at or before time (seconds), where there is one
	function locate(track:Int, time:Float):Run;
	// where a walk adds run's next stretch (Matroska's next cluster): -1
	// nothing follows; -2 it met the next run and took it in
	function grow(run:Run):Float;
}
