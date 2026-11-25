package lanes;

import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
import lanes.Tools.*;

using StringTools;

class Viewer {
	public static final LANES:Array<Lane> = [
		{name: "viewer", about: "the image viewer's tests natively and on Eval", run: viewerApp},
		{name: "viewer-window", about: "the viewer in a real window on the GPU", run: viewerWindow},
		{name: "viewer-app", about: "macOS: the viewer as a universal app bundle", run: viewerBundle},
		{name: "apps", about: "build Foundry and Tables, with their type checks", run: apps},
		{name: "viewer-package", about: "the viewer's release packages, checked", run: viewerPackage}
	];

	static function apps() {
		var h = helderCli();
		run(h, ["build", "apps/foundry", "-o", exePath("bin/ci-apps/Foundry", HOST)]);
		run("bun", ["install", "--frozen-lockfile", "--cwd", "apps/tables"]);
		run(h, ["build", "apps/tables", "-o", exePath("bin/ci-apps/Tables", HOST)]);
	}

	static function viewerApp() {
		var h = FileSystem.fullPath(helderCli());
		var here = Sys.getCwd();
		Sys.setCwd("apps/viewer");
		// (natively, and on Eval its logic that opts in; its web build: ui-web)
		try run(h, ["test", "--target", "host,interp"]) catch (e:Failed) {
			Sys.setCwd(here);
			throw e;
		}
		Sys.setCwd(here);
		run(h, ["build", "apps/viewer"]);
	}

	// (GFX_TARGET's build, run on the fixtures with --exit-after: Linux under
	// Xvfb, a Windows target on another host under Wine)
	static function viewerWindow() {
		var h = helderCli();
		var kept = viewerStore();
		run(h, ["build", "--target", GFX_TARGET, "apps/viewer"]);
		var exe = exePath('apps/viewer/bin/$GFX_TARGET/viewer', GFX_TARGET);
		var wine = GFX_TARGET.startsWith("windows-") && !HOST.startsWith("windows-") ? "wine " : "";
		var cmd = '$wine$exe --new --exit-after 3 "apps/viewer/tests/fixtures/folder/photo 2.jpg"';
		var out = 'bin/viewer-window.txt';
		mkdirs("bin");
		if (Sys.systemName() == "Linux") shell('$XVFB -a $cmd > $out') else shell('$cmd > $out');
		var said = File.getContent(out);
		Sys.print(said);
		if (said.indexOf("viewer: photo 2.jpg · 5 / 6 · 1242×1048 (shown") < 0) throw new Failed('the viewer did not show the photo: $said');
		// (its main screen's accessibility tree read whole over AT-SPI, as the ui-draw lane reads AccessApp's: Linux's)
		if (GFX_TARGET.startsWith("linux-") && Sys.systemName() == "Linux") {
			native('bin/ui/$GFX_TARGET/AtspiProbe', uiCp().concat(["-main", "AtspiProbe"]), GFX_TARGET);
			shell('$XVFB -a dbus-run-session -- sh -c \'$exe --new --exit-after 30 "apps/viewer/tests/fixtures/folder/photo 2.jpg" & p=$$!; '
				+ 'bin/ui/$GFX_TARGET/AtspiProbe "photo 2" "image:photo 2.jpg · 5 / 6 · 1242×1048" "menu item:File" "menu item:View"; s=$$?; kill $$p; exit $$s\'');
		}
		// (a PDF's first page, its pages counted)
		var pdf = '$wine$exe --new --exit-after 3 apps/viewer/tests/fixtures/pdf/pages.pdf';
		if (Sys.systemName() == "Linux") shell('$XVFB -a $pdf > $out') else shell('$pdf > $out');
		said = File.getContent(out);
		Sys.print(said);
		if (said.indexOf("viewer: pages.pdf · 1 / 1 · page 1 / 3 (shown") < 0) throw new Failed('the viewer did not show the PDF\'s first page: $said');
		// (a Markdown document: read through its Files, parsed and shown, its picture decoded)
		var md = '$wine$exe --new --exit-after 3 apps/viewer/tests/fixtures/markdown/doc.md';
		if (Sys.systemName() == "Linux") shell('$XVFB -a $md > $out') else shell('$md > $out');
		said = File.getContent(out);
		Sys.print(said);
		if (said.indexOf("viewer: doc.md · 1 / 3 (shown") < 0) throw new Failed('the viewer did not show the Markdown document: $said');
		// (a folder among 40: the sidebar's level of them scrolls, not pushing the window's content past its bottom)
		for (i in 0...40)
			mkdirs('bin/viewer/many/folder $i');
		File.saveContent("bin/viewer/many/folder 0/a.txt", "a");
		var many = '$wine$exe --new --exit-after 3 "bin/viewer/many/folder 0"';
		if (Sys.systemName() == "Linux") shell('$XVFB -a $many > $out') else shell('$many > $out');
		said = File.getContent(out);
		Sys.print(said);
		var ends = ~/ends at ([0-9]+) of ([0-9]+)/;
		if (!ends.match(said) || ends.matched(1) != ends.matched(2)) throw new Failed('the window\'s content does not end at its bottom: $said');
		// (macOS: a video, played by helder.media on VideoToolbox; a video alone, so nothing is heard)
		if (GFX_TARGET.startsWith("macos-") && HOST.startsWith("macos-")) {
			shell('$exe --new --exit-after 2 tests/media/hevc.mp4 > $out');
			said = File.getContent(out);
			Sys.print(said);
			if (said.indexOf("viewer: hevc.mp4 · ") < 0 || said.indexOf(" · 64×48 · 0:01 (shown") < 0) throw new Failed('the viewer did not play the video: $said');
		}
		// (again with no system font found: its own, not a stop)
		var nofont = 'HELDER_NO_SYSTEM_FONTS=1 $cmd';
		if (Sys.systemName() == "Linux") shell('HELDER_NO_SYSTEM_FONTS=1 $XVFB -a $cmd > $out') else shell('$nofont > $out');
		said = File.getContent(out);
		Sys.print(said);
		if (said.indexOf("(shown") < 0) throw new Failed('without system fonts, the viewer did not show the photo: $said');
		// (an image past a texture's side: in tiles)
		mkdirs("bin/viewer");
		run(NODE, ["apps/viewer/tests/bigpng.mjs", "bin/viewer/wide.png", "9000", "2000"]);
		var wide = '$wine$exe --new --exit-after 4 bin/viewer/wide.png';
		if (Sys.systemName() == "Linux") shell('$XVFB -a $wide > $out') else shell('$wide > $out');
		said = File.getContent(out);
		Sys.print(said);
		if (said.indexOf("9000×2000 (shown") < 0) throw new Failed('the viewer did not show a 9000x2000 PNG in tiles: $said');
		// (one viewer: a second launch hands its file to the first, which shows it)
		var first = '$wine$exe --exit-after 6 apps/viewer/tests/fixtures/folder/alpha.png > bin/viewer/first.txt';
		var second = '$wine$exe "apps/viewer/tests/fixtures/folder/photo 2.jpg" > bin/viewer/second.txt';
		var both = '$first & sleep 3; $second; wait';
		if (Sys.systemName() == "Linux") shell('$XVFB -a sh -c \'$both\'') else shell(both);
		var a = File.getContent("bin/viewer/first.txt"), b = File.getContent("bin/viewer/second.txt");
		Sys.print(b + a);
		if (b.indexOf("handed to the running viewer") < 0 || a.indexOf("viewer: photo 2.jpg") < 0) throw new Failed('the second launch did not hand its file to the first: $b / $a');
		// (the file types registered: Windows' registry, Linux's .desktop file)
		if (!GFX_TARGET.startsWith("macos-")) {
			shell('$wine$exe --register > bin/viewer/register.txt');
			var r = File.getContent("bin/viewer/register.txt");
			Sys.print(r);
			if (r.indexOf(GFX_TARGET.startsWith("windows-") ? "helder-viewer.file\\shell\\open\\command" : "helder-viewer.desktop") < 0) throw new Failed('--register: $r');
		}
		viewerStoreKept(kept);
	}

