package helder.scenario;

import helder.os.headless.Inspector.InspectedNode;
import helder.ui.*;

// A scenario's steps (phase 2c): what a user does after boot, before the
// still, each found by what the user sees and each waited for. A query is
// a string, tried in this order: a node with a role and that name (a
// button "Add"), with that label, with that text, with that id; or
// {role, name, label, text, id}, each given matched. Only what is shown
// counts; the first kind that matches must match one node (more: an error,
// ambiguous). After each step the screen's clock runs until nothing is
// pending (frames, transitions, timers due soon, tasks): exact, not a
// sleep. A step that finds nothing fails the screen: `step 2: no button
// "Add" (near: button "Add habit")` and what is shown.
//
//   steps: [tap("Add habit"), type("Habit", "Stretch"), press("Enter"), waitFor("Stretch")]

// a query's fields, each given matched (a string: a role's name, else a label, a text, an id)
typedef Query = {
	@:optional var role:String;
	@:optional var name:String;
	@:optional var label:String;
	@:optional var text:String;
	@:optional var id:String;
}

// a step (tap, type, press, scroll, drag, waitFor make one)
class Step {
	public final kind:String;
	public final query:Dynamic;
	public final text:Null<String>;
	public final to:Dynamic;

	public function new(kind, query, ?text, ?to) {
		this.kind = kind;
		this.query = query;
		this.text = text;
		this.to = to;
	}
}

// (a step that went wrong: where its scenario was written, when known)
class StepError extends helder.view.MarkupError {}

class Steps {
	// (60 frames a second of the screen's clock; a step's wait at most this long)
	static inline var FPS = 60.0;
	static inline var LONGEST = 60.0;

	// a tap at the node's centre (a press and its release)
	public static function tap(@:typescript.type("string | Query") query:Dynamic):Step
		return new Step("tap", query);

	// text typed into the node (tapped first: its focus)
	public static function type(@:typescript.type("string | Query") query:Dynamic, text:String):Step
		return new Step("type", query, text);

	// a key pressed and let go in what has the focus: "Enter", "Escape", "Tab",
	// "Backspace", "ArrowUp" and the other arrows, "Space", or a character
	public static function press(key:String):Step
		return new Step("press", null, key);

	// the scroll view of the node scrolled: to "end", "start", by points (a
	// number), or until another query is shown
	public static function scroll(@:typescript.type("string | Query") query:Dynamic, @:typescript.type("\"end\" | \"start\" | number | string | Query") to:Dynamic):Step
		return new Step("scroll", query, null, to);

	// a press at from (a query, or {x, y} in points) moved to to (a query, or
	// {x, y}, or {dx, dy} from from) and let go, as a mouse drags
	public static function drag(@:typescript.type("string | Query | {x: number; y: number}") from:Dynamic,
			@:typescript.type("string | Query | {x: number; y: number} | {dx: number; dy?: number}") to:Dynamic):Step
		return new Step("drag", from, null, to);

	// the clock run until the query is shown (a minute of it at most)
	public static function waitFor(@:typescript.type("string | Query") query:Dynamic):Step
		return new Step("waitFor", query);

	// each step of list run in the screen, waited for; a failure thrown with its number
	public static function run(list:Array<Step>, ui:Ui, context:ScreenContext, ?at:helder.view.Source) {
		settle(ui, context);
		for (i => s in list) {
			var fail = (why:String) -> throw new StepError('step ${i + 1}: $why\n${tree(ui)}', at);
			switch s.kind {
				case "tap":
					var n = one(ui, s.query, fail);
					click(ui, centre(n));
				case "type":
					var n = one(ui, s.query, fail);
					click(ui, centre(n));
					settle(ui, context);
					ui.textInput(s.text);
				case "press":
					var k = key(s.text);
					if (k == null) fail('no key "${s.text}" (Enter, Escape, Tab, Backspace, ArrowUp, ArrowDown, ArrowLeft, ArrowRight, Space or a character)');
					ui.keyDown(k, 0);
					ui.keyUp(k, 0);
				case "scroll":
					var n = one(ui, s.query, fail), c = centre(n);
					if (Std.isOfType(s.to, Float) || Std.isOfType(s.to, Int)) ui.wheel(c.x, c.y, 0, s.to);
					else if (s.to == "end" || s.to == "start") ui.wheel(c.x, c.y, 0, s.to == "end" ? 1e7 : -1e7);
					else {
						// (until the query is shown, a viewful at a time)
						var tries = 0;
						while (matches(ui, s.to).length == 0) {
							if (++tries > 100) fail('${describe(s.to)} not shown after scrolling ${describe(s.query)} 100 times');
							ui.wheel(c.x, c.y, 0, Math.max(40, n.height * 0.8));
							settle(ui, context);
						}
					}
				case "drag":
					var from = point(ui, s.query, null, fail), to = point(ui, s.to, from, fail);
					ui.pointerMove(from.x, from.y);
					ui.pointerDown(from.x, from.y, 1);
					for (k in 1...11) {
						var t = k / 10;
						Clock.tick(context.now + 1 / FPS);
						ui.pointerMove(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t);
						ui.update();
					}
					ui.pointerUp(to.x, to.y, 1);
				case "waitFor":
					var end = context.now + LONGEST;
					while (matches(ui, s.query).length == 0) {
						if (context.now >= end) fail('${describe(s.query)} not shown after a minute of its clock');
						frame(ui, context);
					}
				case k:
					fail('no step $k');
			}
			settle(ui, context);
		}
		// (the pointer gone after them: the still not showing a hover it did not ask for)
		ui.pointerMove(-1000, -1000);
		settle(ui, context);
	}

