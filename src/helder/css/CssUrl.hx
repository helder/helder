package helder.css;

using StringTools;

// A URL reference resolved against a base (RFC 3986 §5.2): what @import,
// <link href> and url() need. Nothing is fetched here.
class CssUrl {
	public static function resolve(base:Null<String>, ref:String):String {
		if (base == null || base == "" || scheme(ref) != null) return ref;
		var b = parts(base);
		if (ref.startsWith("//")) return b.scheme + ":" + ref;
		if (ref == "") return base.split("#")[0];
		if (ref.startsWith("#")) return base.split("#")[0] + ref;
		var r = parts(ref);
		var path = if (ref.startsWith("/")) r.path else if (r.path == "") b.path else {
			var dir = b.path.lastIndexOf("/");
			(dir < 0 ? (b.authority != null ? "/" : "") : b.path.substr(0, dir + 1)) + r.path;
		}
		var query = r.path == "" && r.query == null ? b.query : r.query;
		return (b.scheme != null ? b.scheme + ":" : "") + (b.authority != null ? "//" + b.authority : "") + dots(path) + (query != null ? "?" + query : "")
			+ (r.fragment != null ? "#" + r.fragment : "");
	}

	static function scheme(s:String):Null<String> {
		var r = ~/^([A-Za-z][A-Za-z0-9+.-]*):/;
		return r.match(s) ? r.matched(1) : null;
	}

	static function parts(s:String):{scheme:Null<String>, authority:Null<String>, path:String, query:Null<String>, fragment:Null<String>} {
		var fragment = null, query = null;
		var hash = s.indexOf("#");
		if (hash >= 0) {
			fragment = s.substr(hash + 1);
			s = s.substr(0, hash);
		}
		var q = s.indexOf("?");
		if (q >= 0) {
			query = s.substr(q + 1);
			s = s.substr(0, q);
		}
		var sc = scheme(s);
		if (sc != null) s = s.substr(sc.length + 1);
		var authority = null;
		if (s.startsWith("//")) {
			var end = s.indexOf("/", 2);
			authority = end < 0 ? s.substr(2) : s.substring(2, end);
			s = end < 0 ? "" : s.substr(end);
		}
		return {scheme: sc, authority: authority, path: s, query: query, fragment: fragment};
	}

	// (dot segments removed, §5.2.4)
	static function dots(path:String):String {
		var out = [];
		var segs = path.split("/");
		for (k in 0...segs.length) {
			var s = segs[k];
			if (s == ".") {
				if (k == segs.length - 1) out.push("");
			} else if (s == "..") {
				if (out.length > 1) out.pop();
				if (k == segs.length - 1) out.push("");
			} else out.push(s);
		}
		return out.join("/");
	}
}
