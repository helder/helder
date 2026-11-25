package helder.os.linux;

import helder.os.DeviceInfo.DeviceDetails;

// Device on Linux: /etc/os-release, /sys/class/dmi/id.
class Device {
	public static function details():DeviceDetails {
		inline function read(path:String):String
			return try StringTools.trim(sys.io.File.getContent(path)) catch (_:Dynamic) "";
		var r = release(try sys.io.File.getContent("/etc/os-release") catch (_:Dynamic) read("/usr/lib/os-release"));
		return {
			model: read("/sys/class/dmi/id/product_name"),
			manufacturer: read("/sys/class/dmi/id/sys_vendor"),
			os: "Linux",
			osVersion: StringTools.trim((r.get("NAME") ?? "") + " " + (r.get("VERSION_ID") ?? "")),
			kind: Desktop
		};
	}

	// os-release's KEY=value lines, a value quoted ("" or '') with \ escapes
	public static function release(text:String):Map<String, String> {
		var out = new Map<String, String>();
		for (line in text.split("\n")) {
			var l = StringTools.trim(line), eq = l.indexOf("=");
			if (eq <= 0 || l.charAt(0) == "#") continue;
			var v = l.substr(eq + 1), q = v.charAt(0);
			if ((q == '"' || q == "'") && v.length >= 2 && v.charAt(v.length - 1) == q) {
				v = v.substr(1, v.length - 2);
				if (q == '"') v = ~/\\(.)/g.map(v, r -> r.matched(1));
			}
			out.set(l.substr(0, eq), v);
		}
		return out;
	}
}
