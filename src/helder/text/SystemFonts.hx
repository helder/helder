package helder.text;

import haxe.io.Bytes;

// The fonts a program can use: the system's (OpenType files found in the
// usual directories of Linux, Android, Windows and macOS, their names read without
// loading them; in a browser, the fonts the page gives: WebFonts) and fonts
// added from bytes (add: a program may bring its own). match picks a face as CSS does: the
// family (or a generic one: sans-serif, serif, monospace, mapped to
// families common on each system), then the italic style, then the closest
// weight. Faces are loaded (parsed) when first matched.
class SystemFonts {
	static var shared:Null<SystemFonts>;

	final faces:Array<FaceInfo> = [];
	final loaded = new Map<String, FontFile>();
	var scanned = false;

	public static final GENERIC = [
		"sans-serif" => [
			"Segoe UI", "SF Pro Text", "Helvetica Neue", "Helvetica", "Arial", "DejaVu Sans", "Noto Sans", "Roboto", "Liberation Sans", "Cantarell", "Ubuntu",
			"FreeSans", "Verdana"
		],
		"serif" => ["Times New Roman", "Georgia", "DejaVu Serif", "Noto Serif", "Liberation Serif", "Times", "FreeSerif"],
		"monospace" => ["Consolas", "Cascadia Mono", "Menlo", "SF Mono", "DejaVu Sans Mono", "Noto Sans Mono", "Liberation Mono", "Courier New", "FreeMono"],
	];

	// fonts tried for characters the matched face lacks, in order
	public static final FALLBACK = [
		"DejaVu Sans", "Noto Sans", "Segoe UI", "Segoe UI Symbol", "Arial Unicode MS", "FreeSans", "FreeSerif"
	];

	// colour emoji fonts, each loaded when an emoji first needs it
	public static final EMOJI = ["Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji"];

	// fonts tried after those, each loaded when a character first needs it: CJK, other scripts
	public static final MORE = [
		"Noto Sans CJK SC", "Noto Sans SC", "Microsoft YaHei", "PingFang SC", "Hiragino Sans", "Yu Gothic", "Malgun Gothic", "Apple SD Gothic Neo",
		"Source Han Sans SC", "WenQuanYi Zen Hei", "WenQuanYi Micro Hei", "Droid Sans Fallback", "IPAGothic", "Noto Sans Arabic", "Noto Sans Hebrew",
		"Noto Sans Devanagari", "Noto Sans Thai"
	];

	public function new() {}

	// one set of the system's fonts for the program
	public static function get():SystemFonts {
		if (shared == null) shared = new SystemFonts();
		return shared;
	}

	// the files added, and their faces
	final addedFiles:Array<{data:Bytes, faces:Array<FontFile>}> = [];

	// a font's bytes (every face of a collection), found before the system's
	public function add(data:Bytes):Array<FontFile> {
		// (the same file again: a page's font that the program loads too, Asset.font's)
		for (a in addedFiles)
			if (a.data.length == data.length && a.data.compare(data) == 0) return a.faces;
		var out = [];
		for (i in 0...FontFile.faceCount(data)) {
			var f = try FontFile.parse(data, i) catch (e:Dynamic) null;
			if (f == null) continue;
			var key = "added:" + f.id;
			loaded.set(key, f);
			var fi = new FaceInfo(key, i, f.family, f.subfamily, f.weight, f.italic);
			for (a in f.axes)
				if (a.tag == "wght") {
					fi.minWeight = Std.int(a.min);
					fi.maxWeight = Std.int(a.max);
				}
			faces.insert(0, fi);
			fallbackList = null;
			out.push(f);
			#if (target.name == "hxmc") WebFonts.face(f); #end
		}
		addedFiles.push({data: data, faces: out});
		return out;
	}

