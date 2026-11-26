import {e, s, block, lit} from './Program.mjs'

// Random programs that type-check under helder's config by construction:
// the generator knows the type of everything in scope, and draws only what
// TypeScript's types describe (an index read only in bounds, a hole never
// read into a typed slot). Weighted towards what helder represents
// specially (src/helder/typescript/README.md, "Strict"): numbers in typed
// slots, loop counters, number arrays, classes with layouts, captured
// bindings, strings built in loops, branded numbers and generics.

const N = e('number'), Str = e('string'), B = e('boolean')
const Nums = e('number[]'), Strs = e('string[]'), M = e('M')

const EDGES = ['0', '-0', '1', '-1', '2', '3', '7', '10', '0.5', '-0.5', '1.5',
  '2.5', '-2.5', '0.1', '0.2', '1e21', '1e-7', '123.456', 'NaN', 'Infinity',
  '-Infinity', '2147483647', '2147483648', '-2147483648', '-2147483649',
  '4294967295', '4294967296', '9007199254740991', '9007199254740992',
  '-9007199254740991', '2 ** 31', '2 ** 32', '2 ** 53', '-(2 ** 31)',
  'Number.MAX_VALUE', 'Number.MIN_VALUE', 'Number.EPSILON', '5e-324',
  '0.30000000000000004', '255', '256', '65535', '65536', '1e300', '-1e-300',
  '100', '1000000007', '0.1 + 0.2', '-7', '1e16', '123456789012']

const STRINGS = ['', 'a', 'abc', 'héllo', '😀x', 'é', '  pad ', '12', '-0',
  '0x1f', '1e3', 'NaN', 'Infinity', 'a,b,,c', 'İstanbul', 'straße', 'ΑΣ',
  'ﬀ', 'x\ud83d', 'é', 'A-b_C', ' 42 ', 'abcabc', '\t\n', '0.5', '-12.5e-1',
  '7', 'Zz', '2024-02-29', 'aaa', 'b', '\u0000', 'ǅ', '1_000', '0b11', '0o7']

const RADIX = [2, 8, 10, 16, 36, 3, 7]

export class Generator {
  constructor(random, options = {}) {
    this.r = random
    this.lies = options.lies ?? false
    // (what helder is known to get wrong, drawn only when asked: README.md's list)
    this.known = options.known ?? false
  }

  // a case: top-level declarations and a body
  case(id) {
    const r = this.r
    const c = this.c = {id, async: r.chance(0.12), top: [], body: [],
      features: new Set(), names: 0, fns: [], classes: [], gens: []}
    const sc = new Scope(null, {async: c.async})
    const family = r.weighted(FAMILIES.map(f => [f.weight, f]))
    c.family = family.name
    const stmts = []
    for (const st of family.run(this, sc)) stmts.push(st)
    for (let n = r.range(1, 4); n > 0; n--) stmts.push(...this.stmt(sc))
    if (c.async && r.chance(0.6)) stmts.push(...this.asyncOrder(sc))
    // (a sync case's: after a TSHX100 an async one's scheduled work still prints)
    if (this.lies && !c.async) {
      const at = r.int(stmts.length + 1)
      // (of no binding in scope: it goes anywhere in the body)
      stmts.splice(at, 0, ...this.lie(new Scope(null, {async: c.async})))
    }
    c.body = stmts
    return c
  }

  name(prefix = 'v') {
    return `${prefix}${++this.c.names}`
  }

  // a top-level name: §, the case's prefix
  top(prefix) {
    return `§${prefix}${++this.c.names}`
  }

  feature(f) {
    this.c.features.add(f)
  }

  numLit() {
    const r = this.r
    if (r.chance(0.45)) {
      const edge = r.pick(EDGES)
      return lit('number', edge.includes(' ') ? `(${edge})` : edge)
    }
    if (r.chance(0.5)) return lit('number', r.range(-5, 20))
    return lit('number', (r.range(-1000, 1000) / r.pick([1, 2, 4, 10, 100, 3])).toString())
  }

  strLit() {
    const r = this.r
    return lit('string', JSON.stringify(r.chance(0.8) ? r.pick(STRINGS) : r.pick(STRINGS) + r.pick(STRINGS)))
  }

  smallInt(lo = 0, hi = 5) {
    return lit('number', this.r.range(lo, hi))
  }

  // a non-negative integer, an index: a literal, a counter
  index(sc) {
    const vars = sc.of('number', v => v.index)
    if (vars.length && this.r.chance(0.7)) return N`${this.r.pick(vars).name}`
    return this.smallInt(0, 4)
  }

  expr(t, sc, d = 0) {
    switch (t) {
      case 'number': return this.num(sc, d)
      case 'string': return this.str(sc, d)
      case 'boolean': return this.bool(sc, d)
      case 'number[]': return this.nums(sc, d)
      case 'string[]': return this.strs(sc, d)
      case 'M': return this.brand(sc, d)
    }
    throw new Error(`no expression of ${t}`)
  }

  // an expression of any type, to print
  any(sc, d = 0) {
    const r = this.r
    const t = r.weighted([[6, 'number'], [3, 'string'], [2, 'boolean'], [2, 'number[]'], [1, 'string[]']])
    const vars = sc.all().filter(v => !v.hidden)
    if (vars.length && r.chance(0.3)) return e('unknown')`${r.pick(vars).name}`
    return this.expr(t, sc, d)
  }

  num(sc, d = 0) {
    const r = this.r
    const vars = sc.of('number')
    if (d > 3 || r.chance(0.15 + d * 0.2))
      return vars.length && r.chance(0.6) ? N`${r.pick(vars).name}` : this.numLit()
    const a = () => this.num(sc, d + 1)
    return r.weighted([
      [6, () => N`(${a()} ${r.pick(['+', '-', '*', '/', '%', '%', '+', '-'])} ${a()})`],
      [3, () => N`(${a()} ${r.pick(['|', '&', '^', '<<', '>>', '>>>'])} ${a()})`],
      [1, () => N`(~${a()})`],
      [1, () => N`(-(${a()}))`],
      [1, () => N`((${lit('number', r.range(-6, 10))}) ** ${this.smallInt(0, 6)})`],
      [4, () => this.math(sc, d)],
      [4, () => this.fromStr(sc, d)],
      [4, () => this.fromArr(sc, d)],
      [2, () => this.ternary(N, sc, d, a)],
      [vars.length ? 4 : 0, () => N`${r.pick(vars).name}`],
      [this.c.fns.length ? 3 : 0, () => this.callFn(sc, d)],
      [sc.of('inst').length ? 4 : 0, () => this.instNum(sc, d)],
      // (made a number: a branded one's type would follow it into a callback's result)
      [sc.of('M').length ? 2 : 0, () => N`(${r.pick(sc.of('M')).name} + 0)`],
      [sc.of('fn').length ? 2 : 0, () => N`${r.pick(sc.of('fn')).name}(${a()})`],
      [1, () => N`Number(${this.bool(sc, d + 1)})`],
      [1, () => this.numLit()]
    ])()
  }

  math(sc, d) {
    const r = this.r, a = () => this.num(sc, d + 1)
    return r.weighted([
      [5, () => N`Math.${r.pick(['floor', 'ceil', 'round', 'trunc', 'sign', 'abs', 'sqrt', 'fround', 'clz32'])}(${a()})`],
      [3, () => N`Math.${r.pick(['min', 'max'])}(${a()}, ${a()})`],
      [1, () => N`Math.${r.pick(['min', 'max'])}(${a()}, ${a()}, ${a()})`],
      [1, () => N`Math.${r.pick(['min', 'max'])}()`],
      [1, () => N`Math.imul(${a()}, ${a()})`],
      [1, () => N`Math.round(${a()} * 100) / 100`]
    ])()
  }

  fromStr(sc, d) {
    const r = this.r, x = () => this.str(sc, d + 1)
    return r.weighted([
      [3, () => N`${x()}.length`],
      [4, () => N`${x()}.charCodeAt(${r.chance(0.6) ? this.index(sc) : this.num(sc, d + 1)})`],
      [1, () => N`(${x()}.codePointAt(${this.index(sc)}) ?? -1)`],
      [2, () => N`${x()}.${r.pick(['indexOf', 'lastIndexOf'])}(${x()})`],
      [2, () => N`Number(${x()})`],
      [1, () => N`(+${x()})`],
      // (not 36: past 20 digits a radix other than a power of two's may be approximated)
      [2, () => N`parseInt(${x()}${r.chance(0.4) ? `, ${r.pick([2, 10, 16, 0, 8])}` : ''})`],
      [1, () => N`parseFloat(${x()})`],
      [1, () => N`${x()}.search(${x()})`]
    ])()
  }

  fromArr(sc, d) {
    const r = this.r, a = () => this.nums(sc, d + 1), n = () => this.num(sc, d + 1)
    const arrays = sc.of('number[]')
    return r.weighted([
      [3, () => N`${a()}.length`],
      [2, () => N`${a()}.${r.pick(['indexOf', 'lastIndexOf'])}(${n()})`],
      [3, () => N`(${a()}.at(${r.chance(0.5) ? this.index(sc) : n()}) ?? ${n()})`],
      [arrays.length ? 4 : 0, () => {
        const v = r.pick(arrays).name, i = this.index(sc)
        return N`(${i} < ${v}.length ? ${v}[${i}] : ${n()})`
      }],
      [2, () => N`${a()}.reduce((x, y) => ${this.numWith(sc, d, ['x', 'y'])}, ${n()})`],
      [1, () => N`${a()}.findIndex(x => ${this.boolWith(sc, d, ['x'])})`],
      [1, () => N`(${a()}.find(x => ${this.boolWith(sc, d, ['x'])}) ?? -1)`],
      [1, () => N`Math.${r.pick(['max', 'min'])}(...${a()})`],
      [1, () => N`Number(${a()}.includes(${n()}))`]
    ])()
  }

  // a number expression of the given number names (a callback's parameters)
  numWith(sc, d, names) {
    const inner = new Scope(sc)
    for (const n of names) inner.add({name: n, t: 'number'})
    return this.num(inner, Math.max(d + 1, 2))
  }

