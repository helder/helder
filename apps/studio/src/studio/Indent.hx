package studio;

using StringTools;

// An agent's edit whose text is indented otherwise than the file: spaces
// for the file's tabs, or none. A tab can't be written raw in a tool call's
// JSON (Claude Code refuses the call), so an agent writes spaces or leaves
// the indentation out; old is found with each run of spaces or tabs loose
// (its first line from its first word), and new takes the file's
// indentation: its lines' leading spaces past old's first line's as the
// file's, a tab a level when the file indents with tabs.
class Indent {
	// where old is: as written, else loosely; null: nowhere; throws: more than once
	public static function find(text:String, old:String):Null<{start:Int, end:Int, loose:Bool}> {
		var at = text.indexOf(old);
		if (at >= 0) {
			if (text.indexOf(old, at + 1) >= 0) throw "more than once";
			return {start: at, end: at + old.length, loose: false};
		}
		var lines = old.trim().split("\n");
		if (lines.length == 0 || lines[0].trim() == "") return null;
		var r = new EReg([for (i => l in lines) (i == 0 ? "" : "[ \\t]*") + [for (w in ~/[ \t]+/g.split(l.trim())) EReg.escape(w)].join("[ \\t]+")].join("[ \\t]*\\r?\\n"), "");
		var found = [], pos = 0;
		while (pos <= text.length && r.matchSub(text, pos)) {
			var p = r.matchedPos();
			found.push({start: p.pos, end: p.pos + p.len, loose: true});
			pos = p.pos + Std.int(Math.max(1, p.len));
		}
		if (found.length > 1) throw "more than once";
		return found.length == 0 ? null : found[0];
	}

	// new for old found loosely (at.start to at.end): indented as the file is there
	public static function adapt(text:String, at:{start:Int, end:Int}, old:String, next:String):String {
		var olds = ~/^(\s*\n)+/.replace(old, "").split("\n");
		var own = lead(olds[0]);
		var file = lead(text.substring(text.lastIndexOf("\n", at.start - 1) + 1, at.start));
		// (the file's indentation of each line found; its first line's before the match)
		var found = [for (i => l in text.substring(at.start, at.end).split("\n")) i == 0 ? file : lead(l)];
		var tabs = file.indexOf("\t") >= 0 || ~/\n\t/.match(text);
		var lines = next.split("\n");
		// (the first line goes where old's first word was: its indentation the file's already)
		if (lines[0].startsWith(own)) lines[0] = lines[0].substr(own.length);
		var extra = [for (l in lines.slice(1).concat(olds.slice(1))) if (l.trim() != "" && l.startsWith(own) && lead(l).length > own.length) lead(l).length - own.length];
		var unit = extra.length == 0 ? 4 : Lambda.fold(extra, (a, b) -> Std.int(Math.min(a, b)), extra[0]);
		for (i in 1...lines.length) {
			var l = lines[i], w = lead(l);
			if (l.trim() == "") continue;
			// (indented as one of old's lines, the one at its place first: as the file's line found there)
			var j = [i].concat([for (k in 0...olds.length) k]).filter(k -> k < olds.length && k < found.length && lead(olds[k]) == w);
			if (j.length > 0) lines[i] = found[j[0]] + l.substr(w.length);
			else if (w.startsWith(own) && w.indexOf("\t") < 0) {
				var more = w.length - own.length;
				lines[i] = file + (tabs ? "".lpad("\t", Std.int(more / unit)) + "".lpad(" ", Std.int(more % unit)) : "".lpad(" ", more)) + l.substr(w.length);
			}
		}
		return lines.join("\n");
	}

	static function lead(s:String):String {
		var i = 0;
		while (i < s.length && (s.fastCodeAt(i) == " ".code || s.fastCodeAt(i) == "\t".code))
			i++;
		return s.substr(0, i);
	}
}
