package lanes;

import sys.FileSystem;
import sys.io.File;
import lanes.Tools.*;

using StringTools;

class Os {
	public static final LANES:Array<Lane> = [
		{name: "app", about: "App.run turning helder.async's loop", run: app},
		{name: "window", about: "helder.os's windows, menus, input methods and accessibility", run: window},
		{name: "wayland", about: "helder.os on Wayland under a headless weston", run: wayland},
		{name: "store", about: "macOS: helder.store in an app bundle", run: store},
		{name: "os", about: "helder.os Places and Trash", run: placesTrash},
		{name: "glass-window", about: "macOS: a window with Liquid Glass", run: glassWindow},
		{name: "system-images", about: "the system's image and media decoders", run: systemImages},
		{name: "dbus", about: "the D-Bus client against a real dbus-daemon", run: dbus},
		{name: "audio", about: "helder.os's audio back ends without speakers", run: audio},
		{name: "audio-web", about: "WebAudio and helder.media on the web", run: audioWeb},
		{name: "touch-web", about: "pointers, back and history in headless Chromium", run: touchWeb}
	];

	static function app() {
		native('bin/os/$GFX_TARGET/AppLoopCheck', cps(["src", "tests/os"]).concat(["-main", "AppLoopCheck"]), GFX_TARGET);
		var exe = exePath('bin/os/$GFX_TARGET/AppLoopCheck', GFX_TARGET);
		if (GFX_TARGET.startsWith("linux-")) shell('$XVFB -a ' + exe) else run(exe, []);
	}

	// (the viewer's own tests from its directory, its project: helder test there)
	static function store() {
		if (Sys.systemName() != "Mac") throw new Failed("the store lane: on macOS only");
		var app = "bin/store/StoreCheck.app";
		run(helderCli(), ["build", "tests/store/StoreCheck.hx", "--target", "macos", "-o", app]);
		if (!FileSystem.exists('$app/Contents/Frameworks/HelderStore.dylib')) throw new Failed('$app: no Contents/Frameworks/HelderStore.dylib');
		shell('codesign --verify --deep --strict -v $app');
		var archs = ["arm64"];
		if (Sys.command("sh", ["-c", "arch -x86_64 /usr/bin/true 2> /dev/null"]) == 0) archs.push("x86_64");
		for (a in archs) {
			shell('arch -$a $app/Contents/MacOS/StoreCheck > bin/store/$a.txt');
			var said = File.getContent('bin/store/$a.txt');
			Sys.print(said);
			if (said.indexOf("store: available true") < 0 || said.indexOf("store: ok") < 0) throw new Failed('StoreCheck ($a): $said');
		}
	}

	// (ui-draw's too, which CI runs on Linux only)
	static function glassWindow() {
		if (!GFX_TARGET.startsWith("macos-")) {
			Sys.println("glass-window: macOS's: skipped");
			return;
		}
		native('bin/ui/$GFX_TARGET/GlassWindowCheck', uiCp().concat(["-main", "GlassWindowCheck"]), GFX_TARGET);
		shell('HELDER_BACKGROUND=1 bin/ui/$GFX_TARGET/GlassWindowCheck');
	}

