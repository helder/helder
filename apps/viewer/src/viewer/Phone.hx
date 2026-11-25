package viewer;

import helder.ui.Node;
import helder.ui.NavScreen;
import helder.ui.NavScreen.NavButton;
import helder.ui.Router;
import helder.ui.ScreenContext;
import helder.ui.Sheet;
import helder.ui.Stack;
import helder.ui.actions.Actions;
import helder.ui.controls.Look;
import helder.ui.gesture.Gesture;
import helder.ui.menu.ContextMenu;
import helder.ui.menu.Menu.MenuItem;
import helder.ui.menu.TouchMenu;
import helder.ui.nav.Bar;
import helder.ui.view.UiFlow.VirtualGrid;
import helder.ui.view.UiFlow.VirtualList;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;
import viewer.Files;
import viewer.ViewerActions;

// what a phone's long press and toolbars ask for beyond the browser's actions
enum PhoneAction {
	GetInfo;
	OpenIn;
	SelectItems;
}

// The viewer on a phone (Compact): the Explorer as a navigation stack, iOS
// Files' way in helder's look. Browse (its locations: the places and
// volumes, or a phone's folders, Add a folder…) and Recents (the files
// opened last) are the root's tabs; a folder is a screen (its large title,
// a search field under it, a grid of three columns, four on its side, or
// the list; its … the View menu; Select and its toolbar: Open in…, Copy,
// Info, Trash; a long press's menu: Open, Get Info, Open in…, Copy,
// Select, Move to Trash), a file full size another (a tap shows or hides
// the bars, a swipe across the next or previous file, down back to the
// folder, a pinch or a double tap a zoom; the inspector a sheet). The
// stack and the Explorer follow each other: a screen popped is its folder
// browsed again, a file closed its screen popped.
@:allow(viewer.PhoneState)
class Phone implements Markup {
	public static inline var PAD = 16.0;
	public static inline var GAP = 10.0;
	// (a tile's name and detail under its square)
	static inline var CAPTION = 42.0;
	// (the list's rows)
	public static inline var ROW = 62.0;
	// (the check's ring and its wash over a picture, whatever the theme)
	static final WHITE = helder.ui.Color.parse("#ffffff");
	static final SHADE = helder.ui.Color.parse("rgba(0,0,0,0.25)");

	// (at: the state once made, a story's to bring it to its moment)
	public static function Root(props:{x:Explorer, ?at:PhoneState->Void}):View {
		var p = new PhoneState(props.x);
		if (props.at != null) onSettled(() -> props.at(p));
		return <view tag="phone" grow={1} background={Look.ref.canvas} color={Look.ref.fg} font-family="system-ui" font-size={17}
			ref={(n:Node) -> {
				p.attach(n);
				props.x.zoom.attach(n);
			}}>
			<Stack router={p.nav}/>
			{Flight.layer(props.x.zoom)}
			<Sheet open={() -> p.info()} detents={[Medium, Large]} label="Info" onDismiss={() -> p.info(false)}>{InspectorView.make(p.x, true)}</Sheet>
		</view>;
	}

	// --- the root: Browse and Recents

	static function Home(props:{p:PhoneState}):View {
		var p = props.p;
		return <NavScreen title={() -> p.tab() == "recents" ? "Recents" : "Browse"} large bottom={<Tabs p={p}/>}>
			<Show when={p.tab() == "browse"}><Locations p={p}/></Show>
			<Show when={p.tab() == "recents"}><Recents p={p}/></Show>
		</NavScreen>;
	}

