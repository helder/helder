package helder.os.apple;

import helder.image.Image;
import helder.os.DragOperation;
import helder.os.OsThread;
import helder.os.apple.objc.*;
import hxmc.unsafe.*;

// AppKit keeps the dragging session. Keep its source and completion alive
// until it sends draggingSession:endedAtPoint:operation:.
@:access(helder.os.apple.MacWindow)
@:hxmc.unsafe(gc)
class FileDrag {
	static var cls = Ptr.nil();
	static final active:Array<FileDrag> = [];

	final source:Ptr;
	final mask:Int;
	final done:DragOperation->Void;

	function new(allowed:Array<DragOperation>, done:DragOperation->Void) {
		if (cls.isNull()) {
			cls = ObjC.cls("HxmcFileDragSource");
			var register = cls.isNull();
			if (register) {
				cls = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcFileDragSource"), 0);
				Runtime.class_addProtocol(cls, Runtime.objc_getProtocol(Mem.cstr("NSDraggingSource")));
			}
			Runtime.class_replaceMethod(cls, ObjC.sel("draggingSession:sourceOperationMaskForDraggingContext:"), Callback.addr(operations), Mem.cstr("Q@:@q"));
			Runtime.class_replaceMethod(cls, ObjC.sel("draggingSession:endedAtPoint:operation:"), Callback.addr(ended), Mem.cstr("v@:@{CGPoint=dd}Q"));
			if (register) Runtime.objc_registerClassPair(cls);
		}
		source = Msg.id(cls, ObjC.sel("new"));
		var bits = 0;
		for (op in allowed)
			bits |= switch op {
				case Copy: 1;
				case Link: 2;
				case Move: 16;
				case None: 0;
			};
		mask = bits;
		this.done = done;
	}

	public static function begin(w:MacWindow, ev:Ptr, paths:Array<String>, image:Null<Image>, x:Float, y:Float, allowed:Array<DragOperation>,
		done:DragOperation->Void):Bool {
		var list = items(w, ev, paths, image, x, y);
		if (list.isNull()) return false;
		var drag = new FileDrag(allowed, done);
		active.push(drag);
		var session = Msg.idPtrPtrPtr(w.view, ObjC.sel("beginDraggingSessionWithItems:event:source:"), list, ev, drag.source);
		if (!session.isNull()) return true;
		if (active.remove(drag)) ObjC.release(drag.source);
		return false;
	}

	// One NSDraggingItem per file URL (autoreleased; nil: a path AppKit
	// refuses), the first one showing the image under the pointer.
	static function items(w:MacWindow, ev:Ptr, paths:Array<String>, image:Null<Image>, x:Float, y:Float):Ptr {
		var items = Msg.id(ObjC.cls("NSMutableArray"), ObjC.sel("array"));
		var preview = image == null ? Ptr.nil() : dragImage(image);
		for (path in paths) {
			var url = fileURL(path);
			if (url.isNull()) {
				ObjC.release(preview);
				return Ptr.nil();
			}
			var item = Msg.idPtr(Msg.id(ObjC.cls("NSDraggingItem"), ObjC.sel("alloc")), ObjC.sel("initWithPasteboardWriter:"), url);
			if (!preview.isNull() && Msg.i(items, ObjC.sel("count")) == 0) Arena.scoped(a -> {
				// (the view isn't flipped: the frame's origin is its bottom left)
				var at = Msg.pointPointPtr(w.view, ObjC.sel("convertPoint:fromView:"), w.location(ev), Ptr.nil());
				var frame = a.make(CGRect);
				frame.value.origin.x = at.x - x;
				frame.value.origin.y = at.y + y - image.height;
				frame.value.size.width = image.width;
				frame.value.size.height = image.height;
				Msg.vRectPtr(item, ObjC.sel("setDraggingFrame:contents:"), frame.value, preview);
			});
			Msg.vPtr(items, ObjC.sel("addObject:"), item);
			ObjC.release(item);
		}
		ObjC.release(preview);
		return items;
	}

	static function fileURL(path:String):Ptr {
		var text = ObjC.str(path);
		var url = text.isNull() ? Ptr.nil() : Msg.idPtr(ObjC.cls("NSURL"), ObjC.sel("fileURLWithPath:"), text);
		ObjC.release(text);
		return url;
	}

	// The bitmap representation takes straight RGBA. The NSImage's size
	// is in points, so AppKit draws it at the screen's backing scale.
	static function dragImage(image:Image):Ptr {
		var pixels = image.pixels;
		var rep = Msg.idPtrIntIntIntIntBoolBoolPtrIntIntInt(Msg.id(ObjC.cls("NSBitmapImageRep"), ObjC.sel("alloc")),
			ObjC.sel("initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bitmapFormat:bytesPerRow:bitsPerPixel:"),
			Ptr.nil(), image.width, image.height, 8, 4, true, false, colorSpaceName(), 2, image.width * 4, 32);
		if (rep.isNull()) return Ptr.nil();
		var data = Msg.id(rep, ObjC.sel("bitmapData"));
		LibC.memcpy(data, BytesPtr.of(pixels, 0, pixels.length), (pixels.length : Int64));
		var result = Arena.scopedValue(a -> {
			var size = a.make(CGSize);
			size.value.width = image.width;
			size.value.height = image.height;
			return Msg.idSize(Msg.id(ObjC.cls("NSImage"), ObjC.sel("alloc")), ObjC.sel("initWithSize:"), size.value);
		});
		Msg.vPtr(result, ObjC.sel("addRepresentation:"), rep);
		ObjC.release(rep);
		return result;
	}

	static function colorSpaceName():Ptr
		return Msg.idPtr(ObjC.cls("NSString"), ObjC.sel("stringWithUTF8String:"), Mem.cstr("NSDeviceRGBColorSpace"));

	@:hxmc.callback static function operations(self:Ptr, cmd:Ptr, session:Ptr, context:Int64):Int64 {
		for (drag in active)
			if (drag.source == self) return drag.mask;
		return 0;
	}

	// (the point: a CGPoint by value, its x and y)
	@:hxmc.callback static function ended(self:Ptr, cmd:Ptr, session:Ptr, x:Float, y:Float, operation:Int64) {
		for (drag in active)
			if (drag.source == self) {
				active.remove(drag);
				ObjC.release(self);
				var bits = operation.toInt();
				var op:DragOperation = bits & 16 != 0 ? Move : bits & 2 != 0 ? Link : bits & 1 != 0 ? Copy : None;
				OsThread.soon(() -> drag.done(op));
				return;
			}
	}
}
