package helder.image;

#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
import helder.os.apple.objc.CGRect;
import helder.os.apple.objc.Runtime;
import hxmc.unsafe.Arena;
import hxmc.unsafe.IoBuffer;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Posix;
import hxmc.unsafe.Ptr;

// iOS's image decoders (ImageIO): what the system reads (JPEG, GIF's first
// frame, WebP, HEIC; PNGs are helder's, Image.decode), upright (EXIF's orientation applied), drawn
// into premultiplied RGBA8 in sRGB, off the collected heap: what a texture
// takes, uploaded as it is. A file in native memory (a job's, or a copy:
// the collector moves Bytes), decoded on a job's thread (ImageJobs.decode)
// or the caller's (Image's pixels again once dropped). ImageLimits is
// checked on the size the file says, before a pixel is decoded; the decode
// and the drawing run in a safe region (as every extern call not
// @:hxmc.fast does), so other threads' collections never wait for them.
// ImageIO, Core Foundation and Core Graphics are C: what is made here is
// released here (the Create rule), in an autorelease pool for what ImageIO
// autoreleases on a job's thread.
@:hxmc.unsafe(gc) class SystemDecoder {
	public static inline function available():Bool
		return true;

	public static function decode(file:Ptr, length:Int):{width:Int, height:Int, pixels:IoBuffer} {
		var pool = Runtime.objc_autoreleasePoolPush();
		try {
			var out = image(file, length);
			Runtime.objc_autoreleasePoolPop(pool);
			return out;
		} catch (e:haxe.Exception) {
			Runtime.objc_autoreleasePoolPop(pool);
			throw helder.async.Errors.kept(e);
		}
	}

	// a constant of the frameworks': a CFStringRef (the symbol's value) or,
	// given by address, a struct (the dictionary callbacks)
	static inline function constant(name:String):Ptr {
		var p:Ptr<Ptr> = cast Posix.dlsym(Ptr.ofI64(-2), Mem.cstr(name));
		return p.isNull() ? Ptr.nil() : p.value;
	}

	static inline function address(name:String):Ptr
		return Posix.dlsym(Ptr.ofI64(-2), Mem.cstr(name));

	static function image(file:Ptr, length:Int):{width:Int, height:Int, pixels:IoBuffer} {
		var made:Array<Ptr> = [];
		inline function keep(p:Ptr):Ptr {
			if (!p.isNull()) made.push(p);
			return p;
		}
		function release() {
			for (p in made) CF.CFRelease(p);
			made = [];
		}
		try {
			// (kCFAllocatorNull: the bytes are the caller's, not freed)
			var data = keep(CF.CFDataCreateWithBytesNoCopy(Ptr.nil(), file, length, constant("kCFAllocatorNull")));
			var src = keep(IO.CGImageSourceCreateWithData(data, Ptr.nil()));
			if (src.isNull()) throw ImageError.unsupported("SystemDecoder: not an image ImageIO reads");
			var props = keep(IO.CGImageSourceCopyPropertiesAtIndex(src, 0, Ptr.nil()));
			if (props.isNull()) throw ImageError.corrupt("SystemDecoder: no image in it");
			function int(key:Ptr):Int {
				var v = CF.CFDictionaryGetValue(props, key);
				if (v.isNull()) return 0;
				return Arena.scopedValue(a -> {
					var n:Ptr<hxmc.I64> = cast a.alloc(8);
					// (kCFNumberSInt64Type)
					CF.CFNumberGetValue(v, 4, n) ? n.value.toInt() : 0;
				});
			}
			var w = int(constant("kCGImagePropertyPixelWidth")), h = int(constant("kCGImagePropertyPixelHeight"));
			if (w <= 0 || h <= 0) throw ImageError.corrupt("SystemDecoder: no size");
			ImageLimits.check("SystemDecoder", w, h, 4);
			var opts = keep(CF.CFDictionaryCreateMutable(Ptr.nil(), 0, address("kCFTypeDictionaryKeyCallBacks"), address("kCFTypeDictionaryValueCallBacks")));
			var yes = constant("kCFBooleanTrue");
			CF.CFDictionarySetValue(opts, constant("kCGImageSourceShouldCacheImmediately"), yes);
			var o = int(constant("kCGImagePropertyOrientation"));
			// (turned or mirrored: a thumbnail of the whole at its own size, the one call that applies
			// the orientation; else the image itself, as a thumbnail of an indexed PNG with alpha comes
			// premultiplied twice)
			if (o > 1) {
				CF.CFDictionarySetValue(opts, constant("kCGImageSourceCreateThumbnailFromImageAlways"), yes);
				CF.CFDictionarySetValue(opts, constant("kCGImageSourceCreateThumbnailWithTransform"), yes);
				var side = Arena.scopedValue(a -> {
					var n:Ptr<hxmc.I64> = cast a.alloc(8);
					n.value = w > h ? w : h;
					CF.CFNumberCreate(Ptr.nil(), 4, n);
				});
				CF.CFDictionarySetValue(opts, constant("kCGImageSourceThumbnailMaxPixelSize"), keep(side));
			}
			var img = keep(o > 1 ? IO.CGImageSourceCreateThumbnailAtIndex(src, 0, opts) : IO.CGImageSourceCreateImageAtIndex(src, 0, opts));
			if (img.isNull()) throw ImageError.corrupt("SystemDecoder: ImageIO cannot decode it");
			var pw = CG.CGImageGetWidth(img).toInt(), ph = CG.CGImageGetHeight(img).toInt();
			// (zeroed: an image with alpha is drawn over what the bitmap holds)
			var pixels = IoBuffer.alloc(pw * ph * 4);
			var space = keep(CG.CGColorSpaceCreateWithName(constant("kCGColorSpaceSRGB")));
			// (kCGImageAlphaPremultipliedLast: R G B A)
			var ctx = keep(CG.CGBitmapContextCreate(pixels.ptr, pw, ph, 8, pw * 4, space, 1));
			if (ctx.isNull()) {
				pixels.free();
				throw ImageError.unsupported("SystemDecoder: no bitmap context");
			}
			Arena.scoped(a -> {
				var r = a.make(CGRect);
				r.value.size.width = pw;
				r.value.size.height = ph;
				CG.CGContextDrawImage(ctx, r.value, img);
			});
			release();
			return {width: pw, height: ph, pixels: pixels};
		} catch (e:haxe.Exception) {
			release();
			throw helder.async.Errors.kept(e);
		}
	}
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/ImageIO.framework/ImageIO") private extern class IO {
	static function CGImageSourceCreateWithData(data:Ptr, options:Ptr):Ptr;
	static function CGImageSourceCopyPropertiesAtIndex(src:Ptr, index:hxmc.I64, options:Ptr):Ptr;
	static function CGImageSourceCreateImageAtIndex(src:Ptr, index:hxmc.I64, options:Ptr):Ptr;
	static function CGImageSourceCreateThumbnailAtIndex(src:Ptr, index:hxmc.I64, options:Ptr):Ptr;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation") private extern class CF {
	static function CFRelease(o:Ptr):Void;
	static function CFDataCreateWithBytesNoCopy(alloc:Ptr, bytes:Ptr, length:hxmc.I64, deallocator:Ptr):Ptr;
	static function CFDictionaryGetValue(d:Ptr, key:Ptr):Ptr;
	static function CFDictionaryCreateMutable(alloc:Ptr, capacity:hxmc.I64, keys:Ptr, values:Ptr):Ptr;
	static function CFDictionarySetValue(d:Ptr, key:Ptr, value:Ptr):Void;
	static function CFNumberGetValue(n:Ptr, type:hxmc.I64, out:Ptr):Bool;
	static function CFNumberCreate(alloc:Ptr, type:hxmc.I64, value:Ptr):Ptr;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics") private extern class CG {
	static function CGImageGetWidth(img:Ptr):hxmc.I64;
	static function CGImageGetHeight(img:Ptr):hxmc.I64;
	static function CGColorSpaceCreateWithName(name:Ptr):Ptr;
	static function CGBitmapContextCreate(data:Ptr, w:hxmc.I64, h:hxmc.I64, bits:hxmc.I64, stride:hxmc.I64, space:Ptr, info:Int):Ptr;
	static function CGContextDrawImage(ctx:Ptr, rect:CGRect, img:Ptr):Void;
}
#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
import hxmc.unsafe.Arena;
import hxmc.unsafe.IoBuffer;
import hxmc.unsafe.Ptr;
import helder.async.Errors;