	static function Tabs(props:{p:PhoneState}):View {
		var p = props.p;
		function tab(name:String, label:String, glyph:String):View
			return <view:button tag={"tab-" + name} role="tab" label={label} selected={p.tab() == name} focusable grow={1} height={50} align-items="center"
				justify="center" row-gap={3} font-size={10.5} font-weight={500} color={p.tab() == name ? Look.ref.fg : Look.ref.fg3}
				onPress={() -> p.home(name)}>
				<image src={Glyphs.get(glyph)} width={26} height={26}/>
				<text>{label}</text>
			</view:button>;
		return <view tag="tabs" role="tablist" direction="row" padding="0 60">
			{tab("recents", "Recents", "clock")}
			{tab("browse", "Browse", "folder")}
		</view>;
	}

	static function Locations(props:{p:PhoneState}):View {
		var p = props.p, x = p.x, s = x.sidebar;
		return <view padding-bottom={24}>
			<text tag="locations-head" font-size={20} font-weight={700} padding="18 16 8 16">Locations</text>
			<view tag="locations" margin="0 16" radius={12} background={Look.ref.surface} overflow="hidden">
				<For each={() -> s.places()}>{place -> row(place().name, Glyphs.place(place().kind), "", () -> p.browse(place().path))}</For>
				{[for (v in s.volumes) row(v.name, Glyphs.volume(v), v.root && v.total > 0 ? Kinds.size(v.free) + " free" : "", () -> p.browse(v.path))]}
				<Show when={x.addFolder != null}>
					<view:button tag="add-folder" role="button" focusable label="Add a folder" direction="row" align-items="center" column-gap={13} height={50}
						padding="0 14" color={Look.ref.fg2} onPress={() -> if (x.addFolder != null) x.addFolder()}>
						<image src={Glyphs.get("plus")} width={22} height={22} margin="0 2"/>
						<text>Add a folder…</text>
					</view:button>
				</Show>
			</view>
		</view>;
	}

	// (a grouped row: its glyph, its name, a detail, the chevron)
	static function row(name:String, glyph:String, meta:String, press:Void->Void):View
		return <view:button tag={"place-" + name} role="button" focusable label={name} direction="row" align-items="center" column-gap={13} height={50}
			padding="0 14" borders="0 0 1 0" border-color={Look.ref.line} onPress={press}>
			<image src={Glyphs.get(glyph)} width={22} height={22} margin="0 2" color={Look.ref.fg2}/>
			<text grow={1} shrink={1} min-width={0} max-lines={1} text-overflow="ellipsis">{name}</text>
			<Show when={meta != ""}><text font-size={15} color={Look.ref.fg3}>{meta}</text></Show>
			<image src={Glyphs.get("forward")} width={16} height={16} color={Look.ref.fg3}/>
		</view:button>;

	static function Recents(props:{p:PhoneState}):View {
		var p = props.p, x = p.x;
		return <view padding-bottom={24}>
			<Show when={x.recent().length == 0}>
				<text tag="no-recents" padding="40 32" text-align="center" color={Look.ref.fg3}>The files you open show up here.</text>
			</Show>
			<For each={() -> x.recent()}>{path -> <view:button tag={"recent-" + Browser.name(path())} role="button" focusable label={Browser.name(path())}
				direction="row" align-items="center" column-gap={12} height={ROW} padding="0 16" onPress={() -> p.reopen(path())}>
				<view width={42} height={42} align-items="center" justify="center" radius={6} background={Look.ref.fill}>
					<image src={Glyphs.get(Glyphs.of(Kinds.glyph({name: Browser.name(path()), kind: File, size: 0, modified: 0, created: 0})))} width={20}
						height={20} color={Look.ref.fg3}/>
				</view>
				<view grow={1} min-width={0} row-gap={2}>
					<text font-size={16} max-lines={1} text-overflow="ellipsis" dir={helder.ui.Dir.Ltr}>{Browser.name(path())}</text>
					<text font-size={13} color={Look.ref.fg3} max-lines={1}>{x.sidebar.title(Browser.parent(path()) ?? path())}</text>
				</view>
			</view:button>}</For>
		</view>;
	}

	// --- a folder

