import haxe.io.Bytes;
import haxe.io.Path;
import helder.canvas.Bitmap;
import helder.dom.Document;
import helder.dom.Dom;
import helder.image.Image;
import helder.ui.box.DocumentView;
import helder.ui.box.FontMatch;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// A page of web-platform-tests (or any file) for DocumentView: parsed as
// XML when it is .xht, .xhtml or .svg, else as HTML; at WPT's own URL
// (http://web-platform.test/...) when it is under the checkout, so its
// root-relative links (/fonts/ahem.css) are found; its sheets, images and
// fonts read from disk; Ahem registered as a font, as WPT's runners have it.
class WptPage {
	public static inline var HOST = "http://web-platform.test/";

	public static var wpt = "bin/wpt";
	static var fonts:Null<FontMatch> = null;

	public static function shared():FontMatch {
		if (fonts != null) return fonts;
		// (helder's own shaping, as the lanes run it: the same pixels however the runner is started, on every OS)
		helder.text.Shaping.engine = helder.text.Shaping.HELDER;
		fonts = new FontMatch();
		var ahem = '$wpt/fonts/Ahem.ttf';
		if (FileSystem.exists(ahem)) fonts.register(File.getBytes(ahem), "Ahem");
		return fonts;
	}

	public static function parse(path:String):Document {
		var text = File.getContent(path);
		var ext = Path.extension(path).toLowerCase();
		return ext == "xht" || ext == "xhtml" || ext == "xml" || ext == "svg" ? Dom.parseXml(text) : Dom.parse(text);
	}

	public static function url(path:String):String {
		var abs = FileSystem.fullPath(path), root = FileSystem.fullPath(wpt) + "/";
		return abs.startsWith(root) ? HOST + abs.substr(root.length) : "file://" + abs;
	}

	public static function file(url:String):Null<String> {
		var q = url.indexOf("?");
		if (q >= 0) url = url.substr(0, q);
		var h = url.indexOf("#");
		if (h >= 0) url = url.substr(0, h);
		var p = url.startsWith(HOST) ? '$wpt/' + url.substr(HOST.length) : url.startsWith("file://") ? url.substr(7) : null;
		return p != null && FileSystem.exists(p) && !FileSystem.isDirectory(p) ? StringTools.urlDecode(p) : null;
	}

	public static function options(path:String):DocumentViewOptions
		return {
			url: url(path),
			fonts: shared(),
			load: u -> {
				var f = file(u);
				f == null ? null : File.getContent(f);
			},
			font: u -> {
				var f = file(u);
				f == null ? null : File.getBytes(f);
			},
			image: u -> {
				var f = file(u);
				if (f == null || f.toLowerCase().endsWith(".svg")) return null;
				var bytes = File.getBytes(f);
				try Bitmap.fromImage(Image.decode(bytes)) catch (_:Dynamic) null;
			}
		};
}
