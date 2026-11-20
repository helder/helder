package helder.os;

import haxe.io.Bytes;

// The system's photo picker: the images the user picks, each its file's
// bytes as encoded (JPEG, PNG, HEIC...; helder.image decodes most), at
// most max (1); none when cancelled. Picking needs no permission.
class Photos {
	@:typescript @:coroutine public static function pick(?options:{?max:Int}):Array<Bytes> {
		var max = options?.max ?? 1;
		if (max < 1) max = 1;
		// (a coroutine's branches are not folded: each target's own, chosen here)
		#if helder.headless
		return [];
		#elseif (hxmc.target == "wasm32-wasi")
		return helder.os.web.WebPhotos.pick(max);
		#elseif (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		return PhotosApple.pick(max);
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		return helder.os.android.AndroidPhotos.pick(max);
		#elseif (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		return dialog();
		#else
		return [];
		#end
	}

	// (the desktop's open dialog, filtered to images: one)
	@:allow(helder.os) static function dialog():Array<Bytes> {
		var w = App.windows[0];
		if (w == null) return [];
		var path = FileDialog.open(w, "Photos", [{name: "Images", extensions: ["jpg", "jpeg", "png", "gif", "webp", "heic", "tiff", "bmp"]}]);
		return path == null ? [] : try [sys.io.File.getBytes(path)] catch (_:Dynamic) [];
	}
}
