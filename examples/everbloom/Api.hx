import haxe.Exception;
import helder.async.http.Client;

// The Storefront GraphQL API (mock.shop, or the benchmark's replay server:
// SHOP_API_URL): every request a POST of the whole document (storefront.graphql,
// as the benchmark's spec gives it), its operation named. A response
// without data, or not 2xx, is an error.
class Api {
	public static final endpoint:String = {
		var env = Sys.getEnv("SHOP_API_URL");
		env != null && env != "" ? env : #if shop_api_url haxe.macro.Compiler.getDefine("shop_api_url") #else "https://apparel-large-catalog.mock.shop/api" #end;
	}

	// a URL the API gave relative to its origin (the replay server's checkout: "/checkout")
	public static function absolute(url:String):String {
		if (!StringTools.startsWith(url, "/")) return url;
		var scheme = endpoint.indexOf("://"), slash = endpoint.indexOf("/", scheme + 3);
		return (slash < 0 ? endpoint : endpoint.substr(0, slash)) + url;
	}

	@:coroutine public static function query(operation:String, variables:Dynamic):Dynamic {
		var body = haxe.Json.stringify({operationName: operation, query: DOCUMENT, variables: variables});
		var r = Client.request(endpoint, {method: "POST", contentType: "application/json", text: body});
		if (r.status < 200 || r.status >= 300) throw new Exception('$operation: HTTP ${r.status}');
		var j:Dynamic = haxe.Json.parse(r.text());
		if (j == null || j.data == null) throw new Exception('$operation: no data');
		return j.data;
	}

	@:coroutine public static function home():HomeData {
		var d = query("Home", {});
		var cs:Array<Dynamic> = d.collections.nodes, ps:Array<Dynamic> = d.products.nodes;
		return {
			collections: [for (c in cs) {handle: c.handle, title: c.title, image: c.image?.url}],
			bestSellers: [for (p in ps) Product.card(p)]
		};
	}

	@:coroutine public static function collection(handle:String, sort:Sort, after:Null<String>):ProductPage {
		var d = query("CollectionProducts", {
			handle: handle,
			first: 24,
			after: after,
			sortKey: sort.key,
			reverse: sort.reverse
		});
		var c:Dynamic = d.collection;
		if (c == null) throw new Exception("no collection " + handle);
		return page(c.products, c.description, null);
	}

	@:coroutine public static function search(q:String, after:Null<String>):ProductPage {
		var d = query("Search", {query: q, first: 24, after: after});
		return page(d.search, null, d.search.totalCount);
	}

	static function page(conn:Dynamic, description:Null<String>, total:Null<Int>):ProductPage {
		var ns:Array<Dynamic> = conn.nodes;
		return {
			products: [for (p in ns) if (p != null && p.handle != null) Product.card(p)],
			hasNext: conn.pageInfo.hasNextPage == true,
			cursor: conn.pageInfo.endCursor,
			description: description,
			total: total
		};
	}

	@:coroutine public static function product(handle:String):ProductDetail {
		var d = query("Product", {handle: handle});
		var p:Dynamic = d.product;
		if (p == null) throw new Exception("no product " + handle);
		var images:Array<Dynamic> = p.images.nodes, options:Array<Dynamic> = p.options, variants:Array<Dynamic> = p.variants.nodes;
		var recs:Array<Dynamic> = d.productRecommendations ?? [];
		return {
			handle: p.handle,
			title: p.title,
			description: p.description ?? "",
			images: [for (i in images) i.url],
			options: [
				for (o in options) {
					var values:Array<Dynamic> = o.optionValues;
					{name: o.name, values: [for (v in values) (v.name : String)]};
				}
			],
			variants: [
				for (v in variants) {
					var sel:Array<Dynamic> = v.selectedOptions;
					var price = Money.of(v.price), compare = Money.of(v.compareAtPrice);
					{
						id: v.id,
						title: v.title,
						available: v.availableForSale == true,
						options: [for (s in sel) (s.name : String) => (s.value : String)],
						price: price,
						compareAt: compare > price ? compare : null
					};
				}
			],
			recommendations: [for (r in recs) Product.card(r)]
		};
	}

	@:coroutine public static function cartCreate(variant:String):CartResult
		return cart(query("CartCreate", {lines: [{merchandiseId: variant, quantity: 1}]}).cartCreate);

	@:coroutine public static function cartAdd(cartId:String, variant:String):CartResult
		return cart(query("CartLinesAdd", {cartId: cartId, lines: [{merchandiseId: variant, quantity: 1}]}).cartLinesAdd);

	@:coroutine public static function cartUpdate(cartId:String, line:String, quantity:Int):CartResult
		return cart(query("CartLinesUpdate", {cartId: cartId, lines: [{id: line, quantity: quantity}]}).cartLinesUpdate);

	static function cart(r:Dynamic):CartResult {
		var errors:Array<Dynamic> = r.userErrors ?? [];
		var c:Dynamic = r.cart;
		var parsed:Null<Cart> = null;
		if (c != null) {
			var nodes:Array<Dynamic> = c.lines?.nodes ?? [];
			parsed = {
				id: c.id,
				checkoutUrl: c.checkoutUrl ?? "",
				totalQuantity: c.totalQuantity ?? 0,
				subtotal: Money.of(c.cost?.subtotalAmount),
				lines: [
					for (n in nodes) {
						var m:Dynamic = n.merchandise ?? {}, p:Dynamic = m.product ?? {};
						{
							id: n.id,
							quantity: n.quantity,
							total: Money.of(n.cost?.totalAmount),
							title: p.title ?? "",
							variant: m.title ?? "",
							image: m.image?.url ?? p.featuredImage?.url
						};
					}
				]
			};
		}
		return {cart: parsed, error: errors.length > 0 ? errors[0].message : null};
	}

