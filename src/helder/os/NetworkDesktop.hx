package helder.os;

import helder.os.Network.NetworkKind;
import hxmc.unsafe.*;

@:hxmc.unsafe(gc)
class NetworkDesktop {
	static var hint = Ptr.nil();
	static var looked = false;

	// GetNetworkConnectivityHint (Windows 10 2004 on: looked up, else online)
	public static function windows():NetworkKind {
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

	// the default route's interface (IPv4's, else IPv6's), Wi-Fi when it is wireless
	public static function linux():NetworkKind {
		var v4 = try sys.io.File.getContent("/proc/net/route") catch (_:Dynamic) return Other;
		var v6 = try sys.io.File.getContent("/proc/net/ipv6_route") catch (_:Dynamic) "";
		var iface = route(v4, v6);
		return iface == null ? None : sys.FileSystem.exists('/sys/class/net/$iface/wireless') ? Wifi : Wired;
	}

	// (route: Iface Destination Gateway Flags, RTF_UP 1; ipv6_route: the
	// destination and its prefix first, the interface last)
	static function route(v4:String, v6:String):Null<String> {
		for (line in v4.split("\n").slice(1)) {
			var f = ~/\s+/g.split(StringTools.trim(line));
			if (f.length >= 4 && f[1] == "00000000" && Std.parseInt("0x" + f[3]) & 1 != 0) return f[0];
		}
		for (line in v6.split("\n")) {
			var f = ~/\s+/g.split(StringTools.trim(line));
			if (f.length >= 10 && ~/^0+$/.match(f[0]) && f[1] == "00" && f[9] != "lo") return f[9];
		}
		return null;
	}
}

@:hxmc.c @:hxmc.lib("kernel32") private extern class Kernel {
	static function LoadLibraryW(name:Ptr):Ptr;
	static function GetProcAddress(module:Ptr, name:Ptr):Ptr;
}

@:hxmc.c private extern class Hint {
	@:hxmc.indirect static function call(f:Ptr, hint:Ptr):Int;
}
