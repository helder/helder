package helder.os.windows;

#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
import helder.os.windows.FileOpenDialog.Shell32Com;
import hxmc.unsafe.*;

@:hxmc.unsafe(gc)
class WinTrash {
	static final CLSID = Com.guid(0x3AD05575, 0x8857, 0x4850, [0x92, 0x77, 0x11, 0xB8, 0x5B, 0xDB, 0x8E, 0x09]);
	static final IID = Com.guid(0x947AAB5F, 0x0A5C, 0x4C13, [0xB4, 0xD6, 0x4B, 0xF7, 0x83, 0x6F, 0xC9, 0xF8]);
	static final ITEM = Com.guid(0x43826D1E, 0xE718, 0x42EE, [0xBC, 0x55, 0xA1, 0xE2, 0x61, 0xC3, 0x7B, 0xFE]);
	// (FOFX_RECYCLEONDELETE, FOF_NOCONFIRMATION, FOF_SILENT, FOF_NOERRORUI, FOFX_EARLYFAILURE)
	static inline var FLAGS = 0x80000 | 0x10 | 0x4 | 0x400 | 0x100000;

	public static function move(path:String):Null<String> {
		path = sys.FileSystem.fullPath(path);
		var error = helder.os.OsThread.get(() -> recycle(path));
		if (error != null) throw 'Trash: $path ($error)';
		return null;
	}

	static function recycle(path:String):Null<String> {
		// (COINIT_APARTMENTTHREADED; RPC_E_CHANGED_MODE: already initialized)
		var apartment = Shell32Com.CoInitializeEx(Ptr.nil(), 2);
		if (apartment < 0 && apartment != 0x80010106) return hresult(apartment);
		var result = Arena.scopedValue(a -> {
			var out:Ptr<Ptr> = a.alloc(8);
			out.value = Ptr.nil();
			var hr = Shell32Com.CoCreateInstance(CLSID, Ptr.nil(), 1, IID, out);
			if (hr < 0) return hresult(hr);
			var op = out.value;
			out.value = Ptr.nil();
			hr = Shell.SHCreateItemFromParsingName(a.wstring(path), Ptr.nil(), ITEM, out);
			var item = out.value;
			if (hr >= 0) hr = IFileOperation.SetOperationFlags(op, FLAGS);
			if (hr >= 0) hr = IFileOperation.DeleteItem(op, item, Ptr.nil());
			var aborted:Ptr<Int32> = a.alloc(4, 4);
			aborted.value = 0;
			if (hr >= 0) {
				hr = IFileOperation.PerformOperations(op);
				var status = IFileOperation.GetAnyOperationsAborted(op, aborted);
				if (hr >= 0) hr = status;
			}
			Com.release(item);
			Com.release(op);
			return hr < 0 ? hresult(hr) : aborted.value != 0 ? "operation aborted" : null;
		});
		if (apartment >= 0) Shell32Com.CoUninitialize();
		return result;
	}

	static inline function hresult(hr:Int):String
		return "0x" + StringTools.hex(hr, 8);
}

@:hxmc.c @:hxmc.lib("shell32") private extern class Shell {
	static function SHCreateItemFromParsingName(path:Ptr, bind:Ptr, iid:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.windows.Com.build())
@:hxmc.unsafe(gc)
private class IFileOperation {
	@:slot(5) static function SetOperationFlags(self:Ptr, flags:Int):Int;
	@:slot(18) static function DeleteItem(self:Ptr, item:Ptr, sink:Ptr):Int;
	@:slot(21) static function PerformOperations(self:Ptr):Int;
	@:slot(22) static function GetAnyOperationsAborted(self:Ptr, aborted:Ptr<Int32>):Int;
}
#end
