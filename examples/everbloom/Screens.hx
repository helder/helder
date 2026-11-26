import Api;
import Everbloom.Route;
import Theme.*;
import helder.async.Async;
import helder.async.Task;
import helder.os.Links;
import helder.ui.*;
import helder.ui.view.UiFlow.*;
import helder.ui.controls.Pager;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;

// The five screens (design/screens/*.dc.html), each made when its route
// is pushed and kept while it is in its stack.
class Screens implements Markup {
	public static function of(r:Route):View
		return switch r.kind {
			case Home: new HomeScreen().view();
			case Collection(c): new CollectionScreen(c).view();
			case ProductPage(handle): new ProductScreen(handle).view();
			case Search: new SearchScreen().view();
			case Cart: CartScreen.view();
		}

	// (after the screen is made: its first load's writes not in its making)
	public static function later(f:Void->Void)
		Async.launch(@:coroutine function(_) {
			f();
			return null;
		});

	public static function openProduct(p:Product)
		Everbloom.push(new Route(ProductPage(p.handle)));

	public static function openCollection(c:Collection)
		Everbloom.push(new Route(Collection(c)));

	// (the safe area's top, then a bar of 44)
	public static function NavBar(props:{title:String}):View
		return <view paddingTop="env(safe-area-inset-top)" flexShrink={0}>
			<view height={44} padding="0 8" flexDirection="row" alignItems="center">
				<Back/>
				<text flexGrow={1} flexBasis={0} minWidth={0} fontSize={17} fontWeight={600} textAlign="center" lineClamp={1} textOverflow="ellipsis">{props.title}</text>
				<view width={44}/>
			</view>
		</view>;
}

// a search's result: its place, its product
typedef Hit = {i:Int, p:Product};

// a long list's rows: a screen's head, two cards, the end (a spinner, a retry, nothing)
enum Row {
	Head;
	Pair(i:Int, a:Product, b:Null<Product>);
	End;
}

// a list fetched page by page (a collection's, a search's): reloaded from
// the first page, the next asked for near the end; a response for an older
// load let go
class Paged {
	public final products:Signal<Array<Product>> = signal([]);
	public final loading = signal(false);
	public final failed = signal(false);
	public final first = signal(true);
	public final total:Signal<Null<Int>> = signal(null);
	public final description:Signal<Null<String>> = signal(null);
	var cursor:Null<String> = null;
	var hasNext = true;
	var generation = 0;
	var task:Null<Task<ProductPage>> = null;
	final fetch:(after:Null<String>, done:(Null<ProductPage>, Null<haxe.Exception>) -> Void) -> Task<ProductPage>;

	public function new(fetch)
		this.fetch = fetch;

	public function reset() {
		generation++;
		task?.cancel();
		task = null;
		products([]);
		cursor = null;
		hasNext = true;
		first(true);
		failed(false);
		loading(false);
	}

	public function more() {
		if (loading.peek() || !hasNext || failed.peek()) return;
		var g = generation;
		loading(true);
		task = fetch(cursor, (page, e) -> {
			if (g != generation) return;
			task = null;
			loading(false);
			if (e != null || page == null) {
				failed(true);
				return;
			}
			hasNext = page.hasNext && page.cursor != null;
			cursor = page.cursor;
			if (first.peek()) {
				description(page.description);
				total(page.total);
			}
			first(false);
			products(products.peek().concat(page.products));
		});
	}

	public function retry() {
		failed(false);
		more();
	}

	// the grid's rows: the head, the cards two by two, the end
	public function rows(head:Bool):Array<Row> {
		var ps = products(), out = head ? [Head] : [];
		var i = 0;
		while (i < ps.length) {
			out.push(Pair(i, ps[i], i + 1 < ps.length ? ps[i + 1] : null));
			i += 2;
		}
		out.push(End);
		return out;
	}

	public static function key(r:Row):Dynamic
		return switch r {
			case Head: "head";
			case Pair(i, _, _): i;
			case End: "end";
		}

	// (the list: near its end, the next page)
	public function watch(list:VirtualScroll) {
		list.rowRole = null;
		list.focusableRows = false;
		list.onScroll = () -> if (list.count > 0 && list.lastVisible() >= list.count - 4) more();
	}
}

