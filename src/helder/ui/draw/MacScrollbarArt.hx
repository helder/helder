package helder.ui.draw;

import haxe.io.Bytes;
import helder.image.Image;
import helder.os.apple.objc.*;
import hxmc.unsafe.*;

// macOS's own scrollers drawn into the tree (Ui.scrollbarArt): an
// NSScroller of each orientation and style, never shown, draws its track
// (drawKnobSlotInRect:highlight:) and its knob (drawKnob) into a bitmap
// (a CGBitmapContext as the current NSGraphicsContext, the window's
// appearance current: light, dark, Increase Contrast's, whatever this
// macOS draws), kept as an Image for that size and appearance and drawn
// where the Ui places the thumb; its sizes are the scroller's
// (scrollerWidthForControlSize:scrollerStyle:, rectForPart:). Each is drawn
// once for its look and appearance, at a length of its own, and drawn at
// any length in three slices (its ends as they are, its middle stretched),
// so that nothing is drawn again as it scrolls, stretches or resizes.
@:hxmc.unsafe(gc)
class MacScrollbarArt implements helder.ui.ScrollbarArt {
	static inline var KNOB = 2; // NSScrollerKnob
	static inline var SLOT = 6; // NSScrollerKnobSlot
	static inline var REST = 0.45;

	// the scrollers: [vertical legacy, vertical overlay, horizontal legacy, horizontal overlay]
	final scrollers:Array<Ptr> = [];
	final rect:Ptr<CGRect> = LibC.malloc(32);
	final cache = new Map<String, Image>();
	final sizes:Array<Array<Float>> = [];

	public function new() {
		helder.os.OsThread.run(() -> {
			for (vertical in [true, false])
				for (overlay in [false, true]) {
					rect.value.origin.x = rect.value.origin.y = 0;
					rect.value.size.width = vertical ? 15 : 100;
					rect.value.size.height = vertical ? 100 : 15;
					var s = Msg.idRect(Msg.id(ObjC.cls("NSScroller"), ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), rect.value);
					Msg.vInt(s, ObjC.sel("setScrollerStyle:"), overlay ? 1 : 0);
					Msg.vBool(s, ObjC.sel("setEnabled:"), true);
					scrollers.push(s);
				}
			// (the sizes: the scroller's width, its knob's, the knob's inset from the outer edge)
			for (overlay in [false, true]) {
				var w = Msg.fIntInt(ObjC.cls("NSScroller"), ObjC.sel("scrollerWidthForControlSize:scrollerStyle:"), 0, overlay ? 1 : 0);
				var s = scroller(true, overlay);
				frame(s, true, w, 200);
				Msg.vFloat(s, ObjC.sel("setKnobProportion:"), 0.3);
				var k = Msg.rectInt(s, ObjC.sel("rectForPart:"), KNOB);
				sizes.push([w, k.size.width, w - k.origin.x - k.size.width]);
			}
		});
	}

	public function metrics(overlay:Bool):Array<Float>
		return sizes[overlay ? 1 : 0];

	inline function scroller(vertical:Bool, overlay:Bool):Ptr
		return scrollers[(vertical ? 0 : 2) + (overlay ? 1 : 0)];

	function frame(s:Ptr, vertical:Bool, across:Float, along:Float) {
		rect.value.origin.x = rect.value.origin.y = 0;
		rect.value.size.width = vertical ? across : along;
		rect.value.size.height = vertical ? along : across;
		Msg.vRect(s, ObjC.sel("setFrame:"), rect.value);
	}

	public function paint(canvas:helder.ui.Canvas, vertical:Bool, overlay:Bool, dark:Bool, scale:Float, track:Null<Array<Float>>, thumb:Array<Float>,
			pressed:Bool, alpha:Float) {
		if (alpha <= 0) return;
		if (alpha < 1) canvas.pushOpacity(alpha);
		if (track != null) {
			var img = slot(vertical, dark, scale, vertical ? track[2] : track[3]);
			if (img != null) slices(canvas, img, vertical, track, 4, scale);
		}
		// (drawKnob draws the always-shown knob as under the pointer; at rest macOS's is lighter: 0x3A of its 0x80 black, as Chromium has it)
		var across = vertical ? thumb[2] : thumb[3];
		var img = knob(vertical, overlay, dark, scale, across), rest = !overlay && !pressed;
		if (rest) canvas.pushOpacity(REST);
		if (img != null) slices(canvas, img, vertical, thumb, across / 2, scale);
		if (rest) canvas.popOpacity();
		if (alpha < 1) canvas.popOpacity();
	}

