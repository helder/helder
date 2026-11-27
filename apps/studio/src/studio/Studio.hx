package studio;

import haxe.Json;
import helder.async.*;

import helder.syntax.Edits;
import helder.syntax.Cst.Kind;
import helder.syntax.Transaction;
import helder.syntax.Transaction.Change;
import helder.ui.*;
import helder.ui.code.CodeEditor;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import studio.Previews;
import studio.Project;
import studio.Turn;

using StringTools;

// The studio's state and what it does (Shell draws it): a project opened,
// its screens' previews (Previews: the program in a process of its own;
// none for a project of design files alone), its design files' frames
// (Designs: interpreted here, an edit drawn again at once),
// the canvas' camera and layout, what is in focus (all screens, or the
// screen zoomed into), the node selected in it, and every edit (Docs: the
// files, one history). An edit's way to the program (commit): a live
// literal's value is patched in the running screens at once (the next
// frame shows it), then the file saved; anything else saved, then built
// and the screens reloaded with their state.
class Studio {
	public static var current(default, null):Null<Studio> = null;
	// when the program started (Main's first line): the cold start's measure
	public static var processStart = haxe.Timer.stamp();

	// the frame under the pointer (its loop played: Host.loop; null: none)
	public final hovered:Signal<Null<String>> = signal(null);
	// (when the frame hovered last was, for its loop's first frame: measured)
	var hoverAt = -1.0;
	// the project was an empty folder, the starter's now (the blank sheet until the first prompt)
	public final starter:Bool;
	// (the blank sheet gone with the first prompt: the canvas fitted again once the chat is beside it)
	var unveiled = false;
	// an agent changed the project (an edit, a file made): the canvas has something of its
	public final touched = signal(false);
	// the canvas has nothing of the agent's yet (nothing on it, or the starter's
	// alone): after the first prompt its places held (Watch's queued blocks)
	// until a frame of the agent's draws (a design's, a story's of its own),
	// the starter's frame never shown (Starter.own)
	var touchedNow = false;
	// (the agent's first frame drawn: the canvas' frames rise into the places the blocks held)
	var rose = false;

	function touch() {
		if (touchedNow) return;
		touchedNow = true;
		touched(true);
		rise();
	}

	function rise() {
		if (rose || !starter || !touchedNow || waiting()) return;
		rose = true;
		marks.rise([for (s in layout.screens()) s.name]);
	}

	public function waiting():Bool {
		revived();
		var p = project;
		if (p == null) return true;
		if (!starter) return p.screens.length == 0;
		// (a failed build: no frame of the agent's comes, its failure shown on the canvas instead)
		var failed = shownFailure() != null;
		return !touched() || !Lambda.exists(p.screens, i -> !starterOwn(i.name) && (failed || shows(i)));
	}

	// (a frame the canvas can show: a design's, a story's with a frame, a still, or what it threw)
	function shows(i:Project.ScreenInfo):Bool {
		if (i.source.match(Design(_))) return true;
		var s = previews?.screen(i.name);
		return s != null && (s.image() != null || s.still() != null || s.crashedSignal());
	}

	// whether a screen is the starter's own, never shown (Starter.own)
	public function starterOwn(name:String):Bool
		return starter && project != null && Starter.own(project.dir, docs, name);
	// (read again when what the project is changes: revive)
	public var project(default, null):Null<Project>;
	public var previews(default, null):Null<Previews>;
	// bumped when they are (a view of the old program's screens made again)
	public final revived = signal(0);
	public final designs:Designs;
	public final docs = new Docs();
	public final camera = new Camera();
	public final layout:Layout;
	public final tools:Tools;
	public final drag:Drag;
	// the project's folder (the sidebar's tree; null: no project)
	public final tree:Null<FileTree>;
	// the file shown: in its viewer (mode "file": an image, a font...), the code view's, a design's page
	public final shown:Signal<Null<String>> = signal(null);
	// the prompt's agent (Agents: the user's own over ACP, else the studio's
	// tools alone), the turn it runs or ran last (the prompt bar's transcript)
	public var agent(default, null):Agent;
	final local:LocalAgent;
	public final turn:Signal<Null<Turn>> = signal(null);
	// (the turn as just changed: the signal's write lands at the event's end)
	var turnNow:Null<Turn> = null;
	// the old shell (--classic: the sidebar, the inspector, the prompt bar;
	// tests/studio's scripted lanes), else the watched one (Watch: a chat, a canvas to watch)
	public final classic:Bool;
	// the chat's turns, the code panel (Watch's shell); what the user tells the agent while it works
	public final talk = new Conversation();
	public final inbox = new Inbox();
	// the agents' questions (studio.ask: the chat's cards, answered there; the answers the inbox's)
	public final questions:Questions;

	function setTurn(t:Null<Turn>, fresh = false) {
		turnNow = t;
		turn(t);
		if (t != null) talk.set(t, fresh);
	}
	public var mcp(default, null):Null<Mcp> = null;
	// the agents here and where they work (Presence: Mcp's sessions, the tools they call), their marks
	public final presence = new Presence();
	public final marks:Marks;
	// "design" (the canvas), "code" (the code view beside the screen), "stories" (the list)
	public final mode = signal("design");
	// the screen zoomed into (its name; null: all screens)
	public final focused:Signal<Null<String>> = signal(null);
	public final selection:Signal<Null<Selection>> = signal(null);
	// the other nodes selected with it (shift-click, a design's frame: the
	// selection the one clicked last, the inspector's)
	public final others:Signal<Array<Selection>> = signal([]);
	// the code view's file
	public final codeFile:Signal<Null<String>> = signal(null);
	// the window is compact (narrower than Theme.COMPACT: a phone, a tablet
	// upright): the panels sheets over the canvas (Sheets), one at a time
	// (sheet: "files", "inspect", "code", "ask"; null: none), each at a
	// detent ("peek", "half", "full")
	public final compact = signal(false);
	public final sheet:Signal<Null<String>> = signal(null);
	public final detent = signal("half");
	// (the sheet and its detent as just set: what the fits read, the signals' writes landing at the event's end)
	var sheetNow:Null<String> = null;
	var detentNow = "half";

	function setSheet(name:Null<String>, d:String) {
		sheetNow = name;
		detentNow = d;
		sheet(name);
		detent(d);
	}
	// what plays (Play: null, nothing), where (Play.targets), a target's last
	// line of output, the story's controls (Story.controls)
	public final playing:Signal<Null<Play.Playing>> = signal(null);
	public final target = signal("studio");
	public final playLog = signal("");
	public final playControls:Signal<Array<Dynamic>> = signal([]);
	// (the played screen's node: its place told to checks, "player")
	public var playScreen:Null<Node> = null;
	var playRect = "";
	#if !(hxmc.target == "wasm32-wasi")
	var targetProcess:Null<Process> = null;
	#end

	// the sidebar's layers shown (its section's header closes it)
	public final layersOpen = signal(true);
	// the command field's list open (secondary-K: Command)
	public final commandOpen = signal(false);
	// the studio's own error nothing caught, shown over it (Crash), and its
	// view's making (Reload: made again, the project and previews kept)
	public final crash:Signal<Null<Crash>> = signal(null);
	public final made = signal(0);
	// the last build's failure (null: none, or the next build was good):
	// why, its first error and the diagnostics (the live frames show it,
	// Board; the prompt's turn can)
	public final failure:Signal<Null<Failure>> = signal(null);
	// the failure as the canvas shows it: the agent's patches settled first (a
	// multi-file change breaks the build between its files, then mends it),
	// none at once; the agent's tools read failure, not this
	public final shownFailure:Signal<Null<Failure>> = signal(null);
	// (when the agent last patched; 0: settled, its build.check or run.snap,
	// its turn's end)
	var patchedAt = 0.0;

	public function settle()
		patchedAt = 0;
	// the status line's message
	public final message = signal("");
	// the stage's size (points): what fits a view; its node; bumped when it changes
	public var stageWidth(default, null) = 0.0;
	public var stageHeight(default, null) = 0.0;
	public var stageNode:Null<Node> = null;
	public final stageSize = signal(0);
	public final editor:CodeEditor;
	// events for checks (--events <file>: JSON lines; in the browser the page's, window.studioWeb.events), measurements
	#if !(hxmc.target == "wasm32-wasi")
	final events:Null<sys.io.FileOutput>;
	#end
	final startedAt:Float;
	var openedAt = 0.0;
	var shownAll = false;
	var firstFrame = false;
	public var frames(default, null) = 0;
	// (the code view's own edits, not applied to it again; its save pending)
	var applyingToEditor = false;
	var saveGeneration = 0;
	// a patch being measured: when it was sent, the frame then, the screen's version then
	var measuring:Null<{t0:Float, frame:Int, screen:Screen, version:Int, label:String}> = null;
	// selection refreshes in flight
	var refreshing = false;
	var refreshAgain = false;
	// (an edit's gesture: its history group)
	public var gesture(default, null) = 0;
	// --cover <png>: the project's cover written there, then the studio closed
	final coverPath:Null<String>;
	var covering = false;
	var covered = false;