	static function systemImages() {
		native('bin/os/$GFX_TARGET/SystemImagesCheck', cps(["src", "tests/os"]).concat(["-main", "SystemImagesCheck"]), GFX_TARGET);
		var exe = exePath('bin/os/$GFX_TARGET/SystemImagesCheck', GFX_TARGET), args = ["tests/os/images"];
		if (GFX_TARGET.startsWith("macos-")) {
			run("sips", ["-s", "format", "heic", "tests/os/images/gradient-lzw.tif", "--out", "bin/os/gradient.heic"]);
			args.push("bin/os/gradient.heic");
		}
		if (GFX_TARGET.startsWith("windows-") && !HOST.startsWith("windows-")) run("wine", [exe].concat(args)) else run(exe, args);
		// (macOS: helder.media's decoders, VideoToolbox's and AudioToolbox's: tests/media/apple/MediaAppleCheck.hx)
		if (GFX_TARGET.startsWith("macos-") && HOST.startsWith("macos-")) {
			native('bin/media/$GFX_TARGET/MediaAppleCheck', cps(["src", "tests/media/apple"]).concat(["-main", "MediaAppleCheck"]), GFX_TARGET);
			run('bin/media/$GFX_TARGET/MediaAppleCheck', ["bin/media"]);
		}
		// (Windows: helder.media's decoders, Media Foundation's: tests/media/windows/MediaWindowsCheck.hx)
		if (GFX_TARGET.startsWith("windows-") && HOST.startsWith("windows-")) {
			native('bin/media/$GFX_TARGET/MediaWindowsCheck', cps(["src", "tests/media/windows"]).concat(["-main", "MediaWindowsCheck"]), GFX_TARGET);
			run(exePath('bin/media/$GFX_TARGET/MediaWindowsCheck', GFX_TARGET), []);
		}
		// (Linux: helder.media's decoders, libavcodec's and VAAPI's: tests/media/linux/MediaLinuxCheck.hx)
		if (GFX_TARGET.startsWith("linux-") && Sys.systemName() == "Linux") {
			native('bin/media/$GFX_TARGET/MediaLinuxCheck', cps(["src", "tests/media/linux"]).concat(["-main", "MediaLinuxCheck"]), GFX_TARGET);
			run('bin/media/$GFX_TARGET/MediaLinuxCheck', ["bin/media"]);
		}
	}

	// (Linux: a private session bus, dbus-run-session)
	static function dbus() {
		exe("bin/os/DBusCheck", cps(["src", "tests/os"]).concat(["-main", "DBusCheck", "-D", "hxmc.libc=glibc"]));
		run("dbus-run-session", ["--", exePath("bin/os/DBusCheck", HOST)]);
	}

	// (Linux: Xvfb; a Windows target on another host: under Wine)
	// (the protocols the bindings are made from, where the system has their XML)
	static final WAYLAND_XML = [
		"/usr/share/wayland/wayland.xml", "/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml",
		"/usr/share/wayland-protocols/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml", "/usr/share/wayland-protocols/stable/viewporter/viewporter.xml",
		"/usr/share/wayland-protocols/staging/fractional-scale/fractional-scale-v1.xml", "/usr/share/wayland-protocols/staging/cursor-shape/cursor-shape-v1.xml",
		"/usr/share/wayland-protocols/unstable/text-input/text-input-unstable-v3.xml", "/usr/share/wayland-protocols/stable/presentation-time/presentation-time.xml",
		"/usr/share/wayland-protocols/staging/single-pixel-buffer/single-pixel-buffer-v1.xml", "/usr/share/wayland-protocols/stable/linux-dmabuf/linux-dmabuf-v1.xml",
		// (KDE's blur behind a window: plasma-wayland-protocols)
		"/usr/share/plasma-wayland-protocols/blur.xml"
	];

