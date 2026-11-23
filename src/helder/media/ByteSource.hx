package helder.media;

import haxe.io.Bytes;

// A file's bytes at any offset, awaited: what the demuxers read, a box or
// a cluster at a time, never the whole file. read puts at most len bytes
// at offset into b from pos and returns how many (fewer only at the end,
// 0 past it); size is the bytes in all, -1 while not known.
interface ByteSource {
	var size(get, never):Float;
	@:coroutine function read(offset:Float, b:Bytes, pos:Int, len:Int):Int;
	function close():Void;
}