class HomeScreen implements Markup {
	final data:Signal<Null<HomeData>> = signal(null);
	final failed = signal(false);

	public function new()
		Screens.later(load);

	function load() {
		failed(false);
		Async.launch(@:coroutine function(_) return Api.home()).onCompletion((d, e) -> {
			if (e != null || d == null) failed(true) else {
				data(d);
				Everbloom.homeReady();
			}
		});
	}

	public function view():View
		return <view flexGrow={1} minHeight={0}>
			<Show when={!failed()} fallback={<view flexGrow={1} paddingTop="env(safe-area-inset-top)">{header()}<Failed onRetry={load}/></view>}>
				<scroll id="home-scroll" flexGrow={1} minHeight={0} scrollbarWidth="none">
					<view paddingTop="env(safe-area-inset-top)" paddingBottom={24}>
						{header()}
						<Show when={data() != null} fallback={skeleton()}>{content(data())}</Show>
					</view>
				</scroll>
			</Show>
		</view>;

	static function header():View
		return <view height={44} padding="0 16" justifyContent="center"><text fontSize={22} fontWeight={700} letterSpacing={-0.4}>Everbloom</text></view>;

	// (States.dc.html's Home loading)
	static function skeleton():View
		return <view>
			<view flexDirection="row" columnGap={8} padding="8 16 12">
				<Repeat count={4}>{i -> <view width={[52, 110, 96, 80][i]} height={36} borderRadius={18} background={SKELETON}/>}</Repeat>
			</view>
			<view margin="4 16 0" height={240} borderRadius={12} background={SKELETON}/>
			<view padding="28 16 12"><view width={120} height={18} borderRadius={4} background={SKELETON}/></view>
			<view flexDirection="row" columnGap={12} padding="0 16">
				<Repeat count={3}>{_ -> <view width={140} height={175} flexShrink={0} borderRadius={8} background={SKELETON}/>}</Repeat>
			</view>
		</view>;

	static function content(d:HomeData):View {
		var featured = d.collections[0];
		return <view>
			<scroll flexDirection="row" scrollbarWidth="none" columnGap={8} padding="8 16 12" flexShrink={0} role="navigation" aria-label="Collections">
				<Repeat count={d.collections.length}>{i -> <button id={"collection-chip-" + i} flexShrink={0} height={36}
					padding="0 14" borderRadius={18} background={SURFACE} justifyContent="center" onPress={() -> Screens.openCollection(d.collections[i])}>
					<text fontSize={14} fontWeight={500} textWrap="nowrap">{d.collections[i].title}</text>
				</button>}</Repeat>
			</scroll>
			<Show when={featured != null}>
				<button id="featured-collection" aria-label={featured.title} margin="4 16 0" height={240} borderRadius={12}
					overflow="hidden" background={SURFACE} onPress={() -> Screens.openCollection(featured)}>
					<Picture url={featured.image} width={1080} w="100%" h={240} radius={12}/>
					<view position="absolute" left={0} right={0} bottom={0} padding={16} rowGap={2} background="rgba(28,27,25,0.72)">
						<text color="#ffffff" fontSize={12} fontWeight={600} letterSpacing={0.6}>FEATURED COLLECTION</text>
						<text color="#ffffff" fontSize={20} fontWeight={700}>{featured.title}</text>
						<text color="#ffffff" fontSize={14}>Shop now</text>
					</view>
				</button>
			</Show>
			<view padding="28 0 0">
				<text padding="0 16 12" fontSize={17} fontWeight={700} role="heading">Collections</text>
				<scroll flexDirection="row" scrollbarWidth="none" columnGap={12} padding="0 16" flexShrink={0}>
					<Repeat count={d.collections.length}>{i -> {
						var c = d.collections[i];
						<button id={"collection-card-" + i} aria-label={c.title} flexShrink={0} width={140} rowGap={8}
							onPress={() -> Screens.openCollection(c)}>
							<Picture url={c.image} width={480} w={140} h={175}/>
							<text fontSize={14} fontWeight={600} lineHeight="18px">{c.title}</text>
						</button>;
					}}</Repeat>
				</scroll>
			</view>
			<view padding="28 16 0" rowGap={12}>
				<text fontSize={17} fontWeight={700} role="heading">Best sellers</text>
				<view rowGap={20}>
					<Repeat count={Math.ceil(d.bestSellers.length / 2)}>{r -> <view flexDirection="row" columnGap={12} alignItems="start">
						<Card product={d.bestSellers[r * 2]} id={"best-seller-" + (r * 2)} onOpen={Screens.openProduct}/>
						{d.bestSellers.length > r * 2 + 1 ? <Card product={d.bestSellers[r * 2 + 1]} id={"best-seller-" + (r * 2 + 1)}
							onOpen={Screens.openProduct}/> : <view flexGrow={1} flexBasis={0}/>}
					</view>}</Repeat>
				</view>
			</view>
		</view>;
	}
}