	static function wayland() {
		if ([for (x in WAYLAND_XML) if (!FileSystem.exists(x)) x].length == 0) {
			if (FileSystem.exists("bin/wayland/protocol")) rmrf("bin/wayland/protocol");
			mkdirs("bin/wayland/protocol");
			run(TOOL, MARKUP.concat(["-cp", "src", "--run", "helder.os.linux.wayland.Scanner", "bin/wayland/protocol"].concat(WAYLAND_XML)));
			for (f in FileSystem.readDirectory("bin/wayland/protocol"))
				if (File.getContent('bin/wayland/protocol/$f') != File.getContent('src/helder/os/linux/wayland/protocol/$f'))
					throw new Failed('src/helder/os/linux/wayland/protocol/$f differs from what the scanner makes of the system\'s XML (bin/wayland/protocol/$f)');
			Sys.println("wayland: the bindings are the scanner's of the system's XML");
		} else Sys.println("wayland: no wayland-protocols XML here: the bindings not compared");
		if (!GFX_TARGET.startsWith("linux-")) {
			Sys.println("wayland: Linux's alone");
			return;
		}
		native('bin/os/$GFX_TARGET/WaylandCheck', cps(["src", "tests/os"]).concat(["-main", "WaylandCheck"]), GFX_TARGET);
		native('bin/ui/$GFX_TARGET/AsyncScrollWindowCheck', uiCp().concat(["-main", "AsyncScrollWindowCheck"]), GFX_TARGET);
		native('bin/ui/$GFX_TARGET/WaylandLayersWindowCheck', uiCp().concat(["-main", "WaylandLayersWindowCheck"]), GFX_TARGET);
		native('bin/os/$GFX_TARGET/SoftWaylandCheck', cps(["src", "tests/os", "tests/gfx"]).concat(["-main", "SoftWaylandCheck", "-D", "helder.soft"]), GFX_TARGET);
		native('bin/ui/$GFX_TARGET/ShapeWindowCheck', uiCp().concat(["-main", "ShapeWindowCheck"]), GFX_TARGET);
		run(helderCli(), ["build", "apps/viewer"]);
		if (Sys.systemName() != "Linux" || Sys.command("sh", ["-c", "command -v weston > /dev/null"]) != 0) {
			Sys.println("wayland: no weston here: built, not run");
			return;
		}
		shell('sh tests/os/wayland.sh bin/os/$GFX_TARGET/WaylandCheck apps/viewer/bin/$GFX_TARGET/viewer bin/os bin/ui/$GFX_TARGET/AsyncScrollWindowCheck bin/ui/$GFX_TARGET/WaylandLayersWindowCheck bin/os/$GFX_TARGET/SoftWaylandCheck');
		// (a transparent window: X11's, with a compositing manager and without, and Wayland's)
		shell('sh tests/ui/shape.sh bin/ui/$GFX_TARGET/ShapeWindowCheck');
	}

