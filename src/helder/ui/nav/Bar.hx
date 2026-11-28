package helder.ui.nav;

import helder.ui.Node;
import helder.ui.SafeArea;
import helder.ui.VirtualScroll;
import helder.ui.controls.Look;
import helder.ui.menu.TouchMenu;
import helder.ui.nav.Screens.Here;
import helder.ui.view.UiView;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Context;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;

typedef NavScreenProps = {
	title:Read<String>,
	?large:Bool,
	?subtitle:Read<String>,
	?leading:Any,
	?trailing:Any,
	?header:Any,
	?bottom:Any,
	?scrolls:Bool,
	?bars:Read<Bool>,
	?tag:String,
	?children:Any
}

// A screen of a Stack with its bars, iOS's navigation bar: the title, a
// large one over the content (large) that scrolls with it and moves into
// the bar as it goes under (the bar's fill showing once something is under
// it); the back button with the title of the screen below (a long press:
// a menu of the screens below, any of them popped to), leading items after
// it, trailing ones at the end (NavButton); a header under the large title
// (a search field) scrolled with it; a bottom bar (a toolbar, tabs) over
// the content; bars={false} hides them (a viewer's tap). The content
// scrolls in a scroller of the screen's, insets left for the bars, or in
// its own (scrolls={false}: one that calls scroller, a VirtualGrid's ref).
// Its parts are the look's (Look.part: nav-screen, nav-bar, nav-bar-fill,
// nav-title, nav-large, nav-large-title, nav-subtitle, nav-back,
// nav-back-title, nav-item, nav-bottom; Look.base's).
class Bar implements Markup {
	public static inline var HEIGHT = 44.0;

	// the NavScreen a component is in
	public static final here:Context<Null<NavState>> = context((null : Null<NavState>));

	public static function NavScreen(props:NavScreenProps):UiView {
		var at = use(Screens.here), look = Look.current(), own = Look.outside();
		var st = new NavState(at, props);
		setContext(here, st);
		var bars:Read<Bool> = props.bars == null ? () -> true : Read.of(props.bars);
		var below = () -> at == null ? null : at.below()[0];
		// (the large title and the header: the scroller's first content, or over its own scroller's top inset)
		var top = props.large != true && props.header == null ? null : <view style={look.part("nav-large")} opacity={1 - st.collapsed()} flexShrink={0}
			onResize={e -> st.sized(1, e.target.height)}>
			{props.large == true ? <text style={look.part("nav-large-title")} role="heading" aria-level={1}>{props.title()}</text> : null}
			{props.large == true && props.subtitle != null ? <text style={look.part("nav-subtitle")}>{props.subtitle()}</text> : null}
			{props.header}
		</view>;
		return <view tag={props.tag ?? "nav-screen"} style={look.part("nav-screen")} flexGrow={1} position="relative" overflow="hidden"
			ref={(n:Node) -> if (own) n.theme = look.theme}>
			{props.scrolls == false ? <>
				{props.children}
				{top == null ? null : <view position="absolute" left={0} right={0} top={st.barHeight()} transform={"translateY(" + (-st.offset()) + "px)"}>{top}</view>}
			</> : <scroll tag="nav-scroll" position="absolute" left={0} top={0} right={0} bottom={0} ref={(n:Node) -> st.scroller(n, true)}>
				{top}
				{props.children}
			</scroll>}
			<view style={look.part("nav-bar")} position="absolute" left={0} top={0} right={0} padding="env(safe-area-inset-top) 0 0 0" opacity={bars() ? 1 : 0}
				pointerEvents={bars() ? "auto" : "none"} transition="opacity 200ms ease-out" onResize={e -> st.sized(0, e.target.height)}>
				<view style={look.part("nav-bar-fill")} position="absolute" left={0} top={0} right={0} bottom={0} opacity={st.filled()} pointerEvents="none"/>
				<view flexDirection="row" alignItems="center" height={HEIGHT} position="relative" zIndex={1} padding="0 8">
					<Show when={below() != null}>
						<button style={look.part("nav-back")} tag="nav-back" aria-label={"Back to " + (below()?.title() ?? "")}
							onPress={() -> at.back()} onLongPress={g -> if (g.state == Began) st.backMenu()}>
							<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"
								width={24} height={24}><path d="m15 18-6-6 6-6"/></svg>
							<text style={look.part("nav-back-title")}>{below()?.title() ?? ""}</text>
						</button>
					</Show>
					{props.leading}
					<view flexGrow={1}/>
					{props.trailing}
					<text style={look.part("nav-title")} tag="nav-title" position="absolute" left={96} right={96} pointerEvents="none" opacity={st.collapsed()}>{props.title()}</text>
				</view>
			</view>
			{props.bottom != null ? <view style={look.part("nav-bottom")} position="absolute" left={0} right={0} bottom={0} padding="0 0 env(safe-area-inset-bottom) 0"
				opacity={bars() ? 1 : 0} pointerEvents={bars() ? "auto" : "none"} transition="opacity 200ms ease-out"
				onResize={e -> st.sized(2, e.target.height)}>{props.bottom}</view> : null}
		</view>;
	}

