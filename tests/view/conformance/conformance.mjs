// reactive-framework-test-suite (MIT, github.com/johnsoncodehk/reactive-framework-test-suite)
// against helder.view's graph (Framework.hx built to JavaScript), as atly's
// conformance.test.ts runs it: plain, and through a store (every read, write
// and computation in a fresh store, the nodes at home in the default one).
// A store's answer differing from plain's is a failure, and so is a case
// helder fails that GAPS does not name. Given Solid 2's build (its
// dist/prod/index.js, as solid-oracle.mjs takes), Solid's answers are shown
// beside helder's: a case both fail is Solid 2's semantics, not a bug (its
// dev build, dist/dev.js, which refuses what helder's graph refuses; each
// case in a process of its own: an error halts Solid's scheduler for good).
//
//   node tests/view/conformance/conformance.mjs <framework.js> [solid dev.js]
import {createRequire} from 'node:module'
import {pathToFileURL, fileURLToPath} from 'node:url'
import {spawnSync} from 'node:child_process'
import path from 'node:path'
import * as suite from 'reactive-framework-test-suite'

const [built, solidPath, only] = process.argv.slice(2)
const sections = [...suite.correctness.map(s => [s, false]), [suite.behaviors, true]]

// (one case on Solid 2, its result printed: a child's)
if (only) {
  const [name, id] = only.split('#')
  const [section, probe] = sections.find(([s]) => s.name === name)
  const fw = solid(await import(pathToFileURL(path.resolve(solidPath)).href))
  const c = section.cases.find(c => String(c.id) === id)
  console.log(JSON.stringify(probe ? suite.runProbe(fw, c) : suite.runCase(fw, c)))
  process.exit(0)
}

const graph = createRequire(import.meta.url)(path.resolve(built)).helderGraph

// the cases helder fails by design, as Solid 2.0.4 does (its dev build fails
// each, 30 with helder's message; #237 and #243 its own count), each with
// why: "section#id"
const CLOCK = "Solid 2's: a memo nothing observes, read outside a computation, is fresh by the write clock: after any write it computes again on its next read (its inputs pulled as it reads them), whether or not they changed"
const OWNED = "Solid 2's: a write inside a computation (here an effect's compute, the suite's effect body) is refused: writes go in an effect's apply or an event (or a signal made with ownedWrite)"
const SPLIT = "Solid 2's split effects: the body is the compute, its cleanup the apply's: the compute runs again before the last run's cleanup, an error in it skips the apply (its cleanup with it), and a cleanup run during a computation is read by it"
const DEFER = "Solid 2's deferred writes: a write is committed at the flush (a batch's end here); until then reads, a computed's too, see the committed value"
const GAPS = Object.fromEntries([
  [CLOCK, ['Graph Propagation#7', 'Dynamic Dependencies#12', 'Dynamic Dependencies#13', 'Computed Evaluation#27', 'Equality & Same-Value Optimization#34',
    'Equality & Same-Value Optimization#220', 'Untracked / Unsampled Reads#76', 'Stale Evaluation Order#95']],
  [OWNED, ['Dynamic Dependencies#200', 'Nested Effects & Ordering#47', 'Inner Write#50', 'Inner Write#54', 'Inner Write#114', 'Inner Write#133', 'Inner Write#134',
    'Inner Write#180', 'Inner Write#212', 'Inner Write#213', 'Inner Write#224', 'Inner Write#225', 'Batching / Transaction#130', 'Untracked / Unsampled Reads#156',
    'Effect Lifecycle#235', 'Behavioral Differences#49']],
  [SPLIT, ['Effect Lifecycle#38', 'Effect Lifecycle#178', 'Effect Lifecycle#237', 'Effect Lifecycle#243', 'Error Handling#89']],
  [DEFER, ['Effect Lifecycle#233', 'Batching / Transaction#67', 'Batching / Transaction#128']]
].flatMap(([why, keys]) => keys.map(k => [k, why])))

function helder(mode) {
  return {
    name: `helder (${mode})`,
    begin: () => graph.begin(mode),
    home: () => graph.home(),
    end: () => graph.end(),
    signal: v => graph.signal(v),
    computed: fn => graph.computed(fn),
    effect: fn => graph.effect(fn),
    run: fn => fn(),
    batch: fn => graph.batch(fn),
    untracked: fn => graph.untracked(fn),
    effectCleanup: true
  }
}

