package helder.asset;

import haxe.io.Path;
import helder.os.locale.LocaleTag;
import sys.FileSystem;
import sys.io.File;

using StringTools;

typedef StringFile = {
	var tag:String;
	var key:String;
	var file:String;
}

typedef StringProject = {
	var fallback:String;
	var files:Array<StringFile>;
	var messages:Map<String, StringMessage>;
}

class StringFiles {
	public static function read(path:String, folder:String, root:String, warn:String->Void):StringProject {
		var names = FileSystem.readDirectory(folder).filter(name -> name.endsWith(".json") && !FileSystem.isDirectory(Path.join([folder, name])));
		names.sort(Reflect.compare);
		if (names.length == 0) throw '$path has no locale JSON files';
		var files:Array<StringFile> = [], tags = new Map<String, Bool>();
		for (name in names) {
			var raw = name.substr(0, name.length - 5), tag = LocaleTag.normalize(raw);
			if (tag == null || tag.toLowerCase() != raw.toLowerCase() || LocaleTag.base(tag) != tag) throw 'invalid locale filename "$name"';
			if (tags.exists(tag)) throw 'duplicate locale "$tag"';
			tags.set(tag, true);
			files.push({tag: tag, key: '$path/$name', file: Path.join([folder, name])});
		}
		var fallback = files[0].tag, config = Path.join([root, "helder.json"]);
		if (FileSystem.exists(config)) {
			var locale:Dynamic = Reflect.field(haxe.Json.parse(File.getContent(config)), "locale");
			if (locale != null) {
				if (!Std.isOfType(locale, String)) throw "helder.json: locale must be a language tag";
				fallback = LocaleTag.normalize(locale);
				if (fallback == null || !tags.exists(fallback)) throw 'helder.json: locale "$locale" has no file in $path';
			}
		}
		var all = [for (entry in files) entry.tag => parse(entry)];
		var source = all.get(fallback);
		var keys = [for (key in source.keys()) key];
		keys.sort(Reflect.compare);
		for (entry in files) if (entry.tag != fallback) {
			var target = all.get(entry.tag);
			for (key in keys) {
				var message = target.get(key);
				if (message == null) {
					warn('${entry.key}: missing message "$key"');
					continue;
				}
				var expected = source.get(key).params, actual = message.params;
				for (name in expected.keys()) if (!actual.exists(name) || actual.get(name) != expected.get(name))
					throw '${entry.key}: placeholder mismatch for "$key" ($name)';
				for (name in actual.keys()) if (!expected.exists(name))
					throw '${entry.key}: placeholder mismatch for "$key" ($name)';
			}
		}
		return {fallback: fallback, files: files, messages: source};
	}

	static function parse(entry:StringFile):Map<String, StringMessage>
		return try StringMessage.catalogue(File.getContent(entry.file)) catch (e:Dynamic) throw '${entry.key}: $e';
}
