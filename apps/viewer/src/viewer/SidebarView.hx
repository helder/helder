package viewer;

import helder.os.Places;
import helder.ui.Node;
import helder.ui.controls.Look;
import helder.ui.controls.Standard;
import helder.ui.widgets.WindowButtons;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// The sidebar (236 points): the overview (Locations, Devices) or a
// folder's level (a back row, its title, its subfolders, its volume's
// capacity at the foot), one level at a time (Sidebar), going between
// levels as a navigation push: the new level slides in from its side (a
// deeper one from the right, an enclosing one from the left) as the old
// one slides out the other way, both together, clipped to the sidebar, on
// the picture's flight's spring (Flight.SPRING) at whole-point offsets, its
// tail ended within a device pixel; clicked again on the way, each pane
// turns from where it is, as fast (the one going back to: the one still
// sliding out). Its rows are there before it moves (Sidebar keeps a level
// until its new one's are read); the one going keeps its own. Reduced
// motion: a cross-fade. On macOS its top holds the window's buttons (the
// shell's WindowControls over it).
class SidebarView implements Markup {
	public static inline var WIDTH = 236;

	public static function make(x:Explorer):View {
		var s = x.sidebar, body:Null<Node> = null, ticking = false;
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
			if (n == null || n.ui == null) {
				panes([new Pane(level, s.rows.value)]);
				return;
			}
			var deeper = now.level == "" || StringTools.startsWith(level, now.level + "/")
				|| (StringTools.endsWith(now.level, "/") && StringTools.startsWith(level, now.level));
			var dir = deeper ? 1 : -1, w = n.width > 0 ? n.width : WIDTH, reduced = helder.ui.Clock.reducedMotion;
			// (the level asked for still on its way out: back from where it is)
			var into = Lambda.find(list, p -> p.level == level);
			if (into == null) {
				into = new Pane(level, s.rows.value);
				if (reduced) into.fade.set(0) else into.at.set(dir * w);
				into.x(Math.round(into.at.value));
				into.shown(into.fade.value);
			} else into.rows(s.rows.value);
			for (p in list)
				if (p != into) {
					if (reduced) p.fade.animate(-1, 0, helder.ui.motion.Curve.REDUCED_FADE) else p.at.animate(-1, -dir * w, Flight.SPRING);
				}
			if (reduced) into.fade.animate(-1, 1, helder.ui.motion.Curve.REDUCED_FADE) else into.at.animate(-1, 0, Flight.SPRING);
			panes(list.filter(p -> p != into).concat([into]));
			if (ticking) return;
			ticking = true;
			helder.ui.Clock.addFor(n, step);
		});
		return <view tag="sidebar" width={WIDTH} shrink={0} padding="0 10" row-gap={6} overflow="hidden"
			padding-top={WindowButtons.side() == "start" ? 0 : 8}>
			<Show when={WindowButtons.side() == "start"}><view height={Shell.BAR} shrink={0} drag-region/></Show>
			<view tag="sidebar-body" grow={1} min-height={0} ref={(n:Node) -> body = n}>
				<For each={panes}>{p -> pane(x, p.peek())}</For>
			</view>
		</view>;
	}

	// (a level's pane: where it is, how shown; its presses the current one's alone)
	static function pane(x:Explorer, p:Pane):View
		return <view tag="sidebar-pane" position="absolute" inset={0} transform={p.x() == 0 ? "none" : "translateX(" + p.x() + "px)"} opacity={p.shown()}
			pointer-events={p.level == x.sidebar.level() ? "auto" : "none"}>
			{p.level == "" ? overview(x) : level(x, p)}
		</view>;

	static function overview(x:Explorer):View {
		var s = x.sidebar, b = x.browser;
		return <scroll tag="overview" grow={1} min-height={0} row-gap={12} padding-bottom={10}>
			<view row-gap={1}>
				<text slot="side-head">Locations</text>
				<For each={() -> s.places()}>{p -> row(p().name, Glyphs.place(p().kind), () -> b.dir() == Browser.normalize(p().path),
					() -> StringTools.startsWith(b.dir(), Browser.normalize(p().path) + "/"), "", () -> x.choose(p().path))}</For>
			</view>
			<Show when={s.volumes.length > 0}>
				<view row-gap={1}>
					<text slot="side-head">Devices</text>
					{[for (v in s.volumes) row(v.name, Glyphs.volume(v), () -> b.dir() == Browser.normalize(v.path), () -> false,
						v.root && v.total > 0 ? Kinds.size(v.free) + " free" : "", () -> x.choose(v.path))]}
				</view>
			</Show>
		</scroll>;
	}

	static function level(x:Explorer, p:Pane):View {
		var s = x.sidebar, b = x.browser;
		return <view grow={1} min-height={0} row-gap={6}>
			<view direction="row" align-items="center" padding="0 2" column-gap={2}>
				<view:button slot="side-back" tag="level-back" role="button" focusable label={"Back to " + s.backLabelOf(p.level)}
					onPress={() -> s.back()}>
					<image src={Glyphs.get("back")} width={14} height={14}/>
					<text max-lines={1} text-overflow="ellipsis">{s.backLabelOf(p.level)}</text>
				</view:button>
				<view grow={1}/>
				<Standard.Button tag="level-home" variant="ghost" size="sm" icon={Glyphs.get("home")} label="Overview" onPress={() -> s.show("")}/>
			</view>
			<view direction="row" align-items="center" column-gap={8} padding="2 8 0 8">
				<text tag="level-title" font-size={15} font-weight={600} max-lines={1} text-overflow="ellipsis" shrink={1}>{() -> s.title(p.level)}</text>
				<view grow={1}/>
				<text font-size={11.5} color={Look.ref.fg3} shrink={0}>{() -> folders(p.rows().length)}</text>
			</view>
			<scroll grow={1} min-height={0} row-gap={1}>
				<For each={() -> p.rows()}>{r -> folderRow(x, r())}</For>
			</scroll>
			{foot(x, p.level)}
		</view>;
	}

	static function folders(n:Int):String
		return n == 0 ? "" : n == 1 ? "1 folder" : Kinds.count(n) + " folders";

	static function folderRow(x:Explorer, r:Sidebar.Row):View {
		var b = x.browser;
		// (its context menu: Open, Rename…, Move to Trash, Show in Finder, Copy Path; a folder dropped on: moved into it)
		return <view:button slot="side-row" role="button" focusable label={r.name} data-selected={b.dir() == r.path} onPress={() -> b.go(r.path)}
			ref={(n:Node) -> {
				helder.ui.menu.ContextMenu.attach(n, () -> ViewerActions.sidebarFolder(r.path));
				Drops.folder(x, n, () -> r.path);
			}}>
			<image src={Glyphs.get("folder")} width={16} height={16} shrink={0} color={b.dir() == r.path ? Look.ref.fg : Look.ref.fg3}/>
			<Show when={x.sidebar.renaming() == r.path}>{() -> NameField.field(r.name, t -> x.renameFolder(r.path, t), () -> x.sidebar.renaming(""))}</Show>
			<Show when={x.sidebar.renaming() != r.path}>
				<text grow={1} shrink={1} min-width={0} max-lines={1} text-overflow="ellipsis">{r.name}</text>
			</Show>
			<Show when={r.deeper}>
				<view:button tag="deeper" role="button" label={"Into " + r.name} width={20} height={20} radius={5} align-items="center" justify="center"
					onPress={() -> x.sidebar.show(r.path)} onClick={e -> e.stop()}>
					<image src={Glyphs.get("forward")} width={14} height={14} color={Look.ref.fg3}/>
				</view:button>
			</Show>
		</view:button>;
	}

	// (a row of the overview: on when it is the folder shown, a path when the folder is inside it)
	static function row(name:String, icon:String, on:Void->Bool, inside:Void->Bool, meta:String, press:Void->Void):View
		return <view:button slot="side-row" role="button" focusable label={name} data-selected={on()} data-state={inside() ? "open" : null} onPress={press}>
			<image src={Glyphs.get(icon)} width={16} height={16} shrink={0} color={on() || inside() ? Look.ref.fg : Look.ref.fg3}/>
			<text grow={1} shrink={1} min-width={0} max-lines={1} text-overflow="ellipsis">{name}</text>
			<Show when={meta != ""}><text font-size={11.5} color={Look.ref.fg3} shrink={0}>{meta}</text></Show>
		</view:button>;

	// (the level's volume: a card inset from the sidebar's edges, its name
	// and how full it is, a short bar of what is used, "45.3 GB free of 494
	// GB" under it; a card's, so that it can't read as a scrollbar)
	static function foot(x:Explorer, at:String):View {
		var s = x.sidebar;
		function vol():Null<Volume>
			return at == "" ? null : s.volumeOf(at);
		function used():Float {
			var v = vol();
			return v == null || v.total <= 0 ? 0 : Math.max(0, Math.min(1, 1 - v.free / v.total));
		}
		return <Show when={vol() != null && vol().total > 0}>
			<view tag="capacity" shrink={0} margin="0 0 10 0" padding="8 10" row-gap={6} radius={10} background={Look.ref.fill} font-size={12}
				color={Look.ref.fg2}>
				<view direction="row" align-items="center" column-gap={7}>
					<image src={Glyphs.get(vol() == null ? "disk" : Glyphs.volume(vol()))} width={15} height={15} color={Look.ref.fg2}/>
					<text tag="capacity-name" grow={1} shrink={1} min-width={0} max-lines={1} text-overflow="ellipsis" font-weight={500} color={Look.ref.fg}>
						{() -> vol() == null ? "" : vol().name}</text>
					<text tag="capacity-used" color={Look.ref.fg3} shrink={0}>{() -> Math.round(used() * 100) + "%"}</text>
				</view>
				<view tag="capacity-bar" height={4} radius={2} background={Look.ref.line} overflow="hidden">
					<view height="100%" radius={2} background={used() > 0.9 ? Look.ref.danger : Look.ref.accent} width={() -> Math.round(used() * 1000) / 10 + "%"}/>
				</view>
				<text tag="capacity-free" font-size={11} color={Look.ref.fg3} max-lines={1} text-overflow="ellipsis">
					{() -> vol() == null ? "" : Kinds.size(vol().free) + " free of " + Kinds.size(vol().total)}</text>
			</view>
		</Show>;
	}
}

// (one level in the sidebar: its rows (the model's while it is the current
// level, its own after), where it is (its offset in points, a spring) and
// how shown (reduced motion's fade))
private class Pane {
	public final level:String;
	public final rows:helder.view.graph.Signal<Array<Sidebar.Row>>;
	public final at = new helder.ui.motion.Track(0, 0.01);
	public final fade = new helder.ui.motion.Track(1, 1e-3);
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