	// img drawn over r ([x, y, width, height]) in three slices along its
	// axis: its ends (cap points long, as drawn) and its middle stretched
	// (the slices meet on the screen's pixels, the ends cut at the image's
	// whole pixels and the middle stretched from its centre column: no seam
	// where two of them blend at a fraction of a pixel)
	function slices(canvas:helder.ui.Canvas, img:Image, vertical:Bool, r:Array<Float>, cap:Float, scale:Float) {
		inline function snap(v:Float):Float
			return Math.round(v * scale) / scale;
		var x = snap(r[0]), y = snap(r[1]), w = snap(r[0] + r[2]) - x, h = snap(r[1] + r[3]) - y;
		var px = drawnAt.get(img.id) ?? 1.0, size = vertical ? img.height : img.width, len = vertical ? h : w;
		var capPx = Math.min(Math.round(cap * px), Math.floor(size / 2)), c = Math.min(snap(capPx / px), snap(len / 2));
		var u = capPx / size, m0 = (Math.floor(size / 2)) / size, m1 = (Math.floor(size / 2) + 1) / size;
		if (vertical) {
			canvas.image(img, x, y, w, c, 0, 0, 1, u, 0);
			if (len > 2 * c) canvas.image(img, x, y + c, w, len - 2 * c, 0, m0, 1, m1, 0);
			canvas.image(img, x, y + len - c, w, c, 0, 1 - u, 1, 1, 0);
		} else {
			canvas.image(img, x, y, c, h, 0, 0, u, 1, 0);
			if (len > 2 * c) canvas.image(img, x + c, y, len - 2 * c, h, m0, 0, m1, 1, 0);
			canvas.image(img, x + len - c, y, c, h, 1 - u, 0, 1, 1, 0);
		}
	}

	// (each image's pixels a point, as it was drawn)
	final drawnAt = new Map<Int, Float>();

	// the track, across points thick, drawn at a length of its own
	function slot(vertical:Bool, dark:Bool, scale:Float, across:Float):Null<Image> {
		var key = 's$vertical$dark$scale ${Math.round(across)}', len = 64.0;
		var img = cache.get(key);
		if (img != null) return img;
		var s = scroller(vertical, false), w = vertical ? across : len, h = vertical ? len : across;
		frame(s, vertical, across, len);
		img = draw(s, dark, scale, w, h, 0, 0, false);
		if (img != null) {
			drawnAt.set(img.id, scale);
			keep(key, img);
		}
		return img;
	}

	// the knob, across points thick, drawn four times as long: a scroller
	// long enough that its knob, all of its slot, is that long
	function knob(vertical:Bool, overlay:Bool, dark:Bool, scale:Float, across:Float):Null<Image> {
		var key = 'k$vertical$overlay$dark$scale ${Math.round(across)}';
		var img = cache.get(key);
		if (img != null) return img;
		var s = scroller(vertical, overlay), m = metrics(overlay), len = across * 4;
		frame(s, vertical, m[0], len + 8);
		Msg.vFloat(s, ObjC.sel("setKnobProportion:"), 0.9999);
		Msg.vFloat(s, ObjC.sel("setDoubleValue:"), 0);
		var k = Msg.rectInt(s, ObjC.sel("rectForPart:"), KNOB);
		frame(s, vertical, m[0], len + 8 + len - (vertical ? k.size.height : k.size.width));
		k = Msg.rectInt(s, ObjC.sel("rectForPart:"), KNOB);
		img = draw(s, dark, scale, k.size.width, k.size.height, k.origin.x, k.origin.y, true);
		if (img != null) {
			drawnAt.set(img.id, scale);
			keep(key, img);
		}
		return img;
	}

