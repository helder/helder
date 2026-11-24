package helder.media;

// A decoded picture: when it shows (seconds), its size, and the system's
// image (Apple's: a CVPixelBuffer on an IOSurface, NV12 or P010 planes),
// held until release().
@:hxmc.unsafe(gc)
class VideoFrame {
	public final time:Float;
	public final width:Int;
	public final height:Int;
	// its YUV's: "601", "709" or "2020"; full range (else video range); 8 or 10 bits
	public final matrix:String;
	public final full:Bool;
	public final bits:Int;
	#if (target.name == "hxmc")
	public var image(default, null):hxmc.unsafe.Ptr;
	#end
	final owner:VideoDecoder;

	@:allow(helder.media)
	function new(owner:VideoDecoder, time:Float, width:Int, height:Int, matrix:String, full:Bool, bits:Int #if (target.name == "hxmc"), image:hxmc.unsafe.Ptr #end) {
		this.owner = owner;
		this.time = time;
		this.width = width;
		this.height = height;
		this.matrix = matrix;
		this.full = full;
		this.bits = bits;
		#if (target.name == "hxmc")
		this.image = image;
		#end
	}

	// a plane as helder.gfx opens it (Device.openShared's handle): luma 0
	// (r8, r16 at 10 bits), chroma 1 (rg8, rg16), at half the size; null: none
	public function plane(n:Int):Null<String> {
		#if (target.name == "hxmc")
		if (image.isNull()) return null;
		#end
		return owner.plane(this, n);
	}

	// its planes' pixels, copied: luma, then chroma's pairs, rows packed
	// (P010: 16 bits a sample, little-endian, the value at the top)
	public function pixels():haxe.io.Bytes
		return owner.pixels(this);

	public function release() {
		#if (target.name == "hxmc")
		if (image.isNull()) return;
		owner.release(this);
		image = hxmc.unsafe.Ptr.nil();
		#end
	}
}
