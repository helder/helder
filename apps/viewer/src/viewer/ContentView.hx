package viewer;

import helder.ui.Clock;
import helder.ui.Node;
import helder.ui.VirtualScroll;
import helder.ui.controls.Look;
import helder.ui.controls.Props.PathSegment;
import helder.ui.controls.Standard;
import helder.ui.menu.Menu.MenuItem;
import helder.ui.menu.Menus;
import helder.ui.view.UiFlow.VirtualList;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import viewer.Files;
import viewer.ViewerActions;

// The browser's middle panel: the toolbar (back, forward, the folder's name
// and its enclosing folders, search, the View menu, the inspector), the
// folder (the list: name, date modified, size, kind; a grid once the
// virtual grid lands) or why it shows nothing (empty, still reading after
// 300 ms, unreadable, no results), and the path bar with the count.
class ContentView implements Markup {
	public static inline var ROW = 30;

	public static function make(x:Explorer):View {
		return <view tag="main" slot="panel" grow={1} min-width={0} direction="column" margin="8 8 8 0" overflow="hidden">
			{toolbar(x)}
			{content(x)}
			{pathBar(x)}
		</view>;
	}

	// --- the toolbar

	static function toolbar(x:Explorer):View {
		var b = x.browser, title:Null<Node> = null, viewButton:Null<Node> = null;
		return <view tag="toolbar" direction="row" align-items="center" column-gap={6} height={52} shrink={0} padding="0 10" drag-region
			borders="0 0 1 0" border-color={Look.ref.line}>
			<view direction="row" column-gap={2}>
				<Standard.Button tag="back" variant="ghost" size="sm" icon={Glyphs.get("back")} label="Back" disabled={() -> !b.canBack()}
					onPress={() -> b.goBack()}/>
				<Standard.Button tag="forward" variant="ghost" size="sm" icon={Glyphs.get("forward")} label="Forward" disabled={() -> !b.canForward()}
					onPress={() -> b.goForward()}/>
			</view>
			<view:button tag="folder-title" slot="title-button" role="button" focusable label={() -> x.sidebar.title(b.dir()) + ", show enclosing folders"}
				ref={(n:Node) -> title = n} onPress={() -> if (title != null) enclosing(x, title)}>
				<text max-lines={1} text-overflow="ellipsis">{() -> x.sidebar.title(b.dir())}</text>
				<image src={Glyphs.get("down")} width={14} height={14} shrink={0} color={Look.ref.fg3}/>
			</view:button>
			<view grow={1}/>
			<Show when={!b.searching()}>
				<Standard.Button tag="search" variant="ghost" size="sm" icon={Glyphs.get("search")} label="Search" onPress={() -> b.searching(true)}/>
			</Show>
			<Show when={b.searching()}>{search(x)}</Show>
			<view:button tag="view-menu" slot="tool" role="button" focusable label="View options" ref={(n:Node) -> viewButton = n}
				onPress={() -> if (viewButton != null) popup(viewButton, ViewerActions.view())}>
				<image src={() -> Glyphs.get(b.layout() == Grid ? "grid" : "list")} width={16} height={16}/>
				<image src={Glyphs.get("down")} width={12} height={12}/>
			</view:button>
			<Standard.Button tag="inspector-toggle" variant="ghost" size="sm" icon={Glyphs.get("info")} label="Inspector" selected={() -> b.inspector()}
				onPress={() -> b.inspector(!b.inspector.value)}/>
		</view>;
	}

