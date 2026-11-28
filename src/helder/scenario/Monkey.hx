package helder.scenario;

#if !macro
import haxe.PosInfos;
import helder.os.headless.Inspector.InspectedNode;
import helder.scenario.Steps;
import helder.story.Stories;
import helder.test.Choices;
import helder.test.Gen;
import helder.test.Property;
import helder.test.Runner;
import helder.ui.*;
import helder.view.RootView;
import helder.view.graph.Atoms;
import helder.view.graph.Graph;
import helder.scenario.Steps.Step;
#end

// A UI monkey: a stateful property over the real program, booted as
// scenarios (helder.scenario). Each case is one of the program's
// scenarios in a screen and store of its own, in this process, not drawn:
// its environment drawn (size, dark, locale, text scale, start time, zone),
// the model's atoms given values of their types (atom), then steps drawn
// from what the screen shows (taps on its nodes, typing into its text
// fields, keys, scrolls, drags, resizes, idle time on its clock), each run
// as a scenario's step (Steps) and waited for, the invariants checked after
// each. A failure is shrunk (helder.test's choices) and written out as a
// scenario file (bin/test/monkey: move it beside the scenarios to open it
// in the studio), and reported with its steps.
//
//   Hosting.on = true;
//   App.main();
//   Hosting.on = false;
//   test("the app under a monkey", () -> Monkey.check({
//     from: Monkey.from("app.App_scenario"),
//     atoms: [Monkey.atom(App.rows), Monkey.atom(App.query)]
//   }, {cases: 40, limit: 20}));
//
// The invariants (except: their names left out):
// - throws: nothing a boot, a step or a settle throws; no request its http
//   fixtures do not answer; nothing done to the machine (each case is
//   sealed, helder.os.Seal: its trash, places, stores' files, an app's real
//   files refused, a refusal its failure even when the program catches it)
// - sizes: no NaN, infinite or negative box, offset or content size
// - window: what is shown and draws (content, a background), outside every
//   clipping box, laid out inside the
//   window (its layout's box: a transform's move, a sheet at a detent, is
//   the program's own)
// - settles: after each step its clock comes to rest (no frame asked for,
//   nothing animating, no timer due within a second) within a minute
// - steady: settled, a frame later nothing has moved and none is asked for
// - scrolls: a wheel to an end moves a scroller under it that way (the
//   innermost, or one around it: nested scrolling), unless all are there;
//   the innermost at its end, its last row shown
// - kept: idle time moves no scroll position and makes no node again;
//   typing moves no scroller around another field (but to its new end,
//   its content shorter) and keeps the field it types into
// - popups: an anchored popup is closed with its anchor gone, else at its
//   anchor (after any step: a resize, a scroll)
class Monkey {
	// a signal of the model given values of its type (Int, Float, Bool,
	// String, Array, Null, structures, enums, enum abstracts), or of gen,
	// written after a case's boot; its expression names it in the
	// scenario file
	public static macro function atom(signal:haxe.macro.Expr, ?gen:haxe.macro.Expr):haxe.macro.Expr
		return MonkeyMacro.atom(signal, gen);

	// the scenarios cases start from: a scenario module's ("app.App_scenario")
	// or the scenarios given, each named in the scenario file by its path
	public static macro function from(rest:Array<haxe.macro.Expr>):haxe.macro.Expr
		return MonkeyMacro.from(rest);

	#if !macro
	// (the invariants by name)
	public static final INVARIANTS = ["throws", "sizes", "window", "settles", "steady", "scrolls", "kept", "popups"];

	// (texts typed, unless given, and a String atom's: short words, runs of
	// any characters (right to left, emoji, combining marks, line breaks),
	// a huge name (one word, nowhere to break), sometimes long)
	public static final TEXTS:Gen<String> = oneOf([pick(["", "a", "Name"]), string(null, 0, 40), string(pick(["a", "W", "m", "中", "😀", "ש"]), 40, 300),
		string(null, 40, 600)]);
	// (keys pressed; the editing keys side by side, early: a shrink lowering
	// one finds the other, its search over the list's order)
	static final KEYS = ["Enter", "Backspace", "Delete", "Escape", "Tab", "Space", "ArrowDown", "ArrowUp", "ArrowLeft", "ArrowRight", "Home", "End", "a"];
	// (sizes a case may have, a phone's, a tablet's, a laptop's, tiny, huge)
	static final SIZES = [[390, 844], [820, 1180], [1280, 800], [320, 240], [2560, 1440], [1100, 700], [240, 180]];
	static final LOCALES = ["nl-BE", "ar-EG", "he-IL", "ja-JP", "de-DE", "en-GB"];
	static final ZONES = ["+05:30", "-08:00", "+14:00", "-12:00", "+01:00"];
	static final SCALES = [0.85, 1.3, 2.0, 3.0];
	// (roles a tap mostly lands on)
	static final ACTIVE = ["button", "link", "checkbox", "switch", "radio", "tab", "menuitem", "menuitemcheckbox", "menuitemradio", "option",
		"combobox", "textbox", "slider", "treeitem", "row", "gridcell", "listitem", "spinbutton"];
	static final FIELDS = ["textbox", "combobox", "searchbox"];

	// the program run by a monkey: its cases' failures shrunk, the smallest
	// reported and written out as a scenario file
	public static function check(def:MonkeyDef, ?options:PropertyOptions, ?pos:PosInfos) {
		var m = new Monkey(def, pos);
		@:privateAccess Property.check(c -> c, c -> m.once(c), null, options, pos);
		m.write();
	}

