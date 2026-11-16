package helder.cli;

import haxe.io.Bytes;
import helder.pack.apple.Identity.PrivateKey;
import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// helder publish's store sync against a stand-in of both stores
// (Publish.transport: no request leaves the process), their answers
// written from the APIs' references (Play Developer API v3's edits,
// listings, images, tracks; App Store Connect's appStoreVersions,
// appInfos, appScreenshotSets, appScreenshots): only what is set sent, a
// screenshot group authoritative and in order, Play's edit committed only
// at the end, App Store Connect's refusals before the first write, the
// build's notes with the build. Not run against the live stores.
function tests() {
	final dir = "bin/test-publish";
	final pkg = "org.helder.skies", play = "/androidpublisher/v3/applications/org.helder.skies";
	final key = {id: "ABC123DEFG", issuer: "issuer", key: PrivateKey.fromPem(File.getContent("tests/pack/signing/key-ec.pem"))};
	final ios = {id: "org.helder.Skies", versionName: "1.2"};
	Sys.putEnv("HELDER_PLAY_API", "http://store");
	Sys.putEnv("HELDER_ASC_API", "http://store");
	// (each its own directory, written over: nothing deleted)
	var apps = 0;
	function app(listing:Dynamic):Entry {
		var d = '$dir/app-${apps++}';
		TestCommand.mkdirs(d);
		File.saveContent('$d/helder.json', haxe.Json.stringify({name: "Skies", entry: "Main.hx", listing: listing}));
		File.saveContent('$d/Main.hx', "class Main {\n\tstatic function main() {}\n}\n");
		return Entry.resolve(d);
	}
	// (a store's image: a PNG's header of w x h, told apart by its last byte)
	function shot(name:String, store:String, type:String, w:Int, h:Int):Dynamic {
		var b = Bytes.alloc(40);
		for (i => x in [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]) b.set(i, x);
		for (i in 0...4) {
			b.set(16 + i, (w >> (24 - 8 * i)) & 0xff);
			b.set(20 + i, (h >> (24 - 8 * i)) & 0xff);
		}
		b.set(39, name.charCodeAt(0));
		TestCommand.mkdirs('$dir/store');
		File.saveBytes('$dir/store/$name.png', b);
		return {file: '$name.png', store: store, type: type, width: w, height: h, sha256: haxe.crypto.Sha256.make(b).toHex(), md5: haxe.crypto.Md5.make(b).toHex()};
	}
	afterEach(() -> Publish.transport = null);

	describe("Google Play", () -> {
		test("only what is set, in one edit committed at the end; ja-JP as Play spells it, an App Store locale alone left out", async(() -> {
			var f = new Fake().edit(play)
				.on('GET $play/edits/e1/listings', {listings: [{language: "en-US", title: "Old", shortDescription: "Old", fullDescription: "Kept"}]})
				.on('GET $play/edits/e1/details', {defaultLanguage: "en-US", contactEmail: "a@b.c"});
			f.install();
			var e = app({summary: "Golf", email: "a@b.c", locales: {"ja-JP": {title: "ゴルフ"}, "or-IN": {title: "Golf"}}});
			Publish.playListing(e, '$dir/store', [], pkg, "en-US", false, {token: "t"});
			equals(f.writes(), ['POST $play/edits', 'PATCH $play/edits/e1/listings/en-US', 'PUT $play/edits/e1/listings/ja-JP', 'POST $play/edits/e1:commit']);
			equals(f.body('PATCH $play/edits/e1/listings/en-US'), {shortDescription: "Golf"});
			equals(f.body('PUT $play/edits/e1/listings/ja-JP'), {title: "ゴルフ", language: "ja-JP"});
		}));

		test("screenshots by SHA-256 in order: the same left alone (the edit deleted), another order all replaced in ours", async(() -> {
			var a = shot("a", "android", "phoneScreenshots", 1080, 1920), b = shot("b", "android", "phoneScreenshots", 1080, 1920);
			var f = new Fake().edit(play)
				.on('GET $play/edits/e1/listings', {listings: [{language: "en-US", title: "Skies"}]})
				.on('GET $play/edits/e1/listings/en-US/phoneScreenshots', {images: [{id: "1", sha256: a.sha256}, {id: "2", sha256: b.sha256}]});
			f.install();
			var e = app(null);
			equals(Publish.playListing(e, '$dir/store', [a, b], pkg, "en-US", false, {token: "t"}), []);
			equals(f.writes(), ['POST $play/edits', 'DELETE $play/edits/e1']);
			f = new Fake().edit(play)
				.on('GET $play/edits/e1/listings', {listings: [{language: "en-US", title: "Skies"}]})
				.on('GET $play/edits/e1/listings/en-US/phoneScreenshots', {images: [{id: "2", sha256: b.sha256}, {id: "1", sha256: a.sha256}]})
				.on('DELETE $play/edits/e1/listings/en-US/phoneScreenshots', {deleted: []})
				.on('POST /upload$play/edits/e1/listings/en-US/phoneScreenshots', {image: {id: "3"}});
			f.install();
			Publish.playListing(e, '$dir/store', [a, b], pkg, "en-US", false, {token: "t"});
			var up = '/upload$play/edits/e1/listings/en-US/phoneScreenshots';
			equals(f.writes(), ['POST $play/edits', 'DELETE $play/edits/e1/listings/en-US/phoneScreenshots', 'POST $up', 'POST $up', 'POST $play/edits/e1:commit']);
			equals([for (i => c in f.calls) if (c == 'POST $up') f.bodies[i]], ['file:$dir/store/a.png', 'file:$dir/store/b.png']);
		}));

		test("a failure in the edit: the edit deleted, nothing committed; no listing of the language: refused", async(() -> {
			var a = shot("a", "android", "phoneScreenshots", 1080, 1920);
			var f = new Fake().edit(play)
				.on('GET $play/edits/e1/listings', {listings: [{language: "en-US", title: "Skies"}]})
				.on('GET $play/edits/e1/listings/en-US/phoneScreenshots', {images: []})
				.on('POST /upload$play/edits/e1/listings/en-US/phoneScreenshots', {error: {code: 500}}, 500);
			f.install();
			var e = app(null);
			var err = Std.string(throwsAsync(() -> {
				Publish.playListing(e, '$dir/store', [a], pkg, "en-US", false, {token: "t"});
			}));
			assert(err.indexOf("images.upload a.png: HTTP 500") >= 0, err);
			equals(f.writes().slice(-1), ['DELETE $play/edits/e1']);
			f = new Fake().edit(play).on('GET $play/edits/e1/listings', {listings: [{language: "en-US", title: "Skies"}]});
			f.install();
			err = Std.string(throwsAsync(() -> {
				Publish.playListing(e, '$dir/store', [a], pkg, "nl-NL", false, {token: "t"});
			}));
			assert(err.indexOf("Google Play has no nl-NL listing") == 0, err);
			equals(f.writes(), ['POST $play/edits', 'DELETE $play/edits/e1']);
		}));

		test("--play: listing.notes on the release, the default language Play's", async(() -> {
			TestCommand.mkdirs(dir);
			File.saveContent('$dir/app.aab', "an app bundle");
			var f = new Fake().edit(play)
				.on('GET $play/edits/e1/details', {defaultLanguage: "en-GB"})
				.on('POST /upload$play/edits/e1/bundles', {versionCode: 3, sha256: "x"})
				.on('PUT $play/edits/e1/tracks/beta', {track: "beta"});
			f.install();
			Publish.toPlay('$dir/app.aab', pkg, 3, "beta", false, false, {token: "t"}, [{lang: null, text: "Fixes"}, {lang: "ja-JP", text: "修正"}]);
			var t:Dynamic = f.body('PUT $play/edits/e1/tracks/beta');
			equals(t.releases[0].releaseNotes, [{language: "en-GB", text: "Fixes"}, {language: "ja-JP", text: "修正"}]);
			equals(f.writes().slice(-1), ['POST $play/edits/e1:commit']);
		}));
	});

	describe("App Store Connect", () -> {
		final editable = '/v1/apps/app-1/appStoreVersions';
		function asc():Fake
			return new Fake().on("GET /v1/apps", {data: [{type: "apps", id: "app-1", attributes: {bundleId: "org.helder.Skies", primaryLocale: "en-US"}}]});

		test("no version being prepared: refused before any write; --create-version makes it", async(() -> {
			var f = asc().on('GET $editable', {data: []});
			f.install();
			var e = app({description: "Mini golf."});
			var err = Std.string(throwsAsync(() -> {
				Publish.ascListing(e, '$dir/store', [], ios, "en-US", false, key, false);
			}));
			assert(err.indexOf("no version 1.2 being prepared") >= 0 && err.indexOf("--create-version") >= 0, err);
			equals(f.writes(), []);
			f = asc().on('GET $editable', {data: []})
				.on("GET /v1/appStoreVersions/appStoreVersions-new/appStoreVersionLocalizations", {data: [{type: "appStoreVersionLocalizations", id: "vl-en", attributes: {locale: "en-US"}}]});
			f.install();
			Publish.ascListing(e, '$dir/store', [], ios, "en-US", false, key, true);
			equals(f.writes(), ["POST /v1/appStoreVersions", "PATCH /v1/appStoreVersionLocalizations/vl-en"]);
			equals(f.body("POST /v1/appStoreVersions").data.attributes, {platform: "IOS", versionString: "1.2"});
			equals(f.body("PATCH /v1/appStoreVersionLocalizations/vl-en").data.attributes, {description: "Mini golf."});
		}));

		test("another version being prepared: refused; --create-version renames it", async(() -> {
			var v = {data: [{type: "appStoreVersions", id: "v-1", attributes: {versionString: "1.1", appStoreState: "PREPARE_FOR_SUBMISSION"}}]};
			var f = asc().on('GET $editable', v).on("GET /v1/appStoreVersions/v-1/appStoreVersionLocalizations", {data: []});
			f.install();
			var e = app({promo: "Now with wind."});
			var err = Std.string(throwsAsync(() -> {
				Publish.ascListing(e, '$dir/store', [], ios, "en-US", true, key, false);
			}));
			assert(err.indexOf("the version being prepared is 1.1, helder.json's 1.2") >= 0, err);
			equals(f.writes(), []);
			Publish.ascListing(e, '$dir/store', [], ios, "en-US", false, key, true);
			equals(f.writes(), ["PATCH /v1/appStoreVersions/v-1", "POST /v1/appStoreVersionLocalizations"]);
			equals(f.body("PATCH /v1/appStoreVersions/v-1").data.attributes, {versionString: "1.2"});
			equals(f.body("POST /v1/appStoreVersionLocalizations").data.attributes, {promotionalText: "Now with wind.", locale: "en-US"});
		}));

		test("no app info being edited: refused before any write; one being edited takes ja-JP as ja, the title unset left alone", async(() -> {
			var v = {data: [{type: "appStoreVersions", id: "v-2", attributes: {versionString: "1.2", appStoreState: "PREPARE_FOR_SUBMISSION"}}]};
			var live = {type: "appInfos", id: "i-live", attributes: {state: "READY_FOR_DISTRIBUTION", appStoreState: "READY_FOR_SALE"}};
			var f = asc().on('GET $editable', v).on("GET /v1/apps/app-1/appInfos", {data: [live]});
			f.install();
			var e = app({subtitle: "Mini golf", locales: {"ja-JP": {subtitle: "ミニゴルフ"}}});
			var err = Std.string(throwsAsync(() -> {
				Publish.ascListing(e, '$dir/store', [], ios, "en-US", false, key, false);
			}));
			assert(err.indexOf("no app info being edited") >= 0, err);
			equals(f.writes(), []);
			f = asc().on('GET $editable', v)
				.on("GET /v1/apps/app-1/appInfos", {data: [live, {type: "appInfos", id: "i-next", attributes: {state: "PREPARE_FOR_SUBMISSION"}}]})
				.on("GET /v1/appInfos/i-next/ageRatingDeclaration", {data: null})
				.on("GET /v1/appInfos/i-next/appInfoLocalizations", {data: [{type: "appInfoLocalizations", id: "il-en", attributes: {locale: "en-US", name: "Skies", subtitle: "Old"}}]});
			f.install();
			Publish.ascListing(e, '$dir/store', [], ios, "en-US", false, key, false);
			equals(f.writes(), ["PATCH /v1/appInfoLocalizations/il-en", "POST /v1/appInfoLocalizations"]);
			equals(f.body("PATCH /v1/appInfoLocalizations/il-en").data.attributes, {subtitle: "Mini golf"});
			equals(f.body("POST /v1/appInfoLocalizations").data.attributes, {subtitle: "ミニゴルフ", locale: "ja"});
		}));

		test("a screenshot set authoritative: the stale and the failed deleted, ours missing uploaded, the set in our order; the same left alone", async(() -> {
			var a = shot("a", "ios", "APP_IPHONE_67", 1320, 2868), b = shot("b", "ios", "APP_IPHONE_67", 1320, 2868), c = shot("c", "ios", "APP_IPHONE_67", 1320, 2868);
			var v = {data: [{type: "appStoreVersions", id: "v-2", attributes: {versionString: "1.2", appStoreState: "PREPARE_FOR_SUBMISSION"}}]};
			function screenshot(id:String, md5:String, state:String):Dynamic
				return {type: "appScreenshots", id: id, attributes: {fileName: '$id.png', fileSize: 40, sourceFileChecksum: md5, assetDeliveryState: {state: state, errors: []}}};
			function store(shots:Array<Dynamic>):Fake {
				var n = 0;
				return asc().on('GET $editable', v)
					.on("GET /v1/appStoreVersions/v-2/appStoreVersionLocalizations", {data: [{type: "appStoreVersionLocalizations", id: "vl-en", attributes: {locale: "en-US"}}]})
					.on("GET /v1/appStoreVersionLocalizations/vl-en/appScreenshotSets", {data: [{type: "appScreenshotSets", id: "set-67", attributes: {screenshotDisplayType: "APP_IPHONE_67"}}]})
					.on("GET /v1/appScreenshotSets/set-67/appScreenshots", {data: shots})
					.answer("POST /v1/appScreenshots", body -> {
						var id = 'new-${n++}';
						return {data: {type: "appScreenshots", id: id, attributes: {uploadOperations: [{method: "PUT", url: 'http://store/part/$id', offset: 0, length: 40, requestHeaders: []}]}}};
					});
			}
			var f = store([screenshot("s-a", a.md5, "COMPLETE"), screenshot("s-x", "stale", "COMPLETE"), screenshot("s-c", c.md5, "FAILED")]);
			f.install();
			var e = app(null);
			Publish.ascListing(e, '$dir/store', [b, a, c], ios, "en-US", false, key, false);
			equals(f.writes(), [
				"DELETE /v1/appScreenshots/s-x", "DELETE /v1/appScreenshots/s-c",
				"POST /v1/appScreenshots", "PUT /part/new-0", "PATCH /v1/appScreenshots/new-0",
				"POST /v1/appScreenshots", "PUT /part/new-1", "PATCH /v1/appScreenshots/new-1",
				"PATCH /v1/appScreenshotSets/set-67/relationships/appScreenshots"
			]);
			equals([for (x in (f.body("PATCH /v1/appScreenshotSets/set-67/relationships/appScreenshots").data : Array<Dynamic>)) x.id], ["new-0", "s-a", "new-1"]);
			equals(f.body("PATCH /v1/appScreenshots/new-0").data.attributes, {uploaded: true, sourceFileChecksum: b.md5});
			f = store([screenshot("s-b", b.md5, "COMPLETE"), screenshot("s-a", a.md5, "UPLOAD_COMPLETE"), screenshot("s-c", c.md5, "COMPLETE")]);
			f.install();
			equals(Publish.ascListing(e, '$dir/store', [b, a, c], ios, "en-US", false, key, false), []);
			equals(f.writes(), []);
		}));

		test("--submit: the version resolved before the upload, listing.notes its whatsNew (none on a first version)", async(() -> {
			var e = app({notes: "Wind.", locales: {"nl-NL": {notes: "Wind."}}});
			var l = (e.config : Manifest.AppConfig).listing;
			var appJson = {type: "apps", id: "app-1", attributes: {primaryLocale: "en-US"}};
			var f = asc().on('GET $editable', {data: []});
			f.install();
			var err = Std.string(throwsAsync(() -> {
				Listing.submission("http://store", "t", appJson, "1.2", l, e.root, false);
			}));
			assert(err.indexOf("--create-version makes it") >= 0, err);
			var v2 = {type: "appStoreVersions", id: "v-2", attributes: {versionString: "1.2"}};
			f = asc().on('GET $editable', {data: [v2]})
				.on("GET /v1/appStoreVersions/v-2/appStoreVersionLocalizations", {data: [{type: "appStoreVersionLocalizations", id: "vl-en", attributes: {locale: "en-US", whatsNew: "Old."}}]});
			f.install();
			// (two versions: not the first; nl-NL has no localization: named, left out)
			f.on('GET $editable', {data: [v2, {type: "appStoreVersions", id: "v-1", attributes: {versionString: "1.1"}}]});
			var plan = Listing.submission("http://store", "t", appJson, "1.2", l, e.root, false);
			equals(plan.whatsNew, [{locale: "en-US", text: "Wind."}]);
			equals(f.writes(), []);
		}));
	});

	describe("helder publish --pull", () -> {
		test("both stores' text as helder.json's listing: Play's shared, the App Store's own where they differ, ja as ja-JP", () -> {
			var l = Listing.pulled({
				details: {defaultLanguage: "en-US", contactEmail: "a@b.c", contactWebsite: "https://skies.example"},
				listings: [
					{language: "en-US", title: "Little Skies", shortDescription: "Golf in the sky", fullDescription: "Long."},
					{language: "ja-JP", title: "空のゴルフ"}
				]
			}, {
				primaryLocale: "en-US",
				info: [
					{attributes: {locale: "en-US", name: "Little Skies: Golf", subtitle: "Mini golf", privacyPolicyUrl: "https://skies.example/privacy"}},
					{attributes: {locale: "ja", name: "空のゴルフ"}}
				],
				version: {attributes: {copyright: "2026 Codeurs"}, localizations: [{attributes: {locale: "en-US", description: "Long.", keywords: "golf, sky", supportUrl: "https://skies.example/help"}}]}
			});
			equals(l.title, "Little Skies");
			equals(l.appStore.infoLocalization.name, "Little Skies: Golf");
			equals([l.summary, l.subtitle, l.description, l.privacy, l.support, l.copyright, l.website], [
				"Golf in the sky", "Mini golf", "Long.", "https://skies.example/privacy", "https://skies.example/help", "2026 Codeurs", "https://skies.example"
			]);
			equals(l.keywords, ["golf", "sky"]);
			equals(Reflect.fields(l.locales), ["ja-JP"]);
			equals(Reflect.field(l.locales, "ja-JP"), {title: "空のゴルフ"});
			// (and what is pulled is a listing helder.json takes)
			HelderJson.parse(haxe.Json.stringify({name: "Skies", listing: l}));
		});
	});
}

