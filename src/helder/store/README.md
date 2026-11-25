# helder.store

In-app purchases (`helder.store.Purchases`; TypeScript's `helder/store`):
the products the store sells the app, buying one, what the user owns.
StoreKit 2 on iOS 15 and macOS 12 and later; Google Play Billing 9 on
Android; none on Windows, Linux and the web, where `available()` is false
and each call fails with a short error.

```haxe
Purchases.onPurchase = p -> deliver(p);           // set as the app starts
var products = Purchases.products(["pro", "coins"]);
switch Purchases.purchase("pro", {account: userUuid}).state { ... }
for (p in Purchases.owned()) unlock(p.product);   // non-consumables, active subscriptions
Purchases.finish(p);                              // delivered (a consumable: consume)
Purchases.restore();                              // a Restore button's: AppStore.sync()
```

- `Product`: `id`, `kind` (consumable, nonConsumable, subscription,
  nonRenewing), `title`, `description`, `price` (the store's own text),
  `amount`, `currency` (ISO 4217), `period` (a subscription's, ISO 8601:
  `P1M`).
- `PurchaseResult`: `state` purchased (with its `purchase`), pending (Ask
  to Buy, a bank: it comes to `onPurchase` later) or cancelled.
- `Purchase`: `id`, `product`, `date`, `quantity`, `expires`, `revoked`
  (ms since 1970; StoreKit's only), `verified` (the store's signature
  checked on the device), `signed` (the JWS a server verifies; Play's
  purchase token).
- `onPurchase`: purchases outside `purchase()`: renewals, Ask to Buy,
  other devices, refunds, one left unfinished. Those that come before it is
  set are given when it is; StoreKit is listened to from the first use of
  the class, so set it as the app starts.
- `account` (`purchase`'s option): a UUID of the app's for the user,
  StoreKit's `appAccountToken` (Play's `obfuscatedAccountId`).

Real purchases need the products in App Store Connect and a sandbox
account on the device or simulator, which the developer sets up; helder
touches no account. With none, `products` gives an empty list.

## Google Play

`android/AndroidPurchases`: Play Billing 9.1.0 (`com.android.billingclient`),
fetched, shrunk to its keep list and translated into the APK when the
program uses `Purchases` (helder.pack.android's Maven libraries: no
Gradle, SDK or JDK); its manifest brings the `BILLING` permission and the
`<queries>` for the Play Store. One `BillingClient` for the app, made and
connected at the first use (pending purchases on, the library's own
reconnection); the purchases left unacknowledged then go to `onPurchase`,
as StoreKit's updates do. Its listeners are `java.lang.reflect.Proxy`
instances of Glue's `org.hxmc.Handler`, called on billing's thread and
read on the activity's main thread.

- `available()`: the Play Store's billing service is on the device and
  has not answered `BILLING_UNAVAILABLE`. Whether the account can pay is
  known only once connected, so it can be true before the first call and
  false after it.
- `products`: Play asks per type, so in-app and subscription products are
  two queries, merged in the ids' order. Play has no consumable kind: a
  one-time product is `nonConsumable`, and the app decides by calling
  `consume` (consumeAsync: it can be bought again) or `finish`
  (acknowledgePurchase). `title` is the product's name (Play's title adds
  the app's). A subscription is its base plan's offer, else the first
  offer Play lists for the user, priced by its last, recurring phase;
  `purchase` buys that offer.
- `purchase`: launchBillingFlow from the activity; `account` is
  `setObfuscatedAccountId`. USER_CANCELED is cancelled, a PENDING
  purchase pending, ITEM_ALREADY_OWNED the owned purchase; other codes
  throw `purchases: <CODE> (<Play's message>)`.
- `Purchase`: `id` the order id (the token when there is none: a pending
  purchase), `product` the first product id (Play's flow buys one; a
  consumable's `quantity` can be more), `date` the purchase time, `signed`
  the purchase token. Play gives no expiry or revocation on the device.
- `verified`: Play's signature (SHA1withRSA of the purchase's JSON)
  checked against the app's license key, Play Console's Monetization
  setup's base64 key, given as `"helder": {"android": {"licenseKey":
  "MIIB..."}}` or `-D helder.play.license-key=...`. Without one it is
  false. A server checks the token with the Play Developer API either way;
  that is the check to trust.
- `finish` acknowledges (Play refunds a purchase left unacknowledged for
  three days); `restore` asks for the purchases again and gives those not
  yet acknowledged to `onPurchase`.

To test real purchases: the products in Play Console with the same ids,
the app on a testing track, and a license tester's account signed in on
the device. Verified (CI's android job, `tests/pack/billing.sh`): the
library's classes through dex2oat's verifier, a connection to an emulator
without the Play Store (BILLING_UNAVAILABLE: a short error, `available()`
false), the library's ProductDetails and Purchase made from fixture JSON
read through the same calls; the mapping and the signature check are
`Purchases.test.hx`'s, with a key made for the test.

## The framework

hxmc links no Swift, and StoreKit 2 is Swift only, so the StoreKit calls are
a small library of their own: `apple/StoreShim.swift`, plain C functions
(`@_cdecl`) answering through a block with JSON, built by
`apple/build.sh` (Xcode) for ios-arm64, ios-sim-arm64 and macos (arm64 and
x86_64), `-Osize`, iOS 15 and macOS 12 at least, Swift's back-deployment
libraries linked in, the same bytes from the same Xcode. The binaries are
committed (users need no Xcode), with `apple/StoreShim.sha256`, the
source's hash: `Purchases.test.hx` fails when the source changed without
a build. The system's dyld binds the Swift runtime (the OS's, since iOS
12.2 and macOS 10.14.4).

A program that uses `Purchases` gets it in its bundle by use
(`@:helder.apple.framework("HelderStore")`, helder.pack.apple.Frameworks):
iOS's `Frameworks/HelderStore.framework` (the App Store takes no loose
library), macOS's `Contents/Frameworks/HelderStore.dylib`, signed by
helder's own signer as the app is (ad hoc, or the app's identity) and
sealed in the app's CodeResources. `ApplePurchases` opens it with
`dlopen` (`@executable_path`) when the class is first used, and starts
listening to `Transaction.updates` then. Its answers come on StoreKit's
threads (hxmc's blocks attach them) and resume the caller's coroutine on
its loop. In-App Purchase needs no entitlement, only an explicit App ID
(not a wildcard's), where App Store Connect enables it by default; the
com.apple.developer.storekit key Xcode's capability writes is none Apple
supports, and helder adds nothing.
