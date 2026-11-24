package viewer;

import helder.ui.Node;
import helder.ui.controls.Look;
import helder.ui.controls.Standard;
import helder.ui.menu.Menus;
import helder.ui.widgets.WindowButtons;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import viewer.Files;
import viewer.Preview.Shown;
import viewer.ViewerActions;

// The inspector (300 points, Mod+I): the selected file's preview in a box
// 220 high (an image fitted, a PDF's first page with its page count, a
// video's keyframe with its duration, else its glyph), its name, kind and
// size, Open, Show in folder, Move to Trash and More, and its details:
// what is known without opening any file but this one. Nothing selected:
// the folder's own.
class InspectorView implements Markup {
	public static inline var WIDTH = 300;
	public static inline var BOX = 220;

	public static function make(x:Explorer):View {
		var b = x.browser, shown:Signal<Null<Shown>> = signal((null : Null<Shown>)), stop:Null<Void->Void> = null;
		// (the selection's preview, one at a time: the last one's stopped)
		effect(() -> {
			b.selected();
			b.items();
			var e = b.current();
			e == null || e.kind == Folder || !Kinds.viewable(e) ? "" : b.path(e.name);
		}, path -> {
			if (stop != null) stop();
			stop = null;
			shown(null);
			if (path != "") stop = x.preview(path, s -> shown(s));
		});
		onCleanup(() -> if (stop != null) stop());
		function entry():Null<Entry> {
			b.selected();
			b.items();
			b.selection.version();
			return b.picked().length > 1 ? null : b.current();
		}
		function several():Array<Entry> {
			b.items();
			b.selection.version();
			var picked = b.picked();
			return picked.length > 1 ? [for (n in picked) b.entry(n)] : [];
		}
		return <view tag="inspector" slot="panel" width={WIDTH} shrink={0} margin="8 8 8 0" overflow="hidden">
			<Show when={several().length > 1}>{() -> {
				var all = several();
				all.length > 1 ? many(x, all) : null;
			}}</Show>
			<Show when={entry() != null}>{() -> {
				var e = entry();
				e == null ? null : file(x, e, shown);
			}}</Show>
			<Show when={entry() == null && several().length < 2}>{() -> folder(x)}</Show>
		</view>;
	}

	static function file(x:Explorer, e:Entry, shown:Signal<Null<Shown>>):View {
		var more:Null<Node> = null;
		return <view grow={1} min-height={0}>
			<view tag="preview" height={BOX} shrink={0} margin="14 14 0 14" radius={10} background={Look.ref.well} align-items="center" justify="center"
				overflow="hidden">
				{() -> picture(x, e, shown())}
			</view>
			<view padding="12 16 0 16" align-items="center" row-gap={2}>
				<text tag="inspector-name" font-size={14} font-weight={600} max-lines={1} text-overflow="ellipsis" text-align="center">{e.name}</text>
				<text tag="inspector-kind" font-size={12} color={Look.ref.fg3} max-lines={1}>{() -> subtitle(e, shown())}</text>
			</view>
			<view direction="row" justify="center" column-gap={6} padding="12 16 14 16">
				<Standard.Button tag="open" variant="primary" size="sm" onPress={() -> x.open(e.name)}>Open</Standard.Button>
				<Standard.Button tag="reveal" size="sm" icon={Glyphs.get("folder")} label={ViewerActions.reveal()} onPress={() -> x.perform(ShowInFolder)}/>
				<Show when={x.files.trash != null}>
					<Standard.Button tag="trash" size="sm" icon={Glyphs.get("trash")} label={ViewerActions.trashLabel()} onPress={() -> x.perform(Trash)}/>
				</Show>
				<view ref={(n:Node) -> more = n}>
					<Standard.Button tag="more" size="sm" icon={Glyphs.get("more")} label="More" onPress={() -> if (more != null && more.ui != null) {
						var r = more.rect();
						Menus.popup(more.ui, ViewerActions.more, r.x, r.y + r.height + 4, more);
					}}/>
				</view>
			</view>
			<view tag="details" padding="10 16 6 16" borders="1 0 0 0" border-color={Look.ref.line}>
				<view direction="row" align-items="center" column-gap={6} height={24}>
					<image src={Glyphs.get("info")} width={14} height={14} color={Look.ref.fg3}/>
					<text font-size={11} font-weight={600} color={Look.ref.fg3}>DETAILS</text>
				</view>
				{() -> [for (kv in details(e, shown())) <view direction="row" justify="space-between" column-gap={12} height={24} align-items="center" font-size={12.5}>
					<text color={Look.ref.fg3} shrink={0}>{kv.k}</text>
					<text max-lines={1} text-overflow="ellipsis" text-align="right" shrink={1}>{kv.v}</text>
				</view>]}
			</view>
		</view>;
	}

