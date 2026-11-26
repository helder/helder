package helder.cli;

import helder.test.Gen;
import helder.test.Test;

// helder.json (HelderJson): read as the web manifest it stands for (the same
// AppConfig a helder.webmanifest gives), its run block, its targets'
// destinations and stores; its mistakes in its own names; the web manifest
// a web build writes from it (no "helder" member); `helder migrate`'s
// conversion and back; helder.run's names
function tests() {
	test("helder.json: the same settings as the web manifest it stands for", () -> {
		var h = HelderJson.parse(haxe.Json.stringify({
			"$schema": HelderJson.SCHEMA,
			name: "Floating Greens",
			label: "Greens",
			description: "Mini golf",
			id: "build.helder.golf",
			version: "1.2",
			build: 7,
			icon: {any: "icon.svg", maskable: "maskable.png"},
			colors: {theme: "#3ED6C3", background: "#060912"},
			splash: {image: "splash.png", dark: {background: "black"}},
			display: "fullscreen",
			orientation: "landscape",
			run: {name: "floating-greens", listed: true, kind: "game", tags: ["golf"], source: "https://github.com/helder/helder"},
			targets: {
				android: {minSdk: 31, licenseKey: "MIIBIjAN", publish: [{to: "play", track: "beta"}], store: "https://play.google.com/store/apps/details?id=build.helder.golf"},
				ios: {bundleId: "build.helder.golf-ios", publish: ["testflight"]},
				windows: {store: "https://apps.microsoft.com/detail/9x"}
			}
		}));
		var m = Manifest.parse(haxe.Json.stringify(h.manifest), HelderJson.FILE);
		var a = App.android("x", m), i = App.ios("x", m);
		equals([a.id, a.label, Std.string(a.versionCode), a.versionName, Std.string(a.minSdk), a.orientation],
			["build.helder.golf", "Greens", "7", "1.2", "31", "landscape"]);
		equals([i.id, i.label], ["build.helder.golf-ios", "Greens"]);
		equals([m.theme, m.background, m.splash.darkBackground], [0xFF3ED6C3, 0xFF060912, 0xFF000000]);
		equals([for (c in m.icons) c.purpose[0] + " " + c.src], ["any icon.svg", "maskable maskable.png"]);
		equals(m.icons[0].sizes, null);
		equals(App.defines(m), ["-D", "helder.fullscreen"]);
		equals(App.licenseKey(m), "MIIBIjAN");
		equals([h.run.name, Std.string(h.run.listed), h.run.kind, h.run.tags.join(",")], ["floating-greens", "true", "game", "golf"]);
		equals([for (d in h.destinations) '${d.target} ${d.to} ${d.track}'], ["android play beta", "ios testflight null"]);
		equals([h.stores.get("android") != null, h.stores.get("windows") != null, h.stores.get("ios") == null], [true, true, true]);
		// (the web build's manifest: the browser's members alone)
		var web:Dynamic = haxe.Json.parse(HelderJson.webText(h.manifest));
		equals([web.name, web.short_name, web.theme_color, Std.string(web.helder)], ["Floating Greens", "Greens", "#3ED6C3", "null"]);
	});
	test("helder.json: run.name from the app's name, an address", () -> {
		equals(HelderJson.parse('{"name": "Floating Greens!", "run": {}}').run.name, "floating-greens");
		var d = HelderJson.parse('{"run": {"name": "viewer", "downloads": {"macos": "https://github.com/helder/helder/releases/latest"}}}').run.downloads;
		equals([d.get("macos"), Std.string(d.get("linux"))], ["https://github.com/helder/helder/releases/latest", "null"]);
		equals(HelderJson.slug("  Ünïcode -- Game 2 "), "n-code-game-2");
		equals(HelderJson.nameProblem("floating-greens"), null);
		equals(HelderJson.nameProblem("ab"), "is not 3 to 40 characters");
		equals(HelderJson.nameProblem("a--b"), "is not lowercase letters, digits and single hyphens (not first or last)");
		equals(HelderJson.nameProblem("2048"), "is only digits");
		equals(HelderJson.entry('{"entry": "Golf.hx"}'), "Golf.hx");
		equals(HelderJson.entry('{}'), null);
	});
	test("helder.json: mistakes, in its own names", () -> {
		function error(json:Dynamic):String
			return Std.string(throws(() -> HelderJson.parse(Std.isOfType(json, String) ? json : haxe.Json.stringify(json))));
		equals(error("[]"), "helder.json: not a JSON object");
		equals(error({nmae: "x"}).split(" (")[0], "helder.json: the top level: no member \"nmae\"");
		equals(error({colors: {theme: "teal-ish"}}), "helder.json: colors.theme: \"teal-ish\" is not a CSS colour (#rrggbb, rgb(), a name)");
		equals(error({build: "two"}), "helder.json: build: a whole number from 1, not \"two\"");
		equals(error({targets: {android: {minSdk: 26}}}), "helder.json: targets: {\"android\": {\"minSdk\": 26}}: 29 is the lowest (Android 10: Bionic's ELF TLS)");
		equals(error({targets: {tv: {}}}).split(" (")[0], "helder.json: targets: no member \"tv\"");
		equals(error({targets: {android: {publish: ["testflight"]}}}), "helder.json: targets.android.publish[0]: \"testflight\": play");
		equals(error({targets: {web: {publish: ["run"]}}}), "helder.json: targets.web.publish[0]: \"run\": none yet for web");
		equals(error({targets: {ios: {store: "http://x"}}}), "helder.json: targets.ios.store: an https URL");
		equals(error({run: {name: "No Spaces"}}), "helder.json: run.name: \"No Spaces\" is not lowercase letters, digits and single hyphens (not first or last)");
		equals(error({run: {kind: "demo"}}), "helder.json: run.kind: \"demo\": game, app, tool");
		equals(error({run: {tags: ["A"]}}), "helder.json: run.tags: at most 5 tags, each lowercase letters, digits and -");
		equals(error({run: {screenshots: ["../x.png"]}}), "helder.json: run.screenshots: at most 8 image files beside helder.json");
		equals(error({run: {downloads: {macos: "https://example.com/viewer.zip"}}}), "helder.json: run.downloads.macos: a GitHub release's URL (https://github.com/<owner>/<repo>/releases/...)");
		equals(error({run: {downloads: {android: "https://github.com/a/b/releases"}}}).split(" (")[0], "helder.json: run.downloads: no member \"android\"");
		equals(error({icon: {round: "a.png"}}).split(" (")[0], "helder.json: icon: no member \"round\"");
		equals(error({links: {schemes: ["My App"]}}), "helder.json: links.schemes: an array of URL schemes (\"myapp\": lower case)");
		equals(error({links: {schemes: ["https"]}}), "helder.json: links.schemes: \"https\" is the system's (domains: https links)");
		equals(error({links: {domains: ["https://example.com"]}}), "helder.json: links.domains: an array of domains (\"example.com\")");
		equals(error({links: {hosts: []}}).split(" (")[0], "helder.json: links: no member \"hosts\"");
		equals(error({targets: {ios: {usage: {contacts: "x"}}}}).split(" (")[0], "helder.json: targets: {\"ios\": {\"usage\"}}: no member \"contacts\"");
		equals(error({targets: {ios: {usage: {camera: " "}}}}), "helder.json: targets: {\"ios\": {\"usage\": {\"camera\"}}}: why the app asks (a sentence)");
	});
	test("helder.json: links and usage strings, as App reads them", () -> {
		var h = HelderJson.parse(haxe.Json.stringify({links: {schemes: ["myapp"], domains: ["example.com"]}, targets: {ios: {usage: {camera: "Scans."}}}}));
		var cfg = Manifest.parse(haxe.Json.stringify(h.manifest), HelderJson.FILE);
		equals(App.links(cfg), {schemes: ["myapp"], domains: ["example.com"]});
		equals(App.ios("x", cfg).usage.camera, "Scans.");
		var face = HelderJson.parse(haxe.Json.stringify({targets: {ios: {usage: {faceid: "Unlocks notes."}}}}));
		equals(App.ios("x", Manifest.parse(haxe.Json.stringify(face.manifest), HelderJson.FILE)).usage.faceid, "Unlocks notes.");
		equals(App.links({}), null);
		equals(App.android("x", cfg).links, {schemes: ["myapp"], domains: ["example.com"]});
	});
	test("helder migrate: a helder.webmanifest as helder.json, the same settings", () -> {
		var old = haxe.Json.stringify({
			name: "Expansion",
			short_name: "Exp",
			description: "A strategy game",
			display: "fullscreen",
			theme_color: "#3ED6C3",
			background_color: "#060912",
			icons: ([{src: "icon.svg", sizes: "any", type: "image/svg+xml"}, {src: "maskable.png", purpose: "maskable"}] : Array<Dynamic>),
			helder: {version: "1.2", build: 3, id: "org.example.expansion", android: {minSdk: 31}, splash: {image: "s.svg"}}
		});
		var text = HelderJson.fromManifest(old);
		var j:Dynamic = haxe.Json.parse(text);
		equals([j.name, j.label, j.id, j.version, j.colors.theme, j.icon.any, j.icon.maskable, j.splash.image, Std.string(j.targets.android.minSdk)],
			["Expansion", "Exp", "org.example.expansion", "1.2", "#3ED6C3", "icon.svg", "maskable.png", "s.svg", "31"]);
		var before = Manifest.parse(old), after = Manifest.parse(haxe.Json.stringify(HelderJson.parse(text).manifest), HelderJson.FILE);
		equals(App.android("x", after), App.android("x", before));
		equals([after.theme, after.background], [before.theme, before.background]);
		equals(after.splash.image, before.splash.image);
	});
	test("helder.json to a web manifest and back: the same settings, then the same text", () -> property(settings, j -> {
		var m = HelderJson.parse(haxe.Json.stringify(j)).manifest;
		var text = HelderJson.fromManifest(haxe.Json.stringify(m));
		var back = HelderJson.parse(text).manifest;
		equals(Manifest.parse(haxe.Json.stringify(back), HelderJson.FILE), Manifest.parse(haxe.Json.stringify(m), HelderJson.FILE), "the settings");
		equals(HelderJson.fromManifest(haxe.Json.stringify(back)), text, "the text");
	}, {cases: 200}));
}