	static function FolderScreen(props:{p:PhoneState, path:String}):View {
		var p = props.p, x = p.x, b = x.browser, path = props.path, more:Null<Node> = null;
		var here = () -> b.dir() == path;
		function count():Int {
			b.selection.version();
			return here() ? b.picked().length : 0;
		}
		return <NavScreen tag="folder" title={() -> p.selecting() ? (count() == 0 ? "Select Items" : Kinds.count(count()) + " Selected") : x.sidebar.title(path)}
			large={true} subtitle={() -> here() ? (b.reading() ? "Reading…" : Kinds.items(b.items().length)) : ""} scrolls={false}
			header={<Search p={p} path={path}/>}
			leading={<Show when={p.selecting()}><NavButton tag="select-all" label="Select All" onPress={() -> b.selection.selectAll()}/></Show>}
			trailing={<>
				<Show when={!p.selecting()}>
					<NavButton tag="select" label="Select" onPress={() -> p.selecting(true)}/>
					<view ref={(n:Node) -> more = n}>
						<NavButton tag="view-menu" label="View options" icon={Glyphs.get("more")} onPress={() -> if (more != null) p.menu(more, ViewerActions.view())}/>
					</view>
				</Show>
				<Show when={p.selecting()}><NavButton tag="done" label="Done" onPress={() -> p.selecting(false)}/></Show>
			</>}
			bottom={<>
				<Show when={!p.selecting()}><Tabs p={p}/></Show>
				<Show when={p.selecting()}><Tools p={p} full={false}/></Show>
			</>}>
			<Listed p={p} path={path}/>
		</NavScreen>;
	}

	static function Search(props:{p:PhoneState, path:String}):View {
		var b = props.p.x.browser;
		return <view tag="search" direction="row" align-items="center" column-gap={7} height={38} margin="0 16 12" padding="0 10" radius={11}
			background={Look.ref.well} color={Look.ref.fg3}>
			<image src={Glyphs.get("search")} width={17} height={17}/>
			<field tag="search-field" grow={1} min-width={0} value={() -> b.dir() == props.path ? b.query() : ""} placeholder="Search" label="Search this folder"
				color={Look.ref.fg} onInput={e -> b.search(e.text)}/>
		</view>;
	}

	// (the folder's grid or list, the screen's scroller: its last items kept
	// while the browser is elsewhere, a screen sliding away)
	static function Listed(props:{p:PhoneState, path:String}):View {
		var p = props.p, x = p.x, b = x.browser, path = props.path, nav = use(Bar.here);
		var here = () -> b.dir.value == path;
		var last:Array<Entry> = [];
		var items = memo(() -> b.dir() == path ? (last = b.items()) : last);
		effect(() -> b.selection.version(), _ -> b.selectionChanged());
		var list:Null<helder.ui.VirtualScroll> = null;
		function scroller(v:helder.ui.VirtualScroll) {
			list = v;
			if (nav != null) nav.scroller(v);
		}
		// (a file closed: its tile in view, for the zoom back into it)
		renderEffect(() -> x.full(), on -> {
			var i = b.indexOf(b.selected.value);
			if (!on && list != null && here() && i >= 0) list.scrollToIndex(i);
		});
		// (why it shows nothing, last: under the bar and the large title)
		return <view grow={1} min-height={0}>
			<Show when={b.layout() == Grid}>{() -> {
				// (three columns, four on its side; squares filling the width)
				var w = ScreenContext.current.width(), h = ScreenContext.current.height();
				var cols = w > h ? 4 : 3, side = Math.floor((w - 2 * Phone.PAD - (cols - 1) * Phone.GAP) / cols);
				<VirtualGrid tag="grid" each={items} by={(e:Entry) -> e.name} cellWidth={side} cellHeight={side + CAPTION} gap={GAP} padding={PAD}
					selection={b.selection} selectMode={p.selecting} label="Files" textOf={(e:Entry) -> e.name} ref={g -> scroller(g)}>
					{(e, i) -> pressed(x, e, tile(p, e, side), p)}
				</VirtualGrid>;
			}}</Show>
			<Show when={b.dir() == path && !b.reading() && (b.error() != "" || b.items().length == 0)}>
				<view position="absolute" left={0} right={0} bottom={0} top={nav == null ? 0 : nav.barHeight() + nav.largeHeight()}>
					<Show when={b.error() != ""}>{States.error(x)}</Show>
					<Show when={b.error() == "" && b.total() == 0}>{States.empty(x)}</Show>
					<Show when={b.error() == "" && b.query() != "" && b.total() > 0}>{States.noResults(x)}</Show>
				</view>
			</Show>
			<Show when={b.layout() == List}>
				<VirtualList tag="rows" each={items} by={(e:Entry) -> e.name} itemHeight={ROW} selection={b.selection} selectMode={p.selecting}
					label="Files" textOf={(e:Entry) -> e.name} ref={v -> scroller(v)}>{(e, i) -> pressed(x, e, listRow(p, e), p)}</VirtualList>
			</Show>
		</view>;
	}

