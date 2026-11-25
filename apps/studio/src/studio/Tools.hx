package studio;

import haxe.Json;
import helder.async.*;
import helder.syntax.Transaction;
import studio.Previews;
#if (hxmc.target == "wasm32-wasi")
import studio.web.StudioWeb;
#end

using StringTools;

// The studio's tools for agents (the MCP server's, Mcp; the prompt bar's,
// LocalAgent): the project read and patched (each patch an edit of the
// studio's, in its history: undone like any other, a live literal's
// patched in the screens, anything else built), the program checked,
// a screen's frame and tree read.
//
//   project.read   {path?}                    a file's text (its current edits too), else the files and screens
//   project.patch  {path, edits: [{old, new}]} or {path, text}   then {result: patched | built | failed | unchanged, diagnostics}
//   build.check    {}                         the program typed (tsgo's check too), nothing written: diagnostics
//   run.snap       {screen?, path?}           a screen's last frame as a PNG (an image, and the file written; a design's frame drawn offscreen)
//   run.tree       {screen?}                  a screen's node tree: tags, boxes, texts, styles, sources (a design's: its interpreted nodes)
//   studio.focus   {}                         what the user looks at: the project, the screen in focus, the selection, the screens in view
//   studio.working {screen?, path?, note}     what the agent is about to do (its status in Presence)
//   studio.done    {note?}                    the agent finished: its marks fade
//
// A call of an agent's (agent: its Presence id) moves it there (Presence.called);
// its patches are its in the history (Docs' by).
//
// In the browser the page calls them (studio.web.WebTools: WebMCP's, a
// draft's link) and makes the PNGs, its GPU's pixels read asynchronously.
class Tools implements Mcp.Target {
	final studio:Studio;

	public function new(studio)
		this.studio = studio;

	public static final list:Array<Dynamic> = [
		{
			name: "project.read",
			description: "Read a file of the project open in helder studio (with the studio's unsaved state), or without a path list its source files and screens (stories by flow).",
			inputSchema: {type: "object", properties: {path: {type: "string", description: "a path relative to the project's directory, or absolute"}}}
		},
		{
			name: "project.patch",
			description: "Edit a file of the project: each edit's old text (once in the file) replaced by its new text, or the whole text given, or the file deleted (delete: true, e.g. the starter's app.tsx and app.story.tsx once unused). The edit goes through the studio's history (undoable); live literals' values are patched in the running screens at once, anything else rebuilds. Answers what happened, the build's diagnostics, and the screens that threw when run (crashed: \"screen: file:line: why\").",
			inputSchema: {
				type: "object",
				properties: {
					path: {type: "string"},
					edits: {
						type: "array",
						items: {type: "object", properties: {old: {type: "string"}, "new": {type: "string"}}, required: ["old", "new"]}
					},
					text: {type: "string", description: "the file's whole new text, for a new file or a rewrite (never together with edits)"},
					delete: {type: "boolean", description: "true: the file deleted (nothing else given)"}
				},
				required: ["path"]
			}
		},
		{
			name: "build.check",
			description: "Type the project's program (TypeScript's tsgo check too) without building it: its diagnostics.",
			inputSchema: {type: "object", properties: {}}
		},
		{
			name: "run.snap",
			description: "A screen's last frame as the running program drew it (a PNG); a design file's frame drawn by the studio from its markup as it is now. Without a screen, the one in focus, else the first.",
			inputSchema: {type: "object", properties: {screen: {type: "string", description: "a screen's (story's) name, Flow/Screen"}, path: {type: "string"}}}
		},
		{
			name: "run.tree",
			description: "A screen's node tree from the running program (a design file's frame: its nodes as interpreted from its markup, and what could not be): each node's tag, box, text, a few styles and where its markup is (file:line).",
			inputSchema: {type: "object", properties: {screen: {type: "string"}}}
		},
		{
			name: "studio.focus",
			description: "What the user is looking at in the studio: the project, the screen in focus, the node selected (its tag, file:line and box) and the screens in view. 'This' or 'here' in a prompt means the selection.",
			inputSchema: {type: "object", properties: {}}
		},
		{
			name: "studio.working",
			description: "Say what you are about to do: the note is shown to the user as your status, on the screen or file given.",
			inputSchema: {
				type: "object",
				properties: {note: {type: "string"}, screen: {type: "string"}, path: {type: "string"}},
				required: ["note"]
			}
		},
		{
			name: "studio.done",
			description: "Say you finished: one line on what changed. Your marks on the canvas fade.",
			inputSchema: {type: "object", properties: {note: {type: "string"}}}
		},
		{
			name: "studio.ask",
			description: "Ask the user a question in the chat. Options point at what is on the canvas (frame: <file>#<name> of a design file's frame, screen: a screen's name, image: a project path), or are text alone; the chat shows them as thumbnails and the user picks there. Draw visual options first (frames in a <Group title=\"the question\"> of a design file), then ask. Returns {id} at once: keep working; the answer arrives appended to a later tool result (or call studio.inbox). wait: true blocks until answered (up to 10 minutes, then {pending: true}); {id} alone waits for an earlier question.",
			inputSchema: {
				type: "object",
				properties: {
					question: {type: "string"},
					options: {
						type: "array",
						items: {
							type: "object",
							properties: {
								id: {type: "string"},
								label: {type: "string"},
								note: {type: "string"},
								frame: {type: "string", description: "a design file's frame, <file>#<name>"},
								screen: {type: "string"},
								image: {type: "string"}
							},
							required: ["label"]
						}
					},
					multiple: {type: "boolean"},
					wait: {type: "boolean"},
					id: {type: "string", description: "an earlier question's id: wait for its answer"}
				}
			}
		},
		{
			name: "studio.guide",
			description: "How to build here, fast: the project's files, screens as stories, sketching on the canvas, and the TypeScript APIs a topic needs (start, ui, game, design, assets, 3d). Call it instead of exploring the repository: start first, then the topic you need.",
			inputSchema: {type: "object", properties: {topic: {type: "string", description: "start (the default), ui, game, design, assets, 3d"}}}
		},
		{
			name: "studio.inbox",
			description: "What the user said since you last heard (answers to your questions, direction typed while you work). It also arrives appended to every tool result.",
			inputSchema: {type: "object", properties: {}}
		},
	];

