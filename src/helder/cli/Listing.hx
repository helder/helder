package helder.cli;

import haxe.DynamicAccess;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// helder.json's "listing": the stores' pages as text, which `helder publish
// --listing` sends with the screenshots. A few fields both stores share,
// each mapped onto the stores' own attributes; and under "play" and
// "appStore" the stores' resources by their own API names, their
// attributes sent as they are, over the shared ones: a field a store adds
// later works without helder knowing it. "locales" holds other languages'
// localized fields (the default language: Play's details', App Store
// Connect's primary locale, else en-US), each a Google Play language or an
// App Store locale, sent to the other store in its spelling (ja-JP and ja,
// iw-IL and he, zh-CN and zh-Hans: SPELLING), to neither when it has none.
// A string "${NAME}" is the environment's NAME (a phone number kept out of a
// public repository; not set: the field left out). Only what is set is
// sent: a field, a language or an image type not given is left as the store
// has it, and nothing is deleted for being absent. All of it is checked
// (validate, images) before the first request.
//
//   "listing": {
//     "title": "Little Skies",                Play's title, App Store's name (30 characters)
//     "subtitle": "Mini golf in the sky",     App Store's (30)
//     "summary": "...",                       Play's short description (80)
//     "description": "store/description.txt" both stores' (4000; a file beside helder.json, or the text)
//     "keywords": ["mini golf", "puzzle"],    App Store's (100 together)
//     "promo": "...",                         App Store's promotional text (170)
//     "notes": "...",                         the build's: Play's release notes (500, --play), the App Store\'s whatsNew (--submit; not on a first version)
//     "website", "support", "privacy":        https URLs; "email"; "copyright": "2026 Codeurs"
//     "category": "GAMES_SPORTS",             App Store's (a game's: GAMES, and this its subcategory)
//     "collects": false, "ads": false         the answers helder setup gives for App Privacy, data safety, ads
//     "play": {"listing": {...}, "details": {...}, "dataSafety": "store/data-safety.csv"},
//     "appStore": {"app", "info", "infoLocalization", "version", "versionLocalization", "ageRating",
//                  "reviewDetail": {...attributes}, "categories": {"secondaryCategory": "ENTERTAINMENT"},
//                  "price": 0, "availability": {"territories": "all", "availableInNewTerritories": true}},
//     "locales": {"nl-NL": {the localized fields, "play": {"listing"}, "appStore": {"infoLocalization", "versionLocalization"}}}
//   }
//
// App Store Connect's age rating questions unanswered (null there, not
// given here) are listed, so that one Apple adds shows up. The price (0:
// free; {"amount": 0.99, "territory": "FRA"}: a base territory other
// than the USA, the others priced from it by Apple) and the availability
// (the territories: "all", or their codes, USA, BEL, ...) are sent when
// they differ from App Store Connect's. Play's data safety form is its
// CSV (exported once from Play Console: App content, Data safety, Export
// to CSV), a file beside helder.json, sent each time (Play cannot read it
// back).
class Listing {
	static final LOCALIZED = ["title", "subtitle", "summary", "description", "keywords", "promo", "notes"];
	static final SHARED = LOCALIZED.concat(["website", "support", "privacy", "email", "copyright", "category", "collects", "ads", "play", "appStore", "locales"]);
	static final PLAY = ["listing", "details", "dataSafety"];
	static final APP_STORE = [
		"app", "info", "infoLocalization", "version", "versionLocalization", "ageRating", "reviewDetail", "categories", "price", "availability"
	];
	static final LIMITS = ["title" => 30, "subtitle" => 30, "summary" => 80, "promo" => 170, "notes" => 4000, "description" => 4000];

	// the languages Google Play's listings take (the API's codes), the
	// locales App Store Connect's take: checked before the first request,
	// since a code a store refuses fails on its own request, after others
	public static final PLAY_LANGUAGES = [
		"af", "am", "ar", "az-AZ", "be", "bg", "bn-BD", "ca", "cs-CZ", "da-DK", "de-DE", "el-GR", "en-AU", "en-CA", "en-GB", "en-IN", "en-SG", "en-US",
		"en-ZA", "es-419", "es-ES", "es-US", "et", "eu-ES", "fa", "fa-AE", "fa-AF", "fa-IR", "fi-FI", "fil", "fr-CA", "fr-FR", "gl-ES", "gu", "hi-IN",
		"hr", "hu-HU", "hy-AM", "id", "is-IS", "it-IT", "iw-IL", "ja-JP", "ka-GE", "kk", "km-KH", "kn-IN", "ko-KR", "ky-KG", "lo-LA", "lt", "lv",
		"mk-MK", "ml-IN", "mn-MN", "mr-IN", "ms", "ms-MY", "my-MM", "ne-NP", "nl-NL", "no-NO", "pa", "pl-PL", "pt-BR", "pt-PT", "rm", "ro", "ru-RU",
		"si-LK", "sk", "sl", "sq", "sr", "sv-SE", "sw", "ta-IN", "te-IN", "th", "tr-TR", "uk", "ur", "vi", "zh-CN", "zh-HK", "zh-TW", "zu"
	];
	public static final APP_STORE_LOCALES = [
		"ar-SA", "bn-BD", "ca", "cs", "da", "de-DE", "el", "en-AU", "en-CA", "en-GB", "en-US", "es-ES", "es-MX", "fi", "fr-CA", "fr-FR", "gu-IN", "he",
		"hi", "hr", "hu", "id", "it", "ja", "kn-IN", "ko", "ml-IN", "mr-IN", "ms", "nl-NL", "no", "or-IN", "pa-IN", "pl", "pt-BR", "pt-PT", "ro", "ru",
		"sk", "sl-SI", "sv", "ta-IN", "te-IN", "th", "tr", "uk", "ur-PK", "vi", "zh-Hans", "zh-Hant"
	];
	// (one language the stores spell differently: Play's => App Store Connect's;
	// none where it is ambiguous: es-419 is not es-MX, zh-HK neither Chinese)
	static final SPELLING = [
		"ar" => "ar-SA", "cs-CZ" => "cs", "da-DK" => "da", "el-GR" => "el", "fi-FI" => "fi", "gu" => "gu-IN", "hi-IN" => "hi", "hu-HU" => "hu",
		"it-IT" => "it", "iw-IL" => "he", "ja-JP" => "ja", "ko-KR" => "ko", "no-NO" => "no", "pa" => "pa-IN", "pl-PL" => "pl", "ru-RU" => "ru",
		"sl" => "sl-SI", "sv-SE" => "sv", "tr-TR" => "tr", "ur" => "ur-PK", "zh-CN" => "zh-Hans", "zh-TW" => "zh-Hant"
	];

	// a listing's language in a store's spelling ("play", "appStore"); null: the store has no such language
	public static function code(lang:String, store:String):Null<String> {
		var list = store == "play" ? PLAY_LANGUAGES : APP_STORE_LOCALES;
		if (list.contains(lang)) return lang;
		var m = SPELLING.get(lang);
		if (m != null && list.contains(m)) return m;
		for (k => v in SPELLING)
			if (v == lang && list.contains(k)) return k;
		return null;
	}

	// (characters, as the stores count them; not UTF-8's bytes)
	public static function chars(s:String):Int {
		var n = 0;
		for (_ in new haxe.iterators.StringIteratorUnicode(s)) n++;
		return n;
	}

