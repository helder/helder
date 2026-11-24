package helder.os.win32;

import helder.image.Image;
import helder.os.DragOperation;
import helder.os.win32.Com.IUnknown;
import helder.os.win32.FileOpenDialog.Shell32Com;
import helder.os.win32.User32;
import hxmc.unsafe.*;

// OLE's source and the Shell's data object both live on the window's STA.
@:hxmc.unsafe(gc)
class WinFileDrag {
	static final UNKNOWN = Com.guid(0, 0, 0, [0xC0, 0, 0, 0, 0, 0, 0, 0x46]);
	static final DROP_SOURCE = Com.guid(0x121, 0, 0, [0xC0, 0, 0, 0, 0, 0, 0, 0x46]);
	static final DATA_OBJECT = Com.guid(0x10E, 0, 0, [0xC0, 0, 0, 0, 0, 0, 0, 0x46]);
	static final SHELL_FOLDER = Com.guid(0x214E6, 0, 0, [0xC0, 0, 0, 0, 0, 0, 0, 0x46]);
	static final BHID_DATA_OBJECT = Com.guid(0xB8C0BD9F, 0xED24, 0x455C, [0x83, 0xE6, 0xD5, 0x39, 0x0C, 0x4F, 0xE8, 0xC4]);
	static final DRAG_DROP_HELPER = Com.guid(0x4657278A, 0x411B, 0x11D2, [0x83, 0x9A, 0, 0xC0, 0x4F, 0xD9, 0x18, 0xD0]);
	static final DRAG_SOURCE_HELPER = Com.guid(0xDE5BF786, 0x477A, 0x11D2, [0x83, 0x9D, 0, 0xC0, 0x4F, 0xD9, 0x18, 0xD0]);
	static inline var DROP = 0x00040100;
	static inline var CANCEL = 0x00040101;
	static var ole:Null<Bool>;
	static var vtable:Ptr<Ptr> = Ptr.nil();

	public final hwnd:Ptr;
	final data:Ptr;
	final effects:Int;
	public final done:DragOperation->Void;
	var running:Ptr<DropSourceState> = Ptr.nil();

	function new(hwnd:Ptr, data:Ptr, allowed:Array<DragOperation>, done:DragOperation->Void) {
		this.hwnd = hwnd;
		this.data = data;
		this.done = done;
		var bits = 0;
		for (op in allowed)
			bits |= switch op {
				case Copy: 1;
				case Move: 2;
				case Link: 4;
				case None: 0;
			};
		effects = bits;
	}

	public static function prepare(hwnd:Ptr, paths:Array<String>, image:Null<Image>, scale:Float, x:Float, y:Float, allowed:Array<DragOperation>,
		done:DragOperation->Void):Null<WinFileDrag> {
		var data = dataObject(paths);
		if (data.isNull()) return null;
		try {
			if (image != null) attachImage(data, image, scale, x, y);
		} catch (e:haxe.Exception) {
			Com.release(data);
			throw e;
		}
		return new WinFileDrag(hwnd, data, allowed, done);
	}

	// The Shell's data object for the files (CF_HDROP, Shell IDList Array
	// and the rest Explorer gives), owned by the caller; nil: none. Its
	// shell item array's handler takes files from several folders; Wine's
	// is a stub, so the parent folder's when they share one (items false:
	// that one only).
	static function dataObject(paths:Array<String>, items = true):Ptr {
		if (ole == null) ole = DragOle32.OleInitialize(Ptr.nil()) >= 0;
		if (!ole || paths.length == 0) return Ptr.nil();
		return Arena.scopedValue(a -> {
			var ids:Ptr<Ptr> = a.alloc(paths.length * 8), count = 0;
			for (path in paths) {
				if (DragShell32.SHParseDisplayName(a.wstring(StringTools.replace(path, "/", "\\")), Ptr.nil(), ids.add(count), 0, Ptr.nil()) < 0) break;
				count++;
			}
			var data = count < paths.length ? Ptr.nil() : items ? fromItems(a, ids, count) : Ptr.nil();
			if (data.isNull() && count == paths.length) data = fromFolder(a, ids, count);
			for (i in 0...count)
				Shell32Com.CoTaskMemFree(ids[i]);
			return data;
		});
	}