  boolWith(sc, d, names, t = 'number') {
    const inner = new Scope(sc)
    for (const n of names) inner.add({name: n, t})
    return this.bool(inner, Math.max(d + 1, 2))
  }

  str(sc, d = 0) {
    const r = this.r
    const vars = sc.of('string')
    if (d > 3 || r.chance(0.2 + d * 0.2))
      return vars.length && r.chance(0.5) ? Str`${r.pick(vars).name}` : this.strLit()
    const x = () => this.str(sc, d + 1), n = () => this.num(sc, d + 1), i = () => this.index(sc)
    return r.weighted([
      [4, () => Str`(${x()} + ${r.chance(0.5) ? x() : n()})`],
      [3, () => Str`\`\${${x()}}:\${${n()}}|\${${x()}}\``],
      [3, () => Str`String(${n()})`],
      [2, () => Str`(${n()}).toString()`],
      [2, () => Str`(${n()} | 0).toString(${r.pick(RADIX)})`],
      [1, () => Str`(${n()} >>> 0).toString(16)`],
      [2, () => Str`(${n()}).toFixed(${this.smallInt(0, 6)})`],
      [2, () => Str`(${n()}).toPrecision(${this.smallInt(1, 12)})`],
      [1, () => Str`(${n()}).toExponential(${this.smallInt(0, 8)})`],
      [3, () => Str`${x()}.${r.pick(['slice', 'substring', 'substr'])}(${r.chance(0.5) ? i() : n()}${r.chance(0.5) ? `` : ''}, ${r.chance(0.5) ? i() : n()})`],
      [1, () => Str`${x()}.slice(${lit('number', r.range(-4, 3))})`],
      [2, () => Str`${x()}.${r.pick(['padStart', 'padEnd'])}(${this.smallInt(0, 12)}, ${x()})`],
      [1, () => Str`${x()}.repeat(${this.smallInt(0, 3)})`],
      [2, () => Str`${x()}.${r.pick(['trim', 'trimStart', 'trimEnd', ...this.known ? ['toUpperCase', 'toLowerCase'] : []])}()`],
      [1, () => Str`(${x()}.at(${lit('number', r.range(-3, 3))}) ?? '?')`],
      [1, () => Str`${x()}.charAt(${r.chance(0.5) ? i() : n()})`],
      [2, () => Str`${x()}.${r.pick(['replace', 'replaceAll'])}(${x()}, ${x()})`],
      [2, () => Str`${x()}.split(${x()}).join(${x()})`],
      [1, () => Str`${x()}.normalize(${JSON.stringify(r.pick(['NFC', 'NFD', 'NFKC', 'NFKD']))})`],
      [1, () => Str`String.fromCharCode(${n()} & 65535)`],
      [1, () => Str`String.fromCodePoint((${n()} >>> 0) % 1114112)`],
      [2, () => Str`${this.nums(sc, d + 1)}.join(${x()})`],
      [1, () => Str`${this.strs(sc, d + 1)}.join(${x()})`],
      [1, () => Str`String(${this.bool(sc, d + 1)})`],
      [1, () => Str`JSON.stringify(${this.any(sc, d + 1)})`],
      [1, () => this.ternary(Str, sc, d, x)],
      [1, () => Str`${x()}.split('').reverse().join('')`],
      [1, () => Str`[...${x()}].join(',')`],
      [vars.length ? 3 : 0, () => Str`${r.pick(vars).name}`],
      [sc.of('S').length ? 1 : 0, () => Str`${r.pick(sc.of('S')).name}`],
      [sc.of('inst').length ? 2 : 0, () => this.instStr(sc, d)]
    ])()
  }

  bool(sc, d = 0) {
    const r = this.r
    const vars = sc.of('boolean')
    if (d > 3 || r.chance(0.1 + d * 0.15))
      return vars.length && r.chance(0.5) ? B`${r.pick(vars).name}` : lit('boolean', r.pick(['true', 'false']))
    const n = () => this.num(sc, d + 1), x = () => this.str(sc, d + 1), b = () => this.bool(sc, d + 1)
    return r.weighted([
      [6, () => this.compare(n, r.pick(['<', '<=', '>', '>=', '===', '!==', '==', '!=']))],
      [2, () => this.compare(x, r.pick(['<', '===', '!==', '>=']))],
      [2, () => B`(!${b()})`],
      [3, () => B`(${b()} ${r.pick(['&&', '||'])} ${b()})`],
      [2, () => B`Number.${r.pick(['isInteger', 'isSafeInteger', 'isNaN', 'isFinite'])}(${n()})`],
      [1, () => B`${r.pick(['isNaN', 'isFinite'])}(${n()})`],
      [3, () => B`Object.is(${n()}, ${n()})`],
      [2, () => B`${x()}.${r.pick(['includes', 'startsWith', 'endsWith'])}(${x()})`],
      [2, () => B`${this.nums(sc, d + 1)}.includes(${n()})`],
      [1, () => B`${this.nums(sc, d + 1)}.${r.pick(['some', 'every'])}(x => ${this.boolWith(sc, d, ['x'])})`],
      [vars.length ? 2 : 0, () => B`${r.pick(vars).name}`],
      // (not instanceof: a condition of it would narrow the binding)
      [sc.of('inst').length ? 1 : 0, () => {
        const v = r.pick(sc.of('inst')), cls = r.pick(this.c.classes)
        return B`${cls.name}.prototype.isPrototypeOf(${v.name})`
      }]
    ])()
  }

  ternary(make, sc, d, side) {
    // (of two literals, the second made a number's or a string's: a union of
    // literal types would follow it into arrays, concat refusing a number[])
    const a = side(), b = side()
    const literal = n => n.lit || n.literal
    const other = literal(a) && literal(b) ? {t: b.t, parts: [b.t === 'number' ? 'Number(' : 'String(', b, ')']} : b
    return make`(${this.bool(sc, d + 1)} ? ${a} : ${other})`
  }

  // a comparison, never of two literals (TypeScript's TS2367 on literal types)
  compare(side, op) {
    // (and NaN never compared: TS2845)
    const nan = n => n.lit && n.parts[0] === 'NaN' ? N`(0 / 0)` : n
    let a = nan(side()), b = nan(side())
    const wrap = n => ({t: n.t, parts: [n.t === 'number' ? 'Number(' : 'String(', n, ')']})
    if (a.t === 'string' || ((a.lit || a.literal) && (b.lit || b.literal))) a = wrap(a)
    // (nor a binding against a literal: an equality would narrow it to the literal's type)
    const bare = n => n.parts.length === 1 && /^[a-z]\w*$/.test(n.parts[0]) && !n.lit
    if (bare(a) && (b.lit || b.literal)) b = wrap(b)
    if (bare(b) && (a.lit || a.literal)) a = wrap(a)
    return B`(${a} ${op} ${b})`
  }

  nums(sc, d = 0) {
    const r = this.r
    const vars = sc.of('number[]')
    if (d > 2 || r.chance(0.25 + d * 0.2)) {
      if (vars.length && r.chance(0.6)) return Nums`${r.pick(vars).name}`
      return this.numsLit(sc, d)
    }
    const a = () => this.nums(sc, d + 1), n = () => this.num(sc, d + 1)
    return r.weighted([
      [3, () => this.numsLit(sc, d)],
      [2, () => Nums`${a()}.slice(${r.chance(0.5) ? this.index(sc) : n()})`],
      [3, () => Nums`${a()}.map(x => ${this.numWith(sc, d, ['x'])})`],
      [1, () => Nums`${a()}.map((x, i) => ${this.numWith(sc, d, ['x', 'i'])})`],
      [2, () => Nums`${a()}.filter(x => ${this.boolWith(sc, d, ['x'])})`],
      [2, () => Nums`[...${a()}, ...${a()}]`],
      [1, () => Nums`${a()}.concat(${a()})`],
      [2, () => Nums`Array.from({length: ${this.smallInt(0, 6)}}, (_, i) => ${this.numWith(sc, d, ['i'])})`],
      [1, () => Nums`${a()}.toSorted(cmp)`],
      [1, () => Nums`${a()}.toSorted()`],
      [1, () => Nums`${a()}.toReversed()`],
      [1, () => Nums`new Array<number>(${this.smallInt(0, 5)}).fill(${n()})`],
      [1, () => Nums`Array.of(${n()}, ${n()})`],
      [1, () => Nums`${this.str(sc, d + 1)}.split('').map(c => c.charCodeAt(0))`],
      [1, () => Nums`${a()}.flatMap(x => [x, ${this.numWith(sc, d, ['x'])}])`],
      [1, () => Nums`[${this.nums(sc, d + 1)}, ${this.nums(sc, d + 1)}].flat()`],
      [vars.length ? 3 : 0, () => Nums`${r.pick(vars).name}`]
    ])()
  }

  numsLit(sc, d) {
    const items = []
    for (let k = this.r.weighted([[1, 0], [3, 2], [3, 4], [1, 7]]); k > 0; k--) items.push(this.num(sc, d + 1), ', ')
    items.pop()
    // (an empty one by the type it is given)
    if (!items.length) return Nums`([] as number[])`
    return {t: 'number[]', parts: ['[', ...items, ']']}
  }

  strs(sc, d = 0) {
    const r = this.r
    const vars = sc.of('string[]')
    if (vars.length && r.chance(0.4)) return Strs`${r.pick(vars).name}`
    const x = () => this.str(sc, d + 1)
    return r.weighted([
      [3, () => Strs`[${x()}, ${x()}]`],
      [2, () => Strs`${x()}.split(${x()})`],
      [1, () => Strs`${x()}.split(${x()}, ${this.smallInt(0, 3)})`],
      [1, () => Strs`${this.nums(sc, d + 1)}.map(String)`],
      [1, () => Strs`${this.nums(sc, d + 1)}.map(x => (x).toFixed(1))`],
      [1, () => Strs`[...${x()}]`],
      [1, () => Strs`${this.strs(sc, d + 1)}.toSorted()`],
      [1, () => Strs`Object.keys(${this.nums(sc, d + 1)})`]
    ])()
  }

