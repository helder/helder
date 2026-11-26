// A generated program: cases, each a tree of statements and expressions
// (parts: text, nodes, blocks), printed as TypeScript. A case's top-level
// declarations name themselves with § (its prefix, c<id>_), so a case
// printed twice under two ids is two independent cases (the shrinker's
// candidates share a program).

export const e = t => (strings, ...values) => ({t, parts: weave(strings, values)})
export const s = (strings, ...values) => ({parts: weave(strings, values)})
export const block = stmts => ({block: stmts})
export const lit = (t, text) => ({t, parts: [String(text)], lit: true})

function weave(strings, values) {
  const parts = [strings[0]]
  values.forEach((v, i) => {
    if (typeof v === 'string' || typeof v === 'number') parts[parts.length - 1] += v
    else parts.push(v, '')
    parts[parts.length - 1] += strings[i + 1]
  })
  return parts.filter(p => p !== '')
}

// the printer's parts each feature needs (their globals installed only
// where a program uses them: helder's Features)
const SHOW = {
  Map: `  if (v instanceof Map) {
    const items: string[] = []
    for (const [k, x] of v) items.push(show(k, d + 1) + ' => ' + show(x, d + 1))
    return 'Map{' + items.join(', ') + '}'
  }`,
  Set: `  if (v instanceof Set) {
    const items: string[] = []
    for (const x of v) items.push(show(x, d + 1))
    return 'Set{' + items.join(', ') + '}'
  }`,
  Date: `  if (v instanceof Date) return 'Date(' + v.getTime() + ')'`,
  RegExp: `  if (v instanceof RegExp) return String(v) + '@' + v.lastIndex`,
  TypedArray: `  if (v instanceof DataView) return 'DataView(' + v.byteLength + ')'
  if (v instanceof ArrayBuffer) return 'ArrayBuffer(' + v.byteLength + ')'
  if (ArrayBuffer.isView(v)) return Object.getPrototypeOf(v).constructor.name + show(Array.prototype.slice.call(v), d)`
}

const TYPES = {
  M: `type M = number & {__brand: 'm'}`,
  S: `type S = string & {__brand: 's'}`,
  Rec: `type Rec = {a: number, b: string, n: number[]}`,
  Opt: `type Opt = {a?: number, b?: string, c?: Opt}`
}

// (plain: a regression test's, no harness, each value on a line of its own)
export function prelude(features, plain = false) {
  const show = Object.keys(SHOW).filter(f => features.has(f)).map(f => SHOW[f])
  const harness = `let cur = ''
let seq = 0
function p(v: unknown): void {
  console.log(cur + '.' + (++seq) + ' ' + show(v))
}
function start(name: string): void {
  cur = name
  seq = 0
  console.log('# ' + name)
}
function fail(e: unknown): void {
  const m = e instanceof Error ? e.message : ''
  const k = m.indexOf(': TSHX100')
  if (k >= 0) console.log(cur + '! TSHX100 L' + m.slice(m.lastIndexOf(':', k - 1) + 1, k))
  else if (e instanceof Error) console.log(cur + '! ' + e.name + (m.startsWith('u:') ? ' ' + m : ''))
  else console.log(cur + '! ' + show(e))
}`
  return [
    ...Object.keys(TYPES).filter(f => features.has(f)).map(f => TYPES[f]),
    `function show(v: unknown, d: number = 0): string {
  if (typeof v === 'number') return Object.is(v, -0) ? '-0' : String(v)
  if (typeof v === 'string') return JSON.stringify(v)
  if (typeof v === 'function') return 'fn ' + v.name
  if (typeof v === 'symbol') return v.toString()
  if (typeof v !== 'object' || v === null) return String(v)
  if (d > 3) return '..'
  if (Array.isArray(v)) {
    const items: string[] = []
    for (let i = 0; i < v.length; i++) items.push(i in v ? show(v[i], d + 1) : '_')
    return '[' + items.join(', ') + ']'
  }
${show.join('\n')}${show.length ? '\n' : ''}  if (v instanceof Error) return v.name + ': ' + v.message
  const proto = Object.getPrototypeOf(v)
  const name: string = proto === null ? 'null' : proto === Object.prototype ? '' : String(proto.constructor?.name)
  const items: string[] = []
  for (const [k, x] of Object.entries(v)) items.push(k + ': ' + show(x, d + 1))
  return name + '{' + items.join(', ') + '}'
}`,
    ...features.has('cmp') ? [`// (a consistent order, NaN last: x - y with a NaN is no order, and the
// engine's sort may put them anywhere)
function cmp(x: number, y: number): number {
  return Number.isNaN(x) ? (Number.isNaN(y) ? 0 : 1) : Number.isNaN(y) ? -1 : x < y ? -1 : x > y ? 1 : 0
}`] : [],
    plain ? `function p(v: unknown): void {
  console.log(show(v))
}` : harness]
}

