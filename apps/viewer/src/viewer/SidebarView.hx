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
// capacity at the foot), one level at a time (Sidebar), a level entered
// sliding in from the side it is on (a push's, as iOS's and Files'): a
// deeper one from the right, an enclosing one from the left, 16 points
// and a fade over SLIDE (reduced motion: the fade). On macOS its top
// holds the window's buttons (the shell's WindowControls over it).
class SidebarView implements Markup {
	public static inline var WIDTH = 236;
	// (a level's slide: short, easing out; the distance a hint of the direction)
	public static final SLIDE = helder.ui.motion.Curve.tween(0.18, helder.ui.Transition.EASE_OUT);
	static inline var SHIFT = 16;

	public static function make(x:Explorer):View {
		var s = x.sidebar, b = x.browser, body:Null<Node> = null, was = s.level.value;
		var move = new helder.ui.motion.Track(1, 1e-4), dx = signal(0.0), shown = signal(1.0), side = 1, ticking = false;
		// (another level: its rows from the side it is on, then in place)
		renderEffect(() -> s.level(), level -> {
			var n = body, from = was;
			was = level;
			if (n == null || n.ui == null || level == from) return;
			var deeper = from == "" || StringTools.startsWith(level, from + "/") || (StringTools.endsWith(from, "/") && StringTools.startsWith(level, from));
			var reduced = helder.ui.Clock.reducedMotion;
			side = reduced ? 0 : deeper ? 1 : -1;
			move.set(0);
			move.animate(-1, 1, reduced ? helder.ui.motion.Curve.REDUCED_FADE : SLIDE);
			dx(side * SHIFT);
			shown(0);
			if (ticking) return;
			ticking = true;
			helder.ui.Clock.addFor(n, t -> {
				move.sample(t);
				dx(side * SHIFT * (1 - move.value));
				shown(move.value);
				return ticking = move.moving();
			});
		});
		return <view tag="sidebar" width={WIDTH} shrink={0} padding="0 10" row-gap={6} overflow="hidden"
			padding-top={WindowButtons.side() == "start" ? 0 : 8}>
			<Show when={WindowButtons.side() == "start"}><view height={Shell.BAR} shrink={0} drag-region/></Show>
			<view tag="sidebar-body" grow={1} min-height={0} transform={dx() == 0 ? "none" : "translateX(" + dx() + "px)"} opacity={shown()}
				ref={(n:Node) -> body = n}>
				<Show when={s.level() == ""}>{overview(x)}</Show>
				<Show when={s.level() != ""}>{level(x)}</Show>
			</view>
		</view>;
	}

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

	static function level(x:Explorer):View {
		var s = x.sidebar, b = x.browser;
		return <view grow={1} min-height={0} row-gap={6}>
			<view direction="row" align-items="center" padding="0 2" column-gap={2}>
				<view:button slot="side-back" tag="level-back" role="button" focusable label={() -> "Back to " + (s.level() == "" ? "" : s.backLabel())}
					onPress={() -> s.back()}>
					<image src={Glyphs.get("back")} width={14} height={14}/>
					<text max-lines={1} text-overflow="ellipsis">{() -> s.level() == "" ? "" : s.backLabel()}</text>
				</view:button>
				<view grow={1}/>
				<Standard.Button tag="level-home" variant="ghost" size="sm" icon={Glyphs.get("home")} label="Overview" onPress={() -> s.show("")}/>
			</view>
			<view direction="row" align-items="center" column-gap={8} padding="2 8 0 8">
				<text tag="level-title" font-size={15} font-weight={600} max-lines={1} text-overflow="ellipsis" shrink={1}>{() -> s.title(s.level())}</text>
				<view grow={1}/>
				<text font-size={11.5} color={Look.ref.fg3} shrink={0}>{() -> folders(s.rows().length)}</text>
			</view>
			<scroll grow={1} min-height={0} row-gap={1}>
				<For each={() -> s.rows()}>{r -> folderRow(x, r())}</For>
			</scroll>
			{foot(x)}
		</view>;
	}

	static function folders(n:Int):String
		return n == 0 ? "" : n == 1 ? "1 folder" : Kinds.count(n) + " folders";

	static function folderRow(x:Explorer, r:Sidebar.Row):View {
		var b = x.browser;
		return <view:button slot="side-row" role="button" focusable label={r.name} data-selected={b.dir() == r.path} onPress={() -> b.go(r.path)}>
			<image src={Glyphs.get("folder")} width={16} height={16} shrink={0} color={b.dir() == r.path ? Look.ref.fg : Look.ref.fg3}/>
			<text grow={1} shrink={1} min-width={0} max-lines={1} text-overflow="ellipsis">{r.name}</text>
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
	static function foot(x:Explorer):View {
		var s = x.sidebar;
		function vol():Null<Volume>
			return s.level() == "" ? null : s.volumeOf(s.level());
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