  brand(sc, d) {
    const r = this.r
    this.feature('M')
    const vars = sc.of('M')
    if (vars.length && r.chance(0.5)) return M`${r.pick(vars).name}`
    return M`(${this.num(sc, d + 1)} as M)`
  }

  callFn(sc, d) {
    const f = this.r.pick(this.c.fns)
    const args = f.params.map(t => this.expr(t, sc, d + 1))
    const parts = [f.name, '(']
    args.forEach((a, i) => parts.push(...(i ? [', '] : []), a))
    parts.push(')')
    return {t: 'number', parts}
  }

  // a field, a getter or a method of an instance in scope
  instNum(sc, d) {
    const r = this.r, v = r.pick(sc.of('inst')), cls = v.cls
    const fields = allOf(cls, 'fields').filter(f => f.t === 'number')
    const methods = allOf(cls, 'methods')
    return r.weighted([
      [fields.length ? 3 : 0, () => N`${v.name}.${r.pick(fields).name}`],
      [methods.length ? 3 : 0, () => N`${v.name}.${r.pick(methods).name}(${this.num(sc, d + 1)})`],
      [cls.getter ? 2 : 0, () => N`${v.name}.${cls.getter}`],
      [1, () => N`${v.name}.x`]
    ])()
  }

  instStr(sc, d) {
    const r = this.r, v = r.pick(sc.of('inst'))
    return r.weighted([
      [2, () => Str`${v.name}.s`],
      [1, () => Str`${v.name}.describe()`],
      [1, () => Str`${v.name}.constructor.name`]
    ])()
  }

  // statements --------------------------------------------------------

  stmt(sc) {
    const r = this.r
    return r.weighted(STATEMENTS.map(([w, f]) => [typeof w === 'function' ? w(this, sc) : w, f]))(this, sc)
  }

  block(sc, n = this.r.range(1, 3), extra = {}) {
    const inner = new Scope(sc, extra)
    const stmts = []
    for (let k = 0; k < n; k++) stmts.push(...this.stmt(inner))
    return block(stmts)
  }

  declare(sc, t, init, extra = {}) {
    const name = this.name()
    const mut = extra.mut ?? this.r.chance(0.5)
    sc.add({name, t, mut, ...extra})
    const type = t === 'fn' ? '(x: number) => number' : t
    if (t.endsWith('[]') && init.parts.length === 1 && typeof init.parts[0] === 'string') init = e(t)`[...${init}]`
    return [s`${mut ? 'let' : 'const'} ${name}: ${type} = ${init}`, name]
  }

  print(x) {
    return s`p(${x})`
  }

  // the lie mode's statement: one value its type does not describe,
  // entering a typed slot on that line
  lie(sc) {
    const r = this.r
    const x = this.name('lie')
    const need = this.top('need')
    const kinds = [
      () => [0, s`const ${x}: number = JSON.parse(${JSON.stringify(JSON.stringify(r.pick(['x', null, true, [1], {}, '1'])))})`, this.print(N`${x} + 1`)],
      () => [0, s`const ${x} = (${this.str(sc, 2)} as unknown) as number`, this.print(N`${x} * 2`)],
      () => [0, s`const ${x}: string = (${this.num(sc, 2)} as unknown) as string`, this.print(Str`${x}.length`)],
      () => {
        // (the argument a function value is not given enters its parameter at
        // the function's line: diverge/missing-argument.ts)
        this.c.top.push({...s`function ${need}(a: number, b: string): string {
  return b + a
}`, lie: true})
        return [-1, s`const ${x}: string = (${need} as unknown as (a: number) => string)(${this.num(sc, 2)})`, this.print(N`${x}.length`)]
      },
      () => {
        const a = sc.of('number[]')[0]?.name
        return [0, a ? s`const ${x}: number = ${a}[${a}.length + ${this.smallInt(0, 3)}]` : s`const ${x}: number = [1, 2][${this.smallInt(2, 5)}]`, this.print(N`${x} + 1`)]
      },
      () => {
        const set = this.name('set')
        return [1, s`let ${x}: number = 0`, s`const ${set} = (v: any) => { ${x} = v }`,
          s`${set}(${this.strLit()})`, this.print(N`${x} + 1`)]
      },
      () => {
        const twice = this.top('twice')
        this.c.top.push(s`function ${twice}(n: number): number {
  return n + n
}`)
        return [0, this.print(N`${twice}(JSON.parse(${JSON.stringify(JSON.stringify(r.pick(['ab', null, false, []])))}))`)]
      }
    ]
    // (at: the statement where the value enters the typed slot, the lie's line)
    const [at, ...stmts] = r.pick(kinds)()
    if (at >= 0) stmts[at].lie = true
    return stmts
  }

  // promises against timers and microtasks: the order must be node's.
  // (every timer 0 ms, so first come first run in both; one nested in
  // another's callback races a longer one when the machine stalls, as it
  // would in node. Counted: the case ends once none is pending.)
  asyncOrder(sc) {
    const r = this.r
    const pending = this.name('pending'), later = this.name('later')
    const out = [s`let ${pending}: number = 0`,
      s`const ${later} = (f: () => void): void => { ${pending}++; setTimeout(() => { ${pending}--; f() }, 0) }`]
    const tag = () => lit('string', JSON.stringify(this.name('t')))
    const steps = r.range(2, 6)
    for (let k = 0; k < steps; k++) {
      out.push(r.weighted([
        [3, () => s`${later}(() => p(${tag()}))`],
        [3, () => s`queueMicrotask(() => p(${tag()}))`],
        [3, () => s`Promise.resolve(${this.num(sc, 2)}).then(v => p(v)).then(() => p(${tag()}))`],
        [2, () => s`void (async () => { p(${tag()}); await null; p(${tag()}); await Promise.resolve(); p(${tag()}) })()`],
        [2, () => s`new Promise<number>(res => res(Promise.resolve(${this.smallInt(0, 9)}))).then(v => p(v))`],
        [1, () => s`Promise.reject(new Error('u:r')).catch((e: unknown) => p(String(e))).finally(() => p(${tag()}))`],
        [1, () => s`${later}(() => { p(${tag()}); queueMicrotask(() => p(${tag()})); ${later}(() => p(${tag()})) })`],
        [1, () => s`void Promise.all([Promise.resolve(1), new Promise<number>(res => ${later}(() => res(2)))]).then(v => p(v))`],
        [1, () => s`void Promise.race([new Promise<string>(res => ${later}(() => res('slow'))), Promise.resolve('fast')]).then(v => p(v))`],
        [1, () => s`void Promise.allSettled([Promise.reject(new Error('u:x')), Promise.resolve(3)]).then(v => p(v.map(x => x.status)))`],
        [1, () => s`void Promise.any([Promise.reject(new Error('u:y')), Promise.resolve(4)]).then(v => p(v))`],
        [1, () => s`p(${tag()})`]
      ])())
    }
    out.push(s`do await new Promise<void>(res => setTimeout(res, 0)); while (${pending} > 0)`)
    out.push(this.print(lit('string', '"end"')))
    return out
  }
}

export class Scope {
  constructor(parent, extra = {}) {
    this.parent = parent
    this.vars = []
    this.async = parent?.async ?? false
    this.loop = parent?.loop ?? false
    this.fixed = new Set()
    Object.assign(this, extra)
  }

  add(v) {
    this.vars.push(v)
    return v
  }

  all() {
    return [...(this.parent?.all() ?? []), ...this.vars]
  }

  of(t, ok = () => true) {
    return this.all().filter(v => v.t === t && !v.dyn && ok(v))
  }

  // an array whose length must not change here (a loop reads it by index)
  isFixed(name) {
    return this.fixed.has(name) || (this.parent?.isFixed(name) ?? false)
  }
}

function allOf(cls, key) {
  return [...(cls.parent ? allOf(cls.parent, key) : []), ...cls[key]]
}

// plain statements, weighted: [weight or (g, sc) => weight, (g, sc) => statements]
const STATEMENTS = [
  [8, (g, sc) => [g.print(g.any(sc))]],
  [4, (g, sc) => {
    const t = g.r.weighted([[5, 'number'], [2, 'string'], [1, 'boolean'], [2, 'number[]'], [1, 'string[]']])
    const [decl, name] = g.declare(sc, t, g.expr(t, sc, 1))
    return [decl, g.print(e(t)`${name}`)]
  }],
  [(g, sc) => sc.of('number', v => v.mut && !v.counter).length ? 4 : 0, (g, sc) => {
    const v = g.r.pick(sc.of('number', v => v.mut && !v.counter))
    v.index = false
    const op = g.r.pick(['=', '+=', '-=', '*=', '/=', '%=', '|=', '<<=', '>>>=', '**='])
    const rhs = op === '**=' ? g.smallInt(0, 3) : g.num(sc, 1)
    return [s`${v.name} ${op} ${rhs}`, g.print(N`${v.name}`)]
  }],
  [(g, sc) => sc.of('string', v => v.mut).length ? 2 : 0, (g, sc) => {
    const v = g.r.pick(sc.of('string', v => v.mut))
    return [s`${v.name} ${g.r.pick(['=', '+='])} ${g.str(sc, 1)}`, g.print(Str`${v.name}`)]
  }],
  [3, (g, sc) => [s`if (${g.bool(sc, 1)}) ${g.block(sc)}${g.r.chance(0.5) ? s` else ${g.block(sc)}` : ''}`]],
  [6, (g, sc) => counterLoop(g, sc)],
  [3, (g, sc) => arrayOps(g, sc)],
  [2, (g, sc) => forOf(g, sc)],
  [2, (g, sc) => stringBuild(g, sc)],
  [1, (g, sc) => whileLoop(g, sc)],
  [(g, sc) => sc.loop ? 0 : 1, (g, sc) => switchStmt(g, sc)],
  [1, (g, sc) => closures(g, sc)],
  [1, (g, sc) => numberEdges(g, sc)]
]

