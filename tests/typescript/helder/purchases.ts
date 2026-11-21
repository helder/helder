// helder/store where there is no store (Linux, wasm32-wasi): none
// available, a call's promise rejected with its short error; a result's
// union narrowed by its state.
import { Purchases, type Purchase, type PurchaseResult } from "helder/store";

function label(r: PurchaseResult): string {
	return r.state === "purchased" ? "bought " + r.purchase.product : r.state;
}

const bought: Purchase = { id: "1", product: "pro", date: 0, quantity: 1, verified: true, signed: "" };
Purchases.onPurchase = p => console.log("update", p.product);
console.log(Purchases.available());
console.log(label({ state: "pending" }), label({ state: "purchased", purchase: bought }));

async function main() {
	try {
		const products = await Purchases.products(["pro"]);
		console.log(products.length);
	} catch (e) {
		console.log(String(e));
	}
}
main();
