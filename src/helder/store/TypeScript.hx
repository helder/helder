package helder.store;

// helder.store for TypeScript programs (helder.typescript): in-app purchases.
@:typescript("helder/store")
@:typescript.types(helder.store.Purchases.ProductKind, helder.store.Purchases.Product, helder.store.Purchases.Purchase,
	helder.store.Purchases.PurchaseState, helder.store.Purchases.PurchaseResult)
@:typescript.classes(helder.store.Purchases)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
