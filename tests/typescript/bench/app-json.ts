// App-style JSON: nested records (objects, arrays, numbers with fractions,
// strings with escapes, booleans, null) stringified, parsed back, walked and
// stringified again indented.
type Item = {sku: string, qty: number, price: number}
type Order = {id: number, items: Item[], paid: boolean, note: string | null}
type User = {id: number, name: string, email: string, address: {street: string, city: string, zip: string}, orders: Order[]}
function users(n: number): User[] {
  const out: User[] = []
  for (let i = 0; i < n; i++) {
    const orders: Order[] = []
    for (let j = 0; j < 4; j++) {
      const items: Item[] = []
      for (let k = 0; k < 3; k++) items.push({sku: `SKU-${i}-${j}-${k}`, qty: (i + j + k) % 5 + 1, price: ((i * 13 + k * 7) % 1000) / 100})
      orders.push({id: i * 10 + j, items, paid: (i + j) % 2 === 0, note: j === 1 ? 'leave at "door"\n' : null})
    }
    out.push({id: i, name: 'User ' + i, email: `user${i}@example.com`, address: {street: i + ' Main St', city: 'Town ' + (i % 50), zip: String(10000 + i)}, orders})
  }
  return out
}
let total = 0, sum = 0
for (let r = 0; r < 10; r++) {
  const text = JSON.stringify(users(1000))
  const back = JSON.parse(text) as User[]
  for (const u of back) for (const o of u.orders) for (const it of o.items) sum += it.qty * it.price
  total += text.length + JSON.stringify(back.slice(0, 50), null, 2).length
}
console.log(total, sum.toFixed(2))
