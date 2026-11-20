// helder.ui's Router and Stack from TypeScript: a route's params typed by
// its path (p.id a string, no annotation), go, back, replace, the query,
// the fallback, open's deep link; the screens kept below the top.
import { flush, Render } from "helder/view";
import { Clock, Router, Stack } from "helder/ui";
import { UiProbe } from "./ui-probe";

function Product(props: { id: string }) {
	return <view tag={"product-" + props.id}><text>{"Product " + props.id}</text></view>;
}

const nav = new Router()
	.route("/", _ => <view tag="home"><text>Home</text></view>)
	.route("/product/:id", p => <Product id={p.id}/>)
	.route("/shop/:shop/item/:item", p => {
		// @ts-expect-error: p has the path's params only, so p is not any
		p.id;
		return <text>{p.shop + "/" + p.item}</text>;
	})
	.fallback(path => <text>{"Missing " + path}</text>);

function step(what: string) {
	flush();
	Clock.finish();
	console.log("-- " + what + ": " + nav.path() + " (" + nav.depth() + ")");
	console.log(UiProbe.dump());
}

const root = UiProbe.root(320, 240);
Render.render(<Stack router={nav} transition="slide"/>, root);
step("start");
nav.go("/product/3?tab=specs");
step("go");
console.log("tab", nav.query().tab);
nav.go("/shop/a/item/b");
step("go");
nav.replace("/nowhere");
step("replace");
console.log("back", nav.back(), nav.back(), nav.back());
step("back");
nav.open("myapp://host/product/7");
step("open");