	static function window() {
		native('bin/os/$GFX_TARGET/WindowCheck', cps(["src", "tests/os"]).concat(["-main", "WindowCheck"]), GFX_TARGET);
		var exe = exePath('bin/os/$GFX_TARGET/WindowCheck', GFX_TARGET);
		var wine = GFX_TARGET.startsWith("windows-") && !HOST.startsWith("windows-") ? "wine " : "";
		if (Sys.systemName() == "Linux") shell('$XVFB -a $wine$exe') else run(exe, []);
		if (GFX_TARGET.startsWith("macos-") && HOST.startsWith("macos-")) {
			// (a click on an inactive window: the app active, the window key; a real click, CI's or
			// HELDER_TEST_INPUT=1's, the app not in the background: it takes the focus)
			native('bin/os/$GFX_TARGET/KeyClickCheck', cps(["src", "tests/os"]).concat(["-main", "KeyClickCheck"]), GFX_TARGET);
			var k = 'bin/os/$GFX_TARGET/KeyClickCheck';
			shell('env -u HELDER_BACKGROUND $k');
			shell('env -u HELDER_BACKGROUND $k --plain');
		}
		native('bin/os/$GFX_TARGET/SettingsCheck', cps(["src", "tests/os"]).concat(["-main", "SettingsCheck"]), GFX_TARGET);
		var settings = exePath('bin/os/$GFX_TARGET/SettingsCheck', GFX_TARGET);
		if (Sys.systemName() == "Linux") shell('$XVFB -a $wine$settings') else run(settings, []);
		// (a window drawn on the CPU, -D helder.soft: its frames shown by
		// helder.os.Blit, read back from the window: GfxCheck's window mode;
		// macOS: in a GUI session, the program on the main thread)
		native('bin/os/$GFX_TARGET/GfxTestSoft', gfxCp().concat(["-main", "GfxCheck", "-D", "helder.soft"]), GFX_TARGET);
		var soft = exePath('bin/os/$GFX_TARGET/GfxTestSoft', GFX_TARGET);
		var gui = !GFX_TARGET.startsWith("macos-") || StringTools.trim(output("launchctl", ["managername"], true) ?? "") == "Aqua";
		for (s in ["triangle", "cube"]) {
			var args = ["window", s, 'tests/gfx/$s.png', 'bin/os/soft-$s.png', "5"];
			if (Sys.systemName() == "Linux") shell('$XVFB -a -s "-screen 0 640x480x24" $wine$soft ' + args.join(" "))
			else if (gui) run(soft, args, ["HELDER_THREAD" => "0", "HELDER_BACKGROUND" => "1"])
			else Sys.println("window: not a GUI session: the soft window not run");
		}
		// (a UI in a window drawn on the CPU: its kept frame shown where it
		// changed; Linux's: the golden's fonts, a window of scale 1)
		if (GFX_TARGET.startsWith("linux-")) native('bin/os/$GFX_TARGET/UiDrawTestSoft', uiCp().concat(["-main", "UiDrawCheck", "-D", "helder.soft"]), GFX_TARGET);
		var ui = exePath('bin/os/$GFX_TARGET/UiDrawTestSoft', GFX_TARGET);
		if (GFX_TARGET.startsWith("linux-")) shell('$XVFB -a $ui tests/ui/draw.png bin/os/soft-draw.png --window');
		native('bin/os/$GFX_TARGET/LocaleCheck', cps(["src", "tests/os"]).concat(["-main", "LocaleCheck"]), GFX_TARGET);
		var locale = exePath('bin/os/$GFX_TARGET/LocaleCheck', GFX_TARGET);
		if (wine != "") shell('$wine$locale') else run(locale, []);
		// (macOS: a <Video> drawn and in the system's layer: tests/media/apple/VideoWindowCheck.hx)
		if (GFX_TARGET.startsWith("macos-") && HOST.startsWith("macos-")) {
			native('bin/media/$GFX_TARGET/VideoWindowCheck', cps(["src", "tests/ui", "tests/media/apple"]).concat(["-main", "VideoWindowCheck"]), GFX_TARGET);
			run('bin/media/$GFX_TARGET/VideoWindowCheck', []);
		}
		// (Windows: a <Video> drawn and on its system layer, a still read: tests/media/windows/WinVideoStillCheck.hx)
		if (GFX_TARGET.startsWith("windows-") && HOST.startsWith("windows-")) {
			native('bin/media/$GFX_TARGET/WinVideoStillCheck', cps(["src", "tests/media/windows"]).concat(["-main", "WinVideoStillCheck"]), GFX_TARGET);
			for (mode in ["drawn", "layer-unit", "layer"]) run(exePath('bin/media/$GFX_TARGET/WinVideoStillCheck', GFX_TARGET), [mode, "bin/media"]);
		}
		// (Windows: Liquid Glass drawn on D3D11, its shaders as HLSL: tests/ui/GlassCheck.hx)
		if (GFX_TARGET.startsWith("windows-") && HOST.startsWith("windows-")) {
			native('bin/ui/$GFX_TARGET/GlassCheck', uiCp().concat(["-main", "GlassCheck"]), GFX_TARGET);
			run(exePath('bin/ui/$GFX_TARGET/GlassCheck', GFX_TARGET), ["--smoke"]);
		}
		// (an inset title bar: tests/os/TitleBarCheck.hx)
		native('bin/os/$GFX_TARGET/TitleBarCheck', cps(["src", "tests/os"]).concat(["-main", "TitleBarCheck"]), GFX_TARGET);
		var bar = exePath('bin/os/$GFX_TARGET/TitleBarCheck', GFX_TARGET);
		if (Sys.systemName() == "Linux") shell('$XVFB -a $wine$bar') else run(bar, []);
		// (helder.ui.menu's model as each platform's menus: tests/os/MenuCheck.hx)
		native('bin/os/$GFX_TARGET/MenuCheck', cps(["src", "tests/os"]).concat(["-main", "MenuCheck"]), GFX_TARGET);
		var menus = exePath('bin/os/$GFX_TARGET/MenuCheck', GFX_TARGET);
		if (Sys.systemName() == "Linux") shell('LIBGL_ALWAYS_SOFTWARE=1 $XVFB -a $wine$menus bin/os') else run(menus, ["bin/os"]);
		// (the platform's spellchecker: tests/text/SpellCheck.hx)
		native('bin/text/$GFX_TARGET/SpellCheck', cps(["src", "tests/text"]).concat(["-main", "SpellCheck"]), GFX_TARGET);
		var spell = exePath('bin/text/$GFX_TARGET/SpellCheck', GFX_TARGET);
		if (wine != "") shell('$wine$spell bin/text') else run(spell, ["bin/text"]);
		// (Windows' TSF for drawn text fields, the test the input method; again without it: IMM32's)
		if (GFX_TARGET.startsWith("windows-")) {
			native('bin/os/$GFX_TARGET/TsfCheck', cps(["src", "tests/os"]).concat(["-main", "TsfCheck"]), GFX_TARGET);
			var tsf = exePath('bin/os/$GFX_TARGET/TsfCheck', GFX_TARGET);
			// (a drawn field typed into through it: tests/ui/WinTextCheck.hx)
			native('bin/ui/$GFX_TARGET/WinTextCheck', uiCp().concat(["-main", "WinTextCheck"]), GFX_TARGET);
			var text = exePath('bin/ui/$GFX_TARGET/WinTextCheck', GFX_TARGET);
			if (Sys.systemName() == "Linux") {
				shell('$XVFB -a $wine$tsf');
				shell('HELDER_NO_TSF=1 $XVFB -a $wine$tsf');
				shell('LIBGL_ALWAYS_SOFTWARE=1 $XVFB -a $wine$text');
			} else {
				run(tsf, []);
				run(tsf, [], ["HELDER_NO_TSF" => "1"]);
				run(text, []);
			}
			winAccess();
			// (the program on its own thread, the windows the main one's: the render
			// thread's frames, the compositor's scrolling and animation while the
			// program is blocked, an EDIT over a scroller moved with it)
			for (m in ["RenderThreadCheck", "AsyncScrollWindowCheck"])
				native('bin/ui/$GFX_TARGET/$m', uiCp().concat(["-main", m]), GFX_TARGET);
			var b = 'bin/ui/$GFX_TARGET';
			for (args in [[], ["--anim"], ["--native"]]) {
				if (Sys.systemName() == "Linux") shell('LIBGL_ALWAYS_SOFTWARE=1 $XVFB -a $wine$b/AsyncScrollWindowCheck.exe ${args.join(" ")}') else run('$b/AsyncScrollWindowCheck.exe', args);
			}
			if (Sys.systemName() == "Linux") shell('LIBGL_ALWAYS_SOFTWARE=1 $XVFB -a $wine$b/RenderThreadCheck.exe') else run('$b/RenderThreadCheck.exe', []);
			// (DirectComposition's layers: the textured compositor's stills first,
			// then the stalled layers' and the layers' against them; Wine has none)
			if (HOST.startsWith("windows-")) {
				native('$b/WinLayersWindowCheck', uiCp().concat(["-main", "WinLayersWindowCheck"]), GFX_TARGET);
				run('$b/WinLayersWindowCheck.exe', ['$b/winlayers', "textured"], ["HELDER_SYSTEM_LAYERS" => "0"]);
				run('$b/WinLayersWindowCheck.exe', ['$b/winlayers', "stall"], ["HELDER_SYSTEM_LAYERS" => "stall"]);
				run('$b/WinLayersWindowCheck.exe', ['$b/winlayers', "layers"]);
			}
		}
		// (a transparent window: its frame read back, and the system's view of it: tests/ui/ShapeWindowCheck.hx; Linux's in the wayland lane)
		if ((GFX_TARGET.startsWith("macos-") && Sys.systemName() == "Mac") || (GFX_TARGET.startsWith("windows-") && HOST.startsWith("windows-"))) {
			var s = 'bin/ui/$GFX_TARGET/ShapeWindowCheck';
			native(s, uiCp().concat(["-main", "ShapeWindowCheck"]), GFX_TARGET);
			// (Windows: over a helder window, then over a plain one)
			if (GFX_TARGET.startsWith("windows-")) run(exePath(s, GFX_TARGET), ["--behind", "helder"], ["HELDER_BACKGROUND" => "1"]);
			run(exePath(s, GFX_TARGET), [], ["HELDER_BACKGROUND" => "1"]);
		}
		// (two helder windows on screen, each its background alone: tests/ui/TwoWindowsCheck.hx)
		if (GFX_TARGET.startsWith("windows-") && HOST.startsWith("windows-")) {
			var s = 'bin/ui/$GFX_TARGET/TwoWindowsCheck';
			native(s, uiCp().concat(["-main", "TwoWindowsCheck"]), GFX_TARGET);
			for (m in ["opaque", "transparent"])
				run(exePath(s, GFX_TARGET), [m], ["HELDER_BACKGROUND" => "1"]);
		}
		// (Core Animation's layers: a sidebar switched (#111), a live resize on
		// them and on the window's layer alone (#113), in the background)
		if (GFX_TARGET.startsWith("macos-") && Sys.systemName() == "Mac") {
			var s = 'bin/ui/$GFX_TARGET/SystemLayersWindowCheck';
			native(s, uiCp().concat(["-main", "SystemLayersWindowCheck"]), GFX_TARGET);
			run(s, ["--swap"], ["HELDER_BACKGROUND" => "1"]);
			for (m in ["1", "0"]) run(s, ["--resize"], ["HELDER_BACKGROUND" => "1", "HELDER_SYSTEM_LAYERS" => m]);
		}
		// (helder.ui's NSAccessibility, in process: tests/ui/MacAccessCheck.hx, MacPatternsCheck.hx)
		if (GFX_TARGET.startsWith("macos-") && Sys.systemName() == "Mac")
			for (m in ["MacAccessCheck", "MacPatternsCheck"]) {
				native('bin/ui/$GFX_TARGET/$m', uiCp().concat(["-main", m]), GFX_TARGET);
				run('bin/ui/$GFX_TARGET/$m', []);
			}
	}

