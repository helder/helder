package viewer;

import viewer.Files;

using StringTools;

enum abstract Glyph(String) to String {
	var FolderGlyph = "folder";
	var ImageGlyph = "image";
	var VideoGlyph = "video";
	var AudioGlyph = "audio";
	var PdfGlyph = "pdf";
	var DocumentGlyph = "document";
}

// What a file is, by its name: the words the list and the inspector say
// ("JPEG image"), the glyph drawn for it, and whether the viewer opens it.
class Kinds {
	static final NAMES = [
		"jpg" => "JPEG image", "jpeg" => "JPEG image", "jfif" => "JPEG image", "png" => "PNG image", "apng" => "PNG image", "gif" => "GIF image",
		"webp" => "WebP image", "heic" => "HEIC image", "heif" => "HEIF image", "avif" => "AVIF image", "tif" => "TIFF image", "tiff" => "TIFF image",
		"dng" => "DNG RAW image", "cr2" => "Canon RAW image", "cr3" => "Canon RAW image", "nef" => "Nikon RAW image", "arw" => "Sony RAW image",
		"raf" => "Fujifilm RAW image", "orf" => "Olympus RAW image", "rw2" => "Panasonic RAW image", "pdf" => "PDF document", "mp4" => "MPEG-4 movie",
		"m4v" => "MPEG-4 movie", "mov" => "QuickTime movie", "webm" => "WebM movie", "mkv" => "Matroska movie", "m4a" => "MPEG-4 audio",
		"mp3" => "MP3 audio", "flac" => "FLAC audio", "mka" => "Matroska audio", "wav" => "WAVE audio", "txt" => "Plain text", "md" => "Markdown text",
		"json" => "JSON", "zip" => "ZIP archive", "svg" => "SVG image", "html" => "HTML page"
	];

	public static function extension(name:String):String {
		var dot = name.lastIndexOf(".");
		return dot > 0 ? name.substr(dot + 1).toLowerCase() : "";
	}

	public static function kind(e:Entry):String {
		if (e.kind == Folder) return "Folder";
		var x = extension(e.name);
		var named = NAMES.get(x);
		return named != null ? named : x == "" ? "Document" : x.toUpperCase() + " file";
	}

	public static function glyph(e:Entry):Glyph {
		if (e.kind == Folder) return FolderGlyph;
		var x = extension(e.name);
		return x == "pdf" ? PdfGlyph : FolderModel.isMedia(e.name) ? (audio(e.name) ? AudioGlyph : VideoGlyph) : FolderModel.isImage(e.name) ? ImageGlyph : DocumentGlyph;
	}

	public static function audio(name:String):Bool
		return ["m4a", "mp3", "flac", "mka", "wav"].contains(extension(name));

	// what the full-size viewer shows
	public static function viewable(e:Entry):Bool
		return e.kind != Folder && (FolderModel.isImage(e.name) || FolderModel.isMedia(e.name));

	public static function hidden(name:String):Bool
		return name.startsWith(".");

	// a size as the list and inspector say it ("3.8 MB"); a folder's none
	public static function size(bytes:Float):String
		return bytes >= 1e9 ? one(bytes / 1e9) + " GB" : bytes >= 1e6 ? one(bytes / 1e6) + " MB" : bytes >= 1e3 ? Math.round(bytes / 1e3) + " KB" : Std.int(bytes) + " bytes";

	static function one(v:Float):String {
		var s = Std.string(Math.round(v * 10) / 10);
		return s.indexOf(".") < 0 ? s + ".0" : s;
	}

	static final MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

	// a time as "14 Jun 2026, 22:51" (local)
	public static function date(seconds:Float):String {
		if (seconds <= 0) return "";
		var d = Date.fromTime(seconds * 1000);
		return '${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}, ${StringTools.lpad(Std.string(d.getHours()), "0", 2)}:${StringTools.lpad(Std.string(d.getMinutes()), "0", 2)}';
	}

	// a count with thousands' separators ("48,213")
	public static function count(n:Int):String {
		var s = Std.string(n), out = "";
		while (s.length > 3) {
			out = "," + s.substr(s.length - 3) + out;
			s = s.substr(0, s.length - 3);
		}
		return s + out;
	}

	public static function items(n:Int):String
		return count(n) + (n == 1 ? " item" : " items");

	// a document glyph's label colour, by extension (the design's)
	public static function tint(ext:String):String
		return switch ext {
			case "xlsx" | "xls" | "csv" | "numbers": "#1f8a4c";
			case "docx" | "doc" | "pages": "#2f6fd6";
			case "zip" | "gz" | "tar" | "7z": "#8a5a2b";
			case "gpx" | "kml": "#0f7f79";
			case "html" | "js" | "ts" | "hx" | "json": "#7e5bef";
			case _: "#6b6b6b";
		}
}
