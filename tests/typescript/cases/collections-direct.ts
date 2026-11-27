// Map and Set iterated by their tables and called directly, against node:
// entries deleted, added and cleared while a loop runs, [k, v] and its
// halves, keys(), values() and entries(), a loop left and resumed, a
// subclass's iterator, -0 and NaN keys, size and delete.
const m = new Map<string, number>([['a', 1], ['b', 2], ['c', 3]])
let out = ''
for (const [k, v] of m) {
  out += k + v
  if (k === 'a') m.delete('b')
  if (k === 'c' && !m.has('d')) m.set('d', 4)
}
for (const [k] of m) out += k
for (const [, v] of m) out += v
for (const e of m) out += e.join('=')
for (const k of m.keys()) out += k
for (const v of m.values()) out += v
for (const [k, v] of m.entries()) out += k + v
console.log(out, m.size)
const s = new Set([3, 1, 2])
out = ''
for (const x of s) {
  out += x
  if (x === 3) { s.delete(1); s.add(4) }
}
for (const [a, b] of s.entries()) out += a + '' + b
for (const x of s.keys()) out += x
console.log(out, s.size, s.delete(4), s.delete(4), s.size)
const c = new Map([[1, 'x'], [2, 'y']])
out = ''
for (const [k, v] of c) {
  out += k + v
  c.clear()
}
c.set(3, 'z')
for (const [k, v] of c) {
  out += k + v
  if (k < 5) c.set(k + 1, 'n')
}
console.log(out, [...c])
out = ''
for (const [k, v] of m) { if (v > 2) break; out += k }
for (const [k] of m) { if (k === 'c') continue; out += k }
console.log(out)
class Reversed<K, V> extends Map<K, V> {
  *[Symbol.iterator](): MapIterator<[K, V]> { yield* [...super.entries()].reverse() }
}
const r: Map<string, number> = new Reversed([['x', 1], ['y', 2]])
out = ''
for (const [k, v] of r) out += k + v
for (const [k, v] of r.entries()) out += k + v
console.log(out, r.size, r.delete('x'), r.size)
class Counting extends Set<number> {
  deleted = 0
  delete(x: number) { this.deleted++; return super.delete(x) }
  get size() { return super.size * 100 }
}
const cs: Set<number> = new Counting([1, 2])
console.log(cs.delete(1), cs.delete(5), cs.size, (cs as Counting).deleted)
const z = new Map<number, string>([[-0, 'zero'], [NaN, 'nan']])
console.log(z.get(0), z.has(-0), z.delete(0), z.delete(NaN), z.size, [...z])
const own = new Set<unknown>([1, 2])
;(own as any)[Symbol.iterator] = function* () { yield 'own' }
out = ''
for (const x of own) out += x
console.log(out)
const weak = new WeakMap<object, number>()
const o = {}
weak.set(o, 1)
console.log(weak.delete(o), weak.delete(o))
let thrown = ''
try {
  for (const [k, v] of new Map([[1, 2]])) { thrown += k + v; throw new Error('out') }
} catch (e) { thrown += (e as Error).message }
console.log(thrown)
const grouped = new Map<string, number[]>()
for (const w of ['ab', 'ac', 'bd']) {
  const g = grouped.get(w[0]) ?? []
  g.push(w.length)
  grouped.set(w[0], g)
}
for (const [k, [first, ...more]] of grouped) console.log(k, first, more)
