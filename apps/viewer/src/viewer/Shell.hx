package viewer;

import helder.async.Async;
import helder.ui.Node;
import helder.ui.controls.Look;
import helder.ui.controls.Standard;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.ui.widgets.WindowButtons;
import helder.ui.widgets.WindowButtons.WindowControls;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.ui.SizeClass;
import helder.ui.view.UiFlow.MenuBarView;
import viewer.Decode.Decoded;
import viewer.ViewerActions;

// The viewer's window: the browser (the sidebar, the folder with its
// toolbar and path bar, the inspector) and a file full size in its place
// (ViewerView), the title bar inset (the window's buttons over the
// sidebar's top on macOS, at the top right elsewhere); files dropped on it
// opened; its size and place, the folder, the layout, the order and the
// inspector kept between runs (helder.os.Store "helder-viewer"); decodes
// and listings as helder.jobs' jobs. On a desktop that has one, the
// sidebar is the system's material (Finder's), the rest opaque.
class Shell implements Markup {
	// the toolbar's height, the window's buttons' row (macOS: the sidebar's top)
	public static inline var BAR = 40;

	// helder's controls' look in the system's font, the browser's parts in its tokens
	public static final look = Look.base.with({
		tokens: {font: "system-ui"},
		button: t -> {
			variants: {
				variant: {ghost: {root: {color: t.fg2, hover: {background: t.hover, color: t.fg}}}},
				size: {sm: {icon: {width: 16, height: 16}}}
			}
		},
		parts: {
			panel: t -> {background: t.surface},
			"side-head": t -> {padding: [6, 8, 4, 8], fontSize: 11, fontWeight: 600, color: t.fg3},
			"side-row": t -> {direction: Row, alignItems: Center, columnGap: 8, height: 28, shrink: 0, padding: [0, 8], radius: 8, color: t.fg2,
				hover: {background: t.hover, color: t.fg}, selected: {background: t.accentSoft, color: t.fg, fontWeight: 500},
				open: {color: t.fg, fontWeight: 500}},
			"side-back": t -> {direction: Row, alignItems: Center, columnGap: 2, height: 26, shrink: 1, minWidth: 0, padding: [0, 8, 0, 2], radius: 7,
				color: t.fg3, fontSize: 12, hover: {background: t.hover, color: t.fg}},
			"title-button": t -> {direction: Row, alignItems: Center, columnGap: 4, height: 30, shrink: 1, minWidth: 0, padding: [0, 6, 0, 8],
				radius: 8, fontSize: 14, fontWeight: 600, color: t.fg, hover: {background: t.hover}},
			tool: t -> {direction: Row, alignItems: Center, columnGap: 2, height: 30, shrink: 0, padding: [0, 4, 0, 7], radius: 8, color: t.fg2,
				hover: {background: t.hover, color: t.fg}},
			"head-cell": t -> {direction: Row, alignItems: Center, columnGap: 4, height: 30, color: t.fg3, hover: {color: t.fg}, selected: {color: t.fg}},
			"grid-tile": t -> {radius: 10, hover: {background: t.hover}},
			"thumb-box": t -> {radius: 10, selected: {background: t.accentSoft}},
			photo: t -> {radius: 8, background: t.fill, selected: {ringWidth: 2.5, ringColor: t.accent, ringOffsetWidth: 2, ringOffsetColor: t.surface}},
			"name-pill": t -> {fontSize: 12.5, padding: [1, 6, 1, 6], radius: 5, color: t.fg, selected: {background: t.accent, color: t.accentFg, fontWeight: 500}},
			"list-row": t -> {direction: Row, alignItems: Center, columnGap: 12, height: 30, margin: [0, 6], padding: [0, 14, 0, 10], radius: 7,
				color: t.fg2, hover: {background: t.hover}, selected: {background: t.accent, color: t.accentFg, hover: {background: t.accent}}},
			// (a Markdown document: a column of about 70 characters, 760 points at most, centred; MarkdownView's parts)
			"markdown": t -> {background: t.canvas, color: t.fg},
			"markdown-scroll": t -> {padding: [36, 0, 56, 0]},
			"markdown-row": t -> {width: "100%", maxWidth: 760, padding: [0, 40, 14, 40]},
			"markdown-h1": t -> {fontSize: 28, fontWeight: 650, lineHeight: 1.25, margin: [6, 0, 2, 0], padding: [0, 0, 8, 0], borders: [0, 0, 1, 0],
				borderColor: t.line},
			"markdown-h2": t -> {fontSize: 21, fontWeight: 650, lineHeight: 1.3, margin: [10, 0, 0, 0], padding: [0, 0, 6, 0], borders: [0, 0, 1, 0],
				borderColor: t.line},
			"markdown-h3": t -> {fontSize: 17, fontWeight: 650, lineHeight: 1.35, marginTop: 6},
			"markdown-h4": t -> {fontSize: 15, fontWeight: 650, marginTop: 4},
			"markdown-h5": t -> {fontSize: 14, fontWeight: 650},
			"markdown-h6": t -> {fontSize: 13, fontWeight: 650, color: t.fg2},
			"markdown-p": t -> {fontSize: 15, lineHeight: 1.6},
			"markdown-quote": t -> {rowGap: 10, padding: [2, 0, 2, 16], borders: [0, 0, 0, 3], borderColor: t.edgeStrong, color: t.fg2},
			"markdown-list": t -> {rowGap: 6},
			"markdown-item-body": t -> {rowGap: 6},
			"markdown-marker": t -> {minWidth: 24, paddingRight: 6, fontSize: 15, lineHeight: 1.6, color: t.fg2},
			"markdown-task": t -> {width: 15, height: 15, margin: [5, 9, 0, 0], radius: 4, borderWidth: 1.5, borderColor: t.edgeStrong, fontSize: 10,
				fontWeight: 700, checked: {background: t.accent, borderColor: t.accent, color: t.accentFg}},
			"markdown-code": t -> {padding: [12, 14, 12, 0], radius: 8, background: t.fill},
			"markdown-code-span": t -> {fontFamily: "JetBrains Mono", fontSize: 13.5, color: t.fg},
			"markdown-link": t -> {color: t.info, cursor: Pointer, hover: {textDecoration: 1}},
			"markdown-table": t -> {borders: [1, 0, 0, 1], borderColor: t.line},
			"markdown-th": t -> {fontSize: 14, fontWeight: 600, padding: [7, 12], borders: [0, 1, 1, 0], borderColor: t.line, background: t.fill},
			"markdown-td": t -> {fontSize: 14, lineHeight: 1.45, padding: [7, 12], borders: [0, 1, 1, 0], borderColor: t.line},
			"markdown-rule": t -> {height: 1, margin: [8, 0], background: t.line},
			"markdown-html": t -> {fontFamily: "JetBrains Mono", fontSize: 12.5, color: t.fg3},
			"markdown-image": t -> {radius: 6},
			"markdown-image-alt": t -> {fontSize: 13, italic: true, color: t.fg3, padding: [4, 10], radius: 6, background: t.fill}
		}
	});

