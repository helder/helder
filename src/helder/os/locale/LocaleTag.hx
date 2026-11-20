package helder.os.locale;

class LocaleTag {
	static final subtag = ~/^[a-zA-Z0-9]{1,8}$/;
	static final language = ~/^[a-zA-Z]{2,8}$/;

	public static function normalize(value:Null<String>):Null<String> {
		if (value == null) return null;
		var tag = StringTools.trim(value), mod = tag.indexOf("@");
		var modifier = mod < 0 ? "" : tag.substr(mod + 1);
		if (mod >= 0) tag = tag.substr(0, mod);
		var encoding = tag.indexOf(".");
		if (encoding >= 0) tag = tag.substr(0, encoding);
		var parts = tag.split("_").join("-").split("-");
		if (!language.match(parts[0]) || parts[0].toLowerCase() == "posix") return null;
		parts[0] = switch parts[0].toLowerCase() {
			case "iw": "he";
			case "in": "id";
			case "ji": "yi";
			case "mo": "ro";
			case l: l;
		};
		if (modifier == "latin" || modifier == "cyrillic") parts.insert(1, modifier == "latin" ? "Latn" : "Cyrl");
		var extension = false;
		for (i in 1...parts.length) {
			var part = parts[i].toLowerCase();
			if (!subtag.match(part)) return null;
			if (part.length == 1) extension = true;
			if (!extension && ~/^[a-z]{2}$/.match(part)) part = part.toUpperCase();
			if (!extension && ~/^[a-z]{4}$/.match(part)) part = part.charAt(0).toUpperCase() + part.substr(1);
			parts[i] = part;
		}
		return parts.join("-");
	}

	public static function base(tag:String):String {
		var parts = tag.split("-");
		for (i in 1...parts.length)
			if (parts[i].length == 1) return parts.slice(0, i).join("-");
		return tag;
	}

	public static function preferred(values:Array<String>):Array<String> {
		var tags = [];
		for (value in values) {
			var tag = normalize(value);
			if (tag != null && !tags.contains(tag)) tags.push(tag);
		}
		return tags.length == 0 ? ["en-US"] : tags;
	}
}