// (Solid 2 through the same shape: writes flushed outside a batch, an effect's
// function its compute, its cleanup given back by its apply)
function solid(s) {
  let depth = 0
  const settle = () => { if (depth === 0) s.flush() }
  return {
    name: 'solid 2',
    begin() {}, end() { depth = 0 },
    signal(v) {
      const [read, write] = s.createSignal(v)
      return {read, write: x => { write(() => x); settle() }}
    },
    computed: fn => ({read: s.createMemo(() => fn())}),
    effect(fn) {
      const dispose = s.createRoot(d => {
        s.createEffect(() => fn(), c => typeof c === 'function' ? c : undefined)
        return d
      })
      settle()
      return () => { dispose(); settle() }
    },
    run: fn => fn(),
    batch(fn) {
      depth++
      try { fn() } finally { depth--; settle() }
    },
    untracked: fn => s.untrack(fn),
    effectCleanup: true
  }
}

const fws = [helder('plain'), helder('home'), helder('foreign')]
if (solidPath) fws.push({name: 'solid 2', apart: true})

function run(fw, c, probe, key) {
  if (fw.apart) {
    const r = spawnSync(process.execPath, [fileURLToPath(import.meta.url), built, solidPath, key], {encoding: 'utf8'})
    const last = r.stdout.trim().split('\n').pop()
    try { return JSON.parse(last) } catch { return {status: 'fail', error: `the process ended: ${r.stderr.trim().split('\n').pop()}`} }
  }
  fw.begin()
  try {
    const r = probe ? suite.runProbe(fw, c) : suite.runCase(fw, c)
    return fw.home ? {...r, home: fw.home()} : r
  } finally {
    fw.end()
  }
}

// (foreign: a count over by no more than the computations its default
// store ran, each memo once as it was made, as at a program's start; the
// value the same: tests/view/graph/Stores.hx's counted)
function made(plain, foreign) {
  const m = foreign.status === 'fail' && /^Expected (\d+) but got (\d+)$/.exec(foreign.error)
  return plain.status !== 'fail' && m && +m[2] > +m[1] && +m[2] - +m[1] <= foreign.home
}

const said = r => r.status === 'fail' ? `fail: ${r.error}` : r.status === 'variant' ? r.variant : r.status === 'skip' ? `skip: ${r.reason}` : r.status
let pass = 0, failed = 0, gaps = 0, total = 0, counts = 0
for (const [section, probe] of sections)
  for (const c of section.cases) {
    total++
    const key = `${section.name}#${c.id}`
    const rs = fws.map(fw => run(fw, c, probe, key))
    const [plain, home, foreign] = rs
    const counted = made(plain, foreign)
    if (counted) counts++
    const bad = plain.status === 'fail' || home.status === 'fail' || foreign.status === 'fail' && !counted
    const apart = said(plain) !== said(home) || said(plain) !== said(foreign) && !counted
    if (!bad && !apart) {
      pass++
      if (probe) console.log(`${key} ${c.title}: ${said(plain)}${rs[3] ? ` (solid 2: ${said(rs[3])})` : ''}`)
      continue
    }
    const line = `${key} ${c.title}\n${fws.map((fw, i) => `    ${fw.name}: ${said(rs[i])}`).join('\n')}`
    if (!apart && GAPS[key]) {
      gaps++
      console.log(`GAP ${key} ${c.title}`)
    } else {
      failed++
      console.log(`FAIL ${line}${apart ? '\n    the store differs from plain' : ''}`)
    }
  }
for (const key of Object.keys(GAPS))
  if (![...suite.correctness, suite.behaviors].some(s => s.cases.some(c => `${s.name}#${c.id}` === key))) console.log(`GAPS names no case: ${key}`)
console.log(`the gaps: Solid 2's semantics\n${[...new Set(Object.values(GAPS))].map(w => `  - ${w}`).join('\n')}`)
console.log(`conformance: ${total} cases, ${pass} pass (${counts} of them foreign over by its default store's computations), ${gaps} known gaps, ${failed} fail`)
process.exit(failed > 0 ? 1 : 0)
