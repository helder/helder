import fs from 'node:fs'
import path from 'node:path'
import {spawnSync} from 'node:child_process'
import {Server} from '../typescript/fuzz/Server.mjs'
import {execute} from '../typescript/fuzz/Runner.mjs'

// test262 (tc39's conformance suite) through helder's frontend as plain
// JavaScript (dynamic paths), natively: the pinned checkout in bin/test262,
// never vendored; manifest.json the gate (README.md).
//
//   node tests/test262/run.mjs [part of a path...]   (BLESS=1 writes the manifest)
//
// A program is a directory's tests in batches: the harness once, each test
// a function of its own called with the global this, the built-ins
// restored after it (propertyHelper's verifyProperty deletes what it
// checks), a line per test. node runs each batch first: a test that fails
// there fails the wrapping, not helder, and is set aside. A batch helder
// does not build is built test by test; a crash or a hang ends the test
// that started last, and the batch's rest runs again.

const REVISION = '4db99ac4dc8924279ae07ed3246385924e878519'
const SCOPE = ['Array', 'String', 'Object', 'JSON', 'Map', 'Set', 'Promise', 'Math', 'Number'].map(d => `test/built-ins/${d}`)
const BATCH = 120
const root = path.resolve('bin/test262/checkout'), work = path.resolve('bin/test262/work')
const here = 'tests/test262', manifestPath = `${here}/manifest.json`
const filters = process.argv.slice(2)
const bless = process.env.BLESS === '1'

// features and flags outside helder's scope (or a realm's): never run
const FEATURES = new Set(['Temporal', 'BigInt', 'Intl', 'SharedArrayBuffer', 'Atomics', 'Atomics.waitAsync', 'Atomics.pause',
  'ShadowRealm', 'WeakRef', 'FinalizationRegistry', 'cross-realm', 'explicit-resource-management', 'resizable-arraybuffer',
  'import-defer', 'source-phase-imports', 'regexp-modifiers', 'decorators', 'Proxy', 'Reflect.setPrototypeOf', '__proto__',
  'dynamic-import', 'tail-call-optimization', 'IsHTMLDDA', 'host-gc-required', 'array-grouping', 'Math.sumPrecise',
  'upsert', 'iterator-sequencing', 'joint-iteration', 'immutable-arraybuffer', 'uint8array-base64', 'canonical-tz',
  'json-parse-with-source', 'Array.fromAsync'])
const BUILTINS = '(?:Array|Object|String|Number|Boolean|Math|JSON|Function|Map|Set|Promise|Symbol|RegExp|Date|Error|Iterator|Reflect)'
const BUILTIN_WRITE = new RegExp(`(?:\\bdelete\\s+${BUILTINS}\\b[.\\[]|(?<![\\w.$])${BUILTINS}(?:\\.prototype)?(?:\\.[\\w$]+|\\[[^\\]]+\\])\\s*(?:[-+*/%&|^]|<<|>>>?|\\*\\*|&&|\\|\\||\\?\\?)?=(?!=))`)
const FLAGS = new Set(['noStrict', 'raw', 'CanBlockIsFalse', 'CanBlockIsTrue'])
const HARNESS_OUT = new Set(['detachArrayBuffer.js', 'nativeFunctionMatcher.js', 'wellKnownIntrinsicObjects.js',
  'proxyTrapsHelper.js', 'testIntl.js', 'testAtomics.js', 'temporalHelpers.js', 'resizableArrayBufferUtils.js', 'atomicsHelper.js'])
// (fnGlobalObject.js makes the global by Function("return this"): helder has no Function)
const SHIMS = {'fnGlobalObject.js': 'function fnGlobalObject() {\n  return globalThis;\n}\n'}