	public function agents():Presence
		return studio.presence;

	@:coroutine public function tool(name:String, args:Dynamic, agent:String):{content:Array<Dynamic>, isError:Bool}
		return call(name, args, agent);

	// a tool called: its content (MCP's: [{type: text, text} | {type: image, data, mimeType}]) and whether it failed
	@:coroutine public function call(name:String, args:Dynamic, ?agent:String):{content:Array<Dynamic>, isError:Bool} {
		var r = run(name, args, agent);
		// (an agent's result carries what the user said since: the inbox's notes, delivered)
		if (agent == null || name == "studio.inbox") return r;
		var notes = studio.inbox.take();
		return notes.length == 0 ? r : {content: r.content.concat([{type: "text", text: Inbox.text(notes)}]), isError: r.isError};
	}

	@:coroutine function run(name:String, args:Dynamic, agent:Null<String>):{content:Array<Dynamic>, isError:Bool} {
		if (args == null) args = {};
		if (agent != null) {
			// (its path as the project's, the way the studio names files)
			var at = Reflect.copy(args);
			if (args.path != null) at.path = try rel(path(args.path)) catch (_:Dynamic) args.path;
			studio.presence.called(agent, name, at);
		}
		return try switch name {
			case "project.read": text(read(args.path));
			case "project.patch": text(Json.stringify(patch(args, agent), "  "));
			case "build.check":
				var pr = studio.previews;
				if (pr == null) throw "no project open";
				var r = pr.check();
				var out:Dynamic = {ok: r.ok, ms: r.ms, diagnostics: r.diagnostics};
				// (it types; what threw when the studio ran it, beside)
				var crashed = studio.crashes();
				if (crashed.length > 0) out.crashed = crashed;
				text(Json.stringify(out, "  "));
			case "run.snap": snap(args);
			case "run.tree": text(Json.stringify(tree(args.screen), "  "));
			case "studio.focus":
				// (the agent is where the user looks)
				var f = focus();
				if (agent != null && f.screen != null) studio.presence.working(agent, null, f.screen);
				text(Json.stringify(f, "  "));
			case "studio.working":
				if (agent != null) studio.presence.working(agent, args.note, args.screen, args.path == null ? null : rel(path(args.path)));
				text("ok");
			case "studio.done":
				if (agent != null) studio.presence.done(agent, args.note);
				text("ok");
			case "studio.ask": text(Json.stringify(ask(args, agent), "  "));
			case "studio.guide": text(Guides.get(args.topic));
			case "studio.inbox":
				var notes = studio.inbox.take();
				text(notes.length == 0 ? "Nothing new from the user." : Inbox.text(notes));
			case _: throw 'no tool $name';
		} catch (e:Dynamic) {content: [{type: "text", text: Std.string(e)}], isError: true};
	}

