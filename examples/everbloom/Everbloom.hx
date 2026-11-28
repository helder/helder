// title: Everbloom
// summary: The shop app of the frameworks benchmark (whiskerrs/benchmarks): a Storefront GraphQL catalog with collections, products, search and a cart, three tabs with their own stacks
// tags: ui, view, network
// demo: none
import Api;
import Theme;
import helder.async.Async;
import helder.os.App;
import helder.os.SystemLog;
import helder.ui.*;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;

// The benchmark's shop (its prompt: examples/everbloom/README.md): Home,
// Collection, Product, Search and Cart on helder.ui, the data from the
// Storefront API (Api: mock.shop, or SHOP_API_URL, the benchmark's
// replay server), the images fetched and decoded by helder (Img). Three
// tabs, each a stack of screens kept while it is not shown; the tab bar
// hidden on a product. The identifiers the benchmark's XCUITest runner
// looks for are the nodes' ids (Semantics.identifier: iOS's
// accessibilityIdentifier), and "SHOPBENCH home_ready" goes to the system
// log (helder.os.SystemLog) on the first frame Home shows its content.
class Everbloom implements Markup {
	// (the three tabs' stacks: Home's and Search's grow, Cart's is one screen)
	public static final tab = signal(0);
	public static final stacks:Array<Signal<Array<Route>>> = [signal([new Route(Home)]), signal([new Route(Search)]), signal([new Route(Cart)])];
	public static final cart:Signal<Null<Cart>> = signal(null);
	public static final cartBusy = signal(false);
	public static final alert:Signal<Null<String>> = signal(null);
	static var window:Null<UiWindow> = null;
	static var homeShown = false;

	static function main() {
		App.onBack = () -> back();
		UiWindow.run(<Surface title="Everbloom" width={390} height={844} background={Theme.BACKGROUND} ref={w -> window = w}>
			{view()}
		</Surface>);
	}

	// (Home's content is in: the frame that shows it logs the marker, once)
	public static function homeReady() {
		if (homeShown) return;
		homeShown = true;
		var w = window;
		if (w == null) return SystemLog.write("SHOPBENCH home_ready");
		var before = w.onFrame;
		w.onFrame = () -> {
			w.onFrame = before;
			if (before != null) before();
			SystemLog.write("SHOPBENCH home_ready");
		};
		w.ui.requestFrame();
	}

	public static function push(r:Route) {
		var s = stacks[tab.peek()];
		s(s.peek().concat([r]));
	}

	// the active tab's top screen popped: false at its root
	public static function back():Bool {
		var s = stacks[tab.peek()], list = s.peek();
		if (list.length <= 1) return false;
		s(list.slice(0, list.length - 1));
		return true;
	}

	static function top():Route {
		var list = stacks[tab()]();
		return list[list.length - 1];
	}

	// adds one of a variant: CartCreate first, CartLinesAdd after; true when it was added
	public static function addToCart(variant:String, done:Bool->Void) {
		var c = cart.peek();
		cartBusy(true);
		Async.launch(@:coroutine function(_) return c == null ? Api.cartCreate(variant) : Api.cartAdd(c.id, variant)).onCompletion((r, e) -> {
			cartBusy(false);
			var ok = cartResult(r, e);
			if (ok) tab(2);
			done(ok);
		});
	}

	public static function updateLine(line:String, quantity:Int) {
		var c = cart.peek();
		if (c == null) return;
		cartBusy(true);
		Async.launch(@:coroutine function(_) return Api.cartUpdate(c.id, line, quantity)).onCompletion((r, e) -> {
			cartBusy(false);
			cartResult(r, e);
		});
	}

	// (the cart the response has replaces it; its first user error an alert)
	static function cartResult(r:Null<CartResult>, e:Null<haxe.Exception>):Bool {
		if (e != null || r == null) {
			alert("Couldn't update your cart. Check your connection and try again.");
			return false;
		}
		if (r.cart != null) cart(r.cart);
		if (r.error != null) {
			alert(r.error);
			return false;
		}
		return r.cart != null;
	}

	static function view():View
		return <view flexGrow={1} background={Theme.BACKGROUND} color={Theme.TEXT}>
			<view flexGrow={1} minHeight={0}>
				<Repeat count={3}>{t -> <view position="absolute" left={0} top={0} right={0} bottom={0} display={tab() == t ? "flex" : "none"}>
					<For each={stacks[t]}>{(route:Read<Route>) -> {
						// (the screen made once, untracked: its row's)
						var r = untrack(() -> route()), screen = untrack(() -> Screens.of(r));
						<view position="absolute" left={0} top={0} right={0} bottom={0} display={top() == r ? "flex" : "none"}>{screen}</view>;
					}}</For>
				</view>}</Repeat>
			</view>
			<Show when={!top().isProduct()}>{TabBar()}</Show>
			<Show when={alert() != null}>{Alert()}</Show>
		</view>;

	static function TabBar():View
		return <view role="tablist" flexDirection="row" background={Theme.BACKGROUND} borderWidth="1 0 0 0" borderColor={Theme.BORDER}
			padding="0 0 env(safe-area-inset-bottom) 0">
			<Repeat count={3}>{t -> <button id={["tab-home", "tab-search", "tab-cart"][t]} role="tab" aria-selected={tab() == t} flexGrow={1} flexBasis={0}
				height={49} alignItems="center" justifyContent="center" rowGap={2} onPress={() -> tab(t)}>
				<view>
					{Theme.icon([Theme.HOME, Theme.SEARCH, Theme.CART][t], 24, tab() == t ? Theme.TEXT : Theme.MUTED)}
					<Show when={t == 2 && (cart()?.totalQuantity ?? 0) > 0}>
						<view id="cart-badge" position="absolute" top={-4} left={18} minWidth={18} height={18} padding="0 5" borderRadius={9} background={Theme.SALE}
							alignItems="center" justifyContent="center">
							<text color="#ffffff" fontSize={11} fontWeight={700}>{Std.string(cart()?.totalQuantity ?? 0)}</text>
						</view>
					</Show>
				</view>
				<text fontSize={11} fontWeight={tab() == t ? 600 : 500} color={tab() == t ? Theme.TEXT : Theme.MUTED}>{["Home", "Search", "Cart"][t]}</text>
			</button>}</Repeat>
		</view>;

	static function Alert():View
		return <view position="absolute" left={0} top={0} right={0} bottom={0} background="rgba(0,0,0,0.4)" alignItems="center" justifyContent="center"
			role="alertdialog" aria-label="Alert">
			<view width={280} borderRadius={14} background={Theme.BACKGROUND} padding={20} rowGap={16} alignItems="center">
				<text fontSize={15} lineHeight="20px" textAlign="center">{alert() ?? ""}</text>
				<button height={44} alignSelf="stretch" borderRadius={12} background={Theme.TEXT} alignItems="center"
					justifyContent="center" onPress={() -> alert(null)}><text color="#ffffff" fontSize={16} fontWeight={600}>OK</text></button>
			</view>
		</view>;
}

enum RouteKind {
	Home;
	Collection(c:Api.Collection);
	ProductPage(handle:String);
	Search;
	Cart;
}

// a screen in a stack (its own: pushed twice, two screens)
class Route {
	public final kind:RouteKind;

	public function new(kind)
		this.kind = kind;

	public function isProduct():Bool
		return kind.match(ProductPage(_));
}
