package viewer;

import helder.ui.Clock;
import helder.ui.Node;
import helder.ui.VirtualScroll;
import helder.ui.controls.Look;
import helder.ui.controls.Props.PathSegment;
import helder.ui.controls.Standard;
import helder.ui.widgets.WindowButtons;
import helder.ui.menu.Menu.MenuItem;
import helder.ui.menu.Menus;
import helder.ui.view.UiFlow.VirtualList;
import helder.ui.view.UiFlow.VirtualGrid;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import viewer.Files;
import viewer.ViewerActions;

// The browser's middle panel: the toolbar (back, forward, the folder's name
// and its enclosing folders, search, the View menu, the inspector), the
// folder (the grid of thumbnails, or the list: name, date modified,
// size, kind) or why it shows nothing (empty, still reading after
// 300 ms, unreadable, no results), and the path bar with the count.
class ContentView implements Markup {
	public static inline var ROW = 30;
	static inline var EDGE = 6;
	// the path bar's height
	public static inline var FOOT = 32;

	// (medium: a tablet's, its sidebar a button's, its inspector a sheet's, no path bar)
	public static function make(x:Explorer, ?medium:Read<Bool>):View {
		var tablet:Read<Bool> = medium ?? () -> false;
		return <view tag="main" slot="panel" grow={1} min-width={0} direction="column" overflow="hidden"
			borders="0 0 0 1" border-color={Look.ref.line}>
			{toolbar(x, tablet)}
			{content(x, tablet)}
			<Show when={!tablet()}>{pathBar(x)}</Show>
		</view>;
	}

	// --- the toolbar

	static function toolbar(x:Explorer, tablet:Read<Bool>):View {
		var b = x.browser;
		// (a tablet's, no sidebar left of it: macOS's buttons at its start, kept clear)
		return <view tag="toolbar" direction="row" align-items="center" column-gap={6} height={tablet() ? 52 : Shell.BAR} shrink={0} padding="0 8" drag-region
			padding-left={tablet() && WindowButtons.side() == "start" ? Shell.BUTTONS : 8}
			borders="0 0 1 0" border-color={Look.ref.line}>
			<Show when={tablet()}>
				<Standard.Button tag="sidebar-toggle" variant="ghost" icon={Glyphs.get("sidebar")} label="Sidebar" onPress={() -> x.sidebarOpen(true)}/>
			</Show>
			<view direction="row" column-gap={2}>
				<Standard.Button tag="back" variant="ghost" size="sm" icon={Glyphs.get("back")} label="Back" disabled={() -> !b.canBack()}
					onPress={() -> b.goBack()}/>
				<Standard.Button tag="forward" variant="ghost" size="sm" icon={Glyphs.get("forward")} label="Forward" disabled={() -> !b.canForward()}
					onPress={() -> b.goForward()}/>
			</view>
			<view:button tag="folder-title" slot="title-button" role="button" focusable label={() -> x.sidebar.title(b.dir()) + ", show enclosing folders"}
				ref={(n:Node) -> Menus.button(n, () -> enclosing(x))}>
				<text max-lines={1} text-overflow="ellipsis">{() -> x.sidebar.title(b.dir())}</text>
				<image src={Glyphs.get("down")} width={14} height={14} shrink={0} color={Look.ref.fg3}/>
			</view:button>
			<view grow={1}/>
			<Show when={x.openFolder != null}>
				<Standard.Button tag="open-folder" variant="ghost" size="sm" icon={Glyphs.get("folder")} label="Open folder"
					onPress={() -> if (x.openFolder != null) x.openFolder()}>Open folder</Standard.Button>
			</Show>
			<Show when={!b.searching()}>
				<Standard.Button tag="search" variant="ghost" size="sm" icon={Glyphs.get("search")} label="Search" onPress={() -> b.searching(true)}/>
			</Show>
			<Show when={b.searching()}>{search(x)}</Show>
			<view:button tag="view-menu" slot="tool" role="button" focusable label="View options" ref={(n:Node) -> Menus.button(n, ViewerActions.view)}>
				<image src={() -> Glyphs.get(b.layout() == Grid ? "grid" : "list")} width={16} height={16}/>
				<image src={Glyphs.get("down")} width={12} height={12}/>
			</view:button>
			<Show when={!tablet()}>
				<Standard.Button tag="inspector-toggle" variant="ghost" size="sm" icon={Glyphs.get("info")} label="Inspector" selected={() -> b.inspector()}
					onPress={() -> b.inspector(!b.inspector.value)}/>
			</Show>
			<Show when={tablet()}>
				<view ref={(n:Node) -> x.infoAnchor = n}>
					<Standard.Button tag="info-toggle" variant="ghost" icon={Glyphs.get("info")} label="Get Info" selected={() -> x.infoOpen()}
						onPress={() -> x.infoOpen(!x.infoOpen.value)}/>
				</view>
			</Show>
		</view>;
	}