// a for loop's counter: the Int64 rule (an integer start, stepped by one,
// written nowhere else, captured by no closure) and its near misses
function counterLoop(g, sc) {
  const r = g.r
  const i = g.name('i')
  const start = r.weighted([[6, 0], [2, 1], [2, -3], [1, -5], [1, 2147483645], [1, -2147483650], [1, 4294967293], [1, 9007199254740988], [1, 0.5], [1, -0.5]])
  const count = r.range(0, 6)
  const arrays = sc.of('number[]', v => !v.frozen)
  const near = r.weighted([[6, 'none'], [1, 'step2'], [1, 'plus'], [1, 'down'], [1, 'written'], [1, 'captured'], [1, 'after'], [1, 'le'], [1, 'pre']])
  const inner = new Scope(sc, {loop: true})
  const counter = inner.add({name: i, t: 'number', mut: false, counter: true, index: start >= 0 && Number.isInteger(start) && ['none', 'plus', 'le', 'pre', 'after'].includes(near)})
  // (over an array: its length the bound, the array not shortened in the body)
  const over = arrays.length && start === 0 && near === 'none' && r.chance(0.4) ? r.pick(arrays) : null
  let bound = over ? `${over.name}.length` : String(start + count)
  // (2^53 + 1 is 2^53: a counter stepped by one stops there)
  if (!over && start + count > 2 ** 53 - 1) bound = String(2 ** 53 - 1)
  if (over) inner.fixed.add(over.name)
  const body = []
  const uses = r.range(1, 3)
  for (let k = 0; k < uses; k++) body.push(r.weighted([
    [5, () => g.print(r.weighted([
      [3, () => N`${i}`],
      [3, () => N`${i} % ${lit('number', r.pick([2, 3, 7, -2, 1000000007, 1]))}`],
      [2, () => N`-${i}`],
      [2, () => N`${i} * ${g.numLit()}`],
      [2, () => N`${i} / ${lit('number', r.pick([2, 3, 0, -1]))}`],
      [2, () => N`(${i} | 0)`],
      [1, () => N`(${i} >>> 0)`],
      [1, () => N`(${i} << 1)`],
      [1, () => N`(${i} - ${i})`],
      [2, () => N`${g.str(inner, 2)}.charCodeAt(${i})`],
      [1, () => B`(${i} === ${lit('number', start + 1)})`],
      [2, () => N`(${i} + ${g.num(inner, 2)})`],
      [1, () => e('string')`${i} + ''`],
      [1, () => e('string')`\`\${${i}}\``],
      [over ? 4 : 0, () => N`${over.name}[${i}]`],
      // (an index only while the counter is an integer: a[0.5] is undefined)
      [arrays.length && Number.isInteger(start) && near !== 'written' ? 1 : 0, () => {
        const a = r.pick(arrays).name
        return N`(${i} < ${a}.length && ${i} >= 0 ? ${a}[${i}] : -1)`
      }]
    ])())],
    [over && !over.dyn ? 2 : 0, () => s`${over.name}[${i}] ${r.pick(['=', '+=', '*='])} ${g.num(inner, 2)}`],
    [over ? 1 : 0, () => {
      const other = r.pick(arrays)
      return s`if (${i} < ${other.name}.length) ${over.name}[${i}] = ${other.name}[${i}]`
    }],
    [2, () => g.stmt(inner)[0] ?? s`p(${i})`]
  ])())
  let head
  switch (near) {
    case 'step2': head = `for (let ${i} = ${start}; ${i} < ${bound}; ${i} += 2)`; break
    case 'plus': head = `for (let ${i} = ${start}; ${i} < ${bound}; ${i} += 1)`; break
    case 'down': head = `for (let ${i} = ${start + count}; ${i} > ${start}; ${i}--)`; break
    case 'le': head = `for (let ${i} = ${start}; ${i} <= ${bound}; ${i}++)`; break
    case 'pre': head = `for (let ${i} = ${start}; ${i} < ${bound}; ++${i})`; break
    case 'after': head = `for (${i} = ${start}; ${i} < ${bound}; ${i}++)`; break
    default: head = `for (let ${i} = ${start}; ${i} < ${bound}; ${i}++)`
  }
  if (near === 'written') body.push(s`if (${i} === ${lit('number', start + 1)}) ${i} += ${lit('number', r.pick([1, 0.5, 2]))}`)
  const out = []
  if (near === 'captured') {
    const fs = g.name('fs')
    out.push(s`const ${fs}: Array<() => number> = []`)
    body.push(s`${fs}.push(() => ${i} * 2)`)
    out.push(s`${head} ${block(body)}`)
    out.push(g.print(N`${fs}.map(f => f()).reduce((a, b) => a + b, 0)`))
    out.push(g.print(Nums`${fs}.map(f => f())`))
    return out
  }
  if (near === 'after') {
    out.push(s`let ${i}: number = 0`)
    out.push(s`${head} ${block(body)}`)
    out.push(g.print(N`${i}`))
    return out
  }
  if (r.chance(0.2)) {
    const label = g.name('L')
    const j = g.name('j')
    return [s`${label}: ${head} {
  for (let ${j} = 0; ${j} < 3; ${j}++) {
    if (${j} === ${lit('number', r.range(0, 2))}) ${r.pick(['continue', 'break'])} ${label}
    p(${i} * 10 + ${j})
  }
}`]
  }
  out.push(s`${head} ${block(body)}`)
  void counter
  return out
}

function whileLoop(g, sc) {
  const r = g.r
  const k = g.name('k')
  const inner = new Scope(sc, {loop: true})
  const body = [...g.stmt(inner)]
  if (r.chance(0.3)) body.push(s`if (${k} === 2) continue`)
  return [s`let ${k}: number = ${g.smallInt(0, 2)}`,
    r.chance(0.5)
      ? s`while (${k}++ < ${g.smallInt(1, 5)}) ${block(body)}`
      : s`do ${block([...body])} while (++${k} < ${g.smallInt(1, 5)})`,
    g.print(N`${k}`)]
}

function forOf(g, sc) {
  const r = g.r
  const x = g.name('x')
  const inner = new Scope(sc, {loop: true})
  const string = r.chance(0.3)
  inner.add({name: x, t: string ? 'string' : 'number', mut: false})
  const src = string ? r.pick([g.str(sc, 1), g.strs(sc, 1)]) : g.nums(sc, 1)
  if (src.parts.length === 1 && typeof src.parts[0] === 'string') inner.fixed.add(src.parts[0])
  const body = r.chance(0.3) ? [s`if (${g.bool(inner, 2)}) ${r.pick(['continue', 'break'])}`] : []
  body.push(g.print(e('unknown')`${x}`), ...g.stmt(inner))
  if (!string && r.chance(0.2)) {
    const i = g.name('i')
    return [s`for (const [${i}, ${x}] of ${src}.entries()) p([${i}, ${x}])`]
  }
  return [s`for (const ${x} of ${src}) ${block(body)}`]
}

// a string local a loop only appends to (buffered) and its near misses
function stringBuild(g, sc) {
  const r = g.r
  const acc = g.name('acc'), i = g.name('i')
  const inner = new Scope(sc, {loop: true})
  inner.add({name: i, t: 'number', counter: true, index: true})
  const piece = r.weighted([[3, () => g.str(inner, 2)], [2, () => N`${i}`], [1, () => g.num(inner, 2)], [1, () => Str`String.fromCharCode(97 + ${i})`]])()
  const n = g.smallInt(0, 6)
  const form = r.weighted([[5, 'append'], [1, 'concat'], [1, 'prepend'], [1, 'read'], [1, 'captured'], [1, 'double'], [1, 'nested']])
  const out = [s`let ${acc}: string = ${r.chance(0.7) ? "''" : g.strLit()}`]
  switch (form) {
    case 'append': out.push(s`for (let ${i} = 0; ${i} < ${n}; ${i}++) ${acc} += ${piece}`); break
    case 'concat': out.push(s`for (let ${i} = 0; ${i} < ${n}; ${i}++) ${acc} = ${acc} + ${piece}`); break
    case 'prepend': out.push(s`for (let ${i} = 0; ${i} < ${n}; ${i}++) ${acc} = ${piece} + ${acc}`); break
    case 'read': out.push(s`for (let ${i} = 0; ${i} < ${n}; ${i}++) {
  ${acc} += ${piece}
  if (${acc}.length > 4) p(${acc}.length)
}`); break
    case 'captured': {
      const f = g.name('f')
      out.push(s`const ${f} = (): number => ${acc}.length`)
      out.push(s`for (let ${i} = 0; ${i} < ${n}; ${i}++) { ${acc} += ${piece}; p(${f}()) }`)
      break
    }
    case 'double': out.push(s`for (let ${i} = 0; ${i} < ${g.smallInt(0, 4)}; ${i}++) ${acc} += ${acc} + ${i}`); break
    case 'nested': {
      const j = g.name('j')
      out.push(s`for (let ${i} = 0; ${i} < ${n}; ${i}++) for (let ${j} = 0; ${j} < 2; ${j}++) ${acc} += ${j} + ':'`)
    }
  }
  out.push(g.print(Str`${acc}`))
  if (r.chance(0.4)) out.push(g.print(N`${acc}.length`))
  sc.add({name: acc, t: 'string', mut: true})
  return out
}

