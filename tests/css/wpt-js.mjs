// A static reader of WPT's test scripts: their calls' arguments as values,
// without running anything. It reads literals and expressions of them
// (+, -, *, ?:, ||, templates, members, spreads, join()), names bound once
// to one, and loops over a list it can read (`for (const x of list)`,
// `list.forEach(x => ...)`, destructured or not), a call taken once per
// item. What it can't read is reported with why.

const PUNCT = ['>>>=', '...', '===', '!==', '**=', '<<=', '>>=', '>>>', '&&=', '||=', '??=',
  '=>', '==', '!=', '<=', '>=', '&&', '||', '??', '?.', '++', '--', '+=', '-=', '*=', '/=', '%=',
  '&=', '|=', '^=', '**', '<<', '>>']
const BEFORE_REGEX = new Set(['return', 'typeof', 'case', 'do', 'else', 'in', 'of', 'new', 'delete', 'void', 'throw', 'instanceof'])
const METHODS = {
  join: (v, sep = ',') => Array.isArray(v) ? v.join(sep) : undefined,
  toUpperCase: v => typeof v === 'string' ? v.toUpperCase() : undefined,
  toLowerCase: v => typeof v === 'string' ? v.toLowerCase() : undefined,
  trim: v => typeof v === 'string' ? v.trim() : undefined,
  concat: (v, ...xs) => Array.isArray(v) || typeof v === 'string' ? v.concat(...xs) : undefined
}