	// helder.json's listing checked (its mistakes named by its members)
	public static function check(l:Dynamic, file:String):Dynamic {
		if (!isObject(l)) throw '$file: listing: an object';
		only(l, SHARED, "listing", file);
		localized(l, "listing", file);
		for (k in ["website", "support", "privacy"]) {
			var v:Dynamic = Reflect.field(l, k);
			if (v != null && !(Std.isOfType(v, String) && ~/^https:\/\/[^\s]+$/.match(v))) throw '$file: listing.$k: an https URL';
		}
		if (l.collects != null && l.collects != false && !(Std.isOfType(l.collects, Array) && Lambda.foreach((l.collects : Array<Dynamic>), x -> Std.isOfType(x, String))))
			throw '$file: listing.collects: false (no data), or the types of data the app collects (["Crash logs"])';
		if (l.ads != null && l.ads != true && l.ads != false) throw '$file: listing.ads: true or false';
		for (k in ["email", "copyright", "category"]) {
			var v:Dynamic = Reflect.field(l, k);
			if (v != null && !Std.isOfType(v, String)) throw '$file: listing.$k: a string';
		}
		stores(l, "listing", file, false);
		if (l.locales != null) {
			if (!isObject(l.locales)) throw '$file: listing.locales: an object of languages ("nl-NL": {...})';
			var seen = new Map<String, String>();
			for (lang in Reflect.fields(l.locales)) {
				var o:Dynamic = Reflect.field(l.locales, lang);
				var at = 'listing.locales.$lang';
				if (!~/^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$/.match(lang)) throw '$file: $at: a language tag (nl-NL)';
				var play = code(lang, "play"), asc = code(lang, "appStore");
				if (play == null && asc == null)
					throw '$file: $at: neither a Google Play language nor an App Store locale (en-US, nl-NL; ja-JP or ja, zh-CN or zh-Hans: either store\'s spelling)';
				for (c in [play == null ? null : 'play $play', asc == null ? null : 'appStore $asc'])
					if (c != null) {
						if (seen.exists(c)) throw '$file: $at: the same language as listing.locales.${seen.get(c)}';
						seen.set(c, lang);
					}
				if (!isObject(o)) throw '$file: $at: an object';
				only(o, LOCALIZED.concat(["play", "appStore"]), at, file);
				localized(o, at, file);
				stores(o, at, file, true);
			}
		}
		return l;
	}

	static function localized(o:Dynamic, at:String, file:String) {
		for (k in LOCALIZED) {
			var v:Dynamic = Reflect.field(o, k);
			if (v == null) continue;
			if (k == "keywords") {
				if (!(Std.isOfType(v, Array) && Lambda.foreach((v : Array<Dynamic>), x -> Std.isOfType(x, String))))
					throw '$file: $at.keywords: an array of strings';
				if (chars((v : Array<String>).join(",")) > 100) throw '$file: $at.keywords: over 100 characters together (App Store Connect\'s limit)';
				continue;
			}
			if (!Std.isOfType(v, String)) throw '$file: $at.$k: a string';
			var max = LIMITS.get(k);
			if (max != null && !(v : String).startsWith("$") && chars(v) > max) throw '$file: $at.$k: over $max characters (the store\'s limit)';
		}
	}

	static function stores(o:Dynamic, at:String, file:String, local:Bool) {
		for (s => keys in ["play" => PLAY, "appStore" => APP_STORE]) {
			var v:Dynamic = Reflect.field(o, s);
			if (v == null) continue;
			if (!isObject(v)) throw '$file: $at.$s: an object';
			var allowed = local ? (s == "play" ? ["listing"] : ["infoLocalization", "versionLocalization"]) : keys;
			only(v, allowed, '$at.$s', file);
			for (k in Reflect.fields(v)) {
				var x:Dynamic = Reflect.field(v, k);
				switch '$s.$k' {
					case "play.dataSafety":
						if (!Std.isOfType(x, String) || !(x : String).toLowerCase().endsWith(".csv"))
							throw '$file: $at.play.dataSafety: a .csv file beside helder.json (Play Console\'s data safety export)';
					case "appStore.price":
						price(x, '$file: $at.appStore.price');
					case "appStore.availability":
						availability(x, '$file: $at.appStore.availability');
					case _:
						if (!isObject(x)) throw '$file: $at.$s.$k: an object of the store\'s attributes';
				}
			}
		}
	}

	// listing.appStore.price: a number (0: free, in the USA's), or
	// {"amount", "territory"} (the base territory, ISO 3166-1 alpha-3)
	public static function price(v:Dynamic, at = "listing.appStore.price"):{amount:Float, territory:String} {
		var amount:Dynamic = isObject(v) ? v.amount : v, territory:Dynamic = isObject(v) ? v.territory ?? "USA" : "USA";
		if (isObject(v)) only(v, ["amount", "territory"], at, "");
		if (!(Std.isOfType(amount, Float) || Std.isOfType(amount, Int)) || amount < 0)
			throw '$at: a price (0: free), or {"amount": 0.99, "territory": "USA"}';
		if (!Std.isOfType(territory, String) || !~/^[A-Z]{3}$/.match(territory)) throw '$at.territory: a territory\'s code (USA, FRA: ISO 3166-1 alpha-3)';
		return {amount: amount, territory: territory};
	}

	// listing.appStore.availability: {"territories": "all" or ["USA", ...],
	// "availableInNewTerritories"} (new ones: all's default yes, a list's no)
	public static function availability(v:Dynamic, at = "listing.appStore.availability"):{all:Bool, territories:Array<String>, newOnes:Null<Bool>} {
		if (!isObject(v)) throw '$at: an object ({"territories": "all", "availableInNewTerritories": true})';
		only(v, ["territories", "availableInNewTerritories"], at, "");
		var t:Dynamic = v.territories ?? "all", n:Dynamic = v.availableInNewTerritories;
		if (n != null && !Std.isOfType(n, Bool)) throw '$at.availableInNewTerritories: true or false';
		if (t == "all") return {all: true, territories: [], newOnes: n};
		if (!Std.isOfType(t, Array) || (t : Array<Dynamic>).length == 0
			|| !Lambda.foreach((t : Array<Dynamic>), x -> Std.isOfType(x, String) && ~/^[A-Z]{3}$/.match(x)))
			throw '$at.territories: "all", or territories\' codes (["USA", "BEL"]: ISO 3166-1 alpha-3)';
		return {all: false, territories: t, newOnes: n};
	}

	// ---- the values to send

	// a language's fields: the default's (null) or one of locales', the
	// description read when it names a file, "${NAME}"s replaced
	public static function fields(l:Dynamic, root:String, ?lang:String):Dynamic {
		var o:Dynamic = lang == null ? l : Reflect.field(l.locales, lang);
		var out:Dynamic = {};
		for (k in Reflect.fields(o)) if (k != "locales") Reflect.setField(out, k, env(Reflect.field(o, k)));
		var d:Dynamic = out.description;
		if (Std.isOfType(d, String) && (d : String).indexOf("\n") < 0 && ~/\.(txt|md)$/.match(d)) {
			var p = path(root, d);
			if (!FileSystem.exists(p)) throw 'listing${lang == null ? "" : ".locales." + lang}.description: $p: no such file';
			out.description = File.getContent(p).replace("\r\n", "\n").trim();
		}
		return out;
	}

	static function path(root:String, f:String):String
		return root == "." || root == "" || haxe.io.Path.isAbsolute(f) ? f : '$root/$f';

	// what can be checked before the first request: each language's fields
	// as they will be sent (the description's file read, "${NAME}"s
	// replaced) against the stores' limits, the data safety CSV there
	public static function validate(l:Null<Dynamic>, root:String) {
		if (l == null) return;
		for (code in languages(l)) {
			var f = fields(l, root, code), at = code == null ? "listing" : 'listing.locales.$code';
			for (k => max in LIMITS) {
				var v:Dynamic = Reflect.field(f, k);
				if (Std.isOfType(v, String) && chars(v) > max) throw '$at.$k: over $max characters (the store\'s limit)';
			}
			var kw:Null<Array<String>> = f.keywords;
			if (kw != null && chars(kw.join(",")) > 100) throw '$at.keywords: over 100 characters together (App Store Connect\'s limit)';
		}
		var ds:Null<String> = l.play?.dataSafety;
		if (ds != null && !FileSystem.exists(path(root, ds)))
			throw 'listing.play.dataSafety: ${path(root, ds)}: no such file (Play Console: App content, Data safety, Export to CSV)';
	}