	// the types it opens (helder.json's fileHandlers too: a macOS bundle's)
	public static final TYPES = [
		{mime: "image/jpeg", extensions: ["jpg", "jpeg", "jfif"]},
		{mime: "image/png", extensions: ["png", "apng"]},
		{mime: "image/gif", extensions: ["gif"]},
		{mime: "image/webp", extensions: ["webp"]},
		{mime: "application/pdf", extensions: ["pdf"]},
		{mime: "text/markdown", extensions: ["md", "markdown", "mdown"]},
		// (the system's decoders': WIC, ImageIO, Linux's libtiff, libheif and libavif where installed)
		{mime: "image/tiff", extensions: ["tif", "tiff"]},
		{mime: "image/heic", extensions: ["heic", "heif"]},
		{mime: "image/avif", extensions: ["avif"]}
	].concat(helder.media.Decoders.available() ? [
		// (helder.media's, where the system decodes them: FolderModel.MEDIA)
		{mime: "video/mp4", extensions: ["mp4", "m4v"]},
		{mime: "video/quicktime", extensions: ["mov"]},
		{mime: "video/webm", extensions: ["webm"]},
		{mime: "video/x-matroska", extensions: ["mkv"]},
		{mime: "audio/mp4", extensions: ["m4a"]},
		{mime: "audio/mpeg", extensions: ["mp3"]},
		{mime: "audio/flac", extensions: ["flac"]}
	] : []);