	public function new(dir:Null<String>, options:{?events:String, ?mcpPort:Int, ?holdWhile:String, ?cover:String, ?agent:String, ?classic:Bool, ?starter:Bool}) {
		current = this;
		classic = options.classic ?? false;
		startedAt = processStart;
		var p:Null<Project> = null;
		#if (hxmc.target == "wasm32-wasi")
		// (the page's project, opened before the module started)
		starter = false;
		p = try Project.opened() catch (e:Dynamic) {
			Sys.println('studio: the project: $e');
			null;
		}
		#else
		events = options.events == null ? null : sys.io.File.write(options.events, false);
		// (an empty folder: the starter's project, the agent's start)
		starter = dir != null && options.starter == true && Starter.write(dir);
		if (starter) log("starter", {dir: dir});
		Starter.typescript();
		if (dir != null) p = try Project.open(dir) catch (e:Dynamic) {
			Sys.println('studio: $dir: $e');
			null;
		}
		#end
		#if !(hxmc.target == "wasm32-wasi")
		if (p != null && p.typescript) Starter.config(p.dir);
		#end
		project = p;
		previews = p == null || p.live().length == 0 ? null : new Previews(p);
		designs = new Designs(this);
		layout = new Layout(this);
		marks = new Marks(this);
		questions = new Questions(this);
		if (p != null) marks.saw([for (s in p.screens) s.name]);
		groupAt = (file, title) -> {
			var g = Lambda.find(layout.groups(), g -> g.file == file && g.title == title);
			g == null ? null : {x: g.x, y: g.y, w: g.w, h: g.h};
		}
		tools = new Tools(this);
		drag = new Drag(this);
		tree = p == null ? null : new FileTree(p);
		local = new LocalAgent(this);
		agent = agentOf(options.cover == null ? options.agent : "local");
		editor = new CodeEditor("", null);
		editor.view.fontFamily = Theme.CODE;
		editor.view.fontSize = Theme.CODE_SIZE;
		editor.view.lineHeight = Theme.CODE_LINE;
		editor.onChange = codeChanged;
		docs.onChange = changed;
		docs.onGone = gone;
		if (previews != null) {
			previews.onFrame = framed;
			previews.onBuilt = built;
			var pr = previews;
			hold(() -> pr.allShown(), "the screens' first frames", 300);
		}
		#if !(hxmc.target == "wasm32-wasi")
		if (options.holdWhile != null) {
			var f = options.holdWhile;
			hold(() -> !sys.FileSystem.exists(f), 'while $f exists', 600);
		}
		// (a cover's run is no session: no MCP server; a headless one's port a free one, not an agent's)
		if (p != null && options.cover == null) mcp = new Mcp(served, options.mcpPort ?? #if helder.headless 0 #else Mcp.PORT #end);
		#end
		coverPath = options.cover;
		if (coverPath != null) hold(() -> covered, "the cover", 600);
	}

	// another agent for the prompts (the chat's menu: Agents' names), the one before closed
	public function useAgent(name:String) {
		if (Turns.running(turnNow)) return;
		agent.close();
		agent = agentOf(name);
		agentChanged(v -> v + 1);
		bootAgent();
	}

	// bumped when the agent changes (what shows its name reads it)
	public final agentChanged = signal(0);

	// the agent's name as the chat writes it ("Claude"), its colour (Theme.AGENTS)
	public function agentName():String {
		agentChanged();
		return Agents.label(agentId());
	}

	public function agentColour():String {
		agentChanged();
		return Agents.colour(agentId());
	}

	// (the prompt's agent as a question's asker: its Presence's name and colour when it is there)
	function asker():{name:String, colour:String} {
		var p = presence.named(agentName());
		return {name: agentName(), colour: p?.colour ?? agentColour()};
	}

	function agentId():String {
		#if (hxmc.target == "wasm32-wasi")
		return "local";
		#else
		return Std.isOfType(agent, AcpAgent) ? (cast agent : AcpAgent).command.name : "local";
		#end
	}

	// (the one chosen, else the first found; a headless run's local unless one is named)
	function agentOf(name:Null<String>):Agent {
		#if !(hxmc.target == "wasm32-wasi")
		#if helder.headless
		name ??= "local";
		#end
		var c = try Agents.command(name) catch (e:Dynamic) {
			Sys.println('studio: $e');
			null;
		}
		var p = project;
		if (c != null && p != null) {
			Sys.println('studio: the agent: ${c.name} (${c.cmd} ${c.args.join(" ")})');
			var self = this;
			return new AcpAgent(c, {dir: p.dir, docs: docs, mcp: () -> self.mcp?.url, serving: () -> self.mcp != null, snap: screen -> self.snapOf(screen)});
		}
		Sys.println("studio: the agent: local (the studio's tools alone: /tree, /snap, /check, /read)");
		#end
		return local;
	}

	// (a screen's last frame for the agent: run.snap's PNG)
	@:coroutine function snapOf(screen:String):Null<String> {
		var r = tools.call("run.snap", {screen: screen});
		if (r.isError) return null;
		for (c in r.content)
			if (c.type == "image" && c.data != "") return c.data;
		return null;
	}

	// the project opened: the compiler, the screens' program built and started, the MCP server
	public function open() {
		openedAt = haxe.Timer.stamp();
		if (project != null) Async.launch(_ -> watch());
		// (a project of design files alone: its MCP server too, no program)
		if (mcp != null) {
			var m = mcp, p = project;
			Async.launch(task -> m.serve(task, url -> written(p, url)));
		}
		var agents = presence;
		Async.launch(_ -> while (true) {
			Async.delay(1);
			agents.tick();
		});
		var pr = previews;
		if (pr != null) Async.launch(task -> pr.start(task));
		#if (hxmc.target == "wasm32-wasi")
		Async.launch(_ -> studio.web.WebTools.serve(this));
		#end
		// (on the loop: open is the window's making, where no signal is written)
		var self = this;
		Async.launch(_ -> self.bootAgent());
	}

	// the prompt's agent started in the background (an ACP agent: its process,
	// its session), so the first prompt goes straight to it; a failure a row
	// of the chat's (the next prompt starts it again)
	function bootAgent() {
		#if !(hxmc.target == "wasm32-wasi")
		if (!Std.isOfType(agent, AcpAgent) || project == null) return;
		var a:AcpAgent = cast agent, self = this;
		talk.trouble(null);
		booting(true);
		a.boot(message -> {
			self.talk.trouble(message);
			self.log("agent-boot", {failed: message});
		});
		Async.launch(_ -> {
			while (a.starting())
				Async.delay(0.05);
			if (self.agent != a) return;
			self.booting(false);
			self.log("agent-boot", {ms: Math.round(a.bootedIn * 1000)});
		});
		// (a headless run's script waits for it: its prompts timed from a started agent)
		hold(() -> !a.starting(), "the agent's start", 180);
		#end
	}

	// (a prompt sent: when, until a frame shows it)
	var acking = -1.0;

	// an ACP agent starting (its process, its session): the chat's turn says so while its prompt waits
	public final booting = signal(false);

	public function agentStarting():Bool
		return booting();

	// a file made (an agent's project.patch of a path not there, an ACP agent's
	// write): one entry of the history (its undo: gone)
	public function create(file:String, text:String, ?by:String) {
		touch();
		docs.create(file, text, project == null || !file.startsWith(project.dir + "/") ? file : file.substr(project.dir.length + 1), "agent", by);
	}

	// a file deleted (an agent's project.patch {delete}): one entry of the history (its undo: back)
	public function remove(file:String, ?by:String) {
		touch();
		log("removed", {file: file, by: by});
		docs.remove(file, project == null || !file.startsWith(project.dir + "/") ? file : file.substr(project.dir.length + 1), by);
	}

	// a file gone (a made file's undo, a removal): deleted, its frames or
	// stories gone, the program built without it
	function gone(file:String) {
		previews?.forget(file);
		Files.remove(file);
		if (project == null) return;
		if (file.endsWith(".helder")) framesChanged(file, project.design(file, null));
		else if (Project.isStory(file)) storiesChanged(file, null);
		if (shaping(file) && revive()) return;
		if (previews != null && !file.endsWith(".helder")) rebuild(file, true);
	}

	// (a file that can change what the project is: a story, its main, a package's or helder's file)
	static function shaping(file:String):Bool {
		var n = haxe.io.Path.withoutDirectory(file);
		return Project.isStory(file) || ~/^(main\.tsx?|Main\.hx|package\.json|helder\.json)$/.match(n);
	}

	// the project read again when what it is may have changed (its first
	// story or main made, its kind): when its entry, its kind or whether it
	// has a program changed, the new project and its program (Previews,
	// started), the old one stopped; whether it did
	public function revive():Bool {
		#if (hxmc.target == "wasm32-wasi")
		return false;
		#else
		var old = project;
		if (old == null) return false;
		var p:Null<Project> = try Project.open(old.dir) catch (e:Dynamic) {
			Sys.println('studio: ${old.dir}: $e');
			null;
		}
		if (p == null) return false;
		var live = p.live().length > 0;
		if (p.typescript) Starter.config(p.dir);
		if (p.typescript == old.typescript && p.entry?.main == old.entry?.main && p.entry?.typescript == old.entry?.typescript && live == (previews != null)) return false;
		var was = previews;
		project = p;
		previews = live ? new Previews(p) : null;
		if (was != null) Async.launch(_ -> was.stop());
		var pr = previews;
		if (pr != null) {
			pr.onFrame = framed;
			pr.onBuilt = built;
			Async.launch(task -> pr.start(task));
			hold(() -> pr.allShown(), "the screens' first frames", 300);
		}
		revived(v -> v + 1);
		if (marks.saw([for (s in p.screens) s.name])) framesCame();
		log("revived", {typescript: p.typescript, entry: p.entry?.main, screens: [for (s in p.screens) s.name]});
		return true;
		#end
	}

	// the project an MCP route reaches (name null: the one in front; one project today)
	function served(name:Null<String>):Null<Mcp.Target>
		return project != null && (name == null || name == project.name) ? tools : null;

	// (the MCP server's URL where an agent finds it: <out>/mcp.json)
	function written(p:Project, url:String) {
		#if !(hxmc.target == "wasm32-wasi")
		try {
			helder.cli.TestCommand.mkdirs(p.out);
			sys.io.File.saveContent('${p.out}/mcp.json', Json.stringify({url: url, project: p.dir, tools: [for (t in Tools.list) t.name]}, "  ") + "\n");
		} catch (_:Dynamic) {}
		#end
	}

	// an error nothing caught (helder.os.App.onError, Errored): said, logged and shown
	public function crashed(e:Dynamic) {
		var c = Crash.of(e);
		Sys.stderr().writeString('studio: ${c.message}' + (c.stack == "" ? "" : '\n${c.stack}') + "\n");
		log("crash", {message: c.message, where: c.where});
		crash(c);
	}

	// the studio's view made again after a crash (the selection and the command field let go)
	public function reload() {
		crash(null);
		commandOpen(false);
		selection(null);
		others([]);
		made(made.peek() + 1);
	}

	// (a headless run's script waits while the studio waits on its processes: Headless.hold)
	public static function hold(done:Void->Bool, why:String, seconds = 120.0) {
		#if helder.headless
		helder.os.headless.Headless.run.hold(done, why, seconds);
		#end
	}

	public function log(event:String, data:Dynamic) {
		Reflect.setField(data, "event", event);
		Reflect.setField(data, "frame", frames);
		#if (hxmc.target == "wasm32-wasi")
		var line = Json.stringify(data);
		hxmc.unsafe.Arena.scoped(a -> studio.web.StudioWeb.event(a.cstring(line)));
		#else
		if (events == null) return;
		events.writeString(Json.stringify(data) + "\n");
		events.flush();
		#end
	}

	// (each frame the studio draws: the first measured, the stage's size followed)
	public function drawn() {
		var stage = stageNode;
		frames++;
		if (acking > 0) {
			log("acked", {ms: Math.round((haxe.Timer.stamp() - acking) * 1000)});
			acking = -1;
		}
		if (!firstFrame) {
			firstFrame = true;
			var ms = Math.round((haxe.Timer.stamp() - startedAt) * 1000);
			Sys.println('studio: first frame $ms ms after start');
			log("first-frame", {ms: ms});
		}
		// (the stills from the frames file: shown with the studio's frame)
		allShown();
		var w = Main.window == null ? 0.0 : Main.window.ui.width;
		if (w > 0 && (w < Theme.COMPACT) != compactNow) {
			compactNow = w < Theme.COMPACT;
			compact(compactNow);
			if (!compactNow) setSheet(null, "half");
			if (stageWidth > 0) fitView(false);
		}
		if (stage != null && (stage.width != stageWidth || stage.height != stageHeight) && stage.width > 0) {
			// (the canvas stays where it is when the window is resized: fitted at the first size, or a phone's turn)
			var first = stageWidth <= 0 || compactNow || unveiled;
			unveiled = false;
			stageWidth = stage.width;
			stageHeight = stage.height;
			stageSize(v -> v + 1);
			if (first) fitView(false);
		}
		var ps = playScreen, r = ps == null || playing.peek() == null ? null : ps.rect();
		var key = r == null ? "" : '${r.x} ${r.y} ${r.width} ${r.height}';
		if (key != playRect && (playRect = key) != "")
			log("player", {rect: [r.x, r.y, r.width, r.height], stage: [stageWidth, stageHeight], compact: compactNow});
		var f = failure.peek();
		if (f != shownFailure.peek() && (f == null || haxe.Timer.stamp() - patchedAt > SETTLED)) shownFailure(f);
		if (framing && stageWidth > 0) {
			framing = false;
			if (!camera.taken) frameAll();
		} else if (fitted != "" && !camera.taken && !camera.flying && box() != fitted) frameAll();
		showVisible();
		if (marks.anyFresh()) marks.inView(layout.inView());
		designs.follow(openedAt > 0 ? openedAt : startedAt);
		if (coverPath != null && !covering) cover(coverPath);
	}

	// (--cover: the cover's screen, a story's or the app's drawn alone at 2x
	// (showVisible), its frame once there; a design's frame drawn offscreen)
	function cover(path:String) {
		var c = project?.cover();
		var s = c == null ? null : previews?.screen(c.name);
		var img = s?.image.peek();
		if (s != null && (img == null || (c.width > 0 && img.width < c.width * 2))) return;
		covering = true;
		Async.launch(_ -> {
			var r = c == null ? {content: [{type: "text", text: "no screen"}], isError: true} : tools.call("run.snap", {screen: c.name, path: path});
			Sys.println('studio: the cover${c == null ? "" : ", " + c.name}: ${r.content[r.content.length - 1].text}');
			covered = true;
			Main.window?.close();
			if (r.isError) Sys.exit(1);
		});
	}

	// the previews told which screens are in view (the camera's; the others
	// suspended, their last frames kept) and which one is zoomed into (drawn
	// every frame): a preview host draws only those
	function showVisible() {
		var pr = previews;
		if (pr == null || stageWidth <= 0) return;
		var c = coverPath == null ? null : project.cover();
		if (c != null && pr.screen(c.name) != null) {
			pr.show([c.name], c.name, 2);
			return;
		}
		var names = [], rects = [];
		if (mode.peek() != "stories")
			for (r in layout.screens()) {
				var x0 = camera.sx(r.x), y0 = camera.sy(r.y), x1 = camera.sx(r.x + r.w), y1 = camera.sy(r.y + r.h);
				if (x1 > 0 && y1 > 0 && x0 < stageWidth && y0 < stageHeight) {
					names.push(r.name);
					rects.push(r);
				}
			}
		var ds = Main.window == null ? 1.0 : Main.window.renderer.scale;
		// (the frames in view as sharp as the canvas shows them once the camera rests, within Sharp's bounds;
		// the selected one's every frame at the canvas' scale, kept while the camera flies)
		var sharp = Sharp.scale(camera.rest.peek() * ds, rects);
		if (sharp != sharpness.peek()) {
			sharpness(sharp);
			log("sharp", {k: sharp, rest: camera.rest.peek(), t: helder.ui.Clock.now});
			var shown = names.copy();
			hold(() -> sharpShown(pr, shown, sharp), 'the frames in view at ${sharp}x', 120);
		}
		// (a still in view holding fewer pixels than that, a scene's picture: its program woken to draw it so)
		var thin = Lambda.find(names, n -> {
			var s = pr.screen(n);
			s != null && s.image.peek() == null && s.still.peek() != null && s.holds < sharp - 0.01;
		});
		if (thin != null && !woken) {
			woken = true;
			log("sharp-wake", {screen: thin, k: sharp, holds: pr.screen(thin).holds});
			pr.wake();
		}
		if (!camera.flying) {
			var r = focused.peek() == null ? null : layout.rect(focused.peek());
			focusScale = Sharp.scale(camera.k * ds, r == null ? [] : [r]);
		}
		// (what plays: drawn every frame at the display's scale)
		var play = playing.peek();
		var live = play == null || play.kind == "design" || play.kind == "target" ? null : play.screen;
		if (live != null) {
			// (Play runs the program, the screens drawn from the frames file or not)
			pr.wake();
			if (!names.contains(live)) names.push(live);
			// (fitted larger on a phone: its pixels at the size shown)
			var s = pr.screen(live), k = s == null ? 1.0 : Math.max(1, Play.fit(this, s.width(), s.height(), play.kind == "story"));
			var most = s == null ? 3.0 : 4096 / Math.max(1, Math.max(s.width(), s.height()));
			pr.show(names, live, Math.min(Math.min(3 * k, most), ds * k), sharp);
			return;
		}
		// (the watched canvas: stills, the hovered frame's loop running; the old shell's frames live)
		pr.stills = !classic;
		var h = hovered.peek(), info = h == null || classic || !names.contains(h) ? null : project.screen(h);
		pr.looping = info?.loop == null || pr.fileLoops(h) ? null : h;
		pr.show(names, mode.peek() == "stories" ? null : focused.peek(), focused.peek() == null ? 1 : focusScale, sharp);
	}

	// the frames in view's pixels a point (Sharp's): the host's drawn so, the stills' scenes too
	public final sharpness = signal(1.0);

	// (the program's frames of names at k pixels a point, or none to wait for: a headless run's script waits for them)
	static function sharpShown(pr:Previews, names:Array<String>, k:Float):Bool {
		if (pr.failed) return true;
		for (n in names) {
			var s = pr.screen(n), img = s?.image.peek();
			if (s == null || s.crashed) continue;
			if (img == null ? s.still.peek() != null && s.holds < k - 0.01 : img.width < Math.round(s.width() * k) - 1) return false;
		}
		return true;
	}

	// (the program woken for a sharper frame than a still holds: once)
	var woken = false;
	var focusScale = 1.0;

	// ---- the canvas: focus and views

	// a frame selected (null: none), its contents not entered: a design's
	// frame its element (its handles resize it, a drag moves it); fly: the
	// camera to it (the sidebar's, the command's; a click on the canvas
	// leaves the camera where it is)
	public function focus(name:Null<String>, fly = true) {
		focused(name);
		if (name != scrub.peek()?.screen) scrub(null);
		entered(false);
		others([]);
		selection(null);
		var info = name == null ? null : project?.screen(name);
		if (info != null && info.source.match(Design(_)) && info.start != null) selectDesign(info, designs.nodeAt(info.name, info.start), info.start);
		if (fly) fitTo(name, true);
		refreshCode();
		log("focused", {screen: name});
	}

	// the frame the prompt is about (what the agent is sent: its name and its
	// PNG, AcpAgent.blocks): the selected one, unless its chip was cleared (×)
	public function about():Null<String> {
		var f = focused();
		return f == unasked() ? null : f;
	}

	// (the frame whose chip was cleared: still selected, not sent)
	final unasked:Signal<Null<String>> = signal(null);

	// the selection bar's Ask: the prompt about the frame, its field focused
	public function askAbout(name:String) {
		if (focused.peek() != name) focus(name, false);
		unasked(null);
		if (!talk.open.peek()) toggleChat();
		talk.field?.focus();
		log("ask-about", {screen: name});
	}

	// the chip's ×: the prompt about the whole app, the frame still selected
	public function clearAbout() {
		unasked(focused.peek());
		log("ask-about", {screen: null});
	}

	// the selection bar's Code: the frame's story or scenario (or design) file at its line
	public function codeOf(name:String) {
		var info = project?.screen(name);
		if (info == null) return;
		var text = docs.get(info.file).text;
		var line = info.source.match(Design(_)) ? (info.start == null ? 1 : docs.get(info.file).doc.lineCol(info.start).line) : Project.lineOf(info.file, text, name);
		if (classic) openCode(info.file, line) else talk.reading({file: info.file, line: line});
		log("reading", {file: info.file, line: line});
	}

	// the selected loop frame's recorded loop, scrubbed or played (null: not
	// touched, the frame as it is); t: seconds from its moment
	public final scrub:Signal<Null<{screen:String, t:Float, playing:Bool}>> = signal(null);

	// (a loop's length, seconds: its recorded frames')
	var scrubLength = 0.0;

	public function scrubTo(name:String, t:Float, length:Float) {
		scrubLength = length;
		scrub({screen: name, t: Math.max(0, Math.min(length, t)), playing: false});
		log("scrub", {screen: name, t: Math.round(t * 100) / 100});
	}

	// play or pause the recorded loop (its clock this studio's: round and round)
	public function scrubPlay(name:String, on:Bool, length:Float) {
		var was = scrub.peek(), t = was?.screen == name ? was.t : 0.0;
		scrubLength = length;
		scrub({screen: name, t: t, playing: on});
		log("scrub-play", {screen: name, playing: on});
		if (!on) return;
		var last = -1.0;
		Clock.add(now -> {
			var c = scrub.peek();
			if (c == null || c.screen != name || !c.playing) return false;
			if (last >= 0 && scrubLength > 0) scrub({screen: name, t: (c.t + now - last) % scrubLength, playing: true});
			last = now;
			return true;
		});
	}

	// whether the focused frame's contents are entered (a double click): a click selects a node in it
	public final entered = signal(false);

	// (the last click on the stage: a second one soon and near is a double click)
	var lastClick = {t: -1.0, x: 0.0, y: 0.0};

	// Escape: out of Play, out of a frame's contents (the frame selected), else nothing selected
	public function escape() {
		if (talk.reading.peek() != null) talk.reading(null) else if (playing.peek() != null) stopPlay() else if (commandOpen.peek()) commandOpen(false) else if (entered.peek() && focused.peek() != null) focus(focused.peek(), false) else if (focused.peek() != null) focus(null, false);
	}

	// a page's screens (a design file's, a story flow's) fitted, none zoomed into
	public function showPage(page:String) {
		if (mode.peek() == "stories") setMode("design");
		focused(null);
		selection(null);
		var b = layout.bounds(page), i = insets();
		var v = Camera.fit(b.x, b.y, b.w, b.h, stageWidth, stageHeight, 28, i.right, i.bottom, i.top + Theme.TITLES, i.left);
		camera.fly(v.x, v.y, v.k);
		log("page", {page: page});
	}

	// compact: a sheet opened from the bar (at half; the prompt at peek), or
	// closed when it is the one open; the frame in focus fitted above it
	public function openSheet(name:String) {
		if (sheetNow == name) setSheet(null, detentNow) else {
			setSheet(name, name == "ask" ? "peek" : "half");
			if (name == "code") refreshCode();
		}
		fitView(true);
		log("sheet", {sheet: sheetNow, detent: detentNow});
	}

	// the sheet's height at a detent (stage points)
	public function sheetHeight(d:String):Float {
		stageSize();
		var h = Math.max(200, stageHeight - Theme.BAR);
		return switch d {
			case "peek": Theme.SHEET_PEEK;
			case "full": h - 8;
			case _: Math.round(h * 0.5);
		}
	}

	// the handle tapped: up a detent (full: back to half)
	public function raiseSheet() {
		setSheet(sheetNow, switch detentNow {
			case "peek": "half";
			case "half": "full";
			case _: "half";
		});
		fitView(true);
	}

	// the handle let go at height h, moving at vy (points a second, down
	// positive): flung down from peek or dragged below it, away; else the
	// nearest detent (a fling one further)
	public function settleSheet(h:Float, vy:Float) {
		var peek = sheetHeight("peek");
		if (h < peek * 0.6 || (vy > 900 && h < sheetHeight("half"))) {
			if (vy > 900 && h >= peek * 0.6 && detentNow != "peek") setSheet(sheetNow, "peek") else setSheet(null, detentNow);
		} else {
			var best = "half", d = 1e9;
			for (x in ["peek", "half", "full"]) {
				var target = h - (vy > 900 ? 120 : vy < -900 ? -120 : 0);
				var e = Math.abs(sheetHeight(x) - target);
				if (e < d) {
					d = e;
					best = x;
				}
			}
			setSheet(sheetNow, best);
		}
		fitView(true);
		log("sheet", {sheet: sheetNow, detent: detentNow});
	}

	// (compact: a choice made in a sheet lowers it to peek, the canvas in view)
	public function lower()
		if (compactNow && sheetNow != null && sheetNow != "code") setSheet(sheetNow, "peek");


	// (the mode just set: a signal's write lands at the end of the event, and a fit after it in the same event needs it)
	var modeNow = "design";

	public function setMode(m:String) {
		modeNow = m;
		mode(m);
		fitView(true, m);
		if (m == "code") {
			refreshCode();
			editor.view.focus();
		}
	}

	// (new frames came (the watched shell's): every frame fitted, in the next
	// frame, at most 1:1, until the user first moves the camera: the studio's
	// framing, never the agent moving it. After a question is answered, the
	// project's real frames alone, not the design frames (the options) that
	// asked it, once there are some)
	var framing = false;
	var real = false;

	function framesCame()
		if (!classic) framing = true;

	// a question answered (Questions): the real frames from now on, framed now
	public function answered() {
		real = true;
		framesCame();
	}

	// (seconds without a patch before a failed build shows on the canvas)
	static inline var SETTLED = 1.5;

	// (the framing's least scale: a still stays readable; the frames past the view's
	// end go to the edge's tab)
	static inline var LEAST = 0.5;

	// (the box framed last ("": none yet): framed again when it changes, the
	// frames moved or gone (a sketch file removed, the rows below it moving up))
	var fitted = "";

	function box():String {
		var b = frameBox(layout.screens(), n -> project?.screen(n)?.source.match(Design(_)) ?? false, real);
		return b == null ? "" : '${b.x} ${b.y} ${b.w} ${b.h}';
	}

	function frameAll() {
		var b = frameBox(layout.screens(), n -> project?.screen(n)?.source.match(Design(_)) ?? false, real), i = insets();
		fitted = box();
		if (b == null) return;
		var v = Camera.fit(b.x, b.y, b.w, b.h, stageWidth, stageHeight, 28, i.right, i.bottom, i.top + Theme.TITLES, i.left, 1, LEAST);
		camera.fly(v.x, v.y, v.k);
		log("framed", {k: v.k});
	}

	// the box the framing fits: every frame's, or (real) the program's frames' when there are some, not a design's
	public static function frameBox(rs:Array<{name:String, x:Float, y:Float, w:Float, h:Float}>, design:String->Bool, real:Bool):Null<{x:Float, y:Float, w:Float, h:Float}> {
		var live = rs.filter(r -> !design(r.name));
		if (real && live.length > 0) rs = live;
		if (rs.length == 0) return null;
		var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
		for (r in rs) {
			x0 = Math.min(x0, r.x);
			y0 = Math.min(y0, r.y);
			x1 = Math.max(x1, r.x + r.w);
			y1 = Math.max(y1, r.y + r.h);
		}
		return {x: x0, y: y0, w: x1 - x0, h: y1 - y0};
	}

	// the view for what is in focus (fly: on the spring)
	public function fitView(fly:Bool, ?m:String)
		fitTo(focused.peek(), fly, m);

	function fitTo(name:Null<String>, fly:Bool, ?m:String) {
		if (stageWidth <= 0) return;
		var code = (m ?? modeNow) == "code";
		var small = compactNow, i = insets(m);
		var v = if (name == null) {
			var b = layout.bounds();
			Camera.fit(b.x, b.y, b.w, b.h, stageWidth, stageHeight, 28, i.right, i.bottom, i.top + Theme.TITLES, i.left);
		} else {
			var r = layout.rect(name);
			if (r == null) return;
			if (small) Camera.fit(r.x, r.y, r.w, r.h, stageWidth, stageHeight, 14, 0, i.bottom, i.top + 20)
			else Camera.fit(r.x, r.y, r.w, r.h, stageWidth, stageHeight, 22, i.right, i.bottom, i.top + 14, i.left);
		}
		if (fly) camera.fly(v.x, v.y, v.k) else camera.jump(v.x, v.y, v.k);
	}

	// (compact as just measured: its signal's write lands at the frame's end, a fit after it in the same frame needs it)
	var compactNow = false;

	// the stage's points the panels cover (the canvas is under them): the
	// sidebar and the code at the left, the inspector at the right, the
	// toolbar above, the prompt bar below; compact, none
	public function insets(?m:String):{left:Float, right:Float, top:Float, bottom:Float} {
		// (the watched canvas: beside the chat, below the header, nothing over it)
		if (!classic) return {left: 0, right: 0, top: 0, bottom: 0};
		if (compactNow) {
			// (the sheet open, at most at half: at full the canvas is under it anyway)
			var d = detentNow, open = sheetNow == null ? 0 : sheetHeight(d == "full" ? "half" : d);
			return {left: 0, right: 0, top: Theme.TOPBAR, bottom: Theme.BAR + open};
		}
		var code = (m ?? modeNow) == "code";
		return {
			left: Theme.SIDEBAR + (code ? Shell.codeWidth(this) : 0),
			right: code ? 0 : Theme.INSPECTOR,
			top: Theme.HEADER,
			bottom: code ? 0 : Theme.ASK_SPACE
		};
	}

	// every frame fitted (shift-1)
	public function fitAll() {
		if (focused.peek() != null) focus(null) else fitTo(null, true);
	}

	// the selection fitted (shift-2): the frame in focus, else every frame
	public function fitSelection()
		fitTo(focused.peek(), true);

	// whether a screen shows the layers' panel when zoomed into (a design's frame)
	public function layers(name:Null<String>):Bool {
		var s = name == null ? null : project?.screen(name);
		return s != null && s.source.match(Design(_));
	}

	// a click on the stage at (px, py), at any zoom: a frame selected; in
	// the frame entered, a node; a double click enters the frame there and
	// selects its node; on nothing, nothing selected (add: shift held, a
	// design's node added to the selection or taken from it)
	public function clickStage(px:Float, py:Float, add = false) {
		var now = #if helder.headless helder.async.Time.now #else haxe.Timer.stamp() #end;
		var double = now - lastClick.t < 0.4 && Math.abs(px - lastClick.x) < 6 && Math.abs(py - lastClick.y) < 6;
		lastClick = {t: double ? -1.0 : now, x: px, y: py};
		var wx = camera.wx(px), wy = camera.wy(py);
		var hit = layout.at(wx, wy);
		if (hit == null) {
			if (!add) focus(null, false);
			return;
		}
		if (double) {
			if (focused.peek() != hit.name) focus(hit.name, false);
			entered(true);
			log("entered", {screen: hit.name});
		} else if (!entered.peek() || focused.peek() != hit.name) {
			if (focused.peek() != hit.name || entered.peek()) focus(hit.name, false);
			return;
		}
		pick(hit.name, wx - hit.x, wy - hit.y, add);
	}

	// the watched canvas' click at (px, py): a frame the prompt's focus (its
	// ring; the camera stays), nothing on none; a double click plays it
	public function aimAt(px:Float, py:Float) {
		var now = #if helder.headless helder.async.Time.now #else haxe.Timer.stamp() #end;
		var double = now - lastClick.t < 0.4 && Math.abs(px - lastClick.x) < 6 && Math.abs(py - lastClick.y) < 6;
		lastClick = {t: double ? -1.0 : now, x: px, y: py};
		var hit = layout.at(camera.wx(px), camera.wy(py));
		focused(hit?.name);
		log("aimed", {screen: hit?.name});
		if (hit?.name != scrub.peek()?.screen) scrub(null);
		if (double && hit != null && !project.screen(hit.name).source.match(Design(_))) playWindow(hit.name);
	}

	// the chat column put away or back (Cmd+B): the frames kept where they are on screen
	public function toggleChat() {
		var open = !talk.open.peek();
		talk.open(open);
		camera.panBy(open ? -Theme.CHAT : Theme.CHAT, 0);
		log("chat", {open: open});
	}

	// the camera flown to a frame (a chip's, a marker's: the user's click)
	public function flyTo(name:String) {
		if (layout.rect(name) == null) return;
		camera.taken = true;
		fitTo(name, true);
		log("flown", {screen: name});
	}

	// a design file's group by its title, where it is in the world (the
	// groups' side sets it: <Group title> in design files; null: not known)
	public var groupAt:Null<(file:String, title:String) -> Null<{x:Float, y:Float, w:Float, h:Float}>> = null;

	// a chip's place flown to: a screen, a design file's frame (Project's screens by file and name), a group (groupAt; else the file's frames)
	public function flyToPlace(p:Replies.Spot) {
		if (project == null) return;
		function file(f:String):String
			return haxe.io.Path.normalize(haxe.io.Path.isAbsolute(f) ? f : project.dir + "/" + f);
		switch p {
			case Screen(name): flyTo(name);
			case Frame(f, name):
				var s = Lambda.find(project.screens, s -> s.file == file(f) && (s.name == name || s.label == name));
				if (s != null) flyTo(s.name);
			case Group(f, title):
				var r = groupAt == null ? null : groupAt(file(f), title);
				if (r == null) {
					var rs = [for (s in project.screens) if (s.file == file(f)) layout.rect(s.name)].filter(r -> r != null);
					if (rs.length == 0) return;
					var x0 = Lambda.fold(rs, (r, m) -> Math.min(m, r.x), 1e9), y0 = Lambda.fold(rs, (r, m) -> Math.min(m, r.y), 1e9);
					var x1 = Lambda.fold(rs, (r, m) -> Math.max(m, r.x + r.w), -1e9), y1 = Lambda.fold(rs, (r, m) -> Math.max(m, r.y + r.h), -1e9);
					r = {x: x0, y: y0, w: x1 - x0, h: y1 - y0};
				}
				var v = Camera.fit(r.x, r.y, r.w, r.h, stageWidth, stageHeight, 28, 0, 0, Theme.TITLES, 0);
				camera.fly(v.x, v.y, v.k);
				log("flown", {group: title});
		}
	}

	// Play: what is selected, else the app from its start (Play's notes);
	// the watched shell's: in a window of its own (playWindow)
	public function play() {
		if (project == null) return;
		// (the watched shell's Play app: the app from its start, in a window of its own, whatever is selected)
		if (!classic) {
			playWindow(null);
			return;
		}
		var t = target.peek();
		if (t != "studio") {
			launch(t);
			return;
		}
		var f = focused.peek(), info = f == null ? null : project.screen(f);
		var app = Lambda.find(project.screens, s -> s.source.match(App));
		var p:Play.Playing = switch info?.source {
			case Story(_): {kind: "story", screen: info.name, note: "a story, live: its input the program's"};
			case Design(_): {kind: "design", screen: info.name, note: "a prototype: the arrow keys go through the page's frames (flows are not made yet)"};
			case _ if (app != null):
				{kind: "app", screen: app.name, note: info != null && info.place != null ? "routes are not made yet: the app from its start" : "the app from its start"};
			case _:
				var first = Lambda.find(project.screens, s -> s.source.match(Design(_)));
				if (first != null) {kind: "design", screen: first.name, note: "no app to run: the first frame as a prototype"}
				else {kind: "story", screen: project.screens[0]?.name, note: "this project's program is its stories': the app runs in a window (the target beside Play)"};
		}
		if (compactNow) setSheet(null, detentNow);
		playing(p);
		playControls([]);
		if (p.kind == "story" && p.screen != null) {
			var s = previews?.screen(p.screen);
			if (s != null) previews.request(s, "Story.controls", {}, r -> playControls(r?.controls ?? []));
		}
		log("play", {kind: p.kind, screen: p.screen, target: t});
	}

	public function stopPlay() {
		#if !(hxmc.target == "wasm32-wasi")
		var tp = targetProcess;
		targetProcess = null;
		if (tp != null) tp.kill();
		#end
		// (for checks: the played screen's texts as it was left)
		var p = playing.peek(), s = p?.screen == null || p.kind == "design" ? null : previews?.screen(p.screen);
		if (s != null) previews.request(s, "Ui.getTree", {}, r -> {
			var texts = [];
			function walk(n:Dynamic) {
				if (n == null) return;
				if (n.text != null) texts.push(Std.string(n.text));
				for (c in (n.children ?? [] : Array<Dynamic>))
					walk(c);
			}
			walk(Studio.rootOf(r));
			log("stopped", {screen: p.screen, texts: texts});
		}) else if (p != null) log("stopped", {screen: p.screen});
		if (sheetNow == "controls") setSheet(null, detentNow);
		playScreen = null;
		playing(null);
	}

	// the prototype's next or previous frame (the page's, in order)
	public function playStep(by:Int) {
		var p = playing.peek();
		var info = p?.screen == null ? null : project.screen(p.screen);
		if (info == null) return;
		var page = [for (s in project.screens) if (s.flow == info.flow && s.source.match(Design(_))) s];
		var k = Lambda.findIndex(page, s -> s.name == info.name) + by;
		if (k < 0 || k >= page.length) return;
		playing({kind: p.kind, screen: page[k].name, note: p.note});
		log("play-step", {screen: page[k].name});
	}

	// a story's control set in the program, its list read again
	public function setControl(name:String, value:Dynamic) {
		var p = playing.peek(), s = p?.screen == null ? null : previews?.screen(p.screen);
		if (s == null) return;
		previews.request(s, "Story.set", {name: name, value: value}, _ -> previews.request(s, "Story.controls", {}, r -> playControls(r?.controls ?? [])));
		log("control", {name: name, value: value});
	}

	// a screen played in a window of its own, live, its input its own, at its
	// size (the watched shell's Play, a double click on its frame): `helder
	// dev` on it, rebuilt in place as the project changes (its state kept),
	// so the user plays on while the agent works; closing it is closing the
	// window, a second Play the first one's window replaced. A story of a
	// TypeScript project: a main of it (.helder-play.tsx, beside the
	// project's files so that helder dev watches them: play(story)); the app
	// (name null: the header's Play with no frame aimed at, the app's frame),
	// or a Haxe project's story: the app. Headless (a check's run): told, not opened.
	public function playWindow(name:Null<String>, fresh = false) {
		#if !(hxmc.target == "wasm32-wasi")
		var info = name == null ? null : project.screen(name);
		if (name != null && info == null) return;
		var scenario = info != null && project.typescript && Project.isScenario(info.file);
		var plan = fresh ? "open" : playPlan(targetProcess != null && launched.peek()?.state != "failed", windowScenarios, name, scenario,
			launched.peek()?.state == "starting" || editedAt > windowBuiltAt);
		log("play-plan", {screen: name, plan: plan});
		switch plan {
			case "switch":
				playIn(name);
				return;
			case "queue":
				queued = name;
				launched({state: launched.peek()?.state ?? "running", note: 'Playing: ${info.label} once its build lands', at: null, playing: null});
				// (no build lands: played all the same)
				Async.launch(_ -> {
					Async.delay(15);
					if (queued == name) playIn(name);
				});
				return;
			case "rewrite":
				// (its main written again with every scenario: helder dev builds and reloads it, the window at this one)
				playEntry(info);
				queued = null;
				arriving = info.label;
				launched({state: "running", note: 'Playing: ${info.label} once its build lands', at: null, playing: null});
				return;
			case _:
		}
		windowScenarios = null;
		var entry = info == null ? project.dir : playEntry(info);
		var label = info?.label ?? project.name;
		var cli = Sys.getEnv("HELDER_CLI") ?? "helder";
		var args = ["dev", entry];
		log("play-window", {screen: name, args: args});
		// (headless: told, not opened, unless a check names a program standing in for helder)
		#if helder.headless
		var stand = Sys.getEnv("HELDER_STUDIO_PLAY_CLI") ?? "";
		if (stand == "") {
			message('would play $label in a window: helder ${args.join(" ")}');
			return;
		}
		cli = stand;
		#end
		var scenarios = windowScenarios;
		stopWindow();
		windowScenarios = scenarios;
		var l = new Launch(project.dir, 'building $label');
		window = l;
		playingLabel = label;
		told();
		// (a check's script waits for it to run or fail)
		hold(() -> l.state != "starting", "Play's window", 300);
		// (its stdin a pipe never written: the studio gone, however it ended, helder dev and its window with it, Parent)
		var p = try new Process(cli, args, {cwd: project.dir, env: Parent.env()}) catch (e:Dynamic) {
			launched({state: "failed", note: 'helder dev did not start: $e', at: null, playing: null});
			null;
		}
		if (p == null) return;
		targetProcess = p;
		var seen = 0;
		function lines(src:Stream.Source)
			Async.launch(_ -> {
				var r = new Reader(src), line;
				try while ((line = r.readLine()) != null) {
					if (targetProcess != p) continue;
					var changed = l.read(line);
					// (a build landed in the window: what waited for it played now)
					if (l.builds > seen) {
						seen = l.builds;
						windowBuiltAt = haxe.Timer.stamp();
						if (arriving != null) {
							playingLabel = arriving;
							arriving = null;
						}
						if (queued != null) playIn(queued);
					}
					if (changed) told();
				} catch (_:haxe.Exception) {}
			});
		lines(p.stdout);
		lines(p.stderr);
		Async.launch(_ -> {
			var code = p.wait();
			if (targetProcess != p) return;
			targetProcess = null;
			l.exited(code);
			told();
			// (closed: Play again; what failed stays shown until the next Play)
			if (l.state == "ended") launched(null);
		});
		#end
	}

	// what Play from here does with a frame (name): "open" a window of its
	// own (none open, the open one plays no scenarios, or name is none);
	// "switch" the open one to it (Scenario.play: nothing built); "queue"
	// the switch after the build on its way (the window's build older than
	// the edits); "rewrite" its main (a scenario it was not started with:
	// helder dev builds and reloads it, at that one)
	public static function playPlan(open:Bool, scenarios:Null<Array<String>>, name:Null<String>, scenario:Bool, stale:Bool):String {
		if (!open || scenarios == null || name == null || !scenario) return "open";
		if (!scenarios.contains(name)) return "rewrite";
		return stale ? "queue" : "switch";
	}

	#if !(hxmc.target == "wasm32-wasi")
	// (Play's window's helder dev, read: its devtools, the builds that landed)
	var window:Null<Launch> = null;
	#end
	// (the switch waiting for a build; the scenario a rewritten main opens at; the one shown)
	var queued:Null<String> = null;
	var arriving:Null<String> = null;
	var playingLabel:Null<String> = null;
	// (the last edit of the project's files, the last build that landed in Play's window: haxe.Timer.stamp)
	var editedAt = 0.0;
	var windowBuiltAt = 0.0;

	// (Play's window's state told: Launch's, what it plays once it runs)
	function told() {
		#if !(hxmc.target == "wasm32-wasi")
		var l = window;
		if (l == null) return;
		launched({state: l.state, note: l.note, at: l.at, playing: l.state == "running" ? playingLabel : null});
		log("launch", {state: l.state, note: l.note, at: l.at, playing: l.state == "running" ? playingLabel : null});
		#end
	}

	// another scenario played in Play's window (Scenario.play through its
	// helder dev's devtools: its store let go, its boot, the root again);
	// refused, or no devtools: a window of its own instead
	function playIn(name:String) {
		#if !(hxmc.target == "wasm32-wasi")
		queued = null;
		var url = window?.devtools, label = project?.screen(name)?.label ?? name;
		if (url == null) {
			playWindow(name, true);
			return;
		}
		Async.launch(_ -> {
			var r = DevCall.call(url, "Scenario.play", {name: name});
			if (r == null || r.error != null) {
				log("play-switch", {screen: name, error: r?.error?.message ?? "no answer"});
				playWindow(name, true);
				return;
			}
			playingLabel = label;
			told();
			log("play-switch", {screen: name, playing: r.result?.playing});
		});
		#end
	}

	// the studio's Share: the project on helder.run for a week (helder share:
	// its web build and the frames file its Board draws, every scenario a
	// place Play starts at), the link said once it is there
	public function share() {
		#if !(hxmc.target == "wasm32-wasi")
		if (project == null || shared.peek()?.state == "sharing") return;
		// (live: Share again stops it, the link kept as it is)
		var p = sharing;
		if (p != null) {
			sharing = null;
			try p.kill() catch (_:Dynamic) {}
			var was = shared.peek();
			shared({state: "shared", note: "not live", url: was?.url});
			log("shared", {state: "shared", note: "stopped"});
			return;
		}
		previews?.saveStills();
		var frames = '${project.out}/${Stills.FILE}';
		var cli = Sys.getEnv("HELDER_CLI") ?? "helder";
		var args = ["share", project.dir, "--live"].concat(Files.exists(frames) ? ["--frames", frames] : []);
		log("share", {args: args});
		#if helder.headless
		var stand = Sys.getEnv("HELDER_STUDIO_PLAY_CLI") ?? "";
		if (stand == "") {
			message('would share ${project.name}: helder ${args.join(" ")}');
			return;
		}
		cli = stand;
		#end
		function told(state:String, note:String, ?url:String) {
			shared({state: state, note: note, url: url});
			log("shared", {state: state, note: note, url: url});
		}
		told("sharing", "building");
		var p = try new Process(cli, args, {cwd: project.dir, env: Parent.env()}) catch (e:Dynamic) {
			told("failed", 'helder share did not start: $e');
			null;
		}
		if (p == null) return;
		sharing = p;
		// (a headless run goes on while its share is live: a check acts on the project meanwhile, at most an hour)
		hold(() -> sharing != p, "Share live", 3600);
		// (helder share --live's lines: building, the link, then live: each patch, version and scene it sends)
		var url:Null<String> = null, state = "sharing";
		function lines(src:Stream.Source)
			Async.launch(_ -> {
				var r = new Reader(src), line;
				try while ((line = r.readLine()) != null) {
					var text = new EReg(String.fromCharCode(27) + "\\[[0-9;]*m", "g").replace(line, "").trim();
					var status = ~/^([a-z ]+?)\s+(\S.*)$/;
					if (sharing != p || !status.match(text)) continue;
					switch status.matched(1) {
						case "shared":
							url = status.matched(2).split(" ")[0];
							told(state, state == "live" ? text : "", url);
						case "live" if (url != null && !status.matched(2).startsWith("the room")):
							state = "live";
							told("live", status.matched(2), url);
						case "error" if (url == null):
							told(state = "failed", status.matched(2));
						case "error" | "patched" | "frames" | "build": told(state, text, url);
						case "release" | "board" | "uploaded" | "built" | "screenshots": told(state, text, url);
						case _:
					}
				} catch (_:haxe.Exception) {}
			});
		lines(p.stdout);
		lines(p.stderr);
		Async.launch(_ -> {
			var code = p.wait();
			if (sharing != p) return;
			sharing = null;
			if (url != null) told("shared", 'not live (helder share ended: exit code $code)', url) else if (state != "failed") told("failed",
				'helder share ended (exit code $code)');
		});
		#end
	}

	// helder share --live while it runs (Share stops it; the studio's end too)
	var sharing:Null<Process> = null;

	// what Share is doing (null: nothing yet): "sharing" (its last line), "live" (the link, kept
	// live: its last patch, version or scenes), "shared" (the link, not live), "failed" (why)
	public final shared:Signal<Null<{state:String, note:String, url:Null<String>}>> = signal(null);

	// what Play's window is doing (null: none): "starting", "running" or
	// "failed" (Launch's), the line shown beside Play, where it failed, what it plays
	public final launched:Signal<Null<{state:String, note:String, at:Null<String>, ?playing:Null<String>}>> = signal(null);

	// Play's window closed (its helder dev ended), or what failed let go
	public function stopWindow() {
		#if !(hxmc.target == "wasm32-wasi")
		var was = targetProcess;
		targetProcess = null;
		if (was != null) was.kill();
		#end
		queued = arriving = null;
		windowScenarios = null;
		if (launched.peek() != null) launched(null);
	}

	// what helder dev runs to play a screen (Play from here): a TypeScript
	// story's main (written: PLAY, play(story) from helder/story); a
	// scenario's, the app in a window of its own at that scenario's moment
	// (helder.scenario.Player: PLAY imports BOOT, hold(), then every
	// scenario of the project and the app's main, then play(them, its name);
	// another played in the same window, Scenario.play); else the project (its app)
	public function playEntry(info:ScreenInfo):String {
		var main = project.typescript ? project.mainFile() : null;
		switch info.source {
			case Story(binding) if (project.typescript && binding != null):
				var rel = module(info.file), entry = project.dir + "/" + PLAY;
				if (!Project.isScenario(info.file)) {
					Files.save(entry, '// helder studio\'s Play from here: ${info.name} in a window of its own (written by the studio, run by helder dev)\n'
						+ 'import { play } from "helder/story";\nimport { $binding } from "$rel";\n\nplay($binding);\n');
					return entry;
				}
				if (main == null) return project.dir;
				var all = scenarios();
				#if !(hxmc.target == "wasm32-wasi")
				entry = helder.cli.Scenes.entry(project.dir, PLAY, main, all, info.name, "helder studio's Play from here");
				#end
				windowScenarios = [for (s in all) s.name];
				return entry;
			case _:
				return project.dir;
		}
	}

	// (the project's scenarios bound to a name, TypeScript's: Play from here's window plays each)
	function scenarios():Array<{name:String, binding:String, file:String}> {
		var out = [];
		for (s in project.screens)
			switch s.source {
				case Story(b) if (b != null && Project.isScenario(s.file)): out.push({name: s.name, binding: b, file: s.file});
				case _:
			}
		return out;
	}

	// (the scenarios Play's window was started with: another of them played in it, nothing built; null: it plays no scenario)
	var windowScenarios:Null<Array<String>> = null;

	// (a file of the project as a module beside PLAY: "./app.scenario")
	function module(file:String):String {
		var rel = file.substr(project.dir.length + 1);
		return "./" + rel.substr(0, rel.lastIndexOf("."));
	}

	// (a scenario's boot, PLAY's first import)
	public static inline var BOOT = ".helder-play-boot.tsx";

	// (the main a story's window plays, at the project's root: helder dev watches the folder of its entry)
	public static inline var PLAY = ".helder-play.tsx";

	// another target: `helder dev` on the project (a window; Android's
	// phone; the web, its page opened in the system's browser), its output
	// the player's line
	function launch(t:String) {
		#if !(hxmc.target == "wasm32-wasi")
		stopPlay();
		var cli = Sys.getEnv("HELDER_CLI") ?? "helder";
		var args = ["dev", project.dir].concat(t == "phone" ? ["--target", "android"] : t == "browser" ? ["--target", "web"] : []);
		var p = try new Process(cli, args, {cwd: project.dir, env: Parent.env()}) catch (e:Dynamic) {
			playLog('helder dev did not start: $e');
			null;
		}
		playing({kind: "target", screen: null, note: ""});
		playLog("helder " + args.join(" "));
		log("play", {kind: "target", target: t, args: args});
		if (p == null) return;
		targetProcess = p;
		var opened = false;
		function lines(src:Stream.Source)
			Async.launch(_ -> {
				var r = new Reader(src), line;
				try while ((line = r.readLine()) != null) {
					var text = new EReg(String.fromCharCode(27) + "\\[[0-9;]*m", "g").replace(line, "").trim();
					if (text == "") continue;
					playLog(text);
					var url = ~/https?:\/\/[^\s]+/;
					if (t == "browser" && !opened && url.match(text)) {
						opened = true;
						var open = Sys.systemName() == "Mac" ? "open" : Sys.systemName() == "Windows" ? "explorer" : "xdg-open";
						try new Process(open, [url.matched(0)]) catch (_:Dynamic) {}
					}
				} catch (_:haxe.Exception) {}
			});
		lines(p.stdout);
		lines(p.stderr);
		Async.launch(_ -> {
			var code = p.wait();
			if (targetProcess == p) playLog('helder dev ended (exit code $code)');
		});
		#end
	}

	// a story's or the app's place on the canvas: its <Frame story> or
	// <Frame app> (made at x, y when it has none: in the design file that
	// places frames already, else canvas.helder at the project's root, made
	// then), as one gesture's edit
	public function place(info:ScreenInfo, x:Float, y:Float):Null<{file:String, start:Int}> {
		if (info.place != null) return info.place;
		var file = null;
		for (s in project.screens)
			if (s.place != null) file = s.place.file;
		if (file == null) {
			file = project.dir + "/canvas.helder";
			if (!Files.exists(file)) Files.save(file, "<Design>\n</Design>\n");
			framesChanged(file, project.design(file, Files.read(file)));
		}
		var doc = docs.get(file).doc, root = doc.elementAt(doc.text.indexOf("<"));
		if (root == null) return null;
		var what = info.source.match(App) ? "app" : 'story="${project.refOf(file, info)}"';
		var tx = try Edits.insertChild(doc, root, root.children().length, '<Frame $what canvas:at="${Math.round(x)} ${Math.round(y)}"/>') catch (e:Dynamic) {
			message('the canvas: $e');
			return null;
		}
		edit(file, tx, "frame placed", "canvas", 'drag:$gesture');
		log("placed", {screen: info.name, file: tree?.relative(file) ?? file});
		return project.screen(info.name)?.place;
	}

	// the node at (x, y) of a screen (its points) selected: the program's
	// tree's boxes, the node's source (a design's frame: its own nodes')
	public function pick(name:String, x:Float, y:Float, add = false) {
		var info = project?.screen(name);
		if (info != null && info.source.match(Design(_))) {
			var hit = designs.pick(name, x, y);
			if (hit != null) selectDesign(info, hit.node, hit.at, add) else if (!add) {
				selection(null);
				others([]);
			}
			return;
		}
		var s = previews?.screen(name);
		if (s == null) return;
		var answered = false;
		var asked = previews.request(s, "Ui.getTree", {}, r -> {
			answered = true;
			var root:Dynamic = Studio.rootOf(r);
			if (root == null) return;
			var n = hitNode(root, x, y);
			if (n == null) {
				selection(null);
				return;
			}
			select(s, n);
		});
		if (asked) hold(() -> answered, "the tree");
	}

	// the deepest node holding (x, y) that the project's markup made
	function hitNode(n:Dynamic, x:Float, y:Float):Null<Dynamic> {
		if (n == null || x < n.x || y < n.y || x >= n.x + n.width || y >= n.y + n.height || n.style?.display == "none") return null;
		var kids:Array<Dynamic> = n.children ?? [];
		var i = kids.length;
		while (--i >= 0) {
			var h = hitNode(kids[i], x, y);
			if (h != null) return h;
		}
		return n.source != null && ours(n.source.file) ? n : null;
	}

	// a file of the project (not helder's own)
	public function ours(file:String):Bool {
		if (project == null || file == null) return false;
		var f = project.real(file);
		return f.startsWith(project.dir + "/") && !f.substr(project.dir.length).contains("/bin/");
	}

	function select(s:Screen, n:Dynamic) {
		var file = project.real(n.source.file);
		var f = docs.get(file);
		var start = f.doc.fromByte(Std.int(n.source.offsets[0]));
		var el = f.doc.elementAt(start);
		var sel:Selection = {
			screen: s.info.name,
			file: file,
			start: start,
			tag: el?.name ?? n.tag ?? "node",
			nodeTag: n.tag,
			id: n.id,
			x: n.x,
			y: n.y,
			width: n.width,
			height: n.height,
			opacity: n.style?.opacity ?? 1,
		};
		selection(sel);
		gesture++;
		docs.close();
		log("selected", {screen: sel.screen, file: file, start: start, tag: sel.tag, rect: [sel.x, sel.y, sel.width, sel.height]});
		refreshCode();
	}

	// a node of a design's frame selected: its element at its markup's
	// offset (add: with what is selected, or taken from it when it is)
	public function selectDesign(info:ScreenInfo, n:Null<Node>, at:Int, add = false) {
		var cur = selection.peek(), more = [];
		if (add && cur != null && cur.screen == info.name) {
			var rest = [for (o in others.peek()) if (o.start != at) o];
			if (cur.start == at || rest.length < others.peek().length) {
				// (a selected one clicked again: no longer; the last of the rest the selection)
				if (cur.start != at) rest.push(cur);
				var last = rest.pop();
				others(rest);
				selection(last);
				log("selected", {screen: info.name, others: rest.length, tag: last?.tag, start: last?.start});
				refreshCode();
				return;
			}
			more = rest.concat([cur]);
		}
		others(more);
		var el = docs.get(info.file).doc.elementAt(at);
		// (a node not drawn yet: its box when its frame is, Designs.follow)
		var b = n == null ? {x: 0.0, y: 0.0, width: 0.0, height: 0.0} : designs.box(info.name, n);
		var sel:Selection = {
			screen: info.name,
			file: info.file,
			start: at,
			tag: el?.name ?? n?.tag ?? "node",
			nodeTag: n?.tag,
			id: 0,
			x: b.x,
			y: b.y,
			width: b.width,
			height: b.height,
			opacity: n == null ? 1 : n.style.opacity,
		};
		selection(sel);
		gesture++;
		docs.close();
		log("selected", {screen: sel.screen, file: sel.file, start: at, tag: sel.tag, rect: [sel.x, sel.y, sel.width, sel.height], others: more.length});
		refreshCode();
	}

	// the selection's box again from the program's tree (after a frame: a
	// layout moved it): the nodes its source makes now (Ui.nodesAt), their boxes
	var lastMiss:Null<String> = null;

	function refreshSelection() {
		var sel = selection.peek();
		var s = sel == null ? null : previews?.screen(sel.screen);
		if (sel == null || s == null) return;
		if (refreshing) {
			refreshAgain = true;
			return;
		}
		refreshing = true;
		var f = docs.get(sel.file);
		var lc = f.doc.lineCol(sel.start);
		var line = lc.line, col = f.doc.toByte(sel.start) - f.doc.toByte(f.doc.lineStart(sel.start)) + 1;
		var file = sel.file;
		var done = false;
		function finish() {
			done = true;
			refreshing = false;
			if (refreshAgain) {
				refreshAgain = false;
				refreshSelection();
			}
		}
		var ok = previews.request(s, "Ui.getTree", {}, t -> {
			var root:Dynamic = Studio.rootOf(t);
			var asked = previews.request(s, "Ui.nodesAt", {file: realToBuilt(file), line: line, col: col}, r -> {
				var nodes:Array<Dynamic> = r.result?.nodes ?? [];
				var found = nodes.length == 0 ? null : findId(root, nodes[0].id);
				var cur = selection.peek();
				// (said once a reason: why the selected node's box is not read again)
				var miss = found != null ? null : '${sel.screen}, $line:$col: '
					+ (t?.error != null ? 'the tree: ${t.error.message}' : root == null ? "no tree" : r?.error != null ? r.error.message : '${nodes.length} node(s) there');
				if (miss != null && miss != lastMiss) Sys.println('studio: the selected node not found again ($miss)');
				lastMiss = miss;
				if (found != null && cur != null && cur.file == file) {
					var next:Selection = Reflect.copy(cur);
					next.id = found.id;
					next.x = found.x;
					next.y = found.y;
					next.width = found.width;
					next.height = found.height;
					next.opacity = found.style?.opacity ?? 1;
					selection(next);
					log("selection", {screen: next.screen, tag: found.tag, rect: [next.x, next.y, next.width, next.height], opacity: next.opacity, text: found.text,
						color: found.style?.color, background: found.style?.background});
				}
				finish();
			});
			if (!asked) finish();
		});
		if (!ok) finish() else hold(() -> done, "the selection's node");
	}

	// (a project's file as the build knows it: a linked story file's link)
	function realToBuilt(file:String):String {
		if (project != null) for (l => r in project.links) if (r == file) return l;
		return file;
	}

	// a Ui.getTree response's first window's root (null: none)
	public static function rootOf(r:Dynamic):Null<Dynamic> {
		var uis:Array<Dynamic> = r?.result?.uis;
		return uis == null || uis.length == 0 ? null : uis[0].root;
	}

	static function findId(n:Dynamic, id:Int):Null<Dynamic> {
		if (n == null) return null;
		if (n.id == id) return n;
		for (c in (n.children : Array<Dynamic>) ?? []) {
			var f = findId(c, id);
			if (f != null) return f;
		}
		return null;
	}

	// a screen's new frame: the first ones counted, a patch's measured, the selection followed
	function framed(s:Screen) {
		marks.framed(s.info.name);
		var ui = Main.window?.ui;
		if (ui != null) ui.requestFrame();
		if (s.version == 1) log("screen-shown", {screen: s.info.name});
		rise();
		if (previews.looping == s.info.name) loopShown(s.info.name, "live");
		allShown();
		var m = measuring;
		if (m != null && m.screen == s && s.version > m.version) {
			measuring = null;
			var ms = Math.round((haxe.Timer.stamp() - m.t0) * 10000) / 10;
			var shown = frames - m.frame, programMs = s.patchedMs, version = s.version;
			Sys.println('studio: ${m.label} shown in $ms ms, $shown studio frame(s)' + (programMs >= 0 ? ', the program\'s own $programMs ms' : ''));
			// (its colour from the frame's pixels: here when they were copied, else read back from the host,
			// Previews.pixels: a shared texture's, macOS's and Windows')
			var img = s.image.peek();
			if (img == null || img.hasPixels) log("patch-shown", {ms: ms, frames: shown, programMs: programMs, label: m.label, color: selectionColor(s, img), version: version});
			else {
				var done = false;
				hold(() -> done, "the patched frame's pixels", 15);
				Async.launch(_ -> {
					var read = #if (hxmc.target == "wasm32-wasi") null #else previews.pixels(s) #end;
					log("patch-shown", {ms: ms, frames: shown, programMs: programMs, label: m.label, color: selectionColor(s, read), version: version});
					done = true;
				});
			}
		}
		if (focused.peek() == s.info.name && selection.peek() != null) refreshSelection();
	}

	// a frame the pointer came onto
	public function hover(name:String) {
		hoverAt = haxe.Timer.stamp();
		hovered(name);
	}

	// a hovered loop's first frame shown (from: "file", or "live": the program's), its time since the hover
	public function loopShown(name:String, from:String) {
		if (hoverAt < 0 || hovered.peek() != name) return;
		var ms = Math.round((haxe.Timer.stamp() - hoverAt) * 10000) / 10;
		hoverAt = -1;
		Sys.println('studio: $name\'s loop shown $ms ms after the hover ($from)');
		log("loop-shown", {screen: name, ms: ms, from: from});
	}

	// (every screen showing a frame, the program's or its still from the frames file: told once)
	function allShown() {
		var pr = previews;
		if (shownAll || pr == null || openedAt <= 0 || !pr.allShown()) return;
		shownAll = true;
		var ms = Math.round((haxe.Timer.stamp() - openedAt) * 1000);
		var host = pr.sinceHost(), stills = [for (s in pr.screens) if (s.version == 0 && s.still.peek() != null && !s.stale.peek()) s].length;
		Sys.println('studio: all ${pr.screens.length} screens shown $ms ms after opening ${project.name}' + (host >= 0 ? ', $host ms after the screens\' program started' : '')
			+ (stills > 0 ? ', $stills from the frames file' : ''));
		log("all-shown", {ms: ms, screens: pr.screens.length, hostMs: host, sharing: pr.sharing, stills: stills});
		if (!camera.taken) fitView(false);
	}

	// the strongest colour in the selection's box of the screen's last frame (a check's: what it shows)
	function selectionColor(s:Screen, img:Null<helder.image.Image>):Null<String> {
		var sel = selection.peek();
		if (sel == null || img == null || sel.screen != s.info.name || !img.hasPixels) return null;
		// (the selection in points, the frame at its pixels a point: the focused one's at the canvas' scale)
		var k = img.width / Math.max(1, s.width());
		var px = img.pixels, best = -1.0, out:Null<String> = null;
		var x0 = Std.int(Math.max(0, sel.x * k)), y0 = Std.int(Math.max(0, sel.y * k));
		var x1 = Std.int(Math.min(img.width, (sel.x + sel.width) * k)), y1 = Std.int(Math.min(img.height, (sel.y + sel.height) * k));
		for (y in y0...y1)
			for (x in x0...x1) {
				var i = (y * img.width + x) * 4;
				var r = px.get(i), g = px.get(i + 1), b = px.get(i + 2);
				var sat = Math.max(r, Math.max(g, b)) - Math.min(r, Math.min(g, b));
				if (sat > best) {
					best = sat;
					out = "#" + StringTools.hex(r, 2).toLowerCase() + StringTools.hex(g, 2).toLowerCase() + StringTools.hex(b, 2).toLowerCase();
				}
			}
		return out;
	}

	// ---- edits

	// the selected element (null: none, or its source no longer reads as one)
	public function element():Null<helder.syntax.Document.Element> {
		var sel = selection();
		docs.version();
		if (sel == null) return null;
		return docs.get(sel.file).doc.elementAt(sel.start);
	}

	// an attribute of the selected element set (Studio.attribute's form)
	public function setAttribute(name:String, raw:String, ?group:String) {
		var sel = selection.peek();
		if (sel == null) return;
		var f = docs.get(sel.file), doc = f.doc;
		var el = doc.elementAt(sel.start);
		if (el == null) return;
		var tx = try attribute(doc, el, name, raw) catch (e:Dynamic) {
			message('$name: $e');
			return;
		}
		edit(sel.file, tx, '$name $raw', "inspector", group ?? 'attr:$name:$gesture');
	}

	// an element's attribute set (raw: as a field has it; its form kept: a
	// number in braces, a string in quotes; "" removes it), against the doc's text
	public static function attribute(doc:helder.syntax.Document, el:helder.syntax.Document.Element, name:String, raw:String):Transaction {
		if (raw.trim() == "") return Edits.removeAttribute(doc, el, name);
		var a = el.attr(name);
		var v = raw.trim();
		var numeric = ~/^-?[0-9]+(\.[0-9]+)?$/.match(v);
		var braced = a != null && a.value != null && doc.text.charAt(a.value.start) == "{";
		var lit = a == null ? null : a.literal();
		return if (a != null && a.value != null && a.value.kind == Str && !numeric && !v.contains('"') && !v.contains("\\"))
			// (a string's value: its text alone, its quotes kept)
			new Transaction([new Change(a.value.start + 1, a.value.end - 1, v)], null, doc.text)
		else if (lit != null && numeric && lit.kind == Num)
			// (a number in braces: the number alone)
			new Transaction([new Change(lit.start, lit.end, v)], null, doc.text)
		else Edits.setAttribute(doc, el, name, numeric && (a == null || braced) ? ACode(v) : AString(v));
	}

	// the selected element's text (its one run of text) set
	public function setText(text:String, ?group:String) {
		var sel = selection.peek();
		if (sel == null) return;
		var f = docs.get(sel.file), doc = f.doc;
		var el = doc.elementAt(sel.start);
		if (el == null) return;
		var run = textRun(el);
		if (run == null || text.trim() == "" || text.contains("<") || text.contains("{")) return;
		edit(sel.file, new Transaction([new helder.syntax.Transaction.Change(run.start, run.end, text)], null, doc.text), 'text $text', "inspector", group ?? 'text:$gesture');
	}

	// an element's one run of text (null: none, or more than text in it)
	public static function textRun(el:helder.syntax.Document.Element):Null<{start:Int, end:Int, text:String}> {
		var kids = el.content();
		if (kids.length != 1) return null;
		var k = kids[0];
		var t = el.doc.text.substring(k.start, k.end);
		if (t.trim() == "" || t.contains("{") || t.contains("<")) return null;
		var lead = t.length - t.ltrim().length, trail = t.length - t.rtrim().length;
		return {start: k.start + lead, end: k.end - trail, text: t.trim()};
	}

	// an edit of a file by the studio (origin: inspector, agent, canvas), recorded
	// (by: the agent who made it, Presence's name; null: the user)
	public function edit(file:String, tx:Transaction, label:String, origin:String, ?group:String, ?by:String)
		docs.apply(file, tx, label, origin, group, by);

	// the next edit its own history entry (a field left, a scrub ended)
	public function endGesture() {
		gesture++;
		docs.close();
	}

	public function undo() {
		var e = docs.undo();
		message(e == null ? "nothing to undo" : 'undid ${entryLabel(e)}');
		gesture++;
	}

	public function redo() {
		var e = docs.redo();
		message(e == null ? "nothing to redo" : 'redid ${entryLabel(e)}');
		gesture++;
	}

	// a history entry as the undo button says it: "Claude: app.tsx", the user's its label alone
	public static function entryLabel(e:Docs.Entry):String
		return e.by == null ? e.label : '${e.by}: ${e.label}';

	// a file's text changed (Docs): the selection moved with it, the code view
	// told, then the program: a live literal patched, else a build
	function changed(file:String, tx:Transaction, origin:String) {
		editedAt = haxe.Timer.stamp();
		var sel = selection.peek();
		if (sel != null && sel.file == file) {
			var next:Selection = Reflect.copy(sel);
			next.start = tx.map(sel.start, 1);
			selection(next);
		}
		if (others.peek().length > 0 && others.peek()[0].file == file) others([for (o in others.peek()) {var n:Selection = Reflect.copy(o); n.start = tx.map(o.start, 1); n;}]);
		if (file.endsWith(".helder") && project != null) {
			framesChanged(file, project.design(file, docs.get(file).text));
			rise();
		}
		if (origin != "code" && codeFile.peek() == file) {
			applyingToEditor = true;
			var changes = [for (c in tx.changes) new helder.syntax.Transaction.Change(c.start, c.end, c.text)];
			editor.model.apply(changes, null, helder.ui.code.CodeModel.EDIT, false);
			editor.view.changed();
			applyingToEditor = false;
			decorate();
		}
		log("edited", {file: file, origin: origin, changes: [for (c in tx.changes) {start: c.start, end: c.end, text: c.text}]});
		if (origin == "agent") agentEdited(file, tx);
		if (origin == "code") saveLater(file) else commit(file);
		if (origin == "agent") tidy();
	}

	// (an empty folder's starter: its files gone once the agent's project no
	// longer needs them, each an entry of the history, after an edit of the
	// agent's (not an undo's); the agent never deletes them)
	function tidy() {
		var p = project;
		if (!starter || p == null) return;
		var own = Lambda.exists(p.screens, i -> i.source.match(Story(_)) && !starterOwn(i.name));
		for (f in Starter.unused(p.dir, docs, p.sources(), own, starterOwn("App/Start"))) {
			log("starter-removed", {file: f});
			remove(f);
		}
	}

	// an agent's edit (an MCP agent's project.patch, an ACP agent's write: its
	// history entry by its name): the agent there (Presence: its lines, its
	// frame when it named none), what it made marked (Marks)
	function agentEdited(file:String, tx:Transaction) {
		touch();
		patchedAt = haxe.Timer.stamp();
		var by = docs.nextUndo()?.by;
		if (by == null || project == null) return;
		var p = presence.named(by) ?? presence.arrive("acp:" + by, by);
		var doc = docs.get(file).doc, rel = file.startsWith(project.dir + "/") ? file.substr(project.dir.length + 1) : file;
		presence.patched(p.id, rel, [for (c in tx.inverse.changes) {file: rel, from: doc.lineCol(c.start).line, to: doc.lineCol(c.end).line}]);
		var cs = tx.inverse.changes, from = cs.length == 0 ? 0 : cs[0].start, to = cs.length == 0 ? 0 : cs[cs.length - 1].end;
		presence.working(p.id, null, presence.peer(p.id).screen == null || file.endsWith(".helder") ? screenFor(file, from, to) : null);
		marks.edited(presence.peer(p.id), file, tx);
	}

	// (the frame an edit shows on, its changed range the text's after it: a
	// design's frame holding the range, else the first it made (a frame, a
	// group's), else the one holding its start; a program's: the one in
	// focus, else the first in view)
	function screenFor(file:String, from:Int, to:Int):Null<String> {
		if (file.endsWith(".helder")) {
			var doc = docs.get(file).doc, holding:Null<String> = null, made:Null<String> = null, near:Null<String> = null;
			for (s in project.screens) {
				var el = s.file == file && s.start != null ? doc.elementAt(s.start) : null;
				if (el == null) continue;
				if (el.start <= from && el.end >= to) holding = s.name;
				else if (el.start >= from && el.end <= to) made ??= s.name;
				else if (el.start <= from && el.end >= from) near ??= s.name;
			}
			return holding ?? made ?? near;
		}
		var shown = layout.inView();
		return focused.peek() ?? Lambda.find(project.live(), s -> shown.contains(s.name))?.name;
	}

	// a design file's frames read again (null: as they were): what was
	// focused or selected in a renamed one follows it, a frame gone is left
	function framesChanged(file:String, renamed:Null<Array<{from:String, to:String}>>) {
		if (renamed == null) return;
		var f = focused.peek(), sel = selection.peek();
		for (r in renamed) {
			if (f == r.from) focused(f = r.to);
			if (sel != null && sel.screen == r.from) {
				var next:Selection = Reflect.copy(sel);
				next.screen = r.to;
				selection(sel = next);
			}
		}
		if (renamed.length > 0) others([]);
		if (f != null && project.screen(f) == null) focus(null);
		log("frames", {file: file, frames: [for (s in project.screens) if (s.file == file) s.name], renamed: renamed});
		if (marks.saw([for (s in project.screens) s.name])) framesCame();
	}

	// (natively) the project's files on disk watched, a second apart (every
	// source, not only its design and story files: an agent's or an editor's
	// edit of app.tsx): one changed there (another editor's save, an
	// agent's, git) read into the studio as an edit of the file's (in the
	// history, undone like any other), one added or deleted its frames or
	// stories shown or gone (a story's: built; after a failed build, any
	// source's: an import of it may resolve now)
	@:coroutine function watch() {
		#if !(hxmc.target == "wasm32-wasi")
		scanDisk();
		while (true) {
			Async.delay(1);
			tree?.scan();
			scanDisk();
		}
		#end
	}

	// (each file's stamp, its mtime and size, as last seen: none yet, the first pass takes them)
	var stamps:Null<Map<String, String>> = null;

	// a pass over the project's files on disk (the first: each read as it is,
	// a change on disk is one from it)
	public function scanDisk() {
		#if !(hxmc.target == "wasm32-wasi")
		if (project == null) return;
		function stamp(f:String):String
			return try {
				var s = sys.FileSystem.stat(f);
				s.mtime.getTime() + " " + s.size;
			} catch (_:Dynamic) "";
		var now = project.sources();
		for (f in Project.found(project.dir))
			if (!now.contains(f)) now.push(f);
		var known = stamps;
		if (known == null) {
			stamps = [for (f in now) f => stamp(f)];
			for (f in now)
				try docs.get(f) catch (_:Dynamic) {}
			return;
		}
		for (f in now) {
			var t = stamp(f);
			if (known.get(f) == t) continue;
			var seen = known.exists(f);
			known.set(f, t);
			var text = try Files.read(f) catch (_:Dynamic) continue;
			if (!seen) {
				diskAdded(f, text);
				continue;
			}
			var d = docs.get(f);
			if (d.text != text) docs.apply(f, new Transaction([Docs.difference(d.text, text)], null, d.text), "the file changed on disk", "disk");
		}
		for (f in [for (k in known.keys()) k])
			if (!now.contains(f)) {
				known.remove(f);
				diskAdded(f, null);
			}
		#end
	}

	// (a file added on disk, or gone: text null)
	function diskAdded(f:String, text:Null<String>) {
		if (f.endsWith(".helder")) framesChanged(f, project.design(f, text));
		// (a story where there was no program: the project read again, its program started)
		else if (previews == null) {
			if (Project.isStory(f)) revive();
		} else if (storiesChanged(f, text)) {
			message(text == null ? "a story file removed: building" : "a story file added: building");
			log("building", {file: f, why: text == null ? "a story file removed" : "a story file added"});
			rebuild(f, true);
		} else if (previews.failed) {
			log("building", {file: f, why: text == null ? "a source removed after a failed build" : "a source added after a failed build"});
			rebuild(f, true);
		}
	}

	// the program told of a file's text: its live literals patched now (the
	// next frame shows them), then the file saved; else saved and built
	public function commit(file:String) {
		var pr = previews;
		var f = docs.get(file);
		// (a design file: its frames drawn again from the text, nothing built)
		if (file.endsWith(".helder")) {
			f.save();
			message("drawn again, nothing built");
			log("redrawn", {file: file});
			return;
		}
		if (pr == null) {
			f.save();
			marks.landed(false);
			if (shaping(file)) revive();
			return;
		}
		// (a file that may change what the project is: its main, a package's)
		if (shaping(file) && !Project.isStory(file) && revive()) return;
		// (a story file's stories changed: the host's screens with them, every source built)
		if (Project.isStory(file) && storiesChanged(file, f.text)) {
			pr.write(file, f.text);
			message("the stories changed: building");
			log("building", {file: file, why: "the stories changed"});
			rebuild(file, true);
			return;
		}
		// (after a failed build: built again, every source, whatever changed: the failure shown until one is good)
		if (pr.failed) {
			pr.write(file, f.text);
			message("building again after a failed build");
			log("building", {file: file, why: "the last build failed"});
			rebuild(file, true);
			return;
		}
		var why = null;
		var patches = pr.literalPatches(file, f.text, w -> why = w);
		if (patches != null && patches.length > 0 && pr.patch(patches)) {
			startMeasure('${patches.length} literal(s) patched');
			pr.write(file, f.text);
			pr.took(patches);
			message('patched ${patches.length} live literal(s), nothing built');
			log("patched", {file: file, patches: patches});
			marks.landed(false);
			return;
		}
		pr.write(file, f.text);
		if (patches != null && patches.length == 0) {
			marks.landed(false);
			return;
		}
		message('building: ${why ?? "not a live literal"}');
		log("building", {file: file, why: why});
		rebuild(file);
	}

	function rebuild(file:String, all = false) {
		var pr = previews;
		var done = false;
		Async.launch(task -> {
			var ok = pr.rebuild(task, all ? project.sources() : [file]);
			marks.landed(true, ok);
			done = true;
			message(ok ? 'rebuilt in ${pr.buildMs.peek()} ms' : "the build failed: the last good build keeps running");
			log("built", {ok: ok, ms: pr.buildMs.peek(), diagnostics: pr.latest.length});
			if (codeFile.peek() != null) editor.setDiagnostics(pr.latest, codeFile.peek());
		});
		hold(() -> done && !pr.busy(), "a build and the screens' reload");
	}

	// a build's end: its failure shown (its first error), cleared by a good one
	function built(ok:Bool, why:String, diagnostics:Array<helder.compiler.service.Diagnostic>) {
		if (ok) {
			if (failure.peek() != null) log("failure", {cleared: true});
			failure(null);
			return;
		}
		var first = Lambda.find(diagnostics, d -> d.severity == "error") ?? (diagnostics.length > 0 ? diagnostics[0] : null);
		var at = first?.file == null ? null : (project != null && first.file.startsWith(project.dir + "/") ? first.file.substr(project.dir.length + 1) : haxe.io.Path.withoutDirectory(first.file)) + ":" + first.line;
		var f:Failure = {
			message: first == null ? why : first.message,
			at: at,
			diagnostics: diagnostics
		};
		failure(f);
		log("failure", {message: f.message, at: at, errors: diagnostics.filter(d -> d.severity == "error").length});
	}

	// a story file's text now (null: gone), its stories read again: when the
	// screens changed, the previews follow them (a build's new host draws
	// them), what was focused or selected on one gone let go; whether they changed
	function storiesChanged(file:String, text:Null<String>):Bool {
		if (project == null || !project.story(file, text)) return false;
		previews?.follow();
		var f = focused.peek(), sel = selection.peek();
		if (sel != null && project.screen(sel.screen) == null) {
			selection(null);
			others([]);
		}
		if (f != null && project.screen(f) == null) focus(null, false);
		log("stories", {file: file, screens: [for (s in project.live()) s.name]});
		if (marks.saw([for (s in project.screens) s.name])) framesCame();
		return true;
	}

	// (a patch's frame to come, measured)
	function startMeasure(label:String) {
		var name = focused.peek() ?? selection.peek()?.screen;
		var s = name == null ? previews.screens[0] : previews.screen(name);
		if (s == null) return;
		var v = s.version;
		measuring = {t0: haxe.Timer.stamp(), frame: frames, screen: s, version: v, label: label};
		hold(() -> s.version > v, "a patch's frame", 10);
	}

	// ---- the code view

	// the code view on the selection's file (else the focused screen's story, else the first source), its element revealed and marked
	public function refreshCode() {
		var sel = selection.peek();
		var file = sel?.file;
		if (file == null && project != null) {
			var name = focused.peek();
			var s = name == null ? null : Lambda.find(project.screens, x -> x.name == name);
			file = s?.file;
			if (file == null || file == "") file = codeFile.peek() ?? project.sources()[0];
		}
		if (file == null) return;
		load(file);
		decorate();
	}

	// a file in the code view (the command field's, the sidebar's, a link's), nothing selected; at a line (1-based)
	public function openCode(file:String, ?line:Int) {
		selection(null);
		others([]);
		focused(null);
		shown(file);
		load(file);
		setMode("code");
		if (line == null) return;
		var text = docs.get(file).text, at = 0;
		for (_ in 1...line) {
			var n = text.indexOf("\n", at);
			if (n < 0) break;
			at = n + 1;
		}
		editor.revealRange(at, at, true);
	}

	// a link of the agent's reply: a web or mail address in the browser, a
	// file of the project in the code view (at its line: "#L12", ":12")
	public function follow(href:String) {
		var h = href.trim();
		if (~/^(https?|mailto):/i.match(h)) {
			helder.os.Links.show(h, false);
			return;
		}
		var place = Replies.place(h);
		if (place != null) {
			flyToPlace(place);
			return;
		}
		var l = project == null ? null : FileLink.parse(h, project.dir);
		if (l == null || !Files.exists(l.path) || Files.isDirectory(l.path)) {
			message('$href: not a file of the project');
			return;
		}
		if (classic) openCode(l.path, l.line) else {
			talk.reading({file: l.path, line: l.line});
			log("reading", {file: l.path, line: l.line});
		}
	}

	// a file of the tree opened in its view: a design or story file's page
	// on the canvas, code in the code view, an image or a font in its
	// viewer (FileView), anything else as text when it reads as text
	public function openFile(e:FileTree.FileEntry) {
		lower();
		switch e.kind {
			case Dir:
				tree.toggle(e);
			case Design | Story:
				var frames = tree.frames(e.path);
				shown(e.path);
				if (mode.peek() != "design") setMode("design");
				if (frames.length > 0) showPage(frames[0].flow) else openCode(e.path);
			case Image | Font | Model | Audio | Other:
				selection(null);
				focused(null);
				shown(e.path);
				setMode("file");
			case Code:
				openCode(e.path);
		}
		log("opened", {file: tree.relative(e.path), kind: (e.kind : String)});
	}

	// an image dragged from the tree onto a design's frame at the stage's
	// (px, py): an <image src> of its path from the design file, its size
	// the image's (fitted into the frame's width), the frame's last child
	public function dropImage(path:String, px:Float, py:Float) {
		var hit = layout.at(camera.wx(px), camera.wy(py));
		var info = hit == null ? null : project.screen(hit.name);
		if (info == null || !info.source.match(Design(_)) || info.start == null) {
			message("an image goes on a design's frame");
			return;
		}
		var doc = docs.get(info.file).doc, frame = doc.elementAt(info.start);
		if (frame == null) return;
		var src = FileTree.relativeTo(haxe.io.Path.directory(info.file), path);
		var size = try designs.imageSize(path) catch (_:Dynamic) {w: 120.0, h: 120.0};
		var w = Math.min(size.w, Math.max(40, (info.width > 0 ? info.width : 390) - 48));
		var h = Math.round(size.h * w / Math.max(1, size.w));
		var markup = '<image src="$src" width={${Math.round(w)}} height={$h}/>';
		var tx = try helder.syntax.Edits.insertChild(doc, frame, frame.children().length, markup) catch (e:Dynamic) {
			message('the image: $e');
			return;
		}
		edit(info.file, tx, "image inserted", "canvas");
		endGesture();
		log("image-inserted", {screen: info.name, src: src});
	}

	// files dropped from the system on the window at (x, y): copied into the
	// folder of the tree's row there (a file's row: its folder), else the project's
	public function dropFiles(files:Array<String>, x:Float, y:Float) {
		if (project == null || tree == null) return;
		var dir = project.dir, ui = Main.window?.ui;
		var n = ui == null ? null : ui.root.hitTest(x, y);
		while (n != null) {
			var p = tree.rowPath(n.tag);
			if (p != null) {
				dir = Files.isDirectory(p) ? p : haxe.io.Path.directory(p);
				break;
			}
			n = n.parent;
		}
		var copied = [];
		#if !(hxmc.target == "wasm32-wasi")
		for (f in files) {
			if (sys.FileSystem.isDirectory(f)) continue;
			var to = dir + "/" + haxe.io.Path.withoutDirectory(f);
			try {
				sys.io.File.copy(f, to);
				copied.push(tree.relative(to));
			} catch (e:Dynamic) message('$f: $e');
		}
		#end
		tree.scan();
		log("dropped", {files: copied});
	}


	function load(file:String) {
		if (codeFile.peek() != file) {
			codeFile(file);
			applyingToEditor = true;
			editor.path = file;
			editor.text = docs.get(file).text;
			applyingToEditor = false;
			if (previews != null) editor.setDiagnostics(previews.latest, file);
		}
	}

	// the selected element marked and revealed, the caret after its tag's name
	function decorate() {
		editor.clearDecorations();
		var sel = selection.peek();
		if (sel == null || sel.file != codeFile.peek()) return;
		var doc = docs.get(sel.file).doc;
		var el = doc.elementAt(sel.start);
		if (el == null) return;
		editor.addDecoration(el.start, el.end, Theme.c("sel-soft"), Theme.c("sel"));
		editor.revealRange(el.start, el.end);
		var name = el.open.first(helder.syntax.Cst.Kind.TagName);
		var at = name == null ? el.start + 1 : name.end;
		editor.setSelection(at, at);
	}

	function codeChanged(changes:Array<helder.syntax.Transaction.Change>) {
		if (applyingToEditor) return;
		var file = codeFile.peek();
		if (file == null) return;
		var before = docs.get(file).text;
		var tx = new Transaction(changes, null, before);
		docs.apply(file, tx, "typing", "code", 'code:$gesture');
	}

	// (typing: saved and told after a pause)
	function saveLater(file:String) {
		var g = ++saveGeneration;
		var saved = false;
		Async.launch(_ -> {
			Async.delay(0.4);
			if (g != saveGeneration) {
				saved = true;
				return;
			}
			gesture++;
			docs.close();
			commitCode(file);
			saved = true;
		});
		hold(() -> saved, "the code's save");
	}

	function commitCode(file:String) {
		var pr = previews;
		var f = docs.get(file);
		if (pr == null || file.endsWith(".helder")) {
			f.save();
			return;
		}
		if (Project.isStory(file) && storiesChanged(file, f.text)) {
			pr.write(file, f.text);
			log("building", {file: file, why: "the stories changed"});
			rebuild(file, true);
			return;
		}
		pr.write(file, f.text);
		var done = false;
		Async.launch(task -> {
			var r = pr.saved(task, file);
			done = true;
			message(switch r {
				case "patched": "patched live literals, nothing built";
				case "built": 'rebuilt in ${pr.buildMs.peek()} ms';
				case "failed": "the build failed: the last good build keeps running";
				case _: r;
			});
			log(r == "patched" ? "patched" : "built", {file: file, result: r, ms: pr.buildMs.peek()});
			editor.setDiagnostics(pr.latest, file);
		});
		hold(() -> done && !pr.busy(), "a save's build or patch");
	}

	// ---- the prompt bar

	// what the prompt is about: the whole app, or the screen in focus
	// (label: the prompt's placeholder; scope: its chip, the screen and the node selected)
	public function context():{label:String, scope:String, screen:Null<String>, selection:Null<Selection>} {
		var name = focused();
		var s = name == null || project == null ? null : Lambda.find(project.screens, x -> x.name == name);
		var sel = selection();
		var scope = s == null ? "Whole app" : sel != null && sel.screen == name ? '${s.label} · ${sel.tag}' : s.label;
		return {label: s == null ? "Ask about the whole app…" : 'Ask about ${s.label}…', scope: scope, screen: name, selection: sel};
	}

	// a prompt to the agent (the studio's own /tree, /snap, /check, /read to
	// its tools), its events folded into the turn; one turn at a time
	// (said: the chat's bubble; a turn of the inbox's notes has none)
	public function ask(prompt:String, said = true) {
		var p = prompt.trim();
		if (p == "") return;
		// (after a question's "Something else…": its answer, the user's words)
		var q = questions.answeringNow();
		if (q != null && said) {
			questions.reply(q, p);
			log("replied-to", {question: q, text: p});
			return;
		}
		// (typed while a turn runs: a direction, the inbox's, not a prompt)
		if (Turns.running(turnNow)) {
			inbox.direct(p, talk.list().length - 1, turnNow.text.length);
			log("directed", {text: p});
			return;
		}
		var a = LocalAgent.tool(p) != null ? local : agent;
		if (talk.list().length == 0 && Watch.blank(this)) {
			unveiled = true;
			if (project != null) marks.rise([for (s in project.screens) s.name]);
		}
		setTurn(Turns.start(said ? p : ""), true);
		talk.trouble(null);
		// (timed: the prompt to the frame showing it, to the agent's first text)
		var sent = haxe.Timer.stamp(), spoke = false;
		acking = sent;
		log("asked", {prompt: p, starting: booting.peek()});
		var answered = false, heard = -1.0, asked:Null<String> = null;
		function end(e:Agent.AgentEvent) {
			settle();
			if (asked != null) questions.close(asked);
			var t = Turns.add(turnNow ?? Turns.start(p), e);
			var ps = a == local ? [] : problems(), cs = a == local ? [] : previews?.crashed() ?? [];
			if (ps.length > 0) t = Turns.broken(t, ps[0]) else if (cs.length > 0) t = Turns.crashed(t, '${cs[0].why} (${cs[0].screen})');
			setTurn(t);
			answered = true;
			// (the ACP agent's turn over: it is done, its marks fade; its calls to
			// the MCP server are its too, a peer of its name)
			for (x in presence.list())
				if (x.working && (x.id.startsWith("acp:") || x.name == agentName())) presence.done(x.id, t.error ?? null);
			log("replied", {prompt: p, reply: t.error ?? t.text, end: t.end, build: t.build});
			// (the notes its tools did not carry: the next prompt, at once)
			var notes = a == local ? [] : inbox.take();
			if (notes.length > 0) ask(Inbox.text(notes), false);
		}
		a.ask(p, {screen: focused.peek() == unasked.peek() ? null : focused.peek(), selection: classic ? selection.peek() : null, problems: problems(), crashes: crashes()}, e -> switch e {
			case Done(_) | Failed(_):
				// (done as the agent is: a build still running shows on its frames, not as a held turn)
				end(e);
			case _:
				heard = haxe.Timer.stamp();
				if (!spoke && e.match(Text(_))) {
					spoke = true;
					log("first-text", {ms: Math.round((heard - sent) * 1000)});
				}
				setTurn(Turns.add(turnNow ?? Turns.start(p), e));
				switch e {
					case Tool(id, title, _, status):
						log("agent-tool", {id: id, title: title, status: status});
									// (a permission ask: the chat's card, as studio.ask's; an answer in
					// the user's words cancels it and goes to the agent as a note)
					case Ask(question, options, _) if (!classic):
						if (asked != null) questions.close(asked);
						asked = questions.permission(asker(), question, options, (picked, text) -> {
							var i = picked.length == 0 ? -1 : Std.parseInt(picked[0]) ?? -1;
							answer(i);
							if (i < 0 && text != null) inbox.direct(text, talk.list().length - 1, turnNow?.text.length ?? 0);
						}).id;
					case _:
				}
		});
		// (a question for the user lets the script go on: its answer is the
		// script's; so does an agent quiet for half a second after it spoke:
		// the script steers it, stops it)
		hold(() -> answered || turnNow?.ask != null || (heard > 0 && haxe.Timer.stamp() - heard > 0.5), "the agent's reply", a == local ? 30 : 300);
	}

	// the last build's errors, "file:line: message" (none: it did not fail)
	// the screens that threw when the studio ran them ("screen: file:line: why"; none after a failed build)
	public function crashes():Array<String> {
		var pr = previews;
		return pr == null || pr.failed ? [] : [for (c in pr.crashed()) '${c.screen}: ${c.why}'];
	}

	public function problems():Array<String> {
		var pr = previews;
		if (pr == null || !pr.failed) return [];
		var dir = project.dir + "/";
		var out = [
			for (d in pr.diagnostics.peek())
				if (d.severity == "error" || d.severity == "ERROR")
					(d.file == null ? "" : (d.file.startsWith(dir) ? d.file.substr(dir.length) : d.file) + ':${d.line}: ') + d.message
		];
		return out.length > 0 ? out : ["the build failed"];
	}

	// the turn stopped (the prompt bar's Stop)
	public function stopTurn()
		if (Turns.running(turnNow)) agent.cancel();

	// the last turn gone from the prompt bar
	public function clearTurn()
		if (!Turns.running(turnNow)) setTurn(null);

	// the agent's question answered: an option's index
	public function answer(i:Int) {
		var t = turnNow;
		if (t == null || t.ask == null) return;
		var a = t.ask.answer;
		setTurn(Turns.answered(t));
		a(i);
	}

	@:coroutine public function stop() {
		agent.close();
		stopPlay();
		stopWindow();
		if (previews != null) previews.stop();
		#if !(hxmc.target == "wasm32-wasi")
		if (events != null) events.close();
		var p = sharing;
		sharing = null;
		if (p != null) try p.kill() catch (_:Dynamic) {}
		#end
	}
}

// a build's failure: why (its first error's message), where (file:line of the project's), every diagnostic
typedef Failure = {
	message:String,
	at:Null<String>,
	diagnostics:Array<helder.compiler.service.Diagnostic>,
}

typedef Selection = {
	screen:String,
	// the element's file and its start (an offset of the file's text now)
	file:String,
	start:Int,
	// its element's name, the node's tag
	tag:String,
	nodeTag:Null<String>,
	// the node in the screen's tree, its box (the screen's points) and opacity
	id:Int,
	x:Float,
	y:Float,
	width:Float,
	height:Float,
	opacity:Float,
}

// Where each screen is in the canvas' world: a flow a row, the rows one under another
class Layout {
	final studio:Studio;

