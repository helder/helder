package helder.cli;

import haxe.io.Path;
import helder.canvas.Bitmap;
import helder.css.CssMedia.CssMediaContext;
import helder.css.CssMedia;
import helder.dom.Dom;
import helder.image.Image;
import helder.cli.Style.Tone;
import helder.ui.box.PagedView;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// `helder pdf <input.html> [-o out.pdf] [--base-url <url>] [--media
// print|screen] [--stylesheet <css>]...`: an HTML document laid out on
// pages (PagedView: CSS Paged Media, fragmentation, margin boxes, GCPM)
// and written as a PDF with its text, outline and links. Its sheets,
// images and fonts are read relative to the file, or to --base-url (a
// file: URL or a path); http(s) ones are not loaded yet (reported).
class PdfCommand {
	public static function run(o:Options):Int {
		var input = o.positionals[0];
		if (input == null) {
			Term.err(Style.usage("helder pdf: an HTML file (helder pdf <input.html> [-o out.pdf])"));
			return 2;
		}
		if (!FileSystem.exists(input) || FileSystem.isDirectory(input)) {
			Term.err(Style.status("error", Fail, 'helder pdf: no file $input'));
			return 1;
		}
		var media:CssMediaContext = switch o.value("media") ?? "print" {
			case "print": CssMedia.PRINT;
			case "screen": {type: "screen", width: CssMedia.PRINT.width, height: CssMedia.PRINT.height, resolution: 1, color: 8};
			case m:
				Term.err(Style.usage('helder pdf: --media $m: print or screen'));
				return 2;
		}
		var out = o.out ?? Path.withExtension(input, "pdf");
		var base = o.value("base-url") ?? url(input);
		if (!base.contains("://")) base = url(base.endsWith("/") ? base + "index.html" : base);
		var skipped = new Map<String, Bool>();
		function read(u:String):Null<haxe.io.Bytes> {
			var f = file(u);
			if (f != null) return File.getBytes(f);
			if (!skipped.exists(u)) {
				skipped.set(u, true);
				Term.err(Style.status("skipped", Warn, u.startsWith("http") ? '$u (http(s) is not loaded yet: files only)' : '$u (no such file)'));
			}
			return null;
		}
		// (helder.css.CssSheet by its path: its module's Style rule would hide helder.cli.Style)
		var user = [];
		for (s in o.values("stylesheet")) {
			if (!FileSystem.exists(s)) {
				Term.err(Style.status("error", Fail, 'helder pdf: no stylesheet $s'));
				return 1;
			}
			var decoded = helder.css.Css.decode(File.getBytes(s));
			user.push(helder.css.CssSheet.parse(decoded.text, User, {url: url(s), loadBytes: u -> sheetBytes(read(u)), encoding: decoded.encoding}));
		}
		var t0 = haxe.Timer.stamp();
		var pages = 0;
		var pdf = try {
			var text = File.getContent(input);
			var doc = ~/\.(xht|xhtml|xml)$/i.match(input) ? Dom.parseXml(text) : Dom.parse(text);
			var v = new PagedView(doc, options(base, media, user, read));
			pages = v.layout();
			v.pdf();
		} catch (e:haxe.Exception) {
			Term.err(Style.status("error", Fail, 'helder pdf: $input: ${e.message}'));
			return 1;
		}
		try File.saveBytes(out, pdf) catch (e:Dynamic) {
			Term.err(Style.status("error", Fail, 'helder pdf: $out not written ($e)'));
			return 1;
		}
		Term.out(Style.status("wrote", Ok, '${Style.path(out)} ($pages pages, ${Math.round(pdf.length / 1024)} KB, ${Math.round((haxe.Timer.stamp() - t0) * 1000)} ms)'));
		return 0;
	}

	// (the paged host's options: sheets, fonts and images read by read)
	static function options(base:String, media:CssMediaContext, user:Array<helder.css.CssSheet>, read:String->Null<haxe.io.Bytes>):PagedViewOptions
		return {
			url: base,
			media: media,
			user: user,
			load: u -> read(u)?.toString(),
			loadBytes: u -> sheetBytes(read(u)),
			font: read,
			image: u -> {
				if (u.toLowerCase().split("?")[0].endsWith(".svg")) return null;
				var b = read(u);
				var bitmap = b == null ? null : try Bitmap.fromImage(Image.decode(b)) catch (_:Dynamic) null;
				// (its file kept: a JPEG or PNG written into the PDF as it is)
				if (bitmap != null) bitmap.source = b;
				bitmap;
			}
		};

	static function sheetBytes(bytes:Null<haxe.io.Bytes>):Null<{bytes:haxe.io.Bytes, ?charset:String}>
		return bytes == null ? null : {bytes: bytes};

	// (a path's file: URL, forward slashes)
	static function url(path:String):String
		return "file://" + FileSystem.fullPath(path).split("\\").join("/");

	// (a file: URL's path, its query and fragment aside; null: not a file there)
	static function file(u:String):Null<String> {
		if (!u.startsWith("file://")) return null;
		var p = u.substr(7);
		for (c in ["?", "#"]) {
			var k = p.indexOf(c);
			if (k >= 0) p = p.substr(0, k);
		}
		p = p.urlDecode();
		return FileSystem.exists(p) && !FileSystem.isDirectory(p) ? p : null;
	}
}
