package viewer;

import helder.os.Places;
import helder.ui.Node;
import helder.ui.controls.Look;
import helder.ui.controls.Standard;
import helder.ui.widgets.WindowButtons;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// The sidebar (236 points): a bar that stays (the back row to the level
// above, the overview's button), the overview (Locations, Devices) or a
// folder's level (its title, its subfolders), one level at a time
// (Sidebar), and its volume's capacity at the foot, which stays too. Going
// between levels is a navigation push of the levels alone: the new one
// slides in from its side (a deeper one from the right, an enclosing one
// from the left) as the old one slides out the other way, both together,
// clipped to the sidebar, on the picture's flight's spring (Flight.SPRING)
// at whole-point offsets, its tail ended within a device pixel; clicked
// again on the way, two levels at most, the one coming replaced or each
// turned from where it is. Its rows are there before it moves (Sidebar
// keeps a level until its new one's are read); the one going keeps its
// own. Reduced motion: a cross-fade. On macOS its top holds the window's
// buttons (the shell's WindowControls over it).
@:renderer(helder.ui.view.NodeRenderer)
class SidebarView implements Markup {
	public static inline var WIDTH = 236;

	public static function make(x:Explorer):View {
		var s = x.sidebar, body:Null<Node> = null, ticking = false, ready = false, c = new Clicks();
		var panes = signal([new Pane(s.level.value, s.rows.value)]);
		// (the current pane's rows, the model's; one going keeps its own)
		renderEffect(() -> s.rows(), r -> for (p in panes.peek()) if (p.level == s.level.value) p.rows(r));
		function step(t:Float):Bool {
			var n = body, d = n == null || n.ui == null ? 1.0 : n.ui.scale, moving = false;
			for (p in panes.peek()) {
				p.at.sample(t);
				p.fade.sample(t);
				Pane.snap(p.at, d);
				p.x(Math.round(p.at.value));
				p.shown(p.fade.value);
				if (p.at.moving() || p.fade.moving()) moving = true;
			}
			// (those gone out of sight let go)
			if (!moving) panes(panes.peek().filter(p -> p.at.target == 0 && p.fade.target > 0));
			return ticking = moving;
		}
		renderEffect(() -> s.level(), level -> {
			var list = panes.peek(), now = list[list.length - 1];
			if (level == now.level) return;
			var n = body;
			// (not shown yet, or just: the sidebar's first level landing as it is made, in place)
			if (n == null || n.ui == null || !ready) {
				panes([new Pane(level, s.rows.value)]);
				return;
			}
			var w = n.width > 0 ? n.width : WIDTH, reduced = helder.ui.Clock.reducedMotion, fade = helder.ui.motion.Curve.REDUCED_FADE;
			if (list.length > 1) {
				// (on the way already: two levels at most, never a queue of them)
				var from = list[0];
				if (level == from.level) {
					// (back to where it began: each turned from where it is, as fast, no detour)
					from.rows(s.rows.value);
					if (reduced) {
						from.fade.animate(-1, 1, fade);
						now.fade.animate(-1, 0, fade);
					} else {
						var side = from.at.target;
						from.at.animate(-1, 0, Flight.SPRING);
						now.at.animate(-1, -side, Flight.SPRING);
					}
					panes([now, from]);
				} else {
					// (another level: in place of the one coming, its motion carried on; the ones between never shown)
					var into = new Pane(level, s.rows.value);
					into.at = now.at.copy();
					into.fade = now.fade.copy();
					into.x(Math.round(into.at.value));
					into.shown(into.fade.value);
					panes([from, into]);
				}
			} else {
				// (a push: the new level from its side, the current one out the other way)
				var deeper = now.level == "" || StringTools.startsWith(level, now.level + "/")
					|| (StringTools.endsWith(now.level, "/") && StringTools.startsWith(level, now.level));
				var dir = deeper ? 1 : -1, into = new Pane(level, s.rows.value);
				if (reduced) {
					into.fade.set(0);
					into.fade.animate(-1, 1, fade);
					now.fade.animate(-1, 0, fade);
				} else {
					into.at.set(dir * w);
					into.at.animate(-1, 0, Flight.SPRING);
					now.at.animate(-1, -dir * w, Flight.SPRING);
				}
				into.x(Math.round(into.at.value));
				into.shown(into.fade.value);
				panes([now, into]);
			}
			if (ticking) return;
			ticking = true;
			helder.ui.Clock.addFor(n, step);
		});
		return <view tag="sidebar" width={WIDTH} flexShrink={0} padding="0 10" rowGap={6} overflow="hidden"
			paddingTop={WindowButtons.side() == "start" ? 0 : 8}>
			<Show when={WindowButtons.side() == "start"}><view height={Shell.BAR} flexShrink={0} dragRegion/></Show>
			{bar(x)}
			<view tag="sidebar-body" flexGrow={1} minHeight={0} ref={(n:Node) -> {
				body = n;
				// (shown a tenth of a second: levels from now on pushed)
				var from = -1.0;
				helder.ui.Clock.addFor(n, t -> {
					if (from < 0) from = t;
					if (t - from < 0.1) return true;
					ready = true;
					return false;
				});
			}}>
				<For each={panes}>{p -> pane(x, c, p.peek())}</For>
			</view>
			{foot(x)}
		</view>;
	}

