package helder.image;

import haxe.io.Bytes;

// An image's pixels: RGBA8, rows top to bottom, straight (not
// premultiplied) alpha. decode reads a PNG file (PngDecoder), a JPEG
// (JpegDecoder), a GIF (GifDecoder) or a WebP (WebpDecoder); renderers
// (helder.ui's ImageNode, a texture: helder.gfx.ImageTexture) upload it
// once (id: their key) and again after changed(); replace(other) puts
// another image's pixels in this one (helder.asset's reload: what shows it
// shows the new one).
//
// Its pixels are dropped once a renderer uploaded them (uploaded()), when
// it can have them again: from the file it was decoded from (source), or
// in a browser from the file the browser decoded (browser images:
// helder.asset's with decodeInBrowser, never in the module's memory unless
// read). Reading pixels after that decodes the file again, on the calling
// thread; retain keeps them, for an image whose pixels are read back (a
// hit test's alpha, a picker's colours).
//
// With hxmc its pixels may be off the collected heap (held: a job's
// decode, ImageJobs), freed once uploaded or when the image is collected.
// On iOS and Android 11 and later the system decodes all but PNGs
// (SystemDecoder: ImageIO, AImageDecoder): decode reads the file's size only, its pixels decoded where they are first used (an
// upload, premultiplied as the system draws them) and dropped after, so an
// image's pixels are never on the heap unless read.
class Image {
	public var width(default, null):Int;
	public var height(default, null):Int;
	// (decoded again from the file when they were dropped)
	public var pixels(get, never):Bytes;
	// whether its pixels are here now (not to be decoded again)
	public var hasPixels(get, never):Bool;
	// keeps its pixels after an upload (they are read back)
	public var retain = false;
	// on the web, files read by helder.asset (Asset.image) decoded by the
	// browser and uploaded from there (helder.gfx.ImageTexture): their pixels
	// never in the module's memory; set before the loads start
	public static var decodeInBrowser = false;
	// (the browser's decoded image: helder_image's handle, 0 none; and
	// whether its pixels are premultiplied)
	@:noCompletion public var browser(default, null) = 0;
	@:noCompletion public var browserPremultiplied(default, null) = false;
	// (a texture another process shares: helder.gfx's Device.openShared's
	// handle, a renderer drawing it as it is, its pixels never here:
	// helder.story's native preview host's frames in the studio; null none)
	@:noCompletion public var shared(default, null):Null<String> = null;
	// (a shared image: the frames a renderer drew it in, counted, for whoever
	// draws into it again to know the GPU is done with what it showed before)
	@:noCompletion public var drawn = 0;
	var data:Null<Bytes>;
	#if (target.name == "hxmc")
	// (pixels off the heap, premultiplied or not: a job's)
	var held:Null<hxmc.Buffer> = null;
	var heldPremultiplied = false;
	#end
	// unique per image (a renderer's texture cache key)
	public final id:Int = nextId++;
	// bumped by changed(): the pixels were written to
	public var version(default, null) = 0;
	// the file it was decoded from (decode; type "png", "jpeg", "gif" or
	// "webp"), kept for a writer to embed as it is (a PDF's JPEG); null once
	// its pixels change, or when it was made from pixels
	public var source(default, null):Null<{bytes:Bytes, type:String}> = null;
	// what it was rendered from, for a writer to draw as vectors (helder.canvas's
	// Svg.render: {svg:Svg, color:Int}, an icon in its colour); null
	// once its pixels change
	@:allow(helder.canvas.Svg) public var drawing(default, null):Null<Any> = null;

	static var nextId = 1;

	public function new(width:Int, height:Int, ?pixels:Bytes) {
		if (width <= 0 || height <= 0) throw "Image: an empty size";
		if (pixels != null && pixels.length != width * height * 4) throw "Image: " + pixels.length + " bytes for " + width + "x" + height;
		this.width = width;
		this.height = height;
		this.data = pixels == null ? Bytes.alloc(width * height * 4) : pixels;
	}

	// an image the browser decoded (helder_image's handle: its file and
	// pixels there), of that size: no pixels here until they are read
	@:noCompletion public static function ofBrowser(handle:Int, width:Int, height:Int, premultiplied:Bool):Image {
		var img = new Image(1, 1, Bytes.alloc(4));
		img.width = width;
		img.height = height;
		img.data = null;
		img.browser = handle;
		img.browserPremultiplied = premultiplied;
		return img;
	}