	// a question asked (its id at once), or waited for (wait, or an earlier one's id)
	@:coroutine function ask(args:Dynamic, agent:Null<String>):Dynamic {
		var qs = studio.questions;
		var q = args.id != null ? qs.get(args.id) : qs.ask(agent == null ? null : studio.presence.peer(agent), args.question, args.options, args.multiple == true);
		if (q == null) throw 'no question ${args.id}';
		if (args.id == null && args.wait != true) return {id: q.id};
		if (q.answered) return {id: q.id, picked: q.picked, text: q.text};
		qs.wait(q.id);
		var t0 = haxe.Timer.stamp();
		while (!(qs.get(q.id)?.answered ?? true) && haxe.Timer.stamp() - t0 < WAIT)
			Async.delay(0.1);
		var a = qs.get(q.id);
		if (a != null && a.answered) return {id: q.id, picked: a.picked, text: a.text};
		qs.wait(q.id, false);
		return {id: q.id, answer: null, pending: true};
	}

	// (the longest a call waits for an answer, seconds)
	public static var WAIT = 600.0;

	static function text(s:String):{content:Array<Dynamic>, isError:Bool}
		return {content: [{type: "text", text: s}], isError: false};

	function path(p:Null<String>):String {
		var pr = studio.project;
		if (pr == null) throw "no project open";
		if (p == null || p == "") throw "a path is needed";
		var full = haxe.io.Path.isAbsolute(p) ? p : pr.dir + "/" + p;
		full = haxe.io.Path.normalize(full);
		if (!full.startsWith(pr.dir + "/")) throw '$p is not in the project ($pr.dir)';
		return full;
	}

	function read(p:Null<String>):String {
		var pr = studio.project;
		if (pr == null) throw "no project open";
		if (p == null || p == "") {
			var files = [for (f in pr.sources()) f.substr(pr.dir.length + 1)];
			var flows = [for (f in pr.flows()) {flow: f.name, screens: [for (s in f.screens) {name: s.name, width: s.width, height: s.height, file: s.file.substr(pr.dir.length + 1)}]}];
			return Json.stringify({project: pr.name, dir: pr.dir, typescript: pr.typescript, files: files, flows: flows}, "  ");
		}
		var f = path(p);
		if (!Files.exists(f)) throw '$p: no such file';
		return studio.docs.get(f).text;
	}

	// what the user looks at: the project, the screen in focus, the selection, the screens in view
	function focus():Dynamic {
		var p = studio.project;
		if (p == null) throw "no project open";
		var sel = studio.selection.peek();
		var selected:Dynamic = sel == null ? null : {
			screen: sel.screen,
			tag: sel.tag,
			node: sel.nodeTag,
			source: rel(sel.file) + ":" + studio.docs.get(sel.file).doc.lineCol(sel.start).line,
			rect: [r(sel.x), r(sel.y), r(sel.width), r(sel.height)]
		};
		return {
			project: {name: p.name, dir: p.dir},
			screen: studio.focused.peek(),
			selection: selected,
			others: [for (o in studio.others.peek()) rel(o.file) + ":" + studio.docs.get(o.file).doc.lineCol(o.start).line],
			inView: studio.layout.inView()
		};
	}

	@:coroutine function patch(args:Dynamic, agent:Null<String>):Dynamic {
		var f = path(args.path);
		// (a whole text sent beside edits is an agent's slip: it once wiped a file)
		if (args.text != null && args.edits != null) throw "text or edits, not both";
		var by = agent == null ? null : studio.presence.peer(agent)?.name;
		if (args.delete == true) {
			if (args.text != null || args.edits != null) throw "delete, or text or edits, not both";
			if (!studio.docs.has(f)) throw '${args.path}: no such file';
			studio.remove(f, by);
			return landed();
		}
		// (a file not there yet: made by its text, through the history: undone, it is gone)
		if (!studio.docs.has(f)) {
			if (args.text == null) throw '${args.path}: no such file; send text to create it';
			studio.create(f, args.text, by);
			return landed();
		}
		var doc = studio.docs.get(f);
		var base = doc.text, changes = [];
		if (args.text != null) changes.push(new helder.syntax.Transaction.Change(0, base.length, args.text));
		else {
			var edits:Array<Dynamic> = args.edits ?? [];
			if (edits.length == 0) throw "no edits (edits: [{old, new}], or text)";
			for (e in edits) {
				var old:String = e.old, at = base.indexOf(old);
				if (old == "" || at < 0) throw 'not in ${args.path}: ${old.substr(0, 60)}';
				if (base.indexOf(old, at + 1) >= 0) throw 'more than once in ${args.path}: ${old.substr(0, 60)} (give more of it)';
				changes.push(new helder.syntax.Transaction.Change(at, at + old.length, Reflect.field(e, "new")));
			}
		}
		var tx = new Transaction(changes, null, base);
		// (the agent there and its marks: Studio.agentEdited, by its name)
		studio.edit(f, tx, rel(f), "agent", null, by);
		return landed();
	}

