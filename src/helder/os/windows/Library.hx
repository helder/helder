package helder.os.windows;

#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi")
import hxmc.unsafe.*;

// A DLL loaded at run time (helder.os.Dl.build(true): a library the system
// may lack, the program starting without it)
@:hxmc.c @:hxmc.lib("kernel32") extern class Library {
	static function LoadLibraryW(name:Ptr):Ptr;
	static function GetProcAddress(module:Ptr, name:Ptr):Ptr;
}
#end