	// a tile: the picture in a square (the thumbnail filling it, a folder's
	// picture, a document's page), the name, a line of detail; in select
	// mode the check
	static function tile(p:PhoneState, e:Read<Entry>, side:Float):View {
		var x = p.x;
		function on():Bool {
			x.browser.selection.version();
			return x.browser.selection.has(e().name);
		}
		return <view tag={"tile-" + e().name} grow={1} align-items="center" row-gap={4} onTap={_ -> if (!p.selecting.peek()) p.open(e().name)}>
			<view slot="photo" data-selected={on() && p.selecting()} width={side} height={side} shrink={0} align-items="center" justify="center" radius={9}
				background={e().kind == Folder ? helder.ui.Color.TRANSPARENT : Look.ref.fill} overflow="hidden"
				opacity={x.zoom.flying() == x.browser.path(e().name) ? 0 : 1} ref={(n:Node) -> x.zoom.tile(n, x.browser.path(e().name))}>
				{() -> square(x, e(), side)}
				<Show when={p.selecting()}>
					<view tag="pick" position="absolute" right={6} bottom={6} width={24} height={24} radius={12} border-width={1.5} align-items="center"
						justify="center" border-color={on() ? Look.ref.accent : WHITE} background={on() ? Look.ref.accent : SHADE}
						color={Look.ref.accentFg}>
						<Show when={on()}><image src={Glyphs.get("check")} width={15} height={15}/></Show>
					</view>
				</Show>
			</view>
			<text slot="name-pill" data-selected={on() && p.selecting()} font-size={13} font-weight={500} max-width={side} max-lines={1}
				text-overflow="ellipsis" dir={helder.ui.Dir.Ltr}>{e().name}</text>
			<text font-size={11.5} color={Look.ref.fg3} margin-top={-4} max-lines={1}>{e().kind == Folder ? "Folder" : Kinds.date(e().modified)}</text>
		</view>;
	}

	static function square(x:Explorer, e:Entry, side:Float):View {
		if (e.kind == Folder) return <image src={Glyphs.folder(helder.ui.UiWindow.dark())} width={side * 0.82} height={side * 0.66}/>;
		var t = Tiles.thumbnail(x, e);
		return <>
			<Show when={t().image != null}><image src={t().image} width={side} height={side} fit="cover"/></Show>
			<Show when={t().image == null}>{Tiles.large(e)}</Show>
		</>;
	}