	// the build's notes (listing.notes): each language's in the store's
	// spelling (lang null: the default language), at most max characters
	public static function notes(l:Null<Dynamic>, root:String, store:String, max:Int):Array<{lang:Null<String>, text:String}> {
		var out = [];
		if (l == null) return out;
		for (key in languages(l)) {
			var t:Null<String> = fields(l, root, key).notes;
			if (t == null) continue;
			var lang = key == null ? null : code(key, store);
			if (key != null && lang == null) continue;
			if (chars(t) > max)
				throw 'listing${key == null ? "" : ".locales." + key}.notes: over $max characters (${store == "play" ? "Google Play\'s release notes" : "the App Store\'s whatsNew"})';
			out.push({lang: lang, text: t});
		}
		return out;
	}

	// ---- the screenshots and images, checked before the first request

	// (the stores' sizes by image type: each one's [width, height], either
	// way round; Play's screenshots by rule: 320 to 3840 pixels a side, the
	// long one at most twice the short; at most max of a type, bytes each)
	static final SPECS:Map<String, {sizes:Array<Array<Int>>, max:Int, bytes:Int}> = [
		"phoneScreenshots" => {sizes: [], max: 8, bytes: 8 << 20},
		"sevenInchScreenshots" => {sizes: [], max: 8, bytes: 8 << 20},
		"tenInchScreenshots" => {sizes: [], max: 8, bytes: 8 << 20},
		"featureGraphic" => {sizes: [[1024, 500]], max: 1, bytes: 15 << 20},
		"icon" => {sizes: [[512, 512]], max: 1, bytes: 1 << 20},
		"APP_IPHONE_67" => {sizes: [[1260, 2736], [1290, 2796], [1320, 2868]], max: 10, bytes: 0},
		"APP_IPHONE_65" => {sizes: [[1242, 2688], [1284, 2778]], max: 10, bytes: 0},
		"APP_IPAD_PRO_3GEN_129" => {sizes: [[2048, 2732], [2064, 2752]], max: 10, bytes: 0}
	];

	// each file there, a PNG of the size shots.json says, one the store
	// takes for its type, within its count and bytes (another type: its
	// count, at most 10)
	public static function images(list:Array<Dynamic>, dir:String) {
		var counts = new Map<String, Int>();
		for (s in list) {
			var store = s.store == "ios" ? "App Store" : "Google Play", type:String = s.type;
			var at = '$store $type ${s.file}', p = '$dir/${s.file}';
			if (!FileSystem.exists(p)) throw '$at: no such file';
			var size = FileSystem.stat(p).size;
			var i = File.read(p, true), head = try i.read(24) catch (_:Dynamic) haxe.io.Bytes.alloc(0);
			i.close();
			if (head.length < 24 || head.get(0) != 0x89 || head.getString(1, 3) != "PNG" || head.getString(12, 4) != "IHDR") throw '$at: not a PNG';
			inline function u32(o:Int)
				return (head.get(o) << 24) | (head.get(o + 1) << 16) | (head.get(o + 2) << 8) | head.get(o + 3);
			var w = u32(16), h = u32(20);
			if (s.width != null && (w != s.width || h != s.height)) throw '$at: ${w}x$h, not ${s.width}x${s.height}';
			var key = '$store $type';
			counts.set(key, (counts.get(key) ?? 0) + 1);
			var spec = SPECS.get(type);
			if (spec == null) continue;
			if (spec.bytes > 0 && size > spec.bytes) throw '$at: ${Math.ceil(size / 1024)} KB, over the store\'s ${spec.bytes >> 20} MB';
			var ok = spec.sizes.length == 0 ? Math.min(w, h) >= 320 && Math.max(w, h) <= 3840 && Math.max(w, h) <= 2 * Math.min(w, h)
				: Lambda.exists(spec.sizes, d -> d[0] == w && d[1] == h || d[0] == h && d[1] == w);
			if (!ok)
				throw '$at: ${w}x$h is not a size $store takes for $type (${spec.sizes.length == 0 ? "320 to 3840 pixels a side, the long one at most twice the short" : [for (d in spec.sizes) '${d[0]}x${d[1]}'].join(", ")})';
		}
		for (key => n in counts) {
			var spec = SPECS.get(key.substr(key.lastIndexOf(" ") + 1)), max = spec == null ? 10 : spec.max;
			if (n > max) throw '$key: $n images, the store takes at most $max';
		}
	}

	// (a value with its "${NAME}" strings the environment's: unset, null)
	static function env(v:Dynamic):Dynamic {
		if (Std.isOfType(v, String)) {
			var r = ~/^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$/;
			if (!r.match(v)) return v;
			var e = Sys.getEnv(r.matched(1));
			return e == null || e.trim() == "" ? null : e.trim();
		}
		if (Std.isOfType(v, Array)) return [for (x in (v : Array<Dynamic>)) env(x)];
		if (isObject(v)) {
			var o:Dynamic = {};
			for (k in Reflect.fields(v)) {
				var x = env(Reflect.field(v, k));
				if (x != null) Reflect.setField(o, k, x);
			}
			return o;
		}
		return v;
	}

	// (the store's own attributes over the mapped ones, nulls left out)
	static function merged(mapped:Map<String, Dynamic>, own:Dynamic):DynamicAccess<Dynamic> {
		var out = new DynamicAccess<Dynamic>();
		for (k => v in mapped) if (v != null) out.set(k, v);
		if (own != null) for (k in Reflect.fields(own)) if (Reflect.field(own, k) != null) out.set(k, Reflect.field(own, k));
		return out;
	}

	// (the attributes of want that differ from have's)
	public static function differ(want:DynamicAccess<Dynamic>, have:Dynamic):DynamicAccess<Dynamic> {
		var out = new DynamicAccess<Dynamic>();
		for (k => v in want) {
			var h:Dynamic = have == null ? null : Reflect.field(have, k);
			if (haxe.Json.stringify(v) != haxe.Json.stringify(h)) out.set(k, v);
		}
		return out;
	}

	static function names(d:DynamicAccess<Dynamic>):String
		return [for (k in d.keys()) k].join(", ");

	public static function languages(l:Dynamic):Array<Null<String>> {
		var out:Array<Null<String>> = [null];
		if (l.locales != null) for (k in Reflect.fields(l.locales)) out.push(k);
		return out;
	}

	// ---- Google Play (in an edit Publish opened: committed or deleted there)