	static function fromItems(a:Arena, ids:Ptr<Ptr>, count:Int):Ptr {
		var items:Ptr<Ptr> = a.alloc(8), out:Ptr<Ptr> = a.alloc(8);
		if (DragShell32.SHCreateShellItemArrayFromIDLists(count, ids, items) < 0) return Ptr.nil();
		if (ShellDragItems.BindToHandler(items.value, Ptr.nil(), BHID_DATA_OBJECT, DATA_OBJECT, out) < 0) out.value = Ptr.nil();
		Com.release(items.value);
		return out.value;
	}

	// (each ID list's last item is in its parent's: the same parent, the
	// same bytes before it)
	static function fromFolder(a:Arena, ids:Ptr<Ptr>, count:Int):Ptr {
		var folders:Ptr<Ptr> = a.alloc(count * 8), children:Ptr<Ptr> = a.alloc(count * 8), out:Ptr<Ptr> = a.alloc(8), bound = 0, same = true;
		while (bound < count && DragShell32.SHBindToParent(ids[bound], SHELL_FOLDER, folders.add(bound), children.add(bound)) >= 0)
			bound++;
		var parent = children[0].toI64() - ids[0].toI64();
		for (i in 1...bound)
			if (children[i].toI64() - ids[i].toI64() != parent || LibC.memcmp(ids[i], ids[0], parent) != 0) same = false;
		if (bound == count && same && ShellFolder.GetUIObjectOf(folders[0], Ptr.nil(), count, children, DATA_OBJECT, Ptr.nil(), out) < 0)
			out.value = Ptr.nil();
		for (i in 0...bound)
			Com.release(folders[i]);
		return out.value;
	}

	static function attachImage(data:Ptr, image:Image, scale:Float, x:Float, y:Float) {
		var pixels = image.pixels;
		Arena.scoped(a -> {
			var helper:Ptr<Ptr> = a.alloc(8);
			if (Shell32Com.CoCreateInstance(DRAG_DROP_HELPER, Ptr.nil(), 1, DRAG_SOURCE_HELPER, helper) < 0) return;
			var w = Std.int(Math.max(1, Math.round(image.width * scale))), h = Std.int(Math.max(1, Math.round(image.height * scale)));
			var info = a.make(BITMAPINFOHEADER), bits:Ptr<Ptr> = a.alloc(8);
			info.value.biSize = 40;
			info.value.biWidth = w;
			info.value.biHeight = -h;
			info.value.biPlanes = 1;
			info.value.biBitCount = 32;
			var bitmap = Gdi32.CreateDIBSection(Ptr.nil(), info, 0, bits, Ptr.nil(), 0);
			if (!bitmap.isNull()) {
				var dst:Ptr<UInt8> = bits.value;
				// (straight BGRA: the helper takes it so, premultiplied colours drawn
				// dark; Chromium unpremultiplies its image for it too)
				for (row in 0...h) {
					var srcRow = Std.int((row + 0.5) * image.height / h) * image.width;
					for (col in 0...w) {
						var i = (srcRow + Std.int((col + 0.5) * image.width / w)) * 4, j = (row * w + col) * 4;
						dst[j] = pixels.get(i + 2);
						dst[j + 1] = pixels.get(i + 1);
						dst[j + 2] = pixels.get(i);
						dst[j + 3] = pixels.get(i + 3);
					}
				}
				var preview = a.make(ShellDragImage);
				preview.value.width = w;
				preview.value.height = h;
				preview.value.x = Math.round(x * scale);
				preview.value.y = Math.round(y * scale);
				preview.value.bitmap = bitmap;
				preview.value.colorKey = -1;
				// The helper takes the bitmap on success (Wine can return E_NOTIMPL).
				if (ShellDragHelper.InitializeFromBitmap(helper.value, preview, data) < 0) Gdi32.DeleteObject(bitmap);
			}
			Com.release(helper.value);
		});
	}

