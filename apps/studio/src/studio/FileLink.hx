package studio;

using StringTools;

// A link of an agent's reply to a file of the project: a path (relative to
// the project's directory, absolute, or a file: URL) and a line ("#L12",
// "#L12-L20", ":12", ":12:4"); null: a web address, or outside the project
class FileLink {
	public static function parse(href:String, dir:String):Null<{path:String, line:Null<Int>}> {
		var h = href.trim();
		// (a scheme: "https:", "mailto:"; not a file's line, "pond.helder:41")
		if (~/^[a-z][a-z0-9+.-]*:(?![0-9])/i.match(h) && !h.startsWith("file:")) return null;
		if (h.startsWith("file://")) h = h.substr(7) else if (h.startsWith("file:")) h = h.substr(5);
		h = try h.urlDecode() catch (_:Dynamic) h;
		var line:Null<Int> = null, at = ~/^(.*?)(?:#L(\d+)(?:-L?\d+)?|:(\d+)(?::\d+)?)$/;
		if (at.match(h)) {
			h = at.matched(1);
			line = Std.parseInt(at.matched(2) ?? at.matched(3));
		}
		if (h == "") return null;
		var path = haxe.io.Path.normalize(haxe.io.Path.isAbsolute(h) ? h : dir + "/" + h);
		return path.startsWith(dir + "/") ? {path: path, line: line} : null;
	}
}