	// (the bar over the levels, still while they slide (a navigation bar's):
	// the back row to the level above, its label cross-faded in place, gone
	// at the overview by a fade; the overview's button, never moved. Its
	// fades on tracks of its own, as the panes' moves: a declared motion
	// (motion-opacity, transition) turns on helder.ui's motions for the
	// whole window, each of its frames then walked twice)
	static function bar(x:Explorer):View {
		var s = x.sidebar, node:Null<Node> = null, ticking = false;
		function top():Bool
			return s.level() == "";
		var row = new helder.ui.motion.Track(s.level.value == "" ? 0 : 1, 1e-3), mix = new helder.ui.motion.Track(1, 1e-3);
		var shown = signal(row.value), crossed = signal(1.0), label = signal(s.level.value == "" ? "" : s.backLabel()), last = signal("");
		function step(t:Float):Bool {
			row.sample(t);
			mix.sample(t);
			shown(row.value);
			crossed(mix.value);
			return ticking = row.moving() || mix.moving();
		}
		renderEffect(() -> [s.level(), s.backLabel()], v -> {
			var at = v[0] != "", now = node != null && node.ui != null, fade = helder.ui.motion.Curve.REDUCED_FADE;
			if (now) row.animate(-1, at ? 1 : 0, fade) else row.set(at ? 1 : 0);
			// (another label: the last fading out over it; from the overview, the row's fade alone)
			if (at && v[1] != label.peek()) {
				if (now && label.peek() != "" && row.target > 0 && row.value > 0) {
					last(label.peek());
					mix.set(0);
					mix.animate(-1, 1, fade);
				} else mix.set(1);
				label(v[1]);
			}
			if (!now) {
				shown(row.value);
				crossed(mix.value);
			} else if (!ticking) {
				ticking = true;
				helder.ui.Clock.addFor(node, step);
			}
		});
		return <view tag="level-bar" flexDirection="row" alignItems="center" padding="0 2" columnGap={2} flexShrink={0} ref={(n:Node) -> node = n}>
			<button slot="side-back" tag="level-back" focusable={!top()} aria-label={() -> "Back to " + s.backLabel()}
				flexShrink={1} minWidth={0} opacity={shown()} pointerEvents={top() ? "none" : "auto"} onPress={() -> if (s.level.value != "") s.back()}>
				<image src={Glyphs.get("back")} width={14} height={14} flexShrink={0}/>
				<view flexShrink={1} minWidth={0}>
					<text tag="level-back-label" opacity={crossed()} lineClamp={1} textOverflow="ellipsis">{label()}</text>
					<Show when={crossed() < 1}>
						<text position="absolute" left={0} top={0} opacity={1 - crossed()} lineClamp={1}>{last()}</text>
					</Show>
				</view>
			</button>
			<view flexGrow={1}/>
			<Standard.Button tag="level-home" variant="ghost" size="sm" icon={Glyphs.get("home")} label="Overview" onPress={() -> s.show("")}/>
		</view>;
	}

	// (a level's pane: where it is, how shown; its presses the current one's
	// alone, once in place: a double click's second, or a triple's third, on
	// none of the level sliding in)
	static function pane(x:Explorer, c:Clicks, p:Pane):View
		return <view tag="sidebar-pane" position="absolute" inset={0} transform={p.x() == 0 ? "none" : "translateX(" + p.x() + "px)"} opacity={p.shown()}
			pointerEvents={p.level == x.sidebar.level() && p.x() == 0 && p.shown() >= 1 ? "auto" : "none"}>
			{p.level == "" ? overview(x, c) : level(x, c, p)}
		</view>;