	// the smallest failing case found (null: none), not a test's failure:
	// a monkey's own tests, or a caller that reports it its own way
	public static function find(def:MonkeyDef, ?options:PropertyOptions, ?pos:PosInfos):Null<Found> {
		var m = new Monkey(def, pos);
		var checks = @:privateAccess Runner.checks, outer = @:privateAccess Runner.capture;
		@:privateAccess Runner.capture = [];
		var r = try @:privateAccess Property.search(c -> c, c -> m.once(c), options ?? {}, Property.key(pos)) catch (e:haxe.Exception) {
			@:privateAccess Runner.capture = outer;
			throw helder.async.Errors.kept(e);
		}
		@:privateAccess Runner.capture = outer;
		@:privateAccess Runner.checks = checks;
		// (none run: a replay whose steps no longer resolve says nothing, not that it holds)
		if (r.failed == null && r.cases == 0 && r.rejected > 0) throw 'helder.scenario.Monkey: every case rejected (${r.rejected}): a scenario\'s step that no longer resolves, a replay too short';
		if (r.failed == null) return null;
		m.write();
		return m.best;
	}

	final def:MonkeyDef;
	final pos:PosInfos;
	final root:RootView;
	final text:TextEngine;
	final except:Array<String>;
	final most:Int;
	final minW:Int;
	final minH:Int;
	// (the smallest failing case: its choices, what it wrote)
	var best:Null<Found> = null;
	var bestValues:Null<Array<Int>> = null;
	// (each root's <Surface>'s size, once)
	var surface:Null<{width:Null<Int>, height:Null<Int>, title:Null<String>}> = null;

	function new(def:MonkeyDef, pos:PosInfos) {
		if (def.from.length == 0) throw "helder.scenario.Monkey: no scenarios to start from";
		var r = def.root ?? Hosting.root;
		if (r == null) throw "helder.scenario.Monkey: the program's main gave UiWindow.run no root (Hosting.on before its main)";
		this.def = def;
		this.pos = pos;
		root = r;
		var names = INVARIANTS.concat([for (k in def.checks ?? []) k.name]);
		for (e in def.except ?? [])
			if (!names.contains(e)) throw 'helder.scenario.Monkey: no invariant "$e" (${names.join(", ")})';
		except = def.except ?? [];
		most = def.steps ?? 20;
		var least = def.smallest ?? [240, 180];
		minW = least[0];
		minH = least[1];
		text = helder.ui.TextEngines.standard();
	}

	inline function on(name:String):Bool
		return !except.contains(name);

	// --- a case

	function once(c:Choices) {
		// (a preview host's, as the studio's is for its whole run: what the
		// program renders reads it, and makes the files it shows in memory
		// (the viewer's Sandbox), never the machine's)
		var hosting = Hosting.on;
		Hosting.on = true;
		try run(c) catch (e:haxe.Exception) {
			Hosting.on = hosting;
			throw helder.async.Errors.kept(e);
		}
		Hosting.on = hosting;
	}

	function run(c:Choices) {
		messages.resize(0);
		var base = c.draw(pick(def.from));
		var env = c.draw(environment(minW, minH));
		var writes = [for (a in def.atoms ?? []) if (c.draw(bool())) {atom: a, value: c.draw(a.gen)}];
		var sc = scenario(base, env, writes, []);
		var w = sc.width ?? size().width ?? Stories.WIDTH, h = sc.height ?? size().height ?? Stories.HEIGHT;
		var s = new Screen(sc, root, text, w, h);
		var done:Array<Step> = [], control:Null<haxe.Exception> = null;
		try {
			s.mount();
			// (its own steps first, as its file runs them)
			for (step in base.scenario.steps) {
				// (written for its own environment: one that does not resolve in the one drawn is no case)
				try s.act(step) catch (e:StepError) throw new Rejected();
				done.push(step);
			}
			if (ok(s, null)) for (_ in 0...most) {
				var step = c.draw(next(s));
				if (step == null) break;
				c.note(code(step));
				var before = Snapshot.of(s);
				before.field = step.kind == "type" ? s.node(step.query) : null;
				// (drawn from the screen, it resolves; replayed after an edit
				// of the case (shrinking), one that does not is no case)
				// (kept before it runs: one that throws is the file's last)
				done.push(step);
				try s.act(step) catch (e:StepError) throw new Rejected();
				if (!ok(s, {step: step, before: before})) break;
			}
			// (its end, as its still: the pointer gone, settled)
			if (failed() == 0) {
				s.leave();
				ok(s, null);
			}
		} catch (e:haxe.Exception) {
			// (a replayed case run out, or rejected: the property's, not a failure)
			if (Std.isOfType(e, Overran) || Std.isOfType(e, Rejected)) control = e else fail("throws", @:privateAccess Runner.error(e));
		}
		try s.dispose() catch (e:haxe.Exception) {
			fail("throws", 'letting the screen go threw: ${@:privateAccess Runner.error(e)}');
		}
		if (control != null) {
			@:privateAccess Runner.capture.resize(0);
			throw control;
		}
		if (failed() == 0) return;
		// (a finding still open (known): no case of this run's, the rest going on)
		var why = messages[0] ?? "";
		if (Lambda.exists(def.known ?? [], k -> why.indexOf(k.failure) >= 0)) {
			@:privateAccess Runner.capture.resize(0);
			throw new Rejected();
		}
		// (another invariant broken while shrinking: not the failure being shrunk)
		if (target != null && first != target) {
			@:privateAccess Runner.capture.resize(0);
			throw new Rejected();
		}
		target = first;
		keep(c, base, env, writes, done);
	}

	// (the case's environment: each field its scenario's unless drawn)
	static function environment(w:Int, h:Int):Gen<Environment>
		return c -> {
			size: c.draw(bool()) ? c.draw(oneOf([pick(SIZES.filter(s -> s[0] >= w && s[1] >= h)), c -> [c.draw(int(w, 2000)), c.draw(int(h, 1400))]])) : null,
			dark: c.draw(pick([null, true, false])),
			locale: c.draw(bool()) ? c.draw(pick(LOCALES)) : null,
			textScale: c.draw(bool()) ? c.draw(pick(SCALES)) : null,
			// (1970 to 2100, its edges and ordinary days)
			time: c.draw(bool()) ? c.draw(int(-3650, 47000)) * 86400000.0 + c.draw(int(0, 86399)) * 1000.0 : null,
			zone: c.draw(bool()) ? c.draw(pick(ZONES)) : null
		};