	public function new(studio)
		this.studio = studio;

	// every frame where it was put (canvas:at: a design's frame's own, a
	// story's or the app's <Frame story> or <Frame app>), the world's points;
	// a frame without one right of the one before it in its page, else laid
	// out below the design frames, a row a page
	public function screens():Array<{name:String, flow:String, x:Float, y:Float, w:Float, h:Float}> {
		var out:Array<{name:String, flow:String, x:Float, y:Float, w:Float, h:Float}> = [];
		// (the project read again: its screens the new one's)
		studio.revived();
		var p = studio.project, pr = studio.previews;
		if (p == null) return out;
		function size(i:Project.ScreenInfo):{w:Float, h:Float} {
			var s = pr?.screen(i.name);
			return s == null ? {w: i.width + 0.0, h: i.height + 0.0} : {w: s.width() + 0.0, h: s.height() + 0.0};
		}
		function shown(i:Project.ScreenInfo):Bool
			return (i.source.match(Design(_)) || pr?.screen(i.name) != null) && !studio.starterOwn(i.name);
		// (below the design frames: a story or the app placed by hand leaves the others where they were)
		var y = 0.0;
		for (f in p.flows())
			for (i in f.screens)
				if (i.at != null && i.source.match(Design(_))) y = Math.max(y, i.at.y + size(i).h + Theme.FLOW_GAP);
		// (each auto-laid frame's row, for the rows' gap once the widest is known)
		var rows:Array<Int> = [], n = 0, widest = 0.0;
		for (f in p.flows()) {
			var x = 0.0, tall = 0.0, row = false, last:Null<{x:Float, y:Float, w:Float, group:Null<String>, row:Int}> = null;
			for (i in f.screens) {
				if (!shown(i)) continue;
				var z = size(i), at = i.at, r = -1;
				// (a group's frames side by side, closer than frames apart)
				if (at == null && last != null) {
					at = {x: last.x + last.w + (i.group != null && i.group == last.group ? Theme.GROUP_GAP : Theme.SCREEN_GAP), y: last.y};
					r = last.row;
				}
				if (at == null) {
					at = {x: x, y: y};
					x += z.w + Theme.SCREEN_GAP;
					tall = Math.max(tall, z.h);
					row = true;
					r = n;
				}
				if (r >= 0) widest = Math.max(widest, at.x + z.w);
				out.push({name: i.name, flow: f.name, x: at.x, y: at.y, w: z.w, h: z.h});
				rows.push(r);
				last = {x: at.x, y: at.y, w: z.w, group: i.group, row: r};
			}
			if (row) {
				y += tall + Theme.FLOW_GAP;
				n++;
			}
		}
		// (rows of wide frames shown small: apart enough for a title and captions at the zoom that fits them)
		rowsGap = gapOf(widest);
		var more = rowsGap - Theme.FLOW_GAP;
		if (more > 0) for (k in 0...out.length)
			if (rows[k] > 0) out[k] = {name: out[k].name, flow: out[k].flow, x: out[k].x, y: out[k].y + rows[k] * more, w: out[k].w, h: out[k].h};
		return out;
	}