// (a member or none)
private function maybe<T>(g:Gen<T>):Gen<Null<T>>
	return oneOf([constant(null), g]);

// (an object of the members drawn, those not left out)
private function object(c:helder.test.Choices, members:Array<{k:String, g:Gen<Dynamic>}>):Dynamic {
	var o:Dynamic = {};
	for (m in members) {
		var v = c.draw(maybe(m.g));
		if (v != null) Reflect.setField(o, m.k, v);
	}
	return o;
}

private final color = pick(["#3ED6C3", "#060912", "black", "#fff"]);

private final settings:Gen<Dynamic> = c -> {
	var o = object(c, [
		{k: "label", g: pick(["Skies", "Little Skies", ""])},
		{k: "description", g: pick(["Mini golf", "é ★"])},
		{k: "id", g: pick(["build.helder.golf", "org.example.ab2"])},
		{k: "version", g: pick(["1.2", "2.0.1"])},
		{k: "build", g: int(1, 99)},
		{k: "icon", g: oneOf([pick(["icon.svg", "icon.png"]), c -> object(c, [
			{k: "any", g: pick(["icon.svg", "a.png"])},
			{k: "maskable", g: constant("maskable.png")},
			{k: "monochrome", g: constant("mono.svg")}
		])])},
		{k: "colors", g: c -> object(c, [{k: "theme", g: color}, {k: "background", g: color}])},
		{k: "splash", g: c -> object(c, [
			{k: "image", g: constant("splash.png")},
			{k: "background", g: color},
			{k: "dark", g: c -> object(c, [{k: "image", g: constant("dark.png")}, {k: "background", g: color}])}
		])},
		{k: "display", g: pick(["fullscreen", "standalone", "minimal-ui", "browser"])},
		{k: "orientation", g: pick(["any", "portrait", "landscape-primary"])},
		{k: "lang", g: constant("en")},
		{k: "dir", g: pick(["ltr", "rtl"])},
		{k: "categories", g: array(pick(["games", "sports"]), 0, 2)},
		{k: "links", g: c -> object(c, [{k: "schemes", g: constant(["myapp"])}, {k: "domains", g: constant(["example.com"])}])},
		{k: "targets", g: c -> object(c, [{k: "android", g: c -> object(c, [{k: "minSdk", g: int(29, 36)}])}, {k: "ios", g: c -> object(c, [{k: "bundleId", g: constant("org.example.ios")}])}])}
	]);
	o.name = c.draw(pick(["Little Skies", "Expansion", "Café"]));
	o;
}

