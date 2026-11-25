package helder.os.windows;

import helder.os.Settings.SettingsValues;
import helder.os.windows.User32;
import hxmc.unsafe.*;

@:hxmc.unsafe(gc)
class Settings {
	public static function read(v:SettingsValues) {
		Arena.scoped(a -> {
			var data:Ptr<Int32> = a.alloc(4), size:Ptr<Int32> = a.alloc(4);
			size.value = 4;
			var hkcu = Ptr.ofI64(haxe.Int64.make(0xFFFFFFFF, 0x80000001));
			if (Advapi32.RegGetValueW(hkcu, a.wstring("Software\\Microsoft\\Accessibility"), a.wstring("TextScaleFactor"), 0x10,
				Ptr.nil(), data, size) == 0 && data.value > 0) v.textScale = data.value / 100;
			if (User32.SystemParametersInfoW(0x1042, 0, data, 0) != 0) v.reducedMotion = data.value == 0;
			// HIGHCONTRASTW: length, flags, scheme pointer.
			var hc:Ptr<Int32> = a.alloc(16);
			hc[0] = 16;
			if (User32.SystemParametersInfoW(0x42, 16, hc, 0) != 0 && hc[1] & 1 != 0) v.contrast = More;
		});
	}
}