	// the face closest to the request, or null when there is no font at all
	public function match(family:String, weight = 400, italic = false):Null<FontFile> {
		scan();
		var lower = family.toLowerCase(), generic = GENERIC.exists(lower);
		var names = lower == "sans-serif" ? sans() : generic ? GENERIC.get(lower) : [family].concat(sans());
		// (a generic family: the platform's own face for it first, with its engine: SF on Apple's, fontconfig's alias on Linux)
		if (generic) {
			var f = platformGeneric(lower, weight, italic);
			if (f != null) return f;
		}
		for (name in names) {
			var f = best(name, weight, italic);
			// (a family by name the directories did not have: the platform's)
			if (f == null && !generic && name == family) f = platformFamily(family, weight, italic);
			if (f != null) return f;
		}
		// anything
		for (fi in faces) {
			var f = load(fi);
			if (f != null) return f;
		}
		return null;
	}

	// (in a browser the page's fonts are all there is: helder's Inter, which
	// Page ships, is its sans-serif and its first fallback)
	static function sans():Array<String>
		return web() ? ["Inter"].concat(GENERIC.get("sans-serif")) : GENERIC.get("sans-serif");

	static function web():Bool {
		#if (target.name == "hxmc")
		return hxmc.Platform.os() == 3;
		#else
		return false;
		#end
	}

	// the fallback faces (regular) found on this system
	public function fallbacks():Array<FontFile> {
		if (fallbackList != null) return fallbackList;
		scan();
		var out = [], names = web() ? ["Inter"].concat(FALLBACK) : FALLBACK;
		for (name in names) {
			var f = best(name, 400, false);
			if (f != null && !out.contains(f)) out.push(f);
		}
		return fallbackList = out;
	}

	// (found once; fonts added later find them again)
	var fallbackList:Null<Array<FontFile>> = null;

	// the first of MORE's faces that has a character (null: none)
	public function fallbackFor(cp:Int):Null<FontFile> {
		if (moreFound.exists(cp)) return moreFound.get(cp);
		if (moreFaces == null) {
			scan();
			moreFaces = [];
			for (name in MORE) {
				var fi = pick(name, 400, false);
				if (fi != null && !moreFaces.contains(fi)) moreFaces.push(fi);
			}
		}
		var found:Null<FontFile> = null;
		for (fi in moreFaces) {
			var f = load(fi);
			if (f != null && f.glyph(cp) != 0) {
				found = f;
				break;
			}
		}
		// (none of those: the system's own fallback: fontconfig's, DirectWrite's, Core Text's)
		if (found == null) found = platformFallback(cp);
		moreFound.set(cp, found);
		return found;
	}

	// the platform's fallback for a character (Shaping.backend: fontconfig,
	// IDWriteFontFallback, CTFontCreateForString), its face loaded once
	function platformFallback(cp:Int):Null<FontFile> {
		if (scannedNone()) return null;
		var b = Shaping.backend();
		if (b == null) return null;
		var m = b.fallback(cp);
		return m == null ? null : fileFace(m.path, m.index, cp);
	}

	// (a face of a file the platform named: loaded once; -1: the face of a collection with cp)
	function fileFace(path:String, index:Int, cp:Int):Null<FontFile> {
		var key = path + "#" + index;
		if (!loaded.exists(key)) {
			var f:Null<FontFile> = null;
			try {
				var data = sys.io.File.getBytes(path);
				if (index >= 0) f = FontFile.parse(data, index) else for (i in 0...FontFile.faceCount(data)) {
					var g = try FontFile.parse(data, i) catch (e:Dynamic) null;
					if (g != null && (cp < 0 || g.glyph(cp) != 0)) {
						f = g;
						break;
					}
				}
			} catch (e:Dynamic) {}
			if (f != null) f.path = path;
			loaded.set(key, f);
		}
		var f = loaded.get(key);
		return f != null && (cp < 0 || f.glyph(cp) != 0) ? f : null;
	}

	// a family the scan did not find, as the platform finds it (fontconfig, DirectWrite's system collection, Core Text's descriptors)
	function platformFamily(name:String, weight:Int, italic:Bool):Null<FontFile> {
		if (scannedNone()) return null;
		var key = name.toLowerCase() + "@" + weight + (italic ? "i" : "");
		if (platformFamilies.exists(key)) return platformFamilies.get(key);
		var b = Shaping.backend(), f:Null<FontFile> = null;
		if (b != null) {
			var m = b.find(name, weight, italic);
			if (m != null) f = fileFace(m.path, m.index, -1);
		}
		platformFamilies.set(key, f);
		return f;
	}