	// the viewer's own font (DejaVu Sans, a subset: fonts/README.md), added
	// only when the system has none it finds (a bare Wine prefix, a minimal
	// container): never stopped for lack of one
	public static function fallbackFont() {
		var fonts = helder.text.SystemFonts.get();
		if (fonts.match("sans-serif") == null) fonts.add(helder.asset.Asset.embed("fonts/DejaVuSans-viewer.ttf"));
	}

	#if (hxmc.target != "wasm32-wasi")
	public static function main(args:Array<String>) {
		var mac = hxmc.Platform.os() == 1, phone = Phone.mobile();
		// (a phone: one app, no other to hand files to)
		if (phone) args = args.concat(["--new"]);
		// (--store or HELDER_VIEWER_STORE: what it keeps elsewhere than the user's own, a test's run)
		var dir = storeDir(args, Sys.getEnv("HELDER_VIEWER_STORE"));
		Instance.dir = dir;
		var store = try helder.os.Store.open("helder-viewer", dir) catch (_:Dynamic) null;
		inline function num(k:String, d:Int):Int {
			var v = store == null ? null : Std.parseInt(store.get(k) ?? "");
			return v == null ? d : v;
		}
		fallbackFont();
		// (an event's, a frame's or a task's error: written down with where it was thrown, the window kept)
		var log = store == null ? null : haxe.io.Path.join([haxe.io.Path.directory(store.path), "errors.log"]);
		helder.async.Errors.handler = (e, source) -> {
			var line = 'viewer: an error in the $source: ${e.details()}\n';
			Sys.stderr().writeString(line);
			if (log != null) try {
				var f = sys.io.File.append(log);
				f.writeString(Date.now().toString() + " " + line);
				f.close();
			} catch (_:Dynamic) {}
			true;
		};
		// (--exit-after s: the window closed after s seconds, what it shows
		// printed: a smoke run of the real window and GPU, CI's)
		// (--report file: that line written there too, for a launch whose output is the system's: open -a)
		var valued = ["--exit-after", "--report", "--store"];
		inline function arg(name:String):Null<String>
			return args.indexOf(name) >= 0 ? args[args.indexOf(name) + 1] : null;
		var exitAfter = arg("--exit-after") != null ? Std.parseFloat(arg("--exit-after")) : -1.0, report = arg("--report");
		if (args.contains("--version")) {
			Sys.println("Viewer " + Version.NAME);
			return;
		}
		var path = [for (i in 0...args.length) if (!StringTools.startsWith(args[i], "-") && (i == 0 || !valued.contains(args[i - 1]))) args[i]][0];
		// (--register: the file types registered for this user, "Open with"; then done)
		if (args.contains("--register")) {
			for (w in helder.os.FileTypes.register(mac ? "org.helder.viewer" : "helder-viewer", "Viewer", sys.FileSystem.fullPath(Sys.programPath()), TYPES))
				Sys.println("registered: " + w);
			return;
		}
		// (another viewer running: the file handed to it, this one done; --new: a viewer of its own)
		if (path != null && !args.contains("--new")) {
			var full = sys.FileSystem.fullPath(path);
			var taken = false;
			Async.run(_ -> taken = Instance.handOver(full));
			if (taken) {
				Sys.println("viewer: handed to the running viewer: " + full);
				return;
			}
		}
		// (served before anything slower is made (the places, the thumbnails'
		// cache): a launch right after this one finds it)
		var handed:Array<String> = [], opener:Null<String->Void> = null;
		if (!args.contains("--new")) Instance.serve(p -> if (opener == null) handed.push(p) else opener(p));
		#if helder.headless
		// (a headless run (helder run --headless) the same each time: the listings,
		// decodes and thumbnails on the loop, in order, not on the pool's threads)
		helder.jobs.Jobs.workers = 0;
		#end
		// (a decode's IDCT, upsampling and colours over two threads: the pool decodes two files at once)
		helder.image.JpegDecoder.threads = 2;
		#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64" || hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		// (a phone: its Documents and the folders the user gave it, the places;
		// Add a folder the system's picker; Open in… the share sheet, the files themselves)
		var grants = new GrantFiles();
		var x = phoneExplorer(new PhoneFiles(new NativeFiles(), grants), grants);
		x.openFolder = () -> addFolder(x, grants);
		x.addFolder = x.openFolder;
		x.share = paths -> Async.launch(_ -> helder.os.Share.share({files: paths}));
		#else
		var x = new Explorer(new NativeFiles(), jobDecode, helder.os.Places.user(), helder.os.Places.volumes(), null, jobSizes);
		x.reveal = reveal;
		x.openDefault = openDefault;
		#end
		var viewer = x.viewer;
		viewer.mod = mac ? "Cmd" : "Ctrl";
		x.thumbnails = try new Thumbnails(dir == null ? null : new ThumbCache(512 << 20, 16 << 20, dir + "/thumbs")) catch (_:Dynamic) null;
		// (the keymap: secondary as this platform's; the user's file over the defaults, beside the store)
		helder.ui.actions.Keymap.mac = mac;
		helder.ui.menu.Menus.appName = "Viewer";
		ViewerActions.defaults(helder.ui.actions.Keymap.global);
		if (store != null) helder.ui.actions.Keymap.global.loadUser(haxe.io.Path.join([haxe.io.Path.directory(store.path), "helder-viewer-keymap.json"]));
		if (helder.ui.actions.Keymap.global.error != null) Sys.println("viewer: " + helder.ui.actions.Keymap.global.error);
		// (File's Open Recent: the last eight files opened, kept in the store)
		var recent = store == null || store.get("recent") == null ? [] : [for (r in store.get("recent").split("\n")) if (r != "") r];
		var bar:Null<helder.ui.menu.Menus.MenuBar> = null;
		var places = [for (p in x.sidebar.places.value) {name: p.name, path: p.path}];
		x.recent(recent);
		var opened = viewer.onOpened;
		viewer.onOpened = p -> {
			if (opened != null) opened(p);
			recent = x.recent.value;
			if (store != null) store.set("recent", recent.join("\n"));
			if (bar != null) bar.setMenus(ViewerActions.menus(recent.slice(0, 8), places));
		};
		restore(store, x);
		// (macOS's: Finder's "Open With", the Dock's icon)
		helder.os.App.onOpen = paths -> {
			x.start(paths[0]);
			helder.view.graph.Graph.flush();
		};
		// (Ctrl+O: the system's dialog, the file picked opened in its folder; a phone's: Add Folder)
		viewer.openDialog = () -> {
			if (x.openFolder != null) return x.openFolder();
			if (!helder.os.FileDialog.available() || helder.os.App.windows.length == 0) return;
			var picked = helder.os.FileDialog.open(helder.os.App.windows[0], "Open an image", [{name: "Images", extensions: [for (t in TYPES) for (x in t.extensions) x]}]);
			if (picked != null) x.start(picked);
		};
		if (path != null) x.start(try sys.FileSystem.fullPath(path) catch (_:Dynamic) path) else {
			var dir = home(store, x);
			x.browser.go(dir, store != null && store.get("dir") == dir ? store.get("selected") : null);
		}
		// (files handed over while this one started: opened after its own)
		if (!args.contains("--new")) {
			opener = p -> {
				x.start(p);
				helder.view.graph.Graph.flush();
				for (w in helder.os.App.windows) w.raise();
			};
			for (p in handed.splice(0, handed.length))
				opener(p);
		}
		var window:Null<UiWindow> = null;
		// (the sidebar's material: the window clear, its content opaque but
		// for the sidebar; reduce transparency's opaque as ever)
		var glass = !phone && material(Sys.systemName(), helder.os.DeviceInfo.get().osVersion, Sys.getEnv("XDG_CURRENT_DESKTOP") ?? "");
		var shows = signal(false);
		UiWindow.run(<Surface title={() -> x.full() ? viewer.title() : x.sidebar.title(x.browser.dir())} width={num("width", 1180)} height={num("height", 780)}
			titlebar="inset" background={() -> glass ? "transparent" : "#" + StringTools.hex(ViewerView.canvas(UiWindow.dark()), 6)}
			backdrop={glass ? () -> helder.os.Settings.reducedTransparency() ? "none" : "sidebar" : null} clickThrough={false}
			onDrop={(files, _, _) -> if (files.length > 0) x.start(files[0])}
			onClose={() -> {
				save(store, window, x);
				if (x.thumbnails != null) x.thumbnails.close();
				if (!args.contains("--new")) Instance.leave();
				window.close();
			}}
			ref={w -> {
				window = w;
				if (!phone) w.window.setMinSize(640, 400);
				var placed = store != null && store.exists("x") && store.exists("y");
				if (placed) w.window.moveTo(num("x", 0), num("y", 0));
				asked = {x: placed ? num("x", 0) : null, y: placed ? num("y", 0) : null, width: num("width", 1180), height: num("height", 780)};
				attach(w.ui.root, x);
				// (what the system made of it: none where it has no such material)
				if (glass) renderEffect(() -> helder.os.Settings.reducedTransparency(), _ -> shows(w.window.backdrop == helder.os.WindowBackdrop.Sidebar));
				effect(() -> viewer.fullscreen(), on -> w.window.fullscreen = on);
				// (the window's size and place kept as they change, not only at its close: macOS's Quit, a crash, a logout)
				Async.launch(_ -> while (!w.window.closed) {
					Async.delay(1);
					if (!w.window.closed) save(store, w, x);
				});
				if (exitAfter >= 0) Async.launch(_ -> {
					Async.delay(exitAfter);
					var line = x.full.value ? 'viewer: ${viewer.title.peek()} (${viewer.state.peek()}${viewer.message.peek() == "" ? "" : ": " + viewer.message.peek()}, ${viewer.camera.percent()}%, ${w.window.width}x${w.window.height})'
						: 'viewer: ${x.sidebar.title(x.browser.dir.value)} (browsing, ${ContentView.count(x)}, ${w.window.width}x${w.window.height})';
					Sys.println(line);
					if (report != null) try sys.io.File.saveContent(report, line + "\n") catch (_:Dynamic) {}
					save(store, w, x);
					if (x.thumbnails != null) x.thumbnails.close();
					if (!args.contains("--new")) Instance.leave();
					w.close();
				});
			}}>
			{phone ? null : <MenuBarView menus={ViewerActions.menus(recent.slice(0, 8), places)} ref={b -> bar = b}/>}
			{view(x, null, shows)}
		</Surface>);
	}

