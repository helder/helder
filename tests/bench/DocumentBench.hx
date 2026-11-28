import haxe.Timer;
import haxe.io.Bytes;
import helder.css.CssCascade;
import helder.css.CssTheme;
import helder.css.CssUserAgentTheme;
import helder.dom.Dom;
import helder.dom.Document;
import helder.dom.Element;
import helder.gfx.Color;
import helder.ui.*;
import helder.ui.box.DocumentNode;
import helder.ui.box.DocumentView;
import helder.ui.draw.DrawText;
import helder.view.Render;
import helder.view.graph.Graph;
import Todo;
import Mail;

using StringTools;

// helder's CSS engine live in a helder.ui window (DocumentNode), timed
// against helder.ui today and against itself on long documents, natively,
// each frame drawn by the GPU renderer offscreen and read back (DrawFrame:
// the GPU waited for), the least and the median of runs (bench document):
//
//   DocumentBench apps                       examples/todo and examples/mail as helder.ui
//                                            draws them, and mirrored as an app on the engine
//                                            would have them: helder.dom trees built in code,
//                                            styled by ua/app.css and the screen's sheet
//                                            (tests/bench/document/<screen>.css: each node's own
//                                            style and :hover look as classes), both compiled at
//                                            build time, no parser: the first frame, the list
//                                            scrolled, rows hovered, a field typed into, the
//                                            window resized, 1,000 rows added
//   DocumentBench sheets                     those sheets written again (a screen changed)
//   DocumentBench doc <page.html> [sheets.json] [name]
//   DocumentBench sample | sample-files <dir> | mem <todo|mail> <helder.ui|engine>
//                                            a page in a scroller: loaded to its first frame,
//                                            scrolled through, its links hovered, resized
//
// Each frame: its update (what the engine's restyle, layout run in) and
// its draw (Ui.paint: what the engine paints recorded, the renderer's work,
// the GPU's, read back); the engine's own work apart (DocumentNode.stats:
// restyle, layout, paint recording); GC bytes a frame; the live heap the
// screen holds (a full collection before and after it is made).
// JSON lines on stdout, tests/bench/document.mjs makes the tables.
class DocumentBench {
	static final RUNS = Std.parseInt(Sys.getEnv("RUNS") ?? "3") ?? 3;
	static var frame:Null<DrawFrame> = null;
	static var pixels:Null<Bytes> = null;
	static var screen = "";
	static var variant = "";
	static var declared = false;