	public function run():DragOperation {
		if (vtable.isNull()) {
			vtable = LibC.malloc(5 * 8);
			vtable[0] = Callback.addr(queryInterface);
			vtable[1] = Callback.addr(addRef);
			vtable[2] = Callback.addr(release);
			vtable[3] = Callback.addr(queryContinue);
			vtable[4] = Callback.addr(giveFeedback);
		}
		running = LibC.malloc(16);
		running.value.vtable = vtable;
		running.value.refs = 1;
		running.value.cancelled = 0;
		var op:DragOperation = Arena.scopedValue(a -> {
			var effect:Ptr<Int32> = a.alloc(4);
			if (DragOle32.DoDragDrop(data, running, effects, effect) != DROP) return DragOperation.None;
			var bits = effect.value;
			return bits & 2 != 0 ? DragOperation.Move : bits & 4 != 0 ? DragOperation.Link : bits & 1 != 0 ? DragOperation.Copy : DragOperation.None;
		});
		Com.release(running);
		running = Ptr.nil();
		Com.release(data);
		return op;
	}

	// True when the modal loop will report the cancellation on its way out.
	public function cancel():Bool {
		if (!running.isNull()) {
			running.value.cancelled = 1;
			return true;
		}
		Com.release(data);
		return false;
	}

	@:hxmc.callback static function queryInterface(self:Ptr<DropSourceState>, iid:Ptr, out:Ptr<Ptr>):Int {
		out.value = Ptr.nil();
		if (LibC.memcmp(iid, UNKNOWN, 16) != 0 && LibC.memcmp(iid, DROP_SOURCE, 16) != 0) return 0x80004002; // E_NOINTERFACE
		out.value = self;
		addRef(self);
		return 0;
	}

	@:hxmc.callback static function addRef(self:Ptr<DropSourceState>):Int
		return ++self.value.refs;

	@:hxmc.callback static function release(self:Ptr<DropSourceState>):Int {
		var refs = --self.value.refs;
		if (refs == 0) LibC.free(self);
		return refs;
	}

	@:hxmc.callback static function queryContinue(self:Ptr<DropSourceState>, escape:Int, keys:Int):Int
		return escape != 0 || self.value.cancelled != 0 ? CANCEL : keys & 1 == 0 ? DROP : 0;

	@:hxmc.callback static function giveFeedback(self:Ptr, effect:Int):Int
		return 0x00040102; // DRAGDROP_S_USEDEFAULTCURSORS
}

@:hxmc.struct @:publicFields private class DropSourceState {
	var vtable:Ptr;
	var refs:Int32;
	var cancelled:Int32;
}

@:hxmc.struct @:publicFields private class ShellDragImage {
	var width:Int32;
	var height:Int32;
	var x:Int32;
	var y:Int32;
	var bitmap:Ptr;
	var colorKey:UInt32;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
private class ShellDragItems {
	@:slot(3) static function BindToHandler(self:Ptr, context:Ptr, handler:Ptr, iid:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
private class ShellFolder {
	@:slot(10) static function GetUIObjectOf(self:Ptr, owner:Ptr, count:Int, children:Ptr<Ptr>, iid:Ptr, reserved:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
private class ShellDragHelper {
	@:slot(3) static function InitializeFromBitmap(self:Ptr, image:Ptr<ShellDragImage>, data:Ptr):Int;
}

@:hxmc.c @:hxmc.lib("shell32") private extern class DragShell32 {
	static function SHParseDisplayName(path:Ptr, context:Ptr, pidl:Ptr<Ptr>, attributes:Int, outAttributes:Ptr):Int;
	static function SHCreateShellItemArrayFromIDLists(count:Int, pidls:Ptr<Ptr>, out:Ptr<Ptr>):Int;
	static function SHBindToParent(pidl:Ptr, iid:Ptr, folder:Ptr<Ptr>, last:Ptr<Ptr>):Int;
}

@:hxmc.c @:hxmc.lib("ole32") extern class DragOle32 {
	static function OleInitialize(reserved:Ptr):Int;
	static function DoDragDrop(data:Ptr, source:Ptr, effects:Int, performed:Ptr<Int32>):Int;
	static function ReleaseStgMedium(medium:Ptr):Void;
}
