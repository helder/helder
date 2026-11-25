package lanes;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
import lanes.Tools.*;

using StringTools;

class Pack {
	public static final LANES:Array<Lane> = [
		{name: "android-device", about: "Android packaging and UI tests on adb's device", run: androidDevice},
		{name: "ios-device", about: "iOS tests on a shared simulator (--shard 0/2, 1/2)", run: iosDevice},
		{name: "webview-macos", about: "WKWebView in a drawn window on macOS", run: () -> run("sh", ["tests/platform/webview-macos.sh", helderCli(), "bin/pack/macos-webview"])},
		{name: "signing", about: "iOS distribution signing verified by Apple's tools", run: signing},
		{name: "asset", about: "helder.asset's rejections and embedded files", run: assetLane},
		{name: "pack", about: "Android and iOS packaging, checked without a device", run: packLane}
	];

	static function signing() {
		var h = FileSystem.fullPath(helderCli());
		if (Sys.getEnv("PACK_PREBUILT") == "1")
			interp(cps(["src", "tests/pack"]), "PackCheck", IOS_BUNDLES);
		run("sh", ["tests/pack/signing/verify.sh", h]);
	}

	static function deviceChecks(checks:Array<Array<String>>, ?env:Map<String, String>) {
		var failed = [];
		for (check in checks) try {
			run(check[0], check.slice(1), env);
		} catch (e:Failed) {
			Sys.println(e.message);
			failed.push(check[1]);
		}
		if (failed.length > 0) throw new Failed("device checks failed: " + failed.join(", "));
	}

	static function androidDevice() {
		var h = helderCli();
		mkdirs("bin/pack/rt");
		mkdirs("bin/pack/cache");
		var env = [
			"HXMC_RT_DIR" => Sys.getEnv("HXMC_RT_DIR") ?? FileSystem.fullPath("bin/pack/rt"),
			"HELDER_CACHE" => Sys.getEnv("HELDER_CACHE") ?? FileSystem.fullPath("bin/pack/cache")
		];
		if (!usePrebuilt) {
			run(NODE, ["tests/pack/runtime.mjs", env["HXMC_RT_DIR"]]);
			for (build in [
				{entry: "tests/gfx/android", name: "AndroidCheck"},
				{entry: "tests/os/AndroidTouchCheck.hx", name: "AndroidTouchCheck"},
				{entry: "tests/ui/AndroidLayersCheck.hx", name: "AndroidLayersCheck"},
				{entry: "tests/media/android/MediaAndroidCheck.hx", name: "MediaAndroidCheck"},
				{entry: "tests/media/android/VideoStillCheck.hx", name: "VideoStillCheck"},
				{entry: "tests/os/FoldersCheck.hx", name: "FoldersCheck"}
			]) run(h, ["build", build.entry, "--target", "android-x86_64", "-o", 'bin/pack/${build.name}.apk'], env);
		}
		if (buildOnly) return;
		deviceChecks([
			["sh", "tests/pack/android.sh", h, "bin/pack/android"],
			[NODE, "tests/os/dev/dev-android.mjs", h, "bin/pack/dev-emulator"],
			["sh", "tests/gfx/android.sh", "bin/pack/AndroidCheck.apk", "bin/pack/android-gfx"],
			["sh", "tests/os/android-touch.sh", "bin/pack/AndroidTouchCheck.apk", "bin/pack/android-gfx"],
			["sh", "tests/ui/android-layers.sh", "bin/pack/AndroidLayersCheck.apk", "bin/pack/android-layers"],
			["sh", "tests/media/android/android.sh", "bin/pack/MediaAndroidCheck.apk", "bin/pack/VideoStillCheck.apk", "bin/pack/android-media"],
			["sh", "tests/typescript/native/android.sh", h, "bin/pack/android-ts"],
			["sh", "tests/pack/viewer-android.sh", h, "bin/pack/android-viewer"],
			["sh", "tests/os/folders-android.sh", "bin/pack/FoldersCheck.apk", "bin/pack/android-folders"],
			["sh", "tests/platform/webview-android.sh", h, "bin/pack/android-webview"],
			["sh", "tests/pack/jvm.sh", "bin/pack/android-jvm"],
			["sh", "tests/pack/billing.sh", h, "bin/pack/android-billing"]
		], env);
	}