	// (storefront.graphql, verbatim)
	public static inline final DOCUMENT = "fragment ProductCard on Product {\n  id\n  handle\n  title\n  featuredImage { url altText }\n  priceRange { minVariantPrice { amount currencyCode } }\n  compareAtPriceRange { minVariantPrice { amount currencyCode } }\n}\n\nfragment CartFields on Cart {\n  id\n  checkoutUrl\n  totalQuantity\n  cost { subtotalAmount { amount currencyCode } }\n  lines(first: 100) {\n    nodes {\n      id\n      quantity\n      cost { totalAmount { amount currencyCode } }\n      merchandise {\n        ... on ProductVariant {\n          id\n          title\n          image { url altText }\n          product { handle title featuredImage { url altText } }\n        }\n      }\n    }\n  }\n}\n\nquery Home {\n  collections(first: 20) {\n    nodes { id handle title image { url altText } }\n  }\n  products(first: 10, sortKey: BEST_SELLING) {\n    nodes { ...ProductCard }\n  }\n}\n\nquery CollectionProducts($handle: String!, $first: Int!, $after: String, $sortKey: ProductCollectionSortKeys!, $reverse: Boolean!) {\n  collection(handle: $handle) {\n    id\n    title\n    description\n    products(first: $first, after: $after, sortKey: $sortKey, reverse: $reverse) {\n      pageInfo { hasNextPage endCursor }\n      nodes { ...ProductCard }\n    }\n  }\n}\n\nquery Search($query: String!, $first: Int!, $after: String) {\n  search(query: $query, first: $first, after: $after, types: PRODUCT) {\n    totalCount\n    pageInfo { hasNextPage endCursor }\n    nodes { ... on Product { ...ProductCard } }\n  }\n}\n\nquery Product($handle: String!) {\n  product(handle: $handle) {\n    id\n    handle\n    title\n    description\n    images(first: 10) { nodes { url altText } }\n    options { name optionValues { name } }\n    variants(first: 100) {\n      nodes {\n        id\n        title\n        availableForSale\n        selectedOptions { name value }\n        price { amount currencyCode }\n        compareAtPrice { amount currencyCode }\n      }\n    }\n  }\n  productRecommendations(productHandle: $handle) { ...ProductCard }\n}\n\nmutation CartCreate($lines: [CartLineInput!]!) {\n  cartCreate(input: { lines: $lines }) {\n    cart { ...CartFields }\n    userErrors { field message }\n  }\n}\n\nmutation CartLinesAdd($cartId: ID!, $lines: [CartLineInput!]!) {\n  cartLinesAdd(cartId: $cartId, lines: $lines) {\n    cart { ...CartFields }\n    userErrors { field message }\n  }\n}\n\nmutation CartLinesUpdate($cartId: ID!, $lines: [CartLineUpdateInput!]!) {\n  cartLinesUpdate(cartId: $cartId, lines: $lines) {\n    cart { ...CartFields }\n    userErrors { field message }\n  }\n}\n";
}

// money in cents ($ and two decimals shown)
abstract Money(Int) {
	inline function new(cents:Int)
		this = cents;

	public static function of(m:Dynamic):Money {
		if (m == null || m.amount == null) return new Money(0);
		var f = Std.parseFloat(Std.string(m.amount));
		return new Money(Math.isNaN(f) ? 0 : Math.round(f * 100));
	}

	@:op(A > B) static function gt(a:Money, b:Money):Bool;

	@:op(A == B) static function eq(a:Money, b:Money):Bool;

	public function toString():String {
		var c = this % 100;
		return "$" + Std.int(this / 100) + "." + (c < 10 ? "0" : "") + c;
	}
}

typedef Collection = {handle:String, title:String, image:Null<String>};
typedef HomeData = {collections:Array<Collection>, bestSellers:Array<Product>};
typedef ProductPage = {products:Array<Product>, hasNext:Bool, cursor:Null<String>, description:Null<String>, total:Null<Int>};
typedef Option = {name:String, values:Array<String>};
typedef Variant = {id:String, title:String, available:Bool, options:Map<String, String>, price:Money, compareAt:Null<Money>};

typedef ProductDetail = {
	handle:String,
	title:String,
	description:String,
	images:Array<String>,
	options:Array<Option>,
	variants:Array<Variant>,
	recommendations:Array<Product>
};

typedef CartLine = {id:String, quantity:Int, total:Money, title:String, variant:String, image:Null<String>};
typedef Cart = {id:String, checkoutUrl:String, totalQuantity:Int, subtotal:Money, lines:Array<CartLine>};
typedef CartResult = {cart:Null<Cart>, error:Null<String>};

// a sort chip's: its label, the identifier's suffix, the API's sortKey and reverse
typedef Sort = {label:String, id:String, key:String, reverse:Bool};

// a product as a card shows it
class Product {
	public final handle:String;
	public final title:String;
	public final image:Null<String>;
	public final price:Money;
	// (only when above the price)
	public final compareAt:Null<Money>;

	function new(handle, title, image, price, compareAt) {
		this.handle = handle;
		this.title = title;
		this.image = image;
		this.price = price;
		this.compareAt = compareAt;
	}

	public static function card(p:Dynamic):Product {
		var price = Money.of(p.priceRange?.minVariantPrice), compare = Money.of(p.compareAtPriceRange?.minVariantPrice);
		return new Product(p.handle, p.title ?? "", p.featuredImage?.url, price, compare > price ? compare : null);
	}
}