class CollectionScreen implements Markup {
	static final SORTS:Array<Sort> = [
		{label: "Featured", id: "sort-featured", key: "COLLECTION_DEFAULT", reverse: false},
		{label: "Best selling", id: "sort-best-selling", key: "BEST_SELLING", reverse: false},
		{label: "Price: low to high", id: "sort-price-asc", key: "PRICE", reverse: false},
		{label: "Price: high to low", id: "sort-price-desc", key: "PRICE", reverse: true}
	];

	final collection:Collection;
	final sort = signal(0);
	final paged:Paged;
	var list:Null<VirtualScroll> = null;

	public function new(c:Collection) {
		collection = c;
		paged = new Paged((after, done) -> {
			var s = SORTS[sort.peek()];
			var t = Async.launch(@:coroutine function(_) return Api.collection(c.handle, s, after));
			t.onCompletion(done);
			t;
		});
		Screens.later(paged.more);
	}

	function pick(i:Int) {
		if (sort.peek() == i) return;
		sort(i);
		paged.reset();
		list?.scrollToIndex(0, "start");
		paged.more();
	}

	public function view():View
		return <view flexGrow={1}>
			<Screens.NavBar title={collection.title}/>
			<Show when={!(paged.failed() && paged.first())} fallback={<Failed onRetry={paged.retry}/>}>
				<VirtualList tag="grid" each={() -> paged.rows(true)} by={Paged.key} estimate={300} overscan={2} label={collection.title} ref={l -> {
					list = l;
					l.semantics.identifier = "product-grid";
					paged.watch(l);
				}}>{(row:Read<Row>, _) -> switch row() {
					case Head: head();
					case Pair(i, a, b): <view flexDirection="row" columnGap={12} padding="0 16 20" alignItems="start">
							<Card product={a} id={"product-card-" + i} onOpen={Screens.openProduct}/>
							{b == null ? <view flexGrow={1} flexBasis={0}/> : <Card product={b} id={"product-card-" + (i + 1)} onOpen={Screens.openProduct}/>}
						</view>;
					case End: <view paddingBottom={16}>
							<Show when={paged.loading()}>{Spinner()}</Show>
							<Show when={paged.failed() && !paged.first()}>
								<view alignItems="center" padding={12}><Button id="error-retry" label="Retry" secondary height={40} onPress={paged.retry}/></view>
							</Show>
						</view>;
				}}</VirtualList>
			</Show>
		</view>;

	function head():View
		return <view>
			<Show when={(paged.description() ?? "") != ""}>
				<text padding="4 16 0" fontSize={14} lineHeight="20px" color={MUTED}>{paged.description() ?? ""}</text>
			</Show>
			<scroll flexDirection="row" scrollbarWidth="none" columnGap={8} padding="12 16" role="radiogroup" aria-label="Sort">
				<Repeat count={SORTS.length}>{i -> <button id={SORTS[i].id} role="radio" aria-checked={sort() == i} flexShrink={0} height={32}
					padding="0 12" borderRadius={16} borderWidth={1} borderColor={sort() == i ? TEXT : BORDER} background={sort() == i ? TEXT : BACKGROUND}
					justifyContent="center" onPress={() -> pick(i)}>
					<text fontSize={13} fontWeight={sort() == i ? 600 : 500} color={sort() == i ? "#ffffff" : TEXT} textWrap="nowrap">{SORTS[i].label}</text>
				</button>}</Repeat>
			</scroll>
		</view>;
}

class ProductScreen implements Markup {
	final handle:String;
	final data:Signal<Null<ProductDetail>> = signal(null);
	final failed = signal(false);
	final variant:Signal<Null<Variant>> = signal(null);
	final adding = signal(false);