	// (its clock run a frame at a time until nothing is pending: no frame
	// asked for, nothing animating, no timer due within a second, no task
	// ready; a minute of it at most)
	static function settle(ui:Ui, context:ScreenContext) {
		var end = context.now + LONGEST;
		while (context.now < end) {
			helder.view.graph.Graph.flush();
			var l = helder.async.Driven.MainLoop.main;
			if (l != null && !l.turning) l.turn(0);
			ui.update();
			var soon = context.nextTimer() <= context.now + 1;
			if (!ui.needsFrame && !context.animating && !soon) return;
			frame(ui, context);
		}
	}

	static function frame(ui:Ui, context:ScreenContext) {
		Clock.tick(context.now + 1 / FPS);
		var l = helder.async.Driven.MainLoop.main;
		if (l != null && !l.turning) l.turn(0);
		ui.update();
	}

	static function click(ui:Ui, p:{x:Float, y:Float}) {
		ui.pointerMove(p.x, p.y);
		ui.pointerDown(p.x, p.y, 1);
		ui.pointerUp(p.x, p.y, 1);
	}

	static function centre(n:InspectedNode):{x:Float, y:Float}
		return {x: n.x + n.width / 2, y: n.y + n.height / 2};

	// (a drag's end: a query's node's centre, {x, y}, or {dx, dy} from from)
	static function point(ui:Ui, q:Dynamic, from:Null<{x:Float, y:Float}>, fail:String->Void):{x:Float, y:Float} {
		if (q != null && !Std.isOfType(q, String) && Reflect.hasField(q, "x")) return {x: q.x, y: q.y};
		if (q != null && from != null && !Std.isOfType(q, String) && Reflect.hasField(q, "dx")) return {x: from.x + q.dx, y: from.y + (q.dy ?? 0)};
		return centre(one(ui, q, fail));
	}

	// the node the query finds, one of what is shown: else fail
	static function one(ui:Ui, q:Dynamic, fail:String->Void):InspectedNode {
		var found = matches(ui, q);
		if (found.length == 1) return found[0];
		if (found.length > 1) fail('${describe(q)} is ${found.length} nodes: ${[for (n in found.slice(0, 5)) name(n)].join(", ")} (a role, a label or an id tells them apart)');
		var near = nearby(ui, q);
		fail('no ${describe(q)}' + (near.length > 0 ? ' (near: ${near.join(", ")})' : ""));
		return null;
	}

	// (what the query finds, its first kind that matches: role and name, label, text, id)
	public static function matches(ui:Ui, q:Dynamic):Array<InspectedNode> {
		var nodes = shown(ui);
		if (Std.isOfType(q, String)) {
			var s:String = q;
			for (test in [(n:InspectedNode) -> n.role != null && n.label == s, n -> n.label == s, n -> n.text == s, n -> n.identifier == s]) {
				var found = nodes.filter(test);
				if (found.length > 0) return found;
			}
			return [];
		}
		return nodes.filter(n -> (q.role == null || n.role == q.role) && (q.name == null || n.label == q.name) && (q.label == null || n.label == q.label)
			&& (q.text == null || n.text == q.text) && (q.id == null || n.identifier == q.id));
	}