	static function overview(x:Explorer, c:Clicks):View {
		var s = x.sidebar, b = x.browser;
		return <scroll tag="overview" flexGrow={1} minHeight={0} rowGap={12} paddingBottom={10}>
			<view rowGap={1}>
				<text slot="side-head">Locations</text>
				<For each={() -> s.places()}>{p -> row(c, p().name, Glyphs.place(p().kind), () -> b.dir() == Browser.normalize(p().path),
					() -> StringTools.startsWith(b.dir(), Browser.normalize(p().path) + "/"), "", () -> x.choose(p().path))}</For>
			</view>
			<Show when={s.volumes.length > 0}>
				<view rowGap={1}>
					<text slot="side-head">Devices</text>
					{[for (v in s.volumes) row(c, v.name, Glyphs.volume(v), () -> b.dir() == Browser.normalize(v.path), () -> false,
						v.root && v.total > 0 ? Kinds.size(v.free) + " free" : "", () -> x.choose(v.path))]}
				</view>
			</Show>
		</scroll>;
	}

	static function level(x:Explorer, c:Clicks, p:Pane):View {
		var s = x.sidebar, b = x.browser;
		return <view flexGrow={1} minHeight={0} rowGap={6}>
			<view flexDirection="row" alignItems="center" columnGap={8} padding="2 8 0 8">
				<text tag="level-title" fontSize={15} fontWeight={600} lineClamp={1} textOverflow="ellipsis" flexShrink={1}>{() -> s.title(p.level)}</text>
				<view flexGrow={1}/>
				<text fontSize={11.5} color={Look.ref.fg3} flexShrink={0}>{() -> folders(p.rows().length)}</text>
			</view>
			<scroll flexGrow={1} minHeight={0} rowGap={1}>
				<For each={() -> p.rows()}>{r -> folderRow(x, c, r())}</For>
			</scroll>
		</view>;
	}

	static function folders(n:Int):String
		return n == 0 ? "" : n == 1 ? "1 folder" : Kinds.count(n) + " folders";

	static function folderRow(x:Explorer, c:Clicks, r:Sidebar.Row):View {
		var b = x.browser;
		// (a click: the folder shown; a double click: into its level as "›" goes, not shown again)
		function press(e:Null<helder.ui.Event>)
			switch c.of(e, r.path) {
				case 1: b.go(r.path);
				case 2: x.sidebar.show(r.path);
				case _:
			}
		// (its context menu: Open, Rename…, Move to Trash, Show in Finder, Copy Path; a folder dropped on: moved into it)
		return <button slot="side-row" aria-label={r.name} data-selected={b.dir() == r.path} onPress={press}
			ref={(n:Node) -> {
				helder.ui.menu.ContextMenu.attach(n, () -> ViewerActions.sidebarFolder(r.path));
				Drops.folder(x, n, () -> r.path);
			}}>
			<image src={Glyphs.get("folder")} width={16} height={16} flexShrink={0} color={b.dir() == r.path ? Look.ref.fg : Look.ref.fg3}/>
			<Show when={x.sidebar.renaming() == r.path}>{() -> NameField.field(r.name, t -> x.renameFolder(r.path, t), () -> x.sidebar.renaming(""))}</Show>
			<Show when={x.sidebar.renaming() != r.path}>
				<text flexGrow={1} flexShrink={1} minWidth={0} lineClamp={1} textOverflow="ellipsis">{r.name}</text>
			</Show>
			<Show when={r.deeper}>
				<button tag="deeper" focusable={false} aria-label={"Into " + r.name} width={20} height={20} borderRadius={5} alignItems="center"
					justifyContent="center" onPress={e -> {
						// (its press the row's none)
						e.stop();
						x.sidebar.show(r.path);
					}}>
					<image src={Glyphs.get("forward")} width={14} height={14} color={Look.ref.fg3}/>
				</button>
			</Show>
		</button>;
	}

	// (a row of the overview: on when it is the folder shown, a path when the folder is inside it)
	static function row(c:Clicks, name:String, icon:String, on:Void->Bool, inside:Void->Bool, meta:String, press:Void->Void):View
		return <button slot="side-row" aria-label={name} data-selected={on()} data-state={inside() ? "open" : null}
			onPress={e -> if (c.of(e, "overview:" + name) == 1) press()}>
			<image src={Glyphs.get(icon)} width={16} height={16} flexShrink={0} color={on() || inside() ? Look.ref.fg : Look.ref.fg3}/>
			<text flexGrow={1} flexShrink={1} minWidth={0} lineClamp={1} textOverflow="ellipsis">{name}</text>
			<Show when={meta != ""}><text fontSize={11.5} color={Look.ref.fg3} flexShrink={0}>{meta}</text></Show>
		</button>;