	// (the next step drawn from what the screen shows; null: the case ends)
	function next(s:Screen):Gen<Null<Step>>
		return c -> {
			if (!c.weighted(1 - 1 / most)) return null;
			var shown = s.inspect(), kinds = ["tap", "press", "wait", "resize"];
			// (what a tap at its centre reaches: a node another covers is no tap's)
			var tappable = [for (n in shown.nodes) if (n.role != null && ACTIVE.contains(n.role) && s.reached(n)) n];
			var named = [for (n in shown.nodes) if ((n.role != null || n.label != null || n.text != null || n.identifier != null) && s.reached(n)) n];
			var fields = [for (n in shown.nodes) if (n.role != null && FIELDS.contains(n.role) && s.reached(n)) n];
			var views = s.scrollers();
			if (fields.length > 0) kinds.push("type");
			if (views.length > 0) kinds.push("scroll");
			if (shown.nodes.length > 0) kinds.push("drag");
			if (named.length == 0) kinds.remove("tap");
			switch c.draw(pick(kinds)) {
				case "tap":
					var from = tappable.length > 0 && c.draw(int(0, 3)) > 0 ? tappable : named;
					Steps.tap(s.query(c.draw(pick(from))));
				case "type": Steps.type(s.query(c.draw(pick(fields))), c.draw(def.texts ?? TEXTS));
				case "press": Steps.press(c.draw(pick(KEYS)));
				case "scroll":
					var v = c.draw(pick(views));
					Steps.scroll(s.place(v), c.draw(oneOf([pick(["end", "start"]), int(-600, 600).map(v -> (v : Dynamic))])));
				case "drag":
					var n = c.draw(pick(shown.nodes));
					Steps.drag(s.query(n), {dx: c.draw(int(-300, 300)), dy: c.draw(int(-300, 300))});
				case "resize": Steps.resize(c.draw(int(minW, 2000)), c.draw(int(minH, 1400)));
				case _: Steps.wait(c.draw(pick([0.5, 2, 10, 61])));
			}
		};

	// --- the invariants

	// (after a step (null: boot, the end) and settling: whether they all held)
	function ok(s:Screen, after:Null<{step:Step, before:Snapshot}>):Bool {
		var seal = s.context.seal;
		if (seal != null && seal.refused.length > 0) fail("throws", '${at(after)}${seal.refused[0]}');
		// (moving by design now, its own say: an animation that loops, a video playing)
		var endless = def.animates != null && s.context.run(def.animates);
		if (!s.settled && on("settles") && !endless) fail("settles", '${at(after)}it never settles: ${s.pending()} after a minute of its clock');
		if (s.missed != null) fail("throws", '${at(after)}${s.missed}');
		if (failed() > 0) return false;
		var now = Snapshot.of(s);
		if (on("sizes")) for (n in now.nodes) {
			var b = n.box;
			var finite = true;
			for (x in [b.x, b.y, b.width, b.height, n.node.contentWidth, n.node.contentHeight, n.node.scrollX, n.node.scrollY])
				if (!Math.isFinite(x)) finite = false;
			if (!finite || b.width < 0 || b.height < 0) {
				fail("sizes", '${at(after)}${describe(n.node)} is ${b.x}, ${b.y}, ${b.width} × ${b.height} (content ${n.node.contentWidth} × ${n.node.contentHeight}, scrolled ${n.node.scrollX}, ${n.node.scrollY})');
				break;
			}
		}
		if (on("window")) for (n in now.nodes) {
			// (what draws: its content (a text, an image), else a background; an empty box draws nothing)
			if (n.clipped || !n.shown || !(n.node.hasContent() || n.node.used.backgroundColor >>> 24 > 0)) continue;
			// (its layout's box: a transform's move is the program's own (a sheet at a detent, a drawer), not an overflow)
			var b = n.laid, e = 0.5;
			if (b.x < -e || b.y < -e || b.x + b.width > s.ui.width + e || b.y + b.height > s.ui.height + e) {
				fail("window", '${at(after)}${describe(n.node)} at ${r(b.x)}, ${r(b.y)}, ${r(b.width)} × ${r(b.height)} is outside the window (${s.ui.width} × ${s.ui.height})');
				break;
			}
		}
		if (on("popups")) for (p in s.popups()) {
			var a = p.anchor;
			if (a == null || !(p.placement == Below || p.placement == Above || p.placement == Left || p.placement == Right)) continue;
			if (!s.attached(a)) {
				fail("popups", '${at(after)}${describe(p)} is open, its anchor ${describe(a)} gone');
				break;
			}
			var ab = a.windowBounds(), pb = p.windowBounds(), g = p.gap + 2;
			var inView = ab.x < s.ui.width && ab.y < s.ui.height && ab.x + ab.width > 0 && ab.y + ab.height > 0;
			if (inView && (pb.x > ab.x + ab.width + g || pb.x + pb.width < ab.x - g || pb.y > ab.y + ab.height + g || pb.y + pb.height < ab.y - g)) {
				fail("popups", '${at(after)}${describe(p)} at ${r(pb.x)}, ${r(pb.y)} is away from its anchor ${describe(a)} at ${r(ab.x)}, ${r(ab.y)}, ${r(ab.width)} × ${r(ab.height)}');
				break;
			}
		}
		if (after != null && on("scrolls") && after.step.kind == "scroll" && (after.step.to == "end" || after.step.to == "start")) {
			var end = after.step.to == "end", under = after.before.under(after.step);
			// (nested scrollers: the wheel may go to one around the innermost first, by design (a large
			// title collapsing): one of those under it moves that way, unless all are there already)
			var moved = false, there = true, inner:Null<{node:Node, offsetY:Float}> = null;
			for (v in under) {
				var sv = s.view(v.node);
				if (sv == null) continue;
				var far = Math.max(0, sv.contentHeight - sv.height);
				if (end ? sv.offsetY > v.offsetY + 0.5 : sv.offsetY < v.offsetY - 0.5) moved = true;
				if (Math.abs(v.offsetY - (end ? Math.max(0, v.contentHeight - v.height) : 0)) > 1) there = false;
				inner = v;
			}
			if (inner != null && !moved && !there) fail("scrolls", '${at(after)}${describe(inner.node)} and the scrollers around it did not move toward their ${end ? "end" : "start"}');
			else if (inner != null && end) {
				var sv = s.view(inner.node), last = s.last(inner.node);
				if (sv != null && last != null && Math.abs(sv.offsetY - Math.max(0, sv.contentHeight - sv.height)) <= 1) {
					var lb = last.windowBounds();
					if (lb.y + lb.height > sv.y + sv.height + 1) fail("scrolls", '${at(after)}${describe(inner.node)} is at its end, but its last row ${describe(last)} ends at ${r(lb.y + lb.height)}, below it (${r(sv.y + sv.height)})');
				}
			}
		}
		if (after != null && on("kept")) kept(s, after.step, after.before, now);
		if (failed() > 0) return false;
		if (on("steady") && !endless) {
			s.frame();
			var later = Snapshot.of(s);
			for (n in now.nodes) {
				var b = n.box, l = later.box(n.node);
				if (l == null) {
					fail("steady", '${at(after)}${describe(n.node)} is gone a frame after settling');
					break;
				}
				if (Math.abs(l.x - b.x) > 0.01 || Math.abs(l.y - b.y) > 0.01 || Math.abs(l.width - b.width) > 0.01 || Math.abs(l.height - b.height) > 0.01) {
					fail("steady", '${at(after)}${describe(n.node)} moved a frame after settling: ${r(b.x)}, ${r(b.y)}, ${r(b.width)} × ${r(b.height)} to ${r(l.x)}, ${r(l.y)}, ${r(l.width)} × ${r(l.height)}');
					break;
				}
			}
			if (failed() == 0 && s.ui.needsFrame) fail("steady", '${at(after)}settled, it asks for a frame again with nothing changed');
		}
		for (k in def.checks ?? [])
			if (failed() == 0 && on(k.name)) {
				var why = s.context.run(k.check);
				if (why != null) fail(k.name, '${at(after)}$why');
			}
		return failed() == 0;
	}