	// helder.ui's UI Automation (Windows; a Windows target from Linux under
	// Wine): its providers in process (tests/ui/WinAccessCheck.hx: Plain's
	// controls, a native field; WinPatternsCheck.hx: the fixture's patterns),
	// then UI Automation's own client in another process (WinAccessRemoteCheck:
	// IUIAutomation) reading AccessApp's fixture, acted on to its Save, and
	// its todo, mail and guide screens whole. (Wine's IUIAutomation has no
	// patterns and hangs on a focus handler: there the probe reads, the
	// window is ended after.)
	static function winAccess() {
		var t = GFX_TARGET, b = 'bin/ui/$t';
		for (m in ["WinAccessCheck", "WinPatternsCheck", "AccessApp", "WinAccessRemoteCheck"])
			native('$b/$m', uiCp().concat(["-main", m]), t);
		var wine = !HOST.startsWith("windows-");
		var w = wine ? "wine " : "", x = wine ? "LIBGL_ALWAYS_SOFTWARE=1 HELDER_UNDER_WINE=1 " + XVFB + " -a " : "";
		var app = '$w$b/AccessApp.exe', probe = '$w$b/WinAccessRemoteCheck.exe';
		shell('$x$w$b/WinAccessCheck.exe');
		shell('$x$w$b/WinPatternsCheck.exe');
		var end = wine ? 'kill $$p; wineserver -k; exit $$s' : 'wait $$p && exit $$s', stop = wine ? 'kill $$p; wineserver -k' : 'kill $$p';
		shell('$x sh -c \'HELDER_ACCESS_LOG=1 $app fixture & p=$$!; $probe fixture; s=$$?; $end\'');
		// (the screens' entries in ASCII: Wine's command line is not UTF-8)
		for (screen in ACCESS_SCREENS) {
			var args = [for (a in screen) if (~/^[\x20-\x7e]*$/.match(a)) a];
			shell('$x sh -c \'$app ${screen[0]} & p=$$!; $probe ${args.join(" ")}; s=$$?; $stop; exit $$s\'');
		}
	}