	// an image of another process's texture (helder.gfx's shared handle), of
	// that size in pixels: no pixels here; a renderer opens the texture
	// (Device.openShared) and draws it, premultiplied as it is
	@:noCompletion public static function ofShared(handle:String, width:Int, height:Int):Image {
		var img = new Image(1, 1, Bytes.alloc(4));
		img.width = width;
		img.height = height;
		img.data = null;
		img.shared = handle;
		return img;
	}

	// an image of pixels off the heap that it owns from now on (RGBA8,
	// premultiplied or straight), freed once uploaded or collected
	#if (target.name == "hxmc")
	@:noCompletion public static function ofHeld(width:Int, height:Int, pixels:hxmc.Buffer, premultiplied:Bool):Image {
		var img = sized(width, height);
		img.hold(pixels, premultiplied);
		return img;
	}

	@:hxmc.unsafe(gc) function hold(pixels:hxmc.Buffer, premultiplied:Bool) {
		if (held == null) hxmc.NativeGc.finalise(drop, this);
		held = pixels;
		heldPremultiplied = premultiplied;
	}

	static function drop(img:Image)
		img.free();

	function free() {
		var h = held;
		held = null;
		if (h != null) h.close();
	}
	#end

	// (no pixels yet: sized only)
	static function sized(width:Int, height:Int):Image {
		var img = new Image(1, 1, Bytes.alloc(4));
		img.width = width;
		img.height = height;
		img.data = null;
		return img;
	}

	function get_hasPixels()
		return data != null #if (target.name == "hxmc") || held != null #end;