	// (several selected: a fanned stack of the first three, how many, their
	// kinds and total size; actions on all of them)
	static function many(x:Explorer, all:Array<Entry>):View {
		var size = 0.0, kinds = new Map<String, Int>();
		for (e in all) {
			size += e.size;
			var k = Kinds.kind(e);
			kinds.set(k, (kinds.get(k) ?? 0) + 1);
		}
		var kindText = [for (k => n in kinds) '$n ${n == 1 ? k : plural(k)}'];
		kindText.sort(Reflect.compare);
		var fan = [
			{e: all[1], t: "translate(-62px, 4px) rotate(-8deg)", side: 132},
			{e: all.length > 2 ? all[2] : null, t: "translate(62px, 4px) rotate(8deg)", side: 132},
			{e: all[0], t: "none", side: 140}
		];
		return <view grow={1} min-height={0}>
			<view tag="preview" height={BOX} shrink={0} margin="14 14 0 14" radius={10} background={Look.ref.well} align-items="center" justify="center"
				overflow="hidden">
				{[for (f in fan) if (f.e != null) card(x, f.e, f.side, f.t)]}
			</view>
			<view padding="12 16 0 16" align-items="center" row-gap={2}>
				<text tag="inspector-name" font-size={14} font-weight={600}>{Kinds.items(all.length)}</text>
				<text tag="inspector-kind" font-size={12} color={Look.ref.fg3} max-lines={1}>{(Lambda.count(kinds) == 1 ? Kinds.kind(all[0]) + " · " : "") + Kinds.size(size)}</text>
			</view>
			<view direction="row" justify="center" column-gap={6} padding="12 16 14 16">
				<Standard.Button tag="open" variant="primary" size="sm" onPress={() -> x.open()}>{"Open " + all.length}</Standard.Button>
				<Standard.Button tag="reveal" size="sm" icon={Glyphs.get("folder")} label={ViewerActions.reveal()} onPress={() -> x.perform(ShowInFolder)}/>
				<Show when={x.files.trash != null}>
					<Standard.Button tag="trash" size="sm" icon={Glyphs.get("trash")} label={ViewerActions.trashLabel()} onPress={() -> x.perform(Trash)}/>
				</Show>
			</view>
			<view tag="details" padding="10 16 6 16" borders="1 0 0 0" border-color={Look.ref.line}>
				<view direction="row" align-items="center" column-gap={6} height={24}>
					<image src={Glyphs.get("info")} width={14} height={14} color={Look.ref.fg3}/>
					<text font-size={11} font-weight={600} color={Look.ref.fg3}>SELECTION</text>
				</view>
				{[for (kv in [{k: "Total size", v: Kinds.size(size)}, {k: "Kinds", v: kindText.join(", ")}])
					<view direction="row" justify="space-between" column-gap={12} height={24} align-items="center" font-size={12.5}>
						<text color={Look.ref.fg3} shrink={0}>{kv.k}</text>
						<text max-lines={1} text-overflow="ellipsis" text-align="right" shrink={1}>{kv.v}</text>
					</view>]}
			</view>
		</view>;
	}

	// (a card of the stack: the thumbnail, else the glyph, on a white mat)
	static function card(x:Explorer, e:Entry, side:Float, transform:String):View {
		var t = Tiles.thumbnail(x, e);
		return <view position="absolute" width={side} height={side} radius={8} padding={3} background="#ffffff" transform={transform}
			shadow="0 4px 14px rgba(0,0,0,0.22)" align-items="center" justify="center" overflow="hidden">
			<Show when={t().image != null}><image src={t().image} width={side - 6} height={side - 6} fit="cover" radius={6}/></Show>
			<Show when={t().image == null}>{Tiles.large(e)}</Show>
		</view>;
	}