	static function listRow(p:PhoneState, e:Read<Entry>):View {
		var x = p.x;
		function on():Bool {
			x.browser.selection.version();
			return x.browser.selection.has(e().name);
		}
		return <view direction="row" align-items="center" column-gap={12} height={ROW} padding="0 16" grow={1}
			background={on() && p.selecting() ? Look.ref.accentSoft : helder.ui.Color.TRANSPARENT} onTap={_ -> if (!p.selecting.peek()) p.open(e().name)}>
			<view width={42} height={42} align-items="center" justify="center" radius={6} overflow="hidden"
				opacity={x.zoom.flying() == x.browser.path(e().name) ? 0 : 1} ref={(n:Node) -> x.zoom.tile(n, x.browser.path(e().name))}>{() -> square(x, e(), 42)}</view>
			<view grow={1} min-width={0} row-gap={2}>
				<text font-size={16} max-lines={1} text-overflow="ellipsis" dir={helder.ui.Dir.Ltr}>{e().name}</text>
				<text font-size={13} color={Look.ref.fg3} max-lines={1}>{Kinds.date(e().modified) + (e().kind == Folder ? "" : " · " + Kinds.size(e().size))}</text>
			</view>
			<Show when={e().kind == Folder && !p.selecting()}><image src={Glyphs.get("forward")} width={16} height={16} color={Look.ref.fg3}/></Show>
		</view>;
	}

	// a file's view with its long press's menu (a phone's, a tablet's): the
	// entry selected first, its picture lifted
	public static function pressed(x:Explorer, e:Read<Entry>, content:View, ?p:PhoneState):View
		return <view grow={1} ref={(n:Node) -> ContextMenu.attach(n, () -> entryMenu(x, e(), p), () -> lifted(x, e()), a -> a == ViewerAction.Trash,
			() -> {
				if (p == null || !p.selecting.peek()) x.browser.select(e().name);
			})}>{content}</view>;

	// (Open, Get Info, Open in…, Copy, Select, Move to Trash: as the files allow)
	static function entryMenu(x:Explorer, e:Entry, p:Null<PhoneState>):Array<MenuItem> {
		var items:Array<MenuItem> = [Item("Open", OpenSelected), Item("Get Info", GetInfo)];
		if (x.share != null && e.kind != Folder) items.push(Item("Open in…", OpenIn));
		if (x.copy != null && ViewerActions.LOCAL && !mobile()) items.push(Item("Copy", CopyPath));
		if (p != null) items.push(Item("Select", SelectItems));
		if (x.files.trash != null) items = items.concat([Separator, Item(ViewerActions.trashLabel(), Trash)]);
		return items;
	}

	// (a long press's preview: the thumbnail, larger, else the file's picture)
	static function lifted(x:Explorer, e:Entry):View {
		var img = Tiles.cached(x, e);
		return <view grow={1} align-items="center" justify="center" background={Look.ref.raised}>
			{img != null ? <image src={img} width="100%" height="100%" fit="cover"/> : e.kind == Folder ? <image
				src={Glyphs.folder(helder.ui.UiWindow.dark())} width={96} height={78}/> : Tiles.large(e)}
		</view>;
	}

	// whether this is a phone's build (iOS, Android): no paths to copy there
	public static inline function mobile():Bool
		return #if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64" || hxmc.target == "android-arm64" || hxmc.target == "android-x86_64") true #else false #end;

	// a bottom toolbar: Open in…, Copy, Info, Trash (a file's full size: Open in…, Info, Trash)
	static function Tools(props:{p:PhoneState, full:Bool}):View {
		var p = props.p, x = p.x, b = x.browser;
		function none():Bool {
			b.selection.version();
			return !props.full && b.picked().length == 0;
		}
		function tool(tag:String, label:String, glyph:String, run:Void->Void, ?danger:Bool):View
			return <view:button tag={tag} role="button" label={label} focusable={!none()} data-disabled={none()} min-width={60} height={50}
				align-items="center" justify="center" row-gap={3} font-size={10.5} opacity={none() ? 0.45 : 1}
				color={danger == true ? Look.ref.danger : Look.ref.fg} onPress={() -> if (!none()) run()}>
				<image src={Glyphs.get(glyph)} width={22} height={22}/>
				<text>{label}</text>
			</view:button>;
		return <view tag="tools" direction="row" justify="space-between" padding="6 12 0 12">
			{x.share != null ? tool("open-in", "Open in…", "share", () -> p.openIn(props.full)) : null}
			{!props.full && x.copy != null && ViewerActions.LOCAL && !mobile() ? tool("copy", "Copy", "copy", () -> x.perform(CopyPath)) : null}
			{tool("info", "Info", "info", () -> p.showInfo(props.full))}
			{x.files.trash != null ? tool("trash", "Trash", "trash", () -> {
				x.perform(Trash);
				if (!props.full) p.selecting(false);
			}, true) : null}
		</view>;
	}

