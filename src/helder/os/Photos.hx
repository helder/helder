package helder.os;

import haxe.io.Bytes;

// The system's photo picker: the images the user picks, each its file's
// bytes as encoded (JPEG, PNG, HEIC...; helder.image decodes most), at
// most max (1); none when cancelled. Picking needs no permission.
class Photos {
	// the camera: a photo the user takes, as a JPEG (the web: the file the
	// browser gives); null when cancelled or where there is no camera
	// (front: the front camera, where the system lets the app choose). iOS
	// asks to use the camera by itself, with helder.json's usage string
	// "camera"; Android's camera app takes the photo, no permission needed.
	@:typescript @:helder.ios.usage("camera") @:coroutine public static function take(?options:{?front:Bool}):Null<Bytes> {
		var front = options?.front ?? false;
		// (a coroutine's branches are not folded: each target's own, chosen here)
		#if helder.headless
		return null;
		#elseif (hxmc.target == "wasm32-wasi")
		return helder.os.web.WebPhotos.take(front);
		#elseif (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		return CameraApple.take(front);
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		return helder.os.android.AndroidCamera.take(front);
		#else
		return null;
		#end
	}

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
