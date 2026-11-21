# In-app purchases

Sell products inside the app: list what the store offers, buy one, and check what the user owns. On iOS and macOS this is StoreKit 2. helder puts its small framework into the app bundle when a program uses purchases, so you don't need Xcode.

```ts
import { Purchases } from "helder/store";

Purchases.onPurchase = p => unlock(p.product);    // renewals, Ask to Buy, other devices

const [pro] = await Purchases.products(["pro"]);  // { title, price: "€4,99", ... }
const r = await Purchases.purchase("pro");
if (r.state === "purchased") {
  unlock("pro");
  await Purchases.finish(r.purchase);             // after delivering it
}
for (const p of await Purchases.owned()) unlock(p.product);
```

```haxe
import helder.store.Purchases;

Purchases.onPurchase = p -> unlock(p.product);

// in a coroutine: no await
var pro = Purchases.products(["pro"])[0];
var r = Purchases.purchase("pro");
if (r.state == Purchased) {
  unlock("pro");
  Purchases.finish(r.purchase);
}
for (p in Purchases.owned()) unlock(p.product);
```

Finish each purchase once you've delivered it, and use `consume` for consumables. The store hands an unfinished purchase back to `onPurchase` the next time the app starts, so set `onPurchase` when the app starts. `restore()` is for a Restore Purchases button.

## Where it works

| | iOS | macOS | Android | Windows | Linux | Web |
|---|---|---|---|---|---|---|
| Purchases | iOS 15+ | macOS 12+, app bundles | Coming | — | — | — |

`Purchases.available()` tells you whether this device can make purchases. Where it can't, every call fails with a short error.

## Real purchases

You set up the products in App Store Connect, with the same ids the app asks for. To test them, sign in with a sandbox account on a device or in the simulator. helder never touches your accounts. Without any products set up, `products()` returns an empty list.

Every purchase carries `verified`, the store's signature checked on the device, and `signed`, the JWS your server can verify itself.

<Reference to="store"/>