checkout()
const tests = collect()
const manifest = fs.existsSync(manifestPath) ? JSON.parse(fs.readFileSync(manifestPath, 'utf8')).cases : {}
const results = new Map()
for (const t of tests) if (t.skip) results.set(t.id, {status: 'skipped', why: t.skip})
const runnable = tests.filter(t => !t.skip && (!filters.length || filters.some(f => t.id.includes(f))))
console.log(`test262 ${REVISION.slice(0, 8)}: ${tests.length} tests in scope's directories, ${tests.filter(t => t.skip).length} out of scope, ${runnable.length} to run`)

fs.mkdirSync(work, {recursive: true})
const built = spawnSync(process.execPath, ['src/helder/compiler/build.mjs', '--quiet'], {encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit']})
if (built.status !== 0) process.exit(1)
const server = await Server.start(built.stdout.trim(), process.cwd())
const t0 = Date.now()
let builds = 0
try {
  const groups = new Map()
  for (const t of runnable) {
    const dir = path.dirname(t.id)
    groups.set(dir, [...(groups.get(dir) ?? []), t])
  }
  let done = 0
  for (const [dir, list] of groups) {
    for (let i = 0; i < list.length; i += BATCH) await batch(list.slice(i, i + BATCH), dir)
    done += list.length
    console.log(`${dir}: ${list.filter(t => results.get(t.id)?.status === 'pass').length}/${list.length} (${done}/${runnable.length}, ${Math.round((Date.now() - t0) / 1000)} s)`)
  }
} finally {
  server.stop()
}
console.log(`test262: ${runnable.length} tests in ${Math.round((Date.now() - t0) / 1000)} s, ${builds} builds`)
process.exit(report())

// the tests of a batch: node's verdicts, then helder's (built whole, else one by one)
async function batch(list, dir) {
  const name = dir.replace(/[^\w]+/g, '_')
  const reference = await runNode(list, name)
  const judged = list.filter(t => {
    if (reference.get(t.id) === 'pass') return true
    results.set(t.id, {status: 'wrapper', why: `fails under node in this wrapping: ${reference.get(t.id) ?? 'not run'}`})
    return false
  })
  let pending = judged
  while (pending.length) {
    const r = await runHelder(pending, name)
    // (refused at a test's line: that test alone set aside, the rest built again)
    if (r.refused && r.at.length) {
      for (const t of r.at) results.set(t.id, {status: 'refused', why: r.refused})
      pending = pending.filter(t => !r.at.includes(t))
      continue
    }
    if (r.refused) {
      if (pending.length === 1) {
        results.set(pending[0].id, {status: 'refused', why: r.refused})
        return
      }
      // (a build that fails: each test on its own, so one refusal hides no other)
      for (const t of pending) await batchOne(t, name)
      return
    }
    for (const [id, v] of r.verdicts) results.set(id, v)
    pending = pending.filter(t => !results.has(t.id))
  }
}

async function batchOne(t, name) {
  const r = await runHelder([t], name + '_one')
  results.set(t.id, r.refused ? {status: 'refused', why: r.refused} : r.verdicts.get(t.id) ?? {status: 'crash', why: 'no verdict'})
}

async function runNode(list, name) {
  const file = path.join(work, `${name}.mjs`)
  fs.writeFileSync(file, program(list))
  const r = await execute(process.execPath, ['--no-warnings', file], 120000)
  const out = new Map()
  for (const [id, v] of verdicts(list, r)) out.set(id, v.status === 'pass' ? 'pass' : `${v.status} ${v.why ?? ''}`.trim())
  return out
}

async function runHelder(list, name) {
  const file = path.join(work, `${name}.mjs`), exe = path.join(work, name)
  const text = program(list)
  fs.writeFileSync(file, text)
  builds++
  const b = await server.build(file, exe)
  if (!b.ok) {
    // (the tests at the lines the messages name)
    const lines = text.split('\n'), starts = []
    lines.forEach((l, i) => {
      const m = /^function __test(\d+)\(\) \{$/.exec(l)
      if (m) starts.push([i + 1, Number(m[1])])
      else if (l.startsWith('const __tests = ')) starts.push([i + 1, -1])
    })
    const at = new Set()
    for (const m of b.messages.matchAll(/\.mjs:(\d+):/g)) {
      const line = Number(m[1])
      const s = starts.filter(([from]) => from <= line).pop()
      if (s && s[1] >= 0) at.add(list[s[1]])
    }
    return {refused: firstLine(b.messages) || 'the build failed', at: [...at]}
  }
  const r = await execute(exe, [], 120000)
  fs.rmSync(exe, {force: true})
  return {verdicts: verdicts(list, r)}
}

// each test's verdict from a run's lines: pass, fail (its error), and for the
// test that started last in a run that crashed or hung, that
function verdicts(list, run) {
  const out = new Map()
  let last = null
  for (const line of run.stdout.split('\n')) {
    const m = /^([#PF]) (\d+)(?: (.*))?$/.exec(line)
    if (!m) continue
    const t = list[Number(m[2])]
    if (!t) continue
    if (m[1] === '#') last = t
    else out.set(t.id, m[1] === 'P' ? {status: 'pass'} : {status: 'fail', why: m[3] ?? ''})
  }
  if (last && !out.has(last.id))
    out.set(last.id, run.hung ? {status: 'hang', why: 'past 120 s'} : {status: 'crash', why: `${run.signal ?? 'exit ' + run.status}: ${firstLine(run.stderr)}`})
  return out
}

// a batch's program: the harness its tests include, once; each test a
// function; the built-ins as they were restored after each
function program(list) {
  const includes = ['assert.js', 'sta.js']
  for (const t of list) for (const i of t.includes) if (!includes.includes(i)) includes.push(i)
  const harness = includes.map(i => SHIMS[i] ?? fs.readFileSync(path.join(root, 'harness', i), 'utf8'))
  const async = list.some(t => t.async)
  const body = list.map((t, i) => `function __test${i}() {\n${t.source}\n}`)
  return `${harness.join('\n')}
let $DONE = undefined
${prelude()}
${body.join('\n')}
const __tests = [${list.map((_, i) => `__test${i}`).join(', ')}]
const __negative = ${JSON.stringify(list.map(t => t.negative ?? null))}
const __async = ${JSON.stringify(list.map(t => t.async))}
${async ? 'async ' : ''}function __main() {
  for (let i = 0; i < __tests.length; i++) {
    console.log('# ' + i)
    ${async ? `if (__async[i]) {
      await new Promise(res => {
        let over = false
        const timer = setTimeout(() => finish(new Error('$DONE not called in 5 s')), 5000)
        function finish(e) {
          if (over) return
          over = true
          clearTimeout(timer)
          __verdict(i, e)
          res(undefined)
        }
        $DONE = finish
        try { __tests[i].call(globalThis) } catch (e) { finish(e) }
      })
      __restore()
      continue
    }` : ''}
    let error = undefined, threw = false
    try { __tests[i].call(globalThis) } catch (e) { error = e; threw = true }
    if (__negative[i] !== null) {
      if (!threw) console.log('F ' + i + ' expected a ' + __negative[i])
      else if (__name(error) === __negative[i]) console.log('P ' + i)
      else console.log('F ' + i + ' expected a ' + __negative[i] + ', threw ' + __describe(error))
    } else __verdict(i, threw ? error : undefined, threw)
    __restore()
  }
}
__main()
export {}
`
}

function prelude() {
  return `function __name(e) {
  try { return e !== null && typeof e === 'object' && e.constructor ? String(e.constructor.name) : typeof e } catch (_) { return '?' }
}
function __describe(e) {
  try {
    const text = e !== null && typeof e === 'object' ? __name(e) + ': ' + String(e.message) : String(e)
    return text.split('\\n').join(' ').slice(0, 300)
  } catch (_) { return 'an error that does not describe itself' }
}
function __verdict(i, e, threw) {
  if (e === undefined && !threw) console.log('P ' + i)
  else console.log('F ' + i + ' ' + __describe(e))
}
// (the built-ins reachable from the global object, two levels down, with
// their prototypes and the iterators': each one's own properties as they
// were, put back after each test)
const __roots = []
{
  const seen = new Set()
  const add = o => {
    if ((typeof o === 'object' || typeof o === 'function') && o !== null && !seen.has(o)) {
      seen.add(o)
      __roots.push(o)
    }
  }
  add(globalThis)
  for (const k of Reflect.ownKeys(globalThis)) {
    const d = Object.getOwnPropertyDescriptor(globalThis, k)
    if (d === undefined || !('value' in d)) continue
    add(d.value)
    if (typeof d.value === 'function') add(d.value.prototype)
  }
  const arrayIterator = Object.getPrototypeOf([][Symbol.iterator]())
  add(arrayIterator)
  add(Object.getPrototypeOf(arrayIterator))
  add(Object.getPrototypeOf(''[Symbol.iterator]()))
  add(Object.getPrototypeOf(new Map()[Symbol.iterator]()))
  add(Object.getPrototypeOf(new Set()[Symbol.iterator]()))
  add(Object.getPrototypeOf(function* () {}))
  add(Object.getPrototypeOf(function* () {}).prototype)
}
const __saved = __roots.map(o => {
  const ds = new Map()
  for (const k of Reflect.ownKeys(o)) ds.set(k, Object.getOwnPropertyDescriptor(o, k))
  return ds
})
function __same(a, b) {
  return a.configurable === b.configurable && a.enumerable === b.enumerable && a.writable === b.writable
    && Object.is(a.value, b.value) && a.get === b.get && a.set === b.set
}
function __restore() {
  for (let i = 0; i < __roots.length; i++) {
    const o = __roots[i], ds = __saved[i]
    for (const k of Reflect.ownKeys(o)) if (!ds.has(k)) try { delete o[k] } catch (_) {}
    for (const [k, d] of ds) {
      const now = Object.getOwnPropertyDescriptor(o, k)
      if (now === undefined || !__same(now, d)) try { Object.defineProperty(o, k, d) } catch (_) {}
    }
  }
}`
}

// ---- the suite

function checkout() {
  const sparse = ['/harness/', '/LICENSE', ...SCOPE.map(d => `/${d}/`)]
  if (!fs.existsSync(root)) {
    sh('git', ['clone', '-q', '--filter=blob:none', '--no-checkout', 'https://github.com/tc39/test262.git', root])
    sh('git', ['-C', root, 'sparse-checkout', 'set', '--no-cone', ...sparse])
    sh('git', ['-C', root, 'checkout', '-q', REVISION])
  } else if (!sparse.every(p => fs.existsSync(path.join(root, p)))) {
    sh('git', ['-C', root, 'sparse-checkout', 'set', '--no-cone', ...sparse])
  }
  const head = sh('git', ['-C', root, 'rev-parse', 'HEAD']).trim()
  if (head !== REVISION) throw new Error(`${root} is at ${head}, not ${REVISION} (check it out, or move REVISION)`)
}

function collect() {
  const out = []
  for (const dir of SCOPE) for (const file of walk(path.join(root, dir))) {
    if (!file.endsWith('.js') || file.includes('_FIXTURE')) continue
    const source = fs.readFileSync(file, 'utf8')
    const m = meta(source)
    const id = path.relative(root, file)
    out.push({id, source, includes: m.includes, async: m.flags.includes('async'), negative: m.negative?.phase === 'runtime' ? m.negative.type : null,
      skip: skipped(m, source)})
  }
  return out.sort((a, b) => a.id < b.id ? -1 : 1)
}

// (why a test is out of scope, or null)
function skipped(m, source) {
  const flag = m.flags.find(f => FLAGS.has(f))
  if (flag) return `flag ${flag}`
  if (m.flags.includes('module')) return 'module code (a program of its own: not yet)'
  if (m.negative && m.negative.phase !== 'runtime') return `negative, ${m.negative.phase} phase (not yet)`
  const feature = m.features.find(f => FEATURES.has(f) || f.startsWith('Intl') || f.startsWith('Temporal'))
  if (feature) return `feature ${feature}`
  const harness = m.includes.find(i => HARNESS_OUT.has(i))
  if (harness) return `harness ${harness}`
  if (/\$262\./.test(source)) return 'a $262 host hook'
  // (a BigInt literal in a test whose features do not say so)
  if (/(?<![\w.])\d+n\b/.test(source)) return 'a BigInt literal'
  if (/\beval\s*\(|\bFunction\s*\(|\bnew\s+Function\b/.test(source)) return 'eval or Function (helder has neither)'
  if (/\bProxy\b|__proto__|setPrototypeOf/.test(source)) return 'Proxy, __proto__ or setPrototypeOf (excluded by helder)'
  // (helder freezes the built-ins' members: an assignment or a delete of one is TSHX001 by design)
  if (BUILTIN_WRITE.test(source)) return "writes a built-in's member (frozen in helder: TSHX001)"
  return null
}

function meta(source) {
  const y = /\/\*---([\s\S]*?)---\*\//.exec(source)?.[1] ?? ''
  const list = key => {
    const inline = new RegExp(`^${key}:\\s*\\[(.*)\\]`, 'm').exec(y)
    if (inline) return inline[1].split(',').map(s => s.trim()).filter(Boolean)
    const block = new RegExp(`^${key}:[ \\t]*\\n((?:[ \\t]+-.*\\n?)+)`, 'm').exec(y)
    return block ? [...block[1].matchAll(/-\s*(\S+)/g)].map(x => x[1]) : []
  }
  const negative = /^negative:[ \t]*\n((?:[ \t]+.*\n?)+)/m.exec(y)?.[1]
  return {includes: list('includes'), flags: list('flags'), features: list('features'),
    negative: negative ? {phase: /phase:\s*(\w+)/.exec(negative)?.[1], type: /type:\s*(\w+)/.exec(negative)?.[1]} : null}
}

function* walk(dir) {
  for (const e of fs.readdirSync(dir, {withFileTypes: true})) {
    const p = path.join(dir, e.name)
    if (e.isDirectory()) yield* walk(p)
    else yield p
  }
}

// ---- the gate

// pass, or pending (why) in the manifest: a required test that fails and a
// pending one that passes fail the run, until BLESS=1 writes the manifest
function report() {
  const areas = new Map(), clusters = new Map()
  const bad = [], fixed = []
  for (const t of tests) {
    const r = results.get(t.id)
    if (!r) continue
    const area = t.id.split('/').slice(1, 3).join('/')
    const a = areas.get(area) ?? areas.set(area, {pass: 0, judged: 0, wrapper: 0, skipped: 0}).get(area)
    if (r.status === 'skipped') a.skipped++
    else if (r.status === 'wrapper') a.wrapper++
    else {
      a.judged++
      if (r.status === 'pass') a.pass++
      else {
        const key = `${r.status}: ${normalize(r.why)}`
        const c = clusters.get(key) ?? clusters.set(key, {count: 0, example: t.id, why: r.why}).get(key)
        c.count++
      }
    }
    if (r.status === 'skipped' || r.status === 'wrapper') continue
    const want = manifest[t.id]
    if (r.status === 'pass' && want) fixed.push(t.id)
    if (r.status !== 'pass' && !want) bad.push(`${t.id}: ${r.status} ${r.why}`)
  }
  const lines = ['| area | pass | judged | rate | set aside (wrapping) | out of scope |', '| --- | --- | --- | --- | --- | --- |']
  let pass = 0, judged = 0
  for (const [area, a] of [...areas].sort()) {
    pass += a.pass
    judged += a.judged
    lines.push(`| ${area} | ${a.pass} | ${a.judged} | ${a.judged ? (100 * a.pass / a.judged).toFixed(1) : '-'}% | ${a.wrapper} | ${a.skipped} |`)
  }
  lines.push(`| all | ${pass} | ${judged} | ${judged ? (100 * pass / judged).toFixed(1) : '-'}% | | |`)
  const top = [...clusters].sort((a, b) => b[1].count - a[1].count).slice(0, 25)
  const table = lines.join('\n')
  const failures = top.map(([k, c]) => `- ${c.count}× ${k.slice(0, 160)} (${c.example})`).join('\n')
  fs.writeFileSync('bin/test262/report.md', `# test262 at ${REVISION.slice(0, 8)}\n\n${table}\n\n## Failure clusters\n\n${failures}\n`)
  console.log(table + '\n\nfailure clusters (bin/test262/report.md):\n' + top.slice(0, 10).map(([k, c]) => `  ${c.count}× ${k.slice(0, 140)} (${c.example})`).join('\n'))
  if (bless) {
    const next = filters.length ? {...manifest} : {}
    for (const t of tests) {
      const r = results.get(t.id)
      if (r && r.status !== 'pass' && r.status !== 'skipped' && r.status !== 'wrapper') next[t.id] = {pending: `${r.status}: ${r.why}`.slice(0, 200)}
      else if (r && r.status === 'pass') delete next[t.id]
    }
    const entries = Object.keys(next).sort().map(k => `\t\t${JSON.stringify(k)}: ${JSON.stringify(next[k])}`)
    fs.writeFileSync(manifestPath, `{\n\t"schema": 1,\n\t"revision": "${REVISION}",\n\t"cases": {\n${entries.join(',\n')}\n\t}\n}\n`)
    readme(table)
    console.log(`BLESS: ${manifestPath}, ${here}/README.md`)
    return 0
  }
  for (const f of fixed) console.log(`FIXED ${f} (BLESS=1 to require it)`)
  for (const b of bad.slice(0, 50)) console.log(`FAIL ${b}`)
  if (bad.length > 50) console.log(`... ${bad.length - 50} more`)
  return bad.length || fixed.length ? 1 : 0
}

function readme(table) {
  const file = `${here}/README.md`
  const text = fs.readFileSync(file, 'utf8')
  const start = text.indexOf('<!-- counts -->'), end = text.indexOf('<!-- /counts -->')
  if (start < 0 || end < 0) return
  fs.writeFileSync(file, text.slice(0, start) + '<!-- counts -->\n' + table + '\n' + text.slice(end))
}

// (a failure's message without its numbers, names in quotes and ids, to cluster by)
function normalize(why) {
  return String(why ?? '').replace(/«[^»]*»/g, '«…»').replace(/\b\d+(\.\d+)?\b/g, 'N').replace(/(["'`]).*?\1/g, '"…"')
    .replace(/[\w.$\[\]()]+ descriptor should/g, 'X descriptor should').replace(/\s+/g, ' ').slice(0, 120)
}

function firstLine(text) {
  // (a compiler's diagnostic: its code and text, wherever its frame put them)
  const code = /\b(TS(?:HX)?(?:IR)?\d+:.*)$/m.exec(String(text ?? ''))
  if (code) return code[1].trim().slice(0, 300)
  return String(text ?? '').split('\n').map(l => l.trim()).filter(l => l && !l.startsWith('|') && !/^\d+ \|/.test(l))
    .map(l => l.replace(/^\[ERROR\]\s*/, '').replace(/^\S*\.mjs:\d+:( characters \d+-\d+)?\s*:?\s*/, '')).join(' ').slice(0, 300)
}

function sh(cmd, args) {
  const r = spawnSync(cmd, args, {encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit']})
  if (r.status !== 0) throw new Error(`${cmd} ${args.join(' ')} failed`)
  return r.stdout
}