	// where the viewer keeps what it keeps (its store, beside it its errors'
	// log and keymap, the running viewer's port, the thumbnails' cache):
	// --store <dir>, else env (HELDER_VIEWER_STORE), else null, the
	// platform's place for the user's own (helder.os.Store, Paths.cache)
	public static function storeDir(args:Array<String>, env:Null<String>):Null<String> {
		var i = args.indexOf("--store");
		if (i >= 0 && i + 1 < args.length && args[i + 1] != "") return args[i + 1];
		return env == null || env == "" ? null : env;
	}

	#end

	// whether the sidebar is the system's material on this desktop (os:
	// Sys.systemName, version: DeviceInfo's, desktop: XDG_CURRENT_DESKTOP):
	// macOS's; Windows 11's Mica (22H2, build 22621, on); KDE's blur. Else
	// none: the window opaque as ever (Windows 10, GNOME, a phone, the web)
	public static function material(os:String, version:String, desktop:String):Bool
		return switch os {
			case "Mac": true;
			case "Windows":
				var parts = version.split(".");
				parts.length >= 3 && (Std.parseInt(parts[2]) ?? 0) >= 22621;
			case "Linux": desktop.split(":").contains("KDE");
			case _: false;
		}

	#if (hxmc.target != "wasm32-wasi")
	// (a phone's explorer: its Documents and its grants; a file on disk
	// (Documents', iOS's grants') decoded as the desktop's are, one that is
	// not (Android's documents) from its bytes)
	static function phoneExplorer(files:Files, grants:GrantFiles):Explorer
		return new Explorer(files, (key, side, done) -> {
			var k = Decode.parseKey(key), local = files.localPath(k.path);
			Async.launch(_ -> done(local != null ? Decode.job(Decode.key(local, k.page), side) : Decode.read(files, key, side)));
		}, phonePlaces().concat(grants.places()), [], (path, done) -> {
			var local = files.localPath(path);
			local != null ? Preview.request(local, done) : Preview.read(files, path, done);
		}, (path, done) -> {
			var local = files.localPath(path);
			local != null ? jobSizes(local, done) : Async.launch(_ -> done(PdfPages.read(files, path)));
		});

