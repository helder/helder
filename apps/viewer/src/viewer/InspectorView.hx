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
// video's keyframe with its duration, a Markdown document's first screen
// with its words and headings, else its glyph), its name, kind and
// size, Open, Show in folder, Move to Trash and More, and its details:
// what is known without opening any file but this one. Nothing selected:
// the folder's own.
@:renderer(helder.ui.view.NodeRenderer)
class InspectorView implements Markup {
	public static inline var WIDTH = 300;
	public static inline var BOX = 220;

	// (fill: as wide as its place, a sheet's)
	public static function make(x:Explorer, fill = false):View {
		var b = x.browser, shown:Signal<Null<Shown>> = signal((null : Null<Shown>)), stop:Null<Void->Void> = null;
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
		// (keys: the same while the entries are, a filter's or a sort's change
		// of the items none, so that nothing is made or decoded again)
		var preview = memo(() -> {
			b.selected();
			b.items();
			var e = b.current();
			e == null || e.kind == Folder || !Kinds.viewable(e) ? "" : key(b, e);
		});
		var one = memo(() -> {
			var e = entry();
			e == null ? "" : key(b, e);
		});
		var many = memo(() -> [for (e in several()) key(b, e)].join("\n"));
		// (the selection's preview, one at a time: the last one's stopped)
		effect(() -> preview(), k -> {
			if (stop != null) stop();
			stop = null;
			shown(null);
			if (k != "") stop = x.preview(k.substr(0, k.indexOf("\t")), s -> shown(s));
		});
		onCleanup(() -> if (stop != null) stop());
		// (Windows' and Linux's window buttons over its top: the toolbar's row carried on, a title bar's)
		return <view tag="inspector" slot="panel" width={fill ? "100%" : WIDTH} flexGrow={fill ? 1 : 0} flexShrink={0} overflow="hidden"
			borders={fill ? "0 0 0 0" : "0 0 0 1"} borderColor={Look.ref.line}>
			<Show when={!fill && WindowButtons.side() == "end"}>
				<view tag="inspector-bar" height={Shell.BAR} flexShrink={0} dragRegion borders="0 0 1 0" borderColor={Look.ref.line}/>
			</Show>
			<Show when={many() != ""}>{() -> {
				many();
				var all = untrack(several);
				all.length > 1 ? InspectorView.many(x, all) : null;
			}}</Show>
			<Show when={one() != ""}>{() -> {
				one();
				var e = untrack(entry);
				e == null ? null : file(x, e, shown);
			}}</Show>
			<Show when={one() == "" && many() == ""}>{() -> folder(x)}</Show>
		</view>;
	}

	// (an entry by its path, size and modified time: its file changed, another key)
	static function key(b:Browser, e:Entry):String
		return b.path(e.name) + "\t" + e.size + "\t" + e.modified;

