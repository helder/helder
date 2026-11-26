import fs from 'node:fs'
import path from 'node:path'
import {spawnSync} from 'node:child_process'
import {emit, size} from './Program.mjs'

// A finding reduced to a small program: the failing case alone (or with the
// cases before it it needs), then its tree edited (statements dropped,
// blocks unwrapped, expressions made literals or their own parts), each
// edit kept while the case still fails the same way. Cases are independent,
// so a round's candidates are one program's cases, each under its own id;
// those tsgo refuses are left out first (tsc, a fraction of a build).
const BATCH = 24

export class Shrinker {
  constructor(runner, {wasm = false, log = () => {}, rounds = 80, seconds = 600} = {}) {
    this.runner = runner
    this.wasm = wasm
    this.log = log
    this.rounds = rounds
    this.seconds = seconds
    this.builds = 0
  }

  // failing: the case that fails, or null when the program does as a whole
  // (a compiler's error at no line): its cases halved first, then each
  async shrink(cases, failing, kind) {
    const t0 = Date.now()
    this.kind = kind
    this.signature = null
    // (one at a time where a failure names no case: a batch could not say whose)
    this.batch = failing ? BATCH : 1
    const holds = async set => {
      const verdicts = await this.verdicts(set)
      return failing ? this.fails(verdicts, failing) : set.some(c => this.fails(verdicts, c))
    }
    if (!await holds(cases)) {
      this.log('does not fail again: kept whole')
      return {cases, kind, whole: true, flaky: true}
    }
    let context = failing ? [failing] : cases
    if (!failing || !await holds(context)) {
      // (it needs some of the cases before it: those halved away while it fails)
      context = failing ? cases.slice(0, cases.indexOf(failing) + 1) : [...cases]
      for (let chunk = Math.ceil(context.length / 2); chunk >= 1; chunk = Math.floor(chunk / 2)) {
        for (let i = 0; i < context.length && context.length > 1;) {
          const trial = [...context.slice(0, i), ...context.slice(i + chunk)]
          if (trial.length && (!failing || trial.includes(failing)) && await holds(trial)) context = trial
          else i += chunk
        }
      }
      this.log(`${context.length} cases of ${cases.length} needed`)
    }
    for (const start of failing ? [failing] : [...context]) {
      let current = start
      for (let round = 0; round < this.rounds && (Date.now() - t0) / 1000 < this.seconds; round++) {
        const candidates = edits(current).map(edit => edit(current)).filter(Boolean)
          .sort((a, b) => size(a) - size(b)).filter(c => size(c) < size(current))
        let better = null
        for (let k = 0; k < candidates.length && !better; k += this.batch) {
          better = await this.best(context.filter(c => c !== current), candidates.slice(k, k + this.batch))
          if ((Date.now() - t0) / 1000 > this.seconds) break
        }
        if (!better) break
        const at = context.indexOf(current)
        context = context.map((c, i) => i === at ? better : c)
        current = better
      }
    }
    const small = context.map((c, i) => ({...c, id: i}))
    // (checked again as it is written: what is kept is what fails)
    if (!await (failing ? this.verdicts(small).then(v => this.fails(v, small[small.length - 1])) : holds(small))) {
      this.log('the shrunk program does not fail: kept whole')
      return {cases, kind, whole: true}
    }
    this.log(`shrunk to ${size(small[small.length - 1])} nodes in ${this.builds} builds, ${Math.round((Date.now() - t0) / 1000)} s`)
    return {cases: small, kind: this.kind}
  }

  // the smallest candidate that still fails (each with the others' context)
  async best(context, candidates) {
    const base = 1000
    let batch = candidates.map((c, i) => ({...c, id: base + i}))
    batch = this.typed([...context, ...batch]).filter(c => c.id >= base)
    while (batch.length) {
      const verdicts = await this.verdicts([...context, ...batch])
      const failing = this.batch === 1 ? (batch.length && [...context, ...batch].some(c => this.fails(verdicts, c)) ? batch[0] : null)
        : batch.find(c => this.fails(verdicts, c))
      if (failing) return candidates[failing.id - base]
      // (those a crash before them left unrun: again without the ones judged)
      batch = batch.filter(c => verdicts.get(c.id) === 'unreached')
    }
    return null
  }

