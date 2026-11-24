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
// capacity at the foot), one level at a time (Sidebar). On macOS its top
// holds the window's buttons (the shell's WindowControls over it).
class SidebarView implements Markup {
	public static inline var WIDTH = 236;

	public static function make(x:Explorer):View {
		var s = x.sidebar, b = x.browser;
		return <view tag="sidebar" width={WIDTH} shrink={0} padding="0 10" row-gap={6} overflow="hidden"
			padding-top={WindowButtons.side() == "start" ? 0 : 8}>
			<Show when={WindowButtons.side() == "start"}><view height={Shell.BAR} shrink={0} drag-region/></Show>
			<Show when={s.level() == ""}>{overview(x)}</Show>
			<Show when={s.level() != ""}>{level(x)}</Show>
		</view>;
	}

	static function overview(x:Explorer):View {
		var s = x.sidebar, b = x.browser;
		return <scroll tag="overview" grow={1} min-height={0} row-gap={12} padding-bottom={10}>
			<view row-gap={1}>
				<text slot="side-head">Locations</text>
				{[for (p in s.places) row(p.name, Glyphs.place(p.kind), () -> b.dir() == Browser.normalize(p.path),
					() -> StringTools.startsWith(b.dir(), Browser.normalize(p.path) + "/"), "", () -> x.choose(p.path))]}
			</view>
			<view row-gap={1}>
				<text slot="side-head">Devices</text>
				{[for (v in s.volumes) row(v.name, Glyphs.volume(v), () -> b.dir() == Browser.normalize(v.path), () -> false,
					v.root && v.total > 0 ? Kinds.size(v.free) + " free" : "", () -> x.choose(v.path))]}
			</view>
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

	// (the level's volume: its name, what is free, a bar of what is used)
	static function foot(x:Explorer):View {
		var s = x.sidebar;
		function vol():Null<Volume>
			return s.level() == "" ? null : s.volumeOf(s.level());
		return <Show when={vol() != null && vol().total > 0}>
			<view tag="capacity" height={ContentView.FOOT} shrink={0} margin="0 -10" padding="0 18" justify="center" row-gap={4} borders="1 0 0 0"
				border-color={Look.ref.line} font-size={12} color={Look.ref.fg2}>
				<view direction="row" align-items="center" column-gap={8}>
					<image src={Glyphs.get(vol() == null ? "disk" : Glyphs.volume(vol()))} width={14} height={14} color={Look.ref.fg3}/>
					<text grow={1} shrink={1} max-lines={1} text-overflow="ellipsis">{() -> vol() == null ? "" : vol().name}</text>
					<text color={Look.ref.fg3} shrink={0}>{() -> vol() == null ? "" : Kinds.size(vol().free) + " free"}</text>
				</view>
				<view height={3} radius={2} background={Look.ref.fill} overflow="hidden">
					<view height="100%" background={Look.ref.fg3}
						width={() -> vol() == null || vol().total <= 0 ? "0%" : Math.round(100 * (1 - vol().free / vol().total)) + "%"}/>
				</view>
			</view>
		</Show>;
	}
}