	static function search(x:Explorer):View {
		var b = x.browser;
		return <view tag="search-box" direction="row" align-items="center" column-gap={7} width={196} height={30} shrink={0} padding="0 8" radius={8}
			background={Look.ref.fill} key-context="search">
			<image src={Glyphs.get("search")} width={14} height={14} color={Look.ref.fg3}/>
			<field tag="search-field" grow={1} min-width={0} value={() -> b.query()} placeholder="Search" label="Search this folder" font-size={13}
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
	static function enclosing(x:Explorer, at:Node) {
		var up = Browser.ancestry(x.browser.dir.value);
		up.pop();
		up.reverse();
		popup(at, [for (p in up) Item(x.sidebar.title(p), Go(p))]);
	}

	static function popup(at:Node, items:Array<MenuItem>) {
		if (at.ui == null || items.length == 0) return;
		var r = at.rect();
		Menus.popup(at.ui, items, r.x, r.y + r.height + 4, at);
	}

	// --- the folder

	static function content(x:Explorer):View {
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
		return <view tag="content" grow={1} min-height={0} onTextInput={e -> if (b.typeAhead(e.text, haxe.Timer.stamp())) e.stop()}>
			{list(x)}
			<Show when={b.error() != ""}>{States.error(x)}</Show>
			<Show when={b.error() == "" && !b.reading() && b.total() == 0}>{States.empty(x)}</Show>
			<Show when={b.error() == "" && b.query() != "" && b.items().length == 0 && !b.reading()}>{States.noResults(x)}</Show>
			<Show when={slow()}>{States.slow(x)}</Show>
		</view>;
	}

	// (the list: a header to sort by, a row a file; the selection by name, kept as the list changes)
	static function list(x:Explorer):View {
		var b = x.browser, scroller:Null<VirtualScroll> = null;
		// (a String's signal: a Dynamic value would be taken for a derived one's function)
		var picked:helder.view.graph.Signal<Dynamic> = cast signal(b.selected.value);
		effect(() -> picked(), (v:Dynamic) -> if (v != null && v != b.selected.value) b.select(v));
		effect(() -> b.selected(), v -> {
			picked(v);
			var s = scroller, i = b.indexOf(v);
			if (s != null && i >= 0) s.scrollToIndex(i);
		});
		// (pressed twice within 0.4 s: opened)
		var last = "", lastAt = -1.0;
		function press(e:Entry, ev:helder.ui.Event) {
			var now = haxe.Timer.stamp();
			if (ev.button == 3) {
				b.select(e.name);
				if (ev.current.ui != null) Menus.popup(ev.current.ui, ViewerActions.entry, ev.x, ev.y, ev.current);
				return;
			}
			if (last == e.name && now - lastAt < 0.4) {
				lastAt = -1;
				x.open(e.name);
				return;
			}
			last = e.name;
			lastAt = now;
			b.select(e.name);
		}
		return <view tag="list" grow={1} min-height={0} display={b.error() != "" ? "none" : "flex"}>
			{header(x)}
			<VirtualList tag="rows" each={() -> b.items()} by={(e:Entry) -> e.name} itemHeight={ROW} selected={picked} label="Files"
				onActivate={(e:Entry) -> x.open(e.name)} ref={v -> {
					scroller = v;
					// (on the next frame: the list shown again first)
					x.focusList = () -> Clock.add(_ -> {
						var i = b.indexOf(b.selected.value);
						if (v.count > 0) v.focusIndex(i < 0 ? 0 : i);
						if (i >= 0) v.scrollToIndex(i, "center");
						false;
					});
				}}>{(e, i) -> row(x, e, press)}</VirtualList>
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

	static function row(x:Explorer, e:helder.view.graph.Read<Entry>, press:(Entry, helder.ui.Event)->Void):View {
		var b = x.browser;
		function on():Bool
			return b.selected() == e().name;
		return <view slot="list-row" data-selected={on()} onPointerDown={ev -> press(e(), ev)}>
			<view direction="row" align-items="center" column-gap={8} grow={1} min-width={0}>
				{Tiles.mini(x, e)}
				<text tag="name" grow={1} shrink={1} min-width={0} max-lines={1} text-overflow="ellipsis" color={on() ? Look.ref.accentFg : Look.ref.fg}
					dir={helder.ui.Dir.Ltr}>{e().name}</text>
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
		return <view tag="pathbar" direction="row" align-items="center" height={32} shrink={0} padding="0 8 0 4" borders="1 0 0 0"
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

	// "28 items", "1 of 28 selected", "Reading… 31,402"
	public static function count(x:Explorer):String {
		var b = x.browser, n = b.items().length;
		if (b.reading()) return "Reading… " + Kinds.count(b.total());
		return b.selected() != "" && b.indexOf(b.selected()) >= 0 ? '1 of ${Kinds.count(n)} selected' : Kinds.items(n);
	}

	// (a segment's icon: a volume's, the home folder's, a known place's)
	static function icon(x:Explorer, path:String):Null<helder.ui.Svg> {
		var s = x.sidebar;
		for (v in s.volumes)
			if (Browser.normalize(v.path) == path) return Glyphs.get(Glyphs.volume(v));
		for (p in s.places)
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
