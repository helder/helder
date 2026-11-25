package helder.os.linux;

import helder.os.Network.NetworkKind;

class Network {
	// the default route's interface (IPv4's, else IPv6's), Wi-Fi when it is wireless
	public static function kind():NetworkKind {
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