	static function iosDevice() {
		if (Sys.systemName() != "Mac") throw new Failed("the ios-device lane needs macOS and Xcode");
		if (shardTotal > 2) throw new Failed("ios-device supports at most two shards");
		var h = helderCli(), udid = Sys.getEnv("HELDER_IOS_SIMULATOR");
		var own = !buildOnly && (udid == null || udid == "");
		if (own) udid = output("sh", ["tests/pack/simulator.sh", "create", "helder-test"]).trim();
		var pack = shardTotal == 1 || shardIndex == 0;
		var gfx = shardTotal == 1 || shardIndex == 1;
		var app = "bin/pack/IosCheck.app", tap = Path.join([Sys.getCwd(), "bin/pack/SimTap"]);
		var hello = ["sh", "tests/pack/ios.sh", h, "bin/pack/ios"];
		var webview = ["sh", "tests/platform/webview-ios.sh", h, "bin/pack/ios-webview"];
		var text = ["sh", "tests/platform/textinput-ios.sh", h, "bin/pack/ios-textinput"];
		// (the viewer's phone shell: its Documents browsed)
		var viewer = ["sh", "tests/pack/viewer-ios.sh", h, "bin/pack/ios-viewer"];
		var builds = [];
		if (pack) builds = builds.concat([hello, webview]);
		if (gfx) builds = builds.concat([text, viewer, [h, "build", "tests/gfx/ios", "--target", "ios-sim", "-o", app],
			[h, "build", "tests/gfx/SimTap.hx", "-o", tap]]);
		function execute() {
			if (!usePrebuilt) {
				// Separate commands build separate apps while the simulator boots.
				var saved = Sys.getEnv("IOS_BUILD_ONLY");
				Sys.putEnv("IOS_BUILD_ONLY", "1");
				var workers = [for (check in builds) {name: check[1], process: new Process(check[0], check.slice(1))}];
				Sys.putEnv("IOS_BUILD_ONLY", saved);
				var errors = [];
				var results = new sys.thread.Deque<{name:String, code:Int, out:String}>();
				for (worker in workers) sys.thread.Thread.create(() -> {
					var log = drain(worker.process);
					var code = worker.process.exitCode();
					worker.process.close();
					results.add({name: worker.name, code: code, out: log.out + log.err});
				});
				for (_ in workers) {
					var result = results.pop(true);
					Sys.print(result.out);
					if (result.code != 0) errors.push(result.name);
				}
				if (errors.length > 0) throw new Failed("iOS builds failed: " + errors.join(", "));
			}
			if (buildOnly) return;
			var checks = pack ? [hello, webview] : [];
			if (gfx) checks = checks.concat([["sh", "tests/gfx/ios.sh", app, "bin/pack/ios-gfx", tap], text, viewer]);
			deviceChecks(checks, ["HELDER_IOS_SIMULATOR" => udid, "IOS_PREBUILT" => "1"]);
		}
		try execute() catch (e:haxe.Exception) {
			if (own) run("sh", ["tests/pack/simulator.sh", "delete", udid]);
			throw e;
		}
		if (own) run("sh", ["tests/pack/simulator.sh", "delete", udid]);
	}

	// (the runtime objects: Android's and iOS's are not npm's for this
	// (Checksum's lines: its files' sizes and CRC-32s, the bundle's list; CI's
	// emulator and simulator jobs check the same, tests/pack/android.sh, ios.sh)
	static final CHECKSUM = [for (l in File.getContent("tests/asset/checksum.txt").split("\n")) if (l != "") l];

	// (PackCheck's: the asset fixture's files, exactly)
	static final ASSETS = "assets=tests/asset:files/kept.txt,files/pixels.png";

