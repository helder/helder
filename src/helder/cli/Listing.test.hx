package helder.cli;

import helder.test.Test;

// helder.json's listing (Listing): its shared fields checked against the
// stores' limits, the stores' own attributes passed through whatever their
// names, "${NAME}" from the environment, the description from a file;
// what differs from what a store has
function tests() {
	function error(listing:Dynamic):String
		return Std.string(throws(() -> HelderJson.parse(haxe.Json.stringify({name: "Skies", listing: listing}))));

	test("listing: read beside the manifest, the stores' own attributes as they are", () -> {
		var h = HelderJson.parse(haxe.Json.stringify({
			name: "Skies",
			listing: {
				subtitle: "Mini golf",
				keywords: ["golf", "puzzle"],
				appStore: {ageRating: {aFieldAppleAddsLater: "NONE"}, reviewDetail: {contactPhone: "${PHONE}"}},
				play: {listing: {video: "https://youtu.be/x"}},
				locales: {"nl-NL": {subtitle: "Minigolf", appStore: {versionLocalization: {promotionalText: "Hallo"}}}}
			}
		}));
		equals([h.listing.subtitle, h.listing.appStore.ageRating.aFieldAppleAddsLater, h.listing.play.listing.video], ["Mini golf", "NONE", "https://youtu.be/x"]);
		equals(Listing.languages(h.listing), [null, "nl-NL"]);
		equals(Listing.fields(h.listing, ".", "nl-NL").subtitle, "Minigolf");
	});
	test("listing: ${NAME} from the environment, left out when it is not set", () -> {
		Sys.putEnv("HELDER_LISTING_TEST_PHONE", "+32 1 234");
		var f = Listing.fields({appStore: {reviewDetail: {contactPhone: "${HELDER_LISTING_TEST_PHONE}", contactEmail: "${HELDER_LISTING_TEST_UNSET}"}}}, ".");
		equals([f.appStore.reviewDetail.contactPhone, Std.string(Reflect.hasField(f.appStore.reviewDetail, "contactEmail"))], ["+32 1 234", "false"]);
	});
	test("listing: the description from a file beside helder.json", () -> {
		var dir = "bin/test/listing";
		TestCommand.mkdirs(dir);
		sys.io.File.saveContent('$dir/description.txt', "Line one.\r\n\r\nLine two.\r\n");
		equals(Listing.fields({description: "description.txt"}, dir).description, "Line one.\n\nLine two.");
		equals(Listing.fields({description: "Just text."}, dir).description, "Just text.");
	});
	test("listing: what differs from the store's", () -> {
		var want:haxe.DynamicAccess<Dynamic> = {title: "Skies", shortDescription: "Golf", keywords: "a,b"};
		var d = Listing.differ(want, {title: "Skies", shortDescription: "Old"});
		var keys = [for (k in d.keys()) k];
		keys.sort(Reflect.compare);
		equals(keys, ["keywords", "shortDescription"]);
	});
	test("listing: the App Store's price and availability, Play's data safety", () -> {
		var h = HelderJson.parse(haxe.Json.stringify({
			name: "Skies",
			listing: {appStore: {price: 0, availability: {territories: ["USA", "BEL"]}}, play: {dataSafety: "store/data-safety.csv"}}
		}));
		equals(Listing.price(h.listing.appStore.price), {amount: 0, territory: "USA"});
		equals(Listing.price({amount: 0.99, territory: "FRA"}), {amount: 0.99, territory: "FRA"});
		equals(Listing.availability(h.listing.appStore.availability), {all: false, territories: ["USA", "BEL"], newOnes: null});
		equals(Listing.availability({}), {all: true, territories: [], newOnes: null});
		equals(Listing.availability({territories: "all", availableInNewTerritories: false}).newOnes, false);
		equals(error({appStore: {price: -1}}), 'helder.json: listing.appStore.price: a price (0: free), or {"amount": 0.99, "territory": "USA"}');
		equals(error({appStore: {price: {amount: 1, territory: "US"}}}), "helder.json: listing.appStore.price.territory: a territory's code (USA, FRA: ISO 3166-1 alpha-3)");
		equals(error({appStore: {price: {cost: 1}}}).indexOf("helder.json: listing.appStore.price.cost: not one of"), 0);
		equals(error({appStore: {availability: {territories: ["be"]}}}).indexOf("helder.json: listing.appStore.availability.territories: \"all\", or"), 0);
		equals(error({play: {dataSafety: {}}}).indexOf("helder.json: listing.play.dataSafety: a .csv file"), 0);
		equals(error({locales: {"nl-NL": {appStore: {price: 0}}}}).indexOf("helder.json: listing.locales.nl-NL.appStore.price: not one of"), 0);
	});
	test("listing: mistakes, in helder.json's names", () -> {
		equals(error("x"), "helder.json: listing: an object");
		equals(error({tagline: "x"}).indexOf("helder.json: listing.tagline: not one of"), 0);
		equals(error({subtitle: "a subtitle well over thirty characters"}), "helder.json: listing.subtitle: over 30 characters (the store's limit)");
		equals(error({keywords: "golf"}), "helder.json: listing.keywords: an array of strings");
		equals(error({privacy: "http://x"}), "helder.json: listing.privacy: an https URL");
		equals(error({appStore: {ageRating: "none"}}), "helder.json: listing.appStore.ageRating: an object of the store's attributes");
		equals(error({appStore: {screenshots: {}}}).indexOf("helder.json: listing.appStore.screenshots: not one of"), 0);
		equals(error({locales: {"nl-NL": {email: "x"}}}).indexOf("helder.json: listing.locales.nl-NL.email: not one of"), 0);
	});
	test("listing: a language in either store's spelling, the other's sent; one neither has, or twice, refused", () -> {
		equals([Listing.code("ja-JP", "appStore"), Listing.code("ja", "play"), Listing.code("iw-IL", "appStore"), Listing.code("zh-Hans", "play")], ["ja", "ja-JP", "he", "zh-CN"]);
		equals([Listing.code("en-US", "play"), Listing.code("nl-NL", "appStore")], ["en-US", "nl-NL"]);
		// (one store alone: es-419 is not es-MX, or-IN is the App Store's)
		equals([Listing.code("es-419", "appStore"), Listing.code("or-IN", "play"), Listing.code("zh-HK", "appStore")], [null, null, null]);
		equals(error({locales: {"en": {title: "x"}}}).indexOf("helder.json: listing.locales.en: neither a Google Play language nor an App Store locale"), 0);
		var twice = error({locales: {"ja-JP": {title: "a"}, "ja": {title: "b"}}});
		assert(twice == "helder.json: listing.locales.ja: the same language as listing.locales.ja-JP"
			|| twice == "helder.json: listing.locales.ja-JP: the same language as listing.locales.ja", twice);
	});
	test("listing: checked before the first request: the description's file, the limits in characters, the notes per store", () -> {
		var dir = "bin/test/listing-validate";
		TestCommand.mkdirs(dir);
		equals(Std.string(throws(() -> Listing.validate({description: "store/missing.txt"}, dir))), 'listing.description: $dir/store/missing.txt: no such file');
		sys.io.File.saveContent('$dir/long.txt', StringTools.lpad("", "x", 4001));
		equals(Std.string(throws(() -> Listing.validate({description: "long.txt"}, dir))), "listing.description: over 4000 characters (the store's limit)");
		// (characters, not UTF-8's bytes: 30 of Japanese is within the title's 30)
		var ja = StringTools.lpad("", "空", 30);
		Listing.validate(Listing.check({title: ja}, "helder.json"), dir);
		equals(error({title: ja + "空"}), "helder.json: listing.title: over 30 characters (the store's limit)");
		Sys.putEnv("HELDER_LISTING_TEST_PROMO", StringTools.lpad("", "p", 171));
		equals(Std.string(throws(() -> Listing.validate({promo: "${HELDER_LISTING_TEST_PROMO}"}, dir))), "listing.promo: over 170 characters (the store's limit)");
		equals(Std.string(throws(() -> Listing.validate({play: {dataSafety: "safety.csv"}}, dir))).indexOf('listing.play.dataSafety: $dir/safety.csv: no such file'), 0);
		var l = {notes: StringTools.lpad("", "n", 600), locales: {"or-IN": {notes: "x"}, "ja-JP": {notes: "y"}}};
		equals(Std.string(throws(() -> Listing.notes(l, dir, "play", 500))), "listing.notes: over 500 characters (Google Play's release notes)");
		var langs = [for (n in Listing.notes(l, dir, "appStore", 4000)) n.lang ?? "(default)"];
		langs.sort(Reflect.compare);
		equals(langs, ["(default)", "ja", "or-IN"]);
		equals(Listing.notes({locales: {"or-IN": {notes: "x"}}}, dir, "play", 500), []);
	});
	test("listing: the images checked: a PNG of its size, one the store takes, within its count", () -> {
		var dir = "bin/test/listing-images";
		TestCommand.mkdirs(dir);
		function png(name:String, w:Int, h:Int):Dynamic {
			var b = haxe.io.Bytes.alloc(33);
			for (i => x in [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]) b.set(i, x);
			for (i in 0...4) {
				b.set(16 + i, (w >> (24 - 8 * i)) & 0xff);
				b.set(20 + i, (h >> (24 - 8 * i)) & 0xff);
			}
			sys.io.File.saveBytes('$dir/$name', b);
			return {file: name, width: w, height: h};
		}
		function shot(s:Dynamic, store:String, type:String):Dynamic {
			s.store = store;
			s.type = type;
			return s;
		}
		Listing.images([shot(png("p.png", 1080, 1920), "android", "phoneScreenshots"), shot(png("i.png", 2868, 1320), "ios", "APP_IPHONE_67")], dir);
		equals(Std.string(throws(() -> Listing.images([shot(png("w.png", 1000, 2868), "ios", "APP_IPHONE_67")], dir))).indexOf("App Store APP_IPHONE_67 w.png: 1000x2868 is not a size"), 0);
		equals(Std.string(throws(() -> Listing.images([shot(png("t.png", 400, 1000), "android", "phoneScreenshots")], dir))).indexOf("Google Play phoneScreenshots t.png: 400x1000 is not a size"), 0);
		var s = shot(png("x.png", 1080, 1920), "android", "phoneScreenshots");
		s.width = 1080;
		s.height = 1080;
		equals(Std.string(throws(() -> Listing.images([s], dir))), "Google Play phoneScreenshots x.png: 1080x1920, not 1080x1080");
		sys.io.File.saveContent('$dir/n.png', "not a png at all, not at all");
		equals(Std.string(throws(() -> Listing.images([{file: "n.png", store: "android", type: "icon"}], dir))), "Google Play icon n.png: not a PNG");
		equals(Std.string(throws(() -> Listing.images([for (_ in 0...9) shot(png("p.png", 1080, 1920), "android", "phoneScreenshots")], dir))),
			"Google Play phoneScreenshots: 9 images, the store takes at most 8");
		// (App Store Connect's screenshot: failed or awaiting its upload, not the same file)
		equals([
			Listing.same({attributes: {sourceFileChecksum: "m", assetDeliveryState: {state: "COMPLETE"}}}, {md5: "m"}, dir),
			Listing.same({attributes: {sourceFileChecksum: "m", assetDeliveryState: {state: "FAILED"}}}, {md5: "m"}, dir),
			Listing.same({attributes: {fileName: "p.png", fileSize: 33}}, {file: "p.png", md5: "m"}, dir)
		], [true, false, true]);
	});
	test("listing: collects and ads, the answers helder setup gives", () -> {
		equals(HelderJson.parse('{"listing": {"collects": false, "ads": false}}').listing.collects, false);
		equals(HelderJson.parse('{"listing": {"collects": ["Crash logs"]}}').listing.collects[0], "Crash logs");
		equals(error({collects: true}).indexOf("helder.json: listing.collects: false"), 0);
		equals(error({ads: "no"}), "helder.json: listing.ads: true or false");
		equals([Checklist.playCategory("GAMES_SPORTS", true), Checklist.playCategory("GAMES", true), Checklist.playCategory("PRODUCTIVITY", false)],
			["Game, Sports", "Game", "App, Productivity (or the closest)"]);
	});
}
