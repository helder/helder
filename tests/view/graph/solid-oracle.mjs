// Solid 2 as the judge (@solidjs/signals 2.0.4): a case the stores fuzzer
// shrank (src/helder/view/graph/AtomsModel.test.hx), its graph and one
// store's ops run against the real package, each effect's applies printed.
// Solid has no stores: one run is one store, as ours are.
//
//   node tests/view/graph/solid-oracle.mjs <path to @solidjs/signals' dist/prod/index.js>
import {pathToFileURL} from 'node:url'

const S = await import(pathToFileURL(process.argv[2]).href)
const {createSignal, createMemo, createEffect, createRenderEffect, createRoot, flush} = S

// the case: 3 signals (0, 1, 2), then memos by index (node 3 on), effects
const memos = [['Sum', 0, 0], ['Async', 0], ['Sum', 0, 0], ['Sum', 0, 2], ['Sum', 0, 4], ['Gate', 0, 0, 0], ['Derived', 2], ['Inner', 0],
  ['Derived', 9], ['Inner', 0], ['Inner', 0], ['Cond', 11, 4, 0, 0], ['Inner', 0], ['Inner', 0], ['Sum', 0, 4], ['Derived', 0], ['Inner', 0],
  ['Inner', 0], ['Inner', 0], ['Sum', 0, 0], ['Inner', 0], ['Inner', 0], ['Cond', 0, 9, 14, 0], ['Sum', 0, 0], ['Inner', 0], ['Inner', 0]]
const effects = [{node: 0, render: false}, {node: 25, render: true}, {node: 0, render: false}, {node: 0, render: false}, {node: 6, render: true},
  {node: 0, render: false}]

const log = []
let round = 0
const nodes = [], writers = {}
createRoot(() => {
  for (const k of [0, 1, 2]) {
    const [get, set] = createSignal(k % 5)
    nodes.push(get)
    writers[k] = set
  }
  for (const [i, m] of memos.entries()) {
    const n = nodes, at = 3 + i
    switch (m[0]) {
      case 'Sum': nodes.push(createMemo(() => n[m[1]]() + n[m[2]]())); break
      case 'Cond': nodes.push(createMemo(() => n[m[1]]() % 2 === 0 ? n[m[2]]() : n[m[3]]() + m[4])); break
      case 'Gate': nodes.push(createMemo(() => n[m[1]]() > m[3] ? n[m[2]]() * 2 : m[3])); break
      case 'Inner': nodes.push(createMemo(() => createMemo(() => n[m[1]]() + 1)() * 2)); break
      // (an ask nobody answers: the store's case answers only another store's)
      case 'Async': nodes.push(createMemo(() => (n[m[1]](), new Promise(() => {})))); break
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
    const apply = v => log.push(`${String(round).padStart(4, '0')} e${k}: ${v}`)
    if (e.render) createRenderEffect(() => n(), apply)
    else createEffect(() => n(), apply)
  }
})

function step(what, f) {
  round++
  f?.()
  flush()
  console.log(what.padEnd(16), JSON.stringify(log.splice(0)))
}
step('made')
step('s0 = 1', () => writers[0](1))
step('s2 = 0', () => writers[2](0))
step('node 9 = 0', () => writers[9](0))
step('flush')