	// (a PDF's pages' sizes on a pool's thread: the document opened there, kept for its pages)
	static function jobSizes(path:String, done:PdfPages.PdfSizes->Void)
		Async.launch(_ -> helder.jobs.Jobs.job(PdfPages.sizesOf).run(path)).onCompletion((r, _) ->
			done(r ?? {sizes: [], fileSize: 0, error: "The PDF could not be read"}));

	// (the decode on a pool's thread: Decode.job)
	static function jobDecode(path:String, side:Int, done:Decoded->Void)
		Async.launch(_ -> done(Decode.job(path, side)));

	// (what the window was made with, and what it then measured: a menu bar
	// in the window (Windows'), a frame the place counts or not; kept the
	// same at the next start, so that size and place do not creep run by run)
	static var asked:Null<{x:Null<Int>, y:Null<Int>, width:Int, height:Int}> = null;
	static var offset:Null<{x:Int, y:Int, width:Int, height:Int}> = null;

	static function save(store:Null<helder.os.Store>, w:Null<UiWindow>, x:Explorer) {
		if (store == null) return;
		var b = x.browser, o = b.order.value;
		store.set("status", x.viewer.statusOn.peek() ? "1" : "0");
		if (b.dir.value != "") store.set("dir", b.dir.value);
		store.set("selected", x.full.value ? x.viewer.folder.name : b.selected.value);
		store.set("layout", b.layout.value);
		store.set("sort", o.key + (o.ascending ? " up" : " down") + (o.foldersFirst ? " folders" : ""));
		store.set("hidden", b.hidden.value ? "1" : "0");
		store.set("inspector", b.inspector.value ? "1" : "0");
		if (w == null || x.viewer.fullscreen.peek()) return;
		var k = w.window.scale > 0 ? w.window.scale : 1;
		var p = w.window.position();
		var width = Math.round(w.window.width / k), height = Math.round(w.window.height / k);
		if (offset == null && asked != null) offset = {
			x: p == null || asked.x == null ? 0 : p.x - asked.x,
			y: p == null || asked.y == null ? 0 : p.y - asked.y,
			width: width - asked.width,
			height: height - asked.height
		};
		var o = offset ?? {x: 0, y: 0, width: 0, height: 0};
		if (p != null) {
			store.set("x", Std.string(p.x - o.x));
			store.set("y", Std.string(p.y - o.y));
		}
		store.set("width", Std.string(width - o.width));
		store.set("height", Std.string(height - o.height));
	}