  async verdicts(cases) {
    this.builds++
    const result = await this.runner.run(cases, `shrink-${process.pid}`, {wasm: this.wasm})
    for (const f of [result.file, result.exe, result.exe + '.wasm']) fs.rmSync(f, {force: true})
    this.message = result.messages ? normalize(result.messages) : null
    return result.verdicts
  }

  fails(verdicts, c) {
    const v = verdicts.get(c.id)
    if (v !== this.kind) return false
    if (v.endsWith('compile')) {
      if (this.signature == null) this.signature = this.message
      return this.message === this.signature
    }
    return true
  }

  // the cases tsgo accepts (tsc on the program: those at an error's line left out)
  typed(cases) {
    const {text, ranges} = emit(cases)
    const file = path.join(this.runner.dir, `typed-${process.pid}.ts`)
    fs.writeFileSync(file, text)
    const r = spawnSync(process.execPath, ['node_modules/typescript/bin/tsc', '--noEmit', '--strict', '--target', 'esnext',
      '--module', 'esnext', '--moduleResolution', 'bundler', '--lib', 'esnext', '--types', '', '--skipLibCheck',
      'src/helder/typescript/globals.d.ts', file], {encoding: 'utf8'})
    fs.rmSync(file, {force: true})
    const lines = [...r.stdout.matchAll(/\.ts\((\d+),\d+\): error/g)].map(m => Number(m[1]))
    return cases.filter(c => !ranges.get(c.id).some(([a, b]) => lines.some(l => l >= a && l <= b)))
  }
}

// (a compiler's message without its places and names, to tell one bug from another)
function normalize(messages) {
  return messages.split('\n')[0].replace(/\S*\.ts:\d+:( characters \d+-\d+ :)?/g, '').replace(/c\d+_/g, '').replace(/\d+/g, 'N').trim()
}

// every edit of a case: a function of the case to a smaller one (null: none)
function edits(c) {
  const out = []
  const lists = []
  const walk = (node, path) => {
    if (typeof node === 'string' || node == null) return
    if (node.block) {
      lists.push([...path, 'block'])
      node.block.forEach((st, i) => walk(st, [...path, 'block', i]))
      return
    }
    node.parts?.forEach((p, i) => {
      if (typeof p !== 'string') {
        if (p.t) exprs.push([...path, 'parts', i])
        walk(p, [...path, 'parts', i])
      }
    })
  }
  const exprs = []
  for (const key of ['top', 'body']) {
    lists.push([key])
    c[key].forEach((st, i) => walk(st, [key, i]))
  }
  for (const list of lists) {
    const items = get(c, list)
    items.forEach((st, i) => {
      out.push(x => update(x, list, items => items.filter((_, k) => k !== i)))
      const blocks = (st.parts ?? []).filter(p => p?.block)
      if (blocks.length === 1) out.push(x => update(x, list, items => [...items.slice(0, i), ...blocks[0].block, ...items.slice(i + 1)]))
    })
  }
  for (const at of exprs) {
    const node = get(c, at)
    for (const simpler of SIMPLEST[node.t] ?? [])
      if (!(node.lit && node.parts[0] === simpler)) out.push(x => update(x, at, () => ({t: node.t, parts: [simpler], lit: true})))
    for (const p of node.parts)
      if (typeof p !== 'string' && p.t && (p.t === node.t || node.t === 'unknown')) out.push(x => update(x, at, () => p))
  }
  return out
}

const SIMPLEST = {
  number: ['0', '1'],
  string: ["''", "'a'"],
  boolean: ['true', 'false'],
  'number[]': ['[1, 2]'],
  'string[]': ["['a']"],
  unknown: ['0']
}

function get(node, path) {
  return path.reduce((n, k) => n[k], node)
}

// a copy with the value at path replaced by f of it
function update(node, path, f) {
  if (!path.length) return f(node)
  const [k, ...rest] = path
  const copy = Array.isArray(node) ? [...node] : {...node}
  copy[k] = update(node[k], rest, f)
  return copy
}