	// (the viewer's runs keep what they keep in a home of their own
	// (HELDER_HOME: its store, its thumbnails' cache; its launches' and their
	// shells', --store where Launch Services passes no environment), not the user's:
	// a test's folders and recent files out of theirs, a second launch
	// handing its file to the test's viewer, not to the user's; the user's
	// own store as it was before: its file's size and time)
	static function viewerStore():{dir:String, user:String} {
		var dir = FileSystem.fullPath("bin") + "/viewer-home";
		rmrf(dir);
		mkdirs(dir);
		Sys.putEnv("HELDER_HOME", dir);
		return {dir: dir, user: userViewerStore()};
	}

	static function viewerStoreKept(kept:{dir:String, user:String}) {
		if (!FileSystem.exists(kept.dir + "/data/helder-viewer/store.json")) throw new Failed('the viewer kept nothing in its test home ${kept.dir}');
		var now = userViewerStore();
		if (now != kept.user) throw new Failed('the viewer\'s runs changed the user\'s own store: $now, was ${kept.user}');
	}

	// (the user's own store, helder.os.Store's place for helder-viewer: its size and time, "none")
	static function userViewerStore():String {
		var home = Sys.getEnv("HOME") ?? "", os = Sys.systemName();
		var dir = os == "Mac" ? '$home/Library/Application Support' : os == "Windows" ? Sys.getEnv("APPDATA") ?? "" : Sys.getEnv("XDG_DATA_HOME") ?? '$home/.local/share';
		var f = '$dir/helder-viewer/store.json';
		if (!FileSystem.exists(f)) return "none";
		var s = FileSystem.stat(f);
		return '${s.size} bytes, ${s.mtime.getTime()}';
	}