	// (an edit's way to the program, waited for: a patch at once, a build;
	// the program the project's now: a file made may have brought it)
	@:coroutine function landed():Dynamic {
		var pr = studio.previews;
		var t0 = haxe.Timer.stamp();
		Async.delay(0.02);
		while (pr != null && pr.busy() && haxe.Timer.stamp() - t0 < 120) Async.delay(0.02);
		// (a host running: the screens out of view a moment longer, one that throws said here)
		var t1 = haxe.Timer.stamp();
		while (pr != null && pr.sinceHost() >= 0 && !pr.failed && !pr.allShown() && haxe.Timer.stamp() - t1 < 3) Async.delay(0.02);
		var diags = pr == null ? [] : [for (d in pr.latest) d];
		var crashed = pr == null || pr.failed ? [] : studio.crashes();
		var out:Dynamic = {
			result: pr == null ? "saved" : pr.failed ? "failed" : crashed.length > 0 ? "crashed" : studio.message.peek().startsWith("patched") ? "patched" : "built",
			message: studio.message.peek(),
			diagnostics: diags
		};
		if (crashed.length > 0) out.crashed = crashed;
		return out;
	}

	function screenOf(name:Null<String>):Screen {
		var pr = studio.previews;
		if (pr == null) throw "no project open";
		var n = name ?? studio.focused.peek();
		var s = n == null ? pr.screens[0] : pr.screen(n);
		if (s == null) throw 'no screen $n (${[for (x in pr.screens) x.info.name].join(", ")})';
		return s;
	}

	// the design frame named (else in focus; else the first screen, without
	// a program): drawn by the studio itself; null: the program's screen
	function designOf(name:Null<String>):Null<Project.ScreenInfo> {
		var p = studio.project;
		if (p == null) throw "no project open";
		var n = name ?? studio.focused.peek();
		var s = n == null ? (studio.previews == null ? p.screens[0] : null) : p.screen(n);
		if (n != null && s == null) throw 'no screen $n (${[for (x in p.screens) x.name].join(", ")})';
		return s != null && s.source.match(Design(_)) ? s : null;
	}

	@:coroutine function snap(args:Dynamic):{content:Array<Dynamic>, isError:Bool} {
		var d = designOf(args.screen);
		#if (hxmc.target == "wasm32-wasi")
		// (the PNG is the page's to make, from the GPU's pixels: pending, its id)
		if (d != null) {
			var t = studio.designs.texture(d.name);
			var id = StudioWeb.snap_texture(t.texture.id());
			Main.window.device.destroyTexture(t.texture);
			return {
				content: [
					{type: "image", data: "", mimeType: "image/png", pending: id},
					{type: "text", text: '${d.name}: ${t.width}x${t.height}, interpreted from ${rel(d.file)}'}
				],
				isError: false
			};
		}
		#end
		if (d != null) {
			var img = studio.designs.pixels(d.name);
			var png = helder.image.PngEncoder.encode(img.pixels, img.width, img.height, true);
			var out = written(png, args.path, Shell.slug(d.name));
			return {
				content: [
					{type: "image", data: haxe.crypto.Base64.encode(png), mimeType: "image/png"},
					{type: "text", text: '${d.name}: ${img.width}x${img.height}, interpreted from ${rel(d.file)}, written to $out'}
				],
				isError: false
			};
		}
		var s = screenOf(args.screen);
		#if (hxmc.target == "wasm32-wasi")
		var img = s.image.peek();
		if (img == null) throw '${s.info.name} has no frame yet';
		// (a frame of the preview host's is the browser's: its bitmap, the page's to make a PNG of)
		if (!img.hasPixels) return {
			content: [
				{type: "image", data: "", mimeType: "image/png", pending: StudioWeb.snap_image(img.browser)},
				{type: "text", text: '${s.info.name}: ${img.width}x${img.height}, frame ${s.version}'}
			],
			isError: false
		};
		var out = "(not written)";
		var png = helder.image.PngEncoder.encode(img.pixels, img.width, img.height, true);
		#else
		// (a texture the host shares: read back there; a frame on its way, out of view or a build's, waited for)
		var img = studio.previews.pixels(s);
		if (s.crashed) throw '${s.info.name} crashed: ${s.report.peek()}';
		if (img == null) throw '${s.info.name} has no frame yet';
		var png = helder.image.PngEncoder.encode(img.pixels, img.width, img.height, true);
		var out = written(png, args.path, s.slug);
		#end
		return {
			content: [
				{type: "image", data: haxe.crypto.Base64.encode(png), mimeType: "image/png"},
				{type: "text", text: '${s.info.name}: ${img.width}x${img.height}, frame ${s.version}, written to $out'}
			],
			isError: false
		};
	}