	// (what is shown: a size, some opacity, its centre (where a tap lands) in
	// the screen and in every scroll view around it, not scrolled out of sight)
	static function shown(ui:Ui):Array<InspectedNode> {
		var all = new helder.ui.draw.UiInspector(ui).nodes(), byId = new Map<Int, InspectedNode>();
		for (n in all)
			byId.set(n.id, n);
		inline function inside(x:Float, y:Float, b:InspectedNode)
			return x >= b.x && y >= b.y && x < b.x + b.width && y < b.y + b.height;
		return all.filter(n -> {
			if (n.width <= 0 || n.height <= 0 || n.opacity <= 0) return false;
			var x = n.x + n.width / 2, y = n.y + n.height / 2;
			if (x < 0 || y < 0 || x >= ui.width || y >= ui.height) return false;
			var up = byId.get(n.parent);
			while (up != null) {
				if (up.tag == "scroll" && !inside(x, y, up)) return false;
				up = byId.get(up.parent);
			}
			true;
		});
	}

	// (what is shown that has a name: a role, a label, a text or an id; a
	// text that only repeats its parent's name (a button's) left out)
	static function named(ui:Ui):Array<InspectedNode> {
		var all = shown(ui), byId = new Map<Int, InspectedNode>(), out = [];
		for (n in all)
			byId.set(n.id, n);
		for (n in all) {
			if (n.role == null && n.label == null && n.text == null && n.identifier == null) continue;
			var up = byId.get(n.parent);
			if (n.role == null && n.label == null && n.identifier == null && up != null && up.label == n.text) continue;
			out.push(n);
		}
		return out;
	}

	// (nodes whose name or text is like the query's: a near miss's)
	static function nearby(ui:Ui, q:Dynamic):Array<String> {
		var want:Null<String> = Std.isOfType(q, String) ? q : q.name ?? q.label ?? q.text ?? q.id;
		if (want == null) return [];
		// (the closest first: a typo's fix before a long text that holds it)
		var w = want.toLowerCase(), near = [];
		for (n in named(ui)) {
			var have = (n.label ?? n.text ?? n.identifier ?? "").toLowerCase(), d = distance(have, w);
			if (have != "" && (have.indexOf(w) >= 0 || w.indexOf(have) >= 0 || d <= 2)) near.push({d: d, name: name(n)});
		}
		near.sort((a, b) -> a.d - b.d);
		var out = [];
		for (n in near) if (out.length < 3 && !out.contains(n.name)) out.push(n.name);
		return out;
	}

	// (a node as a step's message names it: button "Add", "Hello", #id)
	static function name(n:InspectedNode):String {
		var what = n.label ?? n.text;
		return (n.role != null ? n.role + " " : "") + (what != null ? '"$what"' : n.identifier != null ? '#${n.identifier}' : n.tag);
	}

	static function describe(q:Dynamic):String {
		if (Std.isOfType(q, String)) return '"$q"';
		if (q == null) return "nothing";
		var what:Null<String> = q.name ?? q.label ?? q.text;
		return (q.role != null ? q.role + " " : "") + (what != null ? '"$what"' : q.id != null ? '#${q.id}' : "anything");
	}

	// (what is shown, compactly: each node with a role or a name, indented by its depth, 40 at most)
	public static function tree(ui:Ui):String {
		var lines = [];
		for (n in named(ui)) {
			lines.push(StringTools.lpad("", " ", n.depth * 2) + name(n));
			if (lines.length >= 40) {
				lines.push("...");
				break;
			}
		}
		return lines.join("\n");
	}

	static function key(k:Null<String>):Null<Int>
		return switch k {
			case null: null;
			case "Enter": Key.ENTER;
			case "Escape": Key.ESCAPE;
			case "Tab": Key.TAB;
			case "Backspace": Key.BACKSPACE;
			case "Delete": Key.DELETE;
			case "Home": Key.HOME;
			case "End": Key.END;
			case "ArrowUp": Key.UP;
			case "ArrowDown": Key.DOWN;
			case "ArrowLeft": Key.LEFT;
			case "ArrowRight": Key.RIGHT;
			case "Space": Key.SPACE;
			case c if (c.length == 1): c.charCodeAt(0);
			case _: null;
		}

	// (Levenshtein's, short strings)
	static function distance(a:String, b:String):Int {
		if (Math.abs(a.length - b.length) > 2) return 3;
		var prev = [for (j in 0...b.length + 1) j];
		for (i in 1...a.length + 1) {
			var cur = [i];
			for (j in 1...b.length + 1)
				cur.push(Std.int(Math.min(Math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + (a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1))));
			prev = cur;
		}
		return prev[b.length];
	}
}