	final platformFamilies = new Map<String, Null<FontFile>>();

	// the platform's face for a generic family (TextBackend.generic), at the
	// weight (a variable face's instance); only with the platform's engine
	// (helder's own keeps SystemFonts' lists: the same faces everywhere)
	function platformGeneric(name:String, weight:Int, italic:Bool):Null<FontFile> {
		if (scannedNone() || Shaping.engine != Shaping.SYSTEM) return null;
		var key = "generic:" + name + "@" + weight + (italic ? "i" : "");
		if (platformFamilies.exists(key)) return platformFamilies.get(key);
		var b = Shaping.backend(), f:Null<FontFile> = null;
		var m = b == null ? null : b.generic(name, weight, italic);
		if (m != null)
			for (fi in FaceInfo.read(m.path))
				if (fi.index == m.index) {
					f = load(fi);
					if (f != null && fi.maxWeight > fi.minWeight) {
						var w = weight < fi.minWeight ? fi.minWeight : weight > fi.maxWeight ? fi.maxWeight : weight;
						var k = fi.path + "#" + fi.index + "@" + w;
						if (!loaded.exists(k)) loaded.set(k, f.instance(["wght" => w]));
						f = loaded.get(k);
					}
				}
		platformFamilies.set(key, f);
		return f;
	}

	// (HELDER_NO_SYSTEM_FONTS: none of the system's, fontconfig's neither;
	// HELDER_FONT_DIRS: those directories' alone)
	static function scannedNone():Bool {
		var none = Sys.getEnv("HELDER_NO_SYSTEM_FONTS");
		return none != null && none != "" && none != "0" || only() != null;
	}

	// (HELDER_FONT_DIRS: the directories looked in instead of the system's,
	// the platform's lookups off: the same faces on every machine, for
	// golden images)
	static function only():Null<Array<String>> {
		var d = Sys.getEnv("HELDER_FONT_DIRS");
		return d == null || d == "" ? null : d.split(Sys.systemName() == "Windows" ? ";" : ":");
	}

	var moreFaces:Null<Array<FaceInfo>> = null;

	// the first of EMOJI's faces that has a character (null: none)
	public function emojiFor(cp:Int):Null<FontFile> {
		if (emojiFound.exists(cp)) return emojiFound.get(cp);
		if (emojiFaces == null) {
			scan();
			emojiFaces = [];
			for (name in EMOJI) {
				var fi = pick(name, 400, false);
				if (fi != null && !emojiFaces.contains(fi)) emojiFaces.push(fi);
			}
		}
		var found:Null<FontFile> = null;
		for (fi in emojiFaces) {
			var f = load(fi);
			if (f != null && f.glyph(cp) != 0) {
				found = f;
				break;
			}
		}
		emojiFound.set(cp, found);
		return found;
	}

	var emojiFaces:Null<Array<FaceInfo>> = null;
	final emojiFound = new Map<Int, Null<FontFile>>();
	final moreFound = new Map<Int, Null<FontFile>>();

	// the families found, sorted
	public function families():Array<String> {
		scan();
		var m = new Map<String, Bool>();
		for (f in faces)
			m.set(f.family, true);
		var out = [for (k in m.keys()) k];
		out.sort(Reflect.compare);
		return out;
	}

	function best(name:String, weight:Int, italic:Bool):Null<FontFile> {
		var pick = pick(name, weight, italic);
		if (pick == null) return null;
		var f = load(pick);
		// (a variable face: its instance at the weight, within its range)
		if (f == null || pick.maxWeight <= pick.minWeight) return f;
		var w = weight < pick.minWeight ? pick.minWeight : weight > pick.maxWeight ? pick.maxWeight : weight;
		var key = pick.path + "#" + pick.index + "@" + w;
		if (!loaded.exists(key)) loaded.set(key, f.instance(["wght" => w]));
		return loaded.get(key);
	}

