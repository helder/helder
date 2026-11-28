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
// fonts read from disk; the same fonts on every machine (DejaVu for the
// generic families, Ahem and WPT's test fonts installed, none of the system's).
class WptPage {
	public static inline var HOST = "http://web-platform.test/";

	public static var wpt = "bin/wpt";
	static var fonts:Null<FontMatch> = null;

	// (DejaVu 2.37 for the generic families, import-wpt.mjs fetches it)
	public static inline var DEJAVU = "bin/fonts/dejavu-2.37";

	public static function shared():FontMatch {
		if (fonts != null) return fonts;
		// (helder's own shaping, as the lanes run it: the same pixels however the runner is started, on every OS)
		helder.text.Shaping.engine = helder.text.Shaping.HELDER;
		// (the same fonts on every machine, none of the system's: DejaVu's
		// directory alone, then the fonts WPT's runners install)
		if (!FileSystem.exists(DEJAVU)) throw 'no $DEJAVU (node tests/css/import-wpt.mjs --checkout)';
		Sys.putEnv("HELDER_FONT_DIRS", FileSystem.fullPath(DEJAVU));
		fonts = new FontMatch();
		for (f in installed()) fonts.register(File.getBytes(f), StringTools.endsWith(f, "/Ahem.ttf") ? "Ahem" : null);
		return fonts;
	}

	// The font files installed as a test system's: Ahem, CSSTest's, and
	// Ahem's renamed copies (the tests that ask for one installed: a font
	// named "White Space", "serif", "inherit"...).
	public static function installed():Array<String> {
		var out = ['$wpt/fonts/Ahem.ttf'];
		for (dir in ['$wpt/fonts/CSSTest', '$wpt/fonts/ahem-extra']) {
			var names = FileSystem.exists(dir) ? FileSystem.readDirectory(dir) : [];
			names.sort(Reflect.compare);
			for (n in names) if (StringTools.endsWith(n.toLowerCase(), ".ttf")) out.push('$dir/$n');
		}
		return out.filter(FileSystem.exists);
	}

	public static function parse(path:String):Document {
		var text = File.getContent(path);
		var ext = Path.extension(path).toLowerCase();
		return ext == "xht" || ext == "xhtml" || ext == "xml" || ext == "svg" ? Dom.parseXml(text) : Dom.parse(text);
	}

	public static function url(path:String):String {
		// (forward slashes: Windows' full paths have backslashes, which no URL resolves against)
		var abs = FileSystem.fullPath(path).split("\\").join("/"), root = FileSystem.fullPath(wpt).split("\\").join("/") + "/";
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
			loadBytes: u -> {
				var f = file(u);
				f == null ? null : {bytes: File.getBytes(f)};
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
