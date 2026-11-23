package helder.media;

import haxe.io.Bytes;

// (what a demuxer gathers before the track is made)
@:noCompletion class TrackInfo {
	public var index = 0;
	public var id = 0;
	public var kind = MediaKind.Other;
	public var codec = Codec.Other;
	public var tag = "";
	public var config:Null<Bytes> = null;
	public var timescale = 1000.0;
	public var duration = -1.0;
	public var width = 0;
	public var height = 0;
	public var rotation = 0;
	public var sampleRate = 0;
	public var channels = 0;
	public var bits = 0;
	public var delay = 0.0;
	public var preroll = 0.0;

	public function new() {}
}