	// the details and each language's listing, only what is set and differs
	// (a listing Play has patched, one it has not made); listed: the
	// languages Play has a listing of once the edit is committed (l null: read alone)
	@:coroutine public static function play(l:Null<Dynamic>, root:String, base:String, edit:String, token:String, dry:Bool, listed:Array<String>):Array<String> {
		var changes = [];
		var all:Array<Dynamic> = Publish.json("GET", '$base/edits/$edit/listings', token).listings ?? [];
		for (x in all) listed.push(x.language);
		if (l == null) return changes;
		var top:Dynamic = fields(l, root);
		// (the details: the app's contact)
		var details:Dynamic = Publish.json("GET", '$base/edits/$edit/details', token);
		var want = merged(["contactEmail" => top.email, "contactWebsite" => top.website], top.play?.details);
		var d = differ(want, details);
		if (d.keys().length > 0) {
			changes.push('Google Play details: ${names(d)}');
			if (!dry) Publish.json("PATCH", '$base/edits/$edit/details', token, d);
		}
		var deflt:String = details.defaultLanguage ?? "en-US";
		for (key in languages(l)) {
			var language = key == null ? deflt : code(key, "play");
			if (language == null) {
				Term.out(Style.status("not on", Info, 'Google Play: listing.locales.$key (an App Store locale alone)'));
				continue;
			}
			var f:Dynamic = key == null ? top : fields(l, root, key);
			var have:Dynamic = Lambda.find(all, x -> x.language == language);
			var want = merged(["title" => f.title, "shortDescription" => f.summary, "fullDescription" => f.description], f.play?.listing);
			var d = differ(want, have);
			if (d.keys().length == 0) continue;
			if (have == null) {
				changes.push('Google Play $language listing: made (${names(d)})');
				if (!listed.contains(language)) listed.push(language);
				d.set("language", language);
				if (!dry) Publish.json("PUT", '$base/edits/$edit/listings/$language', token, d);
			} else {
				changes.push('Google Play $language listing: ${names(d)}');
				if (!dry) Publish.json("PATCH", '$base/edits/$edit/listings/$language', token, d);
			}
		}
		return changes;
	}

	// a language's image types, each one's files authoritative: Play's
	// images of the type by SHA-256, in order, against ours; the same, left
	// alone; else all of them deleted (deleteall) and ours uploaded in order
	@:coroutine public static function playImages(api:String, pkg:String, edit:String, token:String, lang:String, dir:String, list:Array<Dynamic>, dry:Bool):Array<String> {
		var base = '$api/androidpublisher/v3/applications/$pkg/edits/$edit/listings/$lang';
		var changes = [], types = [];
		for (s in list) if (!types.contains(s.type)) types.push(s.type);
		for (type in types) {
			var ours:Array<Dynamic> = [for (s in list) if (s.type == type) s];
			var theirs:Array<Dynamic> = Publish.json("GET", '$base/$type', token).images ?? [];
			if ([for (t in theirs) t.sha256].join(",") == [for (s in ours) s.sha256].join(",")) continue;
			changes.push('Google Play $lang $type: ${ours.length} uploaded in order' + (theirs.length == 0 ? "" : ', the ${theirs.length} there deleted'));
			if (dry) continue;
			if (theirs.length > 0) Publish.json("DELETE", '$base/$type', token);
			for (s in ours) {
				var p = '$dir/${s.file}';
				var r = Publish.http("POST", '$api/upload/androidpublisher/v3/applications/$pkg/edits/$edit/listings/$lang/$type?uploadType=media',
					["Authorization: Bearer " + token, "Content-Type: image/png"], null, {path: p, offset: 0, length: FileSystem.stat(p).size});
				if (r.code != 200) throw 'images.upload ${s.file}: HTTP ${r.code} ${r.body.trim()}';
			}
		}
		return changes;
	}

	// ---- App Store Connect (no transaction: Publish runs this twice, dry
	// first, so that what is missing refuses before the first write)

