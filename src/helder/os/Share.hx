package helder.os;

class Share {
	// the system's share sheet of text, a URL and files (paths): whether the
	// user shared, where the system tells, else whether it was shown
	@:typescript @:coroutine public static function share(item:{?text:String, ?url:String, ?files:Array<String>}):Bool {
		// (a coroutine's branches are not folded: each target's own, chosen here)
		#if helder.headless
		return false;
		#elseif (hxmc.target == "wasm32-wasi")
		return helder.os.web.WebServices.share(item.text, item.url, item.files ?? []);
		#elseif (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		return helder.os.apple.Share.share(item.text, item.url, item.files ?? []);
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		return helder.os.android.Share.share(item.text, item.url, item.files ?? []);
		#else
		return false;
		#end
	}

	// (a file's MIME type by its extension: what a share's receiver is told; null: not known)
	static function mime(path:String):Null<String> {
		var dot = path.lastIndexOf(".");
		return dot < 0 ? null : switch path.substr(dot + 1).toLowerCase() {
			case "png": "image/png";
			case "jpg" | "jpeg": "image/jpeg";
			case "gif": "image/gif";
			case "webp": "image/webp";
			case "heic": "image/heic";
			case "svg": "image/svg+xml";
			case "pdf": "application/pdf";
			case "txt": "text/plain";
			case "json": "application/json";
			case "zip": "application/zip";
			case "mp4": "video/mp4";
			case "mov": "video/quicktime";
			case "mp3": "audio/mpeg";
			case _: null;
		}
	}
}
