package helder.os.windows;

import helder.os.Network.NetworkKind;
import hxmc.unsafe.*;

@:hxmc.unsafe(gc)
class Network {
	static var hint = Ptr.nil();
	static var looked = false;

	// GetNetworkConnectivityHint (Windows 10 2004 on: looked up, else online)
	public static function kind():NetworkKind {
		if (!looked) {
			looked = true;
			hint = Arena.scopedValue(a -> Kernel.GetProcAddress(Kernel.LoadLibraryW(a.wstring("iphlpapi.dll")), a.cstring("GetNetworkConnectivityHint")));
		}
		if (hint.isNull()) return Other;
		return Arena.scopedValue(a -> {
			var h:Ptr<Int32> = a.alloc(16);
			// (NL_NETWORK_CONNECTIVITY_HINT's level: none 1, local access 2, internet 3, constrained 4)
			if (Hint.call(hint, h) != 0) Other else switch h[0] {
				case 1 | 2: None;
				case _: Other;
			}
		});
	}
}

@:hxmc.c @:hxmc.lib("kernel32") private extern class Kernel {
	static function LoadLibraryW(name:Ptr):Ptr;
	static function GetProcAddress(module:Ptr, name:Ptr):Ptr;
}

@:hxmc.c private extern class Hint {
	@:hxmc.indirect static function call(f:Ptr, hint:Ptr):Int;
}
