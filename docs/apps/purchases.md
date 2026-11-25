# In-app purchases

Sell products inside the app: list what the store offers, buy one, and check what the user owns. On iOS and macOS this is StoreKit 2, on Android Google Play Billing. helder puts what each needs into the app when a program uses purchases, so you don't need Xcode, Gradle or the Android SDK.

<Terminal command="Example purchase flow" src="purchase-flow.txt"/>

```ts
import {Purchases} from 'helder/store'

Purchases.onPurchase = p => unlock(p.product)    // renewals, Ask to Buy, other devices

const [pro] = await Purchases.products(['pro'])  // {title, price: "€4,99", ...}
const r = await Purchases.purchase('pro')
if (r.state === 'purchased') {
  unlock('pro')
  await Purchases.finish(r.purchase)             // after delivering it
}
for (const p of await Purchases.owned()) unlock(p.product)
```

```haxe
import helder.store.Purchases;

Purchases.onPurchase = p -> unlock(p.product);

// in a coroutine: no await
var pro = Purchases.products(['pro'])[0];
var r = Purchases.purchase('pro');
if (r.state == Purchased) {
  unlock('pro');
  Purchases.finish(r.purchase);
}
for (p in Purchases.owned()) unlock(p.product);
```

Finish each purchase once you've delivered it, and use `consume` for consumables. The store hands an unfinished purchase back to `onPurchase` the next time the app starts, so set `onPurchase` when the app starts. `restore()` is for a Restore Purchases button.

## Where it works

| | iOS | macOS | Android | Windows | Linux | Web |
|---|---|---|---|---|---|---|
| Purchases | iOS 15+ | macOS 12+, app bundles | Play Billing 9 | — | — | — |

`Purchases.available()` tells you whether this device can make purchases. Where it can't, every call fails with a short error. On Android it can only say whether the Play Store is there until the first call connects: it turns false when Play answers that billing is unavailable.

## What else

- **Products:** set up the same ids in App Store Connect or Play Console as the ones your app asks for. Until then, `products()` returns an empty list.
- **Testing:** use an Apple sandbox account on a device or simulator, or add a license tester in Play Console and put the app on a testing track.
- **Consumables:** Play reports one-time products as `nonConsumable`. Call `consume` to let the user buy one again. Finish or consume within three days to avoid a refund.
- **Verification:** `verified` is the device's signature check. Use `signed` on your server to check the Apple JWS or the Play purchase token.

On Android the device's check needs the license key from Play Console's Monetization setup:

```json
{
  "targets": {"android": {"licenseKey": "MIIBIjANBgkq..."}}
}
```

Without it `verified` is false. Either way, a server checking the token with the Play Developer API is the check to trust.

<Reference to="store"/>