	// --- a file full size

	static function Full(props:{p:PhoneState}):View {
		var p = props.p, x = p.x, v = x.viewer;
		var shift = signal(0.0), drop = signal(0.0), stage:Null<Node> = null;
		// (a swipe across: the next or previous file; down: back to the folder)
		function swipe(g:Gesture) {
			var w = stage == null || stage.width <= 0 ? 1 : stage.width, h = stage == null || stage.height <= 0 ? 1 : stage.height;
			switch g.state {
				case Began | Changed:
					if (Math.abs(g.tx) >= Math.abs(g.ty) || v.pdf.peek() != null) {
						shift(g.tx);
						drop(0);
					} else {
						shift(0);
						drop(Math.max(0, g.ty));
					}
				case Ended:
					var dx = shift.peek(), dy = drop.peek();
					shift(0);
					drop(0);
					if (dy > h * 0.2 || dy > 0 && g.vy > 800) p.nav.back() else if (dx < -w * 0.25 || dx < 0 && g.vx < -500) v.next() else if (dx > w * 0.25
						|| dx > 0 && g.vx > 500) v.previous();
				case _:
					shift(0);
					drop(0);
			}
		}
		// (a pinch: the zoom about its focus, in the image's device pixels)
		function pinch(g:Gesture) {
			var s = stage;
			if (s == null || s.width <= 0) return;
			var k = v.camera.viewWidth / s.width;
			v.pinch(g.dscale, g.x * k, g.y * k);
		}
		return <NavScreen tag="full" title={() -> {
			v.title();
			v.folder.name;
		}} scrolls={false} bars={p.bars}
			trailing={<NavButton tag="full-info" label="Get Info" icon={Glyphs.get("info")} onPress={() -> p.showInfo(true)}/>}
			bottom={<Tools p={p} full={true}/>}>
			<view tag="full-stage" grow={1} background={Look.ref.canvas} opacity={1 - Math.min(0.6, drop() / 600)} onTap={_ -> p.bars(!p.bars.peek())}
				onPinch={pinch} onPan={swipe} ref={(n:Node) -> {
					stage = n;
					// (zoomed in: a drag is the image's own pan, not a swipe)
					var pan = n.gesture(helder.ui.gesture.Pan);
					renderEffect(() -> v.version(), _ -> if (pan != null) pan.enabled = v.camera.fitted || v.pdf.peek() != null);
				}}>
				<view grow={1} transform={"translate(" + shift() + "px, " + drop() + "px)"}>{ViewerView.stage(x)}</view>
			</view>
		</NavScreen>;
	}
}

// A phone's state beside the Explorer's: its stack, the root's tab, select
// mode, the info sheet, the full view's bars
class PhoneState implements Markup {
	public final x:Explorer;
	public final nav = new Router();
	public final tab = signal("browse");
	public final selecting = signal(false);
	public final info = signal(false);
	public final bars = signal(true);
	// (the top's path as the stack has it now: the router's lands at the next flush)
	var top = "/";
	// (the path the stack last landed on: its effect's)
	var landed = "/";
	static var declared = false;