	public function new(handle:String) {
		this.handle = handle;
		Screens.later(load);
	}

	function load() {
		failed(false);
		Async.launch(@:coroutine function(_) return Api.product(handle)).onCompletion((d, e) -> {
			if (e != null || d == null) {
				failed(true);
				return;
			}
			var first = null;
			for (v in d.variants)
				if (v.available) {
					first = v;
					break;
				}
			variant(first ?? d.variants[0]);
			data(d);
		});
	}

	// a pill tapped: the variant of that combination, else the first with that value
	function choose(option:String, value:String) {
		var d = data.peek(), v = variant.peek();
		if (d == null) return;
		var want = new Map<String, String>();
		if (v != null) for (k => x in v.options) want.set(k, x);
		want.set(option, value);
		var exact = null, fallback = null;
		for (c in d.variants) {
			var all = true;
			for (k => x in want)
				if (c.options.get(k) != x) all = false;
			if (all && exact == null) exact = c;
			if (fallback == null && c.options.get(option) == value) fallback = c;
		}
		if (exact != null || fallback != null) variant(exact ?? fallback);
	}

	function add() {
		var v = variant.peek();
		if (v == null || adding.peek()) return;
		adding(true);
		Everbloom.addToCart(v.id, _ -> adding(false));
	}

	public function view():View
		return <view flexGrow={1} minHeight={0}>
			<Show when={data() != null} fallback={<view flexGrow={1}>
				<view padding="calc(env(safe-area-inset-top) + 4px) 12 0" flexShrink={0}><Back round/></view>
				<Show when={failed()} fallback={<view flexGrow={1} justifyContent="center">{Spinner()}</view>}><Failed onRetry={load}/></Show>
			</view>}>{content(data())}</Show>
		</view>;

	function content(d:ProductDetail):View {
		var options = [for (o in d.options) if (!(o.name == "Title" && o.values.length == 1 && o.values[0] == "Default Title")) o];
		return <view flexGrow={1} minHeight={0}>
			<scroll flexGrow={1} minHeight={0}>
				<view paddingBottom={32}>
					<view>
						<Carousel images={d.images}/>
						<view position="absolute" left={12} top="calc(env(safe-area-inset-top) + 4px)"><Back round/></view>
					</view>
					<view padding="20 16 0" rowGap={6}>
						<text fontSize={22} lineHeight="28px" fontWeight={700} role="heading">{d.title}</text>
						<Show when={variant() != null}><Price price={variant().price} compareAt={variant().compareAt} size={20}/></Show>
					</view>
					<For each={options}>{(o:Read<Option>) -> {
						var opt = o();
						<view padding="24 16 0" rowGap={12}>
							<view flexDirection="row">
								<text fontSize={15} fontWeight={600} paddingRight={4}>{opt.name + ":"}</text>
								<text fontSize={15} color={MUTED}>{variant()?.options.get(opt.name) ?? ""}</text>
							</view>
							<view flexDirection="row" flexWrap columnGap={8} rowGap={8}>
								<For each={opt.values}>{(value:Read<String>) -> {
									var val = value(), on = () -> variant()?.options.get(opt.name) == val;
									<button id={"option-" + opt.name + "-" + val} aria-pressed={on()} minWidth={56} height={44}
										padding="0 16" borderRadius={12} borderWidth={on() ? 2 : 1} borderColor={on() ? TEXT : BORDER} alignItems="center"
										justifyContent="center" onPress={() -> choose(opt.name, val)}>
										<text fontSize={15} fontWeight={on() ? 600 : 500}>{val}</text>
									</button>;
								}}</For>
							</view>
						</view>;
					}}</For>
					<view padding="24 16 0" rowGap={8}>
						<text fontSize={15} fontWeight={600} role="heading">Description</text>
						<text fontSize={15} lineHeight="22px" color={BODY}>{d.description}</text>
					</view>
					<Show when={d.recommendations.length > 0}>
						<view padding="32 0 0" rowGap={12}>
							<text padding="0 16" fontSize={17} fontWeight={700} role="heading">You may also like</text>
							<scroll flexDirection="row" scrollbarWidth="none" columnGap={12} padding="0 16">
								<Repeat count={d.recommendations.length}>{i -> <Card product={d.recommendations[i]} id={"recommendation-" + i} width={140}
									onOpen={Screens.openProduct}/>}</Repeat>
							</scroll>
						</view>
					</Show>
				</view>
			</scroll>
			<view padding="12 16" paddingBottom="max(12px, env(safe-area-inset-bottom))" borders="1 0 0 0" borderColor={BORDER} background={BACKGROUND}>
				<Button id="add-to-cart" label={"Add to cart · " + (variant()?.price.toString() ?? "")} disabled={() -> adding() || Everbloom.cartBusy()}
					onPress={add}/>
			</view>
		</view>;
	}