// number arrays: in place, holes, a length past the end, freezing,
// widening to unknown[]
function arrayOps(g, sc) {
  const r = g.r
  let arrays = sc.of('number[]', v => !v.frozen)
  const out = []
  if (!arrays.length || r.chance(0.3)) {
    const [decl, name] = g.declare(sc, 'number[]', g.numsLit(sc, 1), {mut: false})
    out.push(decl)
    arrays = sc.of('number[]', v => v.name === name)
  }
  const a = r.pick(arrays)
  // (a loop reads it by index or iterates it: its length kept; in a loop no
  // hole made, which a read drawn before it in the body would meet)
  const fixed = sc.isFixed(a.name), loop = sc.loop
  const n = () => g.num(sc, 2)
  const op = r.weighted([
    [fixed ? 0 : 4, () => [s`${a.name}.push(${n()}${r.chance(0.3) ? s`, ${n()}` : ''})`]],
    [fixed ? 0 : 2, () => [g.print(e('unknown')`${a.name}.pop()`)]],
    [fixed ? 0 : 2, () => [g.print(e('unknown')`${a.name}.shift()`)]],
    [fixed ? 0 : 1, () => [s`${a.name}.unshift(${n()})`]],
    [fixed ? 0 : 1, () => [g.print(Nums`${a.name}.splice(${g.index(sc)}, ${g.smallInt(0, 2)}${r.chance(0.5) ? s`, ${n()}` : ''})`)]],
    [2, () => [s`${a.name}.sort(${r.chance(0.6) ? 'cmp' : ''})`]],
    [1, () => [s`${a.name}.reverse()`]],
    [1, () => [s`${a.name}.fill(${n()}, ${g.index(sc)})`]],
    [1, () => [s`${a.name}.copyWithin(${g.index(sc)}, ${g.index(sc)})`]],
    [2, () => {
      const i = g.index(sc)
      return [s`if (${i} < ${a.name}.length) ${a.name}[${i}] = ${n()}`]
    }],
    [fixed || loop ? 0 : 2, () => {
      a.dyn = true
      return [s`${a.name}[${a.name}.length + ${g.smallInt(0, 2)}] = ${n()}`]
    }],
    [fixed || loop ? 0 : 1, () => {
      a.dyn = true
      return [s`${a.name}.length = ${g.smallInt(0, 6)}`]
    }],
    [fixed || loop ? 0 : 1, () => {
      a.dyn = true
      return [s`delete ${a.name}[${g.index(sc)}]`]
    }],
    [fixed || loop ? 0 : 1, () => {
      a.frozen = true
      return [s`Object.freeze(${a.name})`, s`try { ${a.name}.push(1) } catch (e) { p(e instanceof TypeError) }`,
        s`try { ${a.name}[0] = 5 } catch (e) { p(e instanceof TypeError) }`, g.print(B`Object.isFrozen(${a.name})`)]
    }],
    [fixed || loop ? 0 : 1, () => {
      const w = g.name('w')
      a.dyn = true
      return [s`const ${w}: unknown[] = ${a.name}`, s`${w}.push(${g.strLit()})`, g.print(e('unknown')`${w}.length`)]
    }],
    [1, () => {
      const b = g.name('b')
      return [s`const ${b}: number[] = [...${a.name}]`,
        s`for (let i = 0; i < ${b}.length; i++) ${b}[i] = ${b}[${b}.length - 1 - i]`, g.print(Nums`${b}`)]
    }],
    [1, () => [g.print(e('unknown')`[...${a.name}.entries()]`)]],
    [1, () => [g.print(e('unknown')`${a.name}.join()`)]],
    [1, () => [g.print(e('unknown')`${a.name}.indexOf(${n()})`)]]
  ])()
  out.push(...op)
  out.push(g.print(e('unknown')`${a.name}`))
  if (r.chance(0.3)) out.push(g.print(e('unknown')`${a.name}.length`))
  return out
}

function switchStmt(g, sc) {
  const r = g.r
  const string = r.chance(0.3)
  const subject = string ? Str`${g.str(sc, 1)}.charAt(0)` : N`(${g.num(sc, 1)} % 4)`
  const cases = []
  const values = string ? ['"a"', '""', '"1"', '"h"', '"N"'] : ['0', '1', '2', '3', '-1', '-0', 'NaN', '0.5']
  for (let k = r.range(1, 4); k > 0; k--) {
    cases.push(`  case ${r.pick(values)}:\n    p(${JSON.stringify(`case ${k}`)})${r.chance(0.5) ? '\n    break' : ''}`)
  }
  if (r.chance(0.6)) cases.splice(r.int(cases.length + 1), 0, `  default:\n    p('default')`)
  return [s`switch (${subject}) {\n${cases.join('\n')}\n}`]
}

function closures(g, sc) {
  const r = g.r
  const c = g.name('c'), f = g.name('f')
  return r.weighted([
    [3, () => {
      const init = g.num(sc, 2)
      sc.add({name: c, t: 'number', mut: true})
      return [s`let ${c}: number = ${init}`,
        s`const ${f} = (): number => { ${c} ${r.pick(['+=', '-=', '*='])} ${g.smallInt(1, 3)}; return ${c} }`,
        g.print(N`${f}()`), g.print(N`${f}() + ${c}`), g.print(N`${c}`)]
    }],
    [2, () => {
      const kind = r.pick(['let', 'var'])
      const i = g.name('i')
      return [s`const ${f}: Array<() => number> = []`,
        s`for (${kind} ${i} = 0; ${i} < ${g.smallInt(1, 4)}; ${i}++) ${f}.push(() => ${i} * ${g.smallInt(1, 3)})`,
        g.print(Nums`${f}.map(h => h())`)]
    }],
    [2, () => {
      const decl = s`const ${f} = ((k: number) => (x: number): number => x * k + ${g.numLit()})(${g.num(sc, 2)})`
      sc.add({name: f, t: 'fn', mut: false})
      return [decl,
        g.print(N`${f}(${g.num(sc, 2)})`)]
    }],
    [1, () => {
      const xs = g.name('xs')
      return [s`const ${xs}: number[] = []`,
        s`const ${f} = (v: number): number => ${xs}.push(v)`,
        g.print(N`${f}(${g.num(sc, 2)}) + ${f}(1)`), g.print(Nums`${xs}`)]
    }],
    [1, () => {
      const make = g.name('make')
      return [s`function ${make}(start: number): {next: () => number, peek: () => number} {
  let n = start
  return {next: () => ++n, peek: () => n}
}`,
        s`const ${c} = ${make}(${g.num(sc, 2)})`, g.print(N`${c}.next() + ${c}.next()`), g.print(N`${c}.peek()`)]
    }]
  ])()
}

// numbers where helder departs from doubles if it gets them wrong
function numberEdges(g, sc) {
  const r = g.r
  const x = g.name('x')
  const init = g.numLit()
  sc.add({name: x, t: 'number', mut: false})
  const ops = []
  for (let k = r.range(2, 5); k > 0; k--) ops.push(r.weighted([
    [2, () => N`${x} % ${g.numLit()}`],
    [2, () => N`${g.numLit()} % ${x}`],
    [2, () => N`${x} | 0`],
    [1, () => N`${x} >>> 0`],
    [1, () => N`${x} >> ${g.smallInt(0, 33)}`],
    [1, () => N`${x} << ${g.smallInt(0, 33)}`],
    [2, () => N`Math.round(${x})`],
    [1, () => N`Math.trunc(${x})`],
    [1, () => N`${x} * 0`],
    [1, () => N`-${x} + 0`],
    [1, () => N`1 / ${x}`],
    [1, () => N`Math.fround(${x})`],
    [1, () => Str`(${x}).toString(${r.pick(RADIX)})`],
    [1, () => Str`String(${x})`],
    [1, () => Str`(${x}).toFixed(${g.smallInt(0, 20)})`],
    [1, () => N`${x} ** ${g.smallInt(0, 2)}`],
    [1, () => B`${x} === ${x}`],
    [1, () => Str`\`\${${x}}\``]
  ])())
  return [s`const ${x}: number = ${init}`, ...ops.map(o => g.print(o))]
}

// case families: what a case is mainly about
const FAMILIES = [
  {name: 'plain', weight: 8, run: () => []},
  {name: 'counters', weight: 5, run: (g, sc) => [...counterLoop(g, sc), ...counterLoop(g, sc)]},
  {name: 'arrays', weight: 5, run: (g, sc) => [...arrayOps(g, sc), ...arrayOps(g, sc)]},
  {name: 'classes', weight: 6, run: (g, sc) => classes(g, sc)},
  {name: 'brands', weight: 3, run: (g, sc) => brands(g, sc)},
  {name: 'generics', weight: 3, run: (g, sc) => generics(g, sc)},
  {name: 'strings', weight: 4, run: (g, sc) => [...stringBuild(g, sc), ...stringMethods(g, sc)]},
  {name: 'closures', weight: 3, run: (g, sc) => [...closures(g, sc), ...closures(g, sc)]},
  {name: 'control', weight: 4, run: (g, sc) => control(g, sc)},
  {name: 'destructuring', weight: 3, run: (g, sc) => destructuring(g, sc)},
  {name: 'generators', weight: 3, run: (g, sc) => generators(g, sc)},
  {name: 'collections', weight: 3, run: (g, sc) => collections(g, sc)},
  {name: 'json', weight: 2, run: (g, sc) => json(g, sc)},
  {name: 'typed', weight: 2, run: (g, sc) => typedArrays(g, sc)},
  {name: 'regexp', weight: 2, run: (g, sc) => regexps(g, sc)},
  {name: 'dates', weight: 2, run: (g, sc) => dates(g, sc)},
  {name: 'numbers', weight: 3, run: (g, sc) => [...numberEdges(g, sc), ...numberEdges(g, sc)]}
]