	static function search(x:Explorer):View {
		var b = x.browser;
		// (Look's composite field: one ring round the box while the field has the focus)
		return <view tag="search-box" slot="field-box" width={196} height={30} shrink={0} radius={8} key-context="search">
			<image src={Glyphs.get("search")} width={14} height={14} color={Look.ref.fg3}/>
			<field tag="search-field" slot="field-box-input" value={() -> b.query()} placeholder="Search" label="Search this folder" font-size={13}
				onInput={e -> b.search(e.text)}
				onKeyDown={e -> if (e.key == helder.ui.Key.ESCAPE) {
					b.closeSearch();
					e.stop();
				}} ref={n -> Clock.add(_ -> {
					n.focus();
					false;
				})}/>
			<Show when={b.query() != ""}>
				<view:button role="button" label="Clear" onPress={() -> b.search("")}>
					<image src={Glyphs.get("x")} width={14} height={14} color={Look.ref.fg3}/>
				</view:button>
			</Show>
		</view>;
	}

	// (the folder's title's menu: the folders enclosing it, nearest first)
	static function enclosing(x:Explorer):Array<MenuItem> {
		var up = Browser.ancestry(x.browser.dir.value);
		up.pop();
		up.reverse();
		return [for (p in up) Item(x.sidebar.title(p), Go(p))];
	}

	static function popup(at:Node, items:Array<MenuItem>) {
		if (at.ui == null || items.length == 0) return;
		var r = at.rect();
		Menus.popup(at.ui, items, r.x, r.y + r.height + 4, at);
	}

	// --- the folder

	static function content(x:Explorer, tablet:Read<Bool>):View {
		var b = x.browser;
		// (still reading after 300 ms with nothing to show: the skeleton)
		var slow = signal(false), since = -1.0;
		renderEffect(() -> b.reading() && b.items().length == 0, waiting -> {
			slow(false);
			if (!waiting || since >= 0) return;
			since = 0;
			Clock.add(t -> {
				if (since == 0) since = t;
				if (!b.reading.value || b.items.value.length > 0) {
					since = -1;
					return false;
				}
				if (t - since < 0.3) return true;
				since = -1;
				slow(true);
				return false;
			});
		});
		// (a picture flying from it: the folder darker behind, depth, the sidebar and the bars still)
		return <view tag="content" grow={1} min-height={0}>
			{list(x, tablet)}
			<Show when={b.error() != ""}>{States.error(x)}</Show>
			<Show when={b.error() == "" && !b.reading() && b.total() == 0}>{States.empty(x)}</Show>
			<Show when={b.error() == "" && b.query() != "" && b.items().length == 0 && !b.reading()}>{States.noResults(x)}</Show>
			<Show when={slow()}>{States.slow(x)}</Show>
			<Show when={x.zoom.flying() != ""}>
				<view tag="depth" position="absolute" inset={0} pointer-events="none" background="#000000" opacity={Flight.DEPTH_DIM * x.zoom.shown()}/>
			</Show>
		</view>;
	}