	static function slide(url:String):View
		return <view><Picture url={url} width={1080} w="100%" ratio={0.75} radius={0}/></view>;

	// up to ten images (3:4), swiped; the dots below them
	static function Carousel(props:{images:Array<String>}):View {
		var page = signal(0), n = props.images.length;
		var pager = new Pager(page, n == 0 ? 1 : n, p -> page(p));
		var slides:Array<View> = [for (url in props.images) slide(url)];
		var pages:View = n == 0 ? <view aspectRatio={0.75}/> : <Pager.Pages pager={pager} slides={slides}/>;
		return <view id="product-carousel" background={SURFACE}>
			{pages}
			<Show when={n > 1}>
				<view position="absolute" left={0} right={0} bottom={12} flexDirection="row" justifyContent="center" columnGap={4}>
					<Repeat count={n}>{i -> <button aria-label={"Show image " + (i + 1)} width={24} height={24} alignItems="center"
						justifyContent="center" onPress={() -> page(i)}>
						<view width={8} height={8} borderRadius={4} background={page() == i ? TEXT : "rgba(255,255,255,0.8)"}/>
					</button>}</Repeat>
				</view>
			</Show>
		</view>;
	}
}

class SearchScreen implements Markup {
	final query = signal("");
	final paged:Paged;
	var typing:Null<Task<Any>> = null;
	var current = "";

	public function new() {
		paged = new Paged((after, done) -> {
			var q = current;
			var t = Async.launch(@:coroutine function(_) return Api.search(q, after));
			t.onCompletion(done);
			t;
		});
	}

	// (the field's text: sent 300 ms after the last key; empty, the results cleared at once)
	function input(text:String) {
		query(text);
		typing?.cancel();
		var q = StringTools.trim(text);
		if (q == "") {
			current = "";
			paged.reset();
			return;
		}
		typing = Async.launch(@:coroutine function(_) {
			Async.delay(0.3);
			return null;
		});
		typing.onCompletion((_, e) -> {
			if (e != null || q == current) return;
			current = q;
			paged.reset();
			paged.more();
		});
	}

	function hits():Array<Hit>
		return [for (i => p in paged.products()) ({i: i, p: p} : Hit)];

	public function view():View
		return <view flexGrow={1} paddingTop="env(safe-area-inset-top)">
			<view padding="4 16 12" flexShrink={0}>
				<view height={44} borderRadius={12} background={SURFACE} flexDirection="row" alignItems="center" columnGap={8} padding="0 12">
					{icon(SEARCH, 20, MUTED)}
					<field id="search-input" flexGrow={1} minWidth={0} fontSize={16} value={query} placeholder="Search products" aria-label="Search products"
						background="transparent" borderWidth={0} onInput={e -> input(e.text)}/>
				</view>
			</view>
			<Show when={StringTools.trim(query()) != ""} fallback={<text padding="48 32" fontSize={15} lineHeight="22px" color={MUTED}
				textAlign="center">Search across 995 products by name.</text>}>
				<Show when={!(paged.failed() && paged.first())} fallback={<Failed onRetry={paged.retry}/>}>
					<Show when={paged.total() != null}>
						<text padding="4 16 8" fontSize={13} color={MUTED} flexShrink={0}>{(paged.total() ?? 0) + " results"}</text>
					</Show>
					<Show when={!paged.first()} fallback={Spinner()}>
						<VirtualList tag="results" each={hits} by={x -> x.i} estimate={101} overscan={4}
							label="Search results" ref={l -> {
								l.semantics.identifier = "search-results";
								paged.watch(l);
							}}>{(item:Read<Hit>, _) -> {
							var x = item();
							<button id={"search-result-" + x.i} aria-label={x.p.title} flexDirection="row" columnGap={12}
								alignItems="center" padding="8 16" onPress={() -> Screens.openProduct(x.p)}>
								<Picture url={x.p.image} width={240} w={64} h={85}/>
								<view flexGrow={1} minWidth={0} rowGap={4}>
									<text fontSize={15} lineHeight="20px">{x.p.title}</text>
									<Price price={x.p.price} compareAt={x.p.compareAt}/>
								</view>
							</button>;
						}}</VirtualList>
					</Show>
				</Show>
			</Show>
		</view>;
}