	static function plural(kind:String):String
		return StringTools.endsWith(kind, "s") ? kind : kind + "s";

	// (nothing selected: the folder's picture, its name, how many items)
	static function folder(x:Explorer):View {
		var b = x.browser;
		return <view grow={1}>
			<view height={BOX} shrink={0} margin="14 14 0 14" radius={10} background={Look.ref.well} align-items="center" justify="center">
				{Tiles.large({name: "", kind: Folder, size: 0, modified: 0, created: 0})}
			</view>
			<view padding="12 16 0 16" align-items="center" row-gap={2}>
				<text font-size={14} font-weight={600} max-lines={1} text-overflow="ellipsis">{() -> x.sidebar.title(b.dir())}</text>
				<text font-size={12} color={Look.ref.fg3}>{() -> b.reading() ? "Reading…" : Kinds.items(b.items().length)}</text>
			</view>
		</view>;
	}

	// (the box's content: the picture fitted, a PDF's count, a video's duration; else the glyph)
	static function picture(x:Explorer, e:Entry, s:Null<Shown>):View {
		var img = s == null ? null : s.image;
		if (img == null) img = Tiles.cached(x, e);
		if (img == null) return Tiles.large(e);
		var k = Math.min(252 / img.width, 188 / img.height);
		var w = Math.round(img.width * k), h = Math.round(img.height * k);
		// (the thumbnail while the preview comes: nothing known of it yet; a Show's children are made with it)
		var pages = s == null ? 0 : s.pages, duration = s == null ? 0.0 : s.duration;
		return <view align-items="center" justify="center" width="100%" height="100%">
			<image tag="preview-image" src={img} width={w} height={h} radius={4} shadow="0 4px 16px rgba(0,0,0,0.4)"/>
			<Show when={pages > 1}>
				<text tag="pages" position="absolute" bottom={8} padding="2 8" radius={9} background="rgba(10,10,10,0.6)" color="#ffffff" font-size={11.5}>{'1 / $pages'}</text>
			</Show>
			<Show when={duration > 0}>
				<text tag="duration" position="absolute" right={10} bottom={10} padding="0 5" radius={4} background="rgba(0,0,0,0.62)" color="#ffffff"
					font-size={10.5} font-weight={600}>{clock(duration)}</text>
			</Show>
		</view>;
	}

	public static function subtitle(e:Entry, s:Null<Shown>):String {
		var kind = Kinds.kind(e);
		if (s != null && s.pages > 1) return '$kind · ${s.pages} pages';
		if (s != null && s.duration > 0) return '$kind · ${clock(s.duration)}';
		return e.kind == Folder ? kind : '$kind · ${Kinds.size(e.size)}';
	}

	// what is known: the entry's, and what the preview learnt
	public static function details(e:Entry, s:Null<Shown>):Array<{k:String, v:String}> {
		var out = [];
		if (e.kind != Folder) out.push({k: "Size", v: Kinds.size(e.size)});
		out.push({k: "Kind", v: Kinds.kind(e)});
		if (s != null && s.width > 0 && s.pages <= 1) {
			var mp = Math.round(s.width * s.height / 1e5) / 10;
			out.push({k: "Dimensions", v: '${s.width} × ${s.height}' + (mp >= 1 ? ' · $mp MP' : "")});
		}
		if (s != null && s.pages > 1) out.push({k: "Pages", v: Std.string(s.pages)});
		if (s != null && s.duration > 0) out.push({k: "Duration", v: clock(s.duration)});
		if (e.modified > 0) out.push({k: "Modified", v: Kinds.date(e.modified)});
		if (e.created > 0) out.push({k: "Created", v: Kinds.date(e.created)});
		return out;
	}

	static function clock(t:Float):String {
		var s = Std.int(Math.max(0, t)), m = Std.int(s / 60), h = Std.int(m / 60);
		var ss = StringTools.lpad(Std.string(s % 60), "0", 2);
		return h > 0 ? '$h:${StringTools.lpad(Std.string(m % 60), "0", 2)}:$ss' : '$m:$ss';
	}
}