	static final EDITABLE_VERSION = "PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED,INVALID_BINARY,READY_FOR_REVIEW";
	static final EDITABLE_INFO = ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "READY_FOR_REVIEW", "WAITING_FOR_REVIEW"];

	// what the listing sets on the version (its listing, copyright, the
	// review's contact) and on the app info (name, subtitle, privacy URL,
	// categories, age rating)
	static function versionLevel(l:Dynamic):Bool {
		for (key in languages(l)) {
			var o:Dynamic = key == null ? l : Reflect.field(l.locales, key);
			if (o.description != null || o.keywords != null || o.promo != null || o.appStore?.versionLocalization != null) return true;
		}
		return l.support != null || l.website != null || l.copyright != null || l.appStore?.version != null || l.appStore?.reviewDetail != null;
	}

	static function infoLevel(l:Dynamic):Bool {
		for (key in languages(l)) {
			var o:Dynamic = key == null ? l : Reflect.field(l.locales, key);
			if (o.title != null || o.subtitle != null || o.appStore?.infoLocalization != null) return true;
		}
		return l.privacy != null || l.category != null || l.appStore?.info != null || l.appStore?.categories != null || l.appStore?.ageRating != null;
	}

	// the app's version of versionString being prepared (none, or another
	// one being prepared: refused unless create, then made or renamed: App
	// Store Connect prepares one at a time); null with dry: to be made
	@:coroutine static function preparing(c:Asc, app:String, versionString:String, make:Bool):{version:Null<Dynamic>, made:Bool} {
		var versions:Array<Dynamic> = Publish.json("GET", '${c.api}/v1/apps/$app/appStoreVersions?filter%5Bplatform%5D=IOS&filter%5BappStoreState%5D=$EDITABLE_VERSION', c.token).data ?? [];
		var v:Dynamic = Lambda.find(versions, v -> v.attributes?.versionString == versionString);
		if (v != null) return {version: v, made: false};
		var other:Dynamic = versions[0];
		if (!make)
			throw other == null ? 'App Store Connect: no version $versionString being prepared (helder.json\'s); --create-version makes it'
				: 'App Store Connect: the version being prepared is ${other.attributes?.versionString}, helder.json\'s $versionString; --create-version renames it (one is prepared at a time)';
		if (other != null) {
			patch(c, "appStoreVersions", other.id, merged(["versionString" => versionString], null), 'version ${other.attributes?.versionString}: renamed $versionString');
			return {version: other, made: false};
		}
		return {version: create(c, "appStoreVersions", merged(["platform" => "IOS", "versionString" => versionString], null), {app: rel("apps", app)}, 'version $versionString'), made: true};
	}

	static function rel(type:String, rid:String):Dynamic
		return {data: {type: type, id: rid}};

	// the store page: the app's own attributes, its price and territories;
	// the app info being edited (name, subtitle, privacy URL, categories,
	// the age rating: questions unanswered named) and each language's of
	// it; the version being prepared (its copyright, each language's
	// listing, the review's contact) and the screenshots of shots.locale.
	// Refused, before anything is written, when what it sets has nowhere
	// to go: no version of versionString being prepared (create: made),
	// no app info being edited
	@:coroutine public static function appStore(l:Null<Dynamic>, root:String, api:String, token:String, app:Dynamic, versionString:String,
			shots:{dir:String, list:Array<Dynamic>, locale:String}, makeVersion:Bool, dry:Bool, changes:Array<String>) {
		var id:String = app.id;
		var top:Dynamic = l == null ? {} : fields(l, root);
		var primary:String = app.attributes?.primaryLocale ?? "en-US";
		var c:Asc = {api: api, token: token, dry: dry, changes: changes};
		var needInfo = l != null && infoLevel(l), needVersion = shots.list.length > 0 || l != null && versionLevel(l);

		// (resolved first: the version, the app info)
		var v = needInfo || needVersion ? preparing(c, id, versionString, makeVersion) : {version: null, made: false};
		var version:Dynamic = v.version;
		var info:Dynamic = null;
		if (needInfo) {
			var infos:Array<Dynamic> = Publish.json("GET", '$api/v1/apps/$id/appInfos', token).data ?? [];
			info = Lambda.find(infos, i -> EDITABLE_INFO.contains(i.attributes?.state ?? i.attributes?.appStoreState));
			if (info == null && !(dry && v.made))
				throw 'App Store Connect: no app info being edited (the name, subtitle, privacy URL, categories and age rating change with a version being prepared)';
		}

		// (the app's own attributes: contentRightsDeclaration, ...; the price and the territories)
		if (top.appStore?.app != null) patch(c, "apps", id, differ(merged(new Map(), top.appStore.app), app.attributes), "app");
		if (top.appStore?.price != null) setPrice(c, id, price(top.appStore.price));
		if (top.appStore?.availability != null) setAvailability(c, id, availability(top.appStore.availability));

		if (needInfo) {
			if (info != null && top.appStore?.info != null) patch(c, "appInfos", info.id, differ(merged(new Map(), top.appStore.info), info.attributes), "app info");
			// (categories: relationships, by the category's id)
			var cats = new DynamicAccess<Dynamic>();
			var category:Null<String> = top.category;
			if (category != null) {
				if (category.startsWith("GAMES_")) {
					cats.set("primaryCategory", "GAMES");
					cats.set("primarySubcategoryOne", category);
				} else cats.set("primaryCategory", category);
			}
			if (top.appStore?.categories != null) for (k in Reflect.fields(top.appStore.categories)) cats.set(k, Reflect.field(top.appStore.categories, k));
			var changed = new DynamicAccess<Dynamic>();
			for (k => x in cats) {
				var have:Dynamic = info == null ? null : try Publish.json("GET", '$api/v1/appInfos/${info.id}/relationships/$k', token).data catch (_:Dynamic) null;
				if (have?.id != x) changed.set(k, x == null ? {data: null} : rel("appCategories", x));
			}
			if (changed.keys().length > 0) {
				changes.push('App Store categories: ${[for (k => x in cats) if (changed.exists(k)) '$k $x'].join(", ")}');
				if (!dry) Publish.json("PATCH", '$api/v1/appInfos/${info.id}', token, {data: {type: "appInfos", id: info.id, relationships: changed}});
			}
			// (the age rating's answers; those still unanswered named)
			var age:Dynamic = info == null ? null : Publish.json("GET", '$api/v1/appInfos/${info.id}/ageRatingDeclaration', token).data;
			if (age != null) {
				var want = merged(new Map(), top.appStore?.ageRating);
				patch(c, "ageRatingDeclarations", age.id, differ(want, age.attributes), "age rating");
				var open = [for (k in Reflect.fields(age.attributes)) if (Reflect.field(age.attributes, k) == null && !want.exists(k)) k];
				if (open.length > 0 && dry) Term.out(Style.status("unanswered", Warn, 'App Store age rating: ${open.join(", ")} (listing.appStore.ageRating)'));
			} else if (top.appStore?.ageRating != null) changes.push('App Store age rating: ${[for (k in Reflect.fields(top.appStore.ageRating)) k].join(", ")}');
			var locs:Array<Dynamic> = info == null ? [] : Publish.json("GET", '$api/v1/appInfos/${info.id}/appInfoLocalizations', token).data ?? [];
			for (key in languages(l)) {
				var locale = key == null ? primary : code(key, "appStore");
				if (locale == null) {
					if (dry) Term.out(Style.status("not on", Info, 'the App Store: listing.locales.$key (a Google Play language alone)'));
					continue;
				}
				var f:Dynamic = key == null ? top : fields(l, root, key);
				var want = merged(["name" => f.title, "subtitle" => f.subtitle, "privacyPolicyUrl" => top.privacy], f.appStore?.infoLocalization);
				var have:Dynamic = Lambda.find(locs, x -> x.attributes.locale == locale);
				if (have != null) patch(c, "appInfoLocalizations", have.id, differ(want, have.attributes), '$locale app info');
				else if (want.keys().length > 0) {
					want.set("locale", locale);
					create(c, "appInfoLocalizations", want, {appInfo: rel("appInfos", info?.id)}, '$locale app info');
				}
			}
		}

		if (!needVersion) return;
		var vid:Null<String> = version?.id;
		if (vid != null || dry) patch(c, "appStoreVersions", vid, differ(merged(["copyright" => top.copyright], top.appStore?.version), version?.attributes), 'version $versionString');
		// (the version's listing, per language; the localizations' ids by locale)
		var vlocs:Array<Dynamic> = vid == null ? [] : Publish.json("GET", '$api/v1/appStoreVersions/$vid/appStoreVersionLocalizations', token).data ?? [];
		var ids = new Map<String, Null<String>>();
		for (x in vlocs) ids.set(x.attributes.locale, x.id);
		if (l != null) for (key in languages(l)) {
			var locale = key == null ? primary : code(key, "appStore");
			if (locale == null) continue;
			var f:Dynamic = key == null ? top : fields(l, root, key);
			var keywords:Null<Array<String>> = f.keywords;
			var want = merged([
				"description" => f.description,
				"keywords" => keywords == null ? null : keywords.join(","),
				"promotionalText" => f.promo,
				"supportUrl" => top.support,
				"marketingUrl" => top.website
			], f.appStore?.versionLocalization);
			var have:Dynamic = Lambda.find(vlocs, x -> x.attributes.locale == locale);
			if (have != null) patch(c, "appStoreVersionLocalizations", have.id, differ(want, have.attributes), '$locale listing');
			else if (want.keys().length > 0) {
				want.set("locale", locale);
				var made:Dynamic = create(c, "appStoreVersionLocalizations", want, {appStoreVersion: rel("appStoreVersions", vid)}, '$locale listing');
				ids.set(locale, made?.id);
			}
		}
		// (the review's contact and notes)
		if (top.appStore?.reviewDetail != null) {
			var want = merged(new Map(), top.appStore.reviewDetail);
			var have:Dynamic = vid == null ? null : try Publish.json("GET", '$api/v1/appStoreVersions/$vid/appStoreReviewDetail', token).data catch (_:Dynamic) null;
			if (have == null) create(c, "appStoreReviewDetails", want, {appStoreVersion: rel("appStoreVersions", vid)}, "review details");
			else patch(c, "appStoreReviewDetails", have.id, differ(want, have.attributes), "review details");
		}
		if (shots.list.length == 0) return;
		var locale = shots.locale;
		if (!ids.exists(locale)) {
			var made:Dynamic = create(c, "appStoreVersionLocalizations", merged(["locale" => locale], null), {appStoreVersion: rel("appStoreVersions", vid)},
				'$locale listing, for its screenshots');
			ids.set(locale, made?.id);
		}
		appScreenshots(c, ids.get(locale), locale, shots.dir, shots.list);
	}

	// a localization's screenshot sets by display type, each authoritative:
	// its screenshots against ours in order, by the MD5 App Store Connect
	// gives back (sourceFileChecksum; without one, the file's name and
	// size), those not processed or failed counted as missing; the same,
	// left alone; else the others deleted, ours missing uploaded (reserved,
	// the parts sent, committed with the MD5), the set put in our order
	// (loc null: to be made, with dry)
	@:coroutine static function appScreenshots(c:Asc, loc:Null<String>, locale:String, dir:String, list:Array<Dynamic>) {
		var api = c.api, token = c.token;
		var sets:Array<Dynamic> = loc == null ? [] : Publish.json("GET", '$api/v1/appStoreVersionLocalizations/$loc/appScreenshotSets', token).data ?? [];
		var types = [];
		for (s in list) if (!types.contains(s.type)) types.push(s.type);
		for (type in types) {
			var ours:Array<Dynamic> = [for (s in list) if (s.type == type) s];
			var set:Dynamic = Lambda.find(sets, x -> x.attributes.screenshotDisplayType == type);
			var theirs:Array<Dynamic> = set == null ? [] : Publish.json("GET", '$api/v1/appScreenshotSets/${set.id}/appScreenshots?limit=50', token).data ?? [];
			// (ours in order: the id of one there that is the same, else null: to upload)
			var used = [], order:Array<Null<String>> = [];
			for (s in ours) {
				var t:Dynamic = Lambda.find(theirs, t -> !used.contains(t.id) && same(t, s, dir));
				if (t != null) used.push(t.id);
				order.push(t?.id);
			}
			var stale = [for (t in theirs) if (!used.contains(t.id)) t];
			if (stale.length == 0 && !order.contains(null) && [for (t in theirs) t.id].join(",") == order.join(",")) continue;
			var uploads = [for (x in order) if (x == null) x].length;
			var kept = ours.length - uploads, what = [];
			if (uploads > 0) what.push('$uploads uploaded');
			if (stale.length > 0) what.push('${stale.length} deleted');
			if (kept > 0) what.push('$kept kept');
			c.changes.push('App Store $locale $type: ${what.join(", ")}, in order' + (set == null ? " (its set made)" : ""));
			if (c.dry) continue;
			if (set == null) set = Publish.json("POST", '$api/v1/appScreenshotSets', token, {
				data: {
					type: "appScreenshotSets",
					attributes: {screenshotDisplayType: type},
					relationships: {appStoreVersionLocalization: rel("appStoreVersionLocalizations", loc)}
				}
			}, 201).data;
			for (t in stale) Publish.json("DELETE", '$api/v1/appScreenshots/${t.id}', token, null, 204);
			for (i in 0...ours.length) {
				if (order[i] != null) continue;
				var s = ours[i], path = '$dir/${s.file}', size = FileSystem.stat(path).size;
				var shot:Dynamic = Publish.json("POST", '$api/v1/appScreenshots', token, {
					data: {
						type: "appScreenshots",
						attributes: {fileName: haxe.io.Path.withoutDirectory(s.file), fileSize: size},
						relationships: {appScreenshotSet: rel("appScreenshotSets", set.id)}
					}
				}, 201).data;
				for (op in (shot.attributes.uploadOperations ?? [] : Array<Dynamic>)) {
					var headers = [for (h in (op.requestHeaders ?? [] : Array<Dynamic>)) '${h.name}: ${h.value}'];
					var r = Publish.http(op.method ?? "PUT", op.url, headers, null, {path: path, offset: op.offset ?? 0, length: op.length ?? size});
					if (r.code < 200 || r.code >= 300) throw 'a screenshot\'s part: HTTP ${r.code} ${r.body.trim()}';
				}
				Publish.json("PATCH", '$api/v1/appScreenshots/${shot.id}', token, {
					data: {type: "appScreenshots", id: shot.id, attributes: {uploaded: true, sourceFileChecksum: s.md5}}
				});
				order[i] = shot.id;
			}
			if (kept > 0)
				Publish.json("PATCH", '$api/v1/appScreenshotSets/${set.id}/relationships/appScreenshots', token, {
					data: [for (x in order) {type: "appScreenshots", id: x}]
				});
		}
	}

	// (a screenshot App Store Connect has, processed or being, the same file as ours)
	public static function same(t:Dynamic, s:Dynamic, dir:String):Bool {
		var a:Dynamic = t.attributes ?? {};
		var state:Null<String> = a.assetDeliveryState?.state;
		if (state == "FAILED" || state == "AWAITING_UPLOAD") return false;
		if (a.sourceFileChecksum != null) return a.sourceFileChecksum == s.md5;
		return a.fileName == haxe.io.Path.withoutDirectory(s.file) && a.fileSize == FileSystem.stat('$dir/${s.file}').size;
	}

	// (every page of a list: data and included, links.next followed)
	@:coroutine static function pages(c:Asc, url:String):{data:Array<Dynamic>, included:Array<Dynamic>} {
		var data = [], included = [], next:Null<String> = url, n = 0;
		while (next != null && n++ < 50) {
			var j:Dynamic = Publish.json("GET", next, c.token);
			data = data.concat(j.data ?? []);
			included = included.concat(j.included ?? []);
			next = j.links?.next;
		}
		return {data: data, included: included};
	}

	// the price: the schedule's base territory and its manual price now,
	// against ours; else a new schedule (POST /v1/appPriceSchedules) of the
	// price point of that amount in that territory
	@:coroutine static function setPrice(c:Asc, app:String, want:{amount:Float, territory:String}) {
		var api = c.api;
		var schedule:Dynamic = try Publish.json("GET", '$api/v1/apps/$app/appPriceSchedule', c.token).data catch (_:Dynamic) null;
		var base:Null<String> = null, now:Null<Float> = null;
		if (schedule != null) {
			base = try Publish.json("GET", '$api/v1/appPriceSchedules/${schedule.id}/baseTerritory', c.token).data?.id catch (_:Dynamic) null;
			if (base != null) {
				var p = pages(c, '$api/v1/appPriceSchedules/${schedule.id}/manualPrices?include=appPricePoint&filter%5Bterritory%5D=$base&limit=200');
				var today = DateTools.format(Date.now(), "%Y-%m-%d");
				for (m in p.data) {
					var a:Dynamic = m.attributes ?? {};
					var from:Null<String> = a.startDate, until:Null<String> = a.endDate;
					if ((from == null || from <= today) && (until == null || until > today)) {
						var pp:Dynamic = Lambda.find(p.included, x -> x.type == "appPricePoints" && x.id == m.relationships?.appPricePoint?.data?.id);
						if (pp != null) now = Std.parseFloat(pp.attributes.customerPrice);
					}
				}
			}
		}
		if (base == want.territory && now != null && Math.abs(now - want.amount) < 0.001) return;
		inline function shown(v:Float):String
			return v == 0 ? "free" : Std.string(v);
		c.changes.push('App Store price: ${shown(want.amount)} (${want.territory}${base == null ? "" : ", was " + (now == null ? "?" : shown(now)) + " in " + base})');
		// (the price point found with dry too: one Apple has not refuses before anything is written)
		var found:Dynamic = null, next:Null<String> = '$api/v1/apps/$app/appPricePoints?filter%5Bterritory%5D=${want.territory}&limit=200', n = 0;
		while (found == null && next != null && n++ < 50) {
			var j:Dynamic = Publish.json("GET", next, c.token);
			found = Lambda.find((j.data ?? [] : Array<Dynamic>), x -> Math.abs(Std.parseFloat(x.attributes?.customerPrice) - want.amount) < 0.001);
			next = j.links?.next;
		}
		if (found == null) throw 'App Store Connect: no price point of ${want.amount} in ${want.territory} (listing.appStore.price: one of Apple\'s prices)';
		if (c.dry) return;
		Publish.json("POST", '$api/v1/appPriceSchedules', c.token, {
			data: {
				type: "appPriceSchedules",
				relationships: {
					app: {data: {type: "apps", id: app}},
					baseTerritory: {data: {type: "territories", id: want.territory}},
					manualPrices: {data: [{type: "appPrices", id: "${price}"}]}
				}
			},
			included: [
				{
					type: "appPrices",
					id: "${price}",
					attributes: {startDate: null},
					relationships: {appPricePoint: {data: {type: "appPricePoints", id: found.id}}}
				}
			]
		}, 201);
	}

	// the territories: none yet, an availability made (POST
	// /v2/appAvailabilities); else each territory's that differs patched
	// (availableInNewTerritories is kept as made: App Store Connect's
	// Pricing and Availability)
	@:coroutine static function setAvailability(c:Asc, app:String, want:{all:Bool, territories:Array<String>, newOnes:Null<Bool>}) {
		var api = c.api;
		var wanted:Array<String> = want.all ? [for (t in pages(c, '$api/v1/territories?limit=200').data) t.id] : want.territories;
		var newOnes = want.newOnes ?? want.all;
		var have:Dynamic = try Publish.json("GET", '$api/v1/apps/$app/appAvailabilityV2', c.token).data catch (_:Dynamic) null;
		if (have == null) {
			c.changes.push('App Store availability: ${wanted.length} territories${newOnes ? ", new ones too" : ""}');
			if (c.dry) return;
			var ref = (t:String) -> "${" + t + "}";
			Publish.json("POST", '$api/v2/appAvailabilities', c.token, {
				data: {
					type: "appAvailabilities",
					attributes: {availableInNewTerritories: newOnes},
					relationships: {
						app: {data: {type: "apps", id: app}},
						territoryAvailabilities: {data: [for (t in wanted) {type: "territoryAvailabilities", id: ref(t)}]}
					}
				},
				included: [for (t in wanted) {
					type: "territoryAvailabilities",
					id: ref(t),
					attributes: {available: true},
					relationships: {territory: {data: {type: "territories", id: t}}}
				}]
			}, 201);
			return;
		}
		var had:Null<Bool> = have.attributes?.availableInNewTerritories;
		if (want.newOnes != null && had != null && had != want.newOnes)
			Term.out(Style.status("by hand", Warn,
				'App Store availability in new territories: ${want.newOnes} (App Store Connect\'s API keeps it as made: Pricing and Availability)'));
		var list = pages(c, '$api/v2/appAvailabilities/${have.id}/territoryAvailabilities?include=territory&limit=200');
		var change:Array<{id:String, territory:String, available:Bool}> = [];
		for (ta in list.data) {
			var t:Null<String> = ta.relationships?.territory?.data?.id;
			if (t == null) continue;
			var should = wanted.contains(t), is:Bool = ta.attributes?.available == true;
			if (is != should) change.push({id: ta.id, territory: t, available: should});
		}
		if (change.length == 0) return;
		c.changes.push('App Store availability: ${[for (x in change) (x.available ? "" : "not ") + x.territory].join(", ")}');
		if (c.dry) return;
		for (x in change)
			Publish.json("PATCH", '$api/v1/territoryAvailabilities/${x.id}', c.token, {
				data: {type: "territoryAvailabilities", id: x.id, attributes: {available: x.available}}
			});
	}

	// ---- Google Play's data safety (no edit: sent whole, its CSV's text)

	@:coroutine public static function dataSafety(l:Null<Dynamic>, root:String, base:String, token:String, dry:Bool):Array<String> {
		var f:Null<String> = l?.play?.dataSafety;
		if (f == null) return [];
		var p = root == "." || root == "" || haxe.io.Path.isAbsolute(f) ? f : '$root/$f';
		if (!FileSystem.exists(p)) throw 'listing.play.dataSafety: $p: no such file (Play Console: App content, Data safety, Export to CSV)';
		if (!dry) Publish.json("POST", '$base/dataSafety', token, {safetyLabels: File.getContent(p)});
		return ['Google Play data safety: $f'];
	}

	@:coroutine static function patch(c:Asc, type:String, rid:String, d:DynamicAccess<Dynamic>, what:String) {
		if (d.keys().length == 0) return;
		c.changes.push('App Store $what: ${names(d)}');
		if (!c.dry) Publish.json("PATCH", '${c.api}/v1/$type/$rid', c.token, {data: {type: type, id: rid, attributes: d}});
	}

	@:coroutine static function create(c:Asc, type:String, attributes:DynamicAccess<Dynamic>, relationships:Dynamic, what:String):Null<Dynamic> {
		c.changes.push('App Store $what: made${attributes.keys().length > 0 ? " (" + names(attributes) + ")" : ""}');
		return c.dry ? null : Publish.json("POST", '${c.api}/v1/$type', c.token, {data: {type: type, attributes: attributes, relationships: relationships}}, 201).data;
	}

	// before the build's upload, nothing written: the version the build will
	// go out with, the one of versionString being prepared (none, or
	// another one being prepared: refused unless make, then made or renamed
	// once the build is processed), and listing.notes as its localizations'
	// whatsNew (not on an app's first version: App Store Connect refuses it there)
	@:coroutine public static function submission(api:String, token:String, app:Dynamic, versionString:String, l:Null<Dynamic>, root:String, make:Bool):Submission {
		var c:Asc = {api: api, token: token, dry: true, changes: []};
		var notes = notes(l, root, "appStore", 4000);
		var v = preparing(c, app.id, versionString, make);
		var version:Dynamic = v.version;
		var all:Array<Dynamic> = Publish.json("GET", '$api/v1/apps/${app.id}/appStoreVersions?filter%5Bplatform%5D=IOS&limit=2', token).data ?? [];
		var first = all.length == 0 || all.length == 1 && version != null;
		var whatsNew = [];
		if (notes.length > 0 && first) Term.out(Style.status("not on", Info, 'the App Store: listing.notes (an app\'s first version has no whatsNew)'));
		else if (notes.length > 0) {
			var locs:Array<Dynamic> = version == null ? [] : Publish.json("GET", '$api/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations', token).data ?? [];
			for (n in notes) {
				var locale = n.lang ?? app.attributes?.primaryLocale ?? "en-US";
				var loc:Dynamic = Lambda.find(locs, x -> x.attributes.locale == locale);
				if (loc == null && version != null) Term.out(Style.status("not on", Warn, 'version ${version.attributes?.versionString}: no $locale localization for listing.notes (helder publish --listing makes it)'));
				else if (loc == null || loc.attributes?.whatsNew != n.text) whatsNew.push({locale: locale, text: n.text});
			}
		}
		return {version: version, changes: c.changes, whatsNew: whatsNew};
	}

	// the build of version (build) put on the version prepared (made or
	// renamed as submission said, its whatsNew) and sent for review: the
	// build waited for while App Store Connect processes it (minutes), an
	// open review submission reused
	@:coroutine public static function submit(api:String, token:() -> String, app:String, versionString:String, build:String, dry:Bool, plan:Submission, ?upload:String) {
		if (dry) {
			for (c in plan.changes) Term.out(Style.status("would", Info, c));
			for (n in plan.whatsNew) Term.out(Style.status("would", Info, 'App Store ${n.locale} whatsNew'));
			Term.out(Style.status("would", Info, 'put build $versionString ($build) on version $versionString once processed, and send it for App Review'));
			return;
		}
		var q = '$api/v1/builds?filter%5Bapp%5D=$app&filter%5Bversion%5D=' + StringTools.urlEncode(build) + '&filter%5BpreReleaseVersion.version%5D='
			+ StringTools.urlEncode(versionString);
		Term.spin('App Store Connect processing $versionString ($build)');
		var found:Dynamic = null, waited = 0.0, limit = Std.parseFloat(Sys.getEnv("HELDER_ASC_WAIT") ?? "") ?? 3600;
		if (Math.isNaN(limit)) limit = 3600;
		while (true) {
			// (the upload's own state: App Store Connect's validation refusing
			// the binary shows there, no build is ever made of it)
			if (upload != null) {
				var u:Dynamic = try Publish.json("GET", '$api/v1/buildUploads/$upload', token()).data catch (_:Dynamic) null;
				var st:Dynamic = u?.attributes?.state;
				if (st?.state == "FAILED") {
					Term.done();
					var why = [for (e in (st.errors ?? [] : Array<Dynamic>)) '${e.code}: ${e.description}'];
					throw 'App Store Connect refused $versionString ($build): ${why.length == 0 ? "its upload failed" : why.join("; ")}';
				}
			}
			var b:Array<Dynamic> = Publish.json("GET", q, token()).data ?? [];
			if (b.length > 0) {
				var s:String = b[0].attributes.processingState;
				if (s == "VALID") {
					found = b[0];
					break;
				}
				if (s == "FAILED" || s == "INVALID") {
					Term.done();
					throw 'App Store Connect: build $versionString ($build) is $s';
				}
			}
			if (waited >= limit) {
				Term.done();
				throw 'App Store Connect: build $versionString ($build) not processed after ${Std.int(limit / 60)} minutes';
			}
			helder.async.Async.delay(30);
			waited += 30;
		}
		Term.done();
		// (the version, as submission resolved it: made or renamed now)
		var c:Asc = {api: api, token: token(), dry: false, changes: []};
		var version:Dynamic = plan.version;
		if (version == null || version.attributes?.versionString != versionString) version = preparing(c, app, versionString, true).version;
		for (x in c.changes) Term.out(Style.status("version", Ok, x));
		if (plan.whatsNew.length > 0) {
			var locs:Array<Dynamic> = Publish.json("GET", '$api/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations', token()).data ?? [];
			for (n in plan.whatsNew) {
				var loc:Dynamic = Lambda.find(locs, x -> x.attributes.locale == n.locale);
				if (loc == null) {
					Term.out(Style.status("not on", Warn, 'version $versionString: no ${n.locale} localization for listing.notes (helder publish --listing makes it)'));
					continue;
				}
				Publish.json("PATCH", '$api/v1/appStoreVersionLocalizations/${loc.id}', token(), {
					data: {type: "appStoreVersionLocalizations", id: loc.id, attributes: {whatsNew: n.text}}
				});
				Term.out(Style.status("notes", Ok, 'App Store ${n.locale} whatsNew'));
			}
		}
		Publish.json("PATCH", '$api/v1/appStoreVersions/${version.id}/relationships/build', token(), {data: {type: "builds", id: found.id}});
		Term.out(Style.status("build", Ok, '$versionString ($build) on version $versionString'));
		var open:Array<Dynamic> = Publish.json("GET", '$api/v1/reviewSubmissions?filter%5Bapp%5D=$app&filter%5Bplatform%5D=IOS&filter%5Bstate%5D=READY_FOR_REVIEW', token()).data ?? [];
		var sub:Dynamic = open[0];
		if (sub == null)
			sub = Publish.json("POST", '$api/v1/reviewSubmissions', token(), {
				data: {type: "reviewSubmissions", attributes: {platform: "IOS"}, relationships: {app: {data: {type: "apps", id: app}}}}
			}, 201).data;
		var items:Array<Dynamic> = Publish.json("GET", '$api/v1/reviewSubmissions/${sub.id}/items', token()).data ?? [];
		if (items.length == 0)
			Publish.json("POST", '$api/v1/reviewSubmissionItems', token(), {
				data: {
					type: "reviewSubmissionItems",
					relationships: {
						reviewSubmission: {data: {type: "reviewSubmissions", id: sub.id}},
						appStoreVersion: {data: {type: "appStoreVersions", id: version.id}}
					}
				}
			}, 201);
		Publish.json("PATCH", '$api/v1/reviewSubmissions/${sub.id}', token(), {data: {type: "reviewSubmissions", id: sub.id, attributes: {submitted: true}}});
		Term.out(Style.status("submitted", Ok, 'version $versionString for App Review'));
	}

	// ---- the stores' listings as helder.json's (helder publish --pull)

	// the text the stores hold as helder.json's listing: play {details,
	// listings} (edits.details, edits.listings), appStore {primaryLocale,
	// info: the app info's localizations, version: {attributes,
	// localizations}}. The default language's fields at the top, the others
	// under locales (Play's spelling when both stores have it); where the
	// stores differ, Play's shared and the App Store's under appStore
	public static function pulled(play:Null<Dynamic>, appStore:Null<Dynamic>):Dynamic {
		var out:Dynamic = {};
		var locales = new Map<String, Dynamic>(), order = [];
		function at(key:Null<String>):Dynamic {
			if (key == null) return out;
			if (!locales.exists(key)) {
				locales.set(key, {});
				order.push(key);
			}
			return locales.get(key);
		}
		// (a field set when the store has it; another value already there: the store's own)
		function put(o:Dynamic, k:String, v:Dynamic, own:Array<String>) {
			if (v == null || v == "") return;
			var had:Dynamic = Reflect.field(o, k);
			if (had == null) Reflect.setField(o, k, v);
			else if (haxe.Json.stringify(had) != haxe.Json.stringify(v)) {
				deep(o, own, v);
			}
		}
		if (play != null) {
			var d:Dynamic = play.details ?? {}, deflt:String = d.defaultLanguage ?? "en-US";
			put(out, "email", d.contactEmail, ["play", "details", "contactEmail"]);
			put(out, "website", d.contactWebsite, ["play", "details", "contactWebsite"]);
			for (x in (play.listings ?? [] : Array<Dynamic>)) {
				var o = at(x.language == deflt ? null : x.language);
				put(o, "title", x.title, ["play", "listing", "title"]);
				put(o, "summary", x.shortDescription, ["play", "listing", "shortDescription"]);
				put(o, "description", x.fullDescription, ["play", "listing", "fullDescription"]);
				if (x.video != null && x.video != "") deep(o, ["play", "listing", "video"], x.video);
			}
		}
		if (appStore != null) {
			var primary:String = appStore.primaryLocale ?? "en-US";
			function key(locale:String):Null<String>
				return locale == primary ? null : play != null ? code(locale, "play") ?? locale : locale;
			for (x in (appStore.info ?? [] : Array<Dynamic>)) {
				var a:Dynamic = x.attributes ?? {}, o = at(key(a.locale));
				put(o, "title", a.name, ["appStore", "infoLocalization", "name"]);
				put(o, "subtitle", a.subtitle, ["appStore", "infoLocalization", "subtitle"]);
				if (a.locale == primary) put(out, "privacy", a.privacyPolicyUrl, ["appStore", "infoLocalization", "privacyPolicyUrl"]);
			}
			var v:Dynamic = appStore.version;
			if (v != null) {
				put(out, "copyright", v.attributes?.copyright, ["appStore", "version", "copyright"]);
				for (x in (v.localizations ?? [] : Array<Dynamic>)) {
					var a:Dynamic = x.attributes ?? {}, o = at(key(a.locale));
					put(o, "description", a.description, ["appStore", "versionLocalization", "description"]);
					var kw:Null<String> = a.keywords;
					if (kw != null && kw != "") put(o, "keywords", [for (k in kw.split(",")) k.trim()], ["appStore", "versionLocalization", "keywords"]);
					put(o, "promo", a.promotionalText, ["appStore", "versionLocalization", "promotionalText"]);
					if (a.locale == primary) {
						put(out, "support", a.supportUrl, ["appStore", "versionLocalization", "supportUrl"]);
						put(out, "website", a.marketingUrl, ["appStore", "versionLocalization", "marketingUrl"]);
					} else
						for (k in ["supportUrl", "marketingUrl"]) {
							var u:Dynamic = Reflect.field(a, k);
							if (u != null && u != "") deep(o, ["appStore", "versionLocalization", k], u);
						}
				}
			}
		}
		if (order.length > 0) {
			var l:Dynamic = {};
			for (k in order) Reflect.setField(l, k, locales.get(k));
			out.locales = l;
		}
		return out;
	}
	// (v at path under o, the objects on the way made)
	static function deep(o:Dynamic, path:Array<String>, v:Dynamic) {
		var x:Dynamic = o;
		for (p in path.slice(0, path.length - 1)) {
			if (Reflect.field(x, p) == null) Reflect.setField(x, p, {});
			x = Reflect.field(x, p);
		}
		Reflect.setField(x, path[path.length - 1], v);
	}

	static function only(o:Dynamic, allowed:Array<String>, at:String, file:String)
		for (k in Reflect.fields(o))
			if (!allowed.contains(k)) throw (file == "" ? "" : '$file: ') + '$at.$k: not one of ${allowed.join(", ")}';

	static function isObject(v:Dynamic):Bool
		return v != null && Reflect.isObject(v) && !Std.isOfType(v, String) && !Std.isOfType(v, Array);
}

typedef Asc = {api:String, token:String, dry:Bool, changes:Array<String>};
// (what helder publish --testflight --submit resolved before the upload)
typedef Submission = {version:Null<Dynamic>, changes:Array<String>, whatsNew:Array<{locale:String, text:String}>};