	// (what the store kept: the layout, the order, hidden files, the inspector)
	static function restore(store:Null<helder.os.Store>, x:Explorer) {
		if (store == null) return;
		var b = x.browser;
		if (store.get("layout") == "list") b.layout(List);
		var sort = (store.get("sort") ?? "").split(" ");
		if (["name", "kind", "modified", "size"].contains(sort[0]))
			b.setOrder({key: cast sort[0], ascending: sort[1] != "down", foldersFirst: sort.contains("folders")});
		b.hidden(store.get("hidden") == "1");
		b.inspector(store.get("inspector") != "0");
		x.viewer.statusOn(store.get("status") == "1");
	}

	// (a phone's own place: the app's documents folder, which the system's
	// Files app shows as the app's; the folders the user adds come after)
	static function phonePlaces():Array<helder.os.Places.Place> {
		var d = helder.os.Paths.documents();
		return d == null ? [] : [{kind: Documents, name: "Documents", path: d}];
	}

	// (where a start without a path opens: the last folder (its selection kept), else Pictures, else home)
	static function home(store:Null<helder.os.Store>, x:Explorer):String {
		var last = store == null ? null : store.get("dir");
		if (last != null && x.files.stat(last)?.kind == Folder) return last;
		for (kind in [helder.os.Places.PlaceKind.Pictures, helder.os.Places.PlaceKind.Home, helder.os.Places.PlaceKind.Documents])
			for (p in x.sidebar.places.value)
				if (p.kind == kind) return p.path;
		return Sys.getCwd();
	}