	// (the list or the grid, sharing the browser's selection: their own
	// keys, presses, marquee and type-ahead; the selected kept in view)
	static function list(x:Explorer, tablet:Read<Bool>):View {
		var b = x.browser, scroller:Null<VirtualScroll> = null;
		effect(() -> b.selection.version(), _ -> b.selectionChanged());
		effect(() -> b.selected(), v -> {
			var s = scroller, i = b.indexOf(v);
			if (s != null && i >= 0) s.scrollToIndex(i);
		});
		// (a folder shown: where the browser says, once its items are in: its
		// top; a place kept in the history, the batches it needs waited for;
		// the selected entry in view. Not the scroller's own anchor, which
		// would keep the last folder's offset)
		var want:Null<Float> = 0.0;
		function place() {
			var v = scroller, w = want;
			// (none of the folder read yet: its first batch places it; placed
			// on the empty list, the rows coming in would carry their old place)
			if (v == null || w == null || b.stale || b.reading.value && b.items.value.length == 0) return;
			if (w < 0) {
				// (the entry asked for, once it is read; gone: the top)
				var i = b.indexOf(b.selected.value);
				if (i >= 0) v.scrollToIndex(i, "center") else if (!b.reading.value) v.scrollY = 0;
				if (i >= 0 || !b.reading.value) want = null;
				return;
			}
			var max = Math.max(0, @:privateAccess (v.extent() - v.viewHeight()));
			if (w > max && b.reading.value) return;
			v.scrollY = Math.min(w, max);
			want = null;
		}
		b.scrolled = () -> scroller == null ? 0 : scroller.scrollY;
		effect(() -> b.dir(), _ -> want = b.offset);
		effect(() -> {
			b.items();
			b.reading();
		}, _ -> place());
		function made(v:VirtualScroll) {
			scroller = v;
			place();
			// (on the next frame: the list shown again first)
			x.focusList = () -> Clock.add(_ -> {
				var i = b.indexOf(b.selected.value);
				if (v.count > 0) v.focusIndex(i < 0 ? 0 : i);
				if (i >= 0) v.scrollToIndex(i, "center");
				false;
			});
			var i = b.indexOf(b.selected.value);
			if (i >= 0) Clock.add(_ -> {
				v.scrollToIndex(i, "center");
				false;
			});
		}
		function activate(picked:Array<Int>) {
			var i = b.indexOf(b.selected.value);
			x.open(b.items.value[i >= 0 ? i : picked.length > 0 ? picked[0] : 0]?.name);
		}
		function menu(i:Int, px:Float, py:Float) {
			var s = scroller;
			// (on empty space, -1: the folder's own: New Folder, View, Show in Finder, Get Info)
			if (s != null && s.ui != null) Menus.popup(s.ui, i < 0 ? ViewerActions.background() : ViewerActions.entry, px, py, s);
		}
		// (the folder's own space: what is dropped on it, into the folder shown)
		// (the last folder's rows, this one slow to read: dimmed, not pressed, never blank)
		return <view tag="list" grow={1} min-height={0} display={b.error() != "" ? "none" : "flex"} opacity={b.waiting() ? 0.45 : 1}
			pointer-events={b.waiting() ? "none" : "auto"} ref={(n:Node) -> Drops.folder(x, n, () -> b.dir())}>
			<Show when={b.layout() == List}>
				{header(x)}
				<VirtualList tag="rows" each={() -> b.items()} by={(e:Entry) -> e.name} itemHeight={ROW} selection={b.selection} label="Files"
					textOf={(e:Entry) -> e.name} onActivate={(picked:Array<Int>) -> activate(picked)} onContextMenu={menu}
					ref={v -> {
						// (its ends' room: a row's focus ring whole, the last row clear of the path bar)
						v.insets(EDGE, EDGE);
						made(v);
					}}>{(e, i) -> row(x, e)}</VirtualList>
			</Show>
			<Show when={b.layout() == Grid}>
				<VirtualGrid tag="grid" each={() -> b.items()} by={(e:Entry) -> e.name} cellWidth={tablet() ? Tiles.TABLET_WIDTH : Tiles.CELL_WIDTH}
					cellHeight={tablet() ? Tiles.TABLET_HEIGHT : Tiles.CELL_HEIGHT}
					gap={4} padding={12} selection={b.selection} label="Files" textOf={(e:Entry) -> e.name} onActivate={activate} onContextMenu={menu}
					ref={v -> made(v)}>{(e, i) -> tablet() ? Phone.pressed(x, e, Tiles.cell(x, e, true)) : Tiles.cell(x, e)}</VirtualGrid>
			</Show>
		</view>;
	}

	static function header(x:Explorer):View {
		var b = x.browser;
		function column(label:String, key:Listing.SortKey, width:Float, right:Bool):View
			return <view:button slot="head-cell" role="button" focusable label={"Sort by " + label} width={width > 0 ? width : "auto"} grow={width > 0 ? 0 : 1}
				shrink={width > 0 ? 0 : 1} justify={right ? "flex-end" : "flex-start"} data-selected={b.order().key == key} onPress={() -> b.sortBy(key)}>
				<text max-lines={1}>{label}</text>
				<Show when={b.order().key == key}>
					<image src={() -> Glyphs.get(b.order().ascending ? "up" : "down")} width={12} height={12}/>
				</Show>
			</view:button>;
		return <view tag="list-head" direction="row" align-items="center" column-gap={12} height={30} shrink={0} padding="0 20 0 16"
			borders="0 0 1 0" border-color={Look.ref.line} font-size={11.5} font-weight={500} color={Look.ref.fg3}>
			<view grow={1} min-width={0} padding-left={28} direction="row">{column("Name", Name, 0, false)}</view>
			{column("Date modified", Modified, 156, false)}
			{column("Size", Size, 84, true)}
			{column("Kind", Kind, 124, false)}
		</view>;
	}