	static function placesTrash() {
		var args = osCp().concat(["-main", "PlacesTrashCheck"]);
		var target = Sys.getEnv("OS_TARGET") ?? HOST;
		var out = exePath("bin/os/PlacesTrashCheck", target);
		// (on Linux, link this without glibc or any desktop libraries)
		hxmc(out, args.concat(["-D", 'hxmc.target=$target']));
		run(target.startsWith("windows-") && target != HOST ? "wine" : out,
			target.startsWith("windows-") && target != HOST ? [out] : []);
		if (target == HOST && target.startsWith("linux-")) {
			var desktop = "bin/os/PlacesTrashGlibc";
			native(desktop, args, target);
			run(desktop, []);
		}
		exe("bin/os/PlacesTrashHeadless", args.concat(["-D", "helder.headless"]));
		run(exePath("bin/os/PlacesTrashHeadless", HOST), []);
		var module = "bin/os/PlacesTrashCheck.wasm";
		wasm(module, args);
		wasi(module);
		run(NODE, ["-e", "const m = new WebAssembly.Module(require('fs').readFileSync(process.argv[1])); if (WebAssembly.Module.imports(m).some(i => i.module !== 'wasi_snapshot_preview1')) throw new Error('desktop imports in the web build')", module]);
	}

	static function osCp()
		return cps(["src", "examples/tone", "tests/os"]);

