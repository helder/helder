// App-style collections: Maps by string and by number, Sets of strings and
// numbers, filled, looked up, deleted from and iterated.
let total = 0
for (let r = 0; r < 20; r++) {
  const byKey = new Map<string, number>()
  const byId = new Map<number, string>()
  const seen = new Set<string>()
  const ids = new Set<number>()
  for (let i = 0; i < 20000; i++) {
    const key = 'k' + (i % 5000)
    byKey.set(key, (byKey.get(key) ?? 0) + i)
    byId.set(i, key)
    seen.add(key)
    if (i % 3 === 0) ids.add(i)
  }
  for (let i = 0; i < 20000; i += 2) {
    byId.delete(i)
    if (ids.has(i)) ids.delete(i)
  }
  let s = 0
  for (const [k, v] of byKey) if (seen.has(k)) s += v % 1000
  for (const id of ids) s += id % 7
  for (const v of byId.values()) s += v.length
  total += s + byKey.size + byId.size + seen.size + ids.size
}
console.log(total)