	// (a snap's PNG written: path, else the project's snaps/<slug>.png)
	function written(png:haxe.io.Bytes, path:Null<String>, slug:String):String {
		#if (hxmc.target == "wasm32-wasi")
		return "(not written)";
		#else
		var out = path ?? '${studio.project.out}/snaps/$slug.png';
		helder.cli.TestCommand.mkdirs(haxe.io.Path.directory(out));
		sys.io.File.saveBytes(out, png);
		return out;
		#end
	}

	function rel(f:String):String
		return f.startsWith(studio.project.dir + "/") ? f.substr(studio.project.dir.length + 1) : f;

	// a design frame's tree: its nodes as interpreted now, offscreen at its size
	function designTree(d:Project.ScreenInfo):Dynamic {
		var o = studio.designs.offscreen(d.name);
		var doc = studio.docs.get(d.file).doc;
		function node(n:helder.ui.Node, root:helder.ui.Node):Dynamic {
			var o2:Dynamic = {tag: n.tag, rect: [r(n.absX - root.absX), r(n.absY - root.absY), r(n.width), r(n.height)]};
			if (Std.isOfType(n, helder.ui.TextNode)) o2.text = (cast n : helder.ui.TextNode).text;
			if ((n.style.background : Int) != 0) o2.background = hex(n.style.background);
			if (n.style.color != null) o2.color = hex(n.style.color);
			if (n.style.opacity != 1) o2.opacity = n.style.opacity;
			var at = o.made.sources.get(n);
			if (at != null) o2.source = rel(d.file) + ":" + doc.lineCol(at).line;
			if (n.children.length > 0) o2.children = [for (c in n.children) node(c, root)];
			return o2;
		}
		var root = o.made.nodes[0];
		var errors = [for (e in o.made.errors) {message: e.message, source: e.at < 0 ? null : rel(d.file) + ":" + doc.lineCol(e.at).line}];
		return {screen: d.name, interpreted: true, root: root == null ? null : node(root, root), errors: errors};
	}

	static function hex(c:Int):String
		return "#" + StringTools.hex(c, 8).toLowerCase();

	@:coroutine function tree(name:Null<String>):Dynamic {
		var d = designOf(name);
		if (d != null) return designTree(d);
		var s = screenOf(name);
		var answer:Dynamic = null;
		if (!studio.previews.request(s, "Ui.getTree", {}, r -> answer = r)) throw '${s.info.name} is not running';
		var t0 = haxe.Timer.stamp();
		while (answer == null && haxe.Timer.stamp() - t0 < 5) Async.delay(0.005);
		if (answer == null) throw '${s.info.name} did not answer';
		var root:Dynamic = Studio.rootOf(answer);
		return {screen: s.info.name, root: simplify(root)};
	}

	// (a node as an agent reads it: its source a file:line of the project)
	function simplify(n:Dynamic):Dynamic {
		if (n == null) return null;
		var o:Dynamic = {tag: n.tag, rect: [r(n.x), r(n.y), r(n.width), r(n.height)]};
		if (n.text != null) o.text = n.text;
		var st:Dynamic = n.style;
		if (st != null) {
			if (st.background != null && st.background != "#00000000") o.background = st.background;
			if (st.color != null) o.color = st.color;
			if (st.opacity != null && st.opacity != 1) o.opacity = st.opacity;
		}
		if (n.source != null) {
			var f = studio.project.real(n.source.file);
			o.source = (f.startsWith(studio.project.dir + "/") ? f.substr(studio.project.dir.length + 1) : f) + ":" + n.source.line;
		}
		var kids:Array<Dynamic> = n.children ?? [];
		if (kids.length > 0) o.children = [for (c in kids) simplify(c)];
		return o;
	}

	static function r(v:Float):Float
		return Math.round(v * 10) / 10;
}