	static function audio() {
		for (m in ["AudioOutputCheck", "Tone"])
			native('bin/audio/$AUDIO_TARGET/$m', osCp().concat(["-main", m]), AUDIO_TARGET);
		run("sh", ["tests/os/audio.sh", 'bin/audio/$AUDIO_TARGET']);
	}

	static function audioWeb() {
		wasm("bin/audio/AudioOutputCheck.wasm", osCp().concat(["-main", "AudioOutputCheck"]));
		run(NODE, ["tests/os/web.mjs", "bin/audio/AudioOutputCheck.wasm"]);
		wasm("bin/media/WebSourceCheck.wasm", cps(["src", "tests/media"]).concat(["-main", "WebSourceCheck"]));
		run(NODE, ["tests/media/browser.mjs", "bin/media/WebSourceCheck.wasm"]);
		wasm("bin/media/MediaWebCheck.wasm", cps(["src", "tests/media/web"]).concat(["-main", "MediaWebCheck"]));
		run(NODE, ["tests/media/web/browser.mjs", "bin/media/MediaWebCheck.wasm"]);
	}

	static function touchWeb() {
		wasm("bin/os/PointersWebCheck.wasm", cps(["src", "tests/os"]).concat(["-main", "PointersWebCheck"]));
		run(NODE, ["tests/os/pointers-web.mjs", "bin/os/PointersWebCheck.wasm"]);
		run(NODE, ["tests/os/pointers-web.mjs", "bin/os/PointersWebCheck.wasm", "worker"]);
		wasm("bin/os/BackWebCheck.wasm", cps(["src", "tests/os"]).concat(["-main", "BackWebCheck"]));
		run(NODE, ["tests/os/back-web.mjs", "bin/os/BackWebCheck.wasm"]);
		run(NODE, ["tests/os/back-web.mjs", "bin/os/BackWebCheck.wasm", "worker"]);
		wasm("bin/os/NavWebCheck.wasm", uiCp().concat(["-main", "NavWebCheck"]));
		run(NODE, ["tests/ui/nav-web.mjs", "bin/os/NavWebCheck.wasm"]);
		run(NODE, ["tests/ui/nav-web.mjs", "bin/os/NavWebCheck.wasm", "worker"]);
	}
}
