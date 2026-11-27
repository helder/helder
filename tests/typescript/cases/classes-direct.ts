// Typed classes' members called directly, against node: getters and setters
// by the instance's prototype (inherited, overridden, split across classes,
// overridden by a subclass without a layout), super's methods and getters,
// instanceof of a class with a layout, for-of and patterns binding typed
// values (a match's groups left loose), Math's round, trunc and sign.
const log: string[] = []
abstract class Shape {
  constructor(public name: string) {}
  abstract get area(): number
  get label(): string { return `${this.name}:${this.area.toFixed(2)}` }
  set label(v: string) { log.push('label ' + v); this.name = v }
  describe(prefix: string): string { return prefix + this.label }
}
class Rect extends Shape {
  constructor(public w: number, public h: number) { super('rect') }
  get area(): number { return this.w * this.h }
  get side(): number { log.push('side'); return this.w }
  describe(prefix: string): string { return super.describe('[' + prefix + ']') + ' ' + super.label + (() => super.describe('!'))() }
}
class Square extends Rect {
  constructor(s: number) { super(s, s); this.name = 'square' }
  get area(): number { return super.area + 0.5 }
  set side(v: number) { this.w = this.h = v }
}
class Circle extends Shape {
  constructor(public r: number) { super('circle') }
  get area(): number { return Math.PI * this.r * this.r }
}
const key = 'k'
class Odd extends Rect {
  [key] = 1
  get area(): number { return -1 }
}
const shapes: Shape[] = [new Rect(2, 3), new Square(2), new Circle(1), new Odd(1, 1)]
let total = 0
for (const s of shapes) {
  total += s.area
  log.push(s.label, s.describe('d'))
  if (s instanceof Rect) {
    log.push(String(s.side))
    s.label = 'renamed'
  }
  if (s instanceof Square) {
    s.side = 4
    log.push(String(s.area), String((s as Rect).side))
  }
}
console.log(total.toFixed(3), log.join(' | '))
const fake = Object.create(Rect.prototype)
console.log(fake instanceof Rect, fake instanceof Shape, ({}) instanceof Rect, (null as unknown as object) instanceof Shape, shapes[3] instanceof Rect)
class Any {
  static [Symbol.hasInstance](x: unknown) { return typeof x === 'number' }
}
console.log((1 as unknown) instanceof Any, new Any() instanceof Any)
const inc = new Rect(1, 1)
let calls = 0
const box = {get r() { calls++; return inc }}
box.r.w += 2
box.r.label += '!'
console.log(inc.w, inc.name, calls)

// typed bindings: numbers, strings, classes, their patterns
const pairs: [string, number][] = [['a', 1], ['b', 2]]
let text = ''
for (const [k, v] of pairs) text += k + (v + 1)
for (const {name, w = 7} of [{name: 'x', w: 3}, {name: 'y'} as {name: string, w?: number}]) text += name + w
for (let [i, s] of ([[1, 'one'], [2, 'two']] as [number, string][])) { i *= 2; s += i; text += s }
const re = /(a)|(b)/g
for (const [all, a, b] of 'ab'.matchAll(re)) text += `${all}${a}${b}`
const matches = ['a', 'b'].map(x => /(a)?(b)?/.exec(x)!)
for (const [, a, b] of matches) text += `${a}${b}`
const m = /(x)?(y)/.exec('y')!
const [, gx, gy] = m
text += `${gx}${gy}`
console.log(text)

// arrays destructured by index: holes, defaults, rest, a length that changes, an iterator of its own
const holes = [1, , 3] as number[]
const [h0, h1 = 9, h2, h3 = 4, ...hr] = holes
console.log(h0, h1, h2, h3, hr)
const grow = [1]
const [g0, g1 = (grow.push(2), 5), g2] = grow
console.log(g0, g1, g2, grow)
const own = [1, 2]
;(own as any)[Symbol.iterator] = function* () { yield 9 }
const [o0, o1] = own
let ownLoop = ''
for (const x of own) ownLoop += x
console.log(o0, o1, ownLoop, [...own])
let closes = 0
const iterable = {[Symbol.iterator]() { let i = 0; return {next: () => ({value: i++, done: false}), return: () => { closes++; return {value: 0, done: true} }} }}
const [i0, i1] = iterable as Iterable<number>
console.log(i0, i1, closes)
const [c0, ...cs] = 'héllo'
console.log(c0, cs)

// push directly: a number array, a value array, holes past the end, frozen
const ns = [1, 2]
console.log(ns.push(3), ns.push('x' as any), ns)
const sparse: number[] = []
sparse.length = 3
console.log(sparse.push(1), sparse)
const frozen = Object.freeze([1]) as number[]
try { frozen.push(2) } catch (e) { console.log((e as Error).name) }
class Stack extends Array<number> { push(...xs: number[]) { return super.push(...xs.map(x => x * 10)) } }
const st: number[] = new Stack()
console.log(st.push(1), [...st])

// Math's round, trunc and sign
console.log([0.5, -0.5, 2.5, -2.5, -0, 1e300, -1e-300, NaN, 4503599627370495.5].map(x => [Math.round(x), Math.trunc(x), Math.sign(x)].map(y => Object.is(y, -0) ? '-0' : String(y)).join('/')).join(' '))
