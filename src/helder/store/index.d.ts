// helder.store for TypeScript programs (helder.typescript): in-app purchases.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {Purchases: "helder.store.Purchases", __module: "helder.store.TypeScript"};

export type ProductKind = "consumable" | "nonConsumable" | "subscription" | "nonRenewing";

// price: the store's own text ("€4,99"); amount: its number; currency: its
// ISO 4217 code; period: a subscription's, ISO 8601 ("P1M")
export type Product = { id: string; kind: ProductKind; title: string; description: string; price: string; amount: number; currency: string; period?: string };

// A purchase the store has made: StoreKit's transaction, Play's purchase.
// Times in ms since 1970; verified: the store's signature checked on the
// device (StoreKit's JWS); signed: what a server verifies (the JWS; Play's
// purchase token)
export type Purchase = { id: string; product: string; date: number; quantity: number; expires?: number; revoked?: number; verified: boolean; signed: string };

export type PurchaseState = "purchased" | "pending" | "cancelled";

// pending: waiting on someone else (Ask to Buy, a bank), onPurchase gets it later
export type PurchaseResult = {state: "purchased"; purchase: Purchase} | {state: "pending"} | {state: "cancelled"};

// In-app purchases: the products the store sells the app, buying one, the
// purchases the user owns. StoreKit 2 on iOS 15 and macOS 12 and later (a
// framework of helder's, put into the app bundle when the program uses
// this class); elsewhere none is available and each call fails. Deliver
// what was bought, then finish it (consume a consumable): an unfinished
// purchase is given again, to onPurchase, at the next launch.
//
//   for (p in Purchases.owned()) unlock(p.product);
//   var r = Purchases.purchase("pro");
//   if (r.state == Purchased) { unlock("pro"); Purchases.finish(r.purchase); }
export declare class Purchases {
	// purchases made outside purchase(): renewals, Ask to Buy, other
	// devices, refunds, one left unfinished; those that came before it was
	// set given when it is. Set it as the app starts: StoreKit is listened
	// to from the first use of this class, and Apple asks for the launch
	static onPurchase: ((arg0: Purchase) => void) | null;
	static available(): boolean;
	static products(ids: string[]): Promise<Product[]>;
	// account: who buys, a UUID of the app's (StoreKit's appAccountToken, Play's obfuscatedAccountId)
	static purchase(id: string, options?: { account?: string }): Promise<{state: "purchased"; purchase: Purchase} | {state: "pending"} | {state: "cancelled"}>;
	// what the user owns now: non-consumables, active subscriptions
	static owned(): Promise<Purchase[]>;
	// after delivering it (Play: acknowledged)
	static finish(p: Purchase): Promise<unknown>;
	// a consumable's, after delivering it: it can be bought again (StoreKit: finished; Play: consumed)
	static consume(p: Purchase): Promise<unknown>;
	// the user's purchases fetched again from the store (StoreKit asks them
	// to sign in): a Restore button's; owned() after it
	static restore(): Promise<unknown>;
}