	static function main() {
		var args = Sys.args();
		Clock.tick(0);
		switch args[0] {
			case "apps":
				var only = Sys.getEnv("SCREENS");
				if (only == null || only.indexOf("todo") >= 0) todo();
				if (only == null || only.indexOf("mail") >= 0) mail();
			case "doc":
				document(args[1], args.length > 2 ? args[2] : null, args.length > 3 ? args[3] : haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(args[1])));
			case "sample":
				sample();
			case "mem":
				memory(args[1], args[2]);
			case "sheets":
				// (the mirrors' sheets, compiled into the engine's screens: tests/bench/document/<screen>.css)
				for (name in ["todo", "mail"]) {
					var css = sheetText([name == "todo" ? todoMirror(20) : mailMirror(20), name == "todo" ? todoMirror(1020) : mailMirror(1020)]);
					sys.io.File.saveContent('tests/bench/document/$name.css', css);
					Sys.println('tests/bench/document/$name.css');
				}
			case "boxstyles":
				// (the box variant's styles: each mirror node's computed style, by tag, class and its parent's, hovered
				// too where a :hover rule has it, written as data: tests/bench/document/<screen>.boxes)
				for (name in ["todo", "mail"]) {
					screen = name;
					var ms = name == "todo" ? [todoMirror(20), todoMirror(1020)] : [mailMirror(20), mailMirror(1020)];
					sys.io.File.saveContent('tests/bench/document/$name.boxes', boxStyles([for (m in ms) build(m)]));
					Sys.println('tests/bench/document/$name.boxes');
				}
				// (TodoBoxes', the size lane's: TodoDocument's tree and sheet)
				var d = new Document();
				d.append(element(d, cast TodoBoxes.spec()));
				sys.io.File.saveContent('tests/bench/document/todo-app.boxes', boxStyles([d], d -> helder.ui.box.DocumentApp.node(d, [CssUserAgentTheme.app(), CssTheme.file("document/todo-app.css")])));
				Sys.println('tests/bench/document/todo-app.boxes');
			case "sample-files":
				// (the sample page and its images as files, for Chromium)
				var dir = args[1];
				sys.io.File.saveContent('$dir/sample.html', SamplePage.HTML);
				for (n in ["harbour.png", "field.png", "dusk.png"]) {
					var b = SamplePage.image(n);
					sys.io.File.saveBytes('$dir/$n', helder.image.PngEncoder.encode(b.straight(), b.width, b.height));
				}
			case _:
				Sys.println("DocumentBench apps | doc <page.html> [sheets.json] [name] | sample | sheets");
		}
	}

	// ---- the frame

	static function draw(ui:Ui) {
		// (one target as large as the largest window: a resize draws into it as a window's swap chain keeps its size)
		if (frame == null || frame.width < Std.int(ui.width) || frame.height < Std.int(ui.height)) {
			if (frame != null) frame.dispose();
			frame = new DrawFrame(Std.int(Math.max(ui.width, 1024)), Std.int(Math.max(ui.height, 768)));
			pixels = Bytes.alloc(frame.width * frame.height * 4);
		}
		frame.draw(ui, pixels);
	}

	// (a frame: the clock on, the update, the draw; its times and the engine's)
	static function step(ui:Ui, doc:Null<DocumentNode>):Array<Float> {
		Clock.tick(Clock.now + 1 / 60);
		var e0 = engine(doc);
		var t0 = Timer.stamp();
		ui.update();
		var t1 = Timer.stamp();
		draw(ui);
		var t2 = Timer.stamp();
		var e1 = engine(doc);
		return [(t1 - t0) * 1000, (t2 - t1) * 1000, e1[0] - e0[0], e1[1] - e0[1], e1[2] - e0[2]];
	}

	static function engine(doc:Null<DocumentNode>):Array<Float>
		return doc != null ? [doc.stats.restyleMs, doc.stats.layoutMs, doc.stats.paintMs] : boxNode != null ? [0, boxNode.layoutMs, boxNode.paintMs] : fastTree != null ? [0,
			fastTree.layoutMs, fastTree.paintMs] : [0, 0, 0];

	static function spansOf(doc:Null<DocumentNode>):helder.ui.box.PaintSpans
		return doc != null ? @:privateAccess doc.view.spans : boxNode != null ? @:privateAccess boxNode.spans : fastTree != null ? @:privateAccess fastTree.spans : new helder.ui.box.PaintSpans();

	// (the fast variant's tree, its engine work)
	static var fastTree:Null<helder.ui.fast.Tree> = null;

	// (the box variant's node, its engine work: BoxScreen's)
	static var boxNode:Null<BoxScreen.BoxNode> = null;

	// (n frames, each after act(i): their times, GC bytes; a JSON line)
	static function run(op:String, ui:Ui, doc:Null<DocumentNode>, n:Int, act:Int->Void, ?extra:Dynamic) {
		if (Sys.getEnv("PAINT_BYTES") != null) {
			var bb = BoxScreen.BoxNode.bytes;
			for (k in 0...5) bb[k] = 0;

			var f0 = GcStats.bytes();
			var F = helder.gfx.FrameCounts;
			var q0 = F.quads, d0 = F.draws, p0 = F.passes, u0 = F.uploaded;
			for (k in 0...3) DrawFrame.PHASES[k] = 0;
			runOp(op, ui, doc, n, act, extra);
			if (Sys.getEnv("SPAN_CHECK") != null && (op.startsWith("type") || op.startsWith("drag") || op.startsWith("scroll") || op.startsWith("resize") || op.startsWith("hover")) && variant != "helder.ui") {
				var a = Bytes.alloc(pixels.length);
				a.blit(0, pixels, 0, pixels.length);
				helder.ui.box.PaintSpans.off = true;
				if (doc != null) @:privateAccess doc.layerChanged() else @:privateAccess boxNode.layerChanged();
				ui.requestFrame();
				step(ui, doc);
				helder.ui.box.PaintSpans.off = false;
				var diff = 0;
				for (i in 0...Std.int(pixels.length / 4)) if (a.getInt32(i * 4) != pixels.getInt32(i * 4)) diff++;
				Sys.println('SPANS $screen $variant $op: ${diff} pixels differ from the frame painted whole');
			}
			Sys.println('GPU $screen $variant $op: quads ${Math.round((F.quads - q0) / n)} draws ${Math.round((F.draws - d0) / n)} passes ${Math.round((F.passes - p0) / n)} uploaded ${Math.round((F.uploaded - u0) / n)} a frame; spans copied ${spansOf(doc).copied} recorded ${spansOf(doc).recorded}; record ${Math.round(DrawFrame.PHASES[0] / n * 100000) / 100} encode ${Math.round(DrawFrame.PHASES[1] / n * 100000) / 100} gpu+read ${Math.round(DrawFrame.PHASES[2] / n * 100000) / 100} ms');
			if (variant == "boxes") Sys.println('PAINT $screen $op: frame ${Math.round((GcStats.bytes() - f0) / n / 1024)} KB; paints ${bb[4]}: order ${Math.round(bb[0] / n / 1024)} begin ${Math.round(bb[1] / n / 1024)} paint ${Math.round(bb[2] / n / 1024)} end ${Math.round(bb[3] / n / 1024)} KB a frame');
			return;
		}
		runOp(op, ui, doc, n, act, extra);
	}

	static function runOp(op:String, ui:Ui, doc:Null<DocumentNode>, n:Int, act:Int->Void, ?extra:Dynamic) {
		var totals = [], updates = [], draws = [], styles = [], layouts = [], paints = [], bytes = [];
		var gc0 = GcStats.collections();
		for (i in 0...n) {
			var b0 = GcStats.bytes(), t0 = Timer.stamp();
			act(i);
			var a = (Timer.stamp() - t0) * 1000;
			var s = step(ui, doc);
			bytes.push(GcStats.bytes() - b0);
			totals.push(a + s[0] + s[1]);
			updates.push(a + s[0]);
			draws.push(s[1]);
			styles.push(s[2]);
			layouts.push(s[3]);
			paints.push(s[4]);
		}
		report(op, totals, updates, draws, styles, layouts, paints, bytes, GcStats.collections() - gc0, extra);
	}

	static function report(op:String, totals:Array<Float>, updates:Array<Float>, draws:Array<Float>, styles:Array<Float>, layouts:Array<Float>,
			paints:Array<Float>, bytes:Array<Float>, gcs:Int, ?extra:Dynamic) {
		var o:Dynamic = {
			screen: screen,
			variant: variant,
			op: op,
			frames: totals.length,
			median: med(totals),
			min: min(totals),
			p95: pct(totals, 0.95),
			max: pct(totals, 1),
			update: med(updates),
			draw: med(draws),
			style: med(styles),
			layout: med(layouts),
			paint: med(paints),
			engine: med([for (k in 0...styles.length) styles[k] + layouts[k] + paints[k]]),
			gcBytes: med(bytes),
			gcs: gcs
		};
		if (extra != null) for (f in Reflect.fields(extra)) Reflect.setField(o, f, Reflect.field(extra, f));
		Sys.println(haxe.Json.stringify(o));
	}

	static function med(a:Array<Float>):Float
		return pct(a, 0.5);

	static function min(a:Array<Float>):Float {
		var m = Math.POSITIVE_INFINITY;
		for (v in a) if (v < m) m = v;
		return round(m);
	}

	static function pct(a:Array<Float>, p:Float):Float {
		if (a.length == 0) return 0;
		var s = a.copy();
		s.sort(Reflect.compare);
		return round(s[Std.int(Math.min(s.length - 1, Math.floor(p * (s.length - 1) + 0.5)))]);
	}

	static inline function round(v:Float):Float
		return Math.round(v * 1000) / 1000;

	// (the heap's live bytes after a full collection)
	static function live():Float {
		#if (target.name == "hxmc")
		hxmc.NativeGc.collect(true);
		return hxmc.GcStats.liveBytes();
		#else
		return 0;
		#end
	}

	// (a first frame, made RUNS times: the least and the median, the heap it holds; the last kept)
	static function first<T>(op:String, make:Void->{ui:Ui, doc:Null<DocumentNode>, keep:T}):{ui:Ui, doc:Null<DocumentNode>, keep:T} {
		var times = [], updates = [], draws = [], styles = [], layouts = [], paints = [], bytes = [];
		var made = null, heap = 0.0;
		for (_ in 0...RUNS) {
			made = null;
			var h0 = live();
			var b0 = GcStats.bytes(), t0 = Timer.stamp();
			made = make();
			var a = (Timer.stamp() - t0) * 1000;
			var s = step(made.ui, made.doc);
			bytes.push(GcStats.bytes() - b0);
			times.push(a + s[0] + s[1]);
			updates.push(a + s[0]);
			draws.push(s[1]);
			var e = engine(made.doc);
			styles.push(e[0]);
			layouts.push(e[1]);
			paints.push(e[2]);
			heap = live() - h0;
		}
		report(op, times, updates, draws, styles, layouts, paints, bytes, 0, {heap: Math.round(heap)});
		return made;
	}

	// ---- apps: helder.ui today, and the same screen as DOM and CSS

	static function todo() {
		screen = "todo";
		var w = 480, h = 560;
		function items(n:Int, from = 0):Array<Item>
			return [for (i in from...from + n) new Item('Task ${i + 1}: water the plants and call back')];
		function mount(n:Int):{ui:Ui, app:Todo} {
			var ui = new Ui(new DrawText(), w, h);
			ui.theme = Todo.sheet;
			var app = new Todo();
			app.todos(items(n));
			Render.render(app.view(), ui.root);
			Graph.flush();
			ui.update();
			Clock.finish();
			ui.update();
			return {ui: ui, app: app};
		}
		// (the mirrors: as helder.ui lays the screen out with 20 rows, and with 1,000 more)
		var m20 = mirror(mount(20).ui), m1020 = mirror(mount(1020).ui);
		fresh("todo", [m20, m1020]);
		var rowsAdded = rowsOf(m1020.root, "list", 20);
		app(w, h, () -> mount(20), m20, rowsAdded, (u:Ui, a:Todo) -> a.todos(a.todos().concat(items(1000, 20))), "draft");
		todoFast(w, h);
	}

	static function mail() {
		screen = "mail";
		var w = 860, h = 560;
		function messages(n:Int):Array<Message>
			return [
				for (i in 0...n)
					new Message('Sender ${i % 37}', 'Subject number ${i} about the weekly report', 'Body ${i}', "Inbox", 1 + i % 28, i % 3 == 0)
			];
		function mount(n:Int):{ui:Ui, app:Mail} {
			var ui = new Ui(new DrawText(), w, h);
			if (!declared) Mail.declare();
			declared = true;
			var app = new Mail();
			// (light, whatever the machine's appearance: the screen's sheet is checked in)
			app.dark(false);
			if (n > 0) app.messages(messages(n));
			var root = new Node();
			root.theme = Mail.sheet;
			root.style.flexGrow = 1;
			ui.root.append(root);
			Render.render(app.view(), root);
			Graph.flush();
			ui.update();
			Clock.finish();
			ui.update();
			return {ui: ui, app: app};
		}
		var m20 = mirror(mount(20).ui), m1020 = mirror(mount(1020).ui);
		fresh("mail", [m20, m1020]);
		var rowsAdded = rowsOf(m1020.root, "list", 20);
		app(w, h, () -> mount(20), m20, rowsAdded, (u:Ui, a:Mail) -> a.messages(messages(1020)), "search");
		mailFast(w, h);
	}

	// (each operation on helder.ui's screen, then on the engine's)
	static function app<A>(w:Int, h:Int, mount:Void->{ui:Ui, app:A}, m:Mirror, rowsAdded:Array<MirrorNode>, add:(Ui, A) -> Void, field:String) {
		// (helder.ui)
		variant = "helder.ui";
		var made = first("first frame (20 rows)", () -> {
			var x = mount();
			{ui: x.ui, doc: null, keep: x.app};
		});
		var ui = made.ui, a = made.keep;
		add(ui, a);
		Graph.flush();
		step(ui, null);
		var list = ui.root.find("list");
		var lx = list.absX + list.width / 2, ly = list.absY + list.height / 2;
		run("scroll the list (1,020 rows, 40 px a frame)", ui, null, 120, i -> ui.wheel(lx, ly, 0, i % 60 < 30 ? 40 : -40));
		var rows = [for (c in list.children) if (c.absY - list.scrollY > list.absY && c.absY - list.scrollY + c.height < list.absY + list.height) c];
		run("hover over rows", ui, null, 120, i -> {
			var r = rows[i % rows.length];
			ui.pointerMove(r.absX + 20, r.absY - list.scrollY + r.height / 2);
		});
		var f = ui.root.find(field);
		ui.pointerDown(f.absX + 10, f.absY + f.height / 2, 1);
		ui.pointerUp(f.absX + 10, f.absY + f.height / 2, 1);
		step(ui, null);
		run("type into a field", ui, null, 60, i -> ui.textInput(String.fromCharCode(97 + i % 26)));
		run("resize the window", ui, null, 40, i -> ui.resize(i % 2 == 0 ? w - 60 : w, h));
		// (a window's edge dragged: a width not seen before each frame)
		run("drag-resize (a new width each frame)", ui, null, 40, i -> ui.resize(w - 1 - i, h));
		ui.resize(w, h);
		step(ui, null);
		addRows("add 1,000 rows", () -> {
			var x = mount();
			{ui: x.ui, doc: null, keep: x.app};
		}, x -> {
			add(x.ui, x.keep);
			Graph.flush();
		});

		// (the engine)
		variant = "engine";
		function mountDoc():{ui:Ui, doc:Null<DocumentNode>, keep:Document} {
			var ui = new Ui(new DrawText(), w, h);
			var d = build(m);
			var node = engineNode(d);
			node.style.flexGrow = 1;
			ui.root.append(node);
			return {ui: ui, doc: node, keep: d};
		}
		var e = first("first frame (20 rows)", mountDoc);
		var ui = e.ui, doc = e.doc, d = e.keep;
		var listEl = byTag(d, "list");
		appendRows(d, listEl, rowsAdded);
		step(ui, doc);
		var box = rectOf(doc, listEl);
		run("scroll the list (1,020 rows, 40 px a frame)", ui, doc, 120, i -> ui.wheel(box[0] + box[2] / 2, box[1] + box[3] / 2, 0, i % 60 < 30 ? 40 : -40));
		var rowEls = [for (c in listEl.children) c].slice(0, 12);
		run("hover over rows", ui, doc, 120, i -> {
			var r = rectOf(doc, rowEls[i % rowEls.length]);
			var o = doc.view.scrolls.get(listEl);
			ui.pointerMove(r[0] + 20, r[1] - (o == null ? 0 : o[1]) + r[3] / 2);
		});
		var fieldEl = byTag(d, field), text = d.createTextNode(" ");
		fieldEl.append(text);
		step(ui, doc);
		run("type into a field", ui, doc, Std.parseInt(Sys.getEnv("TYPES") ?? "60"), i -> text.data = (text.data.length > 40 ? " " : text.data) + String.fromCharCode(97 + i % 26));
		run("resize the window", ui, doc, Std.parseInt(Sys.getEnv("RESIZES") ?? "40"), i -> ui.resize(i % 2 == 0 ? w - 60 : w, h));
		run("drag-resize (a new width each frame)", ui, doc, Std.parseInt(Sys.getEnv("DRAGS") ?? "40"), i -> ui.resize(w - 1 - i % 200, h));
		ui.resize(w, h);
		step(ui, doc);
		addRows("add 1,000 rows", mountDoc, x -> appendRows(x.keep, byTag(x.keep, "list"), rowsAdded));
		Sys.println(haxe.Json.stringify({screen: screen, mirror: m.nodes, hovers: m.hovers}));
		boxes(w, h, m, rowsAdded, field);
		fast(w, h, m, rowsAdded, field);
		snapshots(w, h, mount, mountDoc);
	}

	// ---- the box variant: the engine's boxes made from code, no DOM, no cascade (BoxScreen)

	// (the box variant's styles, written by `DocumentBench boxstyles`: "" before they are)
	static final boxData = ["todo" => Embed.text("tests/bench/document/todo.boxes"), "mail" => Embed.text("tests/bench/document/mail.boxes")];

	static function boxes(w:Int, h:Int, m:Mirror, rowsAdded:Array<MirrorNode>, field:String) {
		variant = "boxes";
		if (boxData[screen] == "") return;
		var styles = new BoxScreen.BoxStyles(boxData[screen]);
		function mountBoxes():{ui:Ui, doc:Null<DocumentNode>, keep:BoxScreen.BoxBuild} {
			var ui = new Ui(new DrawText(), w, h);
			var bb = new BoxScreen.BoxBuild(styles), out = [];
			bb.box(m.root, null, out);
			var node = new BoxScreen.BoxNode(out[0], bb.contexts);
			node.style.flexGrow = 1;
			ui.root.append(node);
			boxNode = node;
			return {ui: ui, doc: null, keep: bb};
		}
		function rect(b:BoxScreen.BoxNode, x:helder.ui.box.Box):Array<Float> {
			var id = b.fragmentOf(x);
			if (id < 0) return [0, 0, 0, 0];
			var p = b.fragments.absolute(id);
			return [b.absX + p.x, b.absY + p.y, b.fragments.width(id), b.fragments.height(id)];
		}
		function hovering(bb:BoxScreen.BoxBuild, node:BoxScreen.BoxNode) {
			var hovered:Null<helder.ui.box.Box> = null;
			node.onHover = b -> {
				// (the nearest box a :hover rule restyles)
				while (b != null) {
					var spec = bb.specs.get(b);
					if (spec != null && b.parent != null && styles.of(spec.tag, spec.cls, b.parent.style, true) != null) break;
					b = b.parent;
				}
				if (b == hovered) return;
				if (hovered != null) bb.restyle(node, hovered, hovered.parent.style, false);
				if (b != null) bb.restyle(node, b, b.parent.style, true);
				hovered = b;
				node.changed(null, false);
			};
		}
		var made = first("first frame (20 rows)", mountBoxes);
		var ui = made.ui, bb = made.keep, node = boxNode;
		hovering(bb, node);
		var list = bb.named(node.root, "list");
		function addTo(bb:BoxScreen.BoxBuild, n:BoxScreen.BoxNode, list:helder.ui.box.Box) {
			var out = [];
			for (r in rowsAdded) bb.box(r, list.style, out);
			for (b in out) list.append(b);
			n.changed(list, true);
		}
		addTo(bb, node, list);
		step(ui, null);
		var box = rect(node, list);
		run("scroll the list (1,020 rows, 40 px a frame)", ui, null, 120, i -> ui.wheel(box[0] + box[2] / 2, box[1] + box[3] / 2, 0, i % 60 < 30 ? 40 : -40));
		var rows = [];
		var c = list.first;
		while (c != null && rows.length < 12) {
			rows.push(c);
			c = c.next;
		}
		run("hover over rows", ui, null, 120, i -> {
			var r = rect(node, rows[i % rows.length]);
			var o = node.scrolls.get(list);
			ui.pointerMove(r[0] + 20, r[1] - (o == null ? 0 : o[1]) + r[3] / 2);
		});
		var f = bb.named(node.root, field), anon = bb.make(Block, styles.anonymousOf(f.style)), text = bb.text(f.style, " ");
		anon.append(text);
		f.append(anon);
		node.changed(text, true);
		step(ui, null);
		run("type into a field", ui, null, Std.parseInt(Sys.getEnv("TYPES") ?? "60"), i -> {
			text.text = (text.text.length > 40 ? " " : text.text) + String.fromCharCode(97 + i % 26);
			node.changed(text, true);
		});
		run("resize the window", ui, null, Std.parseInt(Sys.getEnv("RESIZES") ?? "40"), i -> ui.resize(i % 2 == 0 ? w - 60 : w, h));
		run("drag-resize (a new width each frame)", ui, null, Std.parseInt(Sys.getEnv("DRAGS") ?? "40"), i -> ui.resize(w - 1 - i % 200, h));
		ui.resize(w, h);
		step(ui, null);
		addRows("add 1,000 rows", mountBoxes, x -> addTo(x.keep, boxNode, x.keep.named(boxNode.root, "list")));
		sys.FileSystem.createDirectory("bin/document-bench");
		var s = mountBoxes();
		step(s.ui, null);
		sys.io.File.saveBytes('bin/document-bench/$screen-boxes.png', crop(w, h));
		boxNode = null;
	}

	// ---- the examples on fast nodes (examples/todo-fast, mail-fast): their own markup, helder.ui's ops as they are run on them

	static function todoFast(w:Int, h:Int) {
		function tasks(n:Int, from = 0):Array<TodoFast.Task>
			return [for (i in from...from + n) new TodoFast.Task('Task ${i + 1}: water the plants and call back')];
		fastApp(w, h, "todo-fast", ui -> {
			var app = new TodoFast();
			app.todos(tasks(20));
			{app: app, tree: FastMount.todo(app, ui.root)};
		}, app -> app.todos(app.todos().concat(tasks(1000, 20))), "draft");
	}

	static function mailFast(w:Int, h:Int) {
		function messages(n:Int):Array<MailFast.MailMessage>
			return [
				for (i in 0...n)
					new MailFast.MailMessage('Sender ${i % 37}', 'Subject number ${i} about the weekly report', 'Body ${i}', "Inbox", 1 + i % 28, i % 3 == 0)
			];
		fastApp(w, h, "mail-fast", ui -> {
			var app = new MailFast();
			app.dark(false);
			app.messages(messages(20));
			{app: app, tree: FastMount.mail(app, ui.root)};
		}, app -> app.messages(messages(1020)), "search");
	}

	static function fastApp<A>(w:Int, h:Int, name:String, make:Ui->{app:A, tree:helder.ui.fast.Tree}, add:A->Void, field:String) {
		variant = name;
		function mount():{ui:Ui, doc:Null<DocumentNode>, keep:A} {
			var ui = new Ui(new DrawText(), w, h);
			var m = make(ui);
			fastTree = m.tree;
			Graph.flush();
			ui.update();
			return {ui: ui, doc: null, keep: m.app};
		}
		function find(tag:String):helder.ui.fast.Node {
			var stack = [fastTree.root];
			while (stack.length > 0) {
				var n = stack.shift();
				if (n.tag == tag) return n;
				for (c in n.children()) stack.push(c);
			}
			throw 'no $tag';
		}
		var made = first("first frame (20 rows)", mount);
		var ui = made.ui, app = made.keep, tree = fastTree;
		add(app);
		Graph.flush();
		step(ui, null);
		var list = find("list"), box = tree.rectOf(list);
		run("scroll the list (1,020 rows, 40 px a frame)", ui, null, 120, i -> ui.wheel(box[0] + box[2] / 2, box[1] + box[3] / 2, 0, i % 60 < 30 ? 40 : -40));
		var rows = [for (r in list.children()) {
			var q = tree.rectOf(r);
			if (q[3] > 0 && q[1] > box[1] && q[1] + q[3] < box[1] + box[3]) r;
		}];
		run("hover over rows", ui, null, 120, i -> {
			var q = tree.rectOf(rows[i % rows.length]);
			ui.pointerMove(q[0] + 20, q[1] + q[3] / 2);
		});
		var f = tree.rectOf(find(field));
		ui.pointerDown(f[0] + 10, f[1] + f[3] / 2, 1);
		ui.pointerUp(f[0] + 10, f[1] + f[3] / 2, 1);
		step(ui, null);
		run("type into a field", ui, null, 60, i -> {
			ui.textInput(String.fromCharCode(97 + i % 26));
			Graph.flush();
		});
		run("resize the window", ui, null, 40, i -> ui.resize(i % 2 == 0 ? w - 60 : w, h));
		run("drag-resize (a new width each frame)", ui, null, 40, i -> ui.resize(w - 1 - i, h));
		ui.resize(w, h);
		step(ui, null);
		addRows("add 1,000 rows", mount, x -> {
			add(x.keep);
			Graph.flush();
		});
		sys.FileSystem.createDirectory("bin/document-bench");
		var s = mount();
		step(s.ui, null);
		sys.io.File.saveBytes('bin/document-bench/$screen-$name.png', crop(w, h));
		fastTree = null;
	}

	// ---- the fast variant: fast nodes (helder.ui.fast), each styled by a Style typed from helder.ui's look (FastMirror): no DOM, no cascade

	static function fast(w:Int, h:Int, m:Mirror, rowsAdded:Array<MirrorNode>, field:String) {
		variant = "fast";
		function build(n:MirrorNode, tags:Map<String, helder.ui.fast.Node>):helder.ui.fast.Node {
			// (its style made with the mirror: an app's are constants, made once)
			var style = n.style ?? helder.ui.fast.Style.none;
			var made:helder.ui.fast.Node = n.text != null ? new helder.ui.fast.TextNode(n.text, style) : new helder.ui.fast.Node(style);
			if (n.text == null) for (c in n.children) made.append(build(c, tags));
			if (!tags.exists(n.tag)) tags.set(n.tag, made);
			return made;
		}
		function mountFast():{ui:Ui, doc:Null<DocumentNode>, keep:Map<String, helder.ui.fast.Node>} {
			var ui = new Ui(new DrawText(), w, h);
			var tags = new Map();
			var tree = new helder.ui.fast.Tree(build(m.root, tags));
			tree.style.flexGrow = 1;
			ui.root.append(tree);
			fastTree = tree;
			return {ui: ui, doc: null, keep: tags};
		}
		var made = first("first frame (20 rows)", mountFast);
		var ui = made.ui, tags = made.keep, tree = fastTree;
		var list = tags.get("list");
		function addTo(list:helder.ui.fast.Node) {
			var t = new Map();
			for (r in rowsAdded) list.append(build(r, t));
		}
		addTo(list);
		step(ui, null);
		var box = tree.rectOf(list);
		run("scroll the list (1,020 rows, 40 px a frame)", ui, null, 120, i -> ui.wheel(box[0] + box[2] / 2, box[1] + box[3] / 2, 0, i % 60 < 30 ? 40 : -40));
		var rows = list.children().slice(0, 12);
		run("hover over rows", ui, null, 120, i -> {
			var r = tree.rectOf(rows[i % rows.length]);
			ui.pointerMove(r[0] + 20, r[1] + r[3] / 2);
		});
		var text = new helder.ui.fast.TextNode(" ");
		tags.get(field).append(text);
		step(ui, null);
		run("type into a field", ui, null, Std.parseInt(Sys.getEnv("TYPES") ?? "60"), i -> text.text = (text.text.length > 40 ? " " : text.text) + String.fromCharCode(97 + i % 26));
		run("resize the window", ui, null, Std.parseInt(Sys.getEnv("RESIZES") ?? "40"), i -> ui.resize(i % 2 == 0 ? w - 60 : w, h));
		run("drag-resize (a new width each frame)", ui, null, Std.parseInt(Sys.getEnv("DRAGS") ?? "40"), i -> ui.resize(w - 1 - i % 200, h));
		ui.resize(w, h);
		step(ui, null);
		addRows("add 1,000 rows", mountFast, x -> addTo(x.keep.get("list")));
		sys.FileSystem.createDirectory("bin/document-bench");
		var s = mountFast();
		step(s.ui, null);
		sys.io.File.saveBytes('bin/document-bench/$screen-fast.png', crop(w, h));
		fastTree = null;
	}

	// (each document's elements' computed styles by tag, class and the parent's style ("|h": hovered, where a
	// :hover rule restyles it, its subtree under it), as data: the initial values, then each style's own)
	static function boxStyles(docs:Array<Document>, ?nodeOf:Document->DocumentNode):String {
		var ids = new haxe.ds.ObjectMap<helder.css.CssStyle, Int>(), list:Array<helder.css.CssStyle> = [], keys = new Map<String, Int>();
		var initials:Null<Array<helder.css.CssGroup>> = null;
		function id(s:helder.css.CssStyle):Int {
			var i = ids.get(s);
			if (i == null) {
				ids.set(s, i = list.length);
				list.push(s);
			}
			return i;
		}
		for (d in docs) {
			var ui = new Ui(new DrawText(), 800, 600), node = nodeOf != null ? nodeOf(d) : engineNode(d);
			ui.root.append(node);
			ui.update();
			var styles = node.view.styles;
			initials ??= @:privateAccess styles.initialGroups();
			function subtree(el:Element):Array<Element> {
				var out = [el];
				for (c in el.children) out = out.concat(subtree(c));
				return out;
			}
			function walk(el:Element, parent:Int, hovered:Bool) {
				var cls = el.getAttribute("class") ?? "", s = id(styles.computed(el));
				keys.set(el.localName + "|" + cls + "|" + parent + (hovered ? "|h" : ""), s);
				for (c in el.children) walk(c, s, false);
				if (!hovered && Lambda.exists(cls.split(" "), c -> c.charAt(0) == "h")) {
					el.setState(helder.dom.ElementState.HOVER, true);
					styles.forget(subtree(el));
					walk(el, parent, true);
					el.setState(helder.dom.ElementState.HOVER, false);
					styles.forget(subtree(el));
				}
			}
			walk(d.documentElement, -1, false);
		}
		var entries = [];
		for (g in 0...helder.css.CssGroups.COUNT) for (p in helder.css.CssProperties.members[g]) {
			var t = initials[g].terms(cast p);
			if (t != null) entries.push({name: "i\t" + helder.css.CssProperties.name(cast p), specified: helder.css.CssTerm.CssSpecified.Terms(t), of: null});
		}
		for (i in 0...list.length) for (g in 0...helder.css.CssGroups.COUNT) {
			var grp = @:privateAccess list[i].group(g);
			if (grp == initials[g]) continue;
			for (p in helder.css.CssProperties.members[g]) {
				var t = grp.terms(cast p), ti = initials[g].terms(cast p);
				if (helder.css.CssIntern.key(t) != helder.css.CssIntern.key(ti))
					entries.push({name: 's$i\t' + helder.css.CssProperties.name(cast p), specified: helder.css.CssTerm.CssSpecified.Terms(t), of: null});
			}
		}
		for (k => i in keys) entries.push({name: "k\t" + k, specified: helder.css.CssTerm.CssSpecified.Terms([helder.css.CssTerm.CssTerm.Number(i, true)]), of: null});
		return helder.css.CssSheetData.encodeInitials(entries);
	}

	// (a first frame made, then rows added and a frame: RUNS times)
	static function addRows<T>(op:String, make:Void->{ui:Ui, doc:Null<DocumentNode>, keep:T}, add:{ui:Ui, doc:Null<DocumentNode>, keep:T}->Void) {
		var times = [], updates = [], draws = [], styles = [], layouts = [], paints = [], bytes = [];
		var heap = 0.0;
		for (_ in 0...RUNS) {
			var x = make();
			step(x.ui, x.doc);
			var h0 = live();
			var e0 = engine(x.doc);
			var b0 = GcStats.bytes(), t0 = Timer.stamp();
			add(x);
			var a = (Timer.stamp() - t0) * 1000;
			var s = step(x.ui, x.doc);
			bytes.push(GcStats.bytes() - b0);
			times.push(a + s[0] + s[1]);
			updates.push(a + s[0]);
			draws.push(s[1]);
			var e1 = engine(x.doc);
			styles.push(e1[0] - e0[0]);
			layouts.push(e1[1] - e0[1]);
			paints.push(e1[2] - e0[2]);
			heap = live() - h0;
		}
		report(op, times, updates, draws, styles, layouts, paints, bytes, 0, {heap: Math.round(heap)});
	}

	// (both screens drawn, for the report: bin/document-bench/<screen>-<variant>.png)
	static function snapshots<A>(w:Int, h:Int, mount:Void->{ui:Ui, app:A}, mountDoc:Void->{ui:Ui, doc:Null<DocumentNode>, keep:Document}) {
		sys.FileSystem.createDirectory("bin/document-bench");
		var a = mount().ui;
		step(a, null);
		sys.io.File.saveBytes('bin/document-bench/$screen-helder.ui.png', crop(w, h));
		var b = mountDoc();
		step(b.ui, b.doc);
		sys.io.File.saveBytes('bin/document-bench/$screen-engine.png', crop(w, h));
	}

	// (the frame's top left w by h, as a PNG)
	static function crop(w:Int, h:Int):Bytes {
		var out = Bytes.alloc(w * h * 4);
		for (y in 0...h) out.blit(y * w * 4, pixels, y * frame.width * 4, w * 4);
		return helder.image.PngEncoder.encode(out, w, h);
	}

	static function byTag(d:Document, tag:String):Element {
		var n:Null<helder.dom.Node> = d.documentElement;
		while (n != null) {
			if (n.nodeType == helder.dom.Node.ELEMENT_NODE && (cast n : Element).getAttribute("data-tag") == tag) return cast n;
			n = next(n);
		}
		throw 'no $tag';
	}

	static function next(n:helder.dom.Node):Null<helder.dom.Node> {
		if (n.firstChild != null) return n.firstChild;
		while (n != null) {
			if (n.nextSibling != null) return n.nextSibling;
			n = n.parentNode;
		}
		return null;
	}

	// (an element's first box in the node: x, y, width, height in the window)
	static function rectOf(doc:DocumentNode, el:Element):Array<Float> {
		var f = doc.view.fragments, id = doc.view.fragmentOf(doc.view.boxesOf(el)[0]);
		if (id < 0) return [0, 0, 0, 0];
		var p = f.absolute(id);
		return [doc.absX + p.x, doc.absY + p.y, f.width(id), f.height(id)];
	}

	// (the list's rows past the first `from`)
	static function rowsOf(root:MirrorNode, tag:String, from:Int):Array<MirrorNode> {
		function find(n:MirrorNode):Null<MirrorNode> {
			if (n.tag == tag) return n;
			for (c in n.children) {
				var f = find(c);
				if (f != null) return f;
			}
			return null;
		}
		return find(root).children.slice(from);
	}

	static function appendRows(d:Document, list:Element, rows:Array<MirrorNode>) {
		for (r in rows) list.appendChild(element(d, r));
	}

	// (the engine's screen as an app has it: its tree built in code, styled by
	// app.css and the screen's sheet, both compiled at build time: no parser)
	static function engineNode(d:Document):DocumentNode
		return screen == "todo" ? helder.ui.box.DocumentApp.node(d, [CssUserAgentTheme.app(), CssTheme.file("document/todo.css")])
			: helder.ui.box.DocumentApp.node(d, [CssUserAgentTheme.app(), CssTheme.file("document/mail.css")]);

	static function build(m:Mirror):Document {
		var d = new Document();
		d.append(element(d, m.root));
		return d;
	}

	static function element(d:Document, n:MirrorNode):Element {
		var e = d.createElement(n.tag);
		for (a in n.attrs) e.setAttribute(a[0], a[1]);
		if (n.text != null) e.append(d.createTextNode(n.text));
		for (c in n.children) e.appendChild(element(d, c));
		return e;
	}

	// (the screen's sheet: the mirrors' classes, sorted; the checked-in one the same, else stale)
	static function sheetText(ms:Array<Mirror>):String {
		var rules = new Map<String, String>();
		for (m in ms) for (k => v in m.rules) rules.set(k, v);
		var keys = [for (k in rules.keys()) k];
		keys.sort(Reflect.compare);
		return HEADER + [for (k in keys) '$k { ${rules[k]} }\n'].join("");
	}

	static function fresh(name:String, ms:Array<Mirror>) {
		var file = 'tests/bench/document/$name.css';
		var have = sys.FileSystem.exists(file) ? sys.io.File.getContent(file) : "";
		if (have != sheetText(ms)) throw '$file is stale (the screen changed): DocumentBench sheets writes it again';
	}

	// (the window's height; the screen's top box shrinks to it: helder.ui's
	// Layout lets it, where CSS's automatic minimum height of a flex item
	// keeps its content's, a port difference this says)
	static final HEADER = ":root { height: 100% } :root > *, :root > * > * { min-height: 0 }\n";

	// (a string's FNV-1a hash, as a class name's hex)
	static function hash(s:String):String {
		var h = 0x811c9dc5;
		for (i in 0...s.length) h = (h ^ StringTools.fastCodeAt(s, i)) * 0x01000193;
		return StringTools.hex(h, 8).toLowerCase();
	}

	// ---- the mirror: a helder.ui tree as a helder.dom document (AppUaCheck's,
	// with what it draws: backgrounds, borders, radii, opacity, colours), and
	// each node whose look changes when hovered as a :hover rule

	static function mirror(ui:Ui):Mirror {
		var rules = new Map<String, String>(), count = 0, hovers = 0;
		// (each kind of node's look hovered, probed once: its slot, variant, size and state)
		var kinds = new Map<String, Null<String>>(), fastKinds = new Map<String, Null<helder.ui.fast.Style.StyleProps>>();
		function node(n:Node):MirrorNode {
			count++;
			var tag = n.tag == "textfield" ? "field" : n.tag == null || n.tag == "" ? "view" : n.tag;
			if (!~/^[a-z][a-z0-9-]*$/.match(tag)) tag = "view";
			var attrs = [], classes = [];
			if (n.tag != null && n.tag != "") attrs.push(["data-tag", n.tag]);
			if (n.slot != null) attrs.push(["slot", n.slot]);
			if (n.variant != null) attrs.push(["variant", n.variant]);
			// (its own style as a class of the screen's sheet)
			var style = declarations(n);
			if (style != "") {
				var c = "s" + hash(style);
				rules.set('.$c', style);
				classes.push(c);
			}
			if (n.slot != null) {
				var kind = '${n.slot}-${n.variant}-${n.size}-${n.attr("data-state")}';
				if (!kinds.exists(kind)) {
					var look = hoverLook(ui, n);
					kinds.set(kind, look);
					if (look != null) {
						hovers++;
						rules.set('.h${hash(look)}:hover', look);
					}
				}
				var look = kinds.get(kind);
				if (look != null) classes.push('h${hash(look)}');
			}
			if (classes.length > 0) attrs.push(["class", classes.join(" ")]);
			var text = Std.isOfType(n, TextNode) ? (cast n : TextNode).text : null;
			// (the fast variant's: its look as a fast style, hovered as a variant)
			var hover = null;
			if (n.slot != null) {
				var kind = '${n.slot}-${n.variant}-${n.size}-${n.attr("data-state")}';
				if (!fastKinds.exists(kind)) fastKinds.set(kind, FastMirror.hovered(ui, n));
				hover = fastKinds.get(kind);
			}
			return {tag: tag, attrs: attrs, text: text, children: [for (c in n.children) node(c)], style: helder.ui.fast.Style.of(FastMirror.props(n, hover))};
		}
		var root:MirrorNode = {tag: "root", attrs: [], text: null, children: [for (c in ui.root.children) node(c)]};
		return {root: root, rules: rules, nodes: count, hovers: hovers};
	}

	static function esc(s:String):String
		return s.replace("&", "&amp;").replace("<", "&lt;").replace('"', "&quot;");

	// (its background, colour and border colour while hovered, where they differ: CSS)
	static function hoverLook(ui:Ui, n:Node):Null<String> {
		if (n.slot == null) return null;
		var s = n.style, bg = s.background, fg = n.textColor(), bc = s.borderColor;
		@:privateAccess n.setState(true, false, false);
		ui.update();
		var out = [];
		if (s.background != bg) out.push('background-color: ${color(s.background)} !important');
		if (n.textColor() != fg) out.push('color: ${color(n.textColor())} !important');
		if (s.borderColor != bc) out.push('border-color: ${color(s.borderColor)} !important');
		@:privateAccess n.setState(false, false, false);
		ui.update();
		return out.length == 0 ? null : out.join("; ");
	}

	// (AppUaCheck's declarations, and what is drawn)
	static function declarations(n:Node):String {
		var s = n.style, out = [@:privateAccess AppUaCheck.declarations(n)];
		if (s.borderColor.a > 0) out.push('border-color: ${color(s.borderColor)}');
		if (s.borderRadius > 0) out.push('border-radius: ${s.borderRadius}px');
		if (s.opacity < 1) out.push('opacity: ${s.opacity}');
		var c = n.textColor();
		if (n.parent != null && c != n.parent.textColor()) out.push('color: ${color(c)}');
		return [for (o in out) if (o != "") o].join("; ");
	}

	static function color(c:Color):String
		return @:privateAccess AppUaCheck.color(c);

	// (a screen of 1,020 rows drawn, held; its live heap printed, then held
	// until a line on stdin: tests/bench/document.mjs reads its RSS meanwhile)
	static var held:Dynamic = null;

	static function memory(name:String, what:String) {
		var w = name == "todo" ? 480 : 860, h = 560;
		var base = live();
		var ui = new Ui(new DrawText(), w, h);
		if (what == "engine") {
			// (the mirror made by helder.ui, let go before the engine's screen is)
			var m = name == "todo" ? todoMirror(1020) : mailMirror(1020);
			var b2 = live();
			screen = name;
			var d = build(m);
			var node = engineNode(d);
			node.style.flexGrow = 1;
			ui.root.append(node);
			step(ui, node);
			base = b2;
			held = node;
		} else if (what == "boxes") {
			var m = name == "todo" ? todoMirror(1020) : mailMirror(1020);
			var b2 = live();
			screen = name;
			var bb = new BoxScreen.BoxBuild(new BoxScreen.BoxStyles(boxData[name])), out = [];
			bb.box(m.root, null, out);
			var node = new BoxScreen.BoxNode(out[0], bb.contexts);
			node.style.flexGrow = 1;
			ui.root.append(node);
			step(ui, null);
			base = b2;
			held = node;
		} else {
			if (name == "todo") {
				ui.theme = Todo.sheet;
				var app = new Todo();
				app.todos([for (i in 0...1020) new Item('Task ${i + 1}: water the plants and call back')]);
				Render.render(app.view(), ui.root);
				held = app;
			} else {
				if (!declared) Mail.declare();
				declared = true;
				var app = new Mail();
				// (light, whatever the machine's appearance: the screen's sheet is checked in)
				app.dark(false);
				app.messages(mailMessages(1020));
				var root = new Node();
				root.theme = Mail.sheet;
				root.style.flexGrow = 1;
				ui.root.append(root);
				Render.render(app.view(), root);
				held = app;
			}
			Graph.flush();
			step(ui, null);
		}
		Sys.println(haxe.Json.stringify({screen: name, variant: what, memory: true, heap: Math.round(live() - base)}));
		Sys.stdin().readLine();
		held = ui;
	}

	static function todoMirror(n:Int):Mirror {
		var ui = new Ui(new DrawText(), 480, 560);
		ui.theme = Todo.sheet;
		var app = new Todo();
		app.todos([for (i in 0...n) new Item('Task ${i + 1}: water the plants and call back')]);
		Render.render(app.view(), ui.root);
		Graph.flush();
		ui.update();
		return mirror(ui);
	}

	static function mailMirror(n:Int):Mirror {
		var ui = new Ui(new DrawText(), 860, 560);
		if (!declared) Mail.declare();
		declared = true;
		var app = new Mail();
		// (light, whatever the machine's appearance: the screen's sheet is checked in)
		app.dark(false);
		app.messages(mailMessages(n));
		var root = new Node();
		root.theme = Mail.sheet;
		root.style.flexGrow = 1;
		ui.root.append(root);
		Render.render(app.view(), root);
		Graph.flush();
		ui.update();
		return mirror(ui);
	}

	static function mailMessages(n:Int):Array<Message>
		return [
			for (i in 0...n)
				new Message('Sender ${i % 37}', 'Subject number ${i} about the weekly report', 'Body ${i}', "Inbox", 1 + i % 28, i % 3 == 0)
		];

	// ---- documents

	static function document(path:String, sheetsPath:Null<String>, name:String) {
		screen = name;
		variant = "engine";
		var html = sys.io.File.getContent(path);
		var files:haxe.DynamicAccess<String> = sheetsPath == null ? {} : haxe.Json.parse(sys.io.File.getContent(sheetsPath));
		var canonical = ~/<link[^>]*rel="?canonical"?[^>]*href="([^"]+)"/;
		var url = canonical.match(html) ? canonical.matched(1) : 'file://$path';
		var load = (u:String) -> files.exists(u) ? sys.io.File.getContent(files[u]) : null;
		var w = 1024, h = 768;
		page(html, url, load, w, h, null);
	}

	static function sample() {
		screen = "sample";
		variant = "engine";
		page(SamplePage.HTML, "https://example.com/sample.html", _ -> null, 1024, 768, SamplePage.image);
	}

	static function page(html:String, url:String, load:String->Null<String>, w:Int, h:Int, image:Null<String->Null<helder.canvas.Bitmap>>) {
		var parse = 0.0;
		function make():{ui:Ui, doc:Null<DocumentNode>, keep:Node} {
			var ui = new Ui(new DrawText(), w, h);
			var t0 = Timer.stamp();
			var d = Dom.parse(html);
			parse = (Timer.stamp() - t0) * 1000;
			var node = DocumentNode.html(d, {url: url, load: load, image: image});
			var sc = new Node("scroll");
			sc.style.overflow = Scroll;
			sc.style.flexGrow = 1;
			sc.style.minHeight = 0;
			sc.append(node);
			ui.root.append(sc);
			return {ui: ui, doc: node, keep: sc};
		}
		var made = first("load to the first frame", make);
		var ui = made.ui, doc = made.doc, sc = made.keep;
		var v = doc.view;
		Sys.println(haxe.Json.stringify({
			screen: screen,
			parse: round(parse),
			elements: count(v.document),
			boxes: v.tree.count,
			fragments: v.fragments.count,
			height: Math.round(doc.height)
		}));
		// (down 100 px a frame for 300 frames, then back and forth over what was recorded)
		// (the pointer over the page as it scrolls, as a person's is: what is under it changes)
		ui.pointerMove(500, 400);
		step(ui, doc);
		var p0 = doc.stats.paints, pm0 = doc.stats.paintMs;
		run("scroll, 100 px a frame", ui, doc, Std.parseInt(Sys.getEnv("SCROLLS") ?? "300"), i -> ui.wheel(500, 400, 0, 100));
		Sys.println(haxe.Json.stringify({screen: screen, scrollPaints: doc.stats.paints - p0, scrollPaintMs: round(doc.stats.paintMs - pm0), restyles: doc.stats.restyles}));
		if (Sys.getEnv("ONLY_SCROLL") != null) return;
		run("scroll back and forth 40 px", ui, doc, 120, i -> ui.wheel(500, 400, 0, i % 20 < 10 ? 40 : -40));
		run("jump 20,000 px", ui, doc, 30, i -> ui.scrollTo(sc, 0, (sc.scrollY + 20000) % Math.max(1, doc.height - h)));
		ui.scrollTo(sc, 0, 0);
		step(ui, doc);
		// (the links in view hovered in turn: each a restyle and a repaint)
		var links = [];
		var f = v.fragments;
		for (id in 0...f.count) {
			var n = helder.ui.box.BoxTree.nodeOf(f.box(id));
			if (n == null || n.nodeType != helder.dom.Node.TEXT_NODE || n.parentNode == null || n.parentNode.nodeName != "A") continue;
			var p = f.absolute(id);
			if (p.y > 20 && p.y < h - 40 && f.width(id) > 4) links.push([p.x + 2, p.y + f.height(id) / 2]);
			if (links.length >= 12) break;
		}
		var r0 = doc.stats.rasters;
		if (links.length > 0) run("hover links", ui, doc, Std.parseInt(Sys.getEnv("HOVERS") ?? "120"), i -> ui.pointerMove(links[i % links.length][0], links[i % links.length][1]), {links: links.length});
		Sys.println(haxe.Json.stringify({screen: screen, rastersPerHover: (doc.stats.rasters - r0) / 120}));
		ui.pointerMove(w - 5, h - 5);
		step(ui, doc);
		run("resize 1024 ↔ 900 wide", ui, doc, 20, i -> ui.resize(i % 2 == 0 ? 900 : 1024, h));
		ui.resize(w, h);
		step(ui, doc);
		Sys.println(haxe.Json.stringify({screen: screen, heapAfter: Math.round(live()), fragmentsAfter: v.fragments.count}));
	}

	static function count(d:Document):Int {
		var n:Null<helder.dom.Node> = d.documentElement, k = 0;
		while (n != null) {
			if (n.nodeType == helder.dom.Node.ELEMENT_NODE) k++;
			n = next(n);
		}
		return k;
	}
}

// (a helder.ui tree as the elements to make: tag, attributes, text, children)
private typedef MirrorNode = {tag:String, attrs:Array<Array<String>>, text:Null<String>, children:Array<MirrorNode>, ?style:helder.ui.fast.Style};
private typedef Mirror = {root:MirrorNode, rules:Map<String, String>, nodes:Int, hovers:Int};
