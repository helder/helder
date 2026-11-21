# helder.store

In-app purchases (`helder.store.Purchases`; TypeScript's `helder/store`):
the products the store sells the app, buying one, what the user owns.
StoreKit 2 on iOS 15 and macOS 12 and later; Google Play Billing on
Android comes later (`available()` is false there for now); none on
Windows, Linux and the web, where `available()` is false and each call
fails with a short error.

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
  (ms since 1970), `verified` (StoreKit's signature checked on the
  device), `signed` (the JWS a server verifies; Play's purchase token).
- `onPurchase`: purchases outside `purchase()`: renewals, Ask to Buy,
  other devices, refunds, one left unfinished. Those that come before it is
  set are given when it is; StoreKit is listened to from the first use of
  the class, so set it as the app starts.
- `account` (`purchase`'s option): a UUID of the app's for the user,
  StoreKit's `appAccountToken` (Play's `obfuscatedAccountId`).

Real purchases need the products in App Store Connect and a sandbox
account on the device or simulator, which the developer sets up; helder
touches no account. With none, `products` gives an empty list.

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
sealed in the app's CodeResources. `PurchasesApple` opens it with
`dlopen` (`@executable_path`) when the class is first used, and starts
listening to `Transaction.updates` then. Its answers come on StoreKit's
threads (hxmc's blocks attach them) and resume the caller's coroutine on
its loop. In-App Purchase needs no entitlement, only an explicit App ID
(not a wildcard's), where App Store Connect enables it by default; the
com.apple.developer.storekit key Xcode's capability writes is none Apple
supports, and helder adds nothing.
