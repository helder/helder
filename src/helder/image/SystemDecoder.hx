package helder.image;

#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
import coregraphics.CGContext;
import coregraphics.CGImage;
import coregraphics.CGPoint;
import coregraphics.CGRect;
import coregraphics.CGSize;
import coregraphics.CoreGraphics as CG;
import foundation.NSData;
import foundation.NSMutableDictionary;
import foundation.NSNumber;
import foundation.NSString;
import hxmc.I64;
import hxmc.objc.AutoreleasePool;
import hxmc.objc.Id;
import hxmc.unsafe.IoBuffer;
import hxmc.unsafe.Ptr;
import imageio.CGImageSource;
import imageio.ImageIO;

// iOS's image decoders (ImageIO): what the system reads (JPEG, GIF's first
// frame, WebP, HEIC; PNGs are helder's, Image.decode), upright (EXIF's orientation applied), drawn
// into premultiplied RGBA8 in sRGB, off the collected heap: what a texture
// takes, uploaded as it is. A file in native memory (a job's, or a copy:
// the collector moves Bytes), decoded on a job's thread (ImageJobs.decode)
// or the caller's (Image's pixels again once dropped). ImageLimits is
// checked on the size the file says, before a pixel is decoded; the decode
// and the drawing run in a safe region (as every extern call not
// @:hxmc.fast does), so other threads' collections never wait for them.
@:hxmc.unsafe(gc) class SystemDecoder {
	public static inline function available():Bool
		return true;

	public static function decode(file:Ptr, length:Int):{width:Int, height:Int, pixels:IoBuffer} {
		var out = null;
		AutoreleasePool.run(() -> out = image(file, length));
		return out;
	}

	static function image(file:Ptr, length:Int):{width:Int, height:Int, pixels:IoBuffer} {
		var src = ImageIO.CGImageSourceCreateWithData(NSData.dataWithBytesNoCopy(file, length, false), null);
		if (src == null) throw ImageError.unsupported("SystemDecoder: not an image ImageIO reads");
		var props = ImageIO.CGImageSourceCopyPropertiesAtIndex(src, 0, null);
		if (props == null) throw ImageError.corrupt("SystemDecoder: no image in it");
		inline function int(key:NSString):Int {
			var v = props.objectForKey(key);
			return v == null ? 0 : (cast v : NSNumber).integerValue.toInt();
		}
		var w = int(ImageIO.kCGImagePropertyPixelWidth), h = int(ImageIO.kCGImagePropertyPixelHeight);
		if (w <= 0 || h <= 0) throw ImageError.corrupt("SystemDecoder: no size");
		ImageLimits.check("SystemDecoder", w, h, 4);
		var opts:NSMutableDictionary<Id, Id> = NSMutableDictionary.dictionary();
		opts.setObject(NSNumber.numberWithBool(true), ImageIO.kCGImageSourceShouldCacheImmediately);
		var o = int(ImageIO.kCGImagePropertyOrientation);
		// (turned or mirrored: a thumbnail of the whole at its own size, the one call that applies
		// the orientation; else the image itself, as a thumbnail of an indexed PNG with alpha comes
		// premultiplied twice)
		if (o > 1) {
			opts.setObject(NSNumber.numberWithBool(true), ImageIO.kCGImageSourceCreateThumbnailFromImageAlways);
			opts.setObject(NSNumber.numberWithBool(true), ImageIO.kCGImageSourceCreateThumbnailWithTransform);
			opts.setObject(NSNumber.numberWithInteger(w > h ? w : h), ImageIO.kCGImageSourceThumbnailMaxPixelSize);
		}
		var img = o > 1 ? ImageIO.CGImageSourceCreateThumbnailAtIndex(src, 0, opts) : ImageIO.CGImageSourceCreateImageAtIndex(src, 0, opts);
		if (img == null) throw ImageError.corrupt("SystemDecoder: ImageIO cannot decode it");
		var pw = CG.CGImageGetWidth(img).toInt(), ph = CG.CGImageGetHeight(img).toInt();
		// (zeroed: an image with alpha is drawn over what the bitmap holds)
		var pixels = IoBuffer.alloc(pw * ph * 4);
		// (kCGImageAlphaPremultipliedLast: R G B A)
		var ctx = CG.CGBitmapContextCreate(pixels.ptr, pw, ph, 8, pw * 4, CG.CGColorSpaceCreateWithName(CG.kCGColorSpaceSRGB), cast 1);
		if (ctx == null) {
			pixels.free();
			throw ImageError.unsupported("SystemDecoder: no bitmap context");
		}
		CG.CGContextDrawImage(ctx, new CGRect(new CGPoint(0, 0), new CGSize(pw, ph)), img);
		return {width: pw, height: ph, pixels: pixels};
	}
}
#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
import hxmc.unsafe.Arena;
import hxmc.unsafe.IoBuffer;
import hxmc.unsafe.Ptr;

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
			throw e;
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