	static function assetLane() {
		var h = helderCli();
		// (what Asset's definitions reject, at the call)
		for (r in [
			{main: "Missing", error: 'Asset.bytes("files/nothere.txt"): no such file under the class paths or the project'},
			{main: "Case", error: 'Asset.bytes("files/Kept.txt"): "Kept.txt" is "kept.txt" on disk (paths are case-sensitive on Android and the web)'},
			{main: "Absolute", error: 'Asset.bytes("/etc/hostname"): an absolute path'},
			{main: "Parent", error: 'Asset.image("files/../files/pixels.png"): a part ".."'},
			{main: "NotLiteral", error: 'Asset.bytes: name is not static'}
		]) {
			var b = build(cps(["src", "tests/asset", "tests/asset/reject"]).concat(["-main", r.main, "--custom-target", 'hxmc=bin/asset/${r.main}']), 'bin/asset/${r.main}.log');
			if (b.code == 0 || !b.log.contains(r.error)) throw new Failed('${r.main}: expected the error "${r.error}":\n' + b.log);
			Sys.println('asset: ${r.main} rejected: ${r.error}');
		}
		// (this machine: the files in the executable, nothing beside it)
		var exe = exePath("bin/asset/host/Checksum", HOST);
		rmrf("bin/asset/host");
		run(h, ["build", "tests/asset/Checksum.hx", "-o", exe]);
		if (FileSystem.readDirectory("bin/asset/host").join(",") != Path.withoutDirectory(exe)) throw new Failed("bin/asset/host: more than the executable");
		rmrf("bin/asset/empty");
		mkdirs("bin/asset/empty");
		var cwd = Sys.getCwd(), full = FileSystem.fullPath(exe);
		Sys.setCwd("bin/asset/empty");
		var out = output(full, []);
		Sys.setCwd(cwd);
		Sys.print(out);
		for (l in CHECKSUM.concat(["asset: built in files/kept.txt,files/pixels.png"])) if (!out.contains(l + "\n")) throw new Failed('Checksum, alone: no line "$l"');
		// (the web: the referenced files beside the page, no other)
		rmrf("bin/asset/web");
		run(h, ["build", "tests/asset/Checksum.hx", "--target", "web", "-o", "bin/asset/web/Checksum.wasm"]);
		var files = [];
		function walk(d:String) for (n in FileSystem.readDirectory('bin/asset/web/$d')) if (FileSystem.isDirectory('bin/asset/web/$d/$n')) walk('$d/$n') else files.push('$d/$n');
		walk("assets");
		files.sort(Reflect.compare);
		if (files.join(",") != "assets/files/kept.txt,assets/files/pixels.png") throw new Failed('bin/asset/web/assets: ${files.join(", ")}');
		var out = output(NODE, ["--no-warnings", "--stack-size=65500", "src/helder/test/wasi.mjs", "bin/asset/web/Checksum.wasm"]);
		Sys.print(out);
		for (l in CHECKSUM) if (!out.contains(l + "\n")) throw new Failed('Checksum, wasm32-wasi: no line "$l"');
	}

	// machine, tests/pack/runtime.mjs fetches them (Android's from the
	// release @hxmc/cli's package.json names); the builds' HXMC_RT_DIR.
	// The debug key made in a cache of its own, on first use)
	static final IOS_BUNDLES = [
		"bin/pack/Packed-signed.ipa@org.helder.packcheck@signed@encryption@entitlements@landscape@fullscreen@icons",
		"bin/pack/Hello-signed.ipa@org.helder.Hello@signed",
		"bin/pack/Hello.ipa@org.helder.Hello", "bin/pack/Hello.app",
		"bin/pack/project/bin/ios-sim/Packed.app@org.helder.packcheck@entitlements@landscape@fullscreen@icons",
		"bin/pack/Screen.app@org.helder.Screen", 'bin/pack/Checksum.app@org.helder.Checksum@$ASSETS',
		'bin/pack/Checksum.ipa@org.helder.Checksum@$ASSETS'
	];