	function pick(name:String, weight:Int, italic:Bool):Null<FaceInfo> {
		var lower = name.toLowerCase();
		var pick:Null<FaceInfo> = null, score = 1 << 30;
		for (fi in faces) {
			if (fi.family.toLowerCase() != lower) continue;
			// (a variable face has every weight of its range)
			var w = fi.maxWeight > fi.minWeight ? (weight < fi.minWeight ? fi.minWeight : weight > fi.maxWeight ? fi.maxWeight : weight) : fi.weight;
			var s = (fi.italic == italic ? 0 : 10000) + Std.int(Math.abs(w - weight)) + (w > weight && weight <= 400 ? 50 : 0);
			if (s < score) {
				score = s;
				pick = fi;
			}
		}
		return pick;
	}

	function load(fi:FaceInfo):Null<FontFile> {
		var key = fi.path + "#" + fi.index;
		if (loaded.exists(fi.path)) return loaded.get(fi.path);
		if (loaded.exists(key)) return loaded.get(key);
		var f = try FontFile.parse(sys.io.File.getBytes(fi.path), fi.index) catch (e:Dynamic) null;
		if (f != null) f.path = fi.path;
		loaded.set(key, f);
		return f;
	}

	// --- discovery ---

	public static function directories():Array<String> {
		var dirs = only();
		if (dirs != null) return dirs;
		var home = Sys.getEnv("HOME");
		return switch Sys.systemName() {
			case "Windows":
				var win = Sys.getEnv("WINDIR") ?? "C:\\Windows";
				var local = Sys.getEnv("LOCALAPPDATA");
				[win + "\\Fonts"].concat(local != null ? [local + "\\Microsoft\\Windows\\Fonts"] : []);
			case "Mac":
				["/System/Library/Fonts", "/Library/Fonts"].concat(home != null ? [home + "/Library/Fonts"] : []);
			case _:
				var xdg = Sys.getEnv("XDG_DATA_HOME");
				// (Android's: /system/fonts, the product's and the system extension's)
				["/usr/share/fonts", "/usr/local/share/fonts", "/system/fonts", "/product/fonts", "/system_ext/fonts"].concat(home != null ? [home + "/.fonts", home + "/.local/share/fonts"] : []).concat(xdg != null ? [xdg + "/fonts"] : []);
		}
	}

	function scan() {
		if (scanned) return;
		scanned = true;
		#if (target.name == "hxmc")
		if (hxmc.Platform.os() == 3) {
			for (b in WebFonts.all())
				add(b);
			return;
		}
		#end
		// (HELDER_NO_SYSTEM_FONTS set: the system's not looked for, only the
		// fonts added: a program's fallback tested as on a bare system)
		var none = Sys.getEnv("HELDER_NO_SYSTEM_FONTS");
		if (none != null && none != "" && none != "0") return;
		// (the faces a last scan found, while its directories are as they were)
		var file = cachePath();
		if (file != null && readCache(file)) return;
		var seen = new Map<String, Bool>(), walked = [];
		function walk(dir:String, depth:Int) {
			if (depth > 6 || seen.exists(dir)) return;
			seen.set(dir, true);
			walked.push(dir);
			var entries = try sys.FileSystem.readDirectory(dir) catch (e:Dynamic) null;
			if (entries == null) return;
			entries.sort(Reflect.compare);
			for (e in entries) {
				var p = dir + "/" + e;
				var lower = e.toLowerCase();
				if (StringTools.endsWith(lower, ".ttf") || StringTools.endsWith(lower, ".ttc") || StringTools.endsWith(lower, ".otf")) {
					for (fi in FaceInfo.read(p))
						faces.push(fi);
				} else if (lower.indexOf(".") < 0 && try sys.FileSystem.isDirectory(p) catch (e:Dynamic) false) walk(p, depth + 1);
			}
		}
		for (d in directories())
			walk(d, 0);
		if (file != null) writeCache(file, walked);
	}