// the program's text, each case's lines (for a compiler's error at a
// line) and each lie's line
export function emit(cases, {plain = false} = {}) {
  const features = new Set(cases.flatMap(c => [...c.features]))
  const async = cases.some(c => c.async)
  const lines = []
  const add = text => {for (const l of text.split('\n')) lines.push(l)}
  if (cases.some(c => [...c.top, ...c.body].some(st => render(st, 0, c).includes('cmp')))) features.add('cmp')
  for (const t of prelude(features, plain)) add(t)
  const ranges = new Map(), lies = new Map()
  const range = id => ranges.get(id) ?? ranges.set(id, []).get(id)
  for (const c of cases) {
    const from = lines.length + 1
    for (const st of c.top) statement(st, 0, c, lines, lies)
    range(c.id).push([from, lines.length])
  }
  for (const c of cases) {
    const from = lines.length + 1
    lines.push(`${c.async ? 'async ' : ''}function c${c.id}(): ${c.async ? 'Promise<void>' : 'void'} {`)
    for (const st of c.body) statement(st, 1, c, lines, lies)
    lines.push('}')
    range(c.id).push([from, lines.length])
  }
  if (plain) {
    if (async) lines.push('async function main(): Promise<void> {', ...cases.map(c => `  ${c.async ? 'await ' : ''}c${c.id}()`), '}', 'main()')
    else for (const c of cases) lines.push(`c${c.id}()`)
    lines.push('export {}', '')
    return {text: lines.join('\n'), ranges, lies}
  }
  lines.push(`${async ? 'async ' : ''}function main(): ${async ? 'Promise<void>' : 'void'} {`)
  for (const c of cases)
    lines.push(`  start('c${c.id}')`, `  try { ${c.async ? 'await ' : ''}c${c.id}() } catch (e) { fail(e) }`)
  // (a module: strict, as helder's programs are)
  lines.push('}', 'main()', 'export {}', '')
  return {text: lines.join('\n'), ranges, lies}
}

function statement(st, depth, c, lines, lies) {
  const text = '  '.repeat(depth) + render(st, depth, c)
  if (st.lie) lies.set(c.id, lines.length + 1)
  for (const l of text.split('\n')) lines.push(l)
}

export function render(node, depth, c) {
  if (typeof node === 'string') return node.replaceAll('§', `c${c.id}_`)
  if (node.block) {
    if (node.block.length === 0) return '{}'
    const inner = node.block.map(st => '  '.repeat(depth + 1) + render(st, depth + 1, c))
    return '{\n' + inner.join('\n') + '\n' + '  '.repeat(depth) + '}'
  }
  return node.parts.map(p => render(p, depth, c)).join('')
}

// a case's size (the shrinker's order): its nodes
export function size(node) {
  if (typeof node === 'string') return 0
  if (node.block) return node.block.reduce((n, st) => n + size(st), 1)
  if (node.top) return node.top.reduce((n, st) => n + size(st), 0) + node.body.reduce((n, st) => n + size(st), 0)
  return node.parts.reduce((n, p) => n + size(p), 1)
}