	// (macOS: the universal bundle, its Info.plist and slices checked by
	// Apple's tools, then opened by Launch Services with a file: the file
	// reaching the app as an open request, App.onOpen)
	static function viewerBundle() {
		var h = helderCli();
		run(h, ["build", "--target", "macos", "apps/viewer"]);
		var app = "apps/viewer/bin/macos/Viewer.app";
		run("plutil", ["-lint", '$app/Contents/Info.plist']);
		shell('lipo -archs $app/Contents/MacOS/viewer | grep -q "x86_64 arm64\\|arm64 x86_64"');
		var kept = viewerStore();
		var report = FileSystem.fullPath("bin") + "/viewer-app.txt";
		if (FileSystem.exists(report)) FileSystem.deleteFile(report);
		// (absolute: open -a takes a relative path for an application's name)
		var abs = FileSystem.fullPath(app), photo = FileSystem.fullPath("apps/viewer/tests/fixtures/folder/photo 2.jpg");
		// (Launch Services passes no environment: its store by --store)
		shell('open -W -n -a "$abs" "$photo" --args --new --exit-after 5 --report "$report" --store "${kept.dir}"');
		var said = FileSystem.exists(report) ? File.getContent(report) : "(no report)";
		Sys.print(said);
		if (said.indexOf("viewer: photo 2.jpg") < 0) throw new Failed('the bundle, opened with a file, did not show it: $said');
		// (sealed and signed ad hoc by helder: codesign's own check of the bundle)
		run("codesign", ["--verify", "--deep", "--strict", "-vvvv", app]);
		run("codesign", ["-dvvv", app]);
		viewerStoreKept(kept);
	}

	// (the releases of the three desktops from this machine: Linux's on
	// Linux, Windows' and macOS's with their runtime objects from npm)
	static function viewerPackage() {
		var h = helderCli();
		run(NODE, ["tests/pack/runtime.mjs", "bin/pack/rt", "--desktop"]);
		var rt = FileSystem.fullPath("bin/pack/rt"), out = "bin/viewer-package";
		rmrf(out);
		mkdirs(out);
		var id = "org.helder.viewer", made = [];
		if (HOST.startsWith("linux-")) {
			run(h, ["build", "--target", HOST, "--package", "apps/viewer", "-o", out]);
			made.push('$out/' + [for (f in FileSystem.readDirectory(out)) if (f.endsWith(".tar.gz")) f][0]);
		}
		var signing = FileSystem.fullPath("tests/pack/signing");
		if (FileSystem.exists('$rt/windows-x86_64/rt.o')) {
			run(h, ["build", "--target", "windows-x86_64", "--package", "apps/viewer", "-o", out], [
				"HXMC_RT_DIR" => rt,
				"HELDER_WINDOWS_CERTIFICATE" => '$signing/cert.pem',
				"HELDER_WINDOWS_KEY" => '$signing/key.pem',
				"HELDER_WINDOWS_TIMESTAMP_URL" => "none"
			]);
			made.push('$out/' + [for (f in FileSystem.readDirectory(out)) if (f.indexOf("windows") > 0) f][0]);
		} else Sys.println("viewer-package: no windows-x86_64 runtime objects: its package skipped");
		if (FileSystem.exists('$rt/macos-arm64/rt.o') && FileSystem.exists('$rt/macos-x86_64/rt.o')) {
			run(h, ["build", "--target", "macos", "--package", "apps/viewer", "-o", out], ["HXMC_RT_DIR" => rt]);
			made.push('$out/' + [for (f in FileSystem.readDirectory(out)) if (f.indexOf("macos") > 0) f][0]);
		} else Sys.println("viewer-package: no macOS runtime objects: its package skipped");
		interp(cps(["src", "tests/pack"]), "DesktopCheck", [out, id].concat(made));
		var have = (tool:String) -> try {
			var p = new Process(Sys.systemName() == "Windows" ? "where" : "which", [tool]);
			var ok = p.exitCode() == 0;
			p.close();
			ok;
		} catch (_:Dynamic) false;
		if (FileSystem.exists('$out/check/viewer.exe')) {
			if (have("osslsigncode")) run("osslsigncode", ["verify", "-in", '$out/check/viewer.exe', "-CAfile", '$signing/ca.pem']);
			else Sys.println("viewer-package: no osslsigncode: the Authenticode signature checked by DesktopCheck alone");
		}
		if (FileSystem.exists('$out/check/$id.desktop') && have("desktop-file-validate")) run("desktop-file-validate", ['$out/check/$id.desktop']);
		if (FileSystem.exists('$out/check/$id.metainfo.xml') && have("appstreamcli")) run("appstreamcli", ["validate", "--no-net", '$out/check/$id.metainfo.xml']);
		if (HOST.startsWith("macos-")) {
			var zip = [for (f in FileSystem.readDirectory(out)) if (f.indexOf("macos") > 0) f][0];
			if (zip != null) {
				mkdirs('$out/unzipped');
				run("ditto", ["-x", "-k", '$out/$zip', '$out/unzipped']);
				run("codesign", ["--verify", "--deep", "--strict", "-vvvv", '$out/unzipped/Viewer.app']);
			}
		}
	}
}
