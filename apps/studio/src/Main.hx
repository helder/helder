import helder.ui.actions.Actions;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;
import studio.Studio;

// helder studio (apps/studio/README.md): `helder studio [project]`, or
// `studio [project] [--classic] [--events <file>] [--mcp-port <n>] [--agent <name>]
// [--hold-while <file>] [--cover <png>] [--play <screen|app>]` (--cover: the project's cover written, then closed;
// --play: a screen's Play from here at once, or Play app's)
// apps/studio/web/build.mjs runs it headless for each example)
@:renderer(helder.ui.view.NodeRenderer)
class Main implements Markup {
	public static var window(default, null):Null<UiWindow> = null;

	static function main() {
		studio.Studio.processStart = haxe.Timer.stamp();
		var args = Sys.args(), dir:Null<String> = null, events:Null<String> = null, port:Null<Int> = null, holdWhile:Null<String> = null, agent:Null<String> = null;
		var classic = #if (hxmc.target == "wasm32-wasi") true #else false #end;
		var width = 1180, height = 740, exportWeb:Null<String> = null, cover:Null<String> = null, play:Null<String> = null;
		var i = 0;
		while (i < args.length) {
			var a = args[i++];
			switch a {
				case "--events": events = args[i++];
				case "--mcp-port": port = Std.parseInt(args[i++]);
				case "--hold-while": holdWhile = args[i++];
				case "--agent": agent = args[i++];
				case "--classic": classic = true;
				case "--width": width = Std.parseInt(args[i++]) ?? width;
				case "--height": height = Std.parseInt(args[i++]) ?? height;
				case "--export-web": exportWeb = args[i++];
				case "--cover": cover = args[i++];
				case "--play": play = args[i++];
				case _ if (!StringTools.startsWith(a, "--")): dir = a;
				case _: Sys.println('studio: $a: not an option (studio [project] [--events <file>] [--mcp-port <n>] [--agent <name>] [--hold-while <file>])');
			}
		}
		#if !(hxmc.target == "wasm32-wasi")
		// (helder's src/, which this studio was built from: a project without helder in its dependencies builds with it)
		if ((Sys.getEnv("HELDER_SRC") ?? "") == "") Sys.putEnv("HELDER_SRC", studio.BuildInfo.helderSrc());
		var env = Sys.getEnv("HELDER_STUDIO_MCP_PORT");
		if (port == null && env != null && env != "") port = Std.parseInt(env);
		var named = Sys.getEnv("HELDER_STUDIO_AGENT");
		if (agent == null && named != null && named != "") agent = named;
		#end
		#if !(hxmc.target == "wasm32-wasi")
		// (--export-web <dir>: the project for the studio in the browser, its preview built for the web; no window)
		if (exportWeb != null) Sys.exit(studio.WebExport.run(dir ?? ".", exportWeb));
		// (a cover is the classic shell's run: its screen drawn alone)
		if (cover != null) classic = true;
		// (no project: a new folder of the user's, ~/Helder/Untitled n, the blank sheet's)
		if (dir == null && !classic && cover == null) dir = untitled();
		#end
		fonts();
		actions("studio", studio.Shell.StudioAction);
		helder.ui.actions.Keymap.global.bind("secondary-z", studio.Shell.StudioAction.Undo)
			.bind("secondary-shift-z", studio.Shell.StudioAction.Redo)
			.bind("secondary-y", studio.Shell.StudioAction.Redo)
			.bind("escape", studio.Shell.StudioAction.Overview)
			.bind("secondary-k", studio.Shell.StudioAction.Jump)
			.bind("shift-1", studio.Shell.StudioAction.FitAll)
			.bind("shift-2", studio.Shell.StudioAction.FitSelection)
			.bind("secondary-b", studio.Shell.StudioAction.Chat);
		var s = new Studio(dir, {events: events, mcpPort: port, holdWhile: holdWhile, cover: cover, agent: agent, classic: classic, starter: !classic && cover == null});
		#if !(hxmc.target == "wasm32-wasi")
		// (an error of the studio's own out of an event or a frame: shown, the studio going on; in the
		// browser the module ends instead, its page showing its frames, which a WebAssembly catch has not)
		helder.os.App.onError = (e, _) -> {
			s.crashed(e);
			true;
		}
		// (its launcher gone, however it ended: the studio with it. `helder studio`'s: its pipe on
		// stdin (Parent); `helder dev apps/studio`'s: its dev connection, closed. Its own children
		// end with it: the previews' host with its socket, Play's helder dev with its pipe, the agent with its stdin)
		Sys.putEnv("HXMC_DEV_EXIT_WITH_SERVER", "1");
		if (helder.async.Parent.piped()) helder.async.Async.launch(_ -> helder.async.Parent.watch(() -> helder.async.Async.launch(_ -> {
			s.stop();
			Sys.exit(0);
		})));
		#end
		UiWindow.run(<Surface title={s.project == null ? "helder studio" : s.project.name + " · helder studio"} width={width} height={height} titlebar="inset"
			theme={studio.Theme.sheet} background={studio.Theme.c("bg")} dark={true} ref={w -> {
				window = w;
				w.onFrame = () -> s.drawn();
				s.open();
				// (--play <screen>: its Play from here at once, "app": Play app; after this owned scope, from the loop)
				if (play != null) helder.ui.Clock.after(0, () -> s.playWindow(play == "app" ? null : play));
			}} onDrop={(files, x, y) -> s.dropFiles(files, x, y)} onClose={() -> {
				helder.async.Async.launch(_ -> s.stop());
				window.close();
			}}>
			{studio.Shell.view(s)}
		</Surface>);
	}

	// a new project's folder: ~/Helder/Untitled, else Untitled 2, 3…
	static function untitled():Null<String> {
		#if (hxmc.target == "wasm32-wasi")
		return null;
		#else
		var home = Sys.getEnv("HOME") ?? Sys.getEnv("USERPROFILE");
		if (home == null) return null;
		var n = 1;
		while (sys.FileSystem.exists('$home/Helder/Untitled' + (n == 1 ? "" : ' $n'))) n++;
		var d = '$home/Helder/Untitled' + (n == 1 ? "" : ' $n');
		return try {
			sys.FileSystem.createDirectory(d);
			d;
		} catch (_:Dynamic) null;
		#end
	}

	// the studio's fonts: Hanken Grotesk for the interface, Geist Mono for values (apps/studio/fonts)
	public static function fonts() {
		var f = helder.text.SystemFonts.get();
		for (b in [
			helder.asset.Embed.bytes("fonts/HankenGrotesk-Regular.ttf"),
			helder.asset.Embed.bytes("fonts/HankenGrotesk-Medium.ttf"),
			helder.asset.Embed.bytes("fonts/GeistMono-Regular.ttf")
		])
			try f.add(b) catch (_:Dynamic) {}
	}
}