	public function new(x:Explorer) {
		this.x = x;
		if (!declared) {
			declared = true;
			actions("phone", PhoneAction);
		}
		nav.route("/", _ -> <Phone.Home p={this}/>)
			.route("/folder/:path", q -> <Phone.FolderScreen p={this} path={q.path}/>)
			.route("/view", _ -> <Phone.Full p={this}/>);
		// (where the Explorer starts: its folder over Browse, a file full size over that)
		var dir = x.browser.dir.value;
		if (dir != "") push("/folder/" + StringTools.urlEncode(dir));
		if (x.full.value) push("/view", true);
		// (the stack's top is what the Explorer shows: a folder browsed again, a file closed)
		renderEffect(() -> nav.path(), arrived);
		// (a file's screen faded in place, not slid: the zoom from its tile moves it)
		renderEffect(() -> x.full(), on -> {
			if (on && top != "/view") push("/view", true);
			if (!on && top == "/view") nav.back();
		});
	}

	// (its root, once mounted)
	public var node(default, null):Null<Node> = null;

	public function attach(n:Node) {
		node = n;
		n.on(PhoneAction, a -> {
			switch a {
				case GetInfo: showInfo(false);
				case OpenIn: openIn(false);
				case SelectItems: selecting(true);
			}
			true;
		}, a -> a == OpenIn && x.share == null ? Disabled : Enabled);
	}

	function arrived(path:String) {
		var left = landed;
		landed = top = path;
		// (a folder's screen left: its select mode done)
		if (left != path && StringTools.startsWith(left, "/folder/")) selecting(false);
		if (StringTools.startsWith(path, "/folder/")) {
			var dir = StringTools.urlDecode(path.substr("/folder/".length));
			if (x.browser.dir.value != dir) x.browser.go(dir);
		}
		// (the file's screen popped: the file closed)
		if (left == "/view" && path != "/view") {
			bars(true);
			if (x.full.value) x.close();
		}
	}

	function push(path:String, still = false) {
		top = path;
		nav.go(path, still);
	}

	// the root's tab (a tab of the root pressed elsewhere: back to it)
	public function home(name:String) {
		tab(name);
		if (top != "/") nav.reset("/");
	}

	// a place's folder browsed, the stack's first above the root
	public function browse(path:String) {
		x.choose(path);
		nav.reset("/");
		push("/folder/" + StringTools.urlEncode(Browser.normalize(path)));
	}

	// an entry of the folder opened: a folder pushed, a file full size, any other the system's app
	public function open(name:String) {
		var e = x.browser.entry(name);
		if (e == null) return;
		if (e.kind == Folder) {
			var path = x.browser.path(name);
			x.browser.go(path);
			push("/folder/" + StringTools.urlEncode(path));
		} else x.open(name);
	}

	// a recent file: its folder pushed under it, then it full size
	public function reopen(path:String) {
		var dir = Browser.parent(path);
		if (dir == null) return;
		nav.reset("/");
		x.browser.go(dir, Browser.name(path));
		push("/folder/" + StringTools.urlEncode(dir));
		x.start(path);
	}

	// the inspector's sheet: of the file shown, else the selection
	public function showInfo(full:Bool) {
		if (full && x.viewer.folder.name != "") x.browser.select(x.viewer.folder.name);
		info(true);
	}

	// the system's share sheet with the file shown, else those selected
	public function openIn(full:Bool) {
		if (x.share == null) return;
		var names = full ? [x.viewer.folder.name] : x.browser.picked();
		var paths = [for (n in names) if (n != "") x.files.localPath(x.browser.path(n)) ?? x.browser.path(n)];
		if (paths.length > 0) x.share(paths);
	}

	// a menu of the model at a node (the View menu: its choices checked)
	public function menu(at:Node, items:Array<MenuItem>) {
		if (at.ui == null) return;
		TouchMenu.open(at.ui, TouchMenu.choices(at.ui, items, at), at.windowBounds(), null, false, at.sheet());
	}
}
