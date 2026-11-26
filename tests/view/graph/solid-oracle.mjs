// Solid 2 as the judge (@solidjs/signals 2.0.4): cases the stores fuzzer
// shrank (src/helder/view/graph/AtomsModel.test.hx), their graph and one
// store's ops run against the real package, each effect's applies printed.
// Solid has no stores: one run is one store, as ours are.
//
//   node tests/view/graph/solid-oracle.mjs <@solidjs/signals' dist/prod/index.js>
import {pathToFileURL} from 'node:url'

const S = await import(pathToFileURL(process.argv[2]).href)
const {createSignal, createMemo, createEffect, createRenderEffect, createRoot, flush} = S

// a graph: signals by their first values, memos by index after them, effects
function build(signals, memos, effects) {
  const nodes = [], writers = {}, asks = [], log = []
  let round = 0
  createRoot(() => {
    for (const [k, v] of signals.entries()) {
      const [get, set] = createSignal(v)
      nodes.push(get)
      writers[k] = set
    }
    for (const [i, m] of memos.entries()) {
      const n = nodes, at = signals.length + i
      switch (m[0]) {
        case 'Sum': nodes.push(createMemo(() => n[m[1]]() + n[m[2]]())); break
        case 'Cond': nodes.push(createMemo(() => n[m[1]]() % 2 === 0 ? n[m[2]]() : n[m[3]]() + m[4])); break
        case 'Gate': nodes.push(createMemo(() => n[m[1]]() > m[3] ? n[m[2]]() * 2 : m[3])); break
        case 'Inner': nodes.push(createMemo(() => createMemo(() => n[m[1]]() + 1)() * 2)); break
        // (each run asks: its answer given by the ops, or never)
        case 'Async': nodes.push(createMemo(() => {
          const of = n[m[1]]()
          return new Promise((resolve, reject) => asks.push({of, resolve, reject}))
        })); break
        case 'Derived': {
          const [get, set] = createSignal(() => n[m[1]]() + 1)
          nodes.push(get)
          writers[at] = set
          break
        }
      }
    }
    for (const [k, e] of effects.entries()) {
      const n = nodes[e.node]
      const apply = v => { log.push(`e${k}: ${v}`) }
      // (helder's effects take an error handler, Solid's render effects none:
      // the error shown as their value, what is not ready still thrown)
      const shown = () => {
        try {
          return n()
        } catch (x) {
          if (x instanceof S.NotReadyError) throw x
          return `error ${x?.message ?? x}`
        }
      }
      if (e.render) createRenderEffect(shown, apply)
      else createEffect(shown, apply)
    }
  })
  return {writers, asks, log}
}

// (an answer lands at a microtask: flushed after it)
const settle = () => new Promise(r => setTimeout(r, 0))

async function run(name, g, ops) {
  console.log(name)
  for (const [what, f] of ops) {
    f?.(g)
    await settle()
    flush()
    console.log('  ' + what.padEnd(24), JSON.stringify(g.log.splice(0)))
  }
}

// 1. a held change released when its render effect stopped reading the answer it waited on
const memos1 = [['Sum', 0, 0], ['Async', 0], ['Sum', 0, 0], ['Sum', 0, 2], ['Sum', 0, 4], ['Gate', 0, 0, 0], ['Derived', 2], ['Inner', 0],
  ['Derived', 9], ['Inner', 0], ['Inner', 0], ['Cond', 11, 4, 0, 0], ['Inner', 0], ['Inner', 0], ['Sum', 0, 4], ['Derived', 0], ['Inner', 0],
  ['Inner', 0], ['Inner', 0], ['Sum', 0, 0], ['Inner', 0], ['Inner', 0], ['Cond', 0, 9, 14, 0], ['Sum', 0, 0], ['Inner', 0], ['Inner', 0]]
const effects1 = [{node: 0}, {node: 25, render: true}, {node: 0}, {node: 0}, {node: 6, render: true}, {node: 0}]
await run('1. held, then its reader moves off the answer', build([0, 1, 2], memos1, effects1), [
  ['made'], ['s0 = 1', g => g.writers[0](1)], ['s2 = 0', g => g.writers[2](0)], ['node 9 = 0', g => g.writers[9](0)]])

// 2. held, its answer fails, then the reader moves off it
const memos2 = [['Async', 0], ['Sum', 0, 0], ['Sum', 0, 0], ['Inner', 0], ['Inner', 0], ['Inner', 0], ['Cond', 0, 0, 1, 0], ['Sum', 0, 0],
  ['Inner', 0], ['Inner', 0], ['Inner', 0], ['Inner', 7], ['Sum', 0, 0], ['Inner', 0], ['Inner', 0], ['Sum', 0, 0], ['Sum', 0, 0],
  ...Array(15).fill(['Inner', 0]), ['Inner', 1]]
await run('2. held, its answer fails, then the reader moves off it', build([0], memos2, [{node: 12, render: true}]), [
  ['made'], ['s0 = 1', g => g.writers[0](1)],
  ['the open ask fails', g => g.asks.find(a => !a.done && (a.done = true)).reject(new Error('e0'))],
  ['s0 = 2', g => g.writers[0](2)]])