// a stand-in of both stores at http://store: "METHOD /path" (the query
// left out) answered as recorded; an unknown GET 404, a DELETE 204, another
// call a made resource ("<type>-new"); every call kept with its body
private class Fake {
	public var calls:Array<String> = [];
	public var bodies:Array<Dynamic> = [];

	var routes = new Map<String, {code:Int, answer:Null<Bytes>->Dynamic}>();

	public function new() {}

	public function on(route:String, value:Dynamic, code = 200):Fake {
		routes.set(route, {code: code, answer: _ -> value});
		return this;
	}

	public function answer(route:String, f:Null<Bytes>->Dynamic):Fake {
		routes.set(route, {code: route.startsWith("POST /v1/") ? 201 : 200, answer: f});
		return this;
	}

	// (Play's edit e1 opened, committed and deleted)
	public function edit(base:String):Fake
		return on('POST $base/edits', {id: "e1"}).on('POST $base/edits/e1:commit', {id: "e1"}).on('DELETE $base/edits/e1', null, 204);

	public function install()
		Publish.transport = (method, url, headers, body, file) -> {
			var path = url.substr("http://store".length), q = path.indexOf("?");
			var key = '$method ${q < 0 ? path : path.substr(0, q)}';
			calls.push(key);
			var parsed:Dynamic = body == null ? (file == null ? null : 'file:${file.path}') : try haxe.Json.parse(body.toString()) catch (_:Dynamic) body.toString();
			bodies.push(parsed);
			var r = routes.get(key);
			if (r != null) {
				var v:Dynamic = r.answer(body);
				return {code: r.code, body: v == null ? "" : haxe.Json.stringify(v)};
			}
			if (method == "GET") return {code: 404, body: '{"errors": [{"status": "404"}]}'};
			if (method == "DELETE") return {code: 204, body: ""};
			var type:String = parsed?.data?.type ?? "x";
			return {code: method == "POST" ? 201 : 200, body: haxe.Json.stringify({data: {type: type, id: '$type-new', attributes: {}}})};
		};

	public function writes():Array<String>
		return [for (c in calls) if (!c.startsWith("GET")) c];

	// (the body of the last call of route)
	public function body(route:String):Dynamic {
		var at = calls.lastIndexOf(route);
		return at < 0 ? null : bodies[at];
	}
}