	// (a cache bounded: lengths come and go as content changes)
	function keep(key:String, img:Image) {
		var n = 0;
		for (_ in cache)
			n++;
		if (n > 48) cache.clear();
		cache.set(key, img);
	}

	// s's knob (else its slot) drawn into a w by h point bitmap, from x, y in s
	function draw(s:Ptr, dark:Bool, scale:Float, w:Float, h:Float, x:Float, y:Float, isKnob:Bool):Null<Image> {
		return helder.os.OsThread.get(() -> {
			var pw = Math.ceil(w * scale), ph = Math.ceil(h * scale);
			if (pw <= 0 || ph <= 0) return null;
			var pool = Runtime.objc_autoreleasePoolPush();
			var bytes = LibC.malloc(pw * ph * 4);
			LibC.memset(bytes, 0, pw * ph * 4);
			var space = CGBits.CGColorSpaceCreateDeviceRGB();
			// (kCGImageAlphaPremultipliedLast: R G B A)
			var ctx = CGBits.CGBitmapContextCreate(bytes, pw, ph, 8, pw * 4, space, 1);
			CGBits.CGColorSpaceRelease(space);
			if (ctx.isNull()) {
				LibC.free(bytes);
				Runtime.objc_autoreleasePoolPop(pool);
				return null;
			}
			CGBits.CGContextScaleCTM(ctx, scale, scale);
			CGBits.CGContextTranslateCTM(ctx, -x, -y);
			var g = Msg.idPtrBool(ObjC.cls("NSGraphicsContext"), ObjC.sel("graphicsContextWithCGContext:flipped:"), ctx, false);
			var gc = ObjC.cls("NSGraphicsContext"), ac = ObjC.cls("NSAppearance");
			Msg.v(gc, ObjC.sel("saveGraphicsState"));
			Msg.vPtr(gc, ObjC.sel("setCurrentContext:"), g);
			var was = Msg.id(ac, ObjC.sel("currentAppearance"));
			var name = ObjC.str(dark ? "NSAppearanceNameDarkAqua" : "NSAppearanceNameAqua");
			// (the system's appearance, its contrast and transparency settings with it, as light or dark)
			var app = Msg.idPtr(ac, ObjC.sel("appearanceNamed:"), name);
			ObjC.release(name);
			Msg.vPtr(ac, ObjC.sel("setCurrentAppearance:"), app);
			Msg.vPtr(s, ObjC.sel("setAppearance:"), app);
			if (isKnob) Msg.v(s, ObjC.sel("drawKnob")) else Msg.vRectBool(s, ObjC.sel("drawKnobSlotInRect:highlight:"), Msg.rectInt(s, ObjC.sel("rectForPart:"), SLOT), false);
			Msg.vPtr(ac, ObjC.sel("setCurrentAppearance:"), was);
			Msg.v(gc, ObjC.sel("restoreGraphicsState"));
			CGBits.CGContextRelease(ctx);
			Runtime.objc_autoreleasePoolPop(pool);
			// (premultiplied to straight alpha, as Image holds it; rows already top to bottom)
			var out = Bytes.alloc(pw * ph * 4);
			for (i in 0...pw * ph) {
				var o = i * 4, a = Mem.getU8(bytes, o + 3);
				if (a == 0) continue;
				for (c in 0...3)
					out.set(o + c, Std.int(Math.min(255, Mem.getU8(bytes, o + c) * 255 / a)));
				out.set(o + 3, a);
			}
			LibC.free(bytes);
			return new Image(pw, ph, out);
		});
	}
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics") extern class CGBits {
	static function CGColorSpaceCreateDeviceRGB():Ptr;
	static function CGColorSpaceRelease(s:Ptr):Void;
	static function CGBitmapContextCreate(data:Ptr, w:Int64, h:Int64, bits:Int64, bytesPerRow:Int64, space:Ptr, info:Int):Ptr;
	static function CGContextScaleCTM(c:Ptr, sx:Float, sy:Float):Void;
	static function CGContextTranslateCTM(c:Ptr, tx:Float, ty:Float):Void;
	static function CGContextRelease(c:Ptr):Void;
}