	// a bar's item: an icon or a label, 44 points square at least (a touch's)
	public static function NavButton(props:{label:String, ?icon:helder.ui.Svg, ?tag:String, ?disabled:Read<Bool>, onPress:Void->Void}):UiView {
		var off:Read<Bool> = props.disabled == null ? () -> false : Read.of(props.disabled);
		return <button style={Look.current().part("nav-item")} tag={props.tag} aria-label={props.label} focusable={!off()} data-disabled={off()}
			onPress={() -> if (!off()) props.onPress()}>
			{props.icon != null ? <image src={props.icon} width={22} height={22}/> : <text>{props.label}</text>}
		</button>;
	}
}

// A NavScreen's state: its scroller's offset, its bars' heights, how far
// its large title went into the bar
class NavState {
	// the scroller's offset, the bars' and the large title's heights
	public final offset = signalOf(0.0, {ownedWrite: true});
	public final barHeight = signalOf(Bar.HEIGHT + SafeArea.insets.peek().top, {ownedWrite: true});
	public final largeHeight = signalOf(0.0, {ownedWrite: true});
	public final bottomHeight = signalOf(0.0, {ownedWrite: true});
	// (0 the large title in place, 1 in the bar; the bar's fill)
	public final collapsed:Read<Float>;
	public final filled:Read<Float>;
	final at:Null<Here>;
	final large:Bool;
	var scrolls:Null<Node> = null;
	// (the bar's, the large title's and the bottom bar's heights, as laid out)
	final heights = [Bar.HEIGHT + SafeArea.insets.peek().top, 0.0, 0.0];
	var inset:Null<Void->Void> = null;
	// (the scroller its own: the large title its first content)
	var inner = false;

	public function new(at:Null<Here>, props:NavScreenProps) {
		this.at = at;
		large = props.large == true;
		var title:Read<String> = Read.of(props.title);
		if (at != null) renderEffect(() -> title(), t -> at.screen.title(t));
		collapsed = memo(() -> large ? clamp((offset() - Math.max(0, largeHeight() - 20)) / 12) : 1.0);
		filled = memo(() -> clamp((offset() - (large ? largeHeight() : 0)) / 8));
	}

	static function clamp(v:Float):Float
		return v < 0 ? 0 : v > 1 ? 1 : v;

	// n the screen's scroller: its top and bottom left for the bars (a
	// VirtualScroll's insets, else its padding), its offset followed
	public function scroller(n:Node, own = false) {
		scrolls = n;
		inner = own;
		var v:Null<VirtualScroll> = Std.downcast(n, VirtualScroll);
		var top0 = v != null ? @:privateAccess v.insetTop : n.used.paddingPx(0);
		var bottom0 = v != null ? @:privateAccess v.insetBottom : n.used.paddingPx(2);
		inset = () -> {
			var top = top0 + heights[0] + (inner ? 0 : heights[1]), bottom = bottom0 + heights[2];
			if (v != null) {
				v.insets(top, bottom);
				return;
			} else {
				if (n.used.paddingPx(0) == top && n.used.paddingPx(2) == bottom) return;
				n.style = n.style.with({padding: [top, n.used.paddingPx(1), bottom, n.used.paddingPx(3)]});
			}
			n.markDirty();
		};
		inset();
		var was = n.onScroll;
		n.onScroll = () -> {
			if (was != null) was();
			offset(n.scrollY);
		};
	}

	// (a bar laid out: 0 the top one, 1 the large title, 2 the bottom one;
	// the scroller's insets at once, laid out again in the same update)
	@:allow(helder.ui.nav.Bar) function sized(which:Int, h:Float) {
		if (heights[which] == h) return;
		heights[which] = h;
		(which == 0 ? barHeight : which == 1 ? largeHeight : bottomHeight)(h);
		if (inset != null) inset();
	}

	// the scroller moved to y (0: the top, the large title in place)
	public function scrollTo(y:Float) {
		var n = scrolls;
		if (n == null) return;
		n.scrollY = y;
		offset(y);
	}

	// (the back button's long press: the screens below, the nearest first)
	@:allow(helder.ui.nav.Bar) function backMenu() {
		var h = at;
		if (h == null) return;
		var b = h.screen.node?.find("nav-back");
		if (b == null || b.ui == null) return;
		var below = h.below();
		TouchMenu.open(b.ui, [for (k => s in below) {label: s.title.peek() == "" ? s.entry.path : s.title.peek(), run: () -> h.back(k)}], b.windowBounds(), null,
			false, b.scope());
	}
}