	// (kept: idle time moves no scroll position and makes nothing again;
	// typing keeps its field's focus and moves no scroller but one around
	// it, or one whose content it changed (a search's results))
	function kept(s:Screen, step:Step, before:Snapshot, now:Snapshot) {
		if (step.kind == "wait") {
			// (a node gone and one of its tag new in the same parent: made again)
			var gone = new haxe.ds.ObjectMap<Node, Array<String>>();
			for (n in before.nodes)
				if (now.box(n.node) == null && n.parent != null) {
					var tags = gone.get(n.parent) ?? [];
					tags.push(n.node.tag);
					gone.set(n.parent, tags);
				}
			for (n in now.nodes)
				if (before.box(n.node) == null && n.parent != null && (gone.get(n.parent) ?? []).contains(n.node.tag)) {
					fail("kept", '${at({step: step})}${describe(n.node)} was made again with nothing done');
					return;
				}
		}
		if (step.kind != "wait" && step.kind != "type") return;
		var field = step.kind == "type" ? s.ui.focus : null;
		// (a field that takes text: a read-only one, a document's code, takes no focus)
		// (a menu open before it: the tap that closes it goes no further, as the platforms' menus' do)
		var f = before.field, editable = f != null && f.editable() && !(f.accessText()?.readOnly ?? false) && !before.menu;
		if (step.kind == "type" && editable && !~/[\x00-\x1F\x7F]/.match(step.text) && (field == null || !field.takesText())) {
			fail("kept", '${at({step: step})}typing lost its field\'s focus (now ${field == null ? "none" : describe(field)})');
			return;
		}
		for (v in before.views) {
			var sv = s.view(v.node);
			if (sv == null) continue;
			if (field != null && v.node.contains(field)) continue;
			// (its content changed by what was typed, a search's results: where it starts is its own)
			if (Math.abs(sv.contentHeight - v.contentHeight) > 0.5 || Math.abs(sv.contentWidth - v.contentWidth) > 0.5) continue;
			var far = Math.max(0, sv.contentHeight - sv.height);
			var moved = Math.abs(sv.offsetY - v.offsetY) > 0.5 || Math.abs(sv.offsetX - v.offsetX) > 0.5;
			var clamped = v.offsetY > far && Math.abs(sv.offsetY - far) <= 0.5;
			if (moved && !clamped) {
				fail("kept", '${at({step: step})}${describe(v.node)} scrolled from ${r(v.offsetY)} to ${r(sv.offsetY)} (${step.kind == "wait" ? "with nothing done" : "typing elsewhere"})');
				return;
			}
		}
	}

	// --- reporting

	function failed():Int {
		var c = @:privateAccess Runner.capture;
		return c == null ? 0 : c.length;
	}

	function fail(kind:String, message:String) {
		if (messages.length == 0) first = kind;
		messages.push(message);
		@:privateAccess Runner.failure(message, pos);
	}

	// (the case's failures, without their place; its first's invariant, and
	// the one the smallest failing case broke: shrinking keeps to it)
	final messages:Array<String> = [];
	var first = "";
	var target:Null<String> = null;