	static function packLane() {
		var h = helderCli();
		run(NODE, ["tests/pack/runtime.mjs", "bin/pack/rt"]);
		var rt = FileSystem.fullPath("bin/pack/rt");
		rmrf("bin/pack/cache");
		mkdirs("bin/pack/cache");
		var env = ["HXMC_RT_DIR" => rt, "HELDER_CACHE" => FileSystem.fullPath("bin/pack/cache")];
		var required = Sys.getEnv("PACK_REQUIRE") == "1";
		var have = (t:String) -> {
			var ok = FileSystem.exists('$rt/$t/rt.o');
			if (!ok && required) throw new Failed('no runtime objects for $t (tests/pack/runtime.mjs)');
			if (!ok) Sys.println('pack: no runtime objects for $t (tests/pack/runtime.mjs): its builds skipped');
			return ok;
		};
		rmrf("bin/pack/project");
		copy("tests/pack/project", "bin/pack/project");
		mkdirs("bin/pack/project/node_modules/helder");
		var src = FileSystem.fullPath("src").split("\\").join("/");
		File.saveContent("bin/pack/project/node_modules/helder/package.json", haxe.Json.stringify({name: "helder", haxe: {name: "helder", classPath: src}}));
		var checks = [];
		// (PACK_ONLY=ios: the iOS half alone, as CI's Mac runs it for Apple's
		// own tools on the bundles: codesign, plutil, assetutil; Android's is
		// the headless job's, on Linux)
		var only = Sys.getEnv("PACK_ONLY") ?? "";
		var android = only == "" || only == "android", ios = only == "" || only == "ios";
		if (android && have("android-arm64") && have("android-x86_64")) {
			run(h, ["build", "tests/pack/Hello.hx", "--target", "android", "-o", "bin/pack/Hello-arm64.apk"], env);
			run(h, ["build", "tests/pack/Hello.hx", "--target", "android-x86_64", "-o", "bin/pack/Hello-x86_64.apk"], env);
			run(h, ["build", "bin/pack/project", "--target", "android-x86_64"], env);
			// (the screen fixture: CI's emulator runs it, tests/pack/android.sh)
			run(h, ["build", "tests/pack/Screen.hx", "--target", "android-x86_64", "-o", "bin/pack/Screen.apk"], env);
			// (the asset fixture: its files in assets/, files/dropped.txt not; CI's emulator runs it)
			run(h, ["build", "tests/asset/Checksum.hx", "--target", "android-x86_64", "-o", "bin/pack/Checksum.apk"], env);
			// (Java's classes as the program needs them: a drawn ui's listeners, NativeActivity's surface)
			run(h, ["build", "examples/counter", "--target", "android-x86_64", "-o", "bin/pack/Counter.apk"], env);
			checks = checks.concat([
				"bin/pack/Hello-arm64.apk@org.helder.hello@surface", "bin/pack/Hello-x86_64.apk", "bin/pack/project/bin/android/Packed.apk@org.helder.packcheck@landscape@fullscreen@icons",
				"bin/pack/Counter.apk@@surface", "bin/pack/Screen.apk@org.helder.screen@surface",
				'bin/pack/Checksum.apk@org.helder.checksum@$ASSETS'
			]);
			for (c in [{apk: "Counter", want: '{"dex":true,"permissions":[],"services":[],"views":false}'}]) {
				var got = File.getContent('bin/pack/${c.apk}.lib/classes.json');
				if (got != c.want) throw new Failed('bin/pack/${c.apk}.lib/classes.json: $got, not ${c.want}');
			}
			// (release signing, tests/pack/signing's RSA key: an APK, and the
			// project's App Bundle of both ABIs; one of the two settings alone an error)
			var release = [for (k => v in env) k => v];
			release.set("HELDER_ANDROID_SIGNING_CERTIFICATE", FileSystem.fullPath("tests/pack/signing/cert.pem"));
			release.set("HELDER_ANDROID_SIGNING_KEY", FileSystem.fullPath("tests/pack/signing/key.pem"));
			run(h, ["build", "tests/pack/Hello.hx", "--target", "android", "--release", "-o", "bin/pack/Hello-release.apk"], release);
			run(h, ["build", "bin/pack/project", "--target", "android", "--release", "--bundle", "-o", "bin/pack/Packed.aab"], release);
			var half = [for (k => v in env) k => v];
			half.set("HELDER_ANDROID_SIGNING_KEY", FileSystem.fullPath("tests/pack/signing/key.pem"));
			expect(h, ["build", "tests/pack/Hello.hx", "--target", "android", "-o", "bin/pack/Half.apk"], half,
				"release signing takes a certificate and its key: HELDER_ANDROID_SIGNING_CERTIFICATE", 1);
			expect(h, ["build", "tests/pack/Hello.hx", "--target", "android", "--bundle", "-o", "bin/pack/Unsigned.aab"], env,
				"an App Bundle is signed by the upload key", 1);
			checks = checks.concat(["bin/pack/Hello-release.apk@org.helder.hello@surface@release", "bin/pack/Packed.aab@org.helder.packcheck"]);
			if (!File.getContent("bin/pack/cache/android/debug-key").startsWith("helder-android-debug-key 1\n"))
				throw new Failed("bin/pack/cache/android/debug-key: not made on first use");
			Sys.println("pack: the debug key made on first use, in the cache");
			// (the CLI's own fetch of Android's objects, from a stand-in release
			// of the same objects: no HXMC_RT_DIR, a cache of its own)
			run(NODE, ["tests/pack/release.mjs", rt, "bin/pack/release"]);
			rmrf("bin/pack/rt-cache");
			mkdirs("bin/pack/rt-cache");
			var release = FileSystem.fullPath("bin/pack/release").split("\\").join("/");
			expect(h, ["build", "tests/pack/Hello.hx", "--target", "android-x86_64", "-o", "bin/pack/Fetched.apk"], [
				"HXMC_RT_DIR" => "",
				"HELDER_CACHE" => FileSystem.fullPath("bin/pack/rt-cache"),
				"HELDER_RT_URL" => "file://" + (release.startsWith("/") ? "" : "/") + release
			], "fetching");
			var fetched = [for (d in FileSystem.readDirectory("bin/pack/rt-cache/rt")) d];
			if (fetched.length != 1 || !FileSystem.exists('bin/pack/rt-cache/rt/${fetched[0]}/android-x86_64/rt.o'))
				throw new Failed('bin/pack/rt-cache/rt: ${fetched.join(", ")}, not one release\'s android-x86_64 objects');
			checks.push("bin/pack/Fetched.apk");
			Sys.println('pack: Android\'s runtime objects fetched on first use (${fetched[0]})');
		}
		// (helder publish against a stand-in of Google Play's and App Store Connect's APIs)
		if (android && ios && have("android-arm64") && have("android-x86_64") && have("macos-arm64")) run(NODE, ["tests/pack/publish.mjs", h, "bin/pack/publish"], env);
		if (ios && have("macos-arm64")) {
			run(h, ["build", "tests/pack/Hello.hx", "--target", "ios", "-o", "bin/pack/Hello.ipa"], env);
			run(h, ["build", "tests/pack/Hello.hx", "--target", "ios-sim", "-o", "bin/pack/Hello.app"], env);
			run(h, ["build", "bin/pack/project", "--target", "ios-sim"], env);
			run(h, ["build", "tests/pack/Screen.hx", "--target", "ios-sim", "-o", "bin/pack/Screen.app"], env);
			run(h, ["build", "tests/asset/Checksum.hx", "--target", "ios-sim", "-o", "bin/pack/Checksum.app"], env);
			run(h, ["build", "tests/asset/Checksum.hx", "--target", "ios", "-o", "bin/pack/Checksum.ipa"], env);
			// (signed for distribution, tests/pack/signing's throwaway CA: the
			// project with an RSA key, its files' paths; Hello with a P-256
			// key, the PEM's text and the profile's base64 in the variables)
			var signing = FileSystem.fullPath("tests/pack/signing");
			var rsa = ["HELDER_IOS_CERTIFICATE" => '$signing/cert.pem', "HELDER_IOS_KEY" => '$signing/key.pem', "HELDER_IOS_PROFILE" => '$signing/test.mobileprovision'];
			var ec = [
				"HELDER_IOS_CERTIFICATE" => File.getContent('$signing/cert-ec.pem'),
				"HELDER_IOS_KEY" => File.getContent('$signing/key-ec.pem'),
				"HELDER_IOS_PROFILE" => haxe.crypto.Base64.encode(File.getBytes('$signing/test.mobileprovision'))
			];
			for (k => v in env) {
				rsa.set(k, v);
				ec.set(k, v);
			}
			run(h, ["build", "bin/pack/project", "--target", "ios", "-o", "bin/pack/Packed-signed.ipa"], rsa);
			run(h, ["build", "tests/pack/Hello.hx", "--target", "ios", "-o", "bin/pack/Hello-signed.ipa"], ec);
			var partial = [for (k => v in env) k => v];
			partial.set("HELDER_IOS_KEY", '$signing/key.pem');
			expect(h, ["build", "tests/pack/Hello.hx", "--target", "ios", "-o", "bin/pack/Unsigned.ipa"], partial,
				"signing for the App Store takes a certificate and its key (HELDER_IOS_IDENTITY: both in one PEM): HELDER_IOS_CERTIFICATE", 1);
			checks = checks.concat(IOS_BUNDLES);
		}
		if (checks.length > 0) interp(cps(["src", "tests/pack"]), "PackCheck", checks);
		// (a phone's tools stood in for: helder run, the dev loop's protocol)
		if (HOST.startsWith("windows-")) return;
		var fake = ["ADB" => FileSystem.fullPath("tests/pack/fake/adb"), "XCRUN" => FileSystem.fullPath("tests/pack/fake/xcrun")];
		for (k => v in env) fake.set(k, v);
		if (android && FileSystem.exists('$rt/android-x86_64/rt.o')) {
			expect(h, ["run", "tests/pack/Hello.hx", "--target", "android"], fake, "running org.helder.hello on Pixel 7");
			run(NODE, ["tests/pack/dev.mjs", h, "bin/pack/dev-android", "android"], env);
		}
		if (ios && only != "ios" && FileSystem.exists('$rt/macos-arm64/rt.o')) run(NODE, ["tests/pack/dev.mjs", h, "bin/pack/dev-ios", "ios"], env);
	}
}