	// --- the scan kept: the faces found, with the times of the directories
	// walked (each one's, its files' added or removed), so that a launch
	// reads one small file instead of every font's (on a Mac about 75 ms):
	// "helder-fonts 1", then "d <time> <dir>" and "f <index> <weight>
	// <italic> <min> <max> <family> <subfamily> <path>", tab-separated

	// (the app's cache (helder.os.Paths); none for HELDER_FONT_DIRS' own, nor on the web or Eval)
	static function cachePath():Null<String> {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		if (only() != null) return null;
		var d = try helder.os.Paths.cache() catch (_:Dynamic) null;
		return d == null ? null : d + "/helder-fonts.txt";
		#else
		return null;
		#end
	}

	static function stamp(dir:String):String
		return try Std.string(sys.FileSystem.stat(dir).mtime.getTime()) catch (_:Dynamic) "-";

	function readCache(file:String):Bool {
		var text = try sys.io.File.getContent(file) catch (_:Dynamic) null;
		if (text == null) return false;
		var lines = text.split("\n");
		if (lines[0] != "helder-fonts 1") return false;
		var found = [];
		for (l in lines.slice(1)) {
			var c = l.split("\t");
			if (c[0] == "d") {
				if (c.length != 3 || stamp(c[2]) != c[1]) return false;
			} else if (c[0] == "f" && c.length == 9) {
				var fi = new FaceInfo(c[8], Std.parseInt(c[1]), c[6], c[7], Std.parseInt(c[2]), c[3] == "1");
				fi.minWeight = Std.parseInt(c[4]);
				fi.maxWeight = Std.parseInt(c[5]);
				found.push(fi);
			}
		}
		for (fi in found)
			faces.push(fi);
		return true;
	}

	function writeCache(file:String, walked:Array<String>) {
		var b = new StringBuf();
		b.add("helder-fonts 1\n");
		for (d in walked)
			b.add('d\t${stamp(d)}\t$d\n');
		for (fi in faces)
			if (!StringTools.startsWith(fi.path, "added:"))
				b.add('f\t${fi.index}\t${fi.weight}\t${fi.italic ? 1 : 0}\t${fi.minWeight}\t${fi.maxWeight}\t${fi.family}\t${fi.subfamily}\t${fi.path}\n');
		// (written whole, then put in place: another process may be reading it)
		var tmp = file + "." + Std.random(0x7FFFFFFF);
		try {
			sys.io.File.saveContent(tmp, b.toString());
			sys.FileSystem.rename(tmp, file);
		} catch (_:Dynamic) {
			try sys.FileSystem.deleteFile(tmp) catch (_:Dynamic) {}
		}
	}
}

// a face of a font file, as discovery reads it (names, weight, style)
class FaceInfo {
	public final path:String;
	public final index:Int;
	public final family:String;
	public final subfamily:String;
	public final weight:Int;
	public final italic:Bool;
	// a variable face's wght axis (the weights it has; 0, 0: not variable)
	public var minWeight = 0;
	public var maxWeight = 0;

	public function new(path, index, family, subfamily, weight, italic) {
		this.path = path;
		this.index = index;
		this.family = family;
		this.subfamily = subfamily;
		this.weight = weight;
		this.italic = italic;
	}