// a layout class chain (plain field names, single inheritance), its
// methods called directly and through the base, overridden, accessors,
// statics; or a class without a layout (a computed name, extending one
// without a layout or a built-in)
function classes(g, sc) {
  const r = g.r
  const A = g.top('A'), Bc = g.top('B'), Cc = g.top('C')
  const layout = r.chance(0.75)
  const k = r.pick(['1', '2', '0.5', '-1'])
  const computed = layout ? '' : r.pick([`  ['kx']: number = 3\n`, `  [§key]: number = 4\n`, ''])
  if (computed.includes('§key')) g.c.top.push(s`const §key = 'kk'`)
  const builtin = !layout && !computed && r.chance(0.5)
  if (builtin) {
    g.c.top.push(s`class ${A} extends Map<string, number> {
  x: number
  s: string
  constructor(x: number, s: string) {
    super()
    this.x = x
    this.s = s
    this.set(s, x)
  }
  m(k: number): number {
    return this.x * k + this.size
  }
  describe(): string {
    return this.s + '/' + this.x
  }
}`)
    g.feature('Map')
  } else g.c.top.push(s`class ${A} {
${computed}  x: number
  s: string
  static count: number = 0
  constructor(x: number, s: string) {
    this.x = x
    this.s = s
    ${A}.count++
  }
  m(k: number): number {
    return this.x * k + ${k}
  }
  get g(): number {
    return this.x * 2
  }
  set g(v: number) {
    this.x = v / 2
  }
  describe(): string {
    return this.s + '/' + this.x
  }
  static make(): ${A} {
    return new ${A}(${A}.count, 'made')
  }
}`)
  const clsA = {name: A, fields: [{name: 'x', t: 'number'}, {name: 's', t: 'string'}], methods: [{name: 'm'}], getter: builtin ? null : 'g', parent: null}
  g.c.top.push(s`class ${Bc} extends ${A} {
  y: number = ${g.numLit()}
  ${r.chance(0.5) ? 'override ' : ''}m(k: number): number {
    return ${r.chance(0.6) ? 'super.m(k) + ' : ''}this.y * k
  }
  n(k: number): number {
    return this.m(k) - this.x
  }
}`)
  const clsB = {name: Bc, fields: [{name: 'y', t: 'number'}], methods: [{name: 'n'}], getter: clsA.getter, parent: clsA}
  const deep = r.chance(0.4)
  const classesList = [clsA, clsB]
  if (deep) {
    g.c.top.push(s`class ${Cc} extends ${Bc} {
  z: number[] = [1, 2]
  override n(k: number): number {
    return super.n(k) * 2 + this.z.length
  }
  ${builtin ? '' : `override get g(): number {
    return -this.x
  }
  override set g(v: number) {
    this.x = v
  }`}
}`)
    classesList.push({name: Cc, fields: [], methods: [], getter: clsA.getter, parent: clsB})
  }
  g.c.classes.push(...classesList)
  const out = []
  const o = g.name('o'), os = g.name('os')
  const pick = () => r.pick(classesList)
  const cls = pick()
  out.push(s`const ${o}: ${cls.name} = new ${cls.name}(${g.num(sc, 2)}, ${g.strLit()})`)
  sc.add({name: o, t: 'inst', cls, mut: false})
  out.push(s`const ${os}: ${A}[] = [${classesList.map(c => `new ${c.name}(${r.range(-3, 9)}, 'q')`).join(', ')}]`)
  for (let n = r.range(2, 6); n > 0; n--) out.push(r.weighted([
    [3, () => g.print(N`${o}.m(${g.num(sc, 2)})`)],
    [3, () => s`for (const q of ${os}) p(q.m(${g.smallInt(0, 3)}))`],
    [2, () => s`${o}.x ${r.pick(['=', '+=', '*='])} ${g.num(sc, 2)}`],
    [clsA.getter ? 2 : 0, () => s`${o}.g = ${g.num(sc, 2)}`],
    [clsA.getter ? 2 : 0, () => g.print(N`${o}.g`)],
    [2, () => g.print(e('unknown')`${o}`)],
    [1, () => g.print(e('unknown')`${os}`)],
    [1, () => g.print(B`${o} instanceof ${pick().name}`)],
    [builtin ? 0 : 1, () => g.print(N`${A}.count`)],
    [builtin ? 0 : 1, () => g.print(N`${A}.make().m(2)`)],
    [1, () => {
      const f = g.name('f')
      return s`const ${f} = ${o}.m; p(${f}.call(${o}, 3))`
    }],
    [1, () => g.print(e('unknown')`Object.keys(${o})`)],
    [1, () => g.print(Str`${o}.describe()`)],
    [1, () => g.print(Str`JSON.stringify(${o})`)],
    [1, () => g.print(B`Object.getPrototypeOf(${o}) === ${cls.name}.prototype`)],
    [classesList.length > 2 ? 2 : 0, () => s`for (const q of ${os}) if (q instanceof ${Bc}) p(q.n(${g.smallInt(1, 3)}))`],
    [1, () => g.print(e('unknown')`${os}.map(q => q.constructor.name)`)],
    [1, () => g.print(N`${os}.reduce((t, q) => t + q.m(1), 0)`)],
    [1, () => s`try { Object.defineProperty(${o}, 'w', {value: 1}); p(Object.keys(${o})) } catch (e) { p(String(e instanceof TypeError)) }`]
  ])())
  return out
}

function brands(g, sc) {
  const r = g.r
  g.feature('M')
  g.feature('S')
  const add = g.top('add'), scale = g.top('scale'), tag = g.top('tag')
  g.c.top.push(s`function ${add}(a: M, b: M): M {
  return (a + b) as M
}`, s`function ${scale}<T extends number>(x: T, k: number): number {
  return x * k
}`, s`function ${tag}(x: S, n: M): string {
  return x + ':' + n
}`)
  const a = g.name('m'), b = g.name('m'), ms = g.name('ms'), t = g.name('s')
  const out = [s`const ${a}: M = ${g.num(sc, 2)} as M`]
  sc.add({name: a, t: 'M'})
  out.push(s`const ${b} = ${add}(${a}, ${g.numLit()} as M)`,
    s`const ${ms}: M[] = [${a}, ${b}, ${add}(${b}, ${b})]`, s`const ${t} = ${g.strLit()} as S`)
  for (let n = r.range(2, 5); n > 0; n--) out.push(g.print(r.weighted([
    [2, () => N`${a} + ${b}`],
    [2, () => N`${scale}(${a}, ${g.numLit()})`],
    [1, () => N`${scale}(${g.num(sc, 2)}, 2)`],
    [2, () => Nums`${ms}.map(x => x * 2)`],
    [2, () => e('unknown')`${ms}`],
    [1, () => N`${ms}.reduce((x, y) => x + y, 0)`],
    [1, () => Str`${tag}(${t}, ${b})`],
    [1, () => N`${a} % 3`],
    [1, () => Str`${t}.trim()`],
    [1, () => N`${ms}.indexOf(${b})`]
  ])()))
  return out
}

// direct generic functions called with number (a copy each, up to 64)
// and with other types (the dynamic one)
function generics(g, sc) {
  const r = g.r
  const id = g.top('id'), last = g.top('last'), pair = g.top('pair'), sum = g.top('sum'), maxT = g.top('max')
  g.c.top.push(s`function ${id}<T>(x: T): T {
  return x
}`, s`function ${last}<T>(xs: T[]): T | undefined {
  return xs[xs.length - 1]
}`, s`function ${pair}<T>(a: T, b: T): T[] {
  return [a, b, a]
}`, s`function ${sum}<T extends number>(xs: T[]): number {
  let t = 0
  for (const x of xs) t += x
  return t
}`, s`function ${maxT}<T extends number>(a: T, b: T): T {
  return a > b ? a : b
}`)
  const out = []
  if (r.chance(0.1)) {
    // (past the copies' limit: 70 functions called with number)
    const many = []
    for (let k = 0; k < 70; k++) many.push(`function §g${k}<T>(x: T): T[] {\n  return [x, x]\n}`)
    g.c.top.push(s`${many.join('\n')}`)
    out.push(s`p([${Array.from({length: 70}, (_, k) => `§g${k}(${k})[0]`).join(', ')}].reduce((a, b) => a + b, 0))`)
    out.push(s`p(§g69('x'))`)
  }
  for (let n = r.range(3, 6); n > 0; n--) out.push(g.print(r.weighted([
    [3, () => N`${id}(${g.num(sc, 2)})`],
    [1, () => N`${id}<number>(${g.num(sc, 2)})`],
    [2, () => Str`${id}(${g.str(sc, 2)})`],
    [2, () => e('unknown')`${last}(${g.nums(sc, 2)})`],
    [1, () => e('unknown')`${last}(${g.strs(sc, 2)})`],
    [1, () => e('unknown')`${last}<number>([])`],
    [2, () => Nums`${pair}(${g.num(sc, 2)}, ${g.num(sc, 2)})`],
    [1, () => e('unknown')`${pair}<number | string>(${g.num(sc, 2)}, ${g.str(sc, 2)})`],
    [2, () => N`${sum}(${g.nums(sc, 2)})`],
    [2, () => N`${maxT}(${g.num(sc, 2)}, ${g.num(sc, 2)})`],
    [1, () => N`${sum}(${pair}(${g.num(sc, 2)}, -0))`]
  ])()))
  return out
}

function stringMethods(g, sc) {
  const r = g.r
  const out = []
  const x = g.name('x')
  out.push(s`const ${x}: string = ${g.str(sc, 1)}`)
  sc.add({name: x, t: 'string', mut: false})
  for (let n = r.range(2, 5); n > 0; n--) out.push(g.print(g.str(sc, 0)))
  if (r.chance(0.3)) out.push(s`for (let i = -1; i <= ${x}.length; i++) p(${x}.charCodeAt(i))`)
  return out
}

function control(g, sc) {
  const r = g.r
  const f = g.top('f')
  return r.weighted([
    // try/catch/finally, return and break in finally, exceptions across frames
    [3, () => {
      g.c.top.push(s`function ${f}(k: number): number {
  try {
    if (k > ${r.range(0, 3)}) throw new Error('u:big ' + k)
    if (k < 0) throw k
    return k * 2
  } catch (e) {
    p(e instanceof Error ? e.message : e)
    ${r.chance(0.5) ? 'return -1' : "throw new RangeError('u:again')"}
  } finally {
    p('finally ' + k)
    ${r.chance(0.4) ? 'if (k === 2) return 99' : ''}
  }
}`)
      return [s`for (const k of [${r.range(-1, 1)}, 1, 2, 3]) {
  try {
    p(${f}(k))
  } catch (e) {
    p(e instanceof RangeError ? 'range ' + e.message : 'other')
  }
}`]
    }],
    [2, () => [s`for (let i = 0; i < 4; i++) {
  try {
    if (i === ${r.range(0, 3)}) continue
    if (i === ${r.range(1, 4)}) break
    p('body ' + i)
  } finally {
    p('fin ' + i)
  }
}`]],
    [2, () => {
      const inner = g.top('inner'), outer = g.top('outer')
      g.c.top.push(s`function ${inner}(n: number): number {
  if (n <= 0) throw new TypeError('u:bottom')
  return ${inner}(n - 1) + 1
}`, s`function ${outer}(n: number): string {
  try {
    return 'ok ' + ${inner}(n)
  } finally {
    p('unwound ' + n)
  }
}`)
      return [s`try { p(${outer}(${g.smallInt(0, 4)})) } catch (e) { p(e instanceof TypeError ? e.message : 'no') }`]
    }],
    [2, () => {
      const label = g.name('outer')
      return [s`${label}: for (let i = 0; i < ${g.smallInt(1, 4)}; i++) {
  let j = 0
  while (true) {
    j++
    if (j > ${g.smallInt(1, 3)}) continue ${label}
    if (i * j === ${g.smallInt(2, 6)}) break ${label}
    p(i + ',' + j)
  }
}`]
    }],
    [2, () => switchStmt(g, sc)],
    [1, () => {
      const x = g.name('x')
      return [s`const ${x}: number = ${g.num(sc, 1)}`, s`switch (true) {
  case ${x} > 10:
    p('big')
  case ${x} > 0:
    p('positive')
    break
  case Number.isNaN(${x}):
    p('nan')
  default:
    p('other')
}`]
    }],
    [1, () => [s`try {
  try {
    throw ${r.pick(["new Error('u:a')", '42', "'str'", '{code: 1}', 'null'])}
  } catch (e) {
    p(e)
    throw e
  } finally {
    p('inner finally')
  }
} catch (e2) {
  p(['outer', e2])
}`]]
  ])()
}

