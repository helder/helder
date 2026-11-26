package helder.text;

import helder.text.hyphenation.Languages;
import helder.text.hyphenation.Patterns;

// The languages a program hyphenates, and their hyphenators by BCP 47 tag.
// A language is added by its patterns (Hyphenation.add(Nl.patterns()):
// helder.text.hyphenation's classes), so a build carries the patterns of the
// languages it names and none of the others; each is read into its trie on
// its first get.
class Hyphenation {
	static final added = new Map<String, Patterns>();
	static final made = new Map<String, Hyphenator>();
	// (a tag asked for, the language it matched: "" none)
	static final matched = new Map<String, String>();

	// (where a tag's own language is not added under it: en is American English's)
	static final ALIASES = [
		"en" => "en-us", "en-au" => "en-gb", "en-nz" => "en-gb", "en-ie" => "en-gb", "en-za" => "en-gb", "en-in" => "en-gb", "en-uk" => "en-gb",
		"de" => "de-1996", "no" => "nb"
	];

	public static function add(p:Patterns) {
		added.set(p.tag, p);
		made.remove(p.tag);
		matched.clear();
	}

	// every language helder has patterns for (Languages.TAGS)
	public static function addAll()
		for (p in Languages.all())
			add(p);

	// the tags of the languages added
	public static function languages():Array<String> {
		var tags = [for (t in added.keys()) t];
		tags.sort(Reflect.compare);
		return tags;
	}

	// the hyphenator of lang's language (BCP 47: nl-BE is nl's, en en-us's,
	// en-AU en-gb's; then any of its primary language's), null when none is added
	public static function get(lang:Null<String>):Null<Hyphenator> {
		if (lang == null || lang == "") return null;
		var tag = matched.get(lang);
		if (tag == null) matched.set(lang, tag = match(lang));
		if (tag == "") return null;
		var h = made.get(tag);
		if (h == null) made.set(tag, h = new Hyphenator(added[tag]));
		return h;
	}

	static function match(lang:String):String {
		var t = StringTools.replace(lang.toLowerCase(), "_", "-");
		while (true) {
			if (added.exists(t)) return t;
			var a = ALIASES.get(t);
			if (a != null && added.exists(a)) return a;
			var dash = t.lastIndexOf("-");
			if (dash < 0) break;
			t = t.substr(0, dash);
		}
		for (k in languages())
			if (StringTools.startsWith(k, t + "-")) return k;
		return "";
	}
}