	static function at(after:Null<{step:Step}>):String
		return after == null ? "" : 'after ${code(after.step)}: ';

	static function r(v:Float):String
		return Std.string(Math.round(v * 10) / 10);

	// (a node as a failure names it: its tag, its text or label, where markup wrote it)
	public static function describe(n:Node):String {
		var what = Std.isOfType(n, TextNode) ? (cast n : TextNode).text : n.semantics?.label;
		if (what != null && what.length > 40) what = what.substr(0, 40) + "…";
		var out = n.tag + (what != null && what != "" ? ' ${Steps.quote(what)}' : ""), up = [], a = n.parent;
		while (a != null && a.parent != null && up.length < 4) {
			up.unshift(a.tag);
			a = a.parent;
		}
		if (up.length > 0) out += ' in ${up.join("/")}';
		#if ((hxmc.dev || helder.headless) && !macro)
		var src = n.source;
		if (src != null) out += ' (${src.file}:${src.line})';
		#end
		return out;
	}

	// (a failing case: kept when it is the smallest yet)
	function keep(c:Choices, base:Base, env:Environment, writes:Array<Write>, steps:Array<Step>) {
		var v:Array<Int> = @:privateAccess c.values;
		if (bestValues != null && !@:privateAccess Property.smaller(v, bestValues)) return;
		bestValues = v.copy();
		var failures = messages.copy();
		var sc = scenario(base, env, writes, steps);
		best = {
			file: path(),
			text: file(base, env, writes, steps, failures[0] ?? ""),
			failure: failures[0] ?? "",
			steps: [for (s in steps) code(s)],
			scenario: sc
		};
		c.note('written as ${best.file}');
	}

	// (where its file is written: beside the property store, by its test's file)
	function path():String {
		var dir = haxe.io.Path.directory(@:privateAccess Property.STORE);
		var name = haxe.io.Path.withoutDirectory(@:privateAccess Runner.file(pos.fileName)).split(".")[0];
		return haxe.io.Path.join([dir, "monkey", '$name.${pos.lineNumber}.scenario.hx']);
	}

	function write() {
		var b = best;
		if (b == null) return;
		try {
			sys.FileSystem.createDirectory(haxe.io.Path.directory(b.file));
			sys.io.File.saveContent(b.file, b.text);
		} catch (e:Dynamic) {}
	}

	// (the case as a scenario: its scenario's fields, the environment drawn over them)
	static function scenario(base:Base, env:Environment, writes:Array<Write>, steps:Array<Step>):Scenario {
		var b = base.scenario, boot = b.boot;
		var settings:helder.os.Settings.SettingsOverride = {
			textScale: env.textScale ?? b.settings.textScale,
			reducedMotion: b.settings.reducedMotion,
			reducedTransparency: b.settings.reducedTransparency,
			contrast: b.settings.contrast,
			orientation: b.settings.orientation
		};
		return new Scenario({
			name: StringTools.startsWith(b.name, "Monkey/") ? b.name : "Monkey/" + b.name,
			boot: boot == null && writes.length == 0 ? null : () -> {
				if (boot != null) boot();
				for (w in writes)
					w.atom.set(w.value);
			},
			time: env.time ?? b.time,
			seed: b.seed,
			zone: zone(env.zone == null ? b.zone : helder.os.Now.parseZone(env.zone) ?? 0),
			locale: env.locale ?? b.locale,
			settings: settings,
			http: b.http,
			steps: steps,
			size: env.size ?? (b.width == null ? null : [b.width, b.height]),
			dark: env.dark ?? b.dark
		}, b.pos);
	}

	function size():{width:Null<Int>, height:Null<Int>, title:Null<String>}
		return surface ??= Act.size(root);

	// --- the scenario file

	function file(base:Base, env:Environment, writes:Array<Write>, steps:Array<Step>, failure:String):String {
		var sc = scenario(base, env, writes, steps), b = base.scenario;
		var parts = base.path.split("."), pack = parts.slice(0, parts.length - 2);
		var used = [for (s in steps) s.kind];
		var names = ["tap", "type", "press", "scroll", "drag", "waitFor", "resize", "wait"].filter(k -> used.contains(k));
		var lines = ['package ${pack.join(".")};', "", "import helder.scenario.Scenario.scenario;"];
		for (n in names)
			lines.push('import helder.scenario.Steps.$n;');
		lines.push("");
		lines.push('// Found by helder.scenario.Monkey (${@:privateAccess Runner.file(pos.fileName)}:${pos.lineNumber}) from ${base.path}, shrunk:');
		for (l in failure.split("\n").slice(0, 6))
			lines.push('// $l');
		lines.push('// Move it beside the scenarios it starts from to open it in the studio.');
		var fields = ['name: ${Steps.quote(sc.name)}'];
		if (sc.width != null) fields.push('size: [${sc.width}, ${sc.height}]');
		if (sc.dark != null) fields.push('dark: ${sc.dark}');
		if (sc.time != null) fields.push('time: ${Steps.quote(iso(sc.time))}');
		if (sc.zone != 0) fields.push('zone: ${Steps.quote(zone(sc.zone))}');
		if (sc.locale != "en-US") fields.push('locale: ${Steps.quote(sc.locale)}');
		var set = [];
		if (sc.settings.textScale != 1.0) set.push('textScale: ${sc.settings.textScale}');
		if (sc.settings.reducedMotion == true) set.push("reducedMotion: true");
		if (sc.settings.reducedTransparency == true) set.push("reducedTransparency: true");
		if (set.length > 0) fields.push('settings: {${set.join(", ")}}');
		if (sc.seed != 1) fields.push('seed: ${sc.seed}');
		if (sc.http != null) fields.push('http: ${literal(sc.http)}');
		var boot = [];
		if (b.boot != null) boot.push('${base.path}.boot();');
		for (w in writes)
			boot.push('${w.atom.name}(${w.atom.show(w.value)});');
		if (boot.length == 1) fields.push('boot: () -> ${boot[0].substr(0, boot[0].length - 1)}');
		else if (boot.length > 1) fields.push('boot: () -> {\n\t\t' + boot.join("\n\t\t") + "\n\t}");
		if (steps.length > 0) fields.push('steps: [\n\t\t' + [for (s in steps) code(s)].join(",\n\t\t") + "\n\t]");
		lines.push("final found = scenario({\n\t" + fields.join(",\n\t") + "\n});");
		return lines.join("\n") + "\n";
	}