function destructuring(g, sc) {
  g.feature('Opt')
  g.feature('Rec')
  const r = g.r
  const out = []
  const o = g.name('o'), a = g.name('a')
  const opt = () => {
    const fields = []
    if (r.chance(0.6)) fields.push(`a: ${r.pick(['1', '-0', 'undefined', 'NaN', '0'])}`)
    if (r.chance(0.5)) fields.push(`b: ${r.pick(["''", "'x'", 'undefined'])}`)
    if (r.chance(0.4)) fields.push(`c: {a: 7, c: {b: 'deep'}}`)
    return `{${fields.join(', ')}}`
  }
  out.push(s`const ${o}: Opt = ${opt()}`)
  out.push(s`const ${a}: number[] = ${g.numsLit(sc, 1)}`)
  for (let n = r.range(2, 5); n > 0; n--) out.push(...r.weighted([
    [2, () => {
      const x = g.name('x'), y = g.name('y')
      return [s`const {a: ${x} = ${g.numLit()}, b: ${y} = 'dflt'} = ${o}`, s`p([${x}, ${y}])`]
    }],
    [2, () => {
      const x = g.name('x'), y = g.name('y'), z = g.name('z')
      return [s`const [${x} = ${g.numLit()}, , ${y} = -1, ...${z}] = ${a}`, s`p([${x}, ${y}, ${z}])`]
    }],
    [2, () => [g.print(e('unknown')`${o}.c?.c?.b`), g.print(e('unknown')`${o}.c?.a ?? 'none'`), g.print(e('unknown')`${o}.a ?? ${o}.b ?? 0`)]],
    [1, () => {
      const x = g.name('x')
      return [s`let ${x}: number | undefined = ${o}.a`, s`${x} ??= ${g.numLit()}`, s`p(${x})`]
    }],
    [1, () => {
      const x = g.name('x')
      return [s`let ${x}: string = ${o}.b ?? ''`, s`${x} ||= 'or'`, s`p(${x})`, s`let ${x}b: boolean = ${g.bool(sc, 2)}`, s`${x}b &&= ${g.bool(sc, 2)}`, s`p(${x}b)`]
    }],
    [1, () => [s`${o}.a ??= 5`, s`${o}.b ||= 'set'`, g.print(e('unknown')`${o}`)]],
    [1, () => {
      const x = g.name('x'), y = g.name('y')
      return [s`let ${x}: number = ${g.numLit()}, ${y}: number = ${g.numLit()}`, s`;[${x}, ${y}] = [${y}, ${x}]`, s`p([${x}, ${y}])`]
    }],
    [1, () => {
      const f = g.top('f')
      g.c.top.push(s`function ${f}({a = 1, b = 'z'}: Opt, ...rest: number[]): string {
  return a + b + rest.length + ':' + rest.join('|')
}`)
      return [g.print(Str`${f}(${o}, ...${a})`), g.print(Str`${f}({}, ${g.numLit()})`)]
    }],
    [1, () => {
      const rec = g.name('rec'), rest = g.name('rest')
      return [s`const ${rec}: Rec = {a: ${g.numLit()}, b: ${g.strLit()}, n: ${a}}`,
        s`const {a: ${rest}a, ...${rest}} = ${rec}`, s`p(${rest}a)`, g.print(e('unknown')`${rest}`), g.print(e('unknown')`{...${rec}, a: -0, extra: true}`)]
    }],
    [1, () => {
      const f = g.name('f')
      return [s`const ${f}: ((x: number) => number) | undefined = ${g.bool(sc, 2)} ? (x: number) => x + 1 : undefined`, g.print(e('unknown')`${f}?.(${g.numLit()})`)]
    }],
    [1, () => [g.print(e('unknown')`[...${g.str(sc, 2)}, ...${a}]`), g.print(N`Math.max(...${a}, ${g.numLit()})`)]]
  ])())
  return out
}

function generators(g, sc) {
  const r = g.r
  const gen = g.top('gen')
  g.c.top.push(s`function* ${gen}(n: number): Generator<number, string, number | undefined> {
  let total = 0
  try {
    for (let i = 0; i < n; i++) {
      const got = yield i * ${g.smallInt(1, 3)}
      if (got !== undefined) total += got
    }
  } finally {
    p('cleanup ' + total)
  }
  return 'done ' + total
}`)
  const out = []
  for (let n = r.range(2, 4); n > 0; n--) out.push(...r.weighted([
    [2, () => {
      const it = g.name('it')
      return [s`const ${it} = ${gen}(${g.smallInt(0, 4)})`, g.print(e('unknown')`${it}.next()`), g.print(e('unknown')`${it}.next(${g.smallInt(0, 9)})`),
        g.print(e('unknown')`${r.chance(0.5) ? `${it}.return('early')` : `${it}.next()`}`), g.print(e('unknown')`${it}.next()`)]
    }],
    [2, () => [g.print(Nums`[...${gen}(${g.smallInt(0, 5)})]`)]],
    [2, () => [s`for (const v of ${gen}(${g.smallInt(1, 6)})) {
  if (v > ${g.smallInt(0, 4)}) break
  p(v)
}`]],
    [3, () => [g.print(e('unknown')`${gen}(${g.smallInt(2, 8)})${r.pick([
      '.map(x => x * 2).filter(x => x % 3 !== 0).toArray()',
      '.take(2).toArray()', '.drop(1).toArray()', '.reduce((a, b) => a + b, 0)',
      '.some(x => x > 3)', '.every(x => x >= 0)', '.find(x => x > 2)',
      '.flatMap(x => [x, -x]).toArray()', '.filter(x => x > 0).map(String).toArray()'])}`)]],
    [1, () => {
      const x = g.name('x'), y = g.name('y')
      return [s`const [${x} = -1, ${y} = -2] = ${gen}(${g.smallInt(0, 3)})`, s`p([${x}, ${y}])`]
    }],
    [1, () => {
      const deleg = g.top('deleg')
      g.c.top.push(s`function* ${deleg}(): Generator<number, number, undefined> {
  const r: string = yield* ${gen}(2)
  p(r)
  yield 100
  return 7
}`)
      return [g.print(Nums`Array.from(${deleg}())`)]
    }],
    [1, () => {
      const obj = g.name('it')
      return [s`const ${obj}: Iterable<number> = {
  [Symbol.iterator]() {
    let k = 0
    return {next: (): IteratorResult<number> => k < 3 ? {value: k++, done: false} : {value: undefined, done: true}}
  }
}`, g.print(Nums`[...${obj}]`), g.print(e('unknown')`Iterator.from(${obj}).map(x => x + 1).toArray()`)]
    }],
    [sc.async ? 2 : 0, () => {
      const ag = g.top('ag')
      g.c.top.push(s`async function* ${ag}(n: number): AsyncGenerator<number, void, undefined> {
  for (let i = 0; i < n; i++) {
    await null
    yield i
  }
}`)
      return [s`for await (const v of ${ag}(${g.smallInt(0, 4)})) p(v)`]
    }]
  ])())
  return out
}

function collections(g, sc) {
  g.feature('Map')
  g.feature('Set')
  const r = g.r
  const m = g.name('m'), st = g.name('st')
  const keys = ['0', '-0', 'NaN', '1', '2', 'Infinity', '0.5', '-1']
  const out = [s`const ${m} = new Map<number, string>()`, s`const ${st} = new Set<number>(${g.numsLit(sc, 1)})`]
  for (let n = r.range(3, 7); n > 0; n--) out.push(r.weighted([
    [4, () => s`${m}.set(${r.pick(keys)}, ${g.strLit()})`],
    [2, () => s`${st}.add(${r.pick(keys)})`],
    [2, () => g.print(e('unknown')`${m}.get(${r.pick(keys)})`)],
    [1, () => g.print(B`${m}.delete(${r.pick(keys)})`)],
    [1, () => g.print(B`${st}.has(${r.pick(keys)})`)],
    [2, () => g.print(e('unknown')`[...${m}.keys()]`)],
    [1, () => g.print(e('unknown')`${m}`)],
    [1, () => g.print(e('unknown')`${st}`)],
    [1, () => s`for (const [k, v] of ${m}) { if (k > 0) ${m}.delete(k); else ${m}.set(k + 10, v) ; if (${m}.size > 12) break }`],
    [1, () => g.print(e('unknown')`${st}.${r.pick(['union', 'intersection', 'difference', 'symmetricDifference'])}(new Set([0, 1, NaN]))`)],
    [1, () => g.print(B`${st}.isSubsetOf(new Set([0, 1, 2, NaN, 3]))`)],
    [1, () => g.print(e('unknown')`Map.groupBy(${g.numsLit(sc, 2)}, x => x % 2)`)],
    [1, () => g.print(e('unknown')`Object.groupBy(${g.numsLit(sc, 2)}, x => x > 1 ? 'big' : 'small')`)],
    [1, () => g.print(e('unknown')`structuredClone(${m})`)],
    [1, () => g.print(N`${m}.size + ${st}.size`)],
    [1, () => g.print(e('unknown')`[...${st}].map(x => Object.is(x, -0))`)]
  ])())
  return out
}