	function get_pixels():Bytes {
		if (data != null) return data;
		#if (target.name == "hxmc")
		if (held != null) {
			// (a copy on the heap, straight: what is read may be written, and outlives the upload)
			var n = width * height * 4, px = Bytes.alloc(n);
			held.blitToBytes(0, px, 0, n);
			if (heldPremultiplied) unpremultiply(px);
			free();
			return data = px;
		}
		#end
		#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64" || hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		if (source != null && source.type != "png" && SystemDecoder.available()) {
			var px:Null<Bytes> = null;
			system(source.bytes, (w, h, pre) -> {
				px = Bytes.alloc(w * h * 4);
				px.blit(0, pre, 0, w * h * 4);
				unpremultiply(px);
			});
			return data = px;
		}
		#end
		var file = source != null ? source.bytes : browserFile();
		if (file == null && shared != null) throw "Image: a texture of another process's (shared), its pixels not here";
		if (file == null) throw "Image: its pixels were dropped and it has no file to decode them from";
		var d = decode(file);
		if (d.width != width || d.height != height) throw "Image: its file is not of its size";
		return data = d.data;
	}

	// (a browser image's file, copied into the module)
	function browserFile():Null<Bytes>
		return browser != 0 && browserImages != null ? browserImages.file(browser) : null;

	// (helder_image's functions, given by what makes browser images:
	// helder.asset's ImageAsset; a program without them imports none)
	@:noCompletion public static var browserImages:Null<{file:Int->Bytes, close:Int->Void}> = null;

	// a renderer uploaded it: its pixels dropped unless retain or they could
	// not come back (no file); a browser image's decoded pixels closed (its
	// file kept)
	public function uploaded() {
		if (retain) return;
		#if (target.name == "hxmc")
		if (held != null && (source != null || browser != 0)) free();
		#end
		if (data != null && (source != null || browser != 0)) data = null;
		if (browser != 0 && browserImages != null) browserImages.close(browser);
	}

	// the width and height a PNG, JPEG, GIF or WebP file says (its header),
	// null when it is none of those or its header is cut short
	public static function size(b:Bytes, offset = 0, length = -1):Null<{width:Int, height:Int}> {
		var n = length < 0 ? b.length - offset : length;
		if (offset < 0 || n < 0 || offset > b.length - n) return null;
		// (a read past the range: cut short, null)
		return try header(b, offset, n) catch (e:ImageError) null;
	}

	static function header(b:Bytes, o:Int, n:Int):Null<{width:Int, height:Int}> {
		var r = new ByteReader(b);
		inline function u8(i:Int)
			return i < n ? r.u8(o + i) : cut();
		inline function be16(i:Int)
			return (u8(i) << 8) | u8(i + 1);
		inline function le16(i:Int)
			return u8(i) | (u8(i + 1) << 8);
		if (n >= 24 && u8(0) == 0x89 && u8(1) == 0x50 && u8(2) == 0x4E && u8(3) == 0x47)
			return {width: (be16(16) << 16) | be16(18), height: (be16(20) << 16) | be16(22)};
		if (n >= 10 && u8(0) == 0x47 && u8(1) == 0x49 && u8(2) == 0x46)
			return {width: le16(6), height: le16(8)};
		if (n >= 30 && u8(0) == 0x52 && u8(1) == 0x49 && u8(8) == 0x57 && u8(9) == 0x45) {
			var c = r.string(o + 12, 4);
			if (c == "VP8X") return {width: 1 + (u8(24) | (u8(25) << 8) | (u8(26) << 16)), height: 1 + (u8(27) | (u8(28) << 8) | (u8(29) << 16))};
			if (c == "VP8L") {
				var v = u8(21) | (u8(22) << 8) | (u8(23) << 16) | (u8(24) << 24);
				return {width: (v & 0x3FFF) + 1, height: ((v >> 14) & 0x3FFF) + 1};
			}
			if (c == "VP8 ") return {width: le16(26) & 0x3FFF, height: le16(28) & 0x3FFF};
			return null;
		}
		if (n >= 4 && u8(0) == 0xFF && u8(1) == 0xD8) {
			var size = JpegDecoder.size(b, o, n);
			return size == null || !Exif.swaps(Exif.jpegOrientation(b, o, n)) ? size : {width: size.height, height: size.width};
		}
		return null;
	}

	static function cut():Int
		throw ImageError.corrupt("cut short");

	// a PNG, JPEG, GIF or WebP file's image (by its signature); on iOS any
	// format but PNG (helder's, exact everywhere: iOS's ImageIO premultiplies
	// an indexed PNG's alpha twice) its size only, decoded where its pixels
	// are used (SystemDecoder), any format ImageIO reads
	public static function decode(bytes:Bytes):Image {
		var type = typeOf(bytes);
		#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64" || hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		if (!isPng(bytes) && SystemDecoder.available()) {
			var s = size(bytes);
			var img = if (s != null) sized(s.width, s.height) else {
				var d = null;
				system(bytes, (w, h, _) -> d = {width: w, height: h});
				sized(d.width, d.height);
			}
			ImageLimits.check("Image", img.width, img.height, 4);
			img.source = {bytes: bytes, type: type};
			return img;
		}
		#end
		#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		var d = PngDecoder.decode(bytes);
		#else
		var d = switch type {
			case "jpeg": JpegDecoder.decode(bytes);
			case "gif": GifDecoder.decode(bytes);
			case "webp": WebpDecoder.decode(bytes);
			case _: PngDecoder.decode(bytes);
		}
		#end
		var img = new Image(d.width, d.height, d.rgba);
		img.source = {bytes: bytes, type: type};
		return img;
	}

	// (a PNG's signature)
	public static function isPng(b:Bytes):Bool {
		var r = new ByteReader(b);
		return r.length >= 8 && r.u8(0) == 0x89 && r.u8(1) == 0x50 && r.u8(2) == 0x4E && r.u8(3) == 0x47;
	}

	// a file's type by its signature: "jpeg", "gif", "webp", else "png"
	public static function typeOf(bytes:Bytes):String {
		var r = new ByteReader(bytes);
		return r.length >= 2 && r.u8(0) == 0xFF && r.u8(1) == 0xD8 ? "jpeg" : r.length >= 4 && r.string(0, 4) == "GIF8" ? "gif" : r.length >= 12
			&& r.string(0, 4) == "RIFF" && r.string(8, 4) == "WEBP" ? "webp" : "png";
	}

	// other's pixels and size in this image (its source too): renderers
	// upload them again, at the new size
	public function replace(other:Image) {
		width = other.width;
		height = other.height;
		data = other.data;
		#if (target.name == "hxmc")
		free();
		if (other.held != null) {
			hold(other.held, other.heldPremultiplied);
			// (moved: the other image no longer frees it)
			other.held = null;
		}
		#end
		version++;
		source = other.source;
		drawing = other.drawing;
		browser = other.browser;
		browserPremultiplied = other.browserPremultiplied;
		shared = other.shared;
	}

	// its pixels premultiplied by their alpha, for `use` only (an upload:
	// a texture's data, copied there and then): with hxmc in a buffer off
	// the collected heap, freed after, so that a large image's upload leaves
	// no garbage of its size (on WebAssembly the heap's memory, grown for
	// it, is never given back)
	@:hxmc.unsafe(gc) public function premultiplied(use:Bytes->Void) {
		#if (target.name == "hxmc")
		if (held != null && heldPremultiplied) return use(@:privateAccess held.io.view());
		#end
		#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64" || hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		if (data == null && held == null && source != null && source.type != "png" && SystemDecoder.available()) {
			var me = this;
			return system(source.bytes, (w, h, pre) -> {
				// (a file whose orientation the header did not say: the size the system decoded)
				me.width = w;
				me.height = h;
				use(pre);
			});
		}
		#end
		var px = #if (target.name == "hxmc") held != null ? @:privateAccess held.io.view() : #end pixels, n = width * height;
		#if (target.name == "hxmc")
		var buf = hxmc.unsafe.IoBuffer.alloc(n * 4), pre = buf.view();
		#else
		var pre = Bytes.alloc(n * 4);
		#end
		for (k in 0...n) {
			var a = px.get(4 * k + 3);
			pre.set(4 * k, Std.int((px.get(4 * k) * a + 127) / 255));
			pre.set(4 * k + 1, Std.int((px.get(4 * k + 1) * a + 127) / 255));
			pre.set(4 * k + 2, Std.int((px.get(4 * k + 2) * a + 127) / 255));
			pre.set(4 * k + 3, a);
		}
		#if (target.name == "hxmc")
		try use(pre) catch (e:Dynamic) {
			buf.free();
			throw e;
		}
		buf.free();
		#else
		use(pre);
		#end
	}

	#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64" || hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
	// the file decoded by the system, its premultiplied pixels lent to use
	// (a copy of the file in native memory first: the collector moves Bytes)
	@:hxmc.unsafe(gc) static function system(file:Bytes, use:(Int, Int, Bytes) -> Void) {
		var copy = hxmc.unsafe.IoBuffer.alloc(file.length);
		copy.view().blit(0, file, 0, file.length);
		var d = try SystemDecoder.decode(copy.ptr, file.length) catch (e:Dynamic) {
			copy.free();
			throw e;
		}
		copy.free();
		try use(d.width, d.height, d.pixels.view()) catch (e:Dynamic) {
			d.pixels.free();
			throw e;
		}
		d.pixels.free();
	}
	#end

	// straight alpha again: a premultiplied pixel's colour divided by its alpha
	static function unpremultiply(px:Bytes) {
		for (k in 0...px.length >> 2) {
			var a = px.get(4 * k + 3);
			if (a == 0 || a == 255) continue;
			for (c in 0...3)
				px.set(4 * k + c, Std.int(Math.min(255, (px.get(4 * k + c) * 255 + (a >> 1)) / a)));
		}
	}

	// the pixels changed: renderers upload them again
	public function changed() {
		if (data == null) get_pixels();
		version++;
		browser = 0;
		shared = null;
		source = null;
		drawing = null;
	}

	// a pixel of src at s over one of dst at d (RGBA8, straight alpha): the
	// source's colour weighted by its alpha, the destination's by what of its
	// alpha shows through (an APNG's frames, an icon on its background)
	public static function over(dst:Bytes, d:Int, src:Bytes, s:Int) {
		var sa = src.get(s + 3);
		if (sa == 0) return;
		var da = dst.get(d + 3);
		if (sa == 255 || da == 0) {
			dst.blit(d, src, s, 4);
			return;
		}
		var keep = da * (255 - sa), a = sa * 255 + keep;
		for (c in 0...3)
			dst.set(d + c, Std.int((src.get(s + c) * sa * 255 + dst.get(d + c) * keep + (a >> 1)) / a));
		dst.set(d + 3, Std.int((a + 127) / 255));
	}
}