export function tokenize(src) {
  const out = []
  let i = 0
  const regexAllowed = () => {
    const t = out[out.length - 1]
    if (!t) return true
    if (t.type === 'punct') return ![')', ']', '}'].includes(t.value)
    return t.type === 'name' && BEFORE_REGEX.has(t.value)
  }
  while (i < src.length) {
    const c = src[i]
    if (/\s/.test(c)) { i++; continue }
    if (src.startsWith('//', i) || src.startsWith('<!--', i) || src.startsWith('-->', i)) { i = lineEnd(src, i); continue }
    if (src.startsWith('/*', i)) { const e = src.indexOf('*/', i + 2); i = e < 0 ? src.length : e + 2; continue }
    if (c === '"' || c === "'") {
      let j = i + 1, s = ''
      while (j < src.length && src[j] !== c) {
        if (src[j] === '\\') { const [v, n] = escape(src, j); s += v; j = n } else s += src[j++]
      }
      out.push({type: 'string', value: s, at: i})
      i = j + 1
      continue
    }
    if (c === '`') {
      let j = i + 1, s = ''
      const parts = [], subs = []
      while (j < src.length && src[j] !== '`') {
        if (src.startsWith('${', j)) {
          let depth = 1, k = j + 2
          while (k < src.length && depth > 0) {
            if (src[k] === '{') depth++
            else if (src[k] === '}') depth--
            else if (src[k] === '`' || src[k] === '"' || src[k] === "'") k = skipString(src, k)
            k++
          }
          parts.push(s)
          subs.push(src.slice(j + 2, k - 1))
          s = ''
          j = k
          continue
        }
        if (src[j] === '\\') { const [v, n] = escape(src, j); s += v; j = n } else s += src[j++]
      }
      parts.push(s)
      out.push(subs.length ? {type: 'template', parts, subs, at: i} : {type: 'string', value: s, at: i})
      i = j + 1
      continue
    }
    if (/[0-9]/.test(c) || c === '.' && /[0-9]/.test(src[i + 1] ?? '')) {
      const m = /^(0[xX][0-9a-fA-F]+|0[bB][01]+|0[oO][0-7]+|(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?)n?/.exec(src.slice(i, i + 64))
      out.push({type: 'number', value: Number(m[0].replace(/n$/, '')), at: i})
      i += m[0].length
      continue
    }
    if (/[A-Za-z_$\u0080-￿]/.test(c)) {
      const m = /^[A-Za-z0-9_$\u0080-￿]+/.exec(src.slice(i, i + 256))
      out.push({type: 'name', value: m[0], at: i})
      i += m[0].length
      continue
    }
    if (c === '/' && regexAllowed()) {
      let j = i + 1, klass = false
      while (j < src.length && (src[j] !== '/' || klass) && src[j] !== '\n') {
        if (src[j] === '\\') j++
        else if (src[j] === '[') klass = true
        else if (src[j] === ']') klass = false
        j++
      }
      j++
      while (/[a-z]/.test(src[j] ?? '')) j++
      out.push({type: 'regex', value: src.slice(i, j), at: i})
      i = j
      continue
    }
    const p = PUNCT.find(p => src.startsWith(p, i)) ?? c
    out.push({type: 'punct', value: p, at: i})
    i += p.length
  }
  return out
}

function skipString(src, k) {
  const q = src[k]
  for (k++; k < src.length && src[k] !== q; k++) if (src[k] === '\\') k++
  return k
}

function lineEnd(src, i) {
  const e = src.indexOf('\n', i)
  return e < 0 ? src.length : e
}

function escape(src, j) {
  const c = src[j + 1]
  const simple = {n: '\n', t: '\t', r: '\r', b: '\b', f: '\f', v: '\v', 0: '\0'}
  if (c in simple && !(c === '0' && /[0-9]/.test(src[j + 2]))) return [simple[c], j + 2]
  if (c === 'x') return [String.fromCharCode(parseInt(src.slice(j + 2, j + 4), 16)), j + 4]
  if (c === 'u') {
    if (src[j + 2] === '{') {
      const e = src.indexOf('}', j)
      return [String.fromCodePoint(parseInt(src.slice(j + 3, e), 16)), e + 1]
    }
    return [String.fromCharCode(parseInt(src.slice(j + 2, j + 6), 16)), j + 6]
  }
  if (c === '\r' && src[j + 2] === '\n') return ['', j + 3]
  if (c === '\n' || c === '\r') return ['', j + 2]
  return [c, j + 2]
}

class Unreadable extends Error {}

const isPunct = (x, v) => x?.type === 'punct' && x.value === v

// The value of tokens[from, to), or Unreadable (its message: why).
function evaluate(t, from, to, env) {
  let i = from
  const peek = () => i < to ? t[i] : null
  const is = v => isPunct(peek(), v)
  const next = () => i < to ? t[i++] : null
  const expect = v => {
    if (!is(v)) throw new Unreadable(`expected ${v}`)
    i++
  }
  const lookup = name => {
    if (env.has(name)) return env.get(name)
    throw new Unreadable(`a name not bound to a literal (${name})`)
  }
  const list = close => {
    const out = []
    while (!is(close)) {
      if (!peek()) throw new Unreadable('an unclosed list')
      if (is(',')) { next(); out.push(undefined); continue }
      if (is('...')) {
        next()
        const v = conditional()
        if (!Array.isArray(v)) throw new Unreadable('a spread of no list')
        out.push(...v)
      } else out.push(conditional())
      if (is(',')) next()
    }
    next()
    return out
  }
  const primary = () => {
    const x = next()
    if (!x) throw new Unreadable('nothing')
    if (x.type === 'string' || x.type === 'number') return x.value
    if (x.type === 'template') return x.parts.reduce((s, p, k) => s + p + (k < x.subs.length ? text(sub(x.subs[k], env)) : ''), '')
    if (isPunct(x, '(')) {
      const v = conditional()
      expect(')')
      return v
    }
    if (isPunct(x, '[')) return list(']')
    if (isPunct(x, '{')) {
      const out = {}
      while (!is('}')) {
        if (is('...')) {
          next()
          Object.assign(out, conditional())
        } else {
          const k = next()
          if (!k || !['name', 'string', 'number'].includes(k.type)) throw new Unreadable('a computed key')
          if (is(',') || is('}')) out[k.value] = lookup(k.value)
          else {
            expect(':')
            out[k.value] = conditional()
          }
        }
        if (is(',')) next()
      }
      next()
      return out
    }
    if (x.type === 'name') {
      const words = {null: null, undefined: undefined, true: true, false: false, Infinity: Infinity, NaN: NaN}
      if (x.value in words) return words[x.value]
      return lookup(x.value)
    }
    throw new Unreadable(`${x.type} ${x.value}`)
  }
  const member = (v, k) => {
    if (v == null || typeof v !== 'object' && typeof v !== 'string') throw new Unreadable('a member of no object')
    return v[k]
  }
  const postfix = () => {
    let v = primary()
    while (true) {
      if (is('[')) {
        next()
        const k = conditional()
        expect(']')
        v = member(v, k)
      } else if (is('.') || is('?.')) {
        next()
        const name = next()
        if (name?.type !== 'name') throw new Unreadable('a member')
        if (is('(')) {
          if (!METHODS[name.value]) throw new Unreadable(`a call of ${name.value}()`)
          next()
          const r = METHODS[name.value](v, ...list(')'))
          if (r === undefined) throw new Unreadable(`${name.value}() of that`)
          v = r
        } else v = member(v, name.value)
      } else if (is('(')) throw new Unreadable('a call')
      else return v
    }
  }
  const unary = () => {
    if (is('-')) { next(); return -unary() }
    if (is('+')) { next(); return +unary() }
    if (is('!')) { next(); return !unary() }
    if (peek()?.value === 'typeof' || peek()?.value === 'new') throw new Unreadable(peek().value)
    return postfix()
  }
  const product = () => {
    let v = unary()
    while (is('*') || is('/') || is('%')) {
      const op = next().value, w = unary()
      v = op === '*' ? v * w : op === '/' ? v / w : v % w
    }
    return v
  }
  const sum = () => {
    let v = product()
    while (is('+') || is('-')) {
      const op = next().value, w = product()
      v = op === '+' ? v + w : v - w
    }
    return v
  }
  const bits = () => {
    let v = sum()
    while (is('|')) { next(); v = v | sum() }
    return v
  }
  const compare = () => {
    let v = bits()
    while (['===', '!==', '==', '!=', '<', '>', '<=', '>='].some(is)) {
      const op = next().value, w = bits()
      v = {'===': v === w, '==': v === w, '!==': v !== w, '!=': v !== w, '<': v < w, '>': v > w, '<=': v <= w, '>=': v >= w}[op]
    }
    return v
  }
  const logical = () => {
    let v = compare()
    while (is('||') || is('&&') || is('??')) {
      const op = next().value, w = compare()
      v = op === '||' ? v || w : op === '&&' ? v && w : v ?? w
    }
    return v
  }
  const conditional = () => {
    const c = logical()
    if (!is('?')) return c
    next()
    const a = conditional()
    expect(':')
    const b = conditional()
    return c ? a : b
  }
  const v = conditional()
  if (i < to) throw new Unreadable(`an expression (${t[i].value})`)
  return v
}

// (a substitution of undefined is a helper's argument left out: not a test's value)
function text(v) {
  if (v === undefined) throw new Unreadable('undefined in a template')
  return String(v)
}

function sub(src, env) {
  const t = tokenize(src)
  return evaluate(t, 0, t.length, env)
}

// The index of the token closing the bracket at `open`.
function closing(t, open) {
  let depth = 0
  for (let k = open; k < t.length; k++) {
    if (t[k].type !== 'punct') continue
    if (['(', '[', '{'].includes(t[k].value)) depth++
    else if ([')', ']', '}'].includes(t[k].value) && --depth === 0) return k
  }
  return t.length
}

// The index of the token opening the bracket closed at `close`.
function opening(t, close) {
  let depth = 0
  for (let k = close; k >= 0; k--) {
    if (t[k].type !== 'punct') continue
    if ([')', ']', '}'].includes(t[k].value)) depth++
    else if (['(', '[', '{'].includes(t[k].value) && --depth === 0) return k
  }
  return -1
}

// Top-level comma-separated spans of t(open, close).
function spans(t, open, close) {
  const out = []
  let start = open + 1, depth = 0
  for (let k = open + 1; k < close; k++) {
    const v = t[k].type === 'punct' ? t[k].value : null
    if (v === '(' || v === '[' || v === '{') depth++
    else if (v === ')' || v === ']' || v === '}') depth--
    else if (v === ',' && depth === 0) { out.push([start, k]); start = k + 1 }
  }
  if (start < close) out.push([start, close])
  return out
}

// The end of the expression starting at k: a top-level ; , or closer, or a
// new line where automatic semicolon insertion ends it.
function expressionEnd(t, k, src) {
  let depth = 0
  for (let end = k; end < t.length; end++) {
    const v = t[end].type === 'punct' ? t[end].value : null
    if (v === '(' || v === '[' || v === '{') depth++
    else if (v === ')' || v === ']' || v === '}') { if (depth-- === 0) return end }
    else if ((v === ';' || v === ',') && depth === 0) return end
    else if (depth === 0 && end > k && t[end].type === 'name' && t[end - 1].type !== 'punct'
      && src.slice(t[end - 1].at, t[end].at).includes('\n')) return end
  }
  return t.length
}

function statementEnd(t, k) {
  if (isPunct(t[k], '{')) return closing(t, k)
  let depth = 0
  for (; k < t.length; k++) {
    const v = t[k].type === 'punct' ? t[k].value : null
    if (v === '(' || v === '[' || v === '{') depth++
    else if (v === ')' || v === ']' || v === '}') depth--
    else if (v === ';' && depth === 0) return k
  }
  return k
}

// The names src binds once, to something it can read: `const v = '...'`,
// `var list = [...]`, `tests = [...]`.
export function bindings(src, t = tokenize(src)) {
  const env = new Map(), assigned = new Map()
  for (let k = 0; k + 1 < t.length; k++)
    if (t[k].type === 'name' && t[k + 1].type === 'punct' && ['=', '+=', '-=', '++', '--', '||=', '??='].includes(t[k + 1].value) && !isPunct(t[k - 1], '.'))
      assigned.set(t[k].value, (assigned.get(t[k].value) ?? 0) + 1)
  for (let k = 0; k + 2 < t.length; k++) {
    const declared = ['const', 'let', 'var'].includes(t[k].value)
    const n = declared ? k + 1 : k
    if (t[n].type !== 'name' || !isPunct(t[n + 1], '=') || assigned.get(t[n].value) !== 1) continue
    // (a bare `name = ...` only where a statement starts)
    if (!declared && k > 0 && !['name', 'punct'].includes(t[k - 1].type)) continue
    if (!declared && k > 0 && t[k - 1].type === 'name' && !src.slice(t[k - 1].at, t[k].at).includes('\n')) continue
    if (!declared && k > 0 && t[k - 1].type === 'punct' && ![';', '}', '{'].includes(t[k - 1].value)) continue
    const end = expressionEnd(t, n + 2, src)
    try { env.set(t[n].value, evaluate(t, n + 2, end, env)) } catch (e) { if (!(e instanceof Unreadable)) throw e }
  }
  return env
}

// A loop's variable pattern at k: a name, [a, b] or {a, b}; [pattern, next index].
function pattern(t, k) {
  if (t[k]?.type === 'name') return [{name: t[k].value}, k + 1]
  if (isPunct(t[k], '[') || isPunct(t[k], '{')) {
    const close = closing(t, k), names = []
    for (const [a, z] of spans(t, k, close)) {
      if (z - a !== 1 || t[a].type !== 'name') return [null, close + 1]
      names.push(t[a].value)
    }
    return [isPunct(t[k], '[') ? {items: names} : {keys: names}, close + 1]
  }
  return [null, k + 1]
}

function bind(p, v, into) {
  const b = new Map(into)
  if (p.name) b.set(p.name, v)
  else if (p.items) p.items.forEach((n, k) => b.set(n, v?.[k]))
  else for (const n of p.keys) b.set(n, v?.[n])
  return b
}

// Loops: {pattern, items: [from, to) of the list's expression, from, to: the body}.
function loops(t) {
  const out = []
  for (let k = 0; k + 5 < t.length; k++) {
    if (t[k].value === 'for' && isPunct(t[k + 1], '(')) {
      const head = closing(t, k + 1)
      const start = ['const', 'let', 'var'].includes(t[k + 2].value) ? k + 3 : k + 2
      const [p, after] = pattern(t, start)
      if (!p || t[after]?.value !== 'of') continue
      out.push({pattern: p, items: [after + 1, head], from: head + 1, to: statementEnd(t, head + 1)})
    }
    if (t[k].value === 'forEach' && isPunct(t[k - 1], '.') && isPunct(t[k + 1], '(')) {
      let start = k - 2
      if (t[start]?.type === 'punct' && [']', ')'].includes(t[start].value)) start = opening(t, start)
      else if (t[start]?.type !== 'name') continue
      const call = closing(t, k + 1)
      const [p, after] = t[k + 2].value === 'function' ? pattern(t, k + 4) : isPunct(t[k + 2], '(') ? pattern(t, k + 3) : pattern(t, k + 2)
      if (!p) continue
      out.push({pattern: p, items: [start, k - 1], from: after, to: call})
    }
  }
  return out
}

// Every call of one of `names` in src, once per loop item and per call of
// the helper it is in (a named function, its parameters bound to the
// call's arguments): {name, args, at}, or {name, args, errors: [{index,
// why}], at} for the arguments it couldn't read.
export function calls(src, names) {
  const t = tokenize(src)
  const env = bindings(src, t), all = loops(t)
  const helpers = []
  for (let k = 0; k + 2 < t.length; k++) {
    if (t[k].value !== 'function' || t[k + 1].type !== 'name' || !isPunct(t[k + 2], '(')) continue
    const head = closing(t, k + 2)
    if (!isPunct(t[head + 1], '{')) continue
    const params = spans(t, k + 2, head).map(([a, z]) => t[a].type === 'name' ? {name: t[a].value, init: isPunct(t[a + 1], '=') ? [a + 2, z] : null} : null)
    // (`if (arguments.length < n) a = b`: a parameter's default from another)
    const defaults = []
    for (let j = head + 1; j + 10 < closing(t, head + 1); j++)
      if (t[j].value === 'if' && t[j + 2]?.value === 'arguments' && t[j + 4]?.value === 'length' && isPunct(t[j + 5], '<')
        && t[j + 6].type === 'number' && isPunct(t[j + 7], ')') && t[j + 8].type === 'name' && isPunct(t[j + 9], '=') && t[j + 10].type === 'name')
        defaults.push({count: t[j + 6].value, name: t[j + 8].value, from: t[j + 10].value})
    helpers.push({name: t[k + 1].value, params, defaults, from: head + 1, to: closing(t, head + 1), sites: []})
  }
  const isCall = k => t[k].type === 'name' && isPunct(t[k + 1], '(') && !(t[k - 1] && (t[k - 1].value === 'function' || isPunct(t[k - 1], '.')))
  for (let k = 0; k + 1 < t.length; k++) if (isCall(k)) {
    const h = helpers.find(h => h.name === t[k].value)
    if (h && !(h.from < k && k < h.to)) h.sites.push(k)
  }
  // (the scopes a token is read in: [{scope}] or [{why}])
  const scopes = (k, depth) => {
    const helper = helpers.filter(h => h.from < k && k < h.to).sort((a, b) => b.from - a.from)[0]
    let bases = [{scope: env}]
    if (helper) {
      if (depth > 3 || !helper.sites.length || helper.params.includes(null)) return [{why: `in a helper (${helper.name})`}]
      bases = helper.sites.flatMap(site => scopes(site, depth + 1).map(b => {
        if (b.why) return b
        const args = spans(t, site + 1, closing(t, site + 1))
        try {
          const bound = new Map(b.scope)
          helper.params.forEach((p, i) => {
            let v = args[i] ? evaluate(t, args[i][0], args[i][1], b.scope) : undefined
            if (v === undefined && p.init) v = evaluate(t, p.init[0], p.init[1], bound)
            bound.set(p.name, v)
          })
          for (const d of helper.defaults) if (args.length < d.count) bound.set(d.name, bound.get(d.from))
          return {scope: bound}
        } catch (e) {
          if (!(e instanceof Unreadable)) throw e
          return {why: `in a helper (${helper.name})`}
        }
      }))
    }
    const around = all.filter(l => l.from <= k && k < l.to && (!helper || l.from > helper.from)).sort((a, b) => a.from - b.from)
    for (const l of around)
      bases = bases.flatMap(b => {
        if (b.why) return [b]
        try {
          const items = evaluate(t, l.items[0], l.items[1], b.scope)
          if (Array.isArray(items)) return items.map(v => ({scope: bind(l.pattern, v, b.scope)}))
          return [{why: 'a loop over no list'}]
        } catch (e) {
          if (!(e instanceof Unreadable)) throw e
          return [{why: "a loop over what it can't read"}]
        }
      })
    return bases
  }
  const out = []
  for (let k = 0; k + 1 < t.length; k++) {
    if (!names.has(t[k].value) || !isCall(k)) continue
    const args = spans(t, k + 1, closing(t, k + 1))
    for (const s of scopes(k, 0)) {
      const errors = []
      const values = args.map(([a, z], index) => {
        if (s.why) return void errors.push({index, why: s.why})
        try { return evaluate(t, a, z, s.scope) } catch (e) {
          if (!(e instanceof Unreadable)) throw e
          errors.push({index, why: e.message})
        }
      })
      out.push(errors.length ? {name: t[k].value, args: values, errors, at: t[k].at} : {name: t[k].value, args: values, at: t[k].at})
    }
  }
  return out
}