	// the faces of an OpenType file, from its tables' directory, name and OS/2
	// tables only (read from the file at their offsets)
	public static function read(path:String):Array<FaceInfo> {
		var out = [];
		var f = try sys.io.File.read(path, true) catch (e:Dynamic) null;
		if (f == null) return out;
		try {
			// (each header read whole, its fields from the bytes: a read a field
			// was a system call a byte, for every font of the system)
			inline function u32(b:Bytes, p:Int):Int
				return (b.get(p) << 24) | (b.get(p + 1) << 16) | (b.get(p + 2) << 8) | b.get(p + 3);
			var head = f.read(12);
			var offsets = [0];
			if (head.getString(0, 4) == "ttcf") {
				var n = u32(head, 8), table = f.read(n * 4);
				offsets = [for (k in 0...n) u32(table, k * 4)];
			}
			for (i in 0...offsets.length) {
				f.seek(offsets[i], SeekBegin);
				var h = f.read(12), version = u32(h, 0);
				// (TrueType's, 'true', 'OTTO': CFF's)
				if (version != 0x00010000 && version != 0x74727565 && version != 0x4F54544F) continue;
				var n = (h.get(4) << 8) | h.get(5);
				var dir = f.read(n * 16);
				var name = -1, nameLen = 0, os2 = -1, os2Len = 0, fvar = -1, fvarLen = 0;
				for (k in 0...n) {
					var t = dir.getString(k * 16, 4);
					var off = u32(dir, k * 16 + 8), len = u32(dir, k * 16 + 12);
					if (t == "name") {
						name = off;
						nameLen = len;
					} else if (t == "OS/2") {
						os2 = off;
						os2Len = len;
					} else if (t == "fvar") {
						fvar = off;
						fvarLen = len;
					}
				}
				if (name < 0) continue;
				// a small font of just these two tables, read by FontFile's own code
				f.seek(name, SeekBegin);
				var nameBytes = f.read(nameLen);
				var weight = 400, italic = false;
				if (os2 >= 0 && os2Len >= 64) {
					f.seek(os2, SeekBegin);
					var o = f.read(64);
					weight = (o.get(4) << 8) | o.get(5);
					italic = ((o.get(62) << 8) | o.get(63)) & 1 != 0;
				}
				var names = Names.read(nameBytes);
				var sub = names.subfamily.toLowerCase();
				if (sub.indexOf("italic") >= 0 || sub.indexOf("oblique") >= 0) italic = true;
				var fi = new FaceInfo(path, i, names.family, names.subfamily, weight, italic);
				// (a variable face: its wght axis's range)
				if (fvar >= 0 && fvarLen >= 16) {
					f.seek(fvar, SeekBegin);
					var v = f.read(fvarLen);
					var arrays = (v.get(4) << 8) | v.get(5), count = (v.get(8) << 8) | v.get(9), size = (v.get(10) << 8) | v.get(11);
					for (k in 0...count) {
						var p = arrays + k * size;
						if (p + 16 > fvarLen || v.getString(p, 4) != "wght") continue;
						inline function fixed(q:Int):Int
							return ((v.get(q) << 24) | (v.get(q + 1) << 16)) >> 16;
						fi.minWeight = fixed(p + 4);
						fi.maxWeight = fixed(p + 12);
					}
				}
				out.push(fi);
			}
		} catch (e:Dynamic) {}
		f.close();
		return out;
	}
}

// the family and subfamily of a name table
class Names {
	public static function read(b:Bytes):{family:String, subfamily:String} {
		inline function u16(p:Int)
			return (b.get(p) << 8) | b.get(p + 1);
		var count = u16(2), strings = u16(4);
		var best = new Map<Int, String>();
		for (i in 0...count) {
			var r = 6 + 12 * i;
			var platform = u16(r), encoding = u16(r + 2), language = u16(r + 4), id = u16(r + 6);
			if (id != 1 && id != 2 && id != 16 && id != 17) continue;
			var len = u16(r + 8), off = strings + u16(r + 10);
			if (off + len > b.length) continue;
			var s = null;
			if (platform == 3 || platform == 0) {
				var sb = new StringBuf();
				var k = 0;
				while (k + 1 < len) {
					sb.addChar(u16(off + k));
					k += 2;
				}
				s = sb.toString();
			} else if (platform == 1 && encoding == 0) s = b.getString(off, len);
			if (s == null) continue;
			var rank = platform == 3 && language == 0x409 ? 3 : platform == 3 ? 2 : platform == 0 ? 1 : 0;
			var key = id * 10 + rank;
			if (!best.exists(key)) best.set(key, s);
		}
		function pick(ids:Array<Int>):String {
			for (id in ids)
				for (rank in [3, 2, 1, 0])
					if (best.exists(id * 10 + rank)) return best.get(id * 10 + rank);
			return "";
		}
		return {family: pick([16, 1]), subfamily: pick([17, 2])};
	}
}
