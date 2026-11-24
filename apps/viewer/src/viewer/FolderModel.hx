package viewer;

using StringTools;

// The images (and videos) of one folder as the viewer steps through them:
// the browser's list (its order and filter: Browser.viewable), the one
// shown, next and previous wrapping, the neighbours by distance (what to
// prefetch). The list given again (the browser's watch) keeps the one shown
// by name (gone: the one now at its place). Natural order ("img2" before
// "img10", letters without case) is compare's.
class FolderModel {
	// (helder.image's, and the system's where it has decoders: helder.os.SystemImages)
	public static final EXTENSIONS = ["png", "apng", "jpg", "jpeg", "jfif", "gif", "webp", "pdf"].concat(helder.os.SystemImages.available() ? helder.os.SystemImages.EXTENSIONS : []);
	// (video and audio, where the system decodes them: helder.media)
	public static final MEDIA = helder.media.Decoders.available() ? ["mp4", "mov", "m4v", "webm", "mkv", "m4a", "mp3", "flac", "mka"] : [];

	public var dir(default, null) = "";
	public var files(default, null):Array<String> = [];
	// the image shown (-1: none)
	public var index(default, null) = -1;

	public function new() {}

	public var current(get, never):Null<String>;

	function get_current():Null<String>
		return index < 0 ? null : path(index);

	public var name(get, never):String;

	function get_name():String
		return index < 0 ? "" : files[index];

	public function path(i:Int):String
		return join(dir, files[i]);

	public static function join(dir:String, name:String):String
		return dir == "" ? name : dir.endsWith("/") || dir.endsWith("\\") ? dir + name : dir + "/" + name;

	public static function isImage(name:String):Bool {
		var dot = name.lastIndexOf(".");
		return dot > 0 && EXTENSIONS.contains(name.substr(dot + 1).toLowerCase());
	}

	public static function isMedia(name:String):Bool {
		var dot = name.lastIndexOf(".");
		return dot > 0 && MEDIA.contains(name.substr(dot + 1).toLowerCase());
	}

	// the folder's files (in order), the one named shown
	public function set(dir:String, names:Array<String>, name:String) {
		this.dir = dir;
		files = names.copy();
		if (!files.contains(name)) files.push(name);
		index = files.indexOf(name);
	}

	// the list again: the one shown kept by name, else the one now at its
	// place; whether it changed
	public function relist(names:Array<String>):Bool {
		if (names.join("\n") == files.join("\n")) return false;
		var keep = index >= 0 && names.contains(files[index]) ? files[index] : null, at = index;
		files = names.copy();
		index = keep != null ? files.indexOf(keep) : files.length == 0 ? -1 : Std.int(Math.min(Math.max(at, 0), files.length - 1));
		return true;
	}

	// the names, sorted and filtered; the one named keep shown (else the
	// one at the index shown before, else the first)
	public function setEntries(names:Array<String>, ?keep:String) {
		var before = index;
		var wanted = keep;
		files = [for (n in names) if (isImage(n) || isMedia(n) || n == wanted) n];
		files.sort(compare);
		index = wanted != null ? files.indexOf(wanted) : -1;
		if (index < 0 && files.length > 0) index = before < 0 ? 0 : Std.int(Math.min(before, files.length - 1));
	}

	// the next or previous (delta), wrapping; false when there is no other
	public function go(delta:Int):Bool {
		if (files.length < 2) return false;
		index = ((index + delta) % files.length + files.length) % files.length;
		return true;
	}

	public function first():Bool {
		if (files.length == 0 || index == 0) return false;
		index = 0;
		return true;
	}

	public function last():Bool {
		if (files.length == 0 || index == files.length - 1) return false;
		index = files.length - 1;
		return true;
	}

	// the indices around the one shown, nearest first (it, the next, the
	// previous, the one after the next...), at most radius away
	public function around(radius:Int):Array<Int> {
		if (index < 0) return [];
		var out = [index];
		for (d in 1...radius + 1)
			for (s in [d, -d]) {
				var i = ((index + s) % files.length + files.length) % files.length;
				if (!out.contains(i)) out.push(i);
			}
		return out;
	}

	// natural order: runs of digits by their value, the rest without case,
	// then as they are (a stable, total order)
	public static function compare(a:String, b:String):Int {
		var i = 0, j = 0;
		var la = a.toLowerCase(), lb = b.toLowerCase();
		while (i < la.length && j < lb.length) {
			var ca = la.fastCodeAt(i), cb = lb.fastCodeAt(j);
			if (digit(ca) && digit(cb)) {
				var si = i, sj = j;
				while (i < la.length && digit(la.fastCodeAt(i)))
					i++;
				while (j < lb.length && digit(lb.fastCodeAt(j)))
					j++;
				// (by value: leading zeros off, then the longer run is larger)
				var na = la.substring(si, i), nb = lb.substring(sj, j);
				var ta = trimZeros(na), tb = trimZeros(nb);
				if (ta.length != tb.length) return ta.length - tb.length;
				if (ta != tb) return ta < tb ? -1 : 1;
				if (na.length != nb.length) return na.length - nb.length;
				continue;
			}
			if (ca != cb) return ca - cb;
			i++;
			j++;
		}
		if (la.length - i != lb.length - j) return (la.length - i) - (lb.length - j);
		return a == b ? 0 : a < b ? -1 : 1;
	}

	static inline function digit(c:Int):Bool
		return c >= "0".code && c <= "9".code;

	static function trimZeros(s:String):String {
		var k = 0;
		while (k < s.length - 1 && s.fastCodeAt(k) == "0".code)
			k++;
		return s.substr(k);
	}

}