	#end

	// a folder the user picks in the system's picker (helder.os.Folders: a
	// phone's, the browser's) kept and shown: the shell's Add Folder
	public static function addFolder(x:Explorer, grants:GrantFiles)
		Async.launch(_ -> {
			var g = helder.os.Folders.pick();
			if (g != null) showFolder(x, grants, g);
		});

	// a folder granted (picked, dropped) shown, a place of the sidebar's
	public static function showFolder(x:Explorer, grants:GrantFiles, g:helder.os.Folders.FolderGrant) {
		var path = grants.add(g);
		if (!Lambda.exists(x.sidebar.places.value, p -> p.path == path)) x.sidebar.add({kind: Pictures, name: g.name, path: path});
		x.close();
		x.choose(path);
		helder.view.graph.Graph.flush();
	}

	// the actions on the root (its key context "Viewer", with browser or
	// full, fullscreen, pdf, markdown, media, goto and about while they are;
	// ViewerActions' default keymap in the app's)
	public static function attach(root:Node, x:Explorer) {
		ViewerActions.defaults(helder.ui.actions.Keymap.global);
		var viewer = x.viewer;
		renderEffect(() -> "Viewer" + (x.full() ? " full" : " browser") + (viewer.fullscreen() ? " fullscreen" : "")
			+ (x.full() && viewer.pdf() != null ? " pdf" : "") + (x.full() && viewer.markdown() != null ? " markdown" : "")
			+ (x.full() && viewer.media() != "" ? " media" : "") + (viewer.gotoOpen() ? " goto" : "")
			+ (viewer.aboutOpen() ? " about" : ""),
			c -> root.keyContext = helder.ui.actions.KeyContext.parse(c));
		x.copy = p -> if (root.ui != null) root.ui.clipboard.write(p);
		root.on(ViewerAction, a -> switch a {
			case PlayPause:
				MediaView.toggle();
				true;
			case StepForward:
				MediaView.step(1);
				true;
			case StepBack:
				MediaView.step(-1);
				true;
			case ToggleMute:
				MediaView.toggleMute();
				true;
			case _: x.perform(a);
		}, x.actionState);
		// (Help's About, macOS's application menu's: the about card)
		root.on(helder.ui.actions.Actions.StandardAction, a -> switch a {
			case About:
				viewer.aboutOpen(true);
				true;
			case _: false;
		}, a -> a == About ? Enabled : Unhandled);
	}

	#if (hxmc.target != "wasm32-wasi")
	// (the system's file manager at the file: Finder, Explorer, the FileManager1 portal's caller, else the folder opened)
	static function reveal(path:String) {
		var os = Sys.systemName();
		if (os == "Mac") spawn("open", ["-R", path]) else if (os == "Windows") spawn("explorer", ["/select," + path]) else
			spawn("dbus-send", ["--session", "--dest=org.freedesktop.FileManager1", "--type=method_call", "/org/freedesktop/FileManager1",
				"org.freedesktop.FileManager1.ShowItems", "array:string:file://" + path, "string:"], () -> spawn("xdg-open", [haxe.io.Path.directory(path)]));
	}

	static function openDefault(path:String) {
		var os = Sys.systemName();
		if (os == "Mac") spawn("open", [path]) else if (os == "Windows") spawn("cmd", ["/c", "start", "", path]) else spawn("xdg-open", [path]);
	}

	// (a program run, not waited for by the window; failed: otherwise)
	static function spawn(cmd:String, args:Array<String>, ?otherwise:Void->Void)
		Async.launch(_ -> {
			var code = try {
				var p = new helder.async.Process(cmd, args);
				var c = p.wait();
				p.close();
				c;
			} catch (_:Dynamic) -1;
			if (code != 0 && otherwise != null) otherwise();
		});