class CartScreen implements Markup {
	public static function view():View
		return <view flexGrow={1} paddingTop="env(safe-area-inset-top)">
			<view height={44} padding="0 16" justifyContent="center" flexShrink={0}><text fontSize={22} fontWeight={700} role="heading">Cart</text></view>
			<Show when={(Everbloom.cart()?.lines.length ?? 0) > 0} fallback={empty()}>
				<scroll flexGrow={1} minHeight={0}>
					<view padding="0 16">
						<For each={Everbloom.cart()?.lines ?? []} keyed={false}>{(line:Read<CartLine>) -> {
							var i = (Everbloom.cart()?.lines ?? []).indexOf(line());
							<view id={"cart-line-" + i} flexDirection="row" columnGap={12} padding="16 0" borders="0 0 1 0" borderColor={BORDER}>
								<Picture url={line().image} width={240} w={80} h={107}/>
								<view flexGrow={1} minWidth={0} rowGap={4}>
									<text fontSize={15} lineHeight="20px" fontWeight={600}>{line().title}</text>
									<Show when={line().variant != "Default Title"}><text fontSize={13} color={MUTED}>{line().variant}</text></Show>
									<view flexGrow={1}/>
									<view flexDirection="row" alignItems="center" justifyContent="space-between">
										<view flexDirection="row" alignItems="center" height={36} borderRadius={12} borderWidth={1} borderColor={BORDER}>
											{stepper("qty-dec-" + i, "Decrease quantity", Theme.MINUS, () -> Everbloom.updateLine(line().id, line().quantity - 1))}
											<text minWidth={24} textAlign="center" fontSize={15} fontWeight={600} aria-live="polite">{Std.string(line().quantity)}</text>
											{stepper("qty-inc-" + i, "Increase quantity", Theme.PLUS, () -> Everbloom.updateLine(line().id, line().quantity + 1))}
										</view>
										<text fontSize={15} fontWeight={700}>{line().total.toString()}</text>
									</view>
								</view>
							</view>;
						}}</For>
					</view>
				</scroll>
				<view padding={16} rowGap={12} borders="1 0 0 0" borderColor={BORDER} flexShrink={0}>
					<view flexDirection="row" justifyContent="space-between" alignItems="baseline">
						<text fontSize={15}>Subtotal</text>
						<text id="cart-subtotal" fontSize={17} fontWeight={700}>{Everbloom.cart()?.subtotal.toString() ?? ""}</text>
					</view>
					<text fontSize={13} color={MUTED}>Taxes and shipping are calculated at checkout.</text>
					<Button id="checkout" label="Check out" onPress={() -> {
						var c = Everbloom.cart.peek();
						if (c != null && c.checkoutUrl != "") Links.show(Api.absolute(c.checkoutUrl));
					}}/>
				</view>
			</Show>
		</view>;

	static function stepper(id:String, label:String, glyph:Theme.Icon, f:Void->Void):View
		return <button id={id} aria-label={label} width={36} height={34} alignItems="center" justifyContent="center"
			disabled={Everbloom.cartBusy()} onPress={() -> if (!Everbloom.cartBusy.peek()) f()}>{icon(glyph, 16, TEXT)}</button>;

	// (States.dc.html's empty cart)
	static function empty():View
		return <view flexGrow={1} alignItems="center" justifyContent="center" rowGap={12} padding="0 32">
			{icon(Theme.CART, 48, MUTED)}
			<text fontSize={17} fontWeight={700}>Your cart is empty</text>
			<text fontSize={15} lineHeight="22px" color={MUTED} textAlign="center">Items you add will appear here.</text>
			<view marginTop={8}><Button label="Start shopping" height={48} onPress={() -> Everbloom.tab(0)}/></view>
		</view>;
}