	// the rows' gap, the world's points: wider rows, shown smaller, further apart
	public function gap():Float {
		screens();
		return rowsGap;
	}

	var rowsGap = Theme.FLOW_GAP + 0.0;

	static function gapOf(widest:Float):Float
		return Math.max(Theme.FLOW_GAP, widest / 12);

	public function rect(name:String):Null<{name:String, flow:String, x:Float, y:Float, w:Float, h:Float}>
		return Lambda.find(screens(), s -> s.name == name);

	// a design file's groups where they are: each its title and its frames' box (the world's points)
	public function groups():Array<{file:String, title:String, x:Float, y:Float, w:Float, h:Float}> {
		var p = studio.project, out:Array<{file:String, title:String, x:Float, y:Float, w:Float, h:Float}> = [];
		if (p == null) return out;
		var all = screens();
		for (i in p.screens) {
			if (i.group == null) continue;
			var r = Lambda.find(all, s -> s.name == i.name);
			if (r == null) continue;
			var g = Lambda.find(out, g -> g.file == i.file && g.title == i.group);
			if (g == null) out.push({file: i.file, title: i.group, x: r.x, y: r.y, w: r.w, h: r.h}) else {
				var x1 = Math.max(g.x + g.w, r.x + r.w), y1 = Math.max(g.y + g.h, r.y + r.h);
				g.x = Math.min(g.x, r.x);
				g.y = Math.min(g.y, r.y);
				g.w = x1 - g.x;
				g.h = y1 - g.y;
			}
		}
		return out;
	}

	// the screens the stage shows now (any part of them)
	public function inView():Array<String> {
		var cam = studio.camera, w = studio.stageWidth, h = studio.stageHeight;
		return [
			for (r in screens())
				if (cam.sx(r.x + r.w) > 0 && cam.sy(r.y + r.h) > 0 && cam.sx(r.x) < w && cam.sy(r.y) < h) r.name
		];
	}

	public function at(wx:Float, wy:Float):Null<{name:String, flow:String, x:Float, y:Float, w:Float, h:Float}>
		return Lambda.find(screens(), s -> wx >= s.x && wy >= s.y && wx < s.x + s.w && wy < s.y + s.h);

	// (page: its screens' alone)
	public function bounds(?page:String):{x:Float, y:Float, w:Float, h:Float} {
		var l = [for (s in screens()) if (page == null || s.flow == page) s];
		if (l.length == 0) return {x: 0, y: 0, w: 480, h: 560};
		var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
		for (s in l) {
			x0 = Math.min(x0, s.x);
			y0 = Math.min(y0, s.y);
			x1 = Math.max(x1, s.x + s.w);
			y1 = Math.max(y1, s.y + s.h);
		}
		return {x: x0, y: y0, w: x1 - x0, h: y1 - y0};
	}
}