	#end

	// the window's content by the screen's size class (size: the class it
	// is drawn for, else the window's): on a phone (Compact) Phone's stack;
	// on a tablet (Medium) the browser with its sidebar over the folder and
	// its inspector in a sheet, no path bar; else (Expanded) the browser,
	// or a file full size over it (to assistive technology the one shown
	// alone). material: the system's behind the window (Shell.material),
	// seen through the sidebar alone
	public static function view(x:Explorer, ?size:Read<SizeClass>, ?material:Read<Bool>):View {
		var cls:Read<SizeClass> = size ?? () -> SizeClass.current();
		var glass:Read<Bool> = material ?? () -> false;
		return <Standard.Themed look={look}>
			<Switch>
				<Match when={cls() == Compact}><Phone.Root x={x}/></Match>
				<Match when={true}><Desktop x={x} medium={() -> cls() == Medium} material={glass}/></Match>
			</Switch>
		</Standard.Themed>;
	}

	static function Desktop(props:{x:Explorer, medium:Read<Bool>, material:Read<Bool>}):View {
		var x = props.x, b = x.browser, medium = props.medium;
		// (the material through the sidebar: the window's own canvas under the rest)
		var clear = () -> props.material() && !medium();
		// (a large folder, not watched: read again when the pointer comes back to the window)
		function back()
			if (!x.full.value && b.total.value >= Browser.WATCH_BELOW && !b.reading.value) b.refresh();
		return <view tag="window" grow={1} min-height={0} background={clear() ? ("transparent" : Dynamic) : Look.ref.canvas} color={Look.ref.fg} font-family="system-ui" font-size={13} onPointerEnter={back}
			ref={(n:Node) -> x.zoom.attach(n)}>
			<view tag="browser" grow={1} min-height={0} direction="row" hidden={x.full()}>
				<Show when={!medium()}>{SidebarView.make(x)}</Show>
				<view grow={1} min-width={0} direction="row" padding-top={WindowButtons.side() == "end" ? 32 : 0}
					background={clear() ? Look.ref.canvas : null}>
					{ContentView.make(x, medium)}
					<Show when={b.inspector() && !medium()}>{InspectorView.make(x)}</Show>
				</view>
			</view>
			<Show when={medium()}>{Tablet.make(x)}</Show>
			{ViewerView.make(x)}
			{Flight.layer(x.zoom)}
			<Show when={WindowButtons.side() == "end"}>
				<view position="absolute" top={0} left={medium() ? 0 : SidebarView.WIDTH} right={0} height={Shell.BAR} drag-region
					display={x.full() ? "none" : "flex"}/>
			</Show>
			<view tag="window-start" position="absolute" top={0} left={16} height={Shell.BAR} direction="row" align-items="center"><WindowControls side="start"/></view>
			<view tag="window-end" position="absolute" top={0} right={0} direction="row"><WindowControls side="end"/></view>
			<Show when={x.viewer.aboutOpen()}>{about(x.viewer)}</Show>
		</view>;
	}

	static function about(viewer:Viewer):View
		return <view tag="about-backdrop" position="absolute" inset={0} background={Look.ref.scrim} align-items="center" justify="center"
			onClick={_ -> viewer.aboutOpen(false)}>
			<view tag="about" width={340} padding={20} row-gap={6} radius={12} background={Look.ref.raised} border-width={1} border-color={Look.ref.edge}
				align-items="center" shadow="0 8px 30px rgba(0, 0, 0, 0.25)">
				<image src={helder.image.Image.decode(helder.asset.Asset.embed("about-icon.png"))} width={72} height={72}/>
				<text tag="about-name" font-size={18} color={Look.ref.fg}>Viewer</text>
				<text tag="about-version" color={Look.ref.fg3}>{"Version " + Version.NAME}</text>
				<text color={Look.ref.fg2} text-align="center">helder's image viewer and file browser: PNG, JPEG, GIF, WebP, PDF and the system's formats</text>
				<text color={Look.ref.fg3} text-align="center">MIT License · github.com/helder/helder</text>
			</view>
		</view>;
}