	static function row(x:Explorer, e:helder.view.graph.Read<Entry>):View {
		var b = x.browser;
		function on():Bool {
			b.selection.version();
			return b.selection.has(e().name);
		}
		return <view slot="list-row" data-selected={on()} ref={(n:Node) -> {
			DragOut.from(x, n, () -> e().name);
			Drops.folder(x, n, () -> e().kind == Folder ? b.path(e().name) : null);
		}}>
			<view direction="row" align-items="center" column-gap={8} grow={1} min-width={0}>
				{Tiles.mini(x, e)}
				<Show when={b.renaming() == e().name}>{() -> NameField.field(e().name, t -> b.rename(e().name, t), () -> b.renaming(""))}</Show>
				<Show when={b.renaming() != e().name}>
					<text tag="name" grow={1} shrink={1} min-width={0} max-lines={1} text-overflow="middle" color={on() ? Look.ref.accentFg : Look.ref.fg}
						dir={helder.ui.Dir.Ltr}>{e().name}</text>
				</Show>
			</view>
			<text width={156} shrink={0} max-lines={1}>{Kinds.date(e().modified)}</text>
			<text width={84} shrink={0} max-lines={1} text-align="right">{e().kind == Folder ? "—" : Kinds.size(e().size)}</text>
			<text width={124} shrink={0} max-lines={1} text-overflow="ellipsis">{Kinds.kind(e())}</text>
		</view>;
	}

	// --- the path bar

	static function pathBar(x:Explorer):View {
		var b = x.browser, s = x.sidebar;
		// (from the volume down)
		function folders():Array<String> {
			var all = Browser.ancestry(b.dir()), v = s.volumeOf(b.dir());
			if (v == null) return all;
			var top = all.indexOf(Browser.normalize(v.path));
			return top < 0 ? all : all.slice(top);
		}
		function segments():Array<PathSegment>
			return [for (p in folders()) ({label: s.title(p), icon: icon(x, p)} : PathSegment)];
		return <view tag="pathbar" direction="row" align-items="center" height={FOOT} shrink={0} padding="0 8 0 4" borders="1 0 0 0"
			border-color={Look.ref.line}>
			<view grow={1} min-width={0}>
				<Standard.PathBar segments={segments} text={() -> b.dir()} editing={x.editingPath}
					onNavigate={i -> {
						var f = folders();
						if (i >= 0 && i < f.length) b.go(f[i]);
					}}
					onSeparator={(i, anchor) -> subfolders(x, folders()[i], anchor)}
					onSubmit={text -> x.start(text)}/>
			</view>
			<Show when={b.reading()}><view margin="0 8 0 0" color={Look.ref.fg3}>{States.spinner(12)}</view></Show>
			<text tag="count" font-size={12} color={Look.ref.fg3} shrink={0} padding="0 6 0 0">{() -> count(x)}</text>
		</view>;
	}

	// "28 items", "3 of 28 selected", "Reading… 31,402"; a notice first
	public static function count(x:Explorer):String {
		var b = x.browser, n = b.items().length;
		if (b.notice() != "") return b.notice();
		if (b.reading()) return "Reading… " + Kinds.count(b.total());
		b.selected();
		b.selection.version();
		var k = b.picked().length;
		return k > 0 ? '${Kinds.count(k)} of ${Kinds.count(n)} selected' : Kinds.items(n);
	}

	// (a segment's icon: a volume's, the home folder's, a known place's)
	static function icon(x:Explorer, path:String):Null<helder.ui.Svg> {
		var s = x.sidebar;
		for (v in s.volumes)
			if (Browser.normalize(v.path) == path) return Glyphs.get(Glyphs.volume(v));
		for (p in s.places.value)
			if (Browser.normalize(p.path) == path) return Glyphs.get(Glyphs.place(p.kind));
		return null;
	}

	// (a separator's menu: that folder's subfolders, as they are read)
	static function subfolders(x:Explorer, dir:String, at:Node) {
		var got:Array<MenuItem> = [];
		x.files.list(dir, batch -> {
			for (e in batch.entries)
				if (e.kind == Folder && !Kinds.hidden(e.name)) got.push(Item(e.name, Go(FolderModel.join(dir, e.name))));
			if (!batch.done) return;
			got.sort((a, b) -> switch [a, b] {
				case [Item(l, _), Item(m, _)]: FolderModel.compare(l, m);
				case _: 0;
			});
			popup(at, got);
		});
	}
}