	// (the level's volume: a card inset from the sidebar's edges, its name
	// and how full it is, a short bar of what is used, "45.3 GB free of 494
	// GB" under it; a card's, so that it can't read as a scrollbar)
	static function foot(x:Explorer):View {
		var s = x.sidebar;
		function vol():Null<Volume>
			return s.level() == "" ? null : s.volumeOf(s.level());
		function used():Float {
			var v = vol();
			return v == null || v.total <= 0 ? 0 : Math.max(0, Math.min(1, 1 - v.free / v.total));
		}
		return <Show when={vol() != null && vol().total > 0}>
			<view tag="capacity" flexShrink={0} margin="0 0 10 0" padding="8 10" rowGap={6} borderRadius={10} background={Look.ref.fill} fontSize={12}
				color={Look.ref.fg2}>
				<view flexDirection="row" alignItems="center" columnGap={7}>
					<image src={Glyphs.get(vol() == null ? "disk" : Glyphs.volume(vol()))} width={15} height={15} color={Look.ref.fg2}/>
					<text tag="capacity-name" flexGrow={1} flexShrink={1} minWidth={0} lineClamp={1} textOverflow="ellipsis" fontWeight={500} color={Look.ref.fg}>
						{() -> vol() == null ? "" : vol().name}</text>
					<text tag="capacity-used" color={Look.ref.fg3} flexShrink={0}>{() -> Math.round(used() * 100) + "%"}</text>
				</view>
				<view tag="capacity-bar" height={4} borderRadius={2} background={Look.ref.line} overflow="hidden">
					<view height="100%" borderRadius={2} background={used() > 0.9 ? Look.ref.danger : Look.ref.accent} width={() -> Math.round(used() * 1000) / 10 + "%"}/>
				</view>
				<text tag="capacity-free" fontSize={11} color={Look.ref.fg3} lineClamp={1} textOverflow="ellipsis">
					{() -> vol() == null ? "" : Kinds.size(vol().free) + " free of " + Kinds.size(vol().total)}</text>
			</view>
		</Show>;
	}
}

// (a sidebar's rows' presses: 1 a click (or Enter, Space), 2 a double
// click's second on the row of its first (each within 0.45 s and 5 points
// of the last, the grid's); 0 the second on another row, or a triple's
// third: the level slid under the pointer, pressed by none)
private class Clicks {
	var at = -1.0;
	var x = 0.0;
	var y = 0.0;
	var row = "";
	var count = 0;

	public function new() {}

	public function of(e:Null<helder.ui.Event>, row:String):Int {
		if (e == null || e.type != helder.ui.EventType.Click) return 1;
		var t = helder.ui.Ui.now(), next = at >= 0 && t - at < 0.45 && Math.abs(e.x - x) < 5 && Math.abs(e.y - y) < 5;
		at = t;
		x = e.x;
		y = e.y;
		if (next) return ++count == 2 && this.row == row ? 2 : 0;
		count = 1;
		this.row = row;
		return 1;
	}
}

// (one level in the sidebar: its rows (the model's while it is the current
// level, its own after), where it is (its offset in points, a spring) and
// how shown (reduced motion's fade))
private class Pane {
	public final level:String;
	public final rows:helder.view.graph.Signal<Array<Sidebar.Row>>;
	// (its springs: another level's carried over when it takes that one's place)
	public var at = new helder.ui.motion.Track(0, 0.01);
	public var fade = new helder.ui.motion.Track(1, 1e-3);
	public final x = helder.view.graph.Graph.signal(0.0);
	public final shown = helder.view.graph.Graph.signal(1.0);

	public function new(level:String, rows:Array<Sidebar.Row>) {
		this.level = level;
		this.rows = helder.view.graph.Graph.signal(rows);
	}

	// (a spring's tail ended within a device pixel, or slow within two: at its target)
	public static function snap(tr:helder.ui.motion.Track, scale:Float) {
		if (!tr.moving()) return;
		var left = Math.abs(tr.target - tr.value) * scale, speed = Math.abs(tr.velocity) * scale;
		if (left < 1 || left < 2 && speed < 30) tr.set(tr.target);
	}
}