	// (a step as its file writes it: tap("Add"))
	public static function code(s:Step):String
		return switch s.kind {
			case "tap" | "waitFor": '${s.kind}(${literal(s.query)})';
			case "type": 'type(${literal(s.query)}, ${Steps.quote(s.text)})';
			case "press": 'press(${Steps.quote(s.text)})';
			case "scroll": 'scroll(${literal(s.query)}, ${literal(s.to)})';
			case "drag": 'drag(${literal(s.query)}, ${literal(s.to)})';
			case "resize": 'resize(${s.to.width}, ${s.to.height})';
			case "wait": 'wait(${literal(s.to)})';
			case k: '$k()';
		}

	// (a value as Haxe writes it: strings, numbers, arrays, objects, enums)
	public static function literal(v:Dynamic):String {
		if (v == null) return "null";
		if (Std.isOfType(v, String)) return Steps.quote(v);
		if (Std.isOfType(v, Bool)) return v ? "true" : "false";
		if (Std.isOfType(v, Int)) return Std.string(v);
		if (Std.isOfType(v, Float)) return number(v);
		if (Std.isOfType(v, Array)) return "[" + [for (x in (v : Array<Dynamic>)) literal(x)].join(", ") + "]";
		if (Reflect.isEnumValue(v)) {
			var e = Type.getEnum(v);
			var ps = Type.enumParameters(v);
			return Type.getEnumName(e) + "." + Type.enumConstructor(v) + (ps.length == 0 ? "" : "(" + [for (p in ps) literal(p)].join(", ") + ")");
		}
		var fields = Reflect.fields(v);
		fields.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		return "{" + [for (f in fields) '${~/^[A-Za-z_][A-Za-z0-9_]*$/.match(f) ? f : Steps.quote(f)}: ${literal(Reflect.field(v, f))}'].join(", ") + "}";
	}

	public static function number(f:Float):String {
		if (Math.isNaN(f)) return "Math.NaN";
		if (!Math.isFinite(f)) return f > 0 ? "Math.POSITIVE_INFINITY" : "Math.NEGATIVE_INFINITY";
		return Std.string(f);
	}

	// (minutes east of UTC as a scenario's zone: "UTC", "+05:30")
	static function zone(m:Int):String {
		if (m == 0) return "UTC";
		var a = m < 0 ? -m : m;
		return (m < 0 ? "-" : "+") + StringTools.lpad(Std.string(Std.int(a / 60)), "0", 2) + ":" + StringTools.lpad(Std.string(a % 60), "0", 2);
	}

	// (ms since 1970 as an ISO date in UTC: Howard Hinnant's civil from days)
	static function iso(ms:Float):String {
		var days = Math.floor(ms / 86400000), rest = Std.int((ms - days * 86400000.0) / 1000);
		var z = days + 719468, era = Math.floor(z / 146097), doe = z - era * 146097;
		var yoe = Std.int((doe - Std.int(doe / 1460) + Std.int(doe / 36524) - Std.int(doe / 146096)) / 365);
		var doy = doe - (365 * yoe + Std.int(yoe / 4) - Std.int(yoe / 100)), mp = Std.int((5 * doy + 2) / 153);
		var d = doy - Std.int((153 * mp + 2) / 5) + 1, m = mp < 10 ? mp + 3 : mp - 9, y = yoe + era * 400 + (m <= 2 ? 1 : 0);
		inline function two(n:Int)
			return StringTools.lpad(Std.string(n), "0", 2);
		return '${StringTools.lpad(Std.string(y), "0", 4)}-${two(m)}-${two(d)}T${two(Std.int(rest / 3600))}:${two(Std.int(rest / 60) % 60)}:${two(rest % 60)}Z';
	}
	#end

}

#if !macro
// a monkey's program and what it may do
typedef MonkeyDef = {
	// the scenarios cases start from (Monkey.from)
	var from:Array<Base>;
	// the model's signals given values of their types after boot (Monkey.atom)
	@:optional var atoms:Array<MonkeyAtom>;
	// texts typed (else short words, long runs, right to left, emoji, marks)
	@:optional var texts:Gen<String>;
	// invariants left out, by name (Monkey.INVARIANTS, the checks')
	@:optional var except:Array<String>;
	// findings still open: a case whose first failure holds one's text is
	// rejected, not failed (that cause alone; every other failure counts),
	// each with why (one fixed leaves the list)
	@:optional var known:Array<{failure:String, why:String}>;
	// whether the program moves by design now (asked in the case's screen:
	// an animated image looping, a video playing): settles and steady not
	// asked of it then
	@:optional var animates:Void->Bool;
	// the program's own invariants, after the monkey's: each run in the
	// case's screen (its context and store current) after boot and each
	// step, what is wrong (null: none)
	@:optional var checks:Array<{name:String, check:Void->Null<String>}>;
	// a case's most steps (20)
	@:optional var steps:Int;
	// the smallest window a case is given or resized to, [width, height] in
	// points ([240, 180]: below it no layout is asked to fit)
	@:optional var smallest:Array<Int>;
	// the program's root (else what its main gave UiWindow.run)
	@:optional var root:RootView;
}

// a scenario a case starts from, and its path in code
typedef Base = {
	var scenario:Scenario;
	var path:String;
}