	static function file(x:Explorer, e:Entry, shown:Signal<Null<Shown>>):View {
		var more:Null<Node> = null;
		return <view flexGrow={1} minHeight={0}>
			<view tag="preview" height={BOX} flexShrink={0} margin="14 14 0 14" borderRadius={10} background={Look.ref.well} alignItems="center" justifyContent="center"
				overflow="hidden">
				{() -> picture(x, e, shown())}
			</view>
			<view padding="12 16 0 16" alignItems="center" rowGap={2}>
				<text tag="inspector-name" fontSize={14} fontWeight={600} lineClamp={1} textOverflow="ellipsis" textAlign="center">{e.name}</text>
				<text tag="inspector-kind" fontSize={12} color={Look.ref.fg3} lineClamp={1}>{() -> subtitle(e, shown())}</text>
			</view>
			<view flexDirection="row" justifyContent="center" columnGap={6} padding="12 16 14 16">
				<Standard.Button tag="open" variant="primary" size="sm" onPress={() -> x.open(e.name)}>Open</Standard.Button>
				<Show when={ViewerActions.LOCAL}>
					<Standard.Button tag="reveal" size="sm" icon={Glyphs.get("folder")} label={ViewerActions.reveal()} onPress={() -> x.perform(ShowInFolder)}/>
				</Show>
				<Show when={x.files.trash != null}>
					<Standard.Button tag="trash" size="sm" icon={Glyphs.get("trash")} label={ViewerActions.trashLabel()} onPress={() -> x.perform(Trash)}/>
				</Show>
				<Show when={ViewerActions.LOCAL}>
					<view ref={(n:Node) -> more = n}>
						<Standard.Button tag="more" size="sm" icon={Glyphs.get("more")} label="More" onPress={() -> if (more != null && more.ui != null) {
							var r = more.rect();
							Menus.popup(more.ui, ViewerActions.more, r.x, r.y + r.height + 4, more);
						}}/>
					</view>
				</Show>
			</view>
			<view tag="details" padding="10 16 6 16" borders="1 0 0 0" borderColor={Look.ref.line}>
				<view flexDirection="row" alignItems="center" columnGap={6} height={24}>
					<image src={Glyphs.get("info")} width={14} height={14} color={Look.ref.fg3}/>
					<text fontSize={11} fontWeight={600} color={Look.ref.fg3}>DETAILS</text>
				</view>
				{() -> [for (kv in details(e, shown())) <view flexDirection="row" justifyContent="space-between" columnGap={12} height={24} alignItems="center" fontSize={12.5}>
					<text color={Look.ref.fg3} flexShrink={0}>{kv.k}</text>
					<text lineClamp={1} textOverflow="ellipsis" textAlign="right" flexShrink={1}>{kv.v}</text>
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
		return <view flexGrow={1} minHeight={0}>
			<view tag="preview" height={BOX} flexShrink={0} margin="14 14 0 14" borderRadius={10} background={Look.ref.well} alignItems="center" justifyContent="center"
				overflow="hidden">
				{[for (f in fan) if (f.e != null) card(x, f.e, f.side, f.t)]}
			</view>
			<view padding="12 16 0 16" alignItems="center" rowGap={2}>
				<text tag="inspector-name" fontSize={14} fontWeight={600}>{Kinds.items(all.length)}</text>
				<text tag="inspector-kind" fontSize={12} color={Look.ref.fg3} lineClamp={1}>{(Lambda.count(kinds) == 1 ? Kinds.kind(all[0]) + " · " : "") + Kinds.size(size)}</text>
			</view>
			<view flexDirection="row" justifyContent="center" columnGap={6} padding="12 16 14 16">
				<Standard.Button tag="open" variant="primary" size="sm" onPress={() -> x.open()}>{"Open " + all.length}</Standard.Button>
				<Show when={ViewerActions.LOCAL}>
					<Standard.Button tag="reveal" size="sm" icon={Glyphs.get("folder")} label={ViewerActions.reveal()} onPress={() -> x.perform(ShowInFolder)}/>
				</Show>
				<Show when={x.files.trash != null}>
					<Standard.Button tag="trash" size="sm" icon={Glyphs.get("trash")} label={ViewerActions.trashLabel()} onPress={() -> x.perform(Trash)}/>
				</Show>
			</view>
			<view tag="details" padding="10 16 6 16" borders="1 0 0 0" borderColor={Look.ref.line}>
				<view flexDirection="row" alignItems="center" columnGap={6} height={24}>
					<image src={Glyphs.get("info")} width={14} height={14} color={Look.ref.fg3}/>
					<text fontSize={11} fontWeight={600} color={Look.ref.fg3}>SELECTION</text>
				</view>
				{[for (kv in [{k: "Total size", v: Kinds.size(size)}, {k: "Kinds", v: kindText.join(", ")}])
					<view flexDirection="row" justifyContent="space-between" columnGap={12} height={24} alignItems="center" fontSize={12.5}>
						<text color={Look.ref.fg3} flexShrink={0}>{kv.k}</text>
						<text lineClamp={1} textOverflow="ellipsis" textAlign="right" flexShrink={1}>{kv.v}</text>
					</view>]}
			</view>
		</view>;
	}

	// (a card of the stack: the thumbnail, else the glyph, on a white mat)
	static function card(x:Explorer, e:Entry, side:Float, transform:String):View {
		var t = Tiles.thumbnail(x, e);
		return <view position="absolute" width={side} height={side} borderRadius={8} padding={3} background="#ffffff" transform={transform}
			boxShadow="0 4px 14px rgba(0,0,0,0.22)" alignItems="center" justifyContent="center" overflow="hidden">
			<Show when={t().image != null}><image src={t().image} width={side - 6} height={side - 6} objectFit="cover" borderRadius={6}/></Show>
			<Show when={t().image == null}>{Tiles.large(e)}</Show>
		</view>;
	}

	static function plural(kind:String):String
		return StringTools.endsWith(kind, "s") ? kind : kind + "s";

	// (nothing selected: the folder's picture, its name, how many items)
	static function folder(x:Explorer):View {
		var b = x.browser;
		return <view flexGrow={1}>
			<view height={BOX} flexShrink={0} margin="14 14 0 14" borderRadius={10} background={Look.ref.well} alignItems="center" justifyContent="center">
				{Tiles.large({name: "", kind: Folder, size: 0, modified: 0, created: 0})}
			</view>
			<view padding="12 16 0 16" alignItems="center" rowGap={2}>
				<text fontSize={14} fontWeight={600} lineClamp={1} textOverflow="ellipsis">{() -> x.sidebar.title(b.dir())}</text>
				<text fontSize={12} color={Look.ref.fg3}>{() -> b.reading() ? "Reading…" : Kinds.items(b.items().length)}</text>
			</view>
		</view>;
	}

	// (the box's content: the picture fitted, a PDF's count, a video's duration; else the glyph)
	static function picture(x:Explorer, e:Entry, s:Null<Shown>):View {
		if (s != null && s.markdown != null) return page(s.markdown);
		var img = s == null ? null : s.image;
		if (img == null) img = Tiles.cached(x, e);
		if (img == null) return Tiles.large(e);
		var k = Math.min(252 / img.width, 188 / img.height);
		var w = Math.round(img.width * k), h = Math.round(img.height * k);
		// (the thumbnail while the preview comes: nothing known of it yet; a Show's children are made with it)
		var pages = s == null ? 0 : s.pages, duration = s == null ? 0.0 : s.duration;
		return <view alignItems="center" justifyContent="center" width="100%" height="100%">
			<image tag="preview-image" src={img} width={w} height={h} borderRadius={4} boxShadow="0 4px 16px rgba(0,0,0,0.4)"/>
			<Show when={pages > 1}>
				<text tag="pages" position="absolute" bottom={8} padding="2 8" borderRadius={9} background="rgba(10,10,10,0.6)" color="#ffffff" fontSize={11.5}>{'1 / $pages'}</text>
			</Show>
			<Show when={duration > 0}>
				<text tag="duration" position="absolute" right={10} bottom={10} padding="0 5" borderRadius={4} background="rgba(0,0,0,0.62)" color="#ffffff"
					fontSize={10.5} fontWeight={600}>{clock(duration)}</text>
			</Show>
		</view>;
	}

	// (a Markdown document's first screen: its first blocks laid out on a
	// page 600 points wide, shown at 0.38, as tall as an image's box)
	static function page(d:MarkdownDoc):View {
		var k = 0.38, w = 600, h = Math.round(188 / k);
		var view = new helder.markdown.MarkdownView({doc: d.doc, scroll: false, blocks: 12});
		return <view tag="preview-page" width={Math.round(w * k)} height={188} borderRadius={4} overflow="hidden" background={Look.ref.canvas}
			boxShadow="0 4px 16px rgba(0,0,0,0.4)">
			<view position="absolute" left={0} top={0} width={w} height={h} padding="22 0 0 0" transform={'scale($k)'} transformOrigin="0 0"
				pointerEvents="none">{view}</view>
		</view>;
	}

	public static function subtitle(e:Entry, s:Null<Shown>):String {
		var kind = Kinds.kind(e);
		if (s != null && s.markdown != null) return '$kind · ${Kinds.count(s.markdown.words)} words';
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
		if (s != null && s.markdown != null) {
			out.push({k: "Words", v: Kinds.count(s.markdown.words)});
			out.push({k: "Headings", v: Std.string(s.markdown.headings)});
		}
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
