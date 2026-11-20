package helder.os;

import helder.os.DeviceInfo.DeviceDetails;
#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
import helder.os.win32.User32;
import hxmc.unsafe.*;
#end

// Device on Windows (RtlGetVersion's version, the registry's BIOS product
// name and maker) and Linux (/etc/os-release, /sys/class/dmi/id).
@:hxmc.unsafe(gc)
class DeviceDesktop {
	public static function windows():DeviceDetails {
		var d:DeviceDetails = {model: "", manufacturer: "", os: "Windows", osVersion: "", kind: Desktop};
		#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		Arena.scoped(a -> {
			// (RTL_OSVERSIONINFOW: its size, major, minor, build, platform, a service pack's 128 characters)
			var v:Ptr<Int32> = a.alloc(276, 4);
			v[0] = 276;
			var f = Kernel.GetProcAddress(Kernel.GetModuleHandleW(a.wstring("ntdll.dll")), a.cstring("RtlGetVersion"));
			if (!f.isNull() && Version.call(f, v) == 0) d.osVersion = '${v[1]}.${v[2]}.${v[3]}';
			var hklm = Ptr.ofI64(haxe.Int64.make(0xFFFFFFFF, 0x80000002));
			function value(name:String):String {
				var buf = a.alloc(512, 2), size:Ptr<Int32> = a.alloc(4);
				size.value = 510;
				// (RRF_RT_REG_SZ)
				if (Advapi32.RegGetValueW(hklm, a.wstring("HARDWARE\\DESCRIPTION\\System\\BIOS"), a.wstring(name), 2, Ptr.nil(), buf, size) != 0) return "";
				var w:Ptr<UInt16> = cast buf, b = new StringBuf(), k = 0;
				while (w[k] != 0)
					b.addChar(w[k++]);
				return StringTools.trim(b.toString());
			}
			d.model = value("SystemProductName");
			d.manufacturer = value("SystemManufacturer");
		});
		#end
		return d;
	}

	public static function linux():DeviceDetails {
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

#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
@:hxmc.c @:hxmc.lib("kernel32") private extern class Kernel {
	static function GetModuleHandleW(name:Ptr):Ptr;
	static function GetProcAddress(module:Ptr, name:Ptr):Ptr;
}

@:hxmc.c private extern class Version {
	@:hxmc.indirect static function call(f:Ptr, info:Ptr):Int;
}
#end