// the smallest failing case: its scenario file (where it is written, its
// text), its first failure, its steps, its scenario (built again: its
// boot writes what the case wrote)
typedef Found = {
	var file:String;
	var text:String;
	var failure:String;
	var steps:Array<String>;
	var scenario:Scenario;
}

// a signal a case writes: its path in code, its values, how its file writes one
class MonkeyAtom {
	public final name:String;
	public final gen:Gen<Dynamic>;
	public final show:Dynamic->String;
	public final set:Dynamic->Void;

	function new(name, gen, show, set) {
		this.name = name;
		this.gen = gen;
		this.show = show;
		this.set = set;
	}

	public static function make<T>(name:String, gen:Gen<T>, show:T->String, set:T->Void):MonkeyAtom
		return new MonkeyAtom(name, cast gen, cast show, cast set);
}

private typedef Environment = {
	size:Null<Array<Int>>,
	dark:Null<Bool>,
	locale:Null<String>,
	textScale:Null<Float>,
	time:Null<Float>,
	zone:Null<String>
}

private typedef Write = {
	atom:MonkeyAtom,
	value:Dynamic
}

// (a case's screen: a context and store of its own, a Ui, never drawn)
private class Screen {
	public final ui:Ui;
	public final context:ScreenContext;
	final sc:Scenario;
	final root:RootView;
	var unrender:Null<Void->Void> = null;
	public var settled = true;
	public var missed:Null<String> = null;

	public function new(sc:Scenario, root:RootView, text:TextEngine, width:Int, height:Int) {
		this.sc = sc;
		this.root = root;
		context = new ScreenContext("helder.scenario.monkey", true, null, new Atoms("helder.scenario.monkey"));
		if (sc.dark != null) context.dark(sc.dark);
		// (sealed off the machine: its trash, places, stores' files, an app's real files; helder.os.Seal)
		context.seal = new helder.os.Seal("a monkey's case");
		// (made in its context: a Ui claims the screen it is made in, its size class, its clock)
		ui = context.run(() -> new Ui(text, width, height));
		ui.dark = context.dark.peek();
	}

	public function mount()
		unrender = context.run(() -> helder.dev.Hot.scope("helder.scenario.monkey", () -> {
			helder.os.Seed.random(sc.seed);
			var d = Act.mount(sc, root, context, ui, (method, url) -> missed ??= 'no http fixture for $method $url');
			settled = @:privateAccess Steps.settle(ui, context);
			d;
		}));

	// (a step run and waited for, as a scenario runs it)
	public function act(s:Step)
		context.run(() -> {
			settled = @:privateAccess Steps.next(s, ui, context, why -> throw new StepError(why));
		});

	public function leave()
		context.run(() -> {
			ui.pointerMove(-1000, -1000);
			settled = @:privateAccess Steps.settle(ui, context);
		});

	// (one frame of its clock: steady's)
	public function frame()
		context.run(() -> @:privateAccess Steps.frame(ui, context));

	public function pending():String {
		var what = [];
		if (ui.needsFrame) what.push("a frame asked for");
		if (context.animating) {
			// (what moves: its transitions, its motion; else a clock step of its own)
			var moving = [];
			function walk(n:Node) {
				var p = n.present;
				if (p != null && p.active) moving.push(Monkey.describe(n));
				for (c in n.children)
					if (moving.length < 3) walk(c);
			}
			walk(ui.root);
			walk(ui.overlay);
			what.push(moving.length > 0 ? 'moving: ${moving.join(", ")}' : "a clock step running");
		}
		if (context.nextTimer() <= context.now + 1) what.push("a timer due");
		return what.length == 0 ? "something" : what.join(", ");
	}

	// (what is shown, as the steps' queries see it)
	public function inspect():{nodes:Array<InspectedNode>} {
		return {nodes: context.run(() -> @:privateAccess Steps.shown(ui))};
	}

	// (the query that finds n alone, by what the user sees; else its centre)
	public function query(n:InspectedNode):Dynamic {
		var tries:Array<Dynamic> = [];
		if (n.label != null) tries.push(n.label);
		if (n.text != null) tries.push(n.text);
		if (n.identifier != null) tries.push(n.identifier);
		if (n.role != null && n.label != null) tries.push({role: n.role, name: n.label});
		if (n.role != null && n.text != null) tries.push({role: n.role, text: n.text});
		for (q in tries) {
			// (a query is a short, plain string: a long name or text a point)
			if (Std.isOfType(q, String) && (q : String).length > 60) continue;
			var found = context.run(() -> Steps.matches(ui, q));
			if (found.length == 1 && same(found[0], n)) return q;
		}
		return {x: Math.round(n.x + n.width / 2), y: Math.round(n.y + n.height / 2)};
	}

	// (whether a tap at n's centre lands on it: the topmost node there is it or in it)
	public function reached(n:InspectedNode):Bool
		return under(n) != null;

	// (the node a tap at n's centre lands in, n's own: null when another covers it)
	function under(n:InspectedNode):Null<Node> {
		var h = context.run(() -> @:privateAccess ui.hit(n.x + n.width / 2, n.y + n.height / 2));
		while (h != null) {
			var b = h.windowBounds();
			if (h.tag == n.tag && Math.abs(b.x - n.x) < 0.5 && Math.abs(b.y - n.y) < 0.5 && Math.abs(b.width - n.width) < 0.5 && Math.abs(b.height - n.height) < 0.5)
				return h;
			h = h.parent;
		}
		return null;
	}

	// (the node a step's query finds, as it would land on it)
	public function node(q:Dynamic):Null<Node> {
		var found = context.run(() -> Steps.matches(ui, q));
		return found.length == 1 ? under(found[0]) : null;
	}

	static function same(a:InspectedNode, b:InspectedNode):Bool
		return a.id == b.id && a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height;

