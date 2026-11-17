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

#end
