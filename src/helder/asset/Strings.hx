package helder.asset;

import helder.os.Locale;
import helder.os.locale.LocaleTag;

typedef StringSource = {
	var tag:String;
	var key:String;
	var file:Null<String>;
}

class Strings {
	final files = new Map<String, Asset<Map<String, StringMessage>>>();
	final fallback:String;

	@:noCompletion public function new(fallback:String, sources:Array<StringSource>) {
		this.fallback = fallback;
		for (source in sources) {
			var key = StringTools.startsWith(source.key, Bundle.MARK) ? Assets.key(source.key) : source.key, file = source.file;
			files.set(source.tag, Assets.handle("strings", key, _ -> StringMessage.catalogue(Files.read(key, file).toString()), (_, fresh) -> fresh,
				() -> StringMessage.catalogue(Files.readNow(key, file).toString())));
		}
	}

	// Read a message with named string and number arguments.
	@:typescript public function get(key:String, ?params:Dynamic):String {
		for (tag in candidates(Locale.current(), fallback)) {
			var file = files.get(tag);
			if (file == null) continue;
			var message = file.read().get(key);
			if (message != null) return message.format(tag, params);
		}
		return key;
	}

	@:allow(helder.asset) static function candidates(tag:String, fallback:String):Array<String> {
		tag = LocaleTag.base(tag);
		var language = tag.split("-")[0], tags = [tag];
		if (language != tag) tags.push(language);
		if (!tags.contains(fallback)) tags.push(fallback);
		return tags;
	}
}
