package helder.os.apple;

import helder.os.apple.objc.*;
import hxmc.unsafe.*;

// A frame's pixels into a window (Blit): a CGImage of them (in the
// screen's colour space: shown unconverted, as an untagged Metal layer's;
// premultiplied RGBA, its bytes copied into a CFData) as the contents of
// the view's layer, a plain CALayer in a -D helder.soft build, set with
// the layer's implicit animation off and the transaction flushed (a
// frame from another thread than the main one). The whole frame: a
// layer's contents are replaced whole
@:hxmc.unsafe(gc)
class MacBlit {
	final layer:Ptr;
	final view:Ptr;

	public function new(s:Surface) {
		layer = s.display;
		view = s.handle;
	}

	public function present(px:Ptr, w:Int, h:Int, rects:Null<Array<Int>>) {
		var screen = Msg.id(Msg.id(view, ObjC.sel("window")), ObjC.sel("screen"));
		var space = screen.isNull() ? Ptr.nil() : Msg.id(Msg.id(screen, ObjC.sel("colorSpace")), ObjC.sel("CGColorSpace"));
		if (space.isNull()) return;
		var data = QuartzData.CFDataCreate(Ptr.nil(), px, (4 * w * h : hxmc.I64));
		var provider = Quartz.CGDataProviderCreateWithCFData(data);
		// (kCGImageAlphaPremultipliedLast, the bytes in order)
		var img = Quartz.CGImageCreate(w, h, 8, 32, 4 * w, space, 1, provider, Ptr.nil(), false, 0);
		var t = ObjC.cls("CATransaction");
		Msg.v(t, ObjC.sel("begin"));
		Msg.vBool(t, ObjC.sel("setDisableActions:"), true);
		Msg.vPtr(layer, ObjC.sel("setContents:"), img);
		Msg.v(t, ObjC.sel("commit"));
		Msg.v(t, ObjC.sel("flush"));
		Quartz.CGImageRelease(img);
		Quartz.CGDataProviderRelease(provider);
		QuartzData.CFRelease(data);
	}

	public function dispose() {}
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics") extern class Quartz {
	static function CGDataProviderCreateWithCFData(data:Ptr):Ptr;
	static function CGDataProviderRelease(p:Ptr):Void;
	static function CGImageCreate(w:hxmc.I64, h:hxmc.I64, bits:hxmc.I64, bitsPerPixel:hxmc.I64, stride:hxmc.I64, space:Ptr, info:Int, provider:Ptr, decode:Ptr, interpolate:Bool,
		intent:Int):Ptr;
	static function CGImageRelease(img:Ptr):Void;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation") extern class QuartzData {
	static function CFDataCreate(alloc:Ptr, bytes:Ptr, n:hxmc.I64):Ptr;
	static function CFRelease(o:Ptr):Void;
}
