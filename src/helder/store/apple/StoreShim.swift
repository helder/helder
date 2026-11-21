// StoreKit 2 behind C functions, for helder.store.Purchases (hxmc links no
// Swift: this is a framework of its own, opened with dlopen). Each answers
// through a block (code, text) on whichever thread StoreKit finishes on:
// 0 and JSON, 1 and an error's message, 2 pending, 3 cancelled. The text
// is only valid during the call.
import Foundation
import StoreKit

public typealias Reply = @convention(block) (Int32, UnsafePointer<CChar>?) -> Void

struct Out: @unchecked Sendable {
  let reply: Reply
  func send(_ code: Int32, _ s: String = "") { s.withCString { reply(code, $0) } }
  func json(_ v: Any) {
    let d = (try? JSONSerialization.data(withJSONObject: v)) ?? Data("null".utf8)
    send(0, String(decoding: d, as: UTF8.self))
  }
  func fail(_ e: Error) { send(1, e.localizedDescription) }
}

// (the transactions handed out, so finish needs only an id)
let lock = NSLock()
var seen: [UInt64: Transaction] = [:]
func remember(_ t: Transaction) { lock.lock(); seen[t.id] = t; lock.unlock() }
func cached(_ id: UInt64) -> Transaction? { lock.lock(); defer { lock.unlock() }; return seen[id] }

func ms(_ d: Date?) -> Any { d.map { $0.timeIntervalSince1970 * 1000 } ?? NSNull() }

func kind(_ t: Product.ProductType) -> String {
  switch t {
    case .consumable: "consumable"
    case .nonConsumable: "nonConsumable"
    case .autoRenewable: "subscription"
    default: "nonRenewing"
  }
}

// (ISO 8601, as Play's billing periods: P1M)
func period(_ p: Product.SubscriptionPeriod) -> String {
  switch p.unit {
    case .day: "P\(p.value)D"
    case .week: "P\(p.value)W"
    case .month: "P\(p.value)M"
    default: "P\(p.value)Y"
  }
}

func product(_ p: Product) -> [String: Any] {
  var o: [String: Any] = [
    "id": p.id, "kind": kind(p.type), "title": p.displayName, "description": p.description,
    "price": p.displayPrice, "amount": NSDecimalNumber(decimal: p.price).doubleValue,
    "currency": p.priceFormatStyle.currencyCode,
  ]
  if let s = p.subscription { o["period"] = period(s.subscriptionPeriod) }
  return o
}

func entry(_ v: VerificationResult<Transaction>) -> [String: Any] {
  let t = v.unsafePayloadValue
  remember(t)
  let ok = if case .verified = v { true } else { false }
  return [
    "id": String(t.id), "product": t.productID, "date": ms(t.purchaseDate),
    "quantity": t.purchasedQuantity, "expires": ms(t.expirationDate),
    "revoked": ms(t.revocationDate), "verified": ok, "signed": v.jwsRepresentation,
  ]
}

@_cdecl("hsk_products")
public func hsk_products(_ ids: UnsafePointer<CChar>, _ reply: @escaping Reply) {
  let out = Out(reply: reply), list = String(cString: ids).split(separator: "\n").map(String.init)
  Task {
    do { out.json(try await Product.products(for: list).map(product)) } catch { out.fail(error) }
  }
}

@_cdecl("hsk_purchase")
public func hsk_purchase(_ id: UnsafePointer<CChar>, _ account: UnsafePointer<CChar>, _ reply: @escaping Reply) {
  let out = Out(reply: reply), pid = String(cString: id), token = String(cString: account)
  Task {
    do {
      var options: Set<Product.PurchaseOption> = []
      if !token.isEmpty {
        guard let u = UUID(uuidString: token) else { return out.send(1, "account: not a UUID") }
        options.insert(.appAccountToken(u))
      }
      guard let p = try await Product.products(for: [pid]).first else { return out.send(1, "no product \(pid)") }
      switch try await p.purchase(options: options) {
        case .success(let v): out.json(entry(v))
        case .pending: out.send(2)
        case .userCancelled: out.send(3)
        @unknown default: out.send(1, "unknown result")
      }
    } catch {
      out.fail(error)
    }
  }
}

@_cdecl("hsk_owned")
public func hsk_owned(_ reply: @escaping Reply) {
  let out = Out(reply: reply)
  Task {
    var all: [[String: Any]] = []
    for await v in Transaction.currentEntitlements { all.append(entry(v)) }
    out.json(all)
  }
}

// (once per transaction that arrives outside a purchase: renewals, Ask to
// Buy, other devices, refunds; for the app's whole run)
@_cdecl("hsk_updates")
public func hsk_updates(_ reply: @escaping Reply) {
  let out = Out(reply: reply)
  Task.detached { for await v in Transaction.updates { out.json(entry(v)) } }
}

// (one finished already, or never seen: nothing to do)
@_cdecl("hsk_finish")
public func hsk_finish(_ id: UnsafePointer<CChar>, _ reply: @escaping Reply) {
  let out = Out(reply: reply), key = UInt64(String(cString: id)) ?? 0
  Task {
    var t = cached(key)
    if t == nil {
      for await v in Transaction.unfinished where v.unsafePayloadValue.id == key {
        t = v.unsafePayloadValue
        break
      }
    }
    await t?.finish()
    out.send(0)
  }
}

@_cdecl("hsk_sync")
public func hsk_sync(_ reply: @escaping Reply) {
  let out = Out(reply: reply)
  Task {
    do { try await AppStore.sync(); out.send(0) } catch { out.fail(error) }
  }
}