	// (the scrollers that scroll, shown, not under a modal popup, and reached
	// at the point a step wheels them at: none another covers)
	public function scrollers():Array<ScrollView>
		return context.run(() -> ui.scrollViews().filter(v -> {
			if (!(v.scrollsY || v.scrollsX) || v.covered || v.width <= 0 || v.height <= 0) return false;
			var p:{x:Float, y:Float} = spot(v);
			if (p.x < 0 || p.y < 0 || p.x >= ui.width || p.y >= ui.height) return false;
			var h = @:privateAccess ui.hit(p.x, p.y);
			h != null && v.node.contains(h);
		}));

	// (where a step wheels a scroller: its shown part's centre)
	function spot(v:ScrollView):{x:Float, y:Float} {
		var x0 = Math.max(0, v.x), y0 = Math.max(0, v.y), x1 = Math.min(ui.width, v.x + v.width), y1 = Math.min(ui.height, v.y + v.height);
		return {x: Math.round((x0 + x1) / 2), y: Math.round((y0 + y1) / 2)};
	}

	// (a scroller's node, as a step finds it: a query, else its shown part's centre)
	public function place(v:ScrollView):Dynamic {
		var label = v.node.semantics?.label;
		if (label != null && label != "" && label.length <= 60) {
			var found = context.run(() -> Steps.matches(ui, label));
			// (its name when a wheel at its node's centre reaches it, as at its spot)
			if (found.length == 1 && found[0].tag == v.node.tag && Math.abs(found[0].x - v.x) < 1 && Math.abs(found[0].y - v.y) < 1) {
				var h = context.run(() -> @:privateAccess ui.hit(found[0].x + found[0].width / 2, found[0].y + found[0].height / 2));
				if (h != null && v.node.contains(h)) return label;
			}
		}
		return spot(v);
	}

	public function view(n:Node):Null<ScrollView>
		return Lambda.find(context.run(() -> ui.scrollViews()), v -> v.node == n);

	// (its last row: the last child shown of its content, deepest first)
	public function last(n:Node):Null<Node> {
		var c = n.children.filter(k -> !k.used.none && k.width > 0 && k.height > 0 && k.used.position != "absolute");
		if (c.length == 1 && c[0].children.length > 1) return last(c[0]);
		return c.length == 0 ? null : c[c.length - 1];
	}

	public function popups():Array<Popup>
		return [for (c in ui.overlay.children) if (Std.isOfType(c, Popup)) (cast c : Popup)];

	// (whether n is in the tree: under the root or the overlay)
	public function attached(n:Null<Node>):Bool {
		var a = n;
		while (a != null) {
			if (a == ui.root || a == ui.overlay) return true;
			a = a.parent;
		}
		return false;
	}

	public function dispose() {
		var u = unrender;
		unrender = null;
		if (u != null) context.run(() -> u());
		context.atoms?.dispose();
	}
}

// (what a screen shows after settling: each node's box in the window, and
// its scrollers' offsets)
private class Snapshot {
	public final nodes:Array<Shot> = [];
	public final views:Array<{node:Node, offsetX:Float, offsetY:Float, x:Float, y:Float, width:Float, height:Float, scrollsY:Bool, contentWidth:Float,
		contentHeight:Float}> = [];
	public var focus:Null<Node> = null;
	// (a type step's field, as the step finds it; whether a menu was open)
	public var field:Null<Node> = null;
	public var menu = false;
	final boxes = new haxe.ds.ObjectMap<Node, helder.os.Rect>();

	function new() {}

	public static function of(s:Screen):Snapshot {
		var out = new Snapshot();
		out.focus = s.ui.focus;
		out.menu = Lambda.exists(s.popups(), p -> p.menu);
		for (c in s.ui.root.children)
			out.visit(c, false, 1);
		for (c in s.ui.overlay.children)
			out.visit(c, false, 1);
		for (v in s.scrollers())
			out.views.push({node: v.node, offsetX: v.offsetX, offsetY: v.offsetY, x: v.x, y: v.y, width: v.width, height: v.height, scrollsY: v.scrollsY,
				contentWidth: v.contentWidth, contentHeight: v.contentHeight});
		return out;
	}

	function visit(n:Node, clipped:Bool, opacity:Float) {
		var st = n.used;
		if (st.none || n.present != null && n.present.away) return;
		var b = n.windowBounds(), op = opacity * st.opacity;
		nodes.push({node: n, parent: n.parent, box: b, laid: {x: n.absX, y: n.absY, width: n.width, height: n.height}, clipped: clipped,
			shown: op > 0 && b.width > 0 && b.height > 0});
		boxes.set(n, b);
		var clips = clipped || st.clips;
		for (c in n.children)
			visit(c, clips, op);
	}

	public function box(n:Node):Null<helder.os.Rect>
		return boxes.get(n);

	// (the scrollers a scroll step's point is in, as they were, the outermost first)
	public function under(s:Step):Array<{node:Node, offsetY:Float, contentHeight:Float, height:Float}> {
		var p:Dynamic = s.query, out = [];
		if (!Std.isOfType(p, String) && p != null && Reflect.hasField(p, "x")) {
			for (v in views)
				if (v.scrollsY && p.x >= v.x && p.y >= v.y && p.x < v.x + v.width && p.y < v.y + v.height) out.push(v);
		} else for (v in views)
			if (v.scrollsY && v.node.semantics?.label == p) out.push(v);
		// (outermost first: each contains the next)
		out.sort((a, b) -> a.node.contains(b.node) ? -1 : b.node.contains(a.node) ? 1 : 0);
		return [for (v in out) {node: v.node, offsetY: v.offsetY, contentHeight: v.contentHeight, height: v.height}];
	}
}

private typedef Shot = {
	node:Node,
	parent:Null<Node>,
	box:helder.os.Rect,
	laid:helder.os.Rect,
	clipped:Bool,
	shown:Bool
}
#end
