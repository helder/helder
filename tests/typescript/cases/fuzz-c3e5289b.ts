// fuzz (seed 1, program 1): an iterator left before its end is closed (its
// return called, a generator's finally run): by an array pattern that took
// what it needed, by a for-of's break, return, throw or continue to an outer
// loop; not after a throw from its own next, and a throw in the body stands
// over one from return
function* gen(n: number): Generator<number, string, undefined> {
  try {
    for (let i = 0; i < n; i++) yield i
  } finally {
    console.log('cleanup', n)
  }
  return 'done'
}
const [x = -1, y = -2] = gen(5)
console.log(x, y)
const [z] = gen(4)
let q = 0, w = 0
;[q, w] = gen(6)
console.log(z, q, w, [...gen(0)])
const [a, ...rest] = gen(3)
console.log(a, rest)
for (const v of gen(3)) if (v > 0) break
function first(): number {
  for (const v of gen(2)) return v
  return -1
}
console.log(first())
try {
  for (const v of gen(4)) if (v === 2) throw new Error('boom')
} catch (e) {
  console.log(String(e))
}
outer: for (let k = 0; k < 2; k++) for (const v of gen(2)) if (v === 0) continue outer
const custom: Iterable<number> = {[Symbol.iterator]() {
  let i = 0
  return {next: () => ({value: i++, done: i > 5}), return: () => {
    console.log('custom return')
    return {value: undefined, done: true}
  }}
}}
for (const v of custom) if (v > 1) break
const [c0, c1] = custom
console.log(c0, c1)
const bad: Iterable<number> = {[Symbol.iterator]() {
  return {next: () => ({value: 1, done: false}), return: () => 5 as unknown as IteratorResult<number>}
}}
try {
  for (const v of bad) break
} catch (e) {
  console.log('not an object', e instanceof TypeError)
}
try {
  for (const v of bad) throw new Error('first')
} catch (e) {
  console.log('kept', String(e))
}
const broken: Iterable<number> = {[Symbol.iterator]() {
  return {next: (): IteratorResult<number> => { throw new Error('next') }, return: () => {
    console.log('never')
    return {value: undefined, done: true}
  }}
}}
try {
  for (const v of broken) console.log(v)
} catch (e) {
  console.log(String(e))
}
function* inner(): Generator<number, void, undefined> {
  try {
    for (const v of gen(3)) yield v * 10
  } finally {
    console.log('inner closed')
  }
}
for (const v of inner()) if (v === 10) break