// Android's image decoders (AImageDecoder, Android 11: libjnigraphics,
// loaded when first asked, helder.os.Dl; Android 10 has none: available()
// false, helder.image's decoders): JPEG, GIF's first frame, WebP, HEIF
// (PNGs are helder's, Image.decode), upright (EXIF's orientation
// applied), into premultiplied RGBA8 in sRGB off the collected heap, as
// iOS's. ImageLimits is checked on the size the file says, before a pixel
// is decoded; the decode runs in a safe region (Dl's calls).
@:hxmc.unsafe(gc) class SystemDecoder {
	static var ready = 0;

	public static function available():Bool {
		if (ready == 0) ready = AImageDecoder.load("libjnigraphics.so") == null ? 1 : -1;
		return ready > 0;
	}

	public static function decode(file:Ptr, length:Int):{width:Int, height:Int, pixels:IoBuffer} {
		if (!available()) throw ImageError.unsupported("SystemDecoder: no AImageDecoder (Android 11)");
		var out:Ptr<Ptr> = Arena.scopedValue(a -> {
			var p:Ptr<Ptr> = cast a.alloc(8);
			p.value = Ptr.nil();
			var r = AImageDecoder.AImageDecoder_createFromBuffer(file, length, cast p);
			r == 0 ? p.value : Ptr.nil();
		});
		var d:Ptr = cast out;
		if (d.isNull()) throw ImageError.unsupported("SystemDecoder: not an image AImageDecoder reads");
		var info = AImageDecoder.AImageDecoder_getHeaderInfo(d);
		var w = AImageDecoder.AImageDecoderHeaderInfo_getWidth(info), h = AImageDecoder.AImageDecoderHeaderInfo_getHeight(info);
		try ImageLimits.check("SystemDecoder", w, h, 4) catch (e:ImageError) {
			AImageDecoder.AImageDecoder_delete(d);
			throw Errors.kept(e);
		}
		// (RGBA_8888, premultiplied as decoded by default; in sRGB: ADATASPACE_SRGB)
		AImageDecoder.AImageDecoder_setAndroidBitmapFormat(d, 1);
		AImageDecoder.AImageDecoder_setDataSpace(d, 142671872);
		var stride = AImageDecoder.AImageDecoder_getMinimumStride(d).toInt();
		if (stride != w * 4) {
			AImageDecoder.AImageDecoder_delete(d);
			throw ImageError.unsupported("SystemDecoder: rows of " + stride + " bytes for " + w + " pixels");
		}
		var pixels = IoBuffer.alloc(w * h * 4);
		// (INCOMPLETE, -1: a file cut short, what it had drawn, as browsers show it)
		var r = AImageDecoder.AImageDecoder_decodeImage(d, pixels.ptr, (stride : hxmc.I64), ((w * h * 4) : hxmc.I64));
		AImageDecoder.AImageDecoder_delete(d);
		if (r != 0 && r != -1) {
			pixels.free();
			throw ImageError.corrupt("SystemDecoder: AImageDecoder cannot decode it (" + r + ")");
		}
		return {width: w, height: h, pixels: pixels};
	}
}

@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
private class AImageDecoder {
	static function AImageDecoder_createFromBuffer(buffer:Ptr, length:hxmc.I64, out:Ptr):Int;
	static function AImageDecoder_getHeaderInfo(d:Ptr):Ptr;
	static function AImageDecoderHeaderInfo_getWidth(info:Ptr):Int;
	static function AImageDecoderHeaderInfo_getHeight(info:Ptr):Int;
	static function AImageDecoder_setAndroidBitmapFormat(d:Ptr, format:Int):Int;
	static function AImageDecoder_setDataSpace(d:Ptr, space:Int):Int;
	static function AImageDecoder_getMinimumStride(d:Ptr):hxmc.I64;
	static function AImageDecoder_decodeImage(d:Ptr, pixels:Ptr, stride:hxmc.I64, size:hxmc.I64):Int;
	static function AImageDecoder_delete(d:Ptr):Void;
}
#end