function json(g, sc) {
  const r = g.r
  const texts = ['{"a":1,"b":[1,2,{"c":null}],"d":"x"}', '[1e400,-0,0.1,1e21,12345678901234567890]',
    '"\\u00e9\\ud83d\\ude00"', '{"a":1,"a":2}', '[[[[]]]]', '{"":0," ":1,"1":2,"0":3}', '-0', '"\\ud800"', 'true', '[]']
  const out = []
  for (let n = r.range(2, 5); n > 0; n--) out.push(r.weighted([
    [3, () => g.print(Str`JSON.stringify(${g.any(sc, 1)})`)],
    [2, () => g.print(Str`JSON.stringify({x: ${g.num(sc, 2)}, y: [${g.num(sc, 2)}, undefined, () => 1], z: undefined, s: ${g.str(sc, 2)}}${r.chance(0.4) ? `, null, ${r.pick(['2', '"\\t"', '0', '12'])}` : ''})`)],
    [3, () => s`p(JSON.parse(${JSON.stringify(r.pick(texts))}))`],
    [2, () => s`p(JSON.stringify(JSON.parse(${JSON.stringify(r.pick(texts))})))`],
    [1, () => s`p(JSON.parse(${JSON.stringify(r.pick(texts))}, (k, v) => typeof v === 'number' ? v * 2 : v))`],
    [1, () => g.print(Str`JSON.stringify({b: 1, a: [2, 3], c: 'x'}, ['a', 'c'])`)],
    [1, () => s`try { p(JSON.parse(${JSON.stringify(r.pick(['{', '[1,]', "{'a':1}", '01', '"\\x"', '']))})) } catch (e) { p(e instanceof SyntaxError) }`],
    [1, () => {
      const o = g.name('o')
      return s`const ${o}: {self?: unknown, n: number[]} = {n: [1, -0]}; ${o}.self = ${o}; const ${o}c = structuredClone(${o}); p(${o}c.self === ${o}c); p(${o}c.n)`
    }],
    [1, () => g.print(e('unknown')`structuredClone(${g.expr(r.pick(['number', 'string', 'number[]', 'string[]']), sc, 1)})`)]
  ])())
  return out
}

function typedArrays(g, sc) {
  g.feature('TypedArray')
  const r = g.r
  const kinds = ['Uint8Array', 'Uint8ClampedArray', 'Int8Array', 'Int16Array', 'Uint16Array', 'Int32Array', 'Uint32Array', 'Float32Array', 'Float64Array']
  const t = g.name('t'), kind = r.pick(kinds)
  const values = '[' + Array.from({length: r.range(1, 6)}, () => r.pick(['300', '-1', '1.5', '2.5', '-2.5', '0.5', '255', '256', '-0', '1e40', '2147483648', '65535', '0.1', '-129', '127', '3'])).join(', ') + ']'
  const out = [s`const ${t} = new ${kind}(${values})`, g.print(e('unknown')`${t}`)]
  for (let n = r.range(2, 5); n > 0; n--) out.push(r.weighted([
    [2, () => g.print(e('unknown')`${t}.subarray(${g.smallInt(0, 2)})`)],
    [2, () => s`${t}[${g.smallInt(0, 3)}] = ${g.num(sc, 2)}`],
    [1, () => s`${t}.sort()`],
    [1, () => s`${t}.reverse()`],
    [1, () => g.print(e('unknown')`${t}.map(x => x * 2)`)],
    [1, () => g.print(N`${t}.reduce((a, b) => a + b, 0)`)],
    [1, () => s`try { ${t}.set([${g.numLit()}, 7], ${g.smallInt(0, 6)}) } catch (e) { p(e instanceof RangeError) }`],
    [kind.startsWith('Float') ? 0 : 2, () => g.print(e('unknown')`new Uint8Array(${t}.buffer)`)],
    [2, () => {
      const dv = g.name('dv')
      const off = g.smallInt(0, 4)
      const method = r.pick(['setInt16', 'setUint16', 'setInt32', 'setUint32', 'setFloat32', 'setInt8', 'setUint8'])
      return s`const ${dv} = new DataView(new ArrayBuffer(8)); ${dv}.${method}(${off}, Number(${g.num(sc, 2)}) || 0${method.endsWith('8') || !r.chance(0.5) ? '' : ', true'}); p([${dv}.getUint8(${off}), ${dv}.getInt16(0), ${dv}.getUint32(0, true), ${dv}.getFloat32(4)])`
    }],
    [1, () => s`try { new DataView(new ArrayBuffer(4)).getInt32(${g.smallInt(1, 4)}) } catch (e) { p(e instanceof RangeError) }`],
    [1, () => g.print(e('unknown')`${t}.slice(-2)`)],
    [1, () => g.print(e('unknown')`Array.from(${t}).map(x => Object.is(x, -0))`)],
    [1, () => g.print(e('unknown')`new Float64Array([${g.num(sc, 2)}, -0]).map(x => 1 / x)`)]
  ])())
  return out
}

function regexps(g, sc) {
  g.feature('RegExp')
  const r = g.r
  const res = ['/(?<y>\\d{4})-(?<m>\\d{2})/g', '/a+/g', '/(a)(b)?/', '/\\bw\\w*/gi', '/^\\s*(\\d+)/m', '/./gsu',
    '/(?<=\\$)\\d+/g', '/(\\w)\\1/', '/a*?/g', '/[\\u{1F600}]/u', '/\\p{Lu}/gu', '/x/y', '/(?:ab)+/d', '/[^a-c]/g', '/,\\s*/']
  const inputs = ['2024-02 and 1999-12', 'aaa baa caaa', 'abab', 'Word wide web', '  42 apples\n 7 pears', '😀a😀', '$12 and $7',
    'hello little', 'xxyx', 'ABcD', 'a, b,c ,  d', '']
  const re = g.name('re'), str = g.name('str')
  const out = [s`const ${re} = ${r.pick(res)}`, s`const ${str}: string = ${JSON.stringify(r.pick(inputs))}`]
  for (let n = r.range(2, 5); n > 0; n--) out.push(r.weighted([
    [3, () => s`{ const m = ${re}.exec(${str}); p(m === null ? null : [m.index, [...m], m.groups ?? null]); p(${re}.lastIndex) }`],
    [2, () => g.print(e('unknown')`${str}.match(${re})`)],
    [2, () => g.print(e('unknown')`[...${str}.matchAll(new RegExp(${re}.source, ${re}.flags.includes('g') ? ${re}.flags : ${re}.flags + 'g'))].map(m => [m.index, m[0]])`)],
    [2, () => g.print(Str`${str}.replace(${re}, ${JSON.stringify(r.pick(['<$&>', '$1', '[$<y>]', '$$', '$`', "$'"]))})`)],
    [1, () => g.print(Str`${str}.replace(${re}, (m: string, ...rest: unknown[]) => m.length + ':' + rest.length)`)],
    [1, () => g.print(e('unknown')`${str}.split(${re})`)],
    [2, () => s`p([${re}.test(${str}), ${re}.lastIndex, ${re}.test(${str}), ${re}.lastIndex])`],
    [1, () => g.print(e('unknown')`[${re}.flags, ${re}.source, ${re}.global, ${re}.sticky, ${re}.unicode]`)],
    [1, () => s`{ const m = /(?<w>o)(x)?/d.exec(${str}); p(m?.indices ?? null) }`],
    [1, () => s`${re}.lastIndex = ${g.smallInt(0, 5)}; p(${re}.exec(${str})?.index ?? -1)`],
    [1, () => g.print(e('unknown')`new RegExp(${g.str(sc, 2)}.replace(/[.*+?^\${}()|[\\]\\\\]/g, '\\\\$&'), 'g').exec(${str})`)]
  ])())
  return out
}

function dates(g, sc) {
  g.feature('Date')
  const r = g.r
  const d = g.name('d')
  const ms = r.pick(['0', '-1', '86400000', '1709210096789', '-62198755200000', '253402300799999', '253402300800000',
    '8640000000000000', '8640000000000001', '-8640000000000000', '951782400000', '1e12', '-0.5', '1.5', 'NaN'])
  const out = [s`const ${d} = new Date(${r.chance(0.6) ? ms : `Date.UTC(${r.range(-5, 2100)}, ${r.range(-2, 14)}, ${r.range(-1, 32)}, ${r.range(0, 25)}, ${r.range(0, 61)})`})`]
  for (let n = r.range(2, 5); n > 0; n--) out.push(r.weighted([
    [3, () => s`try { p(${d}.toISOString()) } catch (e) { p(e instanceof RangeError) }`],
    [2, () => g.print(e('unknown')`[${d}.getUTCFullYear(), ${d}.getUTCMonth(), ${d}.getUTCDate(), ${d}.getUTCDay(), ${d}.getUTCHours(), ${d}.getUTCMilliseconds()]`)],
    [2, () => s`${d}.${r.pick(['setUTCMonth', 'setUTCDate', 'setUTCHours', 'setUTCFullYear', 'setUTCMinutes', 'setUTCMilliseconds'])}(${g.num(sc, 2)})`],
    [1, () => g.print(Str`${d}.toUTCString()`)],
    [1, () => g.print(Str`JSON.stringify({${d}})`)],
    [1, () => g.print(N`${d}.getTime() - ${g.numLit()}`)],
    [1, () => g.print(N`Date.parse(${JSON.stringify(r.pick(['2020-01-01T00:00:00Z', '2020-01-01', '2020-01-01T12:30:00.123Z', '+002020-06-15T00:00:00Z', '1970-01-01T00:00:00.000+02:00']))})`)],
    [1, () => g.print(e('unknown')`${d}`)],
    [1, () => g.print(B`isNaN(${d}.getTime())`)]
  ])())
  return out
}
