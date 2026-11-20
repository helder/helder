package helder.ui.draw;

import haxe.io.Bytes;
import helder.image.Image;
import helder.os.objc.*;
import hxmc.unsafe.*;

// macOS's own scrollers drawn into the tree (Ui.scrollbarArt): an
// NSScroller of each orientation and style, never shown, draws its track
// (drawKnobSlotInRect:highlight:) and its knob (drawKnob) into a bitmap
// (a CGBitmapContext as the current NSGraphicsContext, the window's
// appearance current: light, dark, Increase Contrast's, whatever this
// macOS draws), kept as an Image for that size and appearance and drawn
// where the Ui places the thumb; its sizes are the scroller's
// (scrollerWidthForControlSize:scrollerStyle:, rectForPart:). Drawn again
// only when a length or the appearance changes, not as it scrolls.
@:hxmc.unsafe(gc)
class MacScrollbarArt implements helder.ui.ScrollbarArt {
	static inline var KNOB = 2; // NSScrollerKnob
	static inline var SLOT = 6; // NSScrollerKnobSlot

	// the scrollers: [vertical legacy, vertical overlay, horizontal legacy, horizontal overlay]
	final scrollers:Array<Ptr> = [];
	final rect:Ptr<CGRect> = LibC.malloc(32);
	final cache = new Map<String, Image>();
	final sizes:Array<Array<Float>> = [];

	public function new() {
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
			var img = slot(vertical, dark, scale, track[2], track[3]);
			if (img != null) canvas.image(img, track[0], track[1], track[2], track[3], 0, 0, 1, 1, 0);
		}
		var img = knob(vertical, overlay, dark, scale, thumb[2], thumb[3]);
		if (img != null) canvas.image(img, thumb[0], thumb[1], thumb[2], thumb[3], 0, 0, 1, 1, 0);
		if (alpha < 1) canvas.popOpacity();
	}

	// the track, w by h points
	function slot(vertical:Bool, dark:Bool, scale:Float, w:Float, h:Float):Null<Image> {
		var key = 's$vertical$dark$scale ${Math.round(w)} ${Math.round(h)}';
		var img = cache.get(key);
		if (img != null) return img;
		var s = scroller(vertical, false);
		frame(s, vertical, vertical ? w : h, vertical ? h : w);
		img = draw(s, dark, scale, w, h, 0, 0, false);
		if (img != null) keep(key, img);
		return img;
	}

	// the knob, w by h points: a scroller long enough that its knob, all of its slot, is that long
	function knob(vertical:Bool, overlay:Bool, dark:Bool, scale:Float, w:Float, h:Float):Null<Image> {
		var key = 'k$vertical$overlay$dark$scale ${Math.round(w)} ${Math.round(h)}';
		var img = cache.get(key);
		if (img != null) return img;
		var s = scroller(vertical, overlay), m = metrics(overlay), len = vertical ? h : w;
		frame(s, vertical, m[0], len + 8);
		Msg.vFloat(s, ObjC.sel("setKnobProportion:"), 0.9999);
		Msg.vFloat(s, ObjC.sel("setDoubleValue:"), 0);
		var k = Msg.rectInt(s, ObjC.sel("rectForPart:"), KNOB);
		frame(s, vertical, m[0], len + 8 + len - (vertical ? k.size.height : k.size.width));
		k = Msg.rectInt(s, ObjC.sel("rectForPart:"), KNOB);
		img = draw(s, dark, scale, k.size.width, k.size.height, k.origin.x, k.origin.y, true);
		if (img != null) keep(key, img);
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
